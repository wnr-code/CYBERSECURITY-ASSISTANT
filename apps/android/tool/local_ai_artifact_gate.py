#!/usr/bin/env python3
"""Fail-closed audit gates for the pinned Local AI Android runtime.

This tool does not download artifacts, install models, activate Local AI, or
modify the manifest. It verifies only files supplied to it by the operator and
emits actual hashes separately from upstream-expected hashes.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import struct
import subprocess
import sys
import tarfile
import tempfile
import zipfile
from pathlib import Path, PurePosixPath
from typing import Any

MANIFEST_PATH = Path(__file__).resolve().parents[3] / "docs" / "local-ai-artifact-manifest.json"
RUNTIME_DEPENDENCIES = {"local_inference", "local_inference_flutter", "llamadart"}
RUNTIME_PREFIXES = ("libggml", "libllama", "libllamadart", "libmtmd")
FORBIDDEN_BACKEND_TOKENS = ("vulkan", "opencl")
MAX_NATIVE_FILE_BYTES = 256 * 1024 * 1024
MAX_ARCHIVE_BYTES = 512 * 1024 * 1024
MAX_EXPANDED_ARCHIVE_BYTES = 1024 * 1024 * 1024
MAX_ARCHIVE_MEMBERS = 4096


class GateError(ValueError):
    """An artifact or build configuration failed a release gate."""


def load_manifest(path: Path = MANIFEST_PATH) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise GateError(f"Cannot load Local AI artifact manifest: {exc}") from exc
    if not isinstance(data, dict) or data.get("schemaVersion") != 1:
        raise GateError("Unsupported or malformed Local AI artifact manifest.")
    return data


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _dependency_names(pubspec_text: str) -> set[str]:
    """Read direct dependency names without requiring a YAML parser."""
    names: set[str] = set()
    in_dependencies = False
    for line in pubspec_text.splitlines():
        if line and not line[0].isspace() and not line.lstrip().startswith("#"):
            in_dependencies = line.strip() in {"dependencies:", "dependency_overrides:"}
            continue
        if not in_dependencies:
            continue
        match = re.match(r"^  ([A-Za-z0-9_]+)\s*:", line)
        if match:
            names.add(match.group(1))
    return names


def _root_yaml_section(text: str, name: str) -> list[str]:
    lines = text.splitlines()
    for index, line in enumerate(lines):
        if line == f"{name}:":
            result = [line]
            for nested in lines[index + 1 :]:
                if nested and not nested[0].isspace() and not nested.lstrip().startswith("#"):
                    break
                result.append(nested)
            return result
    return []


def _indented_mapping_value(lines: list[str], key: str) -> list[str]:
    for index, line in enumerate(lines):
        match = re.match(r"^(\s*)" + re.escape(key) + r"\s*:\s*(.*)$", line)
        if not match:
            continue
        indent = len(match.group(1))
        result = [match.group(2)]
        for nested in lines[index + 1 :]:
            if nested.strip() and not nested.lstrip().startswith("#"):
                nested_indent = len(nested) - len(nested.lstrip())
                if nested_indent <= indent:
                    break
            result.append(nested.strip())
        return result
    return []


def _verify_cpu_only_pubspec(pubspec_text: str) -> None:
    hooks = _root_yaml_section(pubspec_text, "hooks")
    if not hooks:
        raise GateError("Runtime dependency is present, but the llama.cpp build-hook configuration is missing.")

    runtime_lines = _indented_mapping_value(hooks, "llamadart_native_runtimes")
    runtime_value = " ".join(runtime_lines).strip().lower()
    if not re.fullmatch(r"\[\s*llama_cpp\s*\]", runtime_value):
        raise GateError("Configure llamadart_native_runtimes to use llama_cpp only before building.")

    backend_lines = _indented_mapping_value(hooks, "llamadart_native_backends")
    if not backend_lines:
        raise GateError("Runtime dependency is present, but CPU-only backends are not explicitly configured.")
    normalized_backend_lines = [line.strip().lower().replace("'", "").replace('"', "") for line in backend_lines if line.strip()]
    expected_backend_lines = ["platforms:", "android-arm64:", "backends: [cpu]", "cpu_profile: full"]
    if normalized_backend_lines != expected_backend_lines:
        if any(token in " ".join(normalized_backend_lines) for token in FORBIDDEN_BACKEND_TOKENS):
            raise GateError("Vulkan/OpenCL backend configuration is forbidden for this CPU-only prototype.")
        raise GateError("Configure only Android ARM64 with backends [cpu] and cpu_profile full.")


def _manifest_runtime_is_verified(manifest: dict[str, Any]) -> None:
    runtime = manifest.get("runtime")
    gate = manifest.get("releaseGate")
    if not isinstance(runtime, dict) or not isinstance(gate, dict):
        raise GateError("Manifest is missing runtime/release-gate data.")
    archive = runtime.get("archive", {})
    expected = archive.get("expected_sha256")
    actual = archive.get("actual_sha256")
    if not expected or actual != expected or archive.get("verification_status") != "matches":
        raise GateError("Runtime archive bytes are not locally verified against expected_sha256.")
    if archive.get("archive_bytes_verified") is not True or archive.get("actual_contents_inspected") is not True:
        raise GateError("Runtime archive structure has not passed local inspection.")
    libraries = runtime.get("librariesExpectedByUpstreamManifest", [])
    if not libraries or any(
        item.get("verification_status") != "matches" or item.get("actual_sha256") != item.get("expected_sha256")
        for item in libraries
    ):
        raise GateError("One or more native library hashes are not locally verified.")
    if runtime.get("nativeLibraryHashesLocallyVerified") is not True:
        raise GateError("Native library verification is not marked complete.")
    if runtime.get("elfMetadataInspected") is not True or runtime.get("abi") != "arm64-v8a":
        raise GateError("ELF ABI inspection is not complete for the required Android arm64-v8a target.")
    if runtime.get("nativeDependenciesInspected") is not True:
        raise GateError("Native DT_NEEDED dependencies have not been inspected.")
    backend_policy = runtime.get("buildBackendPolicy", {})
    if backend_policy.get("requestedBackends") != ["cpu"] or backend_policy.get("appliedToApp") is not True:
        raise GateError("The app has not explicitly applied its CPU-only runtime build policy.")
    if set(backend_policy.get("forbiddenBackends", [])) != {"vulkan", "opencl"}:
        raise GateError("The manifest does not explicitly forbid Vulkan and OpenCL backends.")
    if set(runtime.get("expectedCpuApkLibraries", [])) & set(runtime.get("forbiddenApkBackendLibraries", [])):
        raise GateError("The APK CPU allowlist contains a forbidden Vulkan/OpenCL backend library.")
    dependency_policy = runtime.get("nativeDependencyPolicy", {})
    if dependency_policy.get("status") != "approved" or not dependency_policy.get("approved_needed_by_library"):
        raise GateError("Native DT_NEEDED dependencies have not been reviewed and allowlisted.")
    if runtime.get("licenses", {}).get("status") != "verified_for_payload":
        raise GateError("Runtime binary license inventory is not verified for the downloaded payload.")
    if gate.get("modelInstallEnabled") is not False:
        raise GateError("Model installation must remain disabled until the model artifact is independently verified.")


def preflight_runtime_build(pubspec_path: Path, manifest_path: Path = MANIFEST_PATH) -> bool:
    """Reject an unverified runtime dependency before Flutter can bundle native code.

    Returns False when no Local AI runtime dependency is configured. Returns True
    only when the dependency, artifact evidence, and CPU-only build configuration
    all pass; the APK must still pass the post-build audit.
    """
    try:
        pubspec_text = pubspec_path.read_text(encoding="utf-8")
    except OSError as exc:
        raise GateError(f"Cannot read app pubspec: {exc}") from exc
    dependencies = _dependency_names(pubspec_text)
    if not dependencies.intersection(RUNTIME_DEPENDENCIES):
        return False
    manifest = load_manifest(manifest_path)
    _manifest_runtime_is_verified(manifest)
    _verify_cpu_only_pubspec(pubspec_text)
    return True


def _safe_tar_members(archive: tarfile.TarFile) -> list[tarfile.TarInfo]:
    members = archive.getmembers()
    if len(members) > MAX_ARCHIVE_MEMBERS:
        raise GateError("Runtime archive contains too many members.")
    if sum(member.size for member in members if member.isfile()) > MAX_EXPANDED_ARCHIVE_BYTES:
        raise GateError("Runtime archive expands beyond the audit size limit.")
    names: set[str] = set()
    for member in members:
        name = member.name
        path = PurePosixPath(name)
        if path.is_absolute() or ".." in path.parts or "\\" in name or name.startswith("/"):
            raise GateError(f"Unsafe path in runtime archive: {name!r}")
        if name in names:
            raise GateError(f"Duplicate path in runtime archive: {name!r}")
        names.add(name)
        if member.issym() or member.islnk() or member.isdev() or member.isfifo():
            raise GateError(f"Non-regular archive member is not allowed: {name!r}")
        if member.isfile() and member.size > MAX_NATIVE_FILE_BYTES:
            raise GateError(f"Runtime archive member is unexpectedly large: {name!r}")
    return members


def _elf_header(path: Path) -> dict[str, Any]:
    with path.open("rb") as handle:
        header = handle.read(64)
    if len(header) < 20 or header[:4] != b"\x7fELF":
        raise GateError(f"Native library is not ELF: {path.name}")
    if header[4] != 2 or header[5] != 1:
        raise GateError(f"Native library is not little-endian ELF64: {path.name}")
    machine = struct.unpack("<H", header[18:20])[0]
    if machine != 183:
        raise GateError(f"Native library is not AArch64 (e_machine={machine}): {path.name}")
    return {"class": "ELF64", "endianness": "little", "machine": "AArch64", "machineId": machine}


def _readelf_needed(path: Path, readelf: str) -> list[str]:
    try:
        result = subprocess.run([readelf, "-d", str(path)], check=False, capture_output=True, text=True, timeout=15)
    except subprocess.TimeoutExpired as exc:
        raise GateError(f"readelf timed out for {path.name}") from exc
    if result.returncode != 0:
        raise GateError(f"readelf failed for {path.name}: {(result.stderr or result.stdout)[-500:]}")
    return sorted(set(re.findall(r"Shared library: \[([^\]]+)\]", result.stdout)))


def audit_runtime_archive(archive_path: Path, manifest_path: Path = MANIFEST_PATH, readelf: str | None = None) -> dict[str, Any]:
    """Hash and inspect an operator-supplied native archive without installing it."""
    manifest = load_manifest(manifest_path)
    runtime = manifest["runtime"]
    if archive_path.is_symlink() or not archive_path.is_file():
        raise GateError("Runtime archive must be a regular, non-symlink file.")
    archive_size = archive_path.stat().st_size
    if archive_size > MAX_ARCHIVE_BYTES:
        raise GateError("Runtime archive exceeds the audit size limit.")
    expected_archive_sha = runtime["archive"]["expected_sha256"]
    actual_archive_sha = _sha256_file(archive_path)
    report: dict[str, Any] = {
        "archive": {
            "expected_sha256": expected_archive_sha,
            "actual_sha256": actual_archive_sha,
            "verification_status": "matches" if actual_archive_sha == expected_archive_sha else "mismatch",
            "actual_size_bytes": archive_size,
        },
        "libraries": [],
        "archiveContentsInspected": False,
        "elfAbiInspected": False,
        "nativeDependenciesInspected": False,
        "dependencyReviewStatus": "not_inspected",
        "readyForRuntimeIntegration": False,
    }
    if actual_archive_sha != expected_archive_sha:
        return report
    expected_libraries = runtime.get("librariesExpectedByUpstreamManifest", [])
    expected_by_name = {item["path"]: item["expected_sha256"] for item in expected_libraries}
    if len(expected_by_name) != len(expected_libraries):
        raise GateError("Manifest contains duplicate native library paths.")
    readelf = readelf or shutil.which("llvm-readelf") or shutil.which("readelf")
    if readelf is None:
        raise GateError("llvm-readelf/readelf is required for native dependency inspection.")

    with tempfile.TemporaryDirectory(prefix="local-ai-audit-") as temp_dir:
        temp_root = Path(temp_dir)
        with tarfile.open(archive_path, mode="r:gz") as archive:
            members = _safe_tar_members(archive)
            so_members = [m for m in members if m.isfile() and m.name.lower().endswith(".so")]
            seen: set[str] = set()
            actual_by_name: dict[str, list[tarfile.TarInfo]] = {}
            for archive_member in so_members:
                actual_by_name.setdefault(PurePosixPath(archive_member.name).name, []).append(archive_member)
            for name, digest in expected_by_name.items():
                matches = actual_by_name.get(name, [])
                if not matches:
                    raise GateError(f"Expected native library is missing from archive: {name}")
                if len(matches) != 1 or name in seen:
                    raise GateError(f"Duplicate native library basename in archive: {name}")
                member = matches[0]
                seen.add(name)
                if member.size <= 0:
                    raise GateError(f"Empty native library in archive: {name}")
                if member.size > MAX_NATIVE_FILE_BYTES:
                    raise GateError(f"Native library exceeds the audit size limit: {name}")
                source = archive.extractfile(member)
                if source is None:
                    raise GateError(f"Cannot read native library member: {name}")
                target = temp_root / name
                hasher = hashlib.sha256()
                with source, target.open("wb") as output:
                    for chunk in iter(lambda: source.read(1024 * 1024), b""):
                        hasher.update(chunk)
                        output.write(chunk)
                actual_sha = hasher.hexdigest()
                status = "matches" if actual_sha == digest else "mismatch"
                row: dict[str, Any] = {"path": name, "expected_sha256": digest, "actual_sha256": actual_sha, "verification_status": status}
                if status == "matches":
                    row["elf"] = _elf_header(target)
                    row["neededLibraries"] = _readelf_needed(target, readelf)
                    if name in runtime.get("expectedCpuApkLibraries", []):
                        forbidden = [x for x in row["neededLibraries"] if any(token in x.lower() for token in FORBIDDEN_BACKEND_TOKENS)]
                        if forbidden:
                            raise GateError(f"CPU runtime library {name} has forbidden GPU dependencies: {forbidden}")
                report["libraries"].append(row)
                if status != "matches":
                    return report
            extra = sorted(PurePosixPath(m.name).name for m in so_members if PurePosixPath(m.name).name not in expected_by_name)
            if extra:
                raise GateError(f"Unmanifested shared libraries found in runtime archive: {extra}")
    report["archiveContentsInspected"] = True
    report["elfAbiInspected"] = len(report["libraries"]) == len(expected_by_name)
    report["nativeDependenciesInspected"] = report["elfAbiInspected"]
    actual_needed = {row["path"]: row.get("neededLibraries", []) for row in report["libraries"]}
    report["actual_needed_by_library"] = actual_needed
    dependency_policy = runtime.get("nativeDependencyPolicy", {})
    approved_needed = dependency_policy.get("approved_needed_by_library")
    approved = dependency_policy.get("status") == "approved" and isinstance(approved_needed, dict) and actual_needed == approved_needed
    report["dependencyReviewStatus"] = "approved" if approved else "review_required"
    report["readyForRuntimeIntegration"] = all(
        row["verification_status"] == "matches" for row in report["libraries"]
    ) and approved and runtime.get("licenses", {}).get("status") == "verified_for_payload"
    return report


def audit_model_file(model_path: Path, manifest_path: Path = MANIFEST_PATH) -> dict[str, Any]:
    """Compute a candidate model's actual size/hash; this does not install it."""
    manifest = load_manifest(manifest_path)
    model = manifest["model"]
    if model_path.is_symlink() or not model_path.is_file():
        raise GateError("Model artifact must be a regular, non-symlink file.")
    expected_sha = model.get("expected_sha256")
    expected_size = model.get("exactSizeBytes")
    actual_sha = _sha256_file(model_path)
    actual_size = model_path.stat().st_size
    report = {
        "expected_sha256": expected_sha,
        "actual_sha256": actual_sha,
        "expected_size_bytes": expected_size,
        "actual_size_bytes": actual_size,
        "publisher_revision": model.get("publisherRevision"),
        "license": model.get("license"),
        "verification_status": "publisher_metadata_unverified",
        "install_gate_status": "still_disabled_until_compatibility_runtime_and_offline_tests_pass",
    }
    with model_path.open("rb") as model_file:
        if model_file.read(4) != b"GGUF":
            report["verification_status"] = "invalid_gguf_header"
            return report
    if (
        not expected_sha
        or not expected_size
        or not model.get("publisherMetadataVerified")
        or not model.get("publisherRevision")
        or not model.get("license")
        or model.get("licenseVerificationStatus") != "verified"
        or model.get("sourceRevisionVerificationStatus") != "verified"
    ):
        return report
    report["verification_status"] = "matches" if actual_sha == expected_sha and actual_size == expected_size else "mismatch"
    return report


