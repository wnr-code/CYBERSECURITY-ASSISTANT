#!/usr/bin/env python3
"""Install and cold-launch the app on an Android Emulator, capturing proof and logs."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Sequence

from process_utils import run_bounded

PACKAGE = "org.cybersecurityassistant.cybersecurity_assistant"
CAPTURE_TIMES_MS = (80, 180, 350, 650, 1_000, 1_800, 3_500, 6_500, 8_500)
MAX_CAPTURE_BYTES = 32 * 1024 * 1024
MAX_LOGCAT_BYTES = 2 * 1024 * 1024
_DEADLINE = 0.0


def _remaining_timeout(timeout: float) -> float:
    remaining = _DEADLINE - time.monotonic()
    if remaining <= 0:
        raise TimeoutError("Cold-start test exceeded its overall time limit.")
    return min(timeout, remaining)


def adb(arguments: Sequence[str], *, timeout: int = 45) -> subprocess.CompletedProcess:
    command = ["adb", *arguments]
    effective_timeout = _remaining_timeout(timeout)
    try:
        return run_bounded(command, check=True, capture_output=True, timeout=effective_timeout)
    except subprocess.TimeoutExpired as error:
        raise TimeoutError(
            f"ADB command timed out after {effective_timeout:.1f}s: {' '.join(command)}"
        ) from error
    except subprocess.CalledProcessError as error:
        detail = error.stderr.decode("utf-8", errors="replace") if isinstance(error.stderr, bytes) else str(error.stderr or "")
        raise RuntimeError(f"ADB command failed ({error.returncode}): {' '.join(command)}; {detail[-1500:]}") from error


def output(arguments: Sequence[str], *, timeout: int = 45) -> str:
    return adb(arguments, timeout=timeout).stdout.decode("utf-8", errors="replace").strip()


def _redact(text: str) -> str:
    text = re.sub(r"(?i)(bearer\s+)[A-Za-z0-9._~+/=-]+", r"\1[redacted]", text)
    text = re.sub(r"(?i)(token|api[_-]?key|password|secret)(\s*[:=]\s*)[^\s,;]+", r"\1\2[redacted]", text)
    return re.sub(r"https?://\S+", "[url]", text)


def _startup_markers(logcat: str) -> list[dict[str, object]]:
    markers: list[dict[str, object]] = []
    for line in logcat.splitlines():
        flutter = re.search(r"\[APP_STARTUP\]\s+([\w-]+)\s+\+(\d+)ms", line)
        native = re.search(r"AppStartup[^\n]*?(native:[\w-]+)", line)
        if flutter:
            markers.append({"source": "flutter", "event": flutter.group(1), "elapsed_ms": int(flutter.group(2)), "line": line})
        elif native:
            markers.append({"source": "android", "event": native.group(1), "line": line})
    return markers


def run(apk: Path, output_dir: Path, api_level: int, *, overall_timeout: int = 720) -> dict[str, object]:
    global _DEADLINE
    output_dir.mkdir(parents=True, exist_ok=True)
    _DEADLINE = time.monotonic() + overall_timeout
    apk = apk.resolve()
    if not apk.is_file():
        raise RuntimeError(f"APK not found: {apk}")
    _ = output(["get-state"], timeout=30)

    install = adb(["install", "-r", str(apk)], timeout=180)
    clear = adb(["shell", "pm", "clear", PACKAGE], timeout=60)
    adb(["shell", "input", "keyevent", "KEYCODE_HOME"])
    adb(["shell", "am", "force-stop", PACKAGE])
    adb(["logcat", "-c"])

    device = {
        "api_level": output(["shell", "getprop", "ro.build.version.sdk"]),
        "android_release": output(["shell", "getprop", "ro.build.version.release"]),
        "model": output(["shell", "getprop", "ro.product.model"]),
        "emulator": output(["shell", "getprop", "ro.kernel.qemu"]),
    }
    if str(device["api_level"]) != str(api_level):
        raise RuntimeError(f"Expected emulator API {api_level}, got {device['api_level']}")

    launch_started = time.monotonic()
    launcher = adb(
        ["shell", "monkey", "-p", PACKAGE, "-c", "android.intent.category.LAUNCHER", "1"],
        timeout=20,
    )
    launcher_output = launcher.stdout.decode("utf-8", errors="replace")
    if launcher.returncode != 0:
        raise RuntimeError(f"Android launcher command failed: {launcher_output[-1500:]}")

    screenshots: list[dict[str, object]] = []
    for requested_ms in CAPTURE_TIMES_MS:
        remaining = _remaining_timeout(overall_timeout)
        delay = requested_ms / 1000 - (time.monotonic() - launch_started)
        if delay > 0:
            time.sleep(min(delay, remaining))
        capture_started = time.monotonic()
        frame = adb(["exec-out", "screencap", "-p"], timeout=40).stdout
        if len(frame) > MAX_CAPTURE_BYTES:
            raise RuntimeError(f"Screenshot exceeded the {MAX_CAPTURE_BYTES}-byte safety limit.")
        actual_ms = int((time.monotonic() - launch_started) * 1000)
        filename = f"cold-start-{actual_ms:05d}ms.png"
        (output_dir / filename).write_bytes(frame)
        screenshots.append({"requested_ms": requested_ms, "actual_ms": actual_ms, "file": filename,
                            "capture_duration_ms": int((time.monotonic() - capture_started) * 1000),
                            "png_bytes": len(frame)})

    logcat = output(["logcat", "-d", "-v", "epoch"], timeout=60)
    logcat = _redact(logcat)
    if len(logcat.encode("utf-8")) > MAX_LOGCAT_BYTES:
        logcat = "[logcat truncated to the last 2 MiB]\n" + logcat[-MAX_LOGCAT_BYTES:]
    (output_dir / "cold-start-logcat.txt").write_text(logcat + "\n", encoding="utf-8")
    markers = _startup_markers(logcat)
    events = [str(marker["event"]) for marker in markers]
    required = (
        "native:activity-onCreate",
        "native:splash-installed",
        "dart-main",
        "animated-splash-first-frame",
        "dashboard-first-frame",
    )
    missing = [event for event in required if event not in events]
    report: dict[str, object] = {
        "package": PACKAGE,
        "device": device,
        "cold_start": not missing,
        "launch_method": "force-stop then monkey MAIN/LAUNCHER tap",
        "apk": apk.name,
        "install_output": install.stdout.decode("utf-8", errors="replace").strip(),
        "clear_data_output": clear.stdout.decode("utf-8", errors="replace").strip(),
        "screenshots": screenshots,
        "startup_markers": markers,
        "missing_required_markers": missing,
        "screenshot_notes": "Inspect the first frames in timestamp order to identify native splash, Flutter splash, and dashboard.",
    }
    (output_dir / "cold-start-report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    if missing:
        raise RuntimeError(f"Cold-start log is missing expected stage markers: {', '.join(missing)}. Captures and logcat were saved to {output_dir}.")
    print(json.dumps({"api_level": api_level, "screenshots": len(screenshots), "markers": events}, indent=2))
    return report


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--api-level", type=int, required=True)
    parser.add_argument("--overall-timeout-seconds", type=int, default=720)
    args = parser.parse_args(argv)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    try:
        run(args.apk, args.output_dir, args.api_level, overall_timeout=args.overall_timeout_seconds)
    except (OSError, RuntimeError, TimeoutError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        detail = _redact(f"Android cold-start test failed for API {args.api_level}: {type(error).__name__}: {error}")
        (args.output_dir / "failure-diagnostics.txt").write_text(detail + "\n", encoding="utf-8")
        print(detail, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
