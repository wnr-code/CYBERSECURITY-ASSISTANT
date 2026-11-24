# Android Device Testing & MVP Stabilization

Status: **manual device testing is pending**. Do not treat CI build success as a physical-device or emulator test.

## Candidate debug APK

- GitHub Actions run: [45242263160](https://github.com/wnr-code/CYBERSECURITY-ASSISTANT/actions/runs/45242263160)
- Commit: `77f54f5f89194b8aea2349810ce125d02727fb17`
- Run result: success, including scaffold generation, Android hardening, dependency resolution, `flutter analyze`, `flutter test`, debug APK build, and artifact upload.
- Artifact: `cybersecurity-assistant-android-verification` (available, not expired when checked; workflow retention is 7 days).
- Artifact archive size reported by GitHub: **90,401,423 bytes** (about **86.2 MiB**). This is the ZIP artifact size, which contains the APK and generated `pubspec.lock`; it is **not** the APK's individual file size.
- APK path/name configured in CI: `apps/android/build/app/outputs/flutter-apk/app-debug.apk` (`app-debug.apk`). The APK's individual byte size could not be inspected in this sandbox: GitHub's download redirects to a blob-storage host outside the sandbox network allowlist, and the artifact download attempt failed. Download the artifact from the run page's **Artifacts** section (or run `gh run download 45242263160 --name cybersecurity-assistant-android-verification` in an environment that can reach GitHub's artifact storage), unzip it, then record the APK's exact size and SHA-256 before installing it.

## Compatibility and permissions review

The CI workflow generates a temporary Android project and applies `apps/android/tool/configure_android.py` before building. The script enforces **minSdk >= 29 (Android 10)**—Android 13 is not required—adds `android.permission.INTERNET`, disables cleartext traffic and Android backup, and writes backup/data-extraction exclusions. The CI build proves that this generated scaffold and Gradle configuration compile; no generated native project is checked into this repository. A Redmi Note 11 Pro meets the stated compatibility target if its installed Android version is 10 or newer; the actual handset and MIUI/HyperOS behavior still need physical-device verification.

`INTERNET` is a normal install-time permission, so Android should not show a runtime permission dialog for it. No camera, microphone, contacts, location, or external-storage permission is intentionally requested by the app. SQLite uses app-private storage. The exact generated `targetSdk`, merged manifest, APK ABIs, install behavior on real devices, and secure-storage/Keystore behavior remain unverified here. Verify these from the downloaded APK/device before considering any release or entering real credentials. The APK is **debug-signed**, not a production release.

No Flutter, Dart, `adb`, or Android emulator executable is installed in the coding environment; no emulator was available for this pass.

## Manual test setup

Use a non-production Android device or emulator, and only endpoints you own or have explicit permission to test. Do not enter real API keys. Use a controlled HTTPS test host for DNS/TLS/headers and a non-sensitive hostname for persisted test history. The deterministic unit/integration fixture tests exercise the assessment pipeline without network access; they do not replace a device-side TLS/network check.

Record before starting:

| Field | Value |
| --- | --- |
| APK filename | `app-debug.apk` |
| APK size / SHA-256 | Fill after downloading and unzipping |
| Device make/model | |
| Android version / API level | |
| APK install source | |
| Wi-Fi/mobile/airplane mode | |
| Result date, tester, notes | |

If using ADB: `adb install -r app-debug.apk`. Record Android version with `adb shell getprop ro.build.version.release` and API level with `adb shell getprop ro.build.version.sdk`. If installation is performed by opening the downloaded APK, grant “install unknown apps” only to the chosen file manager/browser when Android asks, then revoke that setting after installation.

## Checklist

Mark each item **PASS / FAIL / BLOCKED / NOT RUN** and include device/API level plus a short note. Current status for every manual case below is **NOT RUN**.

### 1. Installation, native splash, and first launch

- [ ] Install APK without package/signature/parse error. On cold launch, confirm the Android native splash appears immediately with the navy background and shield/lock mark; verify the app label is **Cybersecurity Assistant**.
- [ ] On Android 12+ (API 31+), verify the native SplashScreen API artwork; on Android 10–11 (API 29–30), verify the legacy launch-window fallback uses the same navy and shield mark.
- [ ] Confirm there is no white/black blank frame or visible mismatched icon between native splash, Flutter splash, and Dashboard. Check cold launch after force-stop as well as warm relaunch.
- [ ] Confirm the Flutter splash is the first Flutter frame and fades/scales to Dashboard without waiting for SQLite. If the first frame is ready quickly, the splash may be brief; the app must not add a minimum-duration delay.
- [ ] Simulate an unavailable/slow local history database if safely possible. Confirm the Dashboard appears while the query is pending, saved-history indicators update when available, and Reports can retry history after an error.
- [ ] Manually dispatch the `Flutter quality checks` workflow when emulator cold-start evidence is needed. The CI `android-cold-start-captures` artifact from API 35 and API 30 contains timestamped screenshots, Dart/native startup markers, and logcat from force-stop + launcher cold starts. Compare the frames for native brand, Flutter animation, and dashboard. Push-triggered CI intentionally skips emulator boot because recent hosted-runner attempts timed out before capture; that is not a cold-start pass.
- [ ] Review the CI `Verify native splash in built APK` step: it checks the compiled APK manifest and resource table, not just the generator output. Emulator results are not a substitute for testing the affected physical handset if its OEM/Android version differs.
- [ ] Confirm the app remains in standalone/local-first mode and no login, developer-owned server, or API key is required for built-in checks.
- [ ] Confirm Android displays no unexpected runtime permission prompt. `INTERNET` is expected in the manifest, not as a runtime dialog.
- [ ] Force-stop and relaunch; app returns without crash or a setup loop.

