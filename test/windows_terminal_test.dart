import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_ide/output_panel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

// Opt in with FLUTTER_IDE_NATIVE_TERMINAL_TEST=1. Add the built directory
// containing flutter_pty and the Flutter SDK bin directory to PATH.
void main() {
  testWidgets(
    'restricted terminal runs Flutter diagnostics without a project',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OutputPanel(
              isVisible: true,
              initialCommand: 'flutter --version',
            ),
          ),
        ),
      );
      String output() => tester
          .widget<TerminalView>(find.byType(TerminalView))
          .terminal
          .buffer
          .getText();
      for (
        var i = 0;
        i < 300 && !output().contains('[process exited with code');
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
      expect(output(), contains('Flutter '));
      expect(output(), contains('Dart '));
      expect(output(), contains('[process exited with code 0]'));
      await tester.pumpWidget(const SizedBox());
    },
    skip:
        (!Platform.isWindows && !Platform.isLinux) ||
        Platform.environment['FLUTTER_IDE_NATIVE_TERMINAL_TEST'] != '1',
  );
}
