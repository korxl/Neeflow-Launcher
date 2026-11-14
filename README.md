# Neeflow Launcher

Neeflow is an Android Minecraft Java launcher built on the open-source Amethyst runtime. The APK includes a Java runtime, native renderer and touch controls; Minecraft game files are downloaded from official sources when a version is installed and are not included in this repository.

## Android APK

A push to `main` builds an installable debug APK with GitHub Actions. The workflow checks out Amethyst at the pinned source revision, initializes its submodules, downloads the OpenJDK 8 runtime, applies the Neeflow branding and local-account patch, then builds the APK. The APK is published as a workflow artifact and attached to a prerelease.

The launcher is based on AngelAuraMC Amethyst-Android at commit `166af615dbdca1a507b8c2d379822cca02795132`. Neeflow's source changes are in [`scripts/prepare_amethyst.py`](scripts/prepare_amethyst.py). The full Amethyst LGPLv3 license is included in [`third_party/AMETHYST-LGPL-3.0.txt`](third_party/AMETHYST-LGPL-3.0.txt) and bundled into the APK's About assets by the workflow. See [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

## Accounts and multiplayer

This build uses local/offline player profiles only and does not require a Microsoft account or OAuth client ID. Choose **Use local account** and enter a player name. Single-player and offline-mode servers can be used; online-mode servers require Microsoft authentication and a Minecraft Java license, which this build does not provide.

Minecraft itself is not bundled. Install a version in the launcher; game libraries and assets are fetched from Mojang/Minecraft's official services. Performance and compatibility depend on the device, Minecraft version and renderer.

## Controls and settings

The Amethyst runtime provides editable touch controls, gamepad support, Java/runtime settings, renderer and resolution preferences, version profiles and mod-loader installers. Some download and mod-loader features may require network access.

## Build source

The Android release workflow is the supported APK build. It uses JDK 21, Gradle 9.6.1, Android SDK/NDK and the JRE artifact described in the upstream [Amethyst build instructions](https://github.com/AngelAuraMC/Amethyst-Android/blob/166af615dbdca1a507b8c2d379822cca02795132/README.md). GitHub Actions checks out the source into a path without spaces, as required by Amethyst's native build.

The root `index.html` and `server.js` remain the separate Neeflow web prototype and preview; they are not the Android game's runtime.
