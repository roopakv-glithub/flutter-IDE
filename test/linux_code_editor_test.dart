import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlight/languages/dart.dart' as highlight_dart;
import 'package:flutter_ide/widgets/editor/linux_code_editor.dart';

void main() {
  testWidgets('Linux code editor renders and edits Dart source', (
    tester,
  ) async {
    final controller = CodeController(
      text: 'void main() {}',
      language: highlight_dart.dart,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 500,
            child: LinuxCodeEditor(controller: controller),
          ),
        ),
      ),
    );

    expect(find.byType(CodeField), findsOneWidget);
    await tester.enterText(
      find.byType(EditableText),
      'void main() { print(1); }',
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(controller.text, 'void main() { print(1); }');
    expect(tester.takeException(), isNull);
  });
}
