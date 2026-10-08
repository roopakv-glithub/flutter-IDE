import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';

import 'config/event_config.dart';

/// A restricted terminal.
///
/// There is NO shell. Typed text is matched against [kTypedCommands]; only an
/// exact match runs, using a fixed executable and fixed arguments. While an
/// allowed command is running (e.g. `flutter run`), keystrokes go to that
/// process so hot reload (r / R) and quit (q) still work.
class OutputPanel extends StatefulWidget {
  final bool isVisible;
  final double height;
  final String? workingDirectory;

  /// A command to run (typed-style text, or an internal command).
  final AllowedCommand? pendingCommand;
  // Kept for callers using the former text API; still subject to the whitelist.
  final String? initialCommand;
  @visibleForTesting
  final Pty Function(int columns, int rows, String? directory)? ptyFactory;
  AllowedCommand? get command =>
      pendingCommand ?? kTypedCommands[initialCommand?.trim()];
  final VoidCallback? onCommandExecuted;
  final VoidCallback? onCloseTerminal;

  const OutputPanel({
    super.key,
    required this.isVisible,
    this.height = 250,
    this.workingDirectory,
    this.pendingCommand,
    this.initialCommand,
    this.ptyFactory,
    this.onCommandExecuted,
    this.onCloseTerminal,
  });

  @override
  State<OutputPanel> createState() => _OutputPanelState();
}

class _OutputPanelState extends State<OutputPanel> {
  static const String _prompt = '> ';

  final terminal = Terminal(maxLines: 10000);
  final focusNode = FocusNode();
  final scrollController = ScrollController();

