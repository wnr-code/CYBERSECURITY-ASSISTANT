# Static Security Audit — Flutter Foundation

- **Review date:** 2026-11-23
- **Review type:** Source-level review plus GitHub Actions compile/test verification
- **Current verified commit:** `77f54f5f89194b8aea2349810ce125d02727fb17`
- **Status:** CI checks and debug build passed; Android device/emulator verification is still pending
- **Not a certification:** No physical-device run, emulator run, dynamic analysis, penetration test, or production release signing has been completed.

## Scope

Reviewed the Flutter Android foundation, target policy/network adapters, orchestration, provider credential handling, local result persistence/export, GitHub release metadata parsing, Android hardening configurator, CI workflow, and security/setup documentation.

## Controls and residual limitations

- Network operations use a registry-only orchestrator, explicit self-attestation, narrow HTTPS-origin validation, and bounded timeouts. Authorization confirmation is a UX gate, not proof of legal authorization.
- DNS uses the device resolver; TLS inspects one connection on port 443; the HTTP header check makes one HTTPS GET to `/`, does not follow redirects, and does not read/display the response body.
- Header and response-value secret redaction is heuristic and not comprehensive. Review exported reports before sharing.
- Results are session-only unless a user explicitly saves an individual result to app-private SQLite. The SQLite database is not encrypted or synced. Deletion and persistence still need device-level verification.
- `flutter_secure_storage` UI/wrapper exists, but the Android Keystore implementation has not been runtime-tested. Do not enter real credentials until device-level read/write/delete, restore/backup, and key invalidation behavior is checked. Provider entries are guidance only; no provider-authenticated requests are implemented.
- GitHub release handling reads allowlisted release metadata only; it does not download, verify, install, or execute assets.
- Android debug APK is debug-signed. No production keystore or release signing is configured.

## CI verification

