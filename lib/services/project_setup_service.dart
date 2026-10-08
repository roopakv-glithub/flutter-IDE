import 'dart:convert';
import 'dart:io';

/// Starts only the fixed web-project creation command; folder paths are never
/// interpolated into shell commands.
typedef SetupProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      required String workingDirectory,
      required bool runInShell,
    });

class ProjectSetupService {
  ProjectSetupService({SetupProcessStarter? start})
    : _start = start ?? _startProcess;
  final SetupProcessStarter _start;

  static Future<Process> _startProcess(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    required bool runInShell,
  }) => Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    runInShell: runInShell,
  );

  Future<int> createWebProject(
    String directory, {
    required void Function(String) onOutput,
  }) async {
    final pubspec = File('$directory${Platform.pathSeparator}pubspec.yaml');
    var name = 'flutter_wars_app';
    if (await pubspec.exists()) {
      final match = RegExp(
        r'^name:\s*([a-z][a-z0-9_]*)(?:\s|$)',
        multiLine: true,
      ).firstMatch(await pubspec.readAsString());
      if (match != null) name = match.group(1)!;
    }
    final arguments = [
      'create',
      '--platforms=web',
      '--project-name=$name',
      '.',
    ];
    onOutput('flutter ${arguments.join(' ')}\n\n');
    final process = await _start(
      'flutter',
      arguments,
      workingDirectory: directory,
      runInShell: Platform.isWindows,
    );
    await Future.wait([
      process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .forEach(onOutput),
      process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .forEach(onOutput),
    ]);
    return process.exitCode;
  }
}
