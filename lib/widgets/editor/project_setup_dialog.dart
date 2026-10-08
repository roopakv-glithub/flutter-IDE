import 'package:flutter/material.dart';
import '../../services/project_setup_service.dart';

class ProjectSetupDialog extends StatefulWidget {
  const ProjectSetupDialog({
    super.key,
    required this.directory,
    required this.service,
  });
  final String directory;
  final ProjectSetupService service;

  @override
  State<ProjectSetupDialog> createState() => _ProjectSetupDialogState();
}

class _ProjectSetupDialogState extends State<ProjectSetupDialog> {
  final _scroll = ScrollController();
  String _output = '';
  bool _running = true;

  @override
  void initState() {
    super.initState();
    _run();
  }

  void _append(String text) {
    if (!mounted) return;
    setState(() => _output += text);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _run() async {
    try {
      final code = await widget.service.createWebProject(
        widget.directory,
        onOutput: _append,
      );
      if (!mounted) return;
      setState(() => _running = false);
      if (code == 0) {
        Navigator.of(context).pop(true);
      } else {
        _append(
          '\nSet up failed (exit code $code). Fix the error above and try again.\n',
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _running = false);
      _append(
        '\nCould not set up the project: $error\nCheck that Flutter is installed and available on PATH.\n',
      );
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_running,
    child: AlertDialog(
      title: Text(_running ? 'Setting Up Project' : 'Project Setup Failed'),
      content: SizedBox(
        width: 640,
        height: 360,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.directory,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            if (_running) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
            ],
            Expanded(
              child: Scrollbar(
                controller: _scroll,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _scroll,
                  child: SelectableText(
                    _output,
                    style: const TextStyle(
                      fontFamily: 'Consolas',
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (!_running)
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Close'),
          ),
      ],
    ),
  );
}