def audit_apk_cpu_only(apk_path: Path, manifest_path: Path = MANIFEST_PATH) -> dict[str, Any]:
    """Verify candidate runtime libraries in an APK; not a runtime readiness test."""
    manifest = load_manifest(manifest_path)
    if apk_path.is_symlink() or not apk_path.is_file():
        raise GateError("APK must be a regular, non-symlink file.")
    runtime = manifest["runtime"]
    expected_hashes = {item["path"]: item["expected_sha256"] for item in runtime["librariesExpectedByUpstreamManifest"]}
    expected_cpu = set(runtime["expectedCpuApkLibraries"])
    found: dict[str, tuple[str, bytes]] = {}
    with zipfile.ZipFile(apk_path) as apk:
        for name in apk.namelist():
            parts = PurePosixPath(name).parts
            if len(parts) < 3 or parts[0] != "lib" or not name.lower().endswith(".so"):
                continue
            basename = parts[-1]
            if any(token in basename.lower() for token in FORBIDDEN_BACKEND_TOKENS):
                raise GateError(f"Vulkan/OpenCL native library is packaged in the APK: {name}")
            if not basename.startswith(RUNTIME_PREFIXES):
                continue
            if len(parts) != 3 or parts[1] != "arm64-v8a":
                raise GateError(f"Local AI runtime library is packaged outside arm64-v8a: {name}")
            if basename in runtime.get("forbiddenApkBackendLibraries", []):
                raise GateError(f"Forbidden non-CPU backend is packaged in APK: {name}")
            if basename in found:
                raise GateError(f"Duplicate Local AI runtime library in APK: {basename}")
            found[basename] = (name, apk.read(name))
    missing = sorted(expected_cpu - found.keys())
    extra = sorted(found.keys() - expected_cpu)
    if missing or extra:
        raise GateError(f"APK runtime library set is not CPU-only allowlisted; missing={missing}, extra={extra}")
    rows = []
    for basename, (path, content) in sorted(found.items()):
        expected = expected_hashes.get(basename)
        actual = hashlib.sha256(content).hexdigest()
        if expected is None or actual != expected:
            raise GateError(f"APK runtime library hash does not match the pinned artifact: {path}")
        rows.append({"path": path, "expected_sha256": expected, "actual_sha256": actual, "verification_status": "matches"})
    return {"verification_status": "cpu_only_hashes_match", "runtime_libraries": rows, "apk": str(apk_path)}