### 2. Navigation and UI stability

- [ ] Verify the compact bottom bar has four primary destinations—Home, Tools, Reports, Settings—and exactly one centered secondary Chat AI shortcut (five visible actions total). Connections must open from Settings, not as a bottom destination.
- [ ] Verify the floating bar has fully rounded ends, stays above the Android system navigation area, and does not cover content. Try a small phone viewport and a larger tablet/emulator viewport if available.
- [ ] Confirm functional icons and provider-specific brand marks appear in the provider catalog; provider marks are visual identifiers only and do not indicate active connections.
- [ ] Scroll long content; open and close tool/provider dialogs using both close/cancel controls and system Back.
- [ ] Exercise keyboard input, hide keyboard, rotate the device and confirm the app remains portrait-locked, background/foreground the app, and use system Back; UI remains usable.
- [ ] Confirm no crash, blank screen, overflow, or stuck loading indicator during navigation and settings-to-connections routing.

### 3. DNS Lookup

- [ ] With connectivity enabled, select DNS Lookup, enter an owned/authorized valid hostname, accept the authorization checkbox, and run. Expect one or more device-resolver addresses and a completed result.
- [ ] Try a malformed hostname/IP and an empty target. Expect a clear validation error and no result/network dispatch.
- [ ] Change the target after accepting authorization. Expect authorization to clear; do not allow a run until it is accepted again.
- [ ] Confirm details do not claim DNSSEC or exhaustive record enumeration; this adapter uses the device resolver for A/AAAA lookup.

### 4. TLS Certificate Inspection

- [ ] On an authorized HTTPS host with a valid certificate on port 443, expect successful handshake and subject, issuer, validity dates, remaining days, and device trust status.
- [ ] On an owned test endpoint with an invalid/expired/untrusted certificate, expect a safe TLS validation error; no certificate trust bypass.
- [ ] Try a host on a non-443 port or with a query/fragment; expect rejection. A path is accepted and preserved as assessment scope, though TLS itself only connects to host port 443.
- [ ] Check timeout/offline behavior. The tool uses an 8-second timeout; allow for device/network scheduling before declaring a hang.

### 5. HTTP Security Header Checker

- [ ] On an authorized HTTPS host, enter the exact allowed URL including its path (for example, `https://api.your-domain.example/v1/health`, without query/fragment), then expect one GET to that same path, HTTP status, response headers, and heuristic findings for selected missing headers. The tool does not rewrite the path to `/`.
- [ ] Confirm redirects are reported but **not followed**, response bodies are not displayed, at most 32 KiB is inspected, and a normal HTTP response is treated as reachable. The request has an 8-second overall limit.
- [ ] Use an owned test endpoint with test-only `Set-Cookie`, authorization, token-like, or sensitive query/header values; verify displayed/exportable values are redacted where supported. Do not use real secrets. Redaction is heuristic, not comprehensive.
- [ ] Treat missing CSP/HSTS/etc. as context-dependent review prompts, not proof of a vulnerability.

### 6. Authorization and URL policy

- [ ] Before confirmation, a network check cannot proceed; accept the exact self-attestation text only for a host you are authorized to test.
- [ ] Edit the target after confirmation. Expect the checkbox to clear and previous output to be discarded.
- [ ] Confirm `http://`, embedded user/password, query string, fragment, non-443 port, malformed port, malformed numeric IPv4/IP shorthand, and empty input are rejected. An authorized HTTPS path is accepted and preserved.
- [ ] Confirm the standard HTTPS origin (or bare hostname normalized to HTTPS) is accepted. The checkbox is a consent gate, not independent proof of authorization.

### 7. Owner-run HTTPS API path procedure

