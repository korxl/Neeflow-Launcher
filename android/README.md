# Android integration sources

`amethyst/src/main/java/net/kdt/pojavlaunch/fragments/NeeflowLauncherFragment.java` is copied into the pinned Amethyst checkout by `scripts/prepare_amethyst.py`. It displays Neeflow's root `index.html` in a WebView and connects the interface to Amethyst's local accounts, version profiles, game launch, catalog requests, resolution scale, memory allocation, JVM arguments, VSync and native touch-control editor.

The web interface and its Steve/Alex preview textures are copied into the APK assets during the Android workflow. The standalone `android/app/` module is an earlier WebView prototype; the installable launcher remains built from Amethyst by `.github/workflows/android-apk.yml`.
