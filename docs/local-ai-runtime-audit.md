# Local AI runtime and model supply-chain audit

**Current status: Not Ready.** The active path is now native source build from official `ggml-org/llama.cpp` commit `ea722948146befb23c9529c1ec7f59fb2f34911f`, not the `local_inference`/`llamadart-native` bundle described in the historical notes below. The official codeload source archive was downloaded and locally hash-verified (`05b362e97564f2e449440f13878c43991a13b6029214dbcb0d1b116b20365ec2`). An opt-in arm64-v8a CPU-only CMake target, JNI/Flutter bridge, source-built APK audit, and fail-closed model-digest gate are implemented. Android NDK/CMake build, real model metadata, model installation, and offline device inference remain unverified; the app's trusted model digest catalog is intentionally empty.

The historical `local_inference` and prebuilt-asset inventory below is background only. It is not the selected integration path and is not evidence that any runtime or model is available in the app.

## Historical status at the earlier package evaluation

| Check | Status |
|---|---|
| Market Local AI card | Present; clearly marked Not Ready |
| `local_inference` source commit | Pinned in Market/docs: `fbf0282ae5ab59af712c43015ebfb171573d5be6` |
| Runtime archive SHA-256 metadata | `expected_sha256` cross-checked between the pinned manifest and GitHub Releases API; `actual_sha256` is null |
| CPU-only backend policy | Explicit CPU-only build config recorded; not applied because runtime is not integrated; APK backend audit pending |
| Runtime archive bytes / extracted libraries | **Not downloaded or verified**; release asset redirects to hosts outside this workspace's network allowlist |
| Runtime license information | Source MIT and upstream native notices reviewed; payload-level inventory still pending |
| Qwen2.5 model license / revision / size / SHA-256 | **Unverified**; no publisher artifact metadata available in this workspace |
| Runtime integrated in Android | No |
| Offline inference on device | No |

The manifest keeps `expected_sha256`, `actual_sha256`, and `verification_status` separate for the archive, each native library, and the model. Expected metadata matching is not local-byte verification; a missing actual hash remains `not_downloaded` / unverified and cannot pass an install gate.

## Candidate review

### `SxryxnshS5/onenm_local_llm`

Audited at upstream commit `55dadf762d40069aa393ff822e7f9e643b40806b` (2026-03-19), package `onenm_local_llm` 0.1.4. Its Flutter API wraps llama.cpp and its registry includes Qwen2.5 1.5B Instruct Q4_K_M, with a listed download of 1120 MB and a vendor-recommended 2 GB RAM. The project labels itself an early MVP and supports Android `arm64-v8a` only. Its downloader checks a minimum file length, not an authenticated SHA-256. Its native code contains prebuilt shared libraries, but this audit did not establish per-binary provenance/checksums. MIT applies to the plugin, not automatically to the model.

**Decision:** do not integrate this package as-is. It does not meet the model-integrity and conservative compatibility gates.

