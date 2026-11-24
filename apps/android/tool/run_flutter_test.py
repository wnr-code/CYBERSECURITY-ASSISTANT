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
TEST_SUMMARY = re.compile(r"(?m)^\d+:\d{2}\s+\+(\d+)(?:\s+-(\d+))?:\s+(All tests passed!|Some tests failed\.)\s*$")


def _parse_test_summary(output: str) -> tuple[int, int] | None:
    matches = list(TEST_SUMMARY.finditer(ANSI_ESCAPE.sub("", output)))
    if not matches:
        return None
    match = matches[-1]
    return int(match.group(1)), int(match.group(2) or 0)


def _escape_command_value(value: str) -> str:
    return value.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def _failure_messages(exit_code: int, output: str) -> list[str]:
    clean_output = ANSI_ESCAPE.sub("", output)
    prefix = f"flutter test failed (exit {exit_code}).\n\n"
    suffix = "\n… failure output truncated …"
    available = MAX_FAILURE_OUTPUT_CHARS - len(prefix)
    if len(clean_output) > available:
        keep_head = max(1, (available - len(suffix)) // 2)
        keep_tail = max(1, available - len(suffix) - keep_head)
        clean_output = clean_output[:keep_head] + suffix + clean_output[-keep_tail:]

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
    test_summary = _parse_test_summary(output)
    if test_summary is not None and os.environ.get("GITHUB_ACTIONS"):
        passed, failed = test_summary
        summary = f"Flutter tests: {passed} passed, {failed} failed."
        escaped = _escape_command_value(summary)
        print(f"::notice title=Flutter test totals::{escaped}")
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as step_summary:
            step_summary.write(f"### Flutter test totals\n\n{summary}\n")
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
