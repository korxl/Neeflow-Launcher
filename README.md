# Neeflow Launcher

Neeflow is an Android Minecraft Java launcher with the Neeflow interface and the Amethyst runtime, renderer, Java runtime and in-game touch-control system. Minecraft game files are fetched from official services when a version is installed; they are not bundled in this repository.

## Android APK

A push to `main` builds an installable debug APK with GitHub Actions. The workflow checks out Amethyst at the pinned source revision, initializes its submodules, downloads the OpenJDK 8 runtime, applies the Neeflow branding and local-account patch, copies the Neeflow web interface and its Android bridge into the launcher, then builds the APK. The APK is published as a workflow artifact and attached to a prerelease.

The launcher is based on AngelAuraMC Amethyst-Android at commit `166af615dbdca1a507b8c2d379822cca02795132`. Neeflow's interface and Android integration are published in [`index.html`](index.html), [`android/amethyst/`](android/amethyst), and [`scripts/prepare_amethyst.py`](scripts/prepare_amethyst.py). The full Amethyst LGPLv3 license is included in [`third_party/AMETHYST-LGPL-3.0.txt`](third_party/AMETHYST-LGPL-3.0.txt) and bundled into the APK's About assets by the workflow. See [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

## Accounts and multiplayer

The APK uses local/offline player profiles only and does not require a Microsoft account or OAuth client ID. Enter a player name in Neeflow's settings; the Android bridge creates and selects the matching local Amethyst account. Single-player and offline-mode servers can be used. Online-mode servers require Microsoft authentication and a Minecraft Java license, which this build does not provide.

Minecraft itself is not bundled. Create or select a Vanilla profile in Neeflow and launch it; Amethyst downloads the required game files and libraries from Mojang/Minecraft's official services. Performance and compatibility depend on the device, Minecraft version and renderer.

## Interface, controls and settings

The Android launcher opens Neeflow's own HTML/CSS/JavaScript interface rather than Amethyst's home screen. Its Android bridge reads and writes Amethyst version profiles, selects local accounts, starts the game, and proxies the Mojang version catalog and Modrinth searches. Vanilla profiles created in Neeflow are native Amethyst profiles. Neeflow's resolution scale, Java memory allocation, JVM arguments and VSync control write to Amethyst's real launcher preferences; other runtime and renderer options are available through Amethyst's native settings. The Neeflow HUD workspace is a visual layout preview; use its “real controls” action to edit Amethyst's actual in-game touch controls.

The root `index.html` also remains runnable as a web preview. Outside the Android APK, game launching and runtime settings are clearly preview-only.

## Build source

The Android release workflow is the supported APK build. It uses JDK 21, Gradle 9.6.1, Android SDK/NDK and the JRE artifact described in the upstream [Amethyst build instructions](https://github.com/AngelAuraMC/Amethyst-Android/blob/166af615dbdca1a507b8c2d379822cca02795132/README.md). GitHub Actions checks out the source into a path without spaces, as required by Amethyst's native build.
