# Android hardening checklist (apply after native scaffold generation)

The workspace currently has Flutter source but no generated `apps/android/android` project. `apps/android/tool/configure_android.py` applies the baseline below after `flutter create` (API 23 minimum, INTERNET permission, cleartext disabled, and backup disabled/excluded). GitHub Actions is configured to generate a temporary scaffold and apply the script. Neither the native output nor its Gradle build has been verified yet; this file remains the review checklist, not an applied local manifest.

## Required before connecting credentials or releasing an APK

- **Minimum Android SDK:** set the app minimum SDK to at least API 23 for the current `flutter_secure_storage` Android cipher defaults. Confirm the plugin's requirement again when resolving dependencies.
- **Network permission:** add `android.permission.INTERNET` for the local DNS/TLS/HTTPS checks and GitHub release metadata request.
- **Disable cleartext traffic:** keep HTTP cleartext disabled (`android:usesCleartextTraffic="false"`) and do not add trust-all certificate callbacks or custom permissive network-security configuration.
- **Backups:** disable Android app backup for this early build (`android:allowBackup="false"`) or add explicit backup/data-extraction rules excluding secure-storage preferences and sensitive scan history. Do not assume an app-private file is automatically excluded from cloud/device transfer.
- **Credential handling:** never add API keys to the manifest, Gradle files, `BuildConfig`, assets, logs, analytics, crash reports, or the SQLite results database.
- **Credential Keystore behavior:** the secure-store wrapper relies on `flutter_secure_storage`'s Android Keystore-backed defaults. Verify key creation, read/write/delete, app upgrade, restore/backup behavior, and key invalidation on physical devices/emulators before enabling credential entry.
- **APK signing is separate:** CI only produces a debug APK with a debug signing identity. No production signing key is configured or stored in this repository. Configure release signing through user-controlled CI secrets or a local secure keystore before any release; never commit signing material.
- **Build validation:** after generating the platform project, run `flutter pub get`, `flutter analyze`, `flutter test`, build the debug APK, and test on supported Android API levels. A signed release build requires the separate signing setup above.

A provider credential-entry dialog and `SecureCredentialStore` wrapper now exist, but neither has been runtime-tested on Android. The UI stores credentials only; no provider makes authenticated requests. Do not enter production credentials until the native scaffold is configured and every relevant item above has been tested.
