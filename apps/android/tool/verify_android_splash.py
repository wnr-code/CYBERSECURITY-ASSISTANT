#!/usr/bin/env python3
"""Verify native splash wiring in Android sources and the built APK."""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import zipfile
import xml.etree.ElementTree as ET
from pathlib import Path

ANDROID_NS = "{http://schemas.android.com/apk/res/android}"


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def verify_sources(android_root: Path) -> None:
    app = android_root / "app"
    manifest_file = app / "src/main/AndroidManifest.xml"
    _require(manifest_file.is_file(), f"Missing Android manifest: {manifest_file}")
    manifest = ET.parse(manifest_file).getroot()
    application = manifest.find("application")
    _require(application is not None, "Android manifest has no application element")
    launchers = []
    for activity in application.findall("activity"):
        actions = [node.get(ANDROID_NS + "name") for node in activity.findall("intent-filter/action")]
        categories = [node.get(ANDROID_NS + "name") for node in activity.findall("intent-filter/category")]
        if "android.intent.action.MAIN" in actions and "android.intent.category.LAUNCHER" in categories:
            launchers.append(activity)
    _require(len(launchers) == 1, f"Expected one MAIN/LAUNCHER activity, found {len(launchers)}")
    launcher = launchers[0]
    _require(launcher.get(ANDROID_NS + "theme") == "@style/LaunchTheme", "Launcher is not using @style/LaunchTheme")
    metadata = {
        node.get(ANDROID_NS + "name"): node.get(ANDROID_NS + "resource")
        for node in launcher.findall("meta-data")
    }
    _require(
        metadata.get("io.flutter.embedding.android.NormalTheme") == "@style/NormalTheme",
        "FlutterActivity NormalTheme metadata is missing or incorrect",
    )

    main_activity = str(launcher.get(ANDROID_NS + "name", "")).rsplit(".", 1)[-1]
    sources = list((app / "src/main").rglob(f"{main_activity}.kt")) + list((app / "src/main").rglob(f"{main_activity}.java"))
    _require(len(sources) == 1, f"Expected one {main_activity} source file, found {len(sources)}")
    activity_source = sources[0].read_text(encoding="utf-8")
    _require(bool(re.search(r"extends\s+FlutterActivity|:\s*FlutterActivity\b", activity_source)), "Launcher does not extend FlutterActivity")
    _require("removeSplashScreen" not in activity_source and "FlutterNativeSplash.remove" not in activity_source,
             "Launcher explicitly removes the splash before Flutter's first frame")

    resource = app / "src/main/res"
    legacy_styles = ET.parse(resource / "values/styles.xml").getroot()
    launch_legacy = next((node for node in legacy_styles.findall("style") if node.get("name") == "LaunchTheme"), None)
    normal = next((node for node in legacy_styles.findall("style") if node.get("name") == "NormalTheme"), None)
    _require(launch_legacy is not None and normal is not None, "Legacy LaunchTheme/NormalTheme is missing")
    legacy_items = {node.get("name"): (node.text or "").strip() for node in launch_legacy.findall("item")}
    normal_items = {node.get("name"): (node.text or "").strip() for node in normal.findall("item")}
    _require(legacy_items.get("android:windowBackground") == "@drawable/launch_background", "Pre-Android 12 launch background is not branded")
    _require(normal_items.get("android:windowBackground") == "@drawable/startup_window_background", "Post-launch window background is not the branded fallback color")

    v31_styles = ET.parse(resource / "values-v31/styles.xml").getroot()
    launch_v31 = next((node for node in v31_styles.findall("style") if node.get("name") == "LaunchTheme"), None)
    _require(launch_v31 is not None, "Android 12+ LaunchTheme is missing")
    _require(launch_v31.get("parent") == "@android:style/Theme.Light.NoTitleBar", "Android 12+ LaunchTheme must use the platform theme without AndroidX-only dependencies")
    v31_items = {node.get("name"): (node.text or "").strip() for node in launch_v31.findall("item")}
    _require(v31_items.get("android:windowBackground") == "@drawable/launch_background", "Android 12+ launch fallback background is missing")
    _require(v31_items.get("android:windowSplashScreenBackground") == "@color/startup_navy", "Android 12+ splash background is missing")
    _require(v31_items.get("android:windowSplashScreenAnimatedIcon") == "@drawable/splash_brand_mark", "Android 12+ splash logo is missing")
    _require("android:postSplashScreenTheme" not in v31_items, "Unexpected AndroidX-only postSplashScreenTheme attribute")

    icon = resource / "drawable/splash_brand_mark.xml"
    _require(icon.is_file(), "Native splash vector logo is missing")
    launch_background = ET.parse(resource / "drawable/launch_background.xml").getroot()
    drawable_values = [value for node in launch_background.iter() for value in node.attrib.values()]
    _require("@drawable/splash_brand_mark" in drawable_values, "Legacy launch drawable does not include the brand logo")
    _require("@color/startup_navy" in drawable_values, "Legacy launch drawable does not include the brand background")
    print("Native splash source wiring verified: launcher theme, Flutter first-frame handoff, API 23-30 fallback and API 31+ SplashScreen attributes/logo.")


