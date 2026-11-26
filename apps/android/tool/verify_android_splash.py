#!/usr/bin/env python3
"""Verify native splash wiring in Android sources and the built APK."""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import shutil
import subprocess
import sys

from process_utils import run_bounded
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
    _require(application.get(ANDROID_NS + "icon") == "@mipmap/ic_launcher", "Android application does not use the branded launcher icon")
    resource_root = app / "src/main/res"
    for density in ("mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi"):
        _require((resource_root / f"mipmap-{density}/ic_launcher.png").is_file(), f"Branded legacy launcher icon is missing for {density}")
    adaptive_icon = resource_root / "mipmap-anydpi-v26/ic_launcher.xml"
    _require(adaptive_icon.is_file(), "Android adaptive launcher icon is missing")
    adaptive = ET.parse(adaptive_icon).getroot()
    adaptive_drawables = {node.get(ANDROID_NS + "drawable") for node in adaptive}
    _require("@color/launcher_background" in adaptive_drawables, "Adaptive icon background is missing")
    _require("@mipmap/ic_launcher_foreground" in adaptive_drawables, "Adaptive icon foreground is missing")
    _require((resource_root / "mipmap-xxxhdpi/ic_launcher_foreground.png").is_file(), "Adaptive icon artwork is missing")
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
    install_call = next((call for call in ("installSplashScreen()", "SplashScreen.installSplashScreen(this)") if call in activity_source), None)
    install_index = activity_source.find(install_call) if install_call else -1
    super_index = activity_source.find("super.onCreate")
    _require(install_index >= 0 and super_index > install_index, "AndroidX SplashScreen must be installed before FlutterActivity.onCreate")
    integrity_call = activity_source.find("AppIntegrityVerifier.verifyOrThrow(this)")
    _require(integrity_call >= 0 and super_index > integrity_call, "APK identity verification must run before FlutterActivity starts")
    _require("AppIntegrityVerifier.attachChannel(this, flutterEngine)" in activity_source,
             "Native APK identity channel is not connected to Flutter")
    _require("LocalAiCapabilityProbe.attachChannel(this, flutterEngine)" in activity_source,
             "Local AI device-capability channel is not connected to Flutter")
    capability_sources = list((app / "src/main").rglob("LocalAiCapabilityProbe.kt")) + list((app / "src/main").rglob("LocalAiCapabilityProbe.java"))
    _require(len(capability_sources) == 1, f"Expected one native local AI capability probe, found {len(capability_sources)}")
    capability_source = capability_sources[0].read_text(encoding="utf-8")
    _require("totalRamBytes" in capability_source and "availableStorageBytes" in capability_source and "runtimeAvailable" in capability_source,
             "Local AI device capability probe is missing resource/runtime status fields")
    verifier_sources = list((app / "src/main").rglob("AppIntegrityVerifier.kt")) + list((app / "src/main").rglob("AppIntegrityVerifier.java"))
    _require(len(verifier_sources) == 1, f"Expected one native APK integrity verifier, found {len(verifier_sources)}")
    verifier_source = verifier_sources[0].read_text(encoding="utf-8")
    _require("GET_SIGNING_CERTIFICATES" in verifier_source and "trusted_apk_cert_sha256" in verifier_source,
             "Native APK verifier does not check package signing identity")
    _require("digestApkFiles" in verifier_source and "SHA-256" in verifier_source,
             "Native APK verifier does not hash installed APK components")
    signer_resource = app / "src/main/res/values/trusted_signer.xml"
    _require(signer_resource.is_file() and "trusted_apk_cert_sha256" in signer_resource.read_text(encoding="utf-8"),
             "Trusted APK signer pin resource is missing")
    _require("native:activity-onCreate" in activity_source and "native:splash-installed" in activity_source,
             "Debug cold-start timestamps are missing from MainActivity")
    _require("removeSplashScreen" not in activity_source and "FlutterNativeSplash.remove" not in activity_source,
             "Launcher explicitly removes the splash before Flutter's first frame")
    gradle_files = list((app).glob("build.gradle")) + list((app).glob("build.gradle.kts"))
    _require(len(gradle_files) == 1 and "androidx.core:core-splashscreen:1.0.1" in gradle_files[0].read_text(encoding="utf-8"),
             "AndroidX core-splashscreen dependency is missing")

    resource = app / "src/main/res"
    legacy_styles = ET.parse(resource / "values/styles.xml").getroot()
    launch_legacy = next((node for node in legacy_styles.findall("style") if node.get("name") == "LaunchTheme"), None)
    normal = next((node for node in legacy_styles.findall("style") if node.get("name") == "NormalTheme"), None)
    _require(launch_legacy is not None and normal is not None, "Legacy LaunchTheme/NormalTheme is missing")
    legacy_items = {node.get("name"): (node.text or "").strip() for node in launch_legacy.findall("item")}
    normal_items = {node.get("name"): (node.text or "").strip() for node in normal.findall("item")}
    _require(launch_legacy.get("parent") == "Theme.SplashScreen", "Legacy LaunchTheme must inherit AndroidX Theme.SplashScreen")
    _require(legacy_items.get("windowSplashScreenBackground") == "@color/startup_navy", "Legacy SplashScreen background is missing")
    _require(legacy_items.get("windowSplashScreenAnimatedIcon") == "@drawable/splash_brand_mark", "Legacy SplashScreen logo is missing")
    _require(legacy_items.get("postSplashScreenTheme") == "@style/NormalTheme", "SplashScreen does not hand off to NormalTheme")
    _require(legacy_items.get("android:windowBackground") == "@drawable/launch_background", "Pre-Android 12 launch background is not branded")
    _require(normal_items.get("android:windowBackground") == "@drawable/startup_window_background", "Post-launch window background is not the branded fallback color")

    v31_styles = ET.parse(resource / "values-v31/styles.xml").getroot()
    launch_v31 = next((node for node in v31_styles.findall("style") if node.get("name") == "LaunchTheme"), None)
    _require(launch_v31 is not None, "Android 12+ LaunchTheme is missing")
    _require(launch_v31.get("parent") == "Theme.SplashScreen", "Android 12+ LaunchTheme must inherit AndroidX Theme.SplashScreen")
    v31_items = {node.get("name"): (node.text or "").strip() for node in launch_v31.findall("item")}
    _require(v31_items.get("android:windowBackground") == "@drawable/launch_background", "Android 12+ launch fallback background is missing")
    _require(v31_items.get("windowSplashScreenBackground") == "@color/startup_navy", "Android 12+ splash background is missing")
    _require(v31_items.get("windowSplashScreenAnimatedIcon") == "@drawable/splash_brand_mark", "Android 12+ splash logo is missing")
    _require(v31_items.get("postSplashScreenTheme") == "@style/NormalTheme", "Android 12+ post-splash theme is not configured")

    icon = resource / "drawable/splash_brand_mark.xml"
    _require(icon.is_file(), "Native splash vector logo is missing")
    launch_background = ET.parse(resource / "drawable/launch_background.xml").getroot()
    drawable_values = [value for node in launch_background.iter() for value in node.attrib.values()]
    _require("@drawable/splash_brand_mark" in drawable_values, "Legacy launch drawable does not include the brand logo")
    _require("@color/startup_navy" in drawable_values, "Legacy launch drawable does not include the brand background")
    print("Generated Android source wiring verified: branded legacy/adaptive launcher icons, splash, pre-Flutter signer gate, integrity and Local AI capability channels, device-resource probe, SHA-256 verifier source, trusted-signer resource, branded API 23+ resources, and Flutter NormalTheme handoff. This is not runtime APK or inference verification.")


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


