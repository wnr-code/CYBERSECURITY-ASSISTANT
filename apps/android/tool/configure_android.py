#!/usr/bin/env python3
"""Apply Android startup branding and security defaults to a Flutter scaffold.

Run only after `flutter create --platforms=android ...` has generated the
Android project. The script deliberately fails when key manifest or Gradle
structure is unfamiliar rather than silently leaving an unsafe default.
"""

from __future__ import annotations

import os
import re
import shutil
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ANDROID_NS = "http://schemas.android.com/apk/res/android"
TOOLS_NS = "http://schemas.android.com/tools"
SPLASH_NAVY = "#030817"
ELECTRIC_BLUE = "#168DFF"
BRAND_WHITE = "#EAF8FF"
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
    # API 29 is Android 10, the minimum supported platform for this app.
    sdk = 29 if value == "flutter.minSdkVersion" else max(29, int(value))
    return f"{match.group(1)}{sdk}{match.group(3)}"


def _enable_build_config(source: str, gradle_file: Path) -> str:
    kotlin_dsl = gradle_file.suffix == ".kts"
    setting = "buildConfig = true" if kotlin_dsl else "buildConfig true"
    setting_pattern = re.compile(r"(?m)^(\s*)buildConfig\s*(?:=\s*)?(true|false)\s*(?://.*)?$")
    settings = list(setting_pattern.finditer(source))
    if len(settings) > 1:
        raise RuntimeError(f"Expected at most one buildConfig feature setting in {gradle_file}.")
    if settings:
        match = settings[0]
        return source[:match.start()] + f"{match.group(1)}{setting}" + source[match.end():]

    android = re.search(r"(?m)^([ \t]*)android\s*\{", source)
    if android is None:
        raise RuntimeError(f"Could not find Android Gradle configuration in {gradle_file}.")
    opening = source.find("{", android.start())
    depth = 1
    closing = None
    for index in range(opening + 1, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                closing = index
                break
    if closing is None:
        raise RuntimeError(f"Unclosed Android Gradle configuration in {gradle_file}.")

    android_indent = android.group(1)
    feature_indent = android_indent + "    "
    block = source[opening + 1:closing]
    features = re.search(r"(?m)^([ \t]*)buildFeatures\s*\{", block)
    if features:
        insert_at = opening + 1 + features.end()
        return source[:insert_at] + f"\n{features.group(1)}    {setting}" + source[insert_at:]

    feature_block = f"\n{feature_indent}buildFeatures {{\n{feature_indent}    {setting}\n{feature_indent}}}\n{android_indent}"
    return source[:closing] + feature_block + source[closing:]


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
    splash_dependency = "androidx.core:core-splashscreen:1.0.1"
    if splash_dependency not in configured:
        dependency_block = re.search(r"(?m)^(\s*)dependencies\s*\{", configured)
        declaration = 'implementation("androidx.core:core-splashscreen:1.0.1")'
        if dependency_block:
            insertion = dependency_block.end()
            indent = dependency_block.group(1) + "    "
            configured = configured[:insertion] + f"\n{indent}{declaration}" + configured[insertion:]
        else:
            configured = configured.rstrip() + f"\n\ndependencies {{\n    {declaration}\n}}\n"
    configured = _enable_build_config(configured, gradle_file)
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


def _set_style_item(style: ET.Element, name: str, value: str) -> None:
    # Android style item names are plain XML attributes (e.g. name="android:windowBackground"),
    # not android-namespaced attributes. Using android:name makes AAPT reject the resource.
    item = next((node for node in style.findall("item") if node.get("name") == name), None)
    if item is None:
        item = ET.SubElement(style, "item", {"name": name})
    item.text = value


def _ensure_style(resources: ET.Element, name: str, parent: str) -> ET.Element:
    style = next((node for node in resources.findall("style") if node.get("name") == name), None)
    if style is None:
        style = ET.SubElement(resources, "style", {"name": name})
    style.set("parent", parent)
    return style


def _write_brand_vector(drawable_root: Path) -> None:
    vector = drawable_root / "splash_brand_mark.xml"
    vector.write_text(
        f'''<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp" android:height="108dp"
    android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="{ELECTRIC_BLUE}"
        android:pathData="M12,2.5L3.5,6v5.9c0,4.8 3.5,9.1 8.5,10.6 5,-1.5 8.5,-5.8 8.5,-10.6V6L12,2.5z" />
    <path android:fillColor="{BRAND_WHITE}" android:pathData="M8,11h8v6H8z" />
    <path android:fillColor="#00000000" android:strokeColor="{BRAND_WHITE}"
        android:strokeWidth="1.8" android:strokeLineCap="round" android:strokeLineJoin="round"
        android:pathData="M9,11V8.5a3,3 0 0,1 6,0V11" />
</vector>
''',
        encoding="utf-8",
    )


def configure_launcher_icon(android_root: Path, icon_assets: Path | None = None) -> None:
    """Install selected app artwork as legacy density icons and an adaptive icon."""
    assets = icon_assets or Path(__file__).resolve().parents[1] / "assets" / "branding" / "launcher_icons"
    resource_root = android_root / "app" / "src" / "main" / "res"
    densities = ("mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi")
    expected = [assets / f"mipmap-{density}" / "ic_launcher.png" for density in densities]
    expected.append(assets / "mipmap-xxxhdpi" / "ic_launcher_foreground.png")
    missing = [str(path) for path in expected if not path.is_file()]
    if missing:
        raise RuntimeError("Selected launcher icon assets are missing: " + ", ".join(missing))

    for density in densities:
        target = resource_root / f"mipmap-{density}"
        target.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(assets / f"mipmap-{density}" / "ic_launcher.png", target / "ic_launcher.png")
    foreground_target = resource_root / "mipmap-xxxhdpi" / "ic_launcher_foreground.png"
    shutil.copyfile(assets / "mipmap-xxxhdpi" / "ic_launcher_foreground.png", foreground_target)

    adaptive_root = resource_root / "mipmap-anydpi-v26"
    adaptive_root.mkdir(parents=True, exist_ok=True)
    (adaptive_root / "ic_launcher.xml").write_text(
        '''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
''',
        encoding="utf-8",
    )


def configure_splash_resources(android_root: Path) -> None:
    """Install a matching legacy window background and Android 12+ splash theme."""
    resource_root = android_root / "app" / "src" / "main" / "res"
    values_root = resource_root / "values"
    values_v31_root = resource_root / "values-v31"
    drawable_root = resource_root / "drawable"
    for directory in (values_root, values_v31_root, drawable_root):
        directory.mkdir(parents=True, exist_ok=True)

    colors_file = values_root / "colors.xml"
    colors = ET.parse(colors_file).getroot() if colors_file.exists() else ET.Element("resources")
    if colors.tag != "resources":
        raise RuntimeError(f"Unexpected Android colors resource root in {colors_file}.")
    for name, value in (("startup_navy", SPLASH_NAVY), ("launcher_background", SPLASH_NAVY)):
        color = next((node for node in colors.findall("color") if node.get("name") == name), None)
        if color is None:
            color = ET.SubElement(colors, "color", {"name": name})
        color.text = value
    ET.indent(colors, space="    ")
    ET.ElementTree(colors).write(colors_file, encoding="utf-8", xml_declaration=True)

    _write_brand_vector(drawable_root)
    (drawable_root / "launch_background.xml").write_text(
        '''<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="@color/startup_navy" />
    <item android:gravity="center" android:drawable="@drawable/splash_brand_mark" />
</layer-list>
''',
        encoding="utf-8",
    )
    (drawable_root / "startup_window_background.xml").write_text(
        f'''<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <solid android:color="{SPLASH_NAVY}" />
</shape>
''',
        encoding="utf-8",
    )

    base_styles_file = values_root / "styles.xml"
    base_styles = ET.parse(base_styles_file).getroot() if base_styles_file.exists() else ET.Element("resources")
    if base_styles.tag != "resources":
        raise RuntimeError(f"Unexpected Android styles resource root in {base_styles_file}.")
    launch_style = _ensure_style(base_styles, "LaunchTheme", "Theme.SplashScreen")
    _set_style_item(launch_style, "windowSplashScreenBackground", "@color/startup_navy")
    _set_style_item(launch_style, "windowSplashScreenAnimatedIcon", "@drawable/splash_brand_mark")
    _set_style_item(launch_style, "postSplashScreenTheme", "@style/NormalTheme")
    _set_style_item(launch_style, "android:windowBackground", "@drawable/launch_background")
    _set_style_item(launch_style, "android:statusBarColor", "@color/startup_navy")
    _set_style_item(launch_style, "android:navigationBarColor", "@color/startup_navy")
    _set_style_item(launch_style, "android:windowLightStatusBar", "false")
    normal_style = _ensure_style(base_styles, "NormalTheme", "@android:style/Theme.Light.NoTitleBar")
    _set_style_item(normal_style, "android:windowBackground", "@drawable/startup_window_background")
    _set_style_item(normal_style, "android:statusBarColor", "@color/startup_navy")
    _set_style_item(normal_style, "android:navigationBarColor", "@color/startup_navy")
    _set_style_item(normal_style, "android:windowLightStatusBar", "false")
    ET.indent(base_styles, space="    ")
    ET.ElementTree(base_styles).write(base_styles_file, encoding="utf-8", xml_declaration=True)

    v31_styles_file = values_v31_root / "styles.xml"
    v31_styles = ET.parse(v31_styles_file).getroot() if v31_styles_file.exists() else ET.Element("resources")
    if v31_styles.tag != "resources":
        raise RuntimeError(f"Unexpected Android API 31 styles resource root in {v31_styles_file}.")
    launch_v31 = _ensure_style(v31_styles, "LaunchTheme", "Theme.SplashScreen")
    _set_style_item(launch_v31, "windowSplashScreenBackground", "@color/startup_navy")
    _set_style_item(launch_v31, "windowSplashScreenAnimatedIcon", "@drawable/splash_brand_mark")
    _set_style_item(launch_v31, "postSplashScreenTheme", "@style/NormalTheme")
    _set_style_item(launch_v31, "android:windowBackground", "@drawable/launch_background")
    _set_style_item(launch_v31, "android:statusBarColor", "@color/startup_navy")
    _set_style_item(launch_v31, "android:navigationBarColor", "@color/startup_navy")
    _set_style_item(launch_v31, "android:windowLightStatusBar", "false")
    _set_style_item(launch_v31, "android:windowLightNavigationBar", "false")
    ET.indent(v31_styles, space="    ")
    ET.ElementTree(v31_styles).write(v31_styles_file, encoding="utf-8", xml_declaration=True)


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
    application.set(_android_attribute("label"), "Cybersecurity Assistant")
    application.set(_android_attribute("icon"), "@mipmap/ic_launcher")
    application.set(_android_attribute("roundIcon"), "@mipmap/ic_launcher")
    application.set(_android_attribute("usesCleartextTraffic"), "false")
    application.set(_android_attribute("allowBackup"), "false")
    application.set(_android_attribute("fullBackupContent"), "@xml/backup_rules")
    application.set(_android_attribute("dataExtractionRules"), "@xml/data_extraction_rules")

    launcher_activities = []
    for activity in application.findall("activity"):
        has_main_action = any(
            action.get(permission_name) == "android.intent.action.MAIN"
            for intent_filter in activity.findall("intent-filter")
            for action in intent_filter.findall("action")
        )
        has_launcher_category = any(
            category.get(permission_name) == "android.intent.category.LAUNCHER"
            for intent_filter in activity.findall("intent-filter")
            for category in intent_filter.findall("category")
        )
        if has_main_action and has_launcher_category:
            launcher_activities.append(activity)
    if len(launcher_activities) != 1:
        raise RuntimeError(
            f"Expected one MAIN/LAUNCHER activity in {manifest_file}; "
            f"found {len(launcher_activities)}."
        )
    launcher = launcher_activities[0]
    launcher.set(_android_attribute("screenOrientation"), "portrait")
    launcher.set(_android_attribute("theme"), "@style/LaunchTheme")

    normal_theme_name = "io.flutter.embedding.android.NormalTheme"
    normal_theme = next(
        (
            node
            for node in launcher.findall("meta-data")
            if node.get(permission_name) == normal_theme_name
        ),
        None,
    )
    if normal_theme is None:
        normal_theme = ET.SubElement(launcher, "meta-data")
    normal_theme.set(permission_name, normal_theme_name)
    normal_theme.set(_android_attribute("resource"), "@style/NormalTheme")

    ET.indent(tree, space="  ")
    tree.write(manifest_file, encoding="utf-8", xml_declaration=True)


def configure_trusted_signer_resource(android_root: Path, trusted_signers: str | None = None) -> None:
    """Write a public SHA-256 signer pin; release builds refuse to start without one."""
    raw = os.environ.get("TRUSTED_APK_CERT_SHA256", "") if trusted_signers is None else trusted_signers
    pins = [value.strip().lower() for value in raw.split(",") if value.strip()]
    if any(not re.fullmatch(r"[0-9a-f]{64}", value) for value in pins):
        raise RuntimeError("TRUSTED_APK_CERT_SHA256 must contain one or more comma-separated 64-character SHA-256 fingerprints.")
    normalized = ",".join(sorted(set(pins)))
    values_root = android_root / "app" / "src" / "main" / "res" / "values"
    values_root.mkdir(parents=True, exist_ok=True)
    resource_file = values_root / "trusted_signer.xml"
    resources = ET.parse(resource_file).getroot() if resource_file.exists() else ET.Element("resources")
    if resources.tag != "resources":
        raise RuntimeError(f"Unexpected signer-pin resource root in {resource_file}.")
    pin = next((node for node in resources.findall("string") if node.get("name") == "trusted_apk_cert_sha256"), None)
    if pin is None:
        pin = ET.SubElement(resources, "string", {"name": "trusted_apk_cert_sha256", "translatable": "false"})
    pin.text = normalized
    ET.indent(resources, space="    ")
    ET.ElementTree(resources).write(resource_file, encoding="utf-8", xml_declaration=True)


def _configure_native_apk_integrity(activity_file: Path, android_root: Path) -> None:
    source = activity_file.read_text(encoding="utf-8")
    is_kotlin = activity_file.suffix == ".kt"
    package_match = re.search(r"(?m)^package\s+([\w.]+)\s*;?\s*$", source)
    if package_match is None:
        raise RuntimeError(f"No native package declaration found in {activity_file}.")
    package_name = package_match.group(1)
    source_dir = android_root / "app" / "src" / "main" / ("kotlin" if is_kotlin else "java")
    verifier_file = source_dir.joinpath(*package_name.split("."), f"AppIntegrityVerifier.{activity_file.suffix[1:]}")
    template_file = Path(__file__).resolve().parent / "native" / f"AppIntegrityVerifier.{activity_file.suffix[1:]}"
    if not template_file.is_file():
        raise RuntimeError(f"Native APK integrity verifier template is missing: {template_file}")
    verifier = template_file.read_text(encoding="utf-8").replace("__ANDROID_PACKAGE__", package_name)
    verifier_file.parent.mkdir(parents=True, exist_ok=True)
    if verifier_file.exists() and verifier_file.read_text(encoding="utf-8") != verifier:
        raise RuntimeError(f"Refusing to overwrite an unrecognized native verifier: {verifier_file}")
    verifier_file.write_text(verifier, encoding="utf-8")

    verify_call = "AppIntegrityVerifier.verifyOrThrow(this)"
    if verify_call not in source:
        splash_pattern = r"(?m)^(\s*)installSplashScreen\(\)\s*$" if is_kotlin else r"(?m)^(\s*)SplashScreen\.installSplashScreen\(this\);\s*$"
        source, count = re.subn(splash_pattern, lambda match: f"{match.group(1)}{verify_call}\n{match.group(0)}", source, count=1)
        if count != 1:
            raise RuntimeError(f"Could not place the APK identity check before Flutter starts in {activity_file}.")

    channel_call = "AppIntegrityVerifier.attachChannel(this, flutterEngine)"
    if channel_call not in source:
        import_line = "import io.flutter.embedding.engine.FlutterEngine"
        if is_kotlin:
            if import_line not in source:
                source = source[:package_match.end()] + f"\n{import_line}\n" + source[package_match.end():]
            if "override fun configureFlutterEngine" in source:
                pattern = r"(?m)^(\s*)super\.configureFlutterEngine\(flutterEngine\)\s*$"
                source, count = re.subn(pattern, lambda match: f"{match.group(0)}\n{match.group(1)}{channel_call}", source, count=1)
                if count != 1:
                    raise RuntimeError(f"Could not attach integrity channel in {activity_file}.")
            else:
                class_end = source.rfind("}")
                if class_end < 0:
                    raise RuntimeError(f"No MainActivity class body found in {activity_file}.")
                method = (
                    "\n\n    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {\n"
                    "        super.configureFlutterEngine(flutterEngine)\n"
                    f"        {channel_call}\n"
                    "    }\n"
                )
                source = source[:class_end] + method + source[class_end:]
        else:
            java_import = "import io.flutter.embedding.engine.FlutterEngine;"
            if java_import not in source:
                source = source[:package_match.end()] + f"\n{java_import}\n" + source[package_match.end():]
            if "configureFlutterEngine(FlutterEngine flutterEngine)" in source:
                pattern = r"(?m)^(\s*)super\.configureFlutterEngine\(flutterEngine\);\s*$"
                source, count = re.subn(pattern, lambda match: f"{match.group(0)}\n{match.group(1)}{channel_call};", source, count=1)
                if count != 1:
                    raise RuntimeError(f"Could not attach integrity channel in {activity_file}.")
            else:
                class_end = source.rfind("}")
                if class_end < 0:
                    raise RuntimeError(f"No MainActivity class body found in {activity_file}.")
                method = (
                    "\n\n    @Override\n"
                    "    public void configureFlutterEngine(FlutterEngine flutterEngine) {\n"
                    "        super.configureFlutterEngine(flutterEngine);\n"
                    f"        {channel_call};\n"
                    "    }\n"
                )
                source = source[:class_end] + method + source[class_end:]
    capability_template = Path(__file__).resolve().parent / "native" / f"LocalAiCapabilityProbe.{activity_file.suffix[1:]}"
    if not capability_template.is_file():
        raise RuntimeError(f"Local AI capability probe template is missing: {capability_template}")
    capability_file = source_dir.joinpath(*package_name.split("."), f"LocalAiCapabilityProbe.{activity_file.suffix[1:]}")
    capability_source = capability_template.read_text(encoding="utf-8").replace("__ANDROID_PACKAGE__", package_name)
    if capability_file.exists() and capability_file.read_text(encoding="utf-8") != capability_source:
        raise RuntimeError(f"Refusing to overwrite an unrecognized local AI capability probe: {capability_file}")
    capability_file.write_text(capability_source, encoding="utf-8")

    capability_call = "LocalAiCapabilityProbe.attachChannel(this, flutterEngine)"
    if capability_call not in source:
        pattern = r"(?m)^(\s*)AppIntegrityVerifier\.attachChannel\(this, flutterEngine\);?\s*$"
        terminator = ";" if not is_kotlin else ""
        source, count = re.subn(
            pattern,
            lambda match: f"{match.group(0)}\n{match.group(1)}{capability_call}{terminator}",
            source,
            count=1,
        )
        if count != 1:
            raise RuntimeError(f"Could not attach Local AI device-capability reporting in {activity_file}.")
    activity_file.write_text(source, encoding="utf-8")


def configure_splash_activity(android_root: Path) -> None:
    """Install AndroidX SplashScreen before FlutterActivity initializes its view."""
    app_root = android_root / "app" / "src" / "main"
    candidates = list(app_root.rglob("MainActivity.kt")) + list(app_root.rglob("MainActivity.java"))
    if len(candidates) != 1:
        raise RuntimeError(f"Expected one generated MainActivity source; found {len(candidates)}.")
    activity_file = candidates[0]
    source = activity_file.read_text(encoding="utf-8")
    install_calls = ("installSplashScreen()", "SplashScreen.installSplashScreen(this)")
    existing_call = next((call for call in install_calls if call in source), None)
    if existing_call:
        if source.index(existing_call) > source.find("super.onCreate"):
            raise RuntimeError("SplashScreen installation must run before super.onCreate().")
        _configure_native_crash_capture(activity_file)
        _configure_native_apk_integrity(activity_file, android_root)
        return

    if activity_file.suffix == ".kt":
        package_line = re.search(r"(?m)^package\s+[\w.]+\s*$", source)
        if package_line is None:
            raise RuntimeError(f"No Kotlin package declaration found in {activity_file}.")
        imports = "\nimport android.content.pm.ApplicationInfo\nimport android.os.Bundle\nimport android.util.Log\nimport androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen\n"
        source = source[:package_line.end()] + imports + source[package_line.end():]
        declaration = re.compile(r"class\s+MainActivity\s*:\s*FlutterActivity\(\)\s*(?:\{\s*\})?")
        replacement = (
            "class MainActivity : FlutterActivity() {\n"
            "    override fun onCreate(savedInstanceState: Bundle?) {\n"
            "        val isDebuggable = applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0\n"
            "        if (isDebuggable) Log.i(\"AppStartup\", \"native:activity-onCreate\")\n"
            "        installSplashScreen()\n"
            "        if (isDebuggable) Log.i(\"AppStartup\", \"native:splash-installed\")\n"
            "        super.onCreate(savedInstanceState)\n"
            "    }\n"
            "}"
        )
    else:
        package_line = re.search(r"(?m)^package\s+[\w.]+\s*;?\s*$", source)
        if package_line is None:
            raise RuntimeError(f"No Java package declaration found in {activity_file}.")
        imports = "\nimport android.content.pm.ApplicationInfo;\nimport android.os.Bundle;\nimport android.util.Log;\nimport androidx.core.splashscreen.SplashScreen;\n"
        source = source[:package_line.end()] + imports + source[package_line.end():]
        declaration = re.compile(r"public\s+class\s+MainActivity\s+extends\s+FlutterActivity\s*\{\s*\}")
        replacement = (
            "public class MainActivity extends FlutterActivity {\n"
            "    @Override\n"
            "    protected void onCreate(Bundle savedInstanceState) {\n"
            "        boolean isDebuggable = (getApplicationInfo().flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0;\n"
            "        if (isDebuggable) Log.i(\"AppStartup\", \"native:activity-onCreate\");\n"
            "        SplashScreen.installSplashScreen(this);\n"
            "        if (isDebuggable) Log.i(\"AppStartup\", \"native:splash-installed\");\n"
            "        super.onCreate(savedInstanceState);\n"
            "    }\n"
            "}"
        )
    source, replacements = declaration.subn(replacement, source, count=1)
    if replacements != 1:
        raise RuntimeError(f"Unexpected generated MainActivity structure in {activity_file}; review it manually.")
    activity_file.write_text(source, encoding="utf-8")
    _configure_native_crash_capture(activity_file)
    _configure_native_apk_integrity(activity_file, android_root)


def _configure_native_crash_capture(activity_file: Path) -> None:
    """Persist bounded uncaught JVM crash evidence for the next Flutter startup."""
    source = activity_file.read_text(encoding="utf-8")
    if activity_file.suffix == ".java":
        _configure_java_native_crash_capture(activity_file, source)
        return
    if activity_file.suffix != ".kt":
        raise RuntimeError("Native diagnostic capture requires a generated Kotlin or Java MainActivity.")
    if "private fun installDiagnosticCrashCapture()" in source:
        return
    if "import java.io.File" not in source:
        package_line = re.search(r"(?m)^package\s+[\w.]+\s*$", source)
        if package_line is None:
            raise RuntimeError(f"No Kotlin package declaration found in {activity_file}.")
        source = source[:package_line.end()] + "\nimport java.io.File\n" + source[package_line.end():]
    if "installDiagnosticCrashCapture()" not in source:
        source, count = re.subn(
            r"(?m)^([ \t]*)installSplashScreen\(\)[ \t]*$",
            lambda match: f"{match.group(1)}installSplashScreen()\n{match.group(1)}installDiagnosticCrashCapture()",
            source,
            count=1,
        )
        if count != 1:
            raise RuntimeError(f"Could not insert native crash handler in {activity_file}.")
    class_end = source.rfind("}")
    if class_end < 0:
        raise RuntimeError(f"No MainActivity class body found in {activity_file}.")
    handler = r'''

    private fun installDiagnosticCrashCapture() {
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            try {
                val raw = buildString {
                    append("Native uncaught exception: ").append(error.javaClass.name).append('\n')
                    error.stackTrace.take(24).forEach { frame ->
                        append(frame.className).append('.').append(frame.methodName)
                            .append('(').append(frame.fileName ?: "unknown").append(':').append(frame.lineNumber).append(')').append('\n')
                    }
                }
                val safe = raw
                    .replace(Regex("https?://\\S+"), "[url]")
                    .replace(Regex("(token|api[_-]?key|password|secret)\\s*[:=]\\s*[^\\s,;]+", RegexOption.IGNORE_CASE)) { match -> "${match.groupValues[1]}=[redacted]" }
                    .replace(Regex("(?:/data/\\S+|/storage/emulated/\\S+)"), "[path]")
                    .take(8000)
                File(applicationContext.filesDir, "pending_native_crash.txt").writeText(safe)
            } catch (_: Throwable) {
                // Crash evidence is best-effort; never block the platform's fatal handler.
            }
            previous?.uncaughtException(thread, error) ?: android.os.Process.killProcess(android.os.Process.myPid())
        }
    }
'''
    source = source[:class_end] + handler + source[class_end:]
    activity_file.write_text(source, encoding="utf-8")


def _configure_java_native_crash_capture(activity_file: Path, source: str) -> None:
    if "private void installDiagnosticCrashCapture()" in source:
        return
    if "import java.io.File;" not in source:
        package_line = re.search(r"(?m)^package\s+[\w.]+\s*;\s*$", source)
        if package_line is None:
            raise RuntimeError(f"No Java package declaration found in {activity_file}.")
        source = source[:package_line.end()] + "\nimport java.io.File;\n" + source[package_line.end():]
    source, count = re.subn(
        r"(?m)^([ \t]*)SplashScreen\.installSplashScreen\(this\);[ \t]*$",
        lambda match: f"{match.group(1)}SplashScreen.installSplashScreen(this);\n{match.group(1)}installDiagnosticCrashCapture();",
        source,
        count=1,
    )
    if count != 1:
        raise RuntimeError(f"Could not insert Java native crash handler in {activity_file}.")
    class_end = source.rfind("}")
    if class_end < 0:
        raise RuntimeError(f"No Java MainActivity class body found in {activity_file}.")
    handler = r'''

    private void installDiagnosticCrashCapture() {
        final Thread.UncaughtExceptionHandler previous = Thread.getDefaultUncaughtExceptionHandler();
        Thread.setDefaultUncaughtExceptionHandler((thread, error) -> {
            try {
                StringBuilder raw = new StringBuilder("Native uncaught exception: ")
                    .append(error.getClass().getName()).append('\n');
                StackTraceElement[] frames = error.getStackTrace();
                for (int i = 0; i < Math.min(24, frames.length); i++) {
                    StackTraceElement frame = frames[i];
                    raw.append(frame.getClassName()).append('.').append(frame.getMethodName())
                        .append('(').append(frame.getFileName() == null ? "unknown" : frame.getFileName())
                        .append(':').append(frame.getLineNumber()).append(')').append('\n');
                }
                String safe = raw.toString()
                    .replaceAll("https?://\\S+", "[url]")
                    .replaceAll("(?i)(token|api[_-]?key|password|secret)\\s*[:=]\\s*[^\\s,;]+", "$1=[redacted]")
                    .replaceAll("(?:/data/\\S+|/storage/emulated/\\S+)", "[path]");
                if (safe.length() > 8000) safe = safe.substring(0, 8000);
                try (java.io.FileWriter writer = new java.io.FileWriter(new File(getApplicationContext().getFilesDir(), "pending_native_crash.txt"))) { writer.write(safe); }
            } catch (Throwable ignored) {
                // Crash evidence is best-effort; never block the platform's fatal handler.
            }
            if (previous != null) previous.uncaughtException(thread, error);
            else android.os.Process.killProcess(android.os.Process.myPid());
        });
    }
'''
    source = source[:class_end] + handler + source[class_end:]
    activity_file.write_text(source, encoding="utf-8")


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
    configure_trusted_signer_resource(android_root)
    configure_splash_activity(android_root)
    _write_backup_rules(android_root)
    configure_splash_resources(android_root)
    configure_launcher_icon(android_root)


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
    print("Configured Android splash, APK signer/integrity gate, portrait launch, HTTPS-only traffic, minSdk >= 29, and backup exclusions.")
    if not os.environ.get("TRUSTED_APK_CERT_SHA256", "").strip():
        print("WARNING: no release signer pin is configured; release builds will fail closed at startup. Development builds are not protected.", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
