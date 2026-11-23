# Static Security Audit — Flutter Foundation

- **Review date:** 2026-11-23
- **Review type:** Source-level static review of the current prototype
- **Status:** Source findings have fixes; Flutter/Android verification is still in progress
- **Not a certification:** No successful Dart/Flutter test run, Android build, device test, dynamic analysis, or penetration test has completed. Eight Python unit tests for the hardening/analyzer helpers passed locally.

## Scope

Reviewed the Android Flutter foundation, including target policy and network adapters, tool orchestration, provider credential handling, local result persistence and export, GitHub release metadata parsing, the Connection Manager and provider dialogs, CI workflow, and security/setup documentation.

## Findings addressed in this review

### Authorization must track the exact endpoint or target

**Risk:** A previously accepted self-attestation could remain selected after editing a target, making a later request appear authorized for a different destination.

**Change:** Editing a target or endpoint clears the authorization checkbox and previous outcome. Inputs are disabled while a network check is in progress. Connection checks require authorization before constructing the HTTP client. Widget coverage was added for target-change invalidation; it has not been run.

### Malformed URL ports must fail closed

**Risk:** URI parsing and port access may reject malformed ports at different stages. An uncaught format error could escape the UI instead of producing a validation message.

**Change:** Tool-target port/host extraction now handles `FormatException`; the Connection Manager validates HTTPS authority, host, credentials, query/fragment, and numeric port range before networking. Malformed-port cases were added to tests; they have not been run.

### Response-header values can carry credentials

**Risk:** Redacting only `Set-Cookie` and authorization header names can still expose secrets in redirect URLs, custom headers, bearer values, JWT-like values, or URL user information.

**Change:** The HTTP adapter now redacts known sensitive header names and applies heuristic sanitization to common token/query/JWT/basic-auth/userinfo patterns. `Location`, `Content-Location`, and `Refresh` are wholly redacted. Tests cover examples but have not been run. This is not comprehensive secret detection; review reports before sharing.

### CI and generated local configuration

**Risk:** Mutable action tags and default workflow permissions increase supply-chain exposure; generated local build/signing files may be accidentally committed.

**Change:** CI actions are pinned to commit SHAs with `contents: read` permission. A repository `.gitignore` excludes Flutter/Gradle output, Python caches, machine-local Android configuration, and signing key files, while intentionally not ignoring `pubspec.lock`. The CI workflow generates a temporary Android scaffold, applies the hardening script, runs tests/analyzer, builds a debug APK, and uploads the APK plus generated lockfile for review. That workflow has not run yet.

## CI verification attempts

The first GitHub Actions run on commit `f32fa91` generated the Android scaffold, applied the native configuration, and resolved dependencies successfully. `flutter analyze` failed, so Flutter tests and APK build were skipped. GitHub check annotations identified deprecated `package:flutter/material.dart` imports in Flutter 3.47+, deprecated `DropdownButtonFormField.value`, and a missing `const`; these were corrected by migrating to `material_ui`, using `initialValue`, and adding `const`. A second CI run on commit `cc3f255` passed scaffold generation, hardening configuration, dependency resolution, and `flutter analyze`, but reported 28 Flutter tests passed and 3 failed; APK build was skipped. Detailed test output could not be retrieved from the current sandbox because GitHub's log archive host is outside its network allowlist. The test wrapper now exposes the captured failure output as a check annotation for the next run. Do not treat either run as a successful test/build.

## Residual risks and release blockers

- Flutter/Dart are unavailable here. `flutter pub get`, `flutter analyze`, `flutter test`, Dart formatting, and Android compilation have **not** run. CI has not run either.
- There is no generated Android Gradle project in this workspace. The CI job is configured to generate and harden a runner-local scaffold; until that job succeeds, no native manifest/Gradle build has been verified or committed.
- Android Keystore behavior, secure-storage backup/restore/key invalidation, and minimum-SDK behavior are unverified. Do not enter production credentials.
- SQLite history is app-private but unencrypted. Save is opt-in and the UI warns about the limitation.
- Provider entries remain guides; credentials are stored locally only and are not used by authenticated connectors.
- GitHub release handling is metadata-only. No asset is downloaded, digest-verified, installed, or executed. A publisher digest is not a signature.
- External tool licenses and Android/device compatibility have not been independently verified.
- No `pubspec.lock` exists yet. Once Flutter is available, resolve dependencies, review the lockfile, and commit it for reproducible app builds before treating CI as repeatable.

## Push guidance

**Not yet ready for a verification-backed push.** First run from `apps/android` on a Flutter-equipped environment:

```sh
flutter pub get
flutter analyze
flutter test
```

Fix all failures, review the generated `pubspec.lock`, and confirm CI passes on this branch. This is the minimum gate for pushing the code changes. Before any release or use of real credentials, also generate the Android project, apply `docs/android-hardening.md`, build a release APK, and verify secure storage on supported Android devices/emulators. A passing Dart test suite alone does not validate Android Keystore or backup behavior.