def _find_apksigner() -> str:
    found = shutil.which("apksigner")
    if found:
        return found
    sdk_roots = {Path(value) for value in (os.environ.get("ANDROID_HOME"), os.environ.get("ANDROID_SDK_ROOT")) if value}
    for sdk in sdk_roots:
        candidates = sorted((sdk / "build-tools").glob("*/apksigner"), reverse=True)
        if candidates:
            return str(candidates[0])
    raise RuntimeError("Android apksigner tool not found; cannot verify the built APK signer")


def _trusted_signer_pins(android_root: Path) -> set[str]:
    resource = android_root / "app/src/main/res/values/trusted_signer.xml"
    if not resource.is_file():
        raise RuntimeError(f"Trusted signer resource not found: {resource}")
    root = ET.parse(resource).getroot()
    node = next((entry for entry in root.findall("string") if entry.get("name") == "trusted_apk_cert_sha256"), None)
    raw = (node.text or "").strip() if node is not None else ""
    pins = {value.strip().lower() for value in raw.split(",") if value.strip()}
    _require(all(re.fullmatch(r"[0-9a-f]{64}", value) for value in pins), "Trusted signer resource contains an invalid SHA-256 fingerprint")
    return pins


def _parse_signer_fingerprints(apksigner_output: str) -> set[str]:
    fingerprints: set[str] = set()
    for line in apksigner_output.splitlines():
        if not re.search(r"(?i)\bsigner\s*#?\d+\b", line):
            continue
        match = re.search(r"(?i)sha-?256(?:\s+digest)?\s*[:=]\s*([0-9a-fA-F: \t-]+)", line)
        if match is None:
            continue
        normalized = re.sub(r"[^0-9a-f]", "", match.group(1).lower())
        if re.fullmatch(r"[0-9a-f]{64}", normalized):
            fingerprints.add(normalized)
    return fingerprints


