#!/usr/bin/env python3
"""Apply Android startup branding and security defaults to a Flutter scaffold.

Run only after `flutter create --platforms=android ...` has generated the
Android project. The script deliberately fails when key manifest or Gradle
structure is unfamiliar rather than silently leaving an unsafe default.
"""

from __future__ import annotations

import re
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
    for name, value in (("startup_navy", SPLASH_NAVY),):
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
        return

    if activity_file.suffix == ".kt":
        package_line = re.search(r"(?m)^package\s+[\w.]+\s*$", source)
        if package_line is None:
            raise RuntimeError(f"No Kotlin package declaration found in {activity_file}.")
        imports = "\nimport android.os.Bundle\nimport android.util.Log\nimport androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen\n"
        source = source[:package_line.end()] + imports + source[package_line.end():]
        declaration = re.compile(r"class\s+MainActivity\s*:\s*FlutterActivity\(\)\s*(?:\{\s*\})?")
        replacement = (
            "class MainActivity : FlutterActivity() {\n"
            "    override fun onCreate(savedInstanceState: Bundle?) {\n"
            "        if (BuildConfig.DEBUG) Log.i(\"AppStartup\", \"native:activity-onCreate\")\n"
            "        installSplashScreen()\n"
            "        if (BuildConfig.DEBUG) Log.i(\"AppStartup\", \"native:splash-installed\")\n"
            "        super.onCreate(savedInstanceState)\n"
            "    }\n"
            "}"
        )
    else:
        package_line = re.search(r"(?m)^package\s+[\w.]+\s*;?\s*$", source)
        if package_line is None:
            raise RuntimeError(f"No Java package declaration found in {activity_file}.")
        imports = "\nimport android.os.Bundle;\nimport android.util.Log;\nimport androidx.core.splashscreen.SplashScreen;\n"
        source = source[:package_line.end()] + imports + source[package_line.end():]
        declaration = re.compile(r"public\s+class\s+MainActivity\s+extends\s+FlutterActivity\s*\{\s*\}")
        replacement = (
            "public class MainActivity extends FlutterActivity {\n"
            "    @Override\n"
            "    protected void onCreate(Bundle savedInstanceState) {\n"
            "        if (BuildConfig.DEBUG) Log.i(\"AppStartup\", \"native:activity-onCreate\");\n"
            "        SplashScreen.installSplashScreen(this);\n"
            "        if (BuildConfig.DEBUG) Log.i(\"AppStartup\", \"native:splash-installed\");\n"
            "        super.onCreate(savedInstanceState);\n"
            "    }\n"
            "}"
        )
    source, replacements = declaration.subn(replacement, source, count=1)
    if replacements != 1:
        raise RuntimeError(f"Unexpected generated MainActivity structure in {activity_file}; review it manually.")
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
    configure_splash_activity(android_root)
    _write_backup_rules(android_root)
    configure_splash_resources(android_root)


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
    print("Configured Android 12+ and legacy branded splash, portrait launch, HTTPS-only traffic, minSdk >= 23, and backup exclusions.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
