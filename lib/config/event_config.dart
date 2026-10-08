// Flutter Wars - event configuration.
//
// Everything an organiser might want to tweak lives in this one file.

// ---------------------------------------------------------------------------
// 1. Approved packages (Change 1)
// ---------------------------------------------------------------------------

/// Packages participants may add. Key = package name on pub.dev,
/// value = optional version constraint ('' means "latest compatible").
///
/// Basic utilities approved for Flutter Wars; Flutter/Dart themselves are SDKs.
const Map<String, String> kApprovedPackages = {
  'collection': '^1.19.1',
  'intl': '^0.20.2',
  'http': '^1.2.0',
  'shared_preferences': '^2.5.0',
  'flutter_svg': '^2.2.3',
};

// ---------------------------------------------------------------------------
// 2. Run target (Change 2)
// ---------------------------------------------------------------------------

/// The only device the IDE will ever run on.
const String kRunDevice = 'chrome';

// ---------------------------------------------------------------------------
// 3. Controlled project editing (Change 3)
// ---------------------------------------------------------------------------

/// Folder (relative to the project root) whose Dart files are editable.
const String kEditableFolder = 'lib';

/// Set to true to lock editing down to lib/main.dart ONLY
/// (no other files can be edited, created, renamed or deleted).
const bool kLimitToMainDart = false;

/// Images participants may import, and where they are copied.
const List<String> kAllowedImageExtensions = [
  'png',
  'jpg',
  'jpeg',
  'gif',
  'webp',
];
const int kMaxImageBytes = 2 * 1024 * 1024; // 2 MB
const String kAssetsFolder = 'assets/images';

// ---------------------------------------------------------------------------
// 4. Terminal whitelist (Change 4)
// ---------------------------------------------------------------------------

/// A command the IDE is allowed to run. The executable and arguments are
/// fixed here - user-typed text is never passed to a shell.
class AllowedCommand {
  final String id;
  final String executable;
  final List<String> arguments;

  const AllowedCommand({
    required this.id,
    required this.executable,
    required this.arguments,
  });

  String get display => '$executable ${arguments.join(' ')}';
}

const AllowedCommand kCmdAnalyze = AllowedCommand(
  id: 'analyze',
  executable: 'flutter',
  arguments: ['analyze'],
);

const AllowedCommand kCmdRunChrome = AllowedCommand(
  id: 'run',
  executable: 'flutter',
  arguments: ['run', '-d', kRunDevice],
);

/// Resolves dependencies already declared by the project.
const AllowedCommand kCmdPubGet = AllowedCommand(
  id: 'pub-get',
  executable: 'flutter',
  arguments: ['pub', 'get'],
);

/// Builds the internal "add approved package" command. Returns null if the
/// package is not on the approved list.
AllowedCommand? pubAddCommand(String packageName) {
  final constraint = kApprovedPackages[packageName];
  if (constraint == null) return null;
  final spec = constraint.isEmpty ? packageName : '$packageName:$constraint';
  return AllowedCommand(
    id: 'pub-add-$packageName',
    executable: 'flutter',
    arguments: ['pub', 'add', spec],
  );
}

/// What participants may type in the terminal (exact match after trimming
/// and collapsing spaces). Everything else is blocked.
const Map<String, AllowedCommand> kTypedCommands = {
  'flutter analyze': kCmdAnalyze,
  'flutter doctor': AllowedCommand(
    id: 'doctor',
    executable: 'flutter',
    arguments: ['doctor'],
  ),
  'flutter doctor -v': AllowedCommand(
    id: 'doctor-verbose',
    executable: 'flutter',
    arguments: ['doctor', '-v'],
  ),
  'flutter devices': AllowedCommand(
    id: 'devices',
    executable: 'flutter',
    arguments: ['devices'],
  ),
  'flutter --version': AllowedCommand(
    id: 'version',
    executable: 'flutter',
    arguments: ['--version'],
  ),
  'flutter help': AllowedCommand(
    id: 'help',
    executable: 'flutter',
    arguments: ['help'],
  ),
  'flutter pub get': kCmdPubGet,
  'flutter clean': AllowedCommand(
    id: 'clean',
    executable: 'flutter',
    arguments: ['clean'],
  ),
  'flutter run -d $kRunDevice': kCmdRunChrome,
  'flutter run': kCmdRunChrome, // shortcut, always goes to Chrome
};
