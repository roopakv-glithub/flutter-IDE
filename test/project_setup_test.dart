import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_ide/services/project_setup_service.dart';
import 'package:flutter_ide/services/file_service_io.dart';
import 'package:flutter_ide/widgets/editor/project_setup_dialog.dart';
import 'package:flutter_ide/models/file_system_entity.dart';

class SetupProcess implements Process {
  SetupProcess(this.code);
  final int code;
  @override
  Stream<List<int>> get stdout =>
      Stream.value(utf8.encode('Created lib/main.dart\n'));
  @override
  Stream<List<int>> get stderr =>
      Stream.value(utf8.encode('diagnostic output\n'));
  @override
  Future<int> get exitCode async => code;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class DialogSetupService extends ProjectSetupService {
  final completion = Completer<int>();
  @override
  Future<int> createWebProject(
    String directory, {
    required void Function(String) onOutput,
  }) {
    onOutput('Creating lib/main.dart...\n');
    onOutput('Package download progress\n');
    return completion.future;
  }
}

void main() {
  test(
    'setup uses fixed web-only arguments and streams stdout and errors',
    () async {
      final directory = await Directory.systemTemp.createTemp('wars_setup_');
      addTearDown(() => directory.delete(recursive: true));
      final output = StringBuffer();
      final service = ProjectSetupService(
        start:
            (
              executable,
              arguments, {
              required workingDirectory,
              required runInShell,
            }) async {
              expect(executable, 'flutter');
              expect(arguments, [
                'create',
                '--platforms=web',
                '--project-name=flutter_wars_app',
                '.',
              ]);
              expect(workingDirectory, directory.path);
              expect(runInShell, Platform.isWindows);
              return SetupProcess(0);
            },
      );
      expect(
        await service.createWebProject(directory.path, onOutput: output.write),
        0,
      );
      expect(output.toString(), contains('Created lib/main.dart'));
      expect(output.toString(), contains('diagnostic output'));
    },
  );

  test(
    'setup preserves an existing project name and returns nonzero exit codes',
    () async {
      final directory = await Directory.systemTemp.createTemp('wars_existing_');
      addTearDown(() => directory.delete(recursive: true));
      await File(
        p.join(directory.path, 'pubspec.yaml'),
      ).writeAsString('name: existing_project\n');
      final service = ProjectSetupService(
        start:
            (
              _,
              arguments, {
              required workingDirectory,
              required runInShell,
            }) async {
              expect(arguments, contains('--project-name=existing_project'));
              expect(arguments, isNot(contains('--overwrite')));
              return SetupProcess(1);
            },
      );
      expect(
        await service.createWebProject(directory.path, onOutput: (_) {}),
        1,
      );
    },
  );

  test(
    'refresh hides generated folders but includes lib and read-only web config',
    () async {
      final directory = await Directory.systemTemp.createTemp('wars_refresh_');
      addTearDown(() => directory.delete(recursive: true));
      for (final name in ['lib/screens', 'web', 'build', '.dart_tool']) {
        await Directory(p.join(directory.path, name)).create(recursive: true);
      }
      await File(
        p.join(directory.path, 'lib', 'main.dart'),
      ).writeAsString('// main');
      await File(
        p.join(directory.path, 'web', 'index.html'),
      ).writeAsString('<html/>');
      final tree = await FileServiceImpl().loadDirectory(directory.path);
      expect(
        tree.children.map((node) => node.name),
        containsAll(['lib', 'web']),
      );
      expect(tree.children.map((node) => node.name), isNot(contains('build')));
      expect(
        tree.children.map((node) => node.name),
        isNot(contains('.dart_tool')),
      );
      final lib = tree.children.whereType<FileNodeDirectory>().firstWhere(
        (node) => node.name == 'lib',
      );
      expect(
        lib.children.map((node) => node.name),
        containsAll(['screens', 'main.dart']),
      );
    },
  );

  Future<void> showSetup(
    WidgetTester tester,
    DialogSetupService service,
    void Function(bool?) done,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async => done(
                await showDialog<bool>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => ProjectSetupDialog(
                    directory: 'example_project',
                    service: service,
                  ),
                ),
              ),
              child: const Text('Set Up Project'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Set Up Project'));
    await tester.pump(const Duration(milliseconds: 250));
  }

  testWidgets('progress stays visible until success then returns true', (
    tester,
  ) async {
    final service = DialogSetupService();
    bool? result;
    await showSetup(tester, service, (value) => result = value);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.textContaining('Creating lib/main.dart'), findsOneWidget);
    service.completion.complete(0);
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(find.byType(ProjectSetupDialog), findsNothing);
  });

  testWidgets('failed setup keeps output visible and allows closing', (
    tester,
  ) async {
    final service = DialogSetupService();
    await showSetup(tester, service, (_) {});
    service.completion.complete(7);
    await tester.pumpAndSettle();
    expect(find.text('Project Setup Failed'), findsOneWidget);
    expect(find.textContaining('exit code 7'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(ProjectSetupDialog), findsNothing);
  });

  testWidgets('missing Flutter displays a helpful error instead of closing', (
    tester,
  ) async {
    final service = DialogSetupService();
    await showSetup(tester, service, (_) {});
    service.completion.completeError(
      const ProcessException('flutter', [], 'not found'),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('available on PATH'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
  });
}
