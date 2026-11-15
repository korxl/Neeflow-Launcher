#!/usr/bin/env python3
"""Apply Neeflow's iOS interface and branding while retaining Amethyst runtime behavior."""

from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

BUNDLE_ID = "com.neeflow.launcher.ios"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"Expected one {label}, found {count}")
    return text.replace(old, new, 1)


def patch_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text(encoding="utf-8")
    if new in text:
        return
    path.write_text(replace_once(text, old, new, label), encoding="utf-8")


def replace_bundle_id(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    if BUNDLE_ID in text and "org.angelauramc.amethyst" not in text:
        return
    if "org.angelauramc.amethyst" not in text:
        raise RuntimeError(f"Could not find Amethyst bundle identifier in {path}")
    path.write_text(text.replace("org.angelauramc.amethyst", BUNDLE_ID), encoding="utf-8")


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python3 scripts/prepare_amethyst_ios.py <Amethyst iOS checkout>")

    repo_root = Path(__file__).resolve().parents[1]
    source_root = Path(sys.argv[1])
    if not source_root.is_absolute():
        source_root = repo_root / source_root
    natives = source_root / "Natives"
    resources = natives / "resources"
    required_files = (
        natives / "CMakeLists.txt",
        natives / "LauncherMenuViewController.m",
        natives / "LauncherSplitViewController.m",
        natives / "MinecraftResourceDownloadTask.m",
        natives / "Info.plist",
        natives / "Assets.xcassets/AppIcon-Light.appiconset/Contents.json",
        natives / "Assets.xcassets/AppIcon-Dark.appiconset/Contents.json",
        natives / "Assets.xcassets/AppIcon-Development.appiconset/Contents.json",
        resources / "en.lproj/Localizable.strings",
        source_root / "Makefile",
        source_root / "entitlements.sideload.xml",
        source_root / "entitlements.trollstore.xml",
        repo_root / "index.html",
        repo_root / "assets/alex.png",
        repo_root / "assets/steve.png",
        repo_root / "assets/neeflow-app-icon.png",
        repo_root / "ios/amethyst/Natives/NeeflowLauncherViewController.h",
        repo_root / "ios/amethyst/Natives/NeeflowLauncherViewController.m",
    )
    missing = [path for path in required_files if not path.is_file()]
    if missing:
        raise SystemExit("Missing required iOS source files:\n" + "\n".join(str(path) for path in missing))

    web_root = resources / "neeflow"
    (web_root / "assets").mkdir(parents=True, exist_ok=True)
    shutil.copy2(repo_root / "index.html", web_root / "index.html")
    for asset_name in ("alex.png", "steve.png", "neeflow-app-icon.png"):
        shutil.copy2(repo_root / "assets" / asset_name, web_root / "assets" / asset_name)

    icon_source = repo_root / "assets/neeflow-app-icon.png"
    icon_targets = (
        "Assets.xcassets/AppIcon-Light.appiconset/1024x1024.png",
        "Assets.xcassets/AppIcon-Light.appiconset/1024x1024-Transparent.png",
        "Assets.xcassets/AppIcon-Light.appiconset/1024x1024-Monochrome-White.png",
        "Assets.xcassets/AppIcon-Dark.appiconset/AppIcon-Dark_1024x1024.png",
        "Assets.xcassets/AppIcon-Development.appiconset/AppIcon-Development_1024x1024.png",
    )
    with tempfile.TemporaryDirectory(prefix="neeflow-ios-icon-") as temp_dir:
        resized_icon = Path(temp_dir) / "neeflow-app-icon-1024.png"
        subprocess.run(["sips", "-z", "1024", "1024", str(icon_source), "--out", str(resized_icon)], check=True)
        for relative_path in icon_targets:
            shutil.copy2(resized_icon, natives / relative_path)

    for filename in ("NeeflowLauncherViewController.h", "NeeflowLauncherViewController.m"):
        shutil.copy2(repo_root / "ios/amethyst/Natives" / filename, natives / filename)

    patch_once(
        natives / "CMakeLists.txt",
        "  LauncherNewsViewController.m\n",
        "  LauncherNewsViewController.m\n  NeeflowLauncherViewController.m\n",
        "Neeflow controller source in CMakeLists.txt",
    )

    split_view = natives / "LauncherSplitViewController.m"
    patch_once(
        split_view,
        '#import "LauncherProfilesViewController.h"\n',
        '#import "LauncherProfilesViewController.h"\n#import "NeeflowLauncherViewController.h"\n',
        "Neeflow controller import in split view",
    )
    patch_once(
        split_view,
        'LauncherNavigationController *detailVc = [[LauncherNavigationController alloc] initWithRootViewController:[[LauncherProfilesViewController alloc] init]];\n    detailVc.toolbarHidden = NO;',
        'LauncherNavigationController *detailVc = [[LauncherNavigationController alloc] initWithRootViewController:[[NeeflowLauncherViewController alloc] init]];\n    detailVc.toolbarHidden = YES;\n    detailVc.navigationBarHidden = YES;',
        "Neeflow as the iOS home screen",
    )
    patch_once(
        split_view,
        '        if(!getPrefBool(@"general.hidden_sidebar")) {',
        '        if(UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPhone && !getPrefBool(@"general.hidden_sidebar")) {',
        "hide the Amethyst sidebar on iPhone",
    )

    menu = natives / "LauncherMenuViewController.m"
    patch_once(
        menu,
        '#import "LauncherNewsViewController.h"\n',
        '#import "LauncherNewsViewController.h"\n#import "NeeflowLauncherViewController.h"\n',
        "Neeflow menu import",
    )
    patch_once(
        menu,
        "        [LauncherMenuCustomItem vcClass:LauncherNewsViewController.class],\n        [LauncherMenuCustomItem vcClass:LauncherProfilesViewController.class],",
        "        [LauncherMenuCustomItem vcClass:LauncherNewsViewController.class],\n        [LauncherMenuCustomItem vcClass:NeeflowLauncherViewController.class],\n        [LauncherMenuCustomItem vcClass:LauncherProfilesViewController.class],",
        "Neeflow menu item",
    )

    patch_once(
        natives / "MinecraftResourceDownloadTask.m",
        '- (BOOL)checkAccessWithDialog:(BOOL)show {\n    // for now\n    BOOL accessible = [BaseAuthenticator.current.authData[@"username"] hasPrefix:@"Demo."] || BaseAuthenticator.current.authData[@"xboxGamertag"] != nil;',
        '- (BOOL)checkAccessWithDialog:(BOOL)show {\n    // for now\n    BOOL isLocalAccount = [BaseAuthenticator.current isKindOfClass:LocalAuthenticator.class];\n    BOOL accessible = isLocalAccount || [BaseAuthenticator.current.authData[@"username"] hasPrefix:@"Demo."] || BaseAuthenticator.current.authData[@"xboxGamertag"] != nil;',
        "allow local accounts to download official Minecraft files",
    )
    info = natives / "Info.plist"
    info_text = info.read_text(encoding="utf-8")
    display_name = '<key>CFBundleDisplayName</key>\n\t<string>Amethyst</string>'
    bundle_name = '<key>CFBundleName</key>\n\t<string>AngelAuraAmethyst</string>'
    if display_name in info_text:
        info_text = replace_once(info_text, display_name, '<key>CFBundleDisplayName</key>\n\t<string>Neeflow</string>', "iOS display name")
    elif '<key>CFBundleDisplayName</key>\n\t<string>Neeflow</string>' not in info_text:
        raise RuntimeError(f"Could not find iOS display name in {info}")
    if bundle_name in info_text:
        info_text = replace_once(info_text, bundle_name, '<key>CFBundleName</key>\n\t<string>Neeflow</string>', "iOS bundle name")
    elif '<key>CFBundleName</key>\n\t<string>Neeflow</string>' not in info_text:
        raise RuntimeError(f"Could not find iOS bundle name in {info}")
    info_text = info_text.replace("org.angelauramc.amethyst", BUNDLE_ID)
    network_description = '<key>NSLocalNetworkUsageDescription</key>\n\t<string>Angel Aura Amethyst uses the local network to find and communicate with AltServer and LAN servers.</string>'
    network_replacement = '<key>NSLocalNetworkUsageDescription</key>\n\t<string>Neeflow uses the local network for Minecraft LAN multiplayer.</string>\n\t<key>NSAppTransportSecurity</key>\n\t<dict>\n\t\t<key>NSAllowsLocalNetworking</key>\n\t\t<true/>\n\t</dict>'
    if network_replacement not in info_text:
        info_text = replace_once(info_text, network_description, network_replacement, "local network description and local HTTP policy")
    info.write_text(info_text, encoding="utf-8")

    replace_bundle_id(source_root / "Makefile")
    for filename in ("entitlements.sideload.xml", "entitlements.trollstore.xml"):
        replace_bundle_id(source_root / filename)

    info_strings = resources / "en.lproj/InfoPlist.strings"
    if info_strings.is_file():
        strings = info_strings.read_text(encoding="utf-8")
        strings = re.sub(r'("CFBundleDisplayName"\s*=\s*)"[^"]*";', r'\1"Neeflow";', strings)
        info_strings.write_text(strings, encoding="utf-8")


if __name__ == "__main__":
    main()