def _validate_apk_signers(signature_output: str, trusted_pins: set[str]) -> str:
    actual_signers = _parse_signer_fingerprints(signature_output)
    if trusted_pins:
        if len(actual_signers) != 1:
            digest_lines = [
                line.strip()
                for line in signature_output.splitlines()
                if re.search(r"(?i)sha-?256", line)
            ]
            diagnostic = "; ".join(digest_lines[:4]) or "apksigner emitted no SHA-256 digest line"
            raise RuntimeError(
                "Expected exactly one APK signer certificate digest from apksigner; "
                f"parsed {len(actual_signers)}. Output: {diagnostic[:500]}"
            )
        _require(actual_signers.issubset(trusted_pins), "Built APK signer does not match the configured trusted developer certificate")
        return f"configured trusted signer(s) verified: {', '.join(sorted(actual_signers))}"

    if len(actual_signers) == 1:
        signer_detail = f"signer {next(iter(actual_signers))}"
    else:
        signer_detail = "signer fingerprint unavailable from apksigner"
    return f"APK signature valid but no trusted release signer pin is configured ({signer_detail}); not release-trusted"


def verify_apk(apk: Path, android_root: Path) -> None:
    _require(apk.is_file(), f"Built APK not found: {apk}")
    with zipfile.ZipFile(apk) as package:
        names = set(package.namelist())
        _require("AndroidManifest.xml" in names, "APK has no compiled Android manifest")
        _require("resources.arsc" in names, "APK has no compiled Android resource table")

    aapt = _find_aapt()
    manifest_result = run_bounded([aapt, "dump", "xmltree", str(apk), "AndroidManifest.xml"], check=True, capture_output=True, text=True, timeout=30)
    resources_result = run_bounded([aapt, "dump", "--values", "resources", str(apk)], check=True, capture_output=True, text=True, timeout=30)
    manifest_dump = manifest_result.stdout
    resources_dump = resources_result.stdout
    _require("android.intent.action.MAIN" in manifest_dump and "android.intent.category.LAUNCHER" in manifest_dump,
             "Compiled APK manifest has no MAIN/LAUNCHER entry point")
    _require("MainActivity" in manifest_dump, "Compiled APK launcher activity is missing")
    theme_reference = re.search(r"android:theme[^\n]*?\s*=\s*@0x([0-9a-fA-F]+)", manifest_dump)
    _require(theme_reference is not None, "Compiled APK launcher activity has no resolved theme resource")
    launch_theme_id = theme_reference.group(1).lower()
    _require(launch_theme_id.startswith("7f"), "Compiled APK launcher theme does not point to an app resource")
    for marker in ("style/LaunchTheme", "style/NormalTheme", "style/Theme.SplashScreen", "drawable/splash_brand_mark",
                   "drawable/launch_background", "drawable/startup_window_background", "color/startup_navy",
                   "windowSplashScreenBackground", "windowSplashScreenAnimatedIcon", "postSplashScreenTheme",
                   "string/trusted_apk_cert_sha256"):
        _require(marker in resources_dump, f"Compiled APK is missing required Android resource: {marker}")

    apksigner = _find_apksigner()
    signature = run_bounded([apksigner, "verify", "--verbose", "--print-certs", str(apk)], check=True, capture_output=True, text=True, timeout=30)
    signature_output = signature.stdout + signature.stderr
    signer_result = _validate_apk_signers(signature_output, _trusted_signer_pins(android_root))

    digest = hashlib.sha256()
    with apk.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    print(f"Built APK structure verified: {apk}; size={apk.stat().st_size} bytes; sha256={digest.hexdigest()}; {signer_result}.")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--android-root", type=Path, default=Path("android"))
    parser.add_argument("--apk", type=Path)
    arguments = parser.parse_args()
    try:
        verify_sources(arguments.android_root)
        if arguments.apk:
            verify_apk(arguments.apk, arguments.android_root)
    except (OSError, RuntimeError, ET.ParseError, zipfile.BadZipFile, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        message = f"Android verification failed: {error}"
        print(message, file=sys.stderr)
        if os.environ.get("GITHUB_ACTIONS"):
            escaped = message.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
            print(f"::error title=Native splash APK verification::{escaped}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
