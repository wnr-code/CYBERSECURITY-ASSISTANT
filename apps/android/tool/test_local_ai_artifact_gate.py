from __future__ import annotations

import hashlib
import json
import struct
import tarfile
import tempfile
import unittest
import zipfile
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from local_ai_artifact_gate import (
    GateError,
    audit_apk_cpu_only,
    audit_model_file,
    audit_runtime_archive,
    audit_source_build_config,
    audit_source_native_apk,
    preflight_runtime_build,
)


def _elf64_aarch64() -> bytes:
    header = bytearray(64)
    header[:4] = b"\x7fELF"
    header[4] = 2  # ELFCLASS64
    header[5] = 1  # little endian
    struct.pack_into("<H", header, 18, 183)  # EM_AARCH64
    return bytes(header)


def _source_apk(apk_path: Path, native: bytes | None = None) -> None:
    with zipfile.ZipFile(apk_path, "w") as apk:
        apk.writestr("lib/arm64-v8a/libcsa_localai.so", native or _elf64_aarch64())
        apk.writestr("assets/local_ai/llama.cpp-LICENSE.txt", "MIT License\nCopyright The ggml authors\n")
        apk.writestr("classes.dex", b"LocalAiInferenceBridge nativeLoadModel nativeUnloadModel nativeComplete nativeCancelInference nativeResetInferenceCancellation")


def _manifest_with_runtime(libraries: dict[str, bytes]) -> dict:
    rows = [
        {"path": name, "expected_sha256": hashlib.sha256(data).hexdigest()}
        for name, data in libraries.items()
    ]
    return {
        "schemaVersion": 1,
        "releaseGate": {"modelInstallEnabled": False},
        "runtime": {
            "archive": {},
            "librariesExpectedByUpstreamManifest": rows,
            "expectedCpuApkLibraries": list(libraries),
            "forbiddenApkBackendLibraries": ["libggml-opencl.so", "libggml-vulkan.so"],
            "nativeDependencyPolicy": {
                "status": "approved",
                "approved_needed_by_library": {name: [] for name in libraries},
            },
            "nativeLibraryHashesLocallyVerified": True,
            "elfMetadataInspected": True,
            "licenses": {"status": "verified_for_payload"},
        },
    }


def _write_manifest(path: Path, data: dict) -> None:
    path.write_text(json.dumps(data), encoding="utf-8")


