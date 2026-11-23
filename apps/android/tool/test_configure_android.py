import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

from verify_android_splash import verify_sources

from configure_android import (
    configure_gradle,
    configure_manifest,
    configure_project,
    configure_splash_resources,
)


class ConfigureAndroidTests(unittest.TestCase):
    def test_kotlin_gradle_template_gets_minimum_sdk_23(self):
        with tempfile.TemporaryDirectory() as temporary:
            gradle = Path(temporary) / "build.gradle.kts"
            gradle.write_text(
                "android {\n    defaultConfig {\n        minSdk = flutter.minSdkVersion\n    }\n}\n",
                encoding="utf-8",
            )

            configure_gradle(gradle)
            first_result = gradle.read_text(encoding="utf-8")
            configure_gradle(gradle)

            self.assertIn("minSdk = 23", first_result)
            self.assertEqual(gradle.read_text(encoding="utf-8"), first_result)

    def test_groovy_template_raises_but_does_not_lower_a_higher_minimum(self):
        with tempfile.TemporaryDirectory() as temporary:
            gradle = Path(temporary) / "build.gradle"
            gradle.write_text(
                "android {\n    defaultConfig {\n        minSdkVersion 26\n    }\n}\n",
                encoding="utf-8",
            )

            configure_gradle(gradle)

            self.assertIn("minSdkVersion 26", gradle.read_text(encoding="utf-8"))

    def test_configure_raises_a_numeric_minimum_below_23(self):
        with tempfile.TemporaryDirectory() as temporary:
            gradle = Path(temporary) / "build.gradle"
            gradle.write_text(
                "android {\n    defaultConfig {\n        minSdkVersion 21\n    }\n}\n",
                encoding="utf-8",
            )

            configure_gradle(gradle)

            self.assertIn("minSdkVersion 23", gradle.read_text(encoding="utf-8"))

    def test_android_splash_resources_match_brand_on_legacy_and_api_31(self):
        with tempfile.TemporaryDirectory() as temporary:
            android = Path(temporary) / "android"
            configure_splash_resources(android)
            configure_splash_resources(android)

            resource_root = android / "app/src/main/res"
            styles = ET.parse(resource_root / "values-v31/styles.xml").getroot()
            launch_style = next(style for style in styles.findall("style") if style.get("name") == "LaunchTheme")
            items = {item.get("name"): item.text for item in launch_style.findall("item")}
            self.assertTrue(all("{http://schemas.android.com/apk/res/android}name" not in item.attrib for item in launch_style.findall("item")))
            self.assertEqual(items["android:windowSplashScreenBackground"], "@color/startup_navy")
            self.assertEqual(items["android:windowSplashScreenAnimatedIcon"], "@drawable/splash_brand_mark")
            self.assertEqual(items["android:windowSplashScreenBackground"], "@color/startup_navy")
            self.assertEqual(items["android:windowBackground"], "@drawable/launch_background")
            self.assertEqual(launch_style.get("parent"), "@android:style/Theme.Light.NoTitleBar")

            base_styles = ET.parse(resource_root / "values/styles.xml").getroot()
            base_launch = next(style for style in base_styles.findall("style") if style.get("name") == "LaunchTheme")
            base_items = {item.get("name"): item.text for item in base_launch.findall("item")}
            self.assertEqual(base_items["android:windowBackground"], "@drawable/launch_background")
            self.assertTrue((resource_root / "drawable/splash_brand_mark.xml").is_file())
            self.assertTrue((resource_root / "drawable/launch_background.xml").is_file())
            self.assertEqual(len([style for style in styles.findall("style") if style.get("name") == "LaunchTheme"]), 1)

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
            self.assertTrue(all("{http://schemas.android.com/apk/res/android}name" not in item.attrib for style in styles.findall("style") for item in style.findall("item")))

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
            configure_splash_resources(android)
            verify_sources(android)

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

            configure_project(android)

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
            self.assertIn("minSdk = 23", (app / "build.gradle.kts").read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
