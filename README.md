# Flutter Wars IDE

A Windows code editor for Flutter Wars, with Monaco editing, an Explorer, a restricted Flutter terminal, and Chrome running.

## Download for Windows

[Download Flutter Wars IDE 1.0.4 for Windows x64](https://github.com/roopakv-glithub/flutter-IDE/releases/download/v1.0.4-windows/Flutter-IDE-1.0.4-windows-x64.zip)

[Release notes and SHA-256 checksum](https://github.com/roopakv-glithub/flutter-IDE/releases/tag/v1.0.4-windows)

Extract the complete ZIP and open `flutter_ide.exe` in the extracted folder. Keep every DLL and the `data` folder alongside the executable.

Requirements:

- Windows 10 or Windows 11, x64.
- Microsoft Edge WebView2 Runtime for Monaco.
- Flutter on PATH and Google Chrome to analyze or run participant projects.
- The Visual C++ runtime DLLs are included. Flutter and Visual Studio are not required just to open the packaged IDE.

The release is an unsigned portable application. The Windows build and automated regression tests were checked locally. Interactive editor scrolling, touchpad behavior, and the full Run flow still need manual confirmation on the target computer.

## Set up a project

Click **Set Up Project** on the welcome screen or in the Explorer. Choose a folder if none is open. The IDE runs `flutter create --platforms=web --project-name=flutter_wars_app .` there (using the existing project name when available). The progress dialog streams Flutter output and errors. Successful setup refreshes the Explorer and automatically opens `lib/main.dart`. Failed setup keeps the error output visible so you can fix the issue and retry. Flutter must be installed and on PATH.

Only Dart files inside `lib/` are editable. Create subfolders and new Dart files there. `lib/main.dart` cannot be renamed or deleted. `pubspec.yaml` and web configuration remain read-only. `build/` and `.dart_tool/` are hidden from project navigation. Run always uses Chrome.

## Changes in 1.0.4

- Recreate the editor after setup refreshes the project, including when a file was already open.

- Added the Set Up Project button, live setup progress/error output, tree refresh, and automatic opening of `lib/main.dart`.
- Hide generated `build/` and `.dart_tool/` folders in both project views.
- Retain the file protections, approved packages, and basic terminal commands from 1.0.2.

## Changes included from 1.0.2

- Merged the teammate's Flutter Wars event features while retaining Windows terminal keyboard, focus, and UTF-8 fixes.
- Dart files inside `lib/`, including `main.dart`, are editable. Project configuration and other files have a read-only viewer. Opening `lib/` directly resolves the enclosing project folder.
- Create, rename, and delete Dart files and folders inside `lib/`. Rename updates tree entries, affected tabs, and file watchers; existing destinations cannot be overwritten. Delete removes tree entries and affected tabs. `lib/` itself and `lib/main.dart` cannot be renamed or deleted.
- Saves edits before switching files, closing tabs, or running a command.
- Terminal scrolling has an explicit scrollbar and mouse, touch, and trackpad drag support. Monaco enables smooth scrolling.
- Run always targets Chrome; the Analyze button runs `flutter analyze`.
- The Approved Packages sidebar lists five basic packages: `collection`, `intl`, `http`, `shared_preferences`, and `flutter_svg`. Flutter and Dart are supplied by the SDK. Adding a listed package uses the IDE's controlled action.
- Import PNG, JPG, JPEG, GIF, or WebP images up to 2 MB through Add Image. The IDE copies them into `assets/images/` and updates the assets declaration.

## Terminal commands

The terminal accepts these fixed commands (extra surrounding or repeated whitespace is ignored):

```text
flutter analyze
flutter run
flutter run -d chrome
flutter doctor
flutter doctor -v
flutter devices
flutter --version
flutter help
flutter pub get
flutter clean
help
clear
```

`flutter run` is a shortcut for `flutter run -d chrome`. Doctor, devices, version, and help work without opening a project. Analyze, Run, pub get, and clean require an open project.

While Flutter runs, normal process input such as `r` for hot reload, `R` for hot restart, `q` to quit, and Ctrl+C remains available. Wait for the process to exit before issuing another command.

Other commands, arbitrary shell syntax, unapproved package additions, and alternative Run targets are blocked. These are IDE workflow restrictions, not an operating-system sandbox.

## Build from source

```powershell
git clone https://github.com/roopakv-glithub/flutter-IDE.git
cd flutter-IDE
flutter pub get
flutter analyze
flutter test
flutter build windows --release --build-name=1.0.4 --build-number=5
```

The application is generated in `build/windows/x64/runner/Release/`. Package that entire directory with the x64 Visual C++ redistributable runtime DLLs. The build uses the existing Windows SDK compatibility fix and Font Awesome 11 dependency.

Event settings and approved package constraints live in `lib/config/event_config.dart`. File operation rules live in `lib/policy/project_policy.dart`.

## Manual release checks

Use a disposable Flutter project:

1. Click Set Up Project in an empty folder; verify progress and automatic opening of `lib/main.dart`.
2. Edit `lib/main.dart` and another Dart file, switch tabs, and verify saved content.
3. Rename a file and a nested folder; verify disk names, tabs, and the Explorer.
4. Delete a spare file and folder; verify tabs close and items stay deleted.
5. Scroll a long code file and long terminal output with both wheel and touchpad.
6. Run `flutter doctor`, `flutter analyze`, and `flutter run`; verify Run opens Chrome and hot reload works.
7. Confirm project configuration stays read-only, approved packages can be added, and other terminal commands are blocked.

## Support and license

[Support the original project author](https://www.buymeacoffee.com/ankurg132)

The original project README identifies the project as MIT-licensed. Third-party dependency notices are bundled in `data/flutter_assets/NOTICES.Z` in the Windows release.
