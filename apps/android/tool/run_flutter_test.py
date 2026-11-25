#!/usr/bin/env python3
"""Run expanded Flutter tests and preserve sanitized, complete CI evidence."""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ANSI_ESCAPE = re.compile(r"\x1B\[[0-?]*[ -/]*[@-~]")
TEST_SUMMARY = re.compile(r"(?m)^\d+:\d{2}\s+\+(\d+)(?:\s+-(\d+))?:\s+(All tests passed!|Some tests failed\.)\s*$")
SENSITIVE_LINE = re.compile(
    r"(?im)(\b(?:authorization|proxy-authorization|cookie|set-cookie|session[_-]?cookie|"
    r"github[_-]?token|actions[_-]?runtime[_-]?token)\s*[:=]\s*)[^\r\n]*"
)
SENSITIVE_ASSIGNMENT = re.compile(
    r"(?i)(\b(?:api[_-]?key|access[_-]?token|refresh[_-]?token|token|password|passwd|secret|"
    r"client[_-]?secret|private[_-]?key)\b\s*[:=]\s*)"
    r"(?:\"[^\"\r\n]*\"|'[^'\r\n]*'|[^\s,;&]+)"
)
URL_USERINFO = re.compile(r"(?i)\b(https?://)[^/\s@]+@")
BEARER_CREDENTIAL = re.compile(r"(?i)\b(Bearer|Basic)\s+[A-Za-z0-9._~+/=-]+")
JWT_CREDENTIAL = re.compile(r"\beyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}\b")
GITHUB_TOKEN = re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,})\b")
SENSITIVE_JSON_KEY = re.compile(
    r"(?i)(?:x[-_]?api[-_]?key|api[-_]?key|access[-_]?token|refresh[-_]?token|"
    r"github[-_]?token|oauth[-_]?token|personal[-_]?access[-_]?token|api[-_]?token|"
    r"id[-_]?token|auth[-_]?token|session[-_]?token|client[-_]?token|bearer[-_]?token|"
    r"(?:[a-z0-9]+[-_])+token|token|"
    r"password|passwd|passphrase|secret|client[-_]?secret|api[-_]?secret|private[-_]?key|"
    r"authorization|proxy[-_]?authorization|cookie|set[-_]?cookie|session[-_]?cookie)\Z"
)


def _parse_test_summary(output: str) -> tuple[int, int] | None:
    clean_output = ANSI_ESCAPE.sub("", output)
    matches = list(TEST_SUMMARY.finditer(clean_output))
    if not matches:
        return None
    match = matches[-1]
    return int(match.group(1)), int(match.group(2) or 0)


def _redact_json_value(value: object) -> object:
    if isinstance(value, dict):
        return {
            key: "[REDACTED]" if isinstance(key, str) and SENSITIVE_JSON_KEY.fullmatch(key)
            else _redact_json_value(item)
            for key, item in value.items()
        }
    if isinstance(value, list):
        return [_redact_json_value(item) for item in value]
    if isinstance(value, str):
        # Test output may itself JSON-encode a payload inside a JSON string.
        try:
            nested = json.loads(value)
        except json.JSONDecodeError:
            return value
        redacted_nested = _redact_json_value(nested)
        if redacted_nested != nested:
            return json.dumps(redacted_nested, ensure_ascii=False, separators=(",", ":"))
    return value


def _redact_json_fragments(output: str) -> str:
    """Redact credential keys in valid JSON objects/arrays embedded in logs."""
    decoder = json.JSONDecoder()
    segments: list[str] = []
    copied_through = 0
    cursor = 0
    while cursor < len(output):
        if output[cursor] not in "[{":
            cursor += 1
            continue
        try:
            value, end = decoder.raw_decode(output, cursor)
        except json.JSONDecodeError:
            cursor += 1
            continue
        redacted = _redact_json_value(value)
        if redacted != value:
            segments.append(output[copied_through:cursor])
            segments.append(json.dumps(redacted, ensure_ascii=False, separators=(",", ":")))
            copied_through = end
        cursor = end
    segments.append(output[copied_through:])
    return "".join(segments)


