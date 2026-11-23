# Android app foundation

This directory contains the first Flutter app foundation for Cybersecurity Assistant:

- Animated local-history startup splash; dashboard and standalone-mode indicator.
- Five stable primary destinations with borderless transparent bottom navigation on compact layouts, a centered secondary AI shortcut, and a NavigationRail on wide layouts. Reports remains a primary destination; the AI screen is still an unconnected placeholder.
- Searchable, category-filtered Tool Registry with version, compatibility, license-status, dependency, and permission metadata.
- Allowlisted GitHub latest-release metadata viewer with constrained URL validation and publisher digest display; it does not download or execute assets.
- Executable P0 DNS, TLS certificate, and HTTP response-header adapters; common cookie, authentication, token, secret, and API-key-like response headers are redacted before results are shown or exported.
- Registry-ID-only orchestration (no free-form shell), explicit target confirmation, narrow target validation, and a result marker recording that the self-attestation gate was accepted. The marker is not proof of authorization.
- Local response analyzer, session history, user-confirmed JSON report copy, session clearing, and opt-in on-device SQLite result storage with a bounded history.
- Assistant UI placeholder (no model/provider connected).
- Connection Manager prototype with an unauthenticated HTTPS reachability check, searchable provider guidance, and credential storage controls for API-key/scoped-token providers. Saved credentials are not used by a connector.
- Widget and unit tests covering navigation, policy validation, provider/tool registries, orchestration guards, GitHub metadata parsing, report JSON, SQLite round-trips, secure-store namespacing/validation, provider credential entry/status/delete flow with a fake backend, response-header secret redaction, history limits, and finding ordering; Python unit tests cover the generated-Android hardening configurator and analyzer diagnostic parser.

The built-in checks are deliberately limited: DNS resolution, one TLS connection on port 443, and one GET request to the HTTPS root path. Redirects are not followed and response bodies are not read. Header findings are heuristic and context-dependent (for example, an API may not need browser-oriented headers). Common secret-bearing response-header names are redacted, and common bearer/basic credentials, JWT-like strings, sensitive query parameters, and URL userinfo are sanitized from other values. This is heuristic; provider-specific encodings may not be recognized. Review exported reports before sharing. The checks do not exploit vulnerabilities, crawl pages, or run arbitrary commands. They are not a substitute for a full security assessment. Only assess targets you own or are explicitly authorized to test. The checkbox is a user-consent gate, not independent proof of authorization.

The Connection Manager test requires an in-app self-attestation that the user owns or is authorized to test the entered endpoint; editing the endpoint clears that confirmation. It then sends one unauthenticated HTTPS GET, does not follow redirects, sends no credentials, and discards the response body. Any HTTP response counts as reachable; it does not authenticate against a provider or establish that an integration is correctly configured. The checkbox is not independent proof of authorization. Do not use URLs containing secrets.

The provider details UI can store user-entered API keys or scoped tokens through a namespaced wrapper around `flutter_secure_storage`; no provider connector sends those credentials anywhere. This storage path and its Android Keystore behavior/native configuration have not been runtime-tested. Do not enter production secrets until those checks pass. Results remain in memory unless the user explicitly saves an individual completed check to SQLite; saved results are stored in the app-private database, are not encrypted, and are not synced. Unsaved session results are discarded when the app process ends. Provider-specific health checks, authenticated connectors, and AI model/provider orchestration remain future work.

## Run when Flutter is installed

This app currently requires Flutter >=3.47.0 and Dart >=3.13 because it uses the standalone `material_ui` package. The repository contains Dart/Flutter source and package metadata but no committed/generated Android Gradle wrapper or platform project. This coding environment does not have a local Flutter/Android toolchain; GitHub Actions generates the Android scaffold temporarily and runs hardening, dependency resolution, analyzer, tests, APK build, and artifact upload. From this directory on a machine with Flutter and Android SDK installed, generate the platform scaffold, apply the hardening script, then run:

```sh
flutter create --platforms=android --project-name cybersecurity_assistant --org org.cybersecurityassistant .
python3 -m unittest discover -s tool -p 'test_*.py' -v
python3 tool/configure_android.py
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter run
```

The latest application-code CI verification before this documentation-only update passed analysis, Flutter tests, and debug APK build on [Actions run 45273085060](https://github.com/wnr-code/CYBERSECURITY-ASSISTANT/actions/runs/45273085060). The generated native project and lockfile are not committed. No emulator or physical-device test has been performed. Follow the [manual device test guide](../../docs/android-device-testing.md) before treating the MVP as device-verified or entering real credentials. AI/provider connections, the Embedded Runtime, internal package management, and a bundled Termux environment are not implemented; see the [AI Engine blueprint](../../docs/ai-cybersecurity-expert-engine.md) and [Embedded Runtime blueprint](../../docs/embedded-runtime-implementation.md).