def _find_aapt() -> str:
    found = shutil.which("aapt")
    if found:
        return found
    sdk_roots = {Path(value) for value in (os.environ.get("ANDROID_HOME"), os.environ.get("ANDROID_SDK_ROOT")) if value}
    for sdk in sdk_roots:
        candidates = sorted((sdk / "build-tools").glob("*/aapt"), reverse=True)
        if candidates:
            return str(candidates[0])
    raise RuntimeError("Android aapt tool not found; cannot inspect the compiled APK")


def verify_apk(apk: Path) -> None:
    _require(apk.is_file(), f"Built APK not found: {apk}")
    with zipfile.ZipFile(apk) as package:
        names = set(package.namelist())
        _require("AndroidManifest.xml" in names, "APK has no compiled Android manifest")
        _require("resources.arsc" in names, "APK has no compiled Android resource table")

    aapt = _find_aapt()
    manifest_result = subprocess.run([aapt, "dump", "xmltree", str(apk), "AndroidManifest.xml"], check=True, capture_output=True, text=True)
    resources_result = subprocess.run([aapt, "dump", "resources", str(apk)], check=True, capture_output=True, text=True)
    manifest_dump = manifest_result.stdout
    resources_dump = resources_result.stdout
    _require("android.intent.action.MAIN" in manifest_dump and "android.intent.category.LAUNCHER" in manifest_dump,
             "Compiled APK manifest has no MAIN/LAUNCHER entry point")
    _require("MainActivity" in manifest_dump, "Compiled APK launcher activity is missing")
    theme_reference = re.search(r"android:theme[^\n]*?\s*=\s*@0x([0-9a-fA-F]+)", manifest_dump)
    _require(theme_reference is not None, "Compiled APK launcher activity has no resolved theme resource")
    launch_theme_id = theme_reference.group(1).lower()
    _require(launch_theme_id.startswith("7f"), "Compiled APK launcher theme does not point to an app resource")
    for marker in ("style/LaunchTheme", "style/NormalTheme", "drawable/splash_brand_mark", "drawable/launch_background",
                   "windowSplashScreenBackground", "windowSplashScreenAnimatedIcon"):
        _require(marker in resources_dump, f"Compiled APK is missing native splash resource: {marker}")
    print(f"Built APK native splash verified: {apk} (compiled manifest and resource table inspected with aapt).")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--android-root", type=Path, default=Path("android"))
    parser.add_argument("--apk", type=Path)
    arguments = parser.parse_args()
    try:
        verify_sources(arguments.android_root)
        if arguments.apk:
            verify_apk(arguments.apk)
    except (OSError, RuntimeError, ET.ParseError, zipfile.BadZipFile, subprocess.CalledProcessError) as error:
        message = f"Android splash verification failed: {error}"
        print(message, file=sys.stderr)
        if os.environ.get("GITHUB_ACTIONS"):
            escaped = message.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
            print(f"::error title=Native splash APK verification::{escaped}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