Sources: [upstream repository](https://github.com/SxryxnshS5/onenm_local_llm/tree/55dadf762d40069aa393ff822e7f9e643b40806b/flutter-llama.cpp), [model registry](https://github.com/SxryxnshS5/onenm_local_llm/blob/55dadf762d40069aa393ff822e7f9e643b40806b/flutter-llama.cpp/lib/models.dart).

### `slimshadystark/local_inference`

Audited at upstream commit `fbf0282ae5ab59af712c43015ebfb171573d5be6` (2026-10-16), release `v0.1.1`. The repository is MIT-licensed and has separate Dart and Flutter packages. `local_inference` requires Dart `>=3.10.7`; `local_inference_flutter` requires Dart `^3.12.0` and Flutter `>=3.44.0`, which fit this app's declared constraints (`>=3.13.0`, Flutter `>=3.47.0`). The release CI run on the main branch completed successfully on 2026-10-16.

Its model manifest requires HTTPS URLs, exact byte size, SHA-256, and per-model physical RAM, available RAM, and free-disk requirements. The manager verifies GGUF magic, size, and digest before atomically installing; it includes pause/resume, model removal, and capability probing. Its `llamadart` Android arm64 runtime is obtained as a pinned v0.4.0 release bundle, and the repository carries a SHA-256 manifest for the extracted libraries and archive as well as native-license notices. The Android archive digest in that pinned manifest (`756f4d3c4d020e2de4e26b029ebe9aad26073b4f14c425ce76d10e1c6922a73f`) matches the GitHub Releases API `digest` field for the v0.4.0 Android arm64 asset (38,610,514 bytes). The Android-only native component KleidiAI is listed as Apache-2.0; the other notices include MIT and public-domain components. This cross-check authenticates the expected archive digest but does **not** mean the archive has been downloaded or its extracted libraries verified in this workspace. It documents Qwen 2.5 family prompt support as best effort; Qwen3.5, not Qwen2.5, is its validated prompt family.

#### ARM64 runtime artifact audit (metadata only)

- `local_inference` depends on `llamadart` 0.8.23; the upstream tag resolves to commit `e153abed06870e3de48ea91a9b6cf8541c2ce79f`. The native `v0.4.0` tag resolves to source commit `236d369512eedbd564b5b1b839c2a6d0f9dd654e`.
- The pinned manifest declares 15 extracted Android ARM64 `.so` files plus the archive: core `ggml`/`llama`/`llamadart`/`mtmd` libraries, seven CPU variant libraries (`armv8.0`, `armv8.2`, `armv8.6`, `armv9.0`, `armv9.2`), and OpenCL/Vulkan modules. This is a manifest inventory, not a byte-level or ELF inspection.
- The upstream `llamadart` build configuration defaults Android ARM64 to CPU + Vulkan. Since the agreed profile is CPU-only, integration must explicitly request only the CPU backend and select a deliberate CPU-variant policy; do not silently ship or enable GPU backends. The exact built APK must then be checked to ensure only expected libraries are packaged.
- The candidate's own README reports Android API 28 at runtime and arm64-v8a support; its compatibility table says a release APK builds but has **not run on a device yet**. Thus upstream device support is not evidence of successful inference on a physical handset.
- A no-follow `HEAD` to the GitHub download URL returned a redirect to `objects.githubusercontent.com`; the GitHub API `application/octet-stream` route returned a redirect to `release-assets.githubusercontent.com`. Neither host is on this workspace's allowed outbound-host list, so the redirect was not followed. No binary archive was downloaded. We therefore cannot calculate the archive hash, list its actual tar members, inspect ELF machine/SONAME/`DT_NEEDED` dependencies, or compare extracted `.so` hashes in this environment. The API asset digest and manifest hashes are useful expected values only.

**Important integration caveat:** its generic manifest/device checks allow unknown RAM or disk readings to pass. The app must wrap this with its existing fail-closed policy and must not expose installation as available when ABI, RAM, storage, runtime/model compatibility, or trusted artifact metadata is unknown. Any model-specific peak-RAM estimate also needs a conservative, evidenced value; do not substitute the upstream plugin's 2 GB recommendation for a validated peak-memory requirement.

Sources: [upstream repository](https://github.com/slimshadystark/local_inference/tree/fbf0282ae5ab59af712c43015ebfb171573d5be6), [model manifest implementation](https://github.com/slimshadystark/local_inference/blob/fbf0282ae5ab59af712c43015ebfb171573d5be6/packages/local_inference/lib/src/delivery/manifest.dart), [model verification implementation](https://github.com/slimshadystark/local_inference/blob/fbf0282ae5ab59af712c43015ebfb171573d5be6/packages/local_inference/lib/src/delivery/model_manager.dart), [native bundle checksum manifest](https://github.com/slimshadystark/local_inference/blob/fbf0282ae5ab59af712c43015ebfb171573d5be6/packages/local_inference/tool/native/llamadart-native-v0.4.0.sha256), [native licenses](https://github.com/slimshadystark/local_inference/blob/fbf0282ae5ab59af712c43015ebfb171573d5be6/packages/local_inference/NATIVE_LICENSES.txt), [llamadart-native v0.4.0 release and GitHub asset digest](https://github.com/leehack/llamadart-native/releases/tag/v0.4.0).

**Decision:** selected as the sole runtime candidate for the next prototype. The app records the exact source commit, archive digest, and upstream license/checksum references in Market. The runtime package and binaries are not yet integrated or locally verified; do not mark Ready.

## Remaining release blockers

1. **Model artifact trust:** the selected Qwen2.5 1.5B Q4 artifact's authoritative size, immutable source revision, SHA-256 and model license have not been verified from the publisher. Its published GGUF source is on Hugging Face, which is outside this workspace's outbound-host allowlist. A SHA copied from an unrelated code search or an unverified registry is not acceptable. No model should be offered until this evidence is recorded in an app-owned manifest.
2. **Device policy:** the app must refuse installation on unknown or insufficient ABI, available/physical RAM, and storage; compatibility must include the actual runtime ABI and conservative inference memory headroom.
3. **Lifecycle/provider integration:** no runtime/model manager is connected to Market or to the AI provider registry. Local AI must not silently fall back to Gemini or another cloud provider.
4. **Validation:** Flutter/Dart tools are not present in this workspace, and no compatible Android ARM64 device/emulator with the model is available here. No build or offline inference test has been run. Offline success must be demonstrated on a device with the verified model installed and network disabled before claiming readiness.

## Immediate next steps

- Make the exact Android arm64 runtime archive available in the audit workspace (or run the audit in an environment whose allowlist permits GitHub's release-asset host), then verify archive and extracted-library SHA-256 values, list actual tar members, inspect ELF ABI/dependencies, and retain all license notices. Do not use an untrusted mirror or proxy.
- Before adding the runtime dependency to the app, apply the manifest's explicit CPU-only `llamadart_native_backends: [cpu]` setting in an isolated build and inspect the APK to prove Vulkan/OpenCL are absent. The manifest setting is a requirement, not an applied app configuration yet.
- Make the official Qwen artifact metadata available from its publisher (or permit the publisher host for this audit), then verify immutable revision, license, exact size, and SHA-256; if that cannot be established, keep the model unavailable rather than weakening verification.
- Only after those audits pass, integrate the pinned `local_inference` runtime, model manager, and explicit `local_ai` provider adapter behind a strict capability gate; preserve no-cloud-fallback semantics.
- Add focused tests for install refusal, hash mismatch/cleanup, lifecycle operations, provider selection, and local-only routing, then run Flutter analysis/tests/build and real inference offline on ARM64 hardware. Until then Local AI remains `notReady`.
