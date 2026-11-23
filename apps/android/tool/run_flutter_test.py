#!/usr/bin/env python3
"""Run Flutter tests and expose bounded failure logs in GitHub annotations."""

from __future__ import annotations

import os
import re
import subprocess
import sys

ANSI_ESCAPE = re.compile(r"\x1B\[[0-?]*[ -/]*[@-~]")
MAX_FAILURE_OUTPUT_CHARS = 50_000
ANNOTATION_CHUNK_CHARS = 2_000


def _escape_command_value(value: str) -> str:
    return value.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def _failure_messages(exit_code: int, output: str) -> list[str]:
    clean_output = ANSI_ESCAPE.sub("", output)
    prefix = f"flutter test failed (exit {exit_code}).\n\n"
    suffix = "\n… failure output truncated …"
    available = MAX_FAILURE_OUTPUT_CHARS - len(prefix)
    if len(clean_output) > available:
        clean_output = clean_output[: available - len(suffix)] + suffix

    chunks = [
        clean_output[start : start + ANNOTATION_CHUNK_CHARS]
        for start in range(0, len(clean_output), ANNOTATION_CHUNK_CHARS)
    ] or ["No test output was produced."]
    total = len(chunks)
    return [
        f"Flutter test failure output {index}/{total}.\n{prefix if index == 1 else ''}{chunk}"
        for index, chunk in enumerate(chunks, start=1)
    ]


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
        messages = _failure_messages(result.returncode, output)
        if os.environ.get("GITHUB_ACTIONS"):
            for message in messages:
                escaped = _escape_command_value(message)
                print(f"::error title=Flutter test failures::{escaped}")
        else:
            print("\n".join(messages), file=sys.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
