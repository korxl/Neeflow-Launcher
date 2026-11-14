# Neeflow Launcher for Android

This Android package is a native WebView shell around the Neeflow interface. The launcher UI, profile settings and HUD preview are bundled in the APK; the Minecraft version catalog and Modrinth search use Android's network connection.

The current app is a launcher prototype: it does not bundle Minecraft, Java, Microsoft authentication or a game runtime, so it cannot launch Minecraft or join multiplayer servers.

## Build

From the repository root, run `gradle -p android :app:assembleDebug`. The installable debug APK is written to `android/app/build/outputs/apk/debug/app-debug.apk`. The Gradle build copies the root `index.html` and `assets/` into the package, so the web UI has one source of truth.
