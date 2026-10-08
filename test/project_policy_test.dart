import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_ide/policy/project_policy.dart';
import 'package:flutter_ide/config/event_config.dart';
import 'package:flutter_ide/services/file_service_io.dart';

void main() {
  final root = p.join(Directory.systemTemp.path, 'wars_policy');
  final policy = ProjectPolicy(root);
  test('main and nested Dart files remain editable, config is protected', () {
    expect(policy.canEdit(p.join(root, 'lib', 'main.dart')), isTrue);
    expect(policy.canEdit(p.join(root, 'lib', 'screens', 'home.dart')), isTrue);
    expect(policy.canEdit(p.join(root, 'pubspec.yaml')), isFalse);
    expect(policy.canEdit(p.join(root, 'web', 'index.html')), isFalse);
    expect(
      policy.canRename(
        p.join(root, 'lib', 'main.dart'),
        'other.dart',
        isDirectory: false,
      ),
      isFalse,
    );
    expect(policy.canCreateIn(p.join(root, 'lib', 'screens')), isTrue);
    expect(policy.canCreateIn(p.join(root, 'web')), isFalse);
    expect(policy.canEdit(p.join(root, 'lib', '..', 'main.dart')), isFalse);
    expect(
      policy.canDelete(p.join(root, 'lib', 'main.dart'), isDirectory: false),
      isFalse,
    );
    expect(policy.canDelete(p.join(root, 'lib'), isDirectory: true), isFalse);
    expect(
      policy.canRename(
        p.join(root, 'lib', 'screen.dart'),
        'view.dart',
        isDirectory: false,
      ),
      isTrue,
    );
    expect(
      policy.canRename(
        p.join(root, 'lib', 'screen.dart'),
        '../pubspec.yaml',
        isDirectory: false,
      ),
      isFalse,
    );
    for (final name in ['..', 'con', 'NUL.dart', 'folder.', 'a/b', 'a\\b']) {
      expect(ProjectPolicy.isValidName(name), isFalse, reason: name);
    }
  });
  test('only five approved packages and Chrome commands are available', () {
    expect(kApprovedPackages.length, 5);
    expect(pubAddCommand('unapproved'), isNull);
    expect(pubAddCommand('http')!.arguments, ['pub', 'add', 'http:^1.2.0']);
    expect(kTypedCommands['flutter run']!.arguments, ['run', '-d', 'chrome']);
    expect(kTypedCommands['flutter pub get'], kCmdPubGet);
    for (final command in [
      'flutter doctor',
      'flutter doctor -v',
      'flutter devices',
      'flutter --version',
      'flutter help',
      'flutter clean',
    ]) {
      expect(kTypedCommands[command], isNotNull, reason: command);
    }
    expect(kTypedCommands['flutter run -d windows'], isNull);
    expect(kTypedCommands['flutter doctor & whoami'], isNull);
  });
  test(
    'file and folder rename and delete affect disk without overwriting',
    () async {
      final directory = await Directory.systemTemp.createTemp('wars_file_ops_');
      addTearDown(() => directory.delete(recursive: true));
      final service = FileServiceImpl();
      final folder = await service.createDirectory(directory.path, 'screens');
      final file = await service.createFile(folder!.path, 'one.dart');
      await service.saveFile(file!, 'content');
      await service.createFile(folder.path, 'two.dart');
      expect(await service.rename(file.path, 'two.dart'), isFalse);
      expect(await service.rename(file.path, '../escape.dart'), isFalse);
      expect(await service.rename(file.path, 'renamed.dart'), isTrue);
      expect(
        await File(p.join(folder.path, 'renamed.dart')).readAsString(),
        'content',
      );
      expect(await service.rename(folder.path, 'views'), isTrue);
      final renamed = p.join(directory.path, 'views');
      expect(await service.deleteFile(p.join(renamed, 'two.dart')), isTrue);
      expect(await service.deleteDirectory(renamed), isTrue);
      expect(await Directory(renamed).exists(), isFalse);
    },
  );
}
