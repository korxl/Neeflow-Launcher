# Third-party notices

## AngelAuraMC Amethyst-Android

The Android launcher in Neeflow is based on [AngelAuraMC/Amethyst-Android](https://github.com/AngelAuraMC/Amethyst-Android), pinned to commit [`166af615dbdca1a507b8c2d379822cca02795132`](https://github.com/AngelAuraMC/Amethyst-Android/tree/166af615dbdca1a507b8c2d379822cca02795132). Amethyst is licensed under the GNU Lesser General Public License, version 3 (LGPL-3.0). A copy of the upstream license is in [`third_party/AMETHYST-LGPL-3.0.txt`](third_party/AMETHYST-LGPL-3.0.txt), and the APK build bundles that license with the application assets.

Neeflow's build-time modifications are kept in [`scripts/prepare_amethyst.py`](scripts/prepare_amethyst.py). They apply Neeflow branding, replace the upstream OAuth client identifier with a disabled local-only placeholder, remove the Microsoft sign-in option, and allow local profiles without an online account. The APK is built from the pinned upstream source plus those published modifications.

The build does not publish Amethyst's upload or debug keystores. Minecraft's proprietary game files are not included; the launcher downloads required files from official Minecraft services.