def _redact_output(output: str) -> str:
    """Pattern-redact common credentials; this is not a general PII detector."""
    # Match whole captured output, not streaming chunks, so credentials split
    # across process writes in the same stream are reassembled before redaction.
    output = _redact_json_fragments(output)
    output = SENSITIVE_LINE.sub(r"\1[REDACTED]", output)
    output = SENSITIVE_ASSIGNMENT.sub(r"\1[REDACTED]", output)
    output = URL_USERINFO.sub(r"\1[REDACTED]@", output)
    output = BEARER_CREDENTIAL.sub(r"\1 [REDACTED]", output)
    output = JWT_CREDENTIAL.sub("[REDACTED_JWT]", output)
    return GITHUB_TOKEN.sub("[REDACTED_GITHUB_TOKEN]", output)


def _evidence_directory() -> Path:
    configured = os.environ.get("FLUTTER_TEST_EVIDENCE_DIR")
    if configured:
        return Path(configured)
    runner_temp = os.environ.get("RUNNER_TEMP")
    root = Path(runner_temp) if runner_temp else Path(tempfile.gettempdir())
    return root / "flutter-test-evidence"


def main() -> int:
    stdout = ""
    stderr = ""
    try:
        result = subprocess.run(
            ["flutter", "test", "--reporter=expanded"],
            check=False,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
        stdout = result.stdout
        stderr = result.stderr
        flutter_exit_code = result.returncode
    except OSError as error:
        stderr = f"Could not start Flutter test process: {error}\n"
        flutter_exit_code = 127

    # Never print or upload raw process output: test failures sometimes include
    # URLs, request headers, or fixture credentials. Keep complete redacted logs.
    safe_stdout = _redact_output(stdout)
    safe_stderr = _redact_output(stderr)
    if safe_stdout:
        sys.stdout.write(safe_stdout)
        sys.stdout.flush()
        if not safe_stdout.endswith("\n"):
            sys.stdout.write("\n")
    if safe_stderr:
        sys.stderr.write(safe_stderr)
        sys.stderr.flush()
        if not safe_stderr.endswith("\n"):
            sys.stderr.write("\n")

    combined = safe_stdout + "\n" + safe_stderr
    summary = _parse_test_summary(combined)
    evidence_dir = _evidence_directory()
    evidence_error: OSError | None = None
    try:
        evidence_dir.mkdir(parents=True, exist_ok=True)
        (evidence_dir / "stdout.log").write_text(safe_stdout, encoding="utf-8")
        (evidence_dir / "stderr.log").write_text(safe_stderr, encoding="utf-8")
        metadata = [
            "command=flutter test --reporter=expanded",
            f"flutter_exit_code={flutter_exit_code}",
            f"evidence_redaction=enabled",
            "junit_xml=not_generated (no validated expanded-output converter)",
        ]
        if summary is not None:
            metadata.append(f"tests_passed={summary[0]}")
            metadata.append(f"tests_failed={summary[1]}")
        (evidence_dir / "metadata.txt").write_text("\n".join(metadata) + "\n", encoding="utf-8")
    except OSError as error:
        evidence_error = error
        sys.stderr.write(f"Failed to write Flutter test evidence: {error}\n")
        sys.stderr.flush()

    if summary is not None:
        passed, failed = summary
        print(f"Flutter tests: {passed} passed, {failed} failed.")
    if flutter_exit_code != 0:
        print(
            f"::error title=Flutter test failures::flutter test exited with code {flutter_exit_code}; "
            "see sanitized stdout.log and stderr.log in the evidence artifact if upload succeeds."
        )
    if evidence_error is not None:
        print("::error title=Flutter test evidence::could not write the diagnostic files for artifact upload.")
        # Do not turn a test failure into success. If tests passed but evidence
        # could not be persisted, fail the step so the missing evidence is clear.
        return flutter_exit_code or 1
    return flutter_exit_code


if __name__ == "__main__":
    raise SystemExit(main())
