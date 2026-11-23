#!/usr/bin/env python3
"""Run Flutter analysis and surface diagnostics as GitHub check annotations."""

from __future__ import annotations

import os
import re
import subprocess
import sys
from dataclasses import dataclass

DIAGNOSTIC = re.compile(
    r"^\s*(error|warning|info)\s+•\s+(.*?)\s+•\s+(.+?):(\d+):(\d+)\s+•\s+(.+?)\s*$"
)


@dataclass(frozen=True)
class Diagnostic:
    severity: str
    message: str
    path: str
    line: int
    column: int
    code: str


def parse_diagnostics(output: str) -> list[Diagnostic]:
    diagnostics = []
    for row in output.splitlines():
        match = DIAGNOSTIC.match(row)
        if match is None:
            continue
        severity, message, path, line, column, code = match.groups()
        diagnostics.append(
            Diagnostic(severity, message, path, int(line), int(column), code)
        )
    return diagnostics


def _escape_command_value(value: str) -> str:
    return value.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def _emit_github_annotations(diagnostics: list[Diagnostic]) -> None:
    if not os.environ.get("GITHUB_ACTIONS"):
        return
    for diagnostic in diagnostics:
        level = "error" if diagnostic.severity == "error" else "warning"
        message = _escape_command_value(f"{diagnostic.message} ({diagnostic.code})")
        path = _escape_command_value(diagnostic.path)
        print(
            f"::{level} file={path},line={diagnostic.line},col={diagnostic.column}::{message}"
        )


def main() -> int:
    result = subprocess.run(
        ["flutter", "analyze"],
        check=False,
        capture_output=True,
        text=True,
    )
    output = result.stdout + result.stderr
    print(output, end="" if output.endswith("\n") else "\n")
    diagnostics = parse_diagnostics(output)
    _emit_github_annotations(diagnostics)
    if result.returncode != 0 and not diagnostics:
        message = "Flutter analyzer failed without parseable source diagnostics."
        if os.environ.get("GITHUB_ACTIONS"):
            message = message.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
            print(f"::error::{message}")
        else:
            print(message, file=sys.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
