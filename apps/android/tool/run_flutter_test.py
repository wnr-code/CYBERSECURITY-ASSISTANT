#!/usr/bin/env python3
"""Run Flutter tests and attach failure output to the GitHub check."""

from __future__ import annotations

import os
import re
import subprocess
import sys

ANSI_ESCAPE = re.compile(r"\x1B\[[0-?]*[ -/]*[@-~]")
MAX_ANNOTATION_CHARS = 50_000


def _escape_command_value(value: str) -> str:
    return value.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def _failure_message(exit_code: int, output: str) -> str:
    clean_output = ANSI_ESCAPE.sub("", output)
    prefix = f"flutter test failed (exit {exit_code}).\n\n"
    available = MAX_ANNOTATION_CHARS - len(prefix)
    if len(clean_output) > available:
        suffix = "\n… output truncated …"
        clean_output = clean_output[: available - len(suffix)] + suffix
    return prefix + clean_output


def main() -> int:
    result = subprocess.run(
        ["flutter", "test", "--reporter", "expanded"],
        check=False,
        capture_output=True,
        text=True,
    )
    output = result.stdout + result.stderr
    print(output, end="" if output.endswith("\n") else "\n")
    if result.returncode != 0:
        message = _failure_message(result.returncode, output)
        if os.environ.get("GITHUB_ACTIONS"):
            print(f"::error title=Flutter test failures::{_escape_command_value(message)}")
        else:
            print(message, file=sys.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
