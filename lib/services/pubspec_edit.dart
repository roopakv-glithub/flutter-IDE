// Small, careful text edits to pubspec.yaml that the IDE performs on behalf of
// participants (they cannot edit pubspec.yaml themselves).

/// Adds `- [entry]` under `flutter: -> assets:`. Returns the new text, or null
/// if the entry is already declared (nothing to change).
String? addAssetsDeclaration(String yaml, String entry) {
  final eol = yaml.contains('\r\n') ? '\r\n' : '\n';
  final lines = yaml.split(eol);
  final bareEntry = entry.endsWith('/')
      ? entry.substring(0, entry.length - 1)
      : entry;

  final flutterIdx = lines.indexWhere(
    (l) => RegExp(r'^flutter:\s*(#.*)?$').hasMatch(l),
  );

  if (flutterIdx == -1) {
    final trimmed = yaml.endsWith(eol) ? yaml : '$yaml$eol';
    return '$trimmed${eol}flutter:$eol  assets:$eol    - $entry$eol';
  }

  // End of the flutter: block = next non-empty, non-comment, unindented line.
  var blockEnd = lines.length;
  for (var i = flutterIdx + 1; i < lines.length; i++) {
    final l = lines[i];
    if (l.trim().isEmpty) continue;
    if (l.startsWith('#')) continue;
    if (!l.startsWith(' ') && !l.startsWith('\t')) {
      blockEnd = i;
      break;
    }
  }

  var assetsIdx = -1;
  for (var i = flutterIdx + 1; i < blockEnd; i++) {
    if (RegExp(r'^  assets:\s*(#.*)?$').hasMatch(lines[i])) {
      assetsIdx = i;
      break;
    }
  }

  if (assetsIdx == -1) {
    lines.insertAll(flutterIdx + 1, ['  assets:', '    - $entry']);
    return lines.join(eol);
  }

  // Already declared?
  for (var i = assetsIdx + 1; i < blockEnd; i++) {
    final m = RegExp(r'^\s{4}-\s*(.+?)\s*$').firstMatch(lines[i]);
    if (m == null) {
      if (lines[i].trim().isEmpty || lines[i].trim().startsWith('#')) continue;
      break; // next key
    }
    final value = m.group(1)!.replaceAll('"', '').replaceAll("'", '');
    if (value == entry || value == bareEntry) return null;
  }

  lines.insert(assetsIdx + 1, '    - $entry');
  return lines.join(eol);
}