1. Deploy or select a **non-production HTTPS endpoint you own or are explicitly authorized to assess**. A safe read-only health/API route is preferred; do not use endpoints that trigger mutations. Use port 443 and a valid trusted certificate.
2. In Assessment, enter the exact URL including the path (for example, `https://api.your-domain.example/v1/health`). Query strings and fragments are intentionally rejected. Select DNS, TLS, and HTTP checks, accept the authorization attestation, and leave **Allow local/private network targets** off for public hosts.
3. Run the assessment once. Each check executes sequentially and has its own Completed/Failed outcome. DNS reports device-resolver A/AAAA addresses; TLS reports device trust/certificate metadata; HTTP issues one GET to the exact path, does not follow redirects, and inspects at most 32 KiB for up to eight seconds. Response body values are not included in the result; sensitive-looking JSON fields are reported by redacted field path.
4. Only for an owned/authorized lab endpoint reachable at loopback/private/link-local addresses, explicitly enable **Allow local/private network targets**. This is off by default and applies to TLS/HTTP connections. Known cloud metadata hostnames/addresses are hard-blocked even when the option is enabled; do not attempt to probe them.
5. Save/export only non-sensitive evidence. Do not use real bearer tokens, cookies, secrets, or production customer responses. The request has no query string and sends no authorization header.

Interpretation and evidence labels:

- **Confirmed** means a specific security condition is directly demonstrated with evidence. The current heuristic rules do not assert a confirmed vulnerability.
- **Potential** is a rule-based indicator requiring owner review (for example, a missing header or a field name such as `access_token`); it does not establish exploitability or broken access control.
- **Informational** records an observation without asserting a vulnerability (for example, a non-public DNS answer or a server technology header).
- **Error** means the check could not complete (policy block, timeout, DNS/connectivity/TLS failure). It is not a security finding and must not be treated as a clean/pass result.

The app labels findings with confidence and severity separately. Severity is a prioritization hint, not proof. A completed response analyzer summarizes only evidence from completed checks; it does not turn potential heuristics into confirmed issues.

### 8. SQLite save, load, delete, persistence

- [ ] Run one harmless check on an authorized test host and choose **Save to session** in the result dialog. On Home, open that recent session result, choose **Save on device**, and explicitly confirm the disclosure. Expect it under **Saved on this device** after **Load history** or **Refresh**.
- [ ] Tap a saved result; verify target, time, summary, details, and findings can be read.
- [ ] Force-stop/close the app (do not clear app data or uninstall), relaunch, choose **Load history**; the saved row remains.
- [ ] Use **Clear local history**, confirm deletion, reload; expect “No locally saved checks.”
- [ ] Separately verify the session list is in-memory only and is cleared by process restart or its session-clear action; saved SQLite history should remain until explicitly deleted.
- [ ] Do not save sensitive production target information during testing. SQLite history is app-private but not encrypted or synced. Uninstalling/clearing app data is destructive and is not a substitute for the in-app delete check.

### 9. Network loss and errors

- [ ] Start with airplane mode/no network and run DNS; expect a bounded, readable failure rather than a crash or infinite spinner.
- [ ] With network disabled, run TLS and header checks; expect a bounded connection/TLS error, responsive Cancel/Back behavior after completion, and no leaked raw exception/secret.
- [ ] Restore connectivity and repeat a valid check; app recovers without restart.
- [ ] Test a controlled slow/unreachable endpoint where safe; confirm the 8-second timeout path and UI returns to idle.

### 10. Market and package lifecycle (offline example)

- [ ] Open Tools → **Open Market**. Confirm the page is separate from the primary four-destination navigation and shows the six categories.
- [ ] Inspect one catalog-only Runtime/Plugin/AI entry. Confirm it is marked incompatible/unsupported or metadata-only and cannot be installed or run.
- [ ] Open the **Security Assessment Evidence Guide** knowledge pack, review its CC BY-SA 4.0 license and installation guide, then accept the license. Confirm installation reaches **Installed** after Downloaded/Verifying and the registry count updates. The bundled demonstration package reads a local app asset; it makes no network request.
- [ ] Close/reopen Market and confirm the app-private registry still marks the package installed. Its JSON is data only and must not be executed or loaded as code.
- [ ] Uninstall the example and confirm the installed status and stored package file are removed. This is an app-private package fixture, not a device-wide app uninstall.
- [ ] Do not treat a matching SHA-256 from a catalog as publisher authentication; external signing keys and remote catalog management are not configured in this foundation.

## Issue log and exit criteria

| ID | Case | Device/API | Expected | Actual | Severity | Repro steps | Fixed in commit |
| --- | --- | --- | --- | --- | --- | --- | --- |
| — | No on-device or emulator run performed in this environment | — | — | BLOCKED: no Flutter/ADB/emulator toolchain or device | — | — | — |

MVP device stabilization is not complete until all applicable high-priority cases pass on at least one real Android device and one emulator/API level if available. Keep the release blocked for a crash, failed install, authorization bypass, cleartext/trust bypass, loss/corruption of saved history, or an unbounded network operation. Never report a physical-device pass based on CI alone.
