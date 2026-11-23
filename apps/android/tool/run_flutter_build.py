#!/usr/bin/env python3
"""Run the debug APK build and publish useful bounded failure diagnostics."""

from __future__ import annotations

import os
import subprocess
import sys

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


def main() -> int:
    result = subprocess.run(
        ["flutter", "build", "apk", "--debug"],
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
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
