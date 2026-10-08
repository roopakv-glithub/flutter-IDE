import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';

class LinuxCodeEditor extends StatelessWidget {
  const LinuxCodeEditor({super.key, required this.controller});

  final CodeController controller;

  @override
  Widget build(BuildContext context) {
    return CodeTheme(
      data: CodeThemeData(styles: monokaiSublimeTheme),
      child: CodeField(
        controller: controller,
        expands: true,
        wrap: false,
        background: const Color(0xFF1E1E1E),
        cursorColor: const Color(0xFFAEAFAD),
        padding: const EdgeInsets.all(12),
        textStyle: const TextStyle(
          color: Color(0xFFD4D4D4),
          fontFamily: 'monospace',
          fontSize: 14,
          height: 1.5,
        ),
        gutterStyle: const GutterStyle(
          width: 48,
          showErrors: false,
          showFoldingHandles: false,
          background: Color(0xFF1E1E1E),
        ),
      ),
    );
  }
}
