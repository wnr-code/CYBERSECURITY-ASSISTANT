#!/usr/bin/env python3
"""Run the debug APK build and publish useful bounded failure diagnostics."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import time
import traceback
from pathlib import Path

from local_ai_artifact_gate import (
    GateError,
    audit_apk_cpu_only,
    audit_source_build_config,
    audit_source_native_apk,
    preflight_runtime_build,
)
from process_utils import run_bounded

MAX_ANNOTATION_CHARS = 1800
MAX_FAILURE_CHARS = 7200
MAX_TRANSIENT_BUILD_RETRIES = 4
TRANSIENT_HTTP_FAILURE = re.compile(r"(?i)(?:status code 429|too many requests|status code 5[0-9]{2})")


def _escape_command_value(value: str) -> str:
    return value.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def flutter_build_command(*, native_enabled: bool) -> list[str]:
    command = ["flutter", "build", "apk", "--debug"]
    if native_enabled:
        # The source-native CMake target deliberately rejects every ABI except
        # arm64-v8a. Flutter otherwise requests armeabi-v7a and x86_64 too.
        command.extend(["--target-platform", "android-arm64"])
    return command


def _redact_diagnostics(output: str) -> str:
    output = re.sub(r"(?i)(bearer\s+)[A-Za-z0-9._~+/=-]+", r"\1[redacted]", output)
    output = re.sub(r"(?i)(token|api[_-]?key|password|secret)(\s*[:=]\s*)[^\s,;]+", r"\1\2[redacted]", output)
    return re.sub(r"https?://\S+", "[url]", output)


def _write_native_diagnostics(app_root: Path, stage: str, output: str) -> None:
    """Persist bounded, redacted source-native failure evidence for CI artifacts."""
    if os.environ.get("LOCAL_AI_NATIVE_BUILD", "").strip() != "1":
        return
    output = _redact_diagnostics(output)[-100_000:]
    path = app_root / "build" / "local-ai-native-diagnostics.txt"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(f"Stage: {stage}\n\n{output}\n", encoding="utf-8")


def failure_annotations(exit_code: int, output: str) -> list[str]:
    prefix = f"flutter build apk --debug failed (exit {exit_code}).\n\n"
    output_budget = MAX_FAILURE_CHARS - len(prefix)
    if len(output) > output_budget:
        diagnostic_lines = [
            line for line in output.splitlines()
            if re.search(r"(?i)(cmake error|fatal error:|\berror:|undefined reference|ninja: build stopped)", line)
        ]
        diagnostic_summary = "\n".join(diagnostic_lines[-12:])[-1600:]
        tail_budget = output_budget - len(diagnostic_summary) - 96
        output = (
            (f"Relevant compiler/build diagnostics:\n{diagnostic_summary}\n\n" if diagnostic_summary else "")
            + "… build output truncated; showing tail …\n"
            + output[-max(0, tail_budget):]
        )
    message = prefix + output
    return [message[start : start + MAX_ANNOTATION_CHARS] for start in range(0, len(message), MAX_ANNOTATION_CHARS)]


def _audit_source_cmake_caches(android_root: Path, expected_commit: str) -> list[dict[str, object]]:
    app_root = android_root / "app"
    caches = sorted(app_root.rglob("CMakeCache.txt"))
    reports = []
    for cache_path in caches:
        try:
            cache_text = cache_path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        if "LLAMA_CPP_SOURCE_DIR" not in cache_text:
            continue
        reports.append(audit_source_build_config(cache_path, expected_commit))
    if not reports:
        raise GateError("Gradle produced no CMakeCache for the pinned llama.cpp Android native target.")
    return reports


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--phase", choices=("all", "build", "audit"), default="all")
    args = parser.parse_args(argv)

    app_root = Path(__file__).resolve().parents[1]
    native_enabled = os.environ.get("LOCAL_AI_NATIVE_BUILD", "").strip() == "1"
    if args.phase == "audit" and not native_enabled:
        print("The audit phase requires LOCAL_AI_NATIVE_BUILD=1.", file=sys.stderr)
        return 2

    setup_stage = "runtime dependency preflight"
    source_commit = ""
    runtime_included = False
    if args.phase != "audit":
        try:
            if native_enabled:
                from configure_android import configure_project
                from prepare_llama_cpp_source import SOURCE_COMMIT, prepare_source

                source_commit = SOURCE_COMMIT
                setup_stage = "fetch and verify pinned llama.cpp source"
                prepare_source(app_root)
                setup_stage = "configure Android/JNI native target"
                configure_project(app_root / "android", local_ai_native=True)
            setup_stage = "runtime dependency preflight"
            runtime_included = preflight_runtime_build(app_root / "pubspec.yaml")
        except GateError as error:
            message = f"Local AI runtime build gate blocked: {error}"
            _write_native_diagnostics(app_root, setup_stage, message)
            print(message, file=sys.stderr)
            if os.environ.get("GITHUB_ACTIONS"):
                print(f"::error title=Local AI artifact gate::{_escape_command_value(message)}")
            return 2
        except Exception as error:
            message = f"Android build setup failed during {setup_stage}: {type(error).__name__}: {error}"
            _write_native_diagnostics(app_root, setup_stage, message)
            print(message, file=sys.stderr)
            if os.environ.get("GITHUB_ACTIONS"):
                print(f"::error title=Android build setup::{_escape_command_value(message)}")
                summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
                if summary_path:
                    with open(summary_path, "a", encoding="utf-8") as summary:
                        summary.write(f"### Android build setup failed during {setup_stage}\n\n```text\n{type(error).__name__}: {error}\n```\n")
            return 2

        build_command = flutter_build_command(native_enabled=native_enabled)
        timeout_seconds = int(os.environ.get(
            "FLUTTER_BUILD_PROCESS_TIMEOUT_SECONDS",
            "2100" if native_enabled else "1500",
        ))
        total_timeout_seconds = int(os.environ.get(
            "FLUTTER_BUILD_TOTAL_TIMEOUT_SECONDS",
            "2100" if native_enabled else "1500",
        ))
        build_deadline = time.monotonic() + total_timeout_seconds
        print(f"Running Flutter build command (per-attempt cap {timeout_seconds}s, total cap {total_timeout_seconds}s): {' '.join(build_command)}")
        for retry in range(MAX_TRANSIENT_BUILD_RETRIES + 1):
            attempt_timeout = min(timeout_seconds, max(0.0, build_deadline - time.monotonic()))
            if attempt_timeout <= 0:
                message = f"Flutter build exhausted its total {total_timeout_seconds}s retry budget; all build process groups have been terminated."
                _write_native_diagnostics(app_root, "Flutter build total timeout", message)
                print(message, file=sys.stderr)
                return 124
            try:
                result = run_bounded(
                    build_command,
                    cwd=app_root,
                    check=False,
                    capture_output=True,
                    text=True,
                    timeout=attempt_timeout,
                )
            except subprocess.TimeoutExpired as error:
                stdout = error.output or ""
                stderr = error.stderr or ""
                if isinstance(stdout, bytes): stdout = stdout.decode("utf-8", errors="replace")
                if isinstance(stderr, bytes): stderr = stderr.decode("utf-8", errors="replace")
                output = _redact_diagnostics(f"{stdout}\n{stderr}\nFlutter build exceeded {attempt_timeout:.0f} seconds on attempt {retry + 1}; process group terminated.")
                _write_native_diagnostics(app_root, "Flutter/CMake/NDK native build timeout", output)
                print(output[-7200:], file=sys.stderr)
                if os.environ.get("GITHUB_ACTIONS"):
                    for index, message in enumerate(failure_annotations(124, output), start=1):
                        print(f"::error title=Android build timeout::{_escape_command_value(message)}")
                return 124
            except OSError as error:
                message = f"Could not start Flutter build command: {error}"
                _write_native_diagnostics(app_root, "Flutter build process start", message)
                print(message, file=sys.stderr)
                return 127

            output = _redact_diagnostics(result.stdout + result.stderr)
            if result.returncode == 0 or retry == MAX_TRANSIENT_BUILD_RETRIES or not TRANSIENT_HTTP_FAILURE.search(output):
                break
            delay = min(30 * (2 ** retry), max(0, build_deadline - time.monotonic()))
            print(f"Transient dependency repository HTTP error; retrying Flutter build in {delay:.0f} seconds.")
            time.sleep(delay)
        print(output, end="" if output.endswith("\n") else "\n")
        if result.returncode:
            _write_native_diagnostics(app_root, "Flutter/CMake/NDK native build", output)
        if result.returncode and os.environ.get("GITHUB_ACTIONS"):
            for index, message in enumerate(failure_annotations(result.returncode, output), start=1):
                print(f"::error title=Android debug APK build::{_escape_command_value(f'Build failure details {index}: {message}')}")
        if result.returncode:
            return result.returncode

        if args.phase == "build":
            return 0

    apk = app_root / "build" / "app" / "outputs" / "flutter-apk" / "app-debug.apk"
    if args.phase != "audit" and runtime_included:
        try:
            apk_report = audit_apk_cpu_only(apk)
        except (GateError, OSError) as error:
            print("Local AI APK backend audit failed; do not distribute this APK as CPU-only.", file=sys.stderr)
            _write_native_diagnostics(app_root, "prebuilt runtime APK audit", str(error))
            return 2
        print(json.dumps(apk_report, indent=2, sort_keys=True))

    if native_enabled:
        diagnostics_path = app_root / "build" / "local-ai-native-diagnostics.txt"
        diagnostics_path.parent.mkdir(parents=True, exist_ok=True)
        diagnostics_path.write_text("Stage: source-native APK audit started\n", encoding="utf-8")
        try:
            from prepare_llama_cpp_source import SOURCE_COMMIT

            source_commit = SOURCE_COMMIT
            cmake_cache_audits = _audit_source_cmake_caches(app_root / "android", source_commit)
            apk_report = audit_source_native_apk(apk)
            report = {
                "verification_status": "source_built_cpu_native_apk_audited",
                "readiness": "not_ready_model_and_device_inference_unverified",
                "device_runtime_validation": "not_run_no_compatible_physical_arm64_device_attached_to_ci",
                "apk": str(apk),
                "apk_sha256": hashlib.sha256(apk.read_bytes()).hexdigest(),
                "llama_cpp_source_commit": source_commit,
                "effective_cmake_cache_audits": cmake_cache_audits,
                "source_native_audit": apk_report,
                "jni_validation": "static_apk_dex_and_elf_registration_markers_only; not_runtime_loaded",
            }
            report_path = app_root / "build" / "local-ai-audit-report.json"
            report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        except Exception as error:
            trace = _redact_diagnostics(traceback.format_exc())
            message = f"Source-built llama.cpp APK audit failed; do not distribute this APK: {type(error).__name__}: {error}"
            _write_native_diagnostics(app_root, "source-native CMake/APK/JNI audit", f"{message}\n\n{trace}")
            print(message, file=sys.stderr)
            if os.environ.get("GITHUB_ACTIONS"):
                print(f"::error title=Source-native APK audit::{_escape_command_value(message)}")
                summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
                if summary_path:
                    with open(summary_path, "a", encoding="utf-8") as summary:
                        summary.write(f"### Source-native APK audit failed\n\n```text\n{type(error).__name__}: {error}\n```\n")
            return 2
        print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
