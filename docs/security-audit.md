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

## Release/MVP gates still open

1. Download the artifact from GitHub, record the APK's exact size and SHA-256, and inspect package metadata/merged permissions/target SDK/ABIs.
2. Complete the manual device checklist on at least one real Android device; use an emulator/API level as a second environment when available.
3. Verify network-loss errors/timeouts, target consent/validation, SQLite save/load/restart/delete, and secure storage behavior on Android.
4. Do not use production credentials or distribute as a release until device checks pass and user-controlled release signing is configured.
