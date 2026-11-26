#!/usr/bin/env python3
"""Run child commands with a wall-clock deadline and kill their process group."""

from __future__ import annotations

import os
import signal
import subprocess
from pathlib import Path
from typing import Sequence


def run_bounded(
    command: Sequence[str],
    *,
    timeout: float,
    cwd: Path | str | None = None,
    check: bool = False,
    capture_output: bool = True,
    text: bool = False,
    encoding: str | None = None,
    errors: str | None = None,
) -> subprocess.CompletedProcess:
    """Run a command in its own process group; terminate descendants on timeout."""
    if timeout <= 0:
        raise ValueError("timeout must be positive")
    process = subprocess.Popen(
        list(command),
        cwd=cwd,
        stdout=subprocess.PIPE if capture_output else None,
        stderr=subprocess.PIPE if capture_output else None,
        text=text,
        encoding=encoding,
        errors=errors,
        start_new_session=True,
    )
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired as timed_out:
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            stdout, stderr = process.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            stdout, stderr = process.communicate()
        error = subprocess.TimeoutExpired(
            command,
            timeout,
            output=stdout if stdout is not None else timed_out.output,
            stderr=stderr if stderr is not None else timed_out.stderr,
        )
        raise error from None

    result = subprocess.CompletedProcess(list(command), process.returncode, stdout, stderr)
    if check and result.returncode:
        raise subprocess.CalledProcessError(result.returncode, list(command), output=stdout, stderr=stderr)
    return result
