import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

from verify_android_splash import _parse_signer_fingerprints, verify_sources

from configure_android import (
    configure_gradle,
    configure_launcher_icon,
    configure_manifest,
    configure_project,
    configure_splash_activity,
    configure_splash_resources,
    configure_trusted_signer_resource,
)


class ConfigureAndroidTests(unittest.TestCase):
    def test_apksigner_fingerprint_parser_normalizes_colon_separated_sha256(self):
        fingerprint = ":".join(["AA"] * 32)
        parsed = _parse_signer_fingerprints(
            f"Signer #1 certificate SHA-256 digest: {fingerprint}\n"
            "Signer #1 certificate SHA-1 digest: AA:BB\n"
        )
        self.assertEqual(parsed, {"aa" * 32})

    def test_trusted_signer_resource_is_validated_and_idempotent(self):
        with tempfile.TemporaryDirectory() as temporary:
            android = Path(temporary) / "android"
            first = "A" * 64
            second = "b" * 64
            configure_trusted_signer_resource(android, f"{first},{second},{first}")
            resource = android / "app/src/main/res/values/trusted_signer.xml"
            parsed = ET.parse(resource).getroot()
            pin = next(node for node in parsed.findall("string") if node.get("name") == "trusted_apk_cert_sha256")
            self.assertEqual(pin.text, f"{first.lower()},{second}")
            before = resource.read_text(encoding="utf-8")
            configure_trusted_signer_resource(android, f"{first},{second},{first}")
            self.assertEqual(resource.read_text(encoding="utf-8"), before)
            with self.assertRaisesRegex(RuntimeError, "64-character SHA-256"):
                configure_trusted_signer_resource(android, "not-a-certificate")

    def test_kotlin_gradle_template_gets_android_10_minimum_sdk_29(self):
        with tempfile.TemporaryDirectory() as temporary:
            gradle = Path(temporary) / "build.gradle.kts"
            gradle.write_text(
                "android {\n    defaultConfig {\n        minSdk = flutter.minSdkVersion\n    }\n}\n",
                encoding="utf-8",
            )

            configure_gradle(gradle)
            first_result = gradle.read_text(encoding="utf-8")
            configure_gradle(gradle)

            self.assertIn("minSdk = 29", first_result)
            self.assertIn("buildFeatures {\n        buildConfig = true\n    }", first_result)
            self.assertEqual(gradle.read_text(encoding="utf-8"), first_result)

    def test_groovy_template_preserves_a_higher_minimum(self):
        with tempfile.TemporaryDirectory() as temporary:
            gradle = Path(temporary) / "build.gradle"
            gradle.write_text(
                "android {\n    defaultConfig {\n        minSdkVersion 33\n    }\n}\n",
                encoding="utf-8",
            )

            configure_gradle(gradle)

            configured = gradle.read_text(encoding="utf-8")
            self.assertIn("minSdkVersion 33", configured)
            self.assertIn("buildFeatures {\n        buildConfig true\n    }", configured)

    def test_configure_raises_a_numeric_minimum_below_android_10(self):
        with tempfile.TemporaryDirectory() as temporary:
            gradle = Path(temporary) / "build.gradle"
            gradle.write_text(
                "android {\n    defaultConfig {\n        minSdkVersion 21\n    }\n}\n",
                encoding="utf-8",
            )

            configure_gradle(gradle)

            self.assertIn("minSdkVersion 29", gradle.read_text(encoding="utf-8"))

    def test_android_splash_resources_match_brand_on_legacy_and_api_31(self):
        with tempfile.TemporaryDirectory() as temporary:
            android = Path(temporary) / "android"
            configure_splash_resources(android)
            configure_splash_resources(android)

            resource_root = android / "app/src/main/res"
            styles = ET.parse(resource_root / "values-v31/styles.xml").getroot()
            launch_style = next(style for style in styles.findall("style") if style.get("name") == "LaunchTheme")
            items = {item.get("name"): item.text for item in launch_style.findall("item")}
            self.assertEqual(items["windowSplashScreenBackground"], "@color/startup_navy")
            self.assertEqual(items["windowSplashScreenAnimatedIcon"], "@drawable/splash_brand_mark")
            self.assertEqual(items["postSplashScreenTheme"], "@style/NormalTheme")
            self.assertEqual(items["android:windowBackground"], "@drawable/launch_background")
            self.assertEqual(launch_style.get("parent"), "Theme.SplashScreen")

            base_styles = ET.parse(resource_root / "values/styles.xml").getroot()
            base_launch = next(style for style in base_styles.findall("style") if style.get("name") == "LaunchTheme")
            base_items = {item.get("name"): item.text for item in base_launch.findall("item")}
            self.assertEqual(base_items["android:windowBackground"], "@drawable/launch_background")
            self.assertTrue((resource_root / "drawable/splash_brand_mark.xml").is_file())
            self.assertTrue((resource_root / "drawable/launch_background.xml").is_file())
            self.assertEqual(len([style for style in styles.findall("style") if style.get("name") == "LaunchTheme"]), 1)

    def test_launcher_icon_installs_selected_brand_for_legacy_and_adaptive_android(self):
        with tempfile.TemporaryDirectory() as temporary:
            android = Path(temporary) / "android"
            configure_launcher_icon(android)
            configure_launcher_icon(android)

            resource_root = android / "app/src/main/res"
            icon_assets = Path(__file__).resolve().parents[1] / "assets/branding/launcher_icons"
            for density in ("mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi"):
                target = resource_root / f"mipmap-{density}/ic_launcher.png"
                source = icon_assets / f"mipmap-{density}/ic_launcher.png"
                self.assertEqual(target.read_bytes(), source.read_bytes())
            foreground = resource_root / "mipmap-xxxhdpi/ic_launcher_foreground.png"
            self.assertEqual(
                foreground.read_bytes(),
                (icon_assets / "mipmap-xxxhdpi/ic_launcher_foreground.png").read_bytes(),
            )
            adaptive = ET.parse(resource_root / "mipmap-anydpi-v26/ic_launcher.xml").getroot()
            self.assertEqual(adaptive.tag, "adaptive-icon")
            drawable_names = {node.get("{http://schemas.android.com/apk/res/android}drawable") for node in adaptive}
            self.assertIn("@color/launcher_background", drawable_names)
            self.assertIn("@mipmap/ic_launcher_foreground", drawable_names)

    def test_splash_config_updates_flutter_scaffold_style_items(self):
        with tempfile.TemporaryDirectory() as temporary:
            android = Path(temporary) / "android"
            values = android / "app/src/main/res/values"
            values.mkdir(parents=True)
            (values / "styles.xml").write_text(
                '<resources><style name="LaunchTheme"><item name="android:windowBackground">old</item></style>'
                '<style name="NormalTheme"><item name="android:windowBackground">old</item></style></resources>',
                encoding="utf-8",
            )

            configure_splash_resources(android)

            styles = ET.parse(values / "styles.xml").getroot()
            launch = next(style for style in styles.findall("style") if style.get("name") == "LaunchTheme")
            background = next(item for item in launch.findall("item") if item.get("name") == "android:windowBackground")
            self.assertEqual(background.text, "@drawable/launch_background")
            self.assertEqual(launch.get("parent"), "Theme.SplashScreen")
            launch_items = {item.get("name"): item.text for item in launch.findall("item")}
            self.assertEqual(launch_items["windowSplashScreenAnimatedIcon"], "@drawable/splash_brand_mark")
            self.assertEqual(launch_items["postSplashScreenTheme"], "@style/NormalTheme")

    def test_native_splash_verifier_requires_a_real_launcher_theme_handoff(self):
        with tempfile.TemporaryDirectory() as temporary:
            android = Path(temporary) / "android"
            app = android / "app"
            main = app / "src/main"
            (main / "res").mkdir(parents=True)
            (main / "AndroidManifest.xml").write_text(
                '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
                '<application><activity android:name=".MainActivity" android:theme="@style/LaunchTheme">'
                '<meta-data android:name="io.flutter.embedding.android.NormalTheme" android:resource="@style/NormalTheme" />'
                '<intent-filter><action android:name="android.intent.action.MAIN" />'
                '<category android:name="android.intent.category.LAUNCHER" /></intent-filter>'
                '</activity></application></manifest>',
                encoding="utf-8",
            )
            (main / "kotlin/org/example/MainActivity.kt").parent.mkdir(parents=True)
            (main / "kotlin/org/example/MainActivity.kt").write_text(
                "package org.example\nimport io.flutter.embedding.android.FlutterActivity\nclass MainActivity : FlutterActivity()\n",
                encoding="utf-8",
            )
            gradle = app / "build.gradle.kts"
            gradle.write_text("android {\n    defaultConfig {\n        minSdk = 29\n    }\n}\n", encoding="utf-8")
            configure_gradle(gradle)
            configure_trusted_signer_resource(android, "a" * 64)
            configure_manifest(main / "AndroidManifest.xml")
            configure_splash_activity(android)
            configure_splash_resources(android)
            configure_launcher_icon(android)
            verify_sources(android)

    def test_java_main_activity_gets_idempotent_native_crash_capture(self):
        with tempfile.TemporaryDirectory() as temporary:
            android = Path(temporary) / "android"
            activity = android / "app/src/main/java/org/example/MainActivity.java"
            activity.parent.mkdir(parents=True)
            activity.write_text(
                "package org.example;\nimport io.flutter.embedding.android.FlutterActivity;\n"
                "public class MainActivity extends FlutterActivity {}\n",
                encoding="utf-8",
            )
            configure_splash_activity(android)
            generated = activity.read_text(encoding="utf-8")
            self.assertIn("installDiagnosticCrashCapture();", generated)
            self.assertIn("pending_native_crash.txt", generated)
            self.assertIn("FileWriter", generated)
            self.assertIn("previous.uncaughtException(thread, error)", generated)
            self.assertIn("safe.length() > 8000", generated)
            self.assertIn("AppIntegrityVerifier.verifyOrThrow(this)", generated)
            self.assertIn("AppIntegrityVerifier.attachChannel(this, flutterEngine)", generated)
            self.assertIn("LocalAiCapabilityProbe.attachChannel(this, flutterEngine)", generated)
            self.assertLess(generated.index("AppIntegrityVerifier.verifyOrThrow(this)"), generated.index("super.onCreate"))
            native_verifier = android / "app/src/main/java/org/example/AppIntegrityVerifier.java"
            self.assertIn("GET_SIGNING_CERTIFICATES", native_verifier.read_text(encoding="utf-8"))
            capability_probe = android / "app/src/main/java/org/example/LocalAiCapabilityProbe.java"
            capability_source = capability_probe.read_text(encoding="utf-8")
            self.assertIn("totalRamBytes", capability_source)
            self.assertIn("availableStorageBytes", capability_source)
            self.assertIn('values.put("runtimeAvailable", false)', capability_source)
            configure_splash_activity(android)
            self.assertEqual(activity.read_text(encoding="utf-8"), generated)

    def test_unknown_gradle_template_fails_closed(self):
        with tempfile.TemporaryDirectory() as temporary:
            gradle = Path(temporary) / "build.gradle.kts"
            gradle.write_text("android { defaultConfig { } }\n", encoding="utf-8")

            with self.assertRaisesRegex(RuntimeError, "minSdk declaration"):
                configure_gradle(gradle)

    def test_manifest_adds_internet_and_disables_cleartext_and_backups(self):
        android_ns = "{http://schemas.android.com/apk/res/android}"
        with tempfile.TemporaryDirectory() as temporary:
            manifest = Path(temporary) / "AndroidManifest.xml"
            manifest.write_text(
                '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
                '<application android:label="Audit test"><activity android:name=".MainActivity">'
                '<intent-filter><action android:name="android.intent.action.MAIN" />'
                '<category android:name="android.intent.category.LAUNCHER" /></intent-filter>'
                '</activity></application></manifest>',
                encoding="utf-8",
            )

            configure_manifest(manifest)
            configure_manifest(manifest)
            root = ET.parse(manifest).getroot()
            application = root.find("application")
            self.assertIsNotNone(application)
            self.assertTrue(
                any(
                    node.get(f"{android_ns}name") == "android.permission.INTERNET"
                    for node in root.findall("uses-permission")
                )
            )
            self.assertEqual(application.get(f"{android_ns}label"), "Cybersecurity Assistant")
            self.assertEqual(application.get(f"{android_ns}icon"), "@mipmap/ic_launcher")
            self.assertEqual(application.get(f"{android_ns}roundIcon"), "@mipmap/ic_launcher")
            launcher = application.find("activity")
            self.assertIsNotNone(launcher)
            self.assertEqual(launcher.get(f"{android_ns}screenOrientation"), "portrait")
            self.assertEqual(launcher.get(f"{android_ns}theme"), "@style/LaunchTheme")
            normal_theme = launcher.find("meta-data")
            self.assertEqual(normal_theme.get(f"{android_ns}resource"), "@style/NormalTheme")
            self.assertEqual(application.get(f"{android_ns}allowBackup"), "false")
            self.assertEqual(application.get(f"{android_ns}usesCleartextTraffic"), "false")
            self.assertEqual(application.get(f"{android_ns}fullBackupContent"), "@xml/backup_rules")
            self.assertEqual(application.get(f"{android_ns}dataExtractionRules"), "@xml/data_extraction_rules")

    def test_project_writes_backup_rules_and_configures_gradle_and_manifest(self):
        with tempfile.TemporaryDirectory() as temporary:
            android = Path(temporary) / "android"
            app = android / "app"
            manifest = app / "src" / "main" / "AndroidManifest.xml"
            manifest.parent.mkdir(parents=True)
            (app / "build.gradle.kts").write_text(
                "android {\n    defaultConfig {\n        minSdk = flutter.minSdkVersion\n    }\n}\n",
                encoding="utf-8",
            )
            manifest.write_text(
                '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
                '<application><activity android:name=".MainActivity"><intent-filter>'
                '<action android:name="android.intent.action.MAIN" />'
                '<category android:name="android.intent.category.LAUNCHER" />'
                '</intent-filter></activity></application></manifest>',
                encoding="utf-8",
            )
            main_activity = app / "src/main/kotlin/org/example/MainActivity.kt"
            main_activity.parent.mkdir(parents=True)
            main_activity.write_text(
                "package org.example\nimport io.flutter.embedding.android.FlutterActivity\nclass MainActivity : FlutterActivity()\n",
                encoding="utf-8",
            )

            configure_project(android)

            generated_activity = main_activity.read_text(encoding="utf-8")
            self.assertIn("installDiagnosticCrashCapture()", generated_activity)
            self.assertIn("pending_native_crash.txt", generated_activity)
            self.assertIn("previous?.uncaughtException(thread, error)", generated_activity)
            self.assertIn(".take(8000)", generated_activity)
            self.assertIn("[path]", generated_activity)
            configure_project(android)
            self.assertEqual(main_activity.read_text(encoding="utf-8"), generated_activity)

            backup_rules = android / "app/src/main/res/xml/backup_rules.xml"
            extraction_rules = android / "app/src/main/res/xml/data_extraction_rules.xml"
            self.assertTrue(backup_rules.is_file())
            self.assertTrue(extraction_rules.is_file())
            self.assertEqual(ET.parse(backup_rules).getroot().tag, "full-backup-content")
            extraction_root = ET.parse(extraction_rules).getroot()
            self.assertEqual(extraction_root.tag, "data-extraction-rules")
            self.assertEqual(
                {section.tag for section in extraction_root},
                {"cloud-backup", "device-transfer"},
            )
            for section in extraction_root:
                self.assertIn(
                    "device_sharedpref",
                    {entry.get("domain") for entry in section.findall("exclude")},
                )
            gradle_text = (app / "build.gradle.kts").read_text(encoding="utf-8")
            self.assertIn("minSdk = 29", gradle_text)
            self.assertIn("androidx.core:core-splashscreen:1.0.1", gradle_text)
            generated_manifest = ET.parse(manifest).getroot()
            generated_application = generated_manifest.find("application")
            self.assertEqual(generated_application.get("{http://schemas.android.com/apk/res/android}icon"), "@mipmap/ic_launcher")
            icon_resources = app / "src/main/res"
            self.assertTrue((icon_resources / "mipmap-anydpi-v26/ic_launcher.xml").is_file())
            self.assertTrue((icon_resources / "mipmap-xxxhdpi/ic_launcher_foreground.png").is_file())
            activity_text = main_activity.read_text(encoding="utf-8")
            self.assertIn("installSplashScreen()", activity_text)
            self.assertLess(activity_text.index("installSplashScreen()"), activity_text.index("super.onCreate"))
            self.assertIn("native:activity-onCreate", activity_text)
            self.assertIn("native:splash-installed", activity_text)
            self.assertIn("ApplicationInfo.FLAG_DEBUGGABLE", activity_text)


if __name__ == "__main__":
    unittest.main()