def audit_source_native_apk(apk_path: Path, readelf: str | None = None) -> dict[str, Any]:
    """Audit the JNI shared library produced from pinned llama.cpp source.

    This is intentionally separate from the historical prebuilt-bundle audit:
    it requires one statically linked JNI library for arm64-v8a, inspects its ELF
    dependencies, and rejects bundled GGUF models. Passing this audit is not a
    model-integrity or offline-inference readiness claim.
    """
    if apk_path.is_symlink() or not apk_path.is_file():
        raise GateError("APK must be a regular, non-symlink file.")
    readelf = readelf or shutil.which("llvm-readelf") or shutil.which("readelf")
    if readelf is None:
        raise GateError("llvm-readelf/readelf is required for source-built runtime dependency inspection.")
    with zipfile.ZipFile(apk_path) as apk:
        names = apk.namelist()
        model_files = [name for name in names if name.lower().endswith(".gguf")]
        if model_files:
            raise GateError(f"Unverified model payload must not be bundled in the APK: {model_files[:5]}")
        native_files = [name for name in names if len(PurePosixPath(name).parts) == 3 and PurePosixPath(name).parts[0] == "lib" and name.lower().endswith(".so")]
        forbidden = [name for name in native_files if any(token in PurePosixPath(name).name.lower() for token in FORBIDDEN_BACKEND_TOKENS)]
        if forbidden:
            raise GateError(f"Forbidden Vulkan/OpenCL native library found in APK: {forbidden}")
        runtime_related = [name for name in native_files if PurePosixPath(name).name.startswith(("libcsa_localai", "libllama", "libggml"))]
        if len(runtime_related) != 1 or PurePosixPath(runtime_related[0]).name != "libcsa_localai.so":
            raise GateError(f"Expected one statically linked Local AI JNI library; found {runtime_related}")
        library_name = runtime_related[0]
        if PurePosixPath(library_name).parts[1] != "arm64-v8a":
            raise GateError(f"Source-built Local AI library is outside arm64-v8a: {library_name}")
        if library_name not in names:
            raise GateError("Source-built Local AI shared library disappeared from the APK.")
        payload = apk.read(library_name)
        if not payload or len(payload) > MAX_NATIVE_FILE_BYTES:
            raise GateError("Source-built Local AI shared library is empty or exceeds the audit size limit.")
        with tempfile.TemporaryDirectory(prefix="local-ai-source-apk-") as temporary:
            library_path = Path(temporary) / "libcsa_localai.so"
            library_path.write_bytes(payload)
            elf = _elf_header(library_path)
            needed = _readelf_needed(library_path, readelf)
        forbidden_dependencies = [name for name in needed if any(token in name.lower() for token in FORBIDDEN_BACKEND_TOKENS)]
        if forbidden_dependencies:
            raise GateError(f"Source-built CPU library has forbidden backend dependencies: {forbidden_dependencies}")
        dynamic_llama = [name for name in needed if name.lower().startswith(("libllama", "libggml"))]
        if dynamic_llama:
            raise GateError(f"llama.cpp/ggml must be statically linked into the single JNI library: {dynamic_llama}")
        return {
            "verification_status": "source_native_elf_inspected_cpu_backend_only",
            "readiness": "not_ready_model_and_device_inference_unverified",
            "native_library": {
                "path": library_name,
                "sha256": hashlib.sha256(payload).hexdigest(),
                "elf": elf,
                "needed_libraries": needed,
            },
            "bundled_gguf_models": 0,
        }


