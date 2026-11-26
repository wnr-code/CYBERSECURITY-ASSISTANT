#!/usr/bin/env python3
"""Fetch and verify the pinned official llama.cpp source archive for Android builds.

Only codeload.github.com is used, redirects are rejected, and archive bytes are
verified before extraction. This prepares build-time source; it does not install
or activate a runtime/model in the app.
"""

from __future__ import annotations

import hashlib
import os
import shutil
import sys
import tarfile
import tempfile
import urllib.error
import urllib.request
from pathlib import Path, PurePosixPath

SOURCE_COMMIT = "ea722948146befb23c9529c1ec7f59fb2f34911f"
SOURCE_URL = f"https://codeload.github.com/ggml-org/llama.cpp/tar.gz/{SOURCE_COMMIT}"
SOURCE_SHA256 = "05b362e97564f2e449440f13878c43991a13b6029214dbcb0d1b116b20365ec2"
MAX_SOURCE_ARCHIVE_BYTES = 100 * 1024 * 1024
MAX_SOURCE_EXPANDED_BYTES = 512 * 1024 * 1024
MAX_SOURCE_MEMBERS = 20_000


class SourceError(RuntimeError):
    """Pinned source could not be acquired or verified."""


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, new_url):
        raise SourceError(f"Refusing source archive redirect (HTTP {code}).")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _read_verified_archive(archive_path: Path, *, opener=None) -> bytes:
    if archive_path.is_file():
        payload = archive_path.read_bytes()
    else:
        request = urllib.request.Request(SOURCE_URL, headers={"User-Agent": "CybersecurityAssistant-source-builder/1"})
        try:
            response = (opener or urllib.request.build_opener(_NoRedirect)).open(request, timeout=30)
            with response:
                final_url = response.geturl()
                if response.status != 200 or final_url != SOURCE_URL:
                    raise SourceError("Official source archive request did not return the exact pinned HTTPS URL.")
                if "codeload.github.com" not in final_url or not final_url.startswith("https://"):
                    raise SourceError("Source archive host is not the approved official codeload host.")
                payload = response.read(MAX_SOURCE_ARCHIVE_BYTES + 1)
        except (OSError, urllib.error.URLError) as exc:
            raise SourceError(f"Could not fetch pinned official llama.cpp source: {exc}") from exc
        except SourceError:
            raise
        if len(payload) > MAX_SOURCE_ARCHIVE_BYTES:
            raise SourceError("Pinned source archive exceeds the configured size limit.")
        archive_path.parent.mkdir(parents=True, exist_ok=True)
        temporary = archive_path.with_suffix(archive_path.suffix + ".part")
        temporary.write_bytes(payload)
        os.replace(temporary, archive_path)

    if len(payload) > MAX_SOURCE_ARCHIVE_BYTES:
        raise SourceError("Source archive exceeds the configured size limit.")
    actual = sha256_bytes(payload)
    if actual != SOURCE_SHA256:
        raise SourceError(f"Pinned source archive SHA-256 mismatch: expected {SOURCE_SHA256}, got {actual}.")
    return payload


def _safe_members(archive: tarfile.TarFile) -> tuple[list[tarfile.TarInfo], str]:
    members = archive.getmembers()
    if not members or len(members) > MAX_SOURCE_MEMBERS:
        raise SourceError("Source archive member count is empty or exceeds the audit limit.")
    roots: set[str] = set()
    seen: set[str] = set()
    expanded = 0
    for member in members:
        path = PurePosixPath(member.name)
        if path.is_absolute() or ".." in path.parts or "\\" in member.name or not path.parts:
            raise SourceError(f"Unsafe source archive member path: {member.name!r}")
        roots.add(path.parts[0])
        if member.name in seen:
            raise SourceError(f"Duplicate source archive path: {member.name!r}")
        seen.add(member.name)
        if not (member.isdir() or member.isfile()):
            raise SourceError(f"Non-regular source archive member is not allowed: {member.name!r}")
        if member.isfile():
            expanded += member.size
    if len(roots) != 1 or expanded > MAX_SOURCE_EXPANDED_BYTES:
        raise SourceError("Source archive has an unexpected root or expands beyond the audit limit.")
    root = next(iter(roots))
    expected_root = f"llama.cpp-{SOURCE_COMMIT}"
    if root != expected_root:
        raise SourceError("Source archive root does not match the pinned commit.")
    return members, root


def prepare_source(project_root: Path, *, opener=None) -> Path:
    cache = project_root / ".dart_tool" / "llama.cpp-source.tar.gz"
    destination = project_root / ".dart_tool" / "llama.cpp"
    _read_verified_archive(cache, opener=opener)
    destination.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix="llama.cpp-prepare-", dir=destination.parent))
    try:
        with tarfile.open(cache, "r:gz") as archive:
            members, root = _safe_members(archive)
            root_dir = staging / root
            root_dir.mkdir()
            for member in members:
                relative = PurePosixPath(member.name).parts[1:]
                if not relative:
                    continue
                target = root_dir.joinpath(*relative)
                if member.isdir():
                    target.mkdir(parents=True, exist_ok=True)
                else:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    source = archive.extractfile(member)
                    if source is None:
                        raise SourceError(f"Could not read source archive member: {member.name!r}")
                    with source, target.open("wb") as output:
                        shutil.copyfileobj(source, output)
                    target.chmod(member.mode & 0o755)
        source_root = staging / root
        if not (source_root / "CMakeLists.txt").is_file() or not (source_root / "include" / "llama.h").is_file():
            raise SourceError("Pinned source archive is missing expected llama.cpp build/API files.")
        (source_root / ".csa-source-lock").write_text(SOURCE_COMMIT + "\n", encoding="utf-8")
        if destination.exists():
            shutil.rmtree(destination)
        os.replace(source_root, destination)
    finally:
        shutil.rmtree(staging, ignore_errors=True)
    return destination


def main() -> int:
    project_root = Path(__file__).resolve().parents[1]
    try:
        prepared = prepare_source(project_root)
    except (OSError, SourceError, tarfile.TarError) as error:
        print(f"llama.cpp source preparation failed: {error}", file=sys.stderr)
        return 2
    print(f"Prepared official llama.cpp source {SOURCE_COMMIT} at {prepared}")
    print(f"Verified codeload archive SHA-256: {SOURCE_SHA256}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
