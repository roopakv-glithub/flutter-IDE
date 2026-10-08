import 'package:path/path.dart' as p;

import '../config/event_config.dart';

/// Decides what participants may do to files in the event project.
/// Pure logic - no I/O - so it is easy to test.
class ProjectPolicy {
  final String rootPath;

  const ProjectPolicy(this.rootPath);

  /// Path parts relative to the project root, or null if outside the root.
  List<String>? _rel(String path) {
    final normalized = p.normalize(p.absolute(path));
    final root = p.normalize(p.absolute(rootPath));
    if (!p.isWithin(root, normalized) && normalized != root) return null;
    final rel = p.relative(normalized, from: root);
    if (rel == '.') return <String>[];
    return p.split(rel);
  }

  bool _isMainDart(List<String> parts) =>
      parts.length == 2 &&
      parts[0] == kEditableFolder &&
      parts[1] == 'main.dart';

  /// Can this file's content be edited?
  bool canEdit(String path) {
    final parts = _rel(path);
    if (parts == null || parts.isEmpty) return false;
    if (kLimitToMainDart) return _isMainDart(parts);
    return parts.length >= 2 &&
        parts.first == kEditableFolder &&
        p.extension(parts.last).toLowerCase() == '.dart';
  }

  /// Can new files/folders be created inside this directory?
  bool canCreateIn(String dirPath) {
    if (kLimitToMainDart) return false;
    final parts = _rel(dirPath);
    if (parts == null || parts.isEmpty) return false;
    return parts.first == kEditableFolder;
  }

  /// Can this file or folder be deleted? (lib/main.dart is always protected.)
  bool canDelete(String path, {required bool isDirectory}) {
    if (kLimitToMainDart) return false;
    final parts = _rel(path);
    if (parts == null || parts.isEmpty) return false;
    if (_isMainDart(parts)) return false;
    if (parts.first != kEditableFolder) return false;
    if (isDirectory) return parts.length >= 2; // not lib/ itself
    return p.extension(parts.last).toLowerCase() == '.dart';
  }

  bool canRename(String path, String newName, {required bool isDirectory}) {
    if (!canDelete(path, isDirectory: isDirectory)) return false;
    return isDirectory ? isValidName(newName) : isValidDartFileName(newName);
  }

  /// Names must be a single, simple path segment.
  static bool isValidName(String name) {
    if (name.isEmpty || name.length > 64) return false;
    if (name == '.' || name == '..' || name.endsWith('.')) return false;
    if (RegExp(
      r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)',
      caseSensitive: false,
    ).hasMatch(name)) {
      return false;
    }
    return RegExp(r'^[A-Za-z0-9_\-.]+$').hasMatch(name);
  }

  /// Dart files only, e.g. `my_screen.dart`.
  static bool isValidDartFileName(String name) =>
      isValidName(name) && name.toLowerCase().endsWith('.dart');

  /// Turns an arbitrary picked file name into a safe asset name.
  static String sanitizeAssetName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[^A-Za-z0-9_\-.]'), '_');
    return cleaned.toLowerCase();
  }
}
