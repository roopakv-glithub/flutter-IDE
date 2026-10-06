import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ide/output_panel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

// Run with FLUTTER_IDE_NATIVE_TERMINAL_TEST=1 and the built directory containing
// flutter_pty.dll on PATH. This exercises real Windows ConPTY, not a mock.
void main() {
  testWidgets(
    'Windows shell echoes typed input and accepts numeric prompts',
    (tester) async {
      Future<void> showCommand(String command) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OutputPanel(isVisible: true, initialCommand: command),
            ),
          ),
        );
        await tester.pump();
      }

      String output() => tester
          .widget<TerminalView>(find.byType(TerminalView))
          .terminal
          .buffer
          .getText();

      Future<void> waitFor(String text) async {
        for (var i = 0; i < 100; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pump();
          if (output().contains(text)) return;
        }
        fail('Terminal did not display "$text":\n${output()}');
      }

      await showCommand('set /p IDE_PICK=CHOOSE_DEVICE_1_2_3:');
      await waitFor('CHOOSE_DEVICE_1_2_3:');
      await tester.sendKeyEvent(LogicalKeyboardKey.digit2, character: '2');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await showCommand('echo SELECTED_DEVICE_%IDE_PICK%');
      await waitFor('SELECTED_DEVICE_2');

      await showCommand('set /p IDE_TEXT=TYPE_TEXT:');
      await waitFor('TYPE_TEXT:');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA, character: 'a');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB, character: 'b');
      await tester.sendKeyEvent(LogicalKeyboardKey.numpad3, character: '3');
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1, character: '1');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await showCommand('echo TYPED_TEXT_%IDE_TEXT%');
      await waitFor('TYPED_TEXT_ab1');
      await tester.pumpWidget(const SizedBox());
    },
    skip:
        !Platform.isWindows ||
        Platform.environment['FLUTTER_IDE_NATIVE_TERMINAL_TEST'] != '1',
  );
}