  Pty? _pty;
  StreamSubscription<String>? _outputSub;
  String _lineBuffer = '';
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    terminal.onOutput = _onTerminalInput;
    terminal.onResize = (width, height, pixelWidth, pixelHeight) {
      _pty?.resize(height, width);
    };
    _printBanner();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.isVisible) return;
      focusNode.requestFocus();
      final command = widget.command;
      if (command != null) {
        _execute(command, echo: true);
        widget.onCommandExecuted?.call();
      }
    });
  }

  @override
  void didUpdateWidget(OutputPanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isVisible && !oldWidget.isVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) focusNode.requestFocus();
      });
    }

    if (widget.workingDirectory != oldWidget.workingDirectory) {
      _killProcess();
      _clearScreen();
      _printBanner();
    }

    final cmd = widget.command;
    if (cmd != null && cmd != oldWidget.command) {
      // Defer to avoid setState during build.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        focusNode.requestFocus();
        await _execute(cmd, echo: true);
        widget.onCommandExecuted?.call();
      });
    }
  }

  // ------------------------------------------------------------------ I/O --

  void _printBanner() {
    terminal.write('Flutter Wars terminal (restricted)\r\n');
    terminal.write('Allowed commands:\r\n');
    for (final command in kTypedCommands.keys) {
      terminal.write('  $command\r\n');
    }
    terminal.write('Type help to list commands, or clear to clear output.\r\n');
    terminal.write('Everything else is blocked.\r\n\r\n');
    terminal.write(_prompt);
  }

  void _clearScreen() {
    // Erase scrollback + screen and move the cursor home.
    terminal.write('\x1b[3J\x1b[2J\x1b[H');
  }

  void _showPrompt() {
    _lineBuffer = '';
    terminal.write(_prompt);
  }

  /// Keystrokes from the terminal view.
  void _onTerminalInput(String data) {
    final pty = _pty;
    if (pty != null) {
      // An allowed command is running: pass keys straight to it.
      pty.write(Uint8List.fromList(utf8.encode(data)));
      return;
    }
    if (_starting) return;

    // Idle: act as a tiny line editor. Nothing is ever sent to a shell.
    for (final rune in data.runes) {
      if (rune == 0x0D || rune == 0x0A) {
        terminal.write('\r\n');
        final line = _lineBuffer;
        _lineBuffer = '';
        _handleTypedLine(line);
        return; // ignore anything pasted after the newline
      } else if (rune == 0x7F || rune == 0x08) {
        if (_lineBuffer.isNotEmpty) {
          _lineBuffer = _lineBuffer.substring(0, _lineBuffer.length - 1);
          terminal.write('\b \b');
        }
      } else if (rune == 0x03) {
        terminal.write('^C\r\n');
        _showPrompt();
        return;
      } else if (rune == 0x1B) {
        return; // escape sequences (arrows etc.) are ignored
      } else if (rune >= 0x20 && rune != 0x7F) {
        _lineBuffer += String.fromCharCode(rune);
        terminal.write(String.fromCharCode(rune));
      }
    }
  }

  Future<void> _handleTypedLine(String line) async {
    final normalized = line.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) {
      _showPrompt();
      return;
    }
    if (normalized == 'clear') {
      _clearScreen();
      _showPrompt();
      return;
    }
    if (normalized == 'help') {
      terminal.write('Allowed commands:\r\n');
      for (final key in kTypedCommands.keys) {
        terminal.write('  $key\r\n');
      }
      _showPrompt();
      return;
    }

    final command = kTypedCommands[normalized];
    if (command == null) {
      terminal.write(
        'Blocked: "$normalized" is not an allowed command. Type "help".\r\n',
      );
      _showPrompt();
      return;
    }
    await _execute(command, echo: false);
  }

  // ------------------------------------------------------------- process --

  Future<void> _execute(AllowedCommand command, {required bool echo}) async {
    if (_pty != null || _starting) {
      terminal.write(
        'Another command is still running. Press q (or Ctrl+C) to stop it first.\r\n',
      );
      return;
    }
    if (echo) {
      terminal.write('${command.display}\r\n');
    }

    final diagnostic = {
      'doctor',
      'doctor-verbose',
      'devices',
      'version',
      'help',
    }.contains(command.id);
    final dir =
        widget.workingDirectory ?? (diagnostic ? Directory.current.path : null);
    if (dir == null) {
      terminal.write('Open the project folder first.\r\n');
      _showPrompt();
      return;
    }

    _starting = true;
    try {
      _startProcess(command, dir);
    } finally {
      _starting = false;
    }
  }

  void _startProcess(AllowedCommand command, String workingDirectory) {
    // On Windows `flutter` is a .bat file, which needs cmd.exe to launch it.
    // The arguments are still the fixed ones from the whitelist.
    final executable = Platform.isWindows
        ? (Platform.environment['COMSPEC'] ?? 'cmd.exe')
        : command.executable;
    final arguments = Platform.isWindows
        ? ['/d', '/c', command.executable, ...command.arguments]
        : command.arguments;

    try {
      final columns = terminal.viewWidth > 0 ? terminal.viewWidth : 80;
      final rows = terminal.viewHeight > 0 ? terminal.viewHeight : 24;

      final pty =
          widget.ptyFactory?.call(columns, rows, workingDirectory) ??
          Pty.start(
            executable,
            arguments: arguments,
            columns: columns,
            rows: rows,
            workingDirectory: workingDirectory,
            environment: Platform.environment,
          );
      _pty = pty;

      _outputSub = pty.output
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(terminal.write);

      pty.exitCode.then((code) {
        if (!mounted || _pty != pty) return;
        _outputSub?.cancel();
        _outputSub = null;
        _pty = null;
        terminal.write('\r\n[process exited with code $code]\r\n');
        _showPrompt();
      });
    } catch (e) {
      _pty = null;
      terminal.write('Failed to start command: $e\r\n');
      _showPrompt();
    }
  }

  void _killProcess() {
    _outputSub?.cancel();
    _outputSub = null;
    _pty?.kill();
    _pty = null;
    _lineBuffer = '';
  }

  @override
  void dispose() {
    _killProcess();
    scrollController.dispose();
    focusNode.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ UI --

  @override
  Widget build(BuildContext context) {
    if (!widget.isVisible) return const SizedBox.shrink();

    return Container(
      height: widget.height,
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        border: Border(top: BorderSide(color: Color(0xFF3C3C3C), width: 1)),
      ),
      child: Column(
        children: [
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF252526),
              border: Border(
                bottom: BorderSide(color: Color(0xFF3C3C3C), width: 1),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.terminal, size: 14, color: Colors.white70),
                const SizedBox(width: 8),
                const Text(
                  'Terminal',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const Spacer(),
                _TerminalHeaderButton(
                  icon: Icons.delete_outline,
                  tooltip: 'Clear',
                  onPressed: () {
                    _clearScreen();
                    if (_pty == null) _showPrompt();
                    focusNode.requestFocus();
                  },
                ),
                _TerminalHeaderButton(
                  icon: Icons.close,
                  tooltip: 'Close Terminal',
                  onPressed: () => widget.onCloseTerminal?.call(),
                ),
              ],
            ),
          ),
          Expanded(
            child: ScrollConfiguration(
              behavior: const MaterialScrollBehavior().copyWith(
                dragDevices: {
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.touch,
                  PointerDeviceKind.trackpad,
                  PointerDeviceKind.stylus,
                },
              ),
              child: Scrollbar(
                controller: scrollController,
                thumbVisibility: true,
                child: TerminalView(
                  terminal,
                  scrollController: scrollController,
                  hardwareKeyboardOnly: Platform.isWindows,
                  onKeyEvent: (_, event) => event is KeyUpEvent
                      ? KeyEventResult.handled
                      : KeyEventResult.ignored,
                  padding: const EdgeInsets.all(8),
                  focusNode: focusNode,
                  autofocus: true,
                  textStyle: TerminalStyle(
                    fontSize: 14,
                    height: 1.3,
                    fontFamily: Platform.isWindows ? 'Consolas' : 'monospace',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TerminalHeaderButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _TerminalHeaderButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 14, color: Colors.white54),
        ),
      ),
    );
  }
}
