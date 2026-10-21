# Together Date Planner

A private planning space for two partners to coordinate visits, activities, travel, accommodation, and booking files.

## Development setup

- Flutter 3.47.7 is installed at `C:\Users\<user>\develop\flutter`.
- Android builds use Android Studio's SDK, Android NDK 28.2.13676358, and Temurin JDK 17. Configure Flutter to use a persistent JDK 17 installation with `flutter config --jdk-dir="<jdk-17-folder>"`.
- The `super_native_extensions` Android plugin compiles Rust code. Install Rust with rustup; the Windows project helper adds `%USERPROFILE%\.cargo\bin` and sets `HOME` for CargoKit.
- On this Windows setup, Java's NIO selector needs a short socket temp path. `tool/flutter_project.ps1` sets the process-local Java option to use `C:\tmp` for Android builds.
- Build actions read `supabase/project_configs.json` and pass its URL and publishable key as Flutter build-time defines. Keep that file local; never commit it.

Use the project helper so builds get the configured Supabase values and the Windows Android build environment:

```powershell
.\tool\flutter_project.ps1 -Action analyze
.\tool\flutter_project.ps1 -Action test
.\tool\flutter_project.ps1 -Action build-web
.\tool\flutter_project.ps1 -Action build-apk -FlutterArgs @('--debug')
```

For an Android App Bundle, run `.\tool\flutter_project.ps1 -Action build-appbundle`. Run the app with `.\tool\flutter_project.ps1 -Action run -Device <device-id>`.

## Project documentation

Product scope, user journeys, layout states, visual system, data security, Space connection, and acceptance decisions are described in `docs/`.
