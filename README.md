# Neeflow Launcher

Neeflow is an Android launcher interface prototype for Minecraft Java. It includes local launcher profiles, a version catalog, Modrinth modpack discovery, skin previews, customizable touch HUD layouts and launcher settings.

## Android APK

Every push to `main` builds an installable Android debug APK. GitHub Actions publishes it as a downloadable workflow artifact and attaches it to a prerelease in the repository's Releases section. The build bundles the website files into the Android app; it does not depend on the FreeMilk preview URL.

The APK includes a native Android WebView shell and native network adapters for the Minecraft version catalog and Modrinth. It does not include Minecraft Java, a Java runtime, Microsoft/Minecraft sign-in or a game engine. It therefore cannot launch Minecraft or connect to multiplayer servers yet. HUD controls and resolution settings are saved as launcher preferences and preview layout only.

## Build locally

Install JDK 17 and Gradle 8.11.1, then run:

`gradle -p android :app:assembleDebug`

The APK is written to `android/app/build/outputs/apk/debug/app-debug.apk`. This is a debug-signed package for testing and sideloading, not a Play Store release.

## Web preview

The original Node.js web app remains available through the repository's Dockerfile. Its server provides the Modrinth and Minecraft catalog API routes used by the preview.
