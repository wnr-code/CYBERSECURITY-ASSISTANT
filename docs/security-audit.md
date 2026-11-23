# Static Security Audit — Flutter Foundation

- **Review date:** 2026-11-23
- **Review type:** Source-level static review of the current prototype
- **Status:** Findings below were addressed in source; Flutter/Android verification remains incomplete
- **Not a certification:** No Dart/Flutter tests, Android build, device testing, dynamic analysis, or penetration test was available in this environment. Five Python unit tests for the hardening configurator passed locally.

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