GitHub Actions run [45242263160](https://github.com/wnr-code/CYBERSECURITY-ASSISTANT/actions/runs/45242263160) on commit `77f54f5` completed successfully. Its job passed Android scaffold generation, native hardening tests/application, Flutter dependency resolution, `flutter analyze`, `flutter test`, debug APK build, and artifact upload. The artifact `cybersecurity-assistant-android-verification` was available and not expired when checked; GitHub reported the ZIP artifact size as 90,401,423 bytes. That is the archive size, not the individual APK size. The sandbox could not download the archive because its GitHub redirect target is outside the allowed outbound host list, so the APK's inner size/hash has not been measured here. The workflow retains artifacts for seven days.

The Python tooling suite was run locally and passed 10 tests. The coding environment has no Flutter/Dart/ADB/emulator executables; therefore there has been no emulator or physical-device testing. In particular, APK installation, exact merged manifest/target SDK/ABI verification, actual Android network behavior, SQLite lifecycle persistence/deletion, and Keystore behavior remain unverified. Refer to [Android Device Testing & MVP Stabilization](android-device-testing.md) for the manual checklist and explicit outstanding cases.

## Android configuration verified in CI

`apps/android/tool/configure_android.py` is exercised against generated Gradle/manifest fixtures and applied to the CI scaffold. It enforces minimum SDK 23, adds the normal `android.permission.INTERNET` permission, disables cleartext traffic and backup, and writes backup/data-extraction exclusions. These generated native files are temporary runner outputs and are not committed. Exact `targetSdk` and the final merged manifest should be inspected from the downloaded APK/build before release. No runtime permission should be required for `INTERNET`; verify there are no unexpected permissions on the installed package.

## Prior issues resolved before this verification

- Deprecated Material imports and related analyzer diagnostics were migrated to `material_ui` and current widget APIs.
- Flutter widget tests were repaired for scroll visibility and target authorization state. The final full CI test suite passed.
- CI test failure output was made available through bounded GitHub annotations to diagnose earlier failures.

## APK self-protection foundation review — 2026-11-23

The app-level `AppSelfProtectionPolicy` is now an additional runtime gate: registered tool execution rejects filesystem read/write, process execution, native-code, and unknown capabilities regardless of UI consent; the existing `PolicyEngine` still controls tool IDs/network authorization. Market verification, direct installer entry, and the manager install path all enforce data-only payload types (`jsonData`/`opaqueData`) and reject archives/executables. The terminal remains an application-command interface rather than an unrestricted shell. New unit tests cover the policy’s deny cases, Market payload boundary, and immutable app-code policy; runtime execution already has coverage that a filesystem capability is rejected before the adapter runs. Indonesian translations were added for new protection errors.

This is **not APK self-integrity verification** and is not a claim that all filesystem routes have been dynamically exercised. Dart/Flutter are unavailable in the current sandbox, so the new Flutter tests, analyzer, formatter, and build have not been run. The `denyAppCodeMutation` policy documents/expresses the immutable-code rule but does not replace Android OS sandboxing or signed-update verification. The app does not yet verify its own APK signature or hash bundled source/components at runtime; `RuntimeDescriptor.sha256` remains metadata, not an integrity proof. Android's Package Manager must enforce update signing, while a production signing configuration and generated Android scaffold are absent from this workspace, so APK signing/update behavior was not tested. There is also no dedicated scoped user-workspace filesystem API in this change; do not grant raw filesystem capabilities to future AI/runtime tools. Keep user-project operations on an explicitly scoped workspace API when implemented. Terminal, AI, Market, and runtime integration tests on-device remain outstanding.

## 4E-1 workspace filesystem boundary — implementation status

A shared `WorkspaceFileSystem` now roots user projects at the dedicated `Documents/user_workspace` directory, checks that its canonical root does not overlap app-support storage, exposes only relative-path text/file operations (not raw `File`/`Directory` handles), and requires a per-operation authorization callback. Terminal `workspace list`/`workspace read`/`workspace write`/`workspace replace` commands use the API and display an allow-once confirmation for the requested relative path; shell-looking characters in write content are treated only as file text and are never dispatched. Gemini, Local AI, Runtime, and Market actors are hard-denied by this workspace API; those components have no user-workspace filesystem handle. Runtime state and Market payload storage remain in separate app-private locations, not the user workspace. The API rejects traversal, symlinks, reserved credential/private paths, executable/binary artifact extensions, invalid UTF-8 and oversized text; writes use a temporary file and rename. The Android normal-app sandbox is still part of the security model.

This does **not** yet provide a multi-line project editor or expose directory-create/delete controls in Terminal UI. Terminal can create or replace a single-line text file per command; the scoped API also has create-directory/delete-file operations for a future consented UI. Dart's path-based filesystem API cannot provide an `openat(O_NOFOLLOW)`-style race-free guarantee, so symlink checks are repeated but still have a time-of-check/time-of-use limitation. Do not expose the API to AI/runtime/Market until there is an actor-specific consent flow and device validation. Regression tests have been added for normal reads/writes, denied actors, traversal, private roots, symlinks, binary/credential paths, size limits, and Terminal integration; they remain unexecuted because Flutter/Dart are unavailable in this sandbox.

## 4E-2 APK identity, integrity baseline, and trusted-update foundation

Generated Android launchers now receive a native Kotlin/Java verifier. Before Flutter starts, a release build compares the installed package's current signing-certificate SHA-256 to the pin from `TRUSTED_APK_CERT_SHA256`; an absent pin or mismatch throws and prevents release startup. The Flutter channel returns package ID, version code, signer fingerprint, installer source, and an aggregate SHA-256 over the installed base/split APK files. The Dart startup monitor anchors package/version/signer/component digest in `flutter_secure_storage` (Android Keystore-backed), rejects changed bytes at the same version and version downgrade, and accepts a version increase only with the same signer and Google Play installer. Candidate metadata/checksum policy tests cover package ID, signer, version monotonicity, and byte digest. There is deliberately no APK downloader, sideload flow, or hidden update/install path: Android Package Manager and Play Store remain responsible for update package-signature verification and replacement.

This remains a **foundation, not verified active APK protection**. No production signer fingerprint or release keystore is configured in this repository/workspace. The Android scaffold is generated rather than committed, so the native Kotlin/Java source has not been compiled against a real generated APK here. A release configured without a signer pin is intentionally non-launchable; debug builds explicitly do not claim trust. The component digest baseline is first anchored on a Play-installed, trusted-signer launch and relies on normal Android package/Keystore protections; root/OS compromise is out of scope. Flutter/Dart tests, analyzer, release build, on-device signature/update checks, and malicious-APK runtime tests remain unrun. The local Android tool suite passed 23 Python tests, including pin validation, source generation/idempotence, signer-fingerprint parsing, and pre-Flutter wiring; this only validates tooling/source text, not APK behavior.

## Release/MVP gates still open

1. Download the artifact from GitHub, record the APK's exact size and SHA-256, and inspect package metadata/merged permissions/target SDK/ABIs.
2. Complete the manual device checklist on at least one real Android device; use an emulator/API level as a second environment when available.
3. Verify network-loss errors/timeouts, target consent/validation, SQLite save/load/restart/delete, and secure storage behavior on Android.
4. Do not use production credentials or distribute as a release until device checks pass and user-controlled release signing is configured.
