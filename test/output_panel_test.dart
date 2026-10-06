import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ide/output_panel.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

class FakePty implements Pty {
  final controller = StreamController<Uint8List>();
  final writes = <String>[];
  bool killed = false;

  @override
  Stream<Uint8List> get output => controller.stream;

  @override
  void write(Uint8List data) => writes.add(utf8.decode(data));

  @override
  void resize(int rows, int cols) {}

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakePty pty;
  setUp(() => pty = FakePty());
  tearDown(() => pty.controller.close());

  Future<void> showPanel(
    WidgetTester tester, {
    String? command,
    bool visible = true,
    VoidCallback? onClose,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OutputPanel(
            isVisible: visible,
            initialCommand: command,
            onCloseTerminal: onClose,
            ptyFactory: (_, _, _) => pty,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('Windows letters, digits, numpad and Enter reach the PTY once', (
    tester,
  ) async {
    await showPanel(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA, character: 'a');
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1, character: '1');
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2, character: '2');
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3, character: '3');
    await tester.sendKeyEvent(LogicalKeyboardKey.numpad1, character: '1');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(pty.writes.join(), 'a1231\r');
  }, skip: !Platform.isWindows);

  testWidgets(
    'Run refocuses an already visible terminal for device selection',
    (tester) async {
      await showPanel(tester);
      final view = tester.widget<TerminalView>(find.byType(TerminalView));
      view.focusNode!.unfocus();
      await tester.pump();
      expect(view.focusNode!.hasFocus, isFalse);
      await showPanel(tester, command: 'flutter run');
      expect(view.focusNode!.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit2, character: '2');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(pty.writes.join(), 'flutter run\r2\r');
    },
    skip: !Platform.isWindows,
  );

  testWidgets('first command starts a hidden terminal and uses Enter', (
    tester,
  ) async {
    await showPanel(tester, visible: false);
    await showPanel(tester, command: 'flutter run');
    expect(pty.writes, ['flutter run\r']);
  });

  testWidgets('UTF-8 split across output reads does not drop later output', (
    tester,
  ) async {
    await showPanel(tester);
    pty.controller.add(Uint8List.fromList([0xe2, 0x82]));
    await tester.pump();
    pty.controller.add(
      Uint8List.fromList([0xac, ...utf8.encode(' ready 123')]),
    );
    await tester.pump();
    final view = tester.widget<TerminalView>(find.byType(TerminalView));
    expect(view.terminal.buffer.getText(), contains('€ ready 123'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Clear and Close never type commands into the running process', (
    tester,
  ) async {
    var closed = false;
    await showPanel(tester, onClose: () => closed = true);
    await tester.tap(find.byTooltip('Clear'));
    await tester.pump();
    await tester.tap(find.byTooltip('Close Terminal'));
    expect(closed, isTrue);
    expect(pty.writes, isEmpty);
  });

  testWidgets('hiding and reopening keeps the active terminal session', (
    tester,
  ) async {
    await showPanel(tester);
    await showPanel(tester, visible: false);
    expect(pty.killed, isFalse);
    await showPanel(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3, character: '3');
    expect(pty.writes, ['3']);
    await tester.pumpWidget(const SizedBox());
    expect(pty.killed, isTrue);
  }, skip: !Platform.isWindows);
}