class LocalAiArtifactGateTests(unittest.TestCase):
    def test_current_app_build_is_not_blocked_when_runtime_dependency_is_absent(self) -> None:
        current = Path(__file__).resolve().parents[1] / "pubspec.yaml"
        self.assertFalse(preflight_runtime_build(current))

    def test_unverified_runtime_dependency_is_blocked_before_flutter_build(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            pubspec = root / "pubspec.yaml"
            pubspec.write_text("name: test_app\ndependencies:\n  local_inference: 0.1.1\n", encoding="utf-8")
            manifest = root / "manifest.json"
            _write_manifest(manifest, {
                "schemaVersion": 1,
                "releaseGate": {"modelInstallEnabled": False},
                "runtime": {"archive": {"expected_sha256": "a" * 64, "actual_sha256": None, "verification_status": "not_downloaded"}},
            })
            with self.assertRaisesRegex(GateError, "archive bytes are not locally verified"):
                preflight_runtime_build(pubspec, manifest)

    def test_cpu_backend_config_accepts_only_arm64_cpu_full_profile(self) -> None:
        from local_ai_artifact_gate import _verify_cpu_only_pubspec

        good = """name: test_app
hooks:
  user_defines:
    llamadart:
      llamadart_native_runtimes: [llama_cpp]
      llamadart_native_backends:
        platforms:
          android-arm64:
            backends: [cpu]
            cpu_profile: full
"""
        _verify_cpu_only_pubspec(good)
        with self.assertRaisesRegex(GateError, "Vulkan/OpenCL"):
            _verify_cpu_only_pubspec(good.replace("backends: [cpu]", "backends: [cpu, vulkan]"))

    def test_runtime_archive_reports_actual_hashes_and_aarch64_dependencies(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            elf = _elf64_aarch64()
            archive_path = root / "runtime.tar.gz"
            with tarfile.open(archive_path, "w:gz") as archive:
                info = tarfile.TarInfo("android-arm64/extracted/libllama.so")
                info.size = len(elf)
                archive.addfile(info, __import__("io").BytesIO(elf))
            archive_sha = hashlib.sha256(archive_path.read_bytes()).hexdigest()
            manifest = _manifest_with_runtime({"libllama.so": elf})
            manifest["runtime"]["archive"] = {"expected_sha256": archive_sha}
            manifest["runtime"]["expectedCpuApkLibraries"] = ["libllama.so"]
            manifest_path = root / "manifest.json"
            _write_manifest(manifest_path, manifest)
            readelf_result = SimpleNamespace(returncode=0, stdout="Dynamic section:\n", stderr="")
            with patch("local_ai_artifact_gate.run_bounded", return_value=readelf_result):
                report = audit_runtime_archive(archive_path, manifest_path, readelf="readelf")
            self.assertEqual(report["archive"]["expected_sha256"], archive_sha)
            self.assertEqual(report["archive"]["actual_sha256"], archive_sha)
            self.assertEqual(report["archive"]["verification_status"], "matches")
            self.assertEqual(report["libraries"][0]["elf"]["machine"], "AArch64")
            self.assertTrue(report["readyForRuntimeIntegration"])

    def test_archive_hash_mismatch_never_inspects_members(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root / "runtime.tar.gz"
            with tarfile.open(archive, "w:gz"):
                pass
            manifest = _manifest_with_runtime({"libllama.so": _elf64_aarch64()})
            manifest["runtime"]["archive"] = {"expected_sha256": "0" * 64}
            path = root / "manifest.json"
            _write_manifest(path, manifest)
            report = audit_runtime_archive(archive, path, readelf="readelf")
            self.assertEqual(report["archive"]["verification_status"], "mismatch")
            self.assertFalse(report["archiveContentsInspected"])
            self.assertFalse(report["readyForRuntimeIntegration"])

    def test_apk_audit_rejects_vulkan_and_non_arm64_runtime_libraries(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            cpu_name = "libggml-base.so"
            cpu_data = b"verified cpu library"
            manifest = _manifest_with_runtime({cpu_name: cpu_data})
            manifest_path = root / "manifest.json"
            _write_manifest(manifest_path, manifest)

            apk_path = root / "gpu.apk"
            with zipfile.ZipFile(apk_path, "w") as apk:
                apk.writestr("lib/arm64-v8a/libggml-base.so", cpu_data)
                apk.writestr("lib/arm64-v8a/libggml-vulkan.so", b"gpu")
            with self.assertRaisesRegex(GateError, "Vulkan/OpenCL native library"):
                audit_apk_cpu_only(apk_path, manifest_path)

            apk_path = root / "wrong-abi.apk"
            with zipfile.ZipFile(apk_path, "w") as apk:
                apk.writestr("lib/armeabi-v7a/libggml-base.so", cpu_data)
            with self.assertRaisesRegex(GateError, "outside arm64-v8a"):
                audit_apk_cpu_only(apk_path, manifest_path)

    def test_qwen_install_requires_official_metadata_and_actual_bytes_before_native_load(self) -> None:
        app = Path(__file__).resolve().parents[1]
        installer = (app / "lib/core/local_ai_model_installer.dart").read_text(encoding="utf-8")
        source = (app / "lib/core/local_ai_model_source.dart").read_text(encoding="utf-8")
        runtime = (app / "lib/core/local_ai_inference_runtime.dart").read_text(encoding="utf-8")
        widget = (app / "lib/widgets/local_ai_model_install_action.dart").read_text(encoding="utf-8")
        diagnostic = (app / "lib/widgets/local_ai_diagnostic_test.dart").read_text(encoding="utf-8")
        self.assertIn("fetchPublisherMetadata(manifest)", installer)
        self.assertIn("actualSha256 != publisherFile.sha256Hex", installer)
        self.assertIn("await _loadPinnedModel(publisherFile)", installer)
        self.assertIn("cardData['license']", source)
        self.assertIn("metadataSha != manifest.sha256Hex", source)
        self.assertIn("publisherMetadataVerified", runtime)
        self.assertIn("downloadVerifyAndLoad", widget)
        self.assertIn("runtime?['publisherMetadataVerified'] == true", diagnostic)
        self.assertIn("official publisher metadata and actual GGUF bytes must pass the in-app download checks", diagnostic)

    def test_model_audit_reports_hash_but_never_enables_install(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            model_bytes = b"GGUF" + b"test-model"
            model_path = root / "candidate.gguf"
            model_path.write_bytes(model_bytes)
            manifest = {
                "schemaVersion": 1,
                "model": {
                    "expected_sha256": hashlib.sha256(model_bytes).hexdigest(),
                    "actual_sha256": None,
                    "exactSizeBytes": len(model_bytes),
                    "publisherRevision": "pinned-test-revision",
                    "publisherMetadataVerified": True,
                    "license": "verified-test-license",
                    "licenseVerificationStatus": "verified",
                    "sourceRevisionVerificationStatus": "verified",
                },
            }
            manifest_path = root / "manifest.json"
            _write_manifest(manifest_path, manifest)
            report = audit_model_file(model_path, manifest_path)
            self.assertEqual(report["verification_status"], "matches")
            self.assertEqual(report["actual_sha256"], report["expected_sha256"])
            self.assertIn("still_disabled", report["install_gate_status"])

    def test_effective_cmake_cache_must_be_pinned_arm64_cpu_only(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "app" / ".dart_tool" / "llama.cpp"
            source.mkdir(parents=True)
            source.joinpath(".csa-source-lock").write_text("a" * 40, encoding="utf-8")
            cache = root / "CMakeCache.txt"
            names = (
                "BUILD_SHARED_LIBS", "GGML_NATIVE", "GGML_OPENMP", "GGML_LLAMAFILE",
                "GGML_CPU_KLEIDIAI", "GGML_CPU_ALL_VARIANTS", "GGML_BACKEND_DL",
                "GGML_CUDA", "GGML_VULKAN", "GGML_OPENCL", "GGML_METAL", "GGML_RPC",
                "GGML_SYCL", "GGML_CANN", "GGML_MUSA", "GGML_CUDA_GRAPHS",
                "LLAMA_OPENSSL", "LLAMA_SUBPROCESS", "LLAMA_BUILD_COMMON", "LLAMA_BUILD_TESTS",
                "LLAMA_BUILD_TOOLS", "LLAMA_BUILD_EXAMPLES", "LLAMA_BUILD_SERVER",
                "LLAMA_BUILD_APP", "LLAMA_BUILD_MTMD",
            )
            lines = [
                "ANDROID_ABI:STRING=arm64-v8a",
                f"LLAMA_CPP_SOURCE_DIR:UNINITIALIZED={source}",
                *(f"{name}:BOOL=OFF" for name in names),
            ]
            cache.write_text("\n".join(lines), encoding="utf-8")
            report = audit_source_build_config(cache, "a" * 40)
            self.assertEqual(report["target_abi"], "arm64-v8a")
            self.assertEqual(report["verification_status"], "effective_cmake_cache_cpu_only_arm64_verified")
            cache.write_text("\n".join(lines).replace("GGML_VULKAN:BOOL=OFF", "GGML_VULKAN:BOOL=ON"), encoding="utf-8")
            with self.assertRaisesRegex(GateError, "CPU-only/no-CLI"):
                audit_source_build_config(cache, "a" * 40)

    def test_local_ai_readiness_requires_real_offline_inference_and_manual_review_diagnostics(self):
        app = Path(__file__).resolve().parents[1]
        runtime = (app / "lib/core/local_ai_inference_runtime.dart").read_text(encoding="utf-8")
        manager = (app / "lib/core/ai_provider_manager.dart").read_text(encoding="utf-8")
        diagnostics = (app / "lib/core/diagnostics.dart").read_text(encoding="utf-8")
        native = (Path(__file__).resolve().parent / "native/LocalAiInferenceBridge.kt").read_text(encoding="utf-8")
        self.assertIn("status['offlineInferenceSucceeded'] == true", runtime)
        self.assertIn("Future<bool> canAttemptInference()", runtime)
        self.assertIn("isNetworkIsolated(activity)", native)
        self.assertIn('"offlineInferenceSucceeded" to loadedOfflineInferenceSucceeded', native)
        self.assertIn("requireManualReview: providerId == 'local_ai'", manager)
        self.assertIn("report.component.startsWith('local_ai_')", diagnostics)

    def test_model_catalog_pins_match_flutter_and_native_bridge(self):
        tool_dir = Path(__file__).resolve().parent
        flutter_pin = (tool_dir.parent / "lib/core/local_ai_model_manifest.dart").read_text(encoding="utf-8")
        flutter_pin += (tool_dir.parent / "lib/core/local_ai_model_installer.dart").read_text(encoding="utf-8")
        native_bridge = (tool_dir / "native/LocalAiInferenceBridge.kt").read_text(encoding="utf-8")
        for token in (
            "dd26da440ef0330c47919d1ecae0966d24022222",
            "qwen2.5-1.5b-instruct-q4_k_m.gguf",
            "6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e",
            "1_117_320_736",
            "qwen2.5-0.5b-instruct-q4_k_m.gguf",
            "74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db",
            "smollm2-1.7b-instruct-q4_k_m.gguf",
            "decd2598bc2c8ed08c19adc3c8fdd461ee19ed5708679d1c54ef54a5a30d4f33",
        ):
            with self.subTest(token=token):
                self.assertIn(token, flutter_pin)
                self.assertIn(token, native_bridge)
        self.assertIn("Apache-2.0", flutter_pin)
        self.assertIn("LocalAiModelDownloadService", native_bridge)

    def test_source_apk_audit_accepts_only_static_arm64_jni_payload(self):
        with tempfile.TemporaryDirectory() as directory:
            apk_path = Path(directory) / "source.apk"
            _source_apk(apk_path)
            with (
                patch("local_ai_artifact_gate._readelf_needed", return_value=["libc.so", "libc++_shared.so"]),
                patch("local_ai_artifact_gate._readelf_symbols", return_value={"JNI_OnLoad"}),
            ):
                report = audit_source_native_apk(apk_path, readelf="readelf")
            self.assertEqual(report["native_library"]["elf"]["machine"], "AArch64")
            self.assertEqual(report["bundled_gguf_models"], 0)
            self.assertIn("not_ready", report["readiness"])
            self.assertEqual(report["native_library"]["jni_methods_registered_in_dex"], [
                "nativeLoadModel", "nativeUnloadModel", "nativeComplete", "nativeCancelInference", "nativeResetInferenceCancellation",
            ])
            json.dumps(report)

    def test_source_apk_audit_rejects_model_payload_and_dynamic_gpu_library(self):
        with tempfile.TemporaryDirectory() as directory:
            apk_path = Path(directory) / "model.apk"
            _source_apk(apk_path)
            with zipfile.ZipFile(apk_path, "a") as apk:
                apk.writestr("assets/unverified.gguf", b"GGUF")
            with self.assertRaisesRegex(GateError, "Unverified model payload"):
                audit_source_native_apk(apk_path, readelf="readelf")

            apk_path = Path(directory) / "gpu.apk"
            _source_apk(apk_path)
            with (
                patch("local_ai_artifact_gate._readelf_needed", return_value=["libvulkan.so"]),
                patch("local_ai_artifact_gate._readelf_symbols", return_value={"JNI_OnLoad"}),
            ):
                with self.assertRaisesRegex(GateError, "forbidden accelerator dependencies"):
                    audit_source_native_apk(apk_path, readelf="readelf")


if __name__ == "__main__":
    unittest.main()
