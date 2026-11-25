#!/usr/bin/env python3
"""Run the debug APK build and publish useful bounded failure diagnostics."""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
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


def _escape_command_value(value: str) -> str:
    return value.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def failure_annotations(exit_code: int, output: str) -> list[str]:
    prefix = f"flutter build apk --debug failed (exit {exit_code}).\n\n"
    output_budget = MAX_FAILURE_CHARS - len(prefix)
    if len(output) > output_budget:
        output = "… build output truncated; showing tail …\n" + output[-(output_budget - 48) :]
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
    try:
        if native_enabled:
            from configure_android import configure_project
            from prepare_llama_cpp_source import SOURCE_COMMIT, prepare_source

            source_commit = SOURCE_COMMIT
            prepare_source(app_root)
            configure_project(app_root / "android", local_ai_native=True)
        runtime_included = preflight_runtime_build(app_root / "pubspec.yaml")
    except (GateError, RuntimeError, OSError) as error:
        message = f"Local AI runtime build gate blocked: {error}"
        print(message, file=sys.stderr)
        if os.environ.get("GITHUB_ACTIONS"):
            escaped = _escape_command_value(message)
            print(f"::error title=Local AI artifact gate::{escaped}")
        return 2

    result = subprocess.run(
        ["flutter", "build", "apk", "--debug"],
        cwd=app_root,
        check=False,
        capture_output=True,
        text=True,
    )
    output = result.stdout + result.stderr
    print(output, end="" if output.endswith("\n") else "\n")
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
            print(f"Source-built llama.cpp APK audit failed; do not distribute this APK: {error}", file=sys.stderr)
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
