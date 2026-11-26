#!/usr/bin/env python3
"""Run the debug APK build and publish useful bounded failure diagnostics."""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

from local_ai_artifact_gate import (
    GateError,
    audit_apk_cpu_only,
    audit_source_build_config,
    audit_source_native_apk,
    preflight_runtime_build,
)

MAX_ANNOTATION_CHARS = 1800
MAX_FAILURE_CHARS = 7200
MAX_TRANSIENT_BUILD_RETRIES = 2
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


def _write_native_diagnostics(app_root: Path, stage: str, output: str) -> None:
    """Persist bounded, redacted source-native failure evidence for CI artifacts."""
    if os.environ.get("LOCAL_AI_NATIVE_BUILD", "").strip() != "1":
        return
    output = re.sub(r"(?i)(bearer\s+)[A-Za-z0-9._~+/=-]+", r"\1[redacted]", output)
    output = re.sub(r"(?i)(token|api[_-]?key|password|secret)(\s*[:=]\s*)[^\s,;]+", r"\1\2[redacted]", output)
    output = re.sub(r"https?://\S+", "[url]", output)
    output = output[-100_000:]
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


def main() -> int:
    app_root = Path(__file__).resolve().parents[1]
    native_enabled = os.environ.get("LOCAL_AI_NATIVE_BUILD", "").strip() == "1"
    setup_stage = "runtime dependency preflight"
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
            escaped = _escape_command_value(message)
            print(f"::error title=Local AI artifact gate::{escaped}")
        return 2
    except Exception as error:
        message = f"Android build setup failed during {setup_stage}: {type(error).__name__}: {error}"
        _write_native_diagnostics(app_root, setup_stage, message)
        print(message, file=sys.stderr)
        if os.environ.get("GITHUB_ACTIONS"):
            escaped = _escape_command_value(message)
            print(f"::error title=Android build setup::{escaped}")
            summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
            if summary_path:
                with open(summary_path, "a", encoding="utf-8") as summary:
                    summary.write(f"### Android build setup failed during {setup_stage}\n\n```text\n{type(error).__name__}: {error}\n```\n")
        return 2

    build_command = flutter_build_command(native_enabled=native_enabled)
    print(f"Running Flutter build command: {' '.join(build_command)}")
    for retry in range(MAX_TRANSIENT_BUILD_RETRIES + 1):
        result = subprocess.run(
            build_command,
            cwd=app_root,
            check=False,
            capture_output=True,
            text=True,
        )
        output = result.stdout + result.stderr
        if result.returncode == 0 or retry == MAX_TRANSIENT_BUILD_RETRIES or not TRANSIENT_HTTP_FAILURE.search(output):
            break
        delay = 30 * (retry + 1)
        print(f"Transient dependency repository HTTP error; retrying Flutter build in {delay} seconds.")
        time.sleep(delay)
    print(output, end="" if output.endswith("\n") else "\n")
    if result.returncode:
        _write_native_diagnostics(app_root, "Flutter/CMake/NDK native build", output)
    if result.returncode and os.environ.get("GITHUB_ACTIONS"):
        for index, message in enumerate(failure_annotations(result.returncode, output), start=1):
            escaped = _escape_command_value(f"Build failure details {index}: {message}")
            print(f"::error title=Android debug APK build::{escaped}")
    if result.returncode:
        return result.returncode

    apk = app_root / "build" / "app" / "outputs" / "flutter-apk" / "app-debug.apk"
    if runtime_included:
        try:
            apk_report = audit_apk_cpu_only(apk)
        except (GateError, OSError):
            print("Local AI APK backend audit failed; do not distribute this APK as CPU-only.", file=sys.stderr)
            return 2
        print(json.dumps(apk_report, indent=2, sort_keys=True))
    if native_enabled:
        try:
            cmake_cache_audits = _audit_source_cmake_caches(app_root / "android", source_commit)
            apk_report = audit_source_native_apk(apk)
        except (GateError, OSError) as error:
            message = f"Source-built llama.cpp APK audit failed; do not distribute this APK: {error}"
            _write_native_diagnostics(app_root, "source-native CMake/APK audit", message)
            print(message, file=sys.stderr)
            if os.environ.get("GITHUB_ACTIONS"):
                escaped = _escape_command_value(message)
                print(f"::error title=Source-native APK audit::{escaped}")
                summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
                if summary_path:
                    with open(summary_path, "a", encoding="utf-8") as summary:
                        summary.write(f"### Source-native APK audit failed\n\n```text\n{error}\n```\n")
            return 2
        report = {
            "verification_status": "source_built_cpu_native_apk_audited",
            "readiness": "not_ready_device_inference_unverified",
            "apk": str(apk),
            "apk_sha256": hashlib.sha256(apk.read_bytes()).hexdigest(),
            "llama_cpp_source_commit": source_commit,
            "effective_cmake_cache_audits": cmake_cache_audits,
            "source_native_audit": apk_report,
        }
        report_path = app_root / "build" / "local-ai-audit-report.json"
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
