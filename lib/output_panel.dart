import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';

class OutputPanel extends StatefulWidget {
  final bool isVisible;
  final double height;
  final String? workingDirectory;
  final String? initialCommand;
  final VoidCallback? onCommandExecuted;
  final VoidCallback? onCloseTerminal;
  @visibleForTesting
  final Pty Function(int columns, int rows, String? directory)? ptyFactory;

  const OutputPanel({
    super.key,
    required this.isVisible,
    this.height = 250,
    this.workingDirectory,
    this.initialCommand,
    this.onCommandExecuted,
    this.onCloseTerminal,
    this.ptyFactory,
  });

  @override
  State<OutputPanel> createState() => _OutputPanelState();
}

class _OutputPanelState extends State<OutputPanel> {
  final terminal = Terminal(maxLines: 10000);
  final focusNode = FocusNode();
  Pty? pty;
  StreamSubscription<String>? _outputSubscription;

  @override
  void initState() {
    super.initState();
    // Start PTY after first frame if visible
    if (widget.isVisible) {
      WidgetsBinding.instance.endOfFrame.then((_) {
        if (!mounted) return;
        _startPty();
        focusNode.requestFocus();
      });
    }
    if (widget.initialCommand != null) _runCommand(widget.initialCommand!);
  }

  @override
  void didUpdateWidget(OutputPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Start or restart PTY when terminal becomes visible
    if (widget.isVisible && !oldWidget.isVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (pty == null) {
          _startPty();
        }
        focusNode.requestFocus();
      });
    }
    // Restart PTY if working directory changes
    if (widget.workingDirectory != oldWidget.workingDirectory &&
        widget.workingDirectory != null &&
        widget.isVisible) {
      _restartPty();
    }
    // Run initial command if provided
    if (widget.initialCommand != null &&
        widget.initialCommand != oldWidget.initialCommand) {
      _runCommand(widget.initialCommand!);
    }
  }

  void _runCommand(String command) {
    // Always defer to avoid setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.isVisible) return;
      _startPty();
      if (pty == null) return;
      // A terminal's Enter key sends CR, including to Windows ConPTY.
      pty!.write(Uint8List.fromList(utf8.encode('$command\r')));
      focusNode.requestFocus();
      widget.onCommandExecuted?.call();
    });
  }

  void _startPty() {
    if (pty != null) return;

    // Determine shell based on platform
    final shell = Platform.isWindows
        ? 'cmd.exe'
        : Platform.environment['SHELL'] ?? '/bin/bash';

    try {
      // Use default dimensions if terminal hasn't been laid out yet
      final columns = terminal.viewWidth > 0 ? terminal.viewWidth : 80;
      final rows = terminal.viewHeight > 0 ? terminal.viewHeight : 24;

      pty =
          widget.ptyFactory?.call(columns, rows, widget.workingDirectory) ??
          Pty.start(
            shell,
            columns: columns,
            rows: rows,
            workingDirectory: widget.workingDirectory,
            environment: Platform.environment,
          );
      // Terminal input (keystrokes) → send to PTY
      terminal.onOutput = (data) {
        pty?.write(Uint8List.fromList(utf8.encode(data)));
      };

      // Handle terminal resize
      terminal.onResize = (width, height, pixelWidth, pixelHeight) {
        pty?.resize(height, width);
      };
      // Decode across chunks: ConPTY may split a UTF-8 character between reads.
      _outputSubscription = pty!.output
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(terminal.write);
    } catch (e) {
      terminal.write('Failed to start terminal: $e\r\n');
    }
  }

  void _restartPty() {
    _outputSubscription?.cancel();
    pty?.kill();
    pty = null;
    terminal.buffer.clear();
    _startPty();
  }

  @override
  void dispose() {
    _outputSubscription?.cancel();
    pty?.kill();
    focusNode.dispose();
    super.dispose();
  }

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
          // Terminal header
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
                    // Clear the view without injecting text into a running app.
                    terminal.write('\x1b[2J\x1b[H');
                    focusNode.requestFocus();
                  },
                ),
                _TerminalHeaderButton(
                  icon: Icons.close,
                  tooltip: 'Close Terminal',
                  onPressed: () {
                    widget.onCloseTerminal?.call();
                  },
                ),
              ],
            ),
          ),
          // Terminal view
          Expanded(
            child: TerminalView(
              terminal,
              focusNode: focusNode,
              autofocus: true,
              // Windows desktop keystrokes must reach ConPTY even when the
              // editor's native WebView has interrupted the text-input client.
              hardwareKeyboardOnly: Platform.isWindows,
              onKeyEvent: (_, event) => event is KeyUpEvent
                  ? KeyEventResult.handled
                  : KeyEventResult.ignored,
              padding: const EdgeInsets.all(8),
              textStyle: const TerminalStyle(
                fontSize: 14,
                height: 1.3,
                fontFamily: 'Consolas',
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
