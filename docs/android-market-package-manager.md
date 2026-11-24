# Android Market & Package Manager Foundation

This milestone adds a dedicated Market page and a local package-management boundary. It is intentionally a small foundation, not an embedded tool runtime or executable plugin loader.

## Implemented now

- Six catalog categories: Security Tools, Runtime, Plugins, AI Models, Knowledge Packs, and Cloud/API Connectors.
- A typed `MarketPackage` metadata model covering source, license, version, size, platform/ABI, dependencies, runtime requirements, permissions, compatibility, payload type, guide, checksum, and optional signature.
- A searchable, filterable Market page opened from Tools (the existing four-destination bottom navigation remains unchanged).
- `PackageDownloadManager`, configurable HTTPS download hosts, a catalog-source interface, bounded HTTPS downloads, redirect refusal, resolver preflight, public-address checks, and pinned socket connections. No source is enabled for remote downloads by default.
- `PackageRegistry`, `PackageVerifier`, `PackageInstaller`, `UninstallManager`, `DependencyManager`, `CompatibilityChecker`, and `UpdateManager`.
- Per-package states: Available, Downloading, Downloaded, Verifying, Installed, Update Available, Incompatible, and Failed.
- A safe offline example Knowledge Pack is downloaded from the Flutter asset bundle, SHA-256 checked, parsed as a schema/ID/version-matched JSON document, and stored under app-private support storage. It can be reloaded from the local registry, updated in a fixture, and uninstalled.
- License acceptance precedes download. Required dependencies, supported platform/ABI, runtime availability, maximum package size, checksum, optional signature verifier, and data-only payload policy are checked before a package is marked installed.

## Security model and limitations

Market does not execute scripts, load Dart/native code, run APKs, unpack archives, or grant permissions from package metadata. At present only validated JSON data and opaque data payloads can be installed. Archive/native executable package types remain blocked. A checksum detects content mismatch against the active catalog entry; it does not authenticate a catalog publisher. A package signature is rejected unless a signature verifier is explicitly configured. The example package uses a bundled catalog entry, with no network request.

`MarketCatalogSource`, `MarketSourceConfig`, and trusted-download-host configuration are extension points for BYOI repositories and storage. The app does not require a developer-owned backend, Cloudflare, Firebase, S3, API key, account, or domain. The UI does not yet offer a source-management form or remote catalog-signature/key enrollment. No remote catalog is enabled by default.

The current catalog has six small examples/placeholders, not a broad tool store. Runtime, plugin, model, and authenticated Connector packages are catalog metadata only or explicitly incompatible/unsupported. A package becoming Installed means its verified data was stored in the Package Registry; it does **not** mean a tool adapter, runtime, plugin, AI model, or connector has become executable or connected to Tool Registry/Assessment/Terminal.

Android App Bundle output is supported by the standard Flutter/Gradle project scaffold, but this milestone does not configure release signing or validate Play Store delivery. ABI-specific package metadata and compatibility checks exist; separate ABI APK publishing and size benchmarking are not yet enabled. The bundled knowledge fixture is intentionally tiny; large models and tools are not embedded in the APK.

## Fixture tests

Run on a Flutter toolchain:

```sh
cd apps/android
flutter pub get
flutter analyze
flutter test
```

`test/package_manager_test.dart` uses byte fixtures and a temporary app-support directory; it makes no network requests. It covers successful download→checksum verification→JSON validation→installation→registry reload, checksum failure, payload identity mismatch, blocked executable payload, missing dependencies, license refusal, failed download, version update, cleanup, and uninstall. Widget tests cover the dedicated Market page and truthful catalog placeholders. These tests validate local package lifecycle logic, not a remote repository, hardware-specific ABI, or production signature key.
