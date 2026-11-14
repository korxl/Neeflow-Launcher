#!/usr/bin/env python3
"""Apply Neeflow branding and local-only login to the pinned Amethyst checkout."""

from pathlib import Path
import shutil
import sys

LEGACY_CLIENT_ID = "00000000402b5328"
REPLACEMENT_CLIENT_ID = "NEEFLOW_LOCAL_ONLY"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"Expected one {label}, found {count}")
    return text.replace(old, new, 1)


def edit_file(path: Path, replacements: list[tuple[str, str]]) -> None:
    text = path.read_text(encoding="utf-8")
    for old, new in replacements:
        text = replace_once(text, old, new, f"replacement in {path}")
    path.write_text(text, encoding="utf-8")


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python3 scripts/prepare_amethyst.py <Amethyst checkout>")

    repo_root = Path(__file__).resolve().parents[1]
    source_root = Path(sys.argv[1])
    if not source_root.is_absolute():
        source_root = repo_root / source_root
    app_root = source_root / "app_pojavlauncher"
    if not (app_root / "build.gradle").is_file():
        raise SystemExit(f"Amethyst source not found at {source_root}")

    neeflow_assets = app_root / "src/main/assets/neeflow"
    (neeflow_assets / "assets").mkdir(parents=True, exist_ok=True)
    shutil.copy2(repo_root / "index.html", neeflow_assets / "index.html")
    for asset_name in ("alex.png", "steve.png"):
        shutil.copy2(repo_root / "assets" / asset_name, neeflow_assets / "assets" / asset_name)

    fragment_source = repo_root / "android/amethyst/src/main/java/net/kdt/pojavlaunch/fragments/NeeflowLauncherFragment.java"
    fragment_target = app_root / "src/main/java/net/kdt/pojavlaunch/fragments/NeeflowLauncherFragment.java"
    if not fragment_source.is_file():
        raise SystemExit(f"Neeflow launcher fragment not found at {fragment_source}")
    fragment_target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(fragment_source, fragment_target)

    gradle_file = app_root / "build.gradle"
    gradle_text = gradle_file.read_text(encoding="utf-8")
    if "org.angelauramc.amethyst" not in gradle_text:
        raise RuntimeError("Could not find Amethyst application identifiers")
    gradle_text = gradle_text.replace("org.angelauramc.amethyst", "com.neeflow.launcher")
    for old, new in (
        ('resValue "string", "app_name", "Amethyst (Debug)"', 'resValue "string", "app_name", "NeeflowLauncher"'),
        ('resValue "string", "app_short_name", "Amethyst (Debug)"', 'resValue "string", "app_short_name", "NeeflowLauncher"'),
        ('resValue "string", "app_name", "Amethyst"', 'resValue "string", "app_name", "NeeflowLauncher"'),
        ('resValue "string", "app_short_name", "Amethyst"', 'resValue "string", "app_short_name", "NeeflowLauncher"'),
        ("            signingConfig signingConfigs.customDebug\n", ""),
    ):
        gradle_text = replace_once(gradle_text, old, new, f"Gradle setting in {gradle_file}")
    gradle_file.write_text(gradle_text, encoding="utf-8")

    manifest = app_root / "src/main/AndroidManifest.xml"
    edit_file(manifest, [
        ('android:icon="@mipmap/ic_launcher"', 'android:icon="@drawable/ic_neeflow_launcher"'),
        ('android:roundIcon="@mipmap/ic_launcher_round"', 'android:roundIcon="@drawable/ic_neeflow_launcher"'),
        ('android:launchMode="singleTop">', 'android:launchMode="singleTop"\n            android:screenOrientation="sensorLandscape">'),
        ('android:windowSoftInputMode="adjustResize"/>', 'android:windowSoftInputMode="adjustResize"\n            android:screenOrientation="sensorLandscape"/>'),
    ])

    icon_source = repo_root / "assets/neeflow-app-icon.png"
    icon_target = app_root / "src/main/res/drawable-nodpi/ic_neeflow_launcher.png"
    if not icon_source.is_file():
        raise SystemExit(f"Neeflow launcher icon not found at {icon_source}")
    icon_target.parent.mkdir(parents=True, exist_ok=True)
    icon_target.write_bytes(icon_source.read_bytes())
    legacy_icon = app_root / "src/main/res/drawable/ic_neeflow_launcher.xml"
    if legacy_icon.exists():
        legacy_icon.unlink()

    values = app_root / "src/main/res/values/strings.xml"
    edit_file(values, [
        ('<string name="app_name" translatable="false">Amethyst</string>', '<string name="app_name" translatable="false">NeeflowLauncher</string>'),
        ('<string name="login_online_username_hint">Username</string>', '<string name="login_online_username_hint">Local player name</string>'),
        ('<string name="login_online_login_label">Login</string>', '<string name="login_online_login_label">Continue offline</string>'),
        ('<string name="error_fatal">Amethyst has unexpectedly crashed</string>', '<string name="error_fatal">NeeflowLauncher has unexpectedly crashed</string>'),
    ])

    auth_selector = app_root / "src/main/java/net/kdt/pojavlaunch/fragments/SelectAuthFragment.java"
    edit_file(auth_selector, [
        ('import static net.kdt.pojavlaunch.Tools.hasNoOnlineProfileDialog;\n\n', ''),
        ('        mMicrosoftButton.setOnClickListener(v -> Tools.swapFragment(requireActivity(), MicrosoftLoginFragment.class, MicrosoftLoginFragment.TAG, null));\n        mLocalButton.setOnClickListener(v -> hasNoOnlineProfileDialog(requireActivity(), () -> Tools.swapFragment(requireActivity(), LocalLoginFragment.class, LocalLoginFragment.TAG, null)));', '        mMicrosoftButton.setVisibility(View.GONE);\n        mLocalButton.setOnClickListener(v -> Tools.swapFragment(requireActivity(), LocalLoginFragment.class, LocalLoginFragment.TAG, null));'),
    ])

    local_login = app_root / "src/main/java/net/kdt/pojavlaunch/fragments/LocalLoginFragment.java"
    edit_file(local_login, [
        ('import static net.kdt.pojavlaunch.Tools.hasOnlineProfile;\n\n', ''),
        ('        // This is overkill but meh\n        if (!hasOnlineProfile()){\n            Tools.swapFragment(requireActivity(), MainMenuFragment.class, MainMenuFragment.TAG, null);\n        }\n', ''),
    ])

    auth_layout = app_root / "src/main/res/layout/fragment_select_auth_method.xml"
    edit_file(auth_layout, [
        ('android:text="Local account"', 'android:text="Use local account"'),
    ])

    local_layout = app_root / "src/main/res/layout/fragment_local_login.xml"
    edit_file(local_layout, [
        ('android:inputType="textEmailAddress"', 'android:inputType="textPersonName|textNoSuggestions"'),
    ])

    minecraft_downloader = app_root / "src/main/java/net/kdt/pojavlaunch/tasks/MinecraftDownloader.java"
    edit_file(minecraft_downloader, [
        ('if(isLocalProfile || !isOnline) {', 'if(!isOnline) {'),
        ('''        File versionJsonFile;
        if(verInfo != null) versionJsonFile = downloadGameJson(verInfo);
        else versionJsonFile = createGameJsonPath(versionName);
        if(versionJsonFile.canRead())  {''', '''        File versionJsonFile;
        if(verInfo != null) {
            versionJsonFile = downloadGameJson(verInfo);
        } else {
            versionJsonFile = createGameJsonPath(versionName);
            if(!versionJsonFile.canRead() && isOnline) {
                JMinecraftVersionList.Version listedVersion = resolveListedVersion(versionName);
                if(listedVersion != null) versionJsonFile = downloadGameJson(listedVersion);
            }
        }
        if(versionJsonFile.canRead())  {'''),
        ('    private boolean downloadAndProcessMetadata(Activity activity, JMinecraftVersionList.Version verInfo, String versionName) throws IOException, MirrorTamperedException {', '''    private JMinecraftVersionList.Version resolveListedVersion(String versionName) throws IOException {
        JMinecraftVersionList.Version cachedVersion = AsyncMinecraftDownloader.getListedVersion(versionName);
        if(cachedVersion != null) return cachedVersion;

        String manifestUrl = Tools.isValidString(LauncherPreferences.PREF_VERSION_REPOS)
                ? LauncherPreferences.PREF_VERSION_REPOS
                : "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json";
        JMinecraftVersionList manifest = Tools.GLOBAL_GSON.fromJson(
                DownloadUtils.downloadString(manifestUrl), JMinecraftVersionList.class);
        if(manifest == null || manifest.versions == null) return null;
        for(JMinecraftVersionList.Version listedVersion : manifest.versions) {
            if(listedVersion != null && versionName.equals(listedVersion.id)) return listedVersion;
        }
        return null;
    }

    private boolean downloadAndProcessMetadata(Activity activity, JMinecraftVersionList.Version verInfo, String versionName) throws IOException, MirrorTamperedException {'''),
    ])

    launcher_activity = app_root / "src/main/java/net/kdt/pojavlaunch/LauncherActivity.java"
    edit_file(launcher_activity, [
        ('if (mAccountSpinner.getSelectedAccount().isLocal() || !isOnline(this)){', 'if (!isOnline(this)){'),
    ])
    edit_file(launcher_activity, [
        ('import net.kdt.pojavlaunch.fragments.MainMenuFragment;\n', 'import net.kdt.pojavlaunch.fragments.MainMenuFragment;\nimport net.kdt.pojavlaunch.fragments.NeeflowLauncherFragment;\n'),
        ('.add(R.id.container_fragment, MainMenuFragment.class, null, "ROOT").commit();', '.add(R.id.container_fragment, NeeflowLauncherFragment.class, null, "ROOT").commit();'),
        ('        bindViews();\n        checkNotificationPermission();', '        bindViews();\n        mAccountSpinner.setVisibility(View.GONE);\n        mSettingsButton.setVisibility(View.GONE);\n        checkNotificationPermission();'),
        ('    public void onBackPressed() {\n        MicrosoftLoginFragment fragment = (MicrosoftLoginFragment) getVisibleFragment(MicrosoftLoginFragment.TAG);', '    public void onBackPressed() {\n        Fragment root = getSupportFragmentManager().findFragmentByTag("ROOT");\n        if(root instanceof NeeflowLauncherFragment && root.isVisible()) {\n            ((NeeflowLauncherFragment) root).handleBack();\n            return;\n        }\n        MicrosoftLoginFragment fragment = (MicrosoftLoginFragment) getVisibleFragment(MicrosoftLoginFragment.TAG);'),
        ('    private void bindViews(){\n        mFragmentView = findViewById(R.id.container_fragment);\n        mSettingsButton = findViewById(R.id.setting_button);\n        mAccountSpinner = findViewById(R.id.account_spinner);\n        mProgressLayout = findViewById(R.id.progress_layout);\n    }\n}', '    private void bindViews(){\n        mFragmentView = findViewById(R.id.container_fragment);\n        mSettingsButton = findViewById(R.id.setting_button);\n        mAccountSpinner = findViewById(R.id.account_spinner);\n        mProgressLayout = findViewById(R.id.progress_layout);\n    }\n\n    public net.kdt.pojavlaunch.value.MinecraftAccount getNeeflowSelectedAccount() {\n        return mAccountSpinner == null ? null : mAccountSpinner.getSelectedAccount();\n    }\n\n    public boolean selectNeeflowLocalAccount(String username) {\n        return mAccountSpinner != null && mAccountSpinner.selectLocalAccount(username);\n    }\n\n    public void launchNeeflowGame(String profileId, String username) {\n        if(!selectNeeflowLocalAccount(username)) {\n            Toast.makeText(this, "Укажи корректное имя локального игрока.", Toast.LENGTH_LONG).show();\n            return;\n        }\n        LauncherProfiles.load();\n        MinecraftProfile profile = LauncherProfiles.mainProfileJson.profiles.get(profileId);\n        if(profile == null || profile.lastVersionId == null || "Unknown".equals(profile.lastVersionId)) {\n            Toast.makeText(this, R.string.error_no_version, Toast.LENGTH_LONG).show();\n            return;\n        }\n        LauncherPreferences.DEFAULT_PREF.edit()\n                .putString(LauncherPreferences.PREF_KEY_CURRENT_PROFILE, profileId)\n                .apply();\n        ExtraCore.setValue(ExtraConstants.LAUNCH_GAME, true);\n    }\n}')
    ])

    account_spinner = app_root / "src/main/java/com/kdt/mcgui/mcAccountSpinner.java"
    edit_file(account_spinner, [
        ('    public MinecraftAccount getSelectedAccount(){\n        return mSelectecAccount;\n    }', '    public MinecraftAccount getSelectedAccount(){\n        return mSelectecAccount;\n    }\n\n    public boolean selectLocalAccount(String username) {\n        if(username == null || !username.matches("^[A-Za-z0-9_]{3,16}$")) return false;\n        int position = mAccountList.indexOf(username);\n        if(position > 0) {\n            pickAccount(position);\n            performLogin(mSelectecAccount);\n            return mSelectecAccount != null && username.equals(mSelectecAccount.username);\n        }\n        ExtraCore.setValue(ExtraConstants.MOJANG_LOGIN_TODO, new String[]{username, ""});\n        return mSelectecAccount != null && username.equals(mSelectecAccount.username);\n    }')
    ])

    java_root = app_root / "src/main/java"
    replacements = 0
    for java_file in java_root.rglob("*.java"):
        text = java_file.read_text(encoding="utf-8")
        count = text.count(LEGACY_CLIENT_ID)
        if count:
            java_file.write_text(text.replace(LEGACY_CLIENT_ID, REPLACEMENT_CLIENT_ID), encoding="utf-8")
            replacements += count
    if replacements < 3:
        raise RuntimeError(f"Expected to neutralize at least 3 upstream OAuth client ID uses, found {replacements}")

    notices = repo_root / "third_party/AMETHYST-LGPL-3.0.txt"
    if not notices.is_file():
        raise SystemExit(f"Amethyst LGPL notice not found at {notices}")
    bundled_license = app_root / "src/main/assets/licenses/NEEFLOW-AMETHYST-LGPL-3.0.txt"
    bundled_license.write_bytes(notices.read_bytes())

    about = app_root / "src/main/assets/about_en.txt"
    about_text = about.read_text(encoding="utf-8")
    about_text = replace_once(
        about_text,
        'This application is licensed under <a href="https://github.com/PojavLauncherTeam/PojavLauncher/blob/master/LICENSE">GNU GPLv3</a>.<br>',
        'The Amethyst-derived launcher is licensed under GNU LGPLv3; its full license is included in this application.<br>',
        "Amethyst license notice",
    )
    if "Neeflow attribution:" in about_text:
        raise RuntimeError("Neeflow attribution notice is already present")
    about_text += (
        "\n* Neeflow attribution:<br>\n"
        "  - This application is based on AngelAuraMC Amethyst-Android, modified for Neeflow. "
        "Source: <a href=\"https://github.com/AngelAuraMC/Amethyst-Android/tree/166af615dbdca1a507b8c2d379822cca02795132\">pinned Amethyst source</a>.<br>\n"
        "  - Neeflow changes are published in the Neeflow Launcher repository; the full LGPLv3 license is bundled as "
        "assets/licenses/NEEFLOW-AMETHYST-LGPL-3.0.txt.<br>\n"
        "  - This build offers local/offline accounts only. Online-mode servers require a Microsoft account that owns Minecraft Java Edition.<br>\n"
        "  - Neeflow is not affiliated with Mojang, Microsoft, or AngelAuraMC.<br>\n"
    )
    about.write_text(about_text, encoding="utf-8")


if __name__ == "__main__":
    main()
