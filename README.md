# Flutter IDE

A lightweight code editor built with Flutter, with a VS Code-inspired interface, Monaco code editing, file navigation, editor tabs, and an integrated terminal.

## Download for Windows

[Download Flutter IDE 1.0.1 for Windows x64](https://github.com/roopakv-glithub/flutter-IDE/releases/download/v1.0.1-windows/Flutter-IDE-1.0.1-windows-x64.zip)

[Release notes and SHA-256 checksum](https://github.com/roopakv-glithub/flutter-IDE/releases/tag/v1.0.1-windows)

1. Download the ZIP and choose **Extract All**.
2. Open the extracted `Flutter-IDE-1.0.1-windows-x64` folder.
3. Double-click `flutter_ide.exe`.

Keep all DLL files and the `data` folder beside the executable. Do not copy only the EXE or run it from inside the ZIP. You can share the complete ZIP with other Windows users.

### Requirements

- Windows 10 or Windows 11 on an Intel/AMD 64-bit (x64) computer.
- [Microsoft Edge WebView2 Evergreen Runtime](https://developer.microsoft.com/en-us/microsoft-edge/webview2/) for the code editor. Install it if it is not already present.
- Flutter and Visual Studio are **not required to launch the packaged IDE**. Visual C++ runtime DLLs are included.
- To build or run Flutter projects with the Run button or terminal, install Flutter, add its `bin` directory to `PATH`, and install the toolchain for the target platform. Windows Flutter projects require the Visual Studio C++ desktop build tools.

This is an unsigned portable application, not an installer or Microsoft Store package. The packaged release was launched and verified on Windows 10 x64; other computers have not been individually tested.

## Features

- **Explorer:** folder tree navigation, file creation, folder creation, rename, and delete.
- **Flutter project view:** organized navigation for `lib`, tests, platform folders, and other project files.
- **Monaco code editor:** syntax highlighting, automatic saving, and file-change monitoring.
- **Editor tabs:** open and switch between multiple files.
- **Terminal:** integrated PTY terminal with a resizable panel.
- **Run button:** runs `flutter run` for the opened project.
- **Layout:** dark theme, resizable sidebar, breadcrumbs, and status bar.

The **Source Control/Git sidebar** and **Pub.dev Packages sidebar**, including their service/API integrations, have been removed. Explorer, Terminal, Run, code editing, tabs, file operations, and Flutter project structure remain intact. Git and Flutter package commands can still be entered manually in the terminal when those tools are installed.

## Terminal fixes in 1.0.1

- Run returns keyboard focus to the terminal, including when it is already open.
- Windows hardware-key input accepts letters, top-row digits, and numpad digits.
- Commands use the terminal Enter character, and output decoding handles UTF-8 split across reads.
- Clear and Close no longer inject shell commands into an active device prompt.
- Consolas text, increased line spacing, and padding make the terminal easier to read.

## Build and run from source

The Flutter project is at the repository root; there is no separate demo directory.

```powershell
git clone https://github.com/roopakv-glithub/flutter-IDE.git
cd flutter-IDE
flutter pub get
flutter run -d windows
```

The Windows build was verified with Flutter 3.47.6, Dart 3.13.5, Visual Studio Build Tools 2019, and Windows SDK 10.0.19041.0. Enable Windows Developer Mode so Flutter can create plugin symlinks.

If the WebView plugin cannot download its native packages because your NuGet configuration only contains a local cache, enable the official `https://api.nuget.org/v3/index.json` package source.

### Build a Windows release

```powershell
flutter pub get
flutter analyze
flutter build windows --release --build-name=1.0.1 --build-number=2
```

The executable and its supporting files are generated in:

```text
build/windows/x64/runner/Release/
```

For distribution, bundle the executable, every required DLL, the complete `data` directory, and the Visual C++ runtime libraries. Follow [Flutter's Windows packaging documentation](https://docs.flutter.dev/platform-integration/windows/building). Sharing the EXE alone is not sufficient.

### Validation of this release

- `flutter pub get`: successful.
- `flutter analyze`: zero errors and one existing warning for an unused `package:flutter/foundation.dart` import in `lib/services/file_service_io.dart`. The command exits nonzero because of that warning; the unrelated file was left unchanged.
- `flutter build windows --release --build-name=1.0.1 --build-number=2`: successful.
- Packaged executable: launched and responding on Windows.
- Six terminal regression tests and a real Windows ConPTY test: passed (letters, numeric prompts, backspace, focus, and output decoding).
- All 140 packaged files: verified against the release ZIP.

## Project structure

```text
lib/
  main.dart
  editor_screen.dart
  file_tree.dart
  flutter_sidebar.dart
  output_panel.dart
  models/
  services/
  widgets/editor/
windows/
  CMakeLists.txt
  runner/
    winrt_compat.h
pubspec.yaml
```

The Windows compatibility header works around a missing forward declaration in Windows SDK 10.0.19041.0. It is applied only to that SDK version. The Font Awesome dependency and icon references are compatible with the Flutter version used for this release.

## Global terminal API

```dart
import 'editor_screen.dart';

runTerminalCommand('flutter run');
runTerminalCommand('flutter pub get');
runTerminalCommand('dart analyze');
```

## Contributing

Contributions are welcome through pull requests. Keep changes focused and run analysis and the relevant platform build before submitting.

## Support

[Support the original project author](https://www.buymeacoffee.com/ankurg132)

## License

The original project README identifies the project as MIT-licensed. Third-party dependency notices are bundled in `data/flutter_assets/NOTICES.Z` in the Windows release.
