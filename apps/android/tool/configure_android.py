#!/usr/bin/env python3
"""Apply the prototype's Android security baseline to a Flutter scaffold.

Run only after `flutter create --platforms=android ...` has generated the
Android project. The script deliberately fails when the generated Gradle
layout is unfamiliar rather than silently leaving an unsafe default.
"""

from __future__ import annotations

import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ANDROID_NS = "http://schemas.android.com/apk/res/android"
TOOLS_NS = "http://schemas.android.com/tools"
ET.register_namespace("android", ANDROID_NS)
ET.register_namespace("tools", TOOLS_NS)

KOTLIN_MIN_SDK = re.compile(
    r"(?m)^(\s*minSdk\s*=\s*)(flutter\.minSdkVersion|\d+)(\s*(?://.*)?$)"
)
GROOVY_MIN_SDK = re.compile(
    r"(?m)^(\s*minSdkVersion\s*(?:=\s*)?)(flutter\.minSdkVersion|\d+)(\s*(?://.*)?$)"
)


def _minimum_sdk(match: re.Match[str]) -> str:
    value = match.group(2)
    sdk = 23 if value == "flutter.minSdkVersion" else max(23, int(value))
    return f"{match.group(1)}{sdk}{match.group(3)}"


def configure_gradle(gradle_file: Path) -> None:
    source = gradle_file.read_text(encoding="utf-8")
    matches = list(KOTLIN_MIN_SDK.finditer(source))
    pattern = KOTLIN_MIN_SDK
    if not matches:
        matches = list(GROOVY_MIN_SDK.finditer(source))
        pattern = GROOVY_MIN_SDK
    if len(matches) != 1:
        raise RuntimeError(
            f"Expected exactly one recognizable minSdk declaration in {gradle_file}; "
            f"found {len(matches)}. Review this Flutter template manually."
        )
    configured = pattern.sub(_minimum_sdk, source, count=1)
    gradle_file.write_text(configured, encoding="utf-8")


def _android_attribute(name: str) -> str:
    return f"{{{ANDROID_NS}}}{name}"


def _write_backup_rules(android_root: Path) -> None:
    xml_root = android_root / "app" / "src" / "main" / "res" / "xml"
    xml_root.mkdir(parents=True, exist_ok=True)

    backup_domains = ("root", "file", "database", "sharedpref", "external")
    extraction_domains = backup_domains + (
        "device_root",
        "device_file",
        "device_database",
        "device_sharedpref",
    )
    full_backup = ET.Element("full-backup-content")
    for domain in backup_domains:
        ET.SubElement(full_backup, "exclude", {"domain": domain, "path": "."})
    ET.indent(full_backup, space="  ")
    ET.ElementTree(full_backup).write(
        xml_root / "backup_rules.xml", encoding="utf-8", xml_declaration=True
    )

    extraction = ET.Element("data-extraction-rules")
    for destination in ("cloud-backup", "device-transfer"):
        section = ET.SubElement(extraction, destination)
        for domain in extraction_domains:
            ET.SubElement(section, "exclude", {"domain": domain, "path": "."})
    ET.indent(extraction, space="  ")
    ET.ElementTree(extraction).write(
        xml_root / "data_extraction_rules.xml", encoding="utf-8", xml_declaration=True
    )


def configure_manifest(manifest_file: Path) -> None:
    tree = ET.parse(manifest_file)
    manifest = tree.getroot()
    if manifest.tag != "manifest":
        raise RuntimeError(f"Unexpected Android manifest root in {manifest_file}.")

    permission_name = _android_attribute("name")
    internet_permission = "android.permission.INTERNET"
    if not any(
        node.get(permission_name) == internet_permission
        for node in manifest.findall("uses-permission")
    ):
        permission = ET.Element("uses-permission", {permission_name: internet_permission})
        manifest.insert(0, permission)

    application = manifest.find("application")
    if application is None:
        raise RuntimeError(f"No <application> element found in {manifest_file}.")
    application.set(_android_attribute("usesCleartextTraffic"), "false")
    application.set(_android_attribute("allowBackup"), "false")
    application.set(_android_attribute("fullBackupContent"), "@xml/backup_rules")
    application.set(_android_attribute("dataExtractionRules"), "@xml/data_extraction_rules")

    ET.indent(tree, space="  ")
    tree.write(manifest_file, encoding="utf-8", xml_declaration=True)


def configure_project(android_root: Path) -> None:
    app_root = android_root / "app"
    gradle_candidates = [app_root / "build.gradle.kts", app_root / "build.gradle"]
    gradle_files = [path for path in gradle_candidates if path.is_file()]
    if len(gradle_files) != 1:
        raise RuntimeError(
            f"Expected one app Gradle file in {app_root}; found {len(gradle_files)}."
        )
    manifest_file = app_root / "src" / "main" / "AndroidManifest.xml"
    if not manifest_file.is_file():
        raise RuntimeError(f"Android manifest not found: {manifest_file}")

    configure_gradle(gradle_files[0])
    configure_manifest(manifest_file)
    _write_backup_rules(android_root)


def main() -> int:
    project_root = Path(__file__).resolve().parents[1]
    android_root = project_root / "android"
    if not android_root.is_dir():
        print(
            "Android scaffold is missing; run flutter create --platforms=android first.",
            file=sys.stderr,
        )
        return 2
    try:
        configure_project(android_root)
    except (OSError, ET.ParseError, RuntimeError) as error:
        print(f"Android hardening configuration failed: {error}", file=sys.stderr)
        return 1
    print("Configured minSdk >= 23, INTERNET, HTTPS-only traffic, and backup exclusions.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
