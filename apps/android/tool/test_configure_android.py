import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

from configure_android import (
    configure_gradle,
    configure_manifest,
    configure_project,
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
                '<application android:label="Audit test" /></manifest>',
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
                '<application /></manifest>',
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