def _print_report(report: dict[str, Any]) -> None:
    print(json.dumps(report, indent=2, sort_keys=True))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    for command, help_text in (
        ("runtime-archive", "Audit an operator-supplied runtime archive without installing it."),
        ("model-file", "Hash/check a model file without installing it."),
        ("apk", "Check a prebuilt-runtime APK against the historical manifest."),
        ("source-apk", "Inspect a source-built llama.cpp JNI library in an APK."),
    ):
        child = subparsers.add_parser(command, help=help_text)
        child.add_argument("path", type=Path)
        child.add_argument("--manifest", type=Path, default=MANIFEST_PATH)
    args = parser.parse_args(argv)
    try:
        if args.command == "runtime-archive":
            report = audit_runtime_archive(args.path, args.manifest)
            _print_report(report)
            return 0 if report["readyForRuntimeIntegration"] else 2
        if args.command == "model-file":
            report = audit_model_file(args.path, args.manifest)
            _print_report(report)
            return 0 if report["verification_status"] == "matches" else 2
        if args.command == "source-apk":
            report = audit_source_native_apk(args.path)
            _print_report(report)
            return 0
        report = audit_apk_cpu_only(args.path, args.manifest)
        _print_report(report)
        return 0
    except (GateError, OSError, tarfile.TarError, zipfile.BadZipFile) as exc:
        print(f"Local AI artifact gate blocked: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
