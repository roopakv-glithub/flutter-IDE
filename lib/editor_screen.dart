import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_monaco/flutter_monaco.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:webview_flutter/webview_flutter.dart';
import 'models/file_system_entity.dart';
import 'models/web_tab.dart';
import 'config/event_config.dart';
import 'policy/project_policy.dart';
import 'services/file_service.dart';
import 'services/pubspec_edit.dart';
import 'file_tree.dart';
import 'flutter_sidebar.dart';
import 'output_panel.dart';
import 'pubdev_sidebar.dart';
import 'widgets/editor/activity_bar.dart';
import 'widgets/editor/editor_tabs.dart';
import 'widgets/editor/status_bar.dart';
import 'widgets/editor/welcome_screen.dart';
import 'widgets/editor/quick_open_dialog.dart';
import 'widgets/editor/resize_handles.dart';

void _noop() {}

// Global function to run terminal commands from anywhere
void Function(String command)? _globalRunTerminalCommand;

/// Run an ALLOWED command in the terminal from anywhere in the app.
/// Anything not in [kTypedCommands] is ignored.
void runTerminalCommand(String command) {
  _globalRunTerminalCommand?.call(command);
}

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  FileNodeDirectory? _rootNode;
  MonacoController? _editorController;
  final List<FileNodeFile> _openFiles = [];
  FileNodeFile? _activeFile;
  String _currentCode = '// Open a file to start editing\n';
  int _selectedActivityIndex = 0;

  // Web tabs state
  final List<WebTab> _webTabs = [];
  WebTab? _activeWebTab;
  final Map<String, WebViewController> _webViewControllers = {};

  // Output panel state
  bool _isOutputVisible = false;
  double _terminalHeight = 250;

  // Terminal command to run (always one of the whitelisted commands)
  AllowedCommand? _pendingCommand;

  // Autosave bookkeeping
  bool _autoSaveRunning = false;
  bool _loadingFile = false;

  // Resizable sidebar width
  double _sidebarWidth = 250;

  // File watchers for detecting external changes
  final Map<String, StreamSubscription<FileSystemEvent>> _fileWatchers = {};

  // Track files we recently saved to avoid reloading from our own changes
  final Set<String> _recentlySavedFiles = {};

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvent);
    // Register global terminal command handler
    _globalRunTerminalCommand = _runTypedCommand;
  }

  // ---------------------------------------------------------------------
  // Event rules
  // ---------------------------------------------------------------------

  ProjectPolicy? get _policy =>
      _rootNode == null ? null : ProjectPolicy(_rootNode!.path);

  bool _canEdit(String path) => _policy?.canEdit(path) ?? false;

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  FileNodeDirectory? _findDir(String name) {
    final root = _rootNode;
    if (root == null) return null;
    for (final child in root.children) {
      if (child is FileNodeDirectory && child.name == name) return child;
    }
    return null;
  }

  /// Source of truth for a file while it is being edited.
  Future<void> _flushActiveFile() async {
    final file = _activeFile;
    final controller = _editorController;
    if (file == null || controller == null || _loadingFile) return;
    if (!_canEdit(file.path)) return;
    try {
      final content = await controller.getValue();
      if (content == _currentCode) return;
      // Don't save if content became empty but wasn't before.
      if (content.trim().isEmpty && _currentCode.trim().isNotEmpty) return;
      // The active file may have changed while we awaited.
      if (_activeFile?.path != file.path) return;
      _currentCode = content;
      _recentlySavedFiles.add(file.path);
      await fileService.saveFile(file, content);
      Future.delayed(const Duration(milliseconds: 500), () {
        _recentlySavedFiles.remove(file.path);
      });
    } catch (e) {
      // Save error
    }
  }

  Future<void> _addApprovedPackage(String name) async {
    final command = pubAddCommand(name);
    if (command == null) {
      _toast('"$name" is not an approved package.');
      return;
    }
    if (_rootNode == null) {
      _toast('Open the project folder first.');
      return;
    }
    _runCommand(command);
    // pubspec.yaml is read-only for participants; refresh it if it is showing.
    final active = _activeFile;
    if (active != null && p.basename(active.path) == 'pubspec.yaml') {
      Future.delayed(const Duration(seconds: 6), () {
        if (mounted && _activeFile?.path == active.path) _openFile(active);
      });
    }
  }

  Future<void> _addImage() async {
    final root = _rootNode;
    if (root == null) {
      _toast('Open the project folder first.');
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: kAllowedImageExtensions,
    );
    final sourcePath = result?.files.single.path;
    if (sourcePath == null) return;

    try {
      final source = File(sourcePath);
      final size = await source.length();
      if (size > kMaxImageBytes) {
        _toast(
          'Image is too large (max ${kMaxImageBytes ~/ (1024 * 1024)} MB).',
        );
        return;
      }

      final ext = p.extension(sourcePath).replaceFirst('.', '').toLowerCase();
      if (!kAllowedImageExtensions.contains(ext)) {
        _toast(
          'Only ${kAllowedImageExtensions.join(', ')} images are allowed.',
        );
        return;
      }

      final assetsDir = Directory(p.join(root.path, kAssetsFolder));
      await assetsDir.create(recursive: true);

      var name = ProjectPolicy.sanitizeAssetName(p.basename(sourcePath));
      final stem = p.basenameWithoutExtension(name);
      var counter = 1;
      while (await File(p.join(assetsDir.path, name)).exists()) {
        name = '${stem}_$counter.$ext';
        counter++;
      }

      final destPath = p.join(assetsDir.path, name);
      await source.copy(destPath);
      await _ensureAssetsDeclared(root.path);

      setState(() {
        _addToTree(root, [
          ...kAssetsFolder.split('/'),
        ], FileNodeFile(name, destPath));
      });
      _toast(
        'Added assets/images/$name  -  use it as Image.asset(\'$kAssetsFolder/$name\')',
      );
    } catch (e) {
      _toast('Could not add image: $e');
    }
  }

  /// Adds [file] to the in-memory tree, creating folders as needed.
  void _addToTree(
    FileNodeDirectory root,
    List<String> folders,
    FileNodeFile file,
  ) {
    var current = root;
    for (final folder in folders) {
      FileNodeDirectory? next;
      for (final child in current.children) {
        if (child is FileNodeDirectory && child.name == folder) next = child;
      }
      if (next == null) {
        next = FileNodeDirectory(
          folder,
          p.join(current.path, folder),
          children: <FileNode>[],
        );
        current.children.add(next);
      }
      current = next;
    }
    current.children.add(file);
  }

  /// Makes sure pubspec.yaml lists the assets folder (done by the IDE, because
  /// participants cannot edit pubspec.yaml themselves).
  Future<void> _ensureAssetsDeclared(String rootPath) async {
    final pubspec = File(p.join(rootPath, 'pubspec.yaml'));
    if (!await pubspec.exists()) return;
    final text = await pubspec.readAsString();
    final updated = addAssetsDeclaration(text, '$kAssetsFolder/');
    if (updated != null) await pubspec.writeAsString(updated);
  }

  WebViewController _getOrCreateWebViewController(String url) {
    if (!_webViewControllers.containsKey(url)) {
      var hasCompletedInitialLoad = false;

      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (String url) {
              hasCompletedInitialLoad = true;
            },
            onNavigationRequest: (NavigationRequest request) {
              // Allow initial page load and redirects during load
              if (!hasCompletedInitialLoad) {
                return NavigationDecision.navigate;
              }

              // After initial load, open all navigations in new tabs
              _openWebTab(_getTitleFromUrl(request.url), request.url);
              return NavigationDecision.prevent;
            },
          ),
        )
        ..loadRequest(Uri.parse(url));
      _webViewControllers[url] = controller;
    }
    return _webViewControllers[url]!;
  }

  String _getTitleFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      // Extract a readable title from the URL
      if (uri.host.contains('github.com')) {
        final parts = uri.pathSegments;
        if (parts.length >= 2) {
          return '${parts[0]}/${parts[1]}';
        }
      }
      if (uri.host.contains('pub.dev')) {
        final parts = uri.pathSegments;
        if (parts.isNotEmpty && parts[0] == 'packages' && parts.length >= 2) {
          return parts[1];
        }
      }
      return uri.host;
    } catch (e) {
      return url;
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvent);
    // Clean up global terminal command handler
    _globalRunTerminalCommand = null;
    // Clean up all file watchers
    for (final subscription in _fileWatchers.values) {
      subscription.cancel();
    }
    _fileWatchers.clear();
    super.dispose();
  }

  void _watchFile(FileNodeFile file) {
    // Cancel existing watcher for this file
    _fileWatchers[file.path]?.cancel();

    try {
      final fileEntity = File(file.path);
      final subscription = fileEntity
          .watch(events: FileSystemEvent.modify)
          .listen(
            (event) {
              if (event.type == FileSystemEvent.modify) {
                // Skip reload if we recently saved this file ourselves
                if (_recentlySavedFiles.contains(file.path)) {
                  return;
                }
                _reloadFileContent(file);
              }
            },
            onError: (error) {
              // File watching failed, ignore silently
            },
          );
      _fileWatchers[file.path] = subscription;
    } catch (e) {
      // File watching not supported or failed
    }
  }

  Future<void> _reloadFileContent(FileNodeFile file) async {
    try {
      final content = await fileService.readFile(file);
      if (content != null && mounted) {
        // Only update if this is the active file
        if (file.path == _activeFile?.path) {
          setState(() {
            _currentCode = content;
          });
          _editorController?.setValue(content);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${file.name} was modified externally and reloaded',
                ),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
      }
    } catch (e) {
      // Failed to reload file
    }
  }

  void _stopWatchingFile(String path) {
    _fileWatchers[path]?.cancel();
    _fileWatchers.remove(path);
  }

  bool _handleGlobalKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    final isMetaPressed =
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;

    if (isMetaPressed && event.logicalKey == LogicalKeyboardKey.keyP) {
      _showQuickOpen();
      return true; // Event handled
    }

    if (isMetaPressed && event.logicalKey == LogicalKeyboardKey.keyO) {
      _pickDirectory();
      return true; // Event handled
    }

    return false; // Event not handled
  }

  Future<void> _pickDirectory() async {
    final root = await fileService.pickDirectory();
    if (root != null && mounted) {
      await _flushActiveFile();
      for (final path in _fileWatchers.keys.toList()) {
        _stopWatchingFile(path);
      }
      setState(() {
        _openFiles.clear();
        _activeFile = null;
        _selectedDirectory = null;
        _editorController = null;
        _rootNode = root;
      });
    }
  }

  FileNodeDirectory? _selectedDirectory;

  Future<void> _createNewFile() async {
    final targetDir = _selectedDirectory ?? _findDir(kEditableFolder);
    if (targetDir == null) return;
    if (!(_policy?.canCreateIn(targetDir.path) ?? false)) {
      _toast('You can only create files inside $kEditableFolder/.');
      return;
    }

    final name = await _showNameDialog('New File', 'Enter file name (.dart)');
    if (name == null || name.isEmpty) return;
    if (!ProjectPolicy.isValidDartFileName(name)) {
      _toast(
        'File names must be simple and end in .dart (e.g. my_screen.dart).',
      );
      return;
    }

    final newFile = await fileService.createFile(targetDir.path, name);
    if (newFile != null) {
      setState(() {
        targetDir.children.add(newFile);
      });
      await _openFile(newFile);
    } else {
      _toast('Could not create $name (it may already exist).');
    }
  }

  Future<void> _createNewFolder() async {
    final targetDir = _selectedDirectory ?? _findDir(kEditableFolder);
    if (targetDir == null) return;
    if (!(_policy?.canCreateIn(targetDir.path) ?? false)) {
      _toast('You can only create folders inside $kEditableFolder/.');
      return;
    }

    final name = await _showNameDialog('New Folder', 'Enter folder name');
    if (name == null || name.isEmpty) return;
    if (!ProjectPolicy.isValidName(name)) {
      _toast('Folder names can only use letters, numbers, _ - and .');
      return;
    }

    final newDir = await fileService.createDirectory(targetDir.path, name);
    if (newDir != null) {
      setState(() {
        targetDir.children.add(newDir);
      });
    } else {
      _toast('Could not create $name (it may already exist).');
    }
  }

  void _startAutoSave() {
    if (_autoSaveRunning) return;
    _autoSaveRunning = true;
    Future.doWhile(() async {
      if (!mounted) return false;
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return false;
      await _flushActiveFile();
      return true;
    });
  }

  void _openWebTab(String title, String url) {
    // Check if tab already exists
    final existingTab = _webTabs.where((t) => t.url == url).firstOrNull;
    if (existingTab != null) {
      setState(() {
        _activeWebTab = existingTab;
        _activeFile = null;
      });
      return;
    }

    final newTab = WebTab(title: title, url: url);
    setState(() {
      _webTabs.add(newTab);
      _activeWebTab = newTab;
      _activeFile = null;
    });
  }

  void _closeWebTab(WebTab tab) {
    setState(() {
      _webTabs.remove(tab);
      _webViewControllers.remove(tab.url);
      if (_activeWebTab == tab) {
        if (_webTabs.isNotEmpty) {
          _activeWebTab = _webTabs.last;
        } else if (_openFiles.isNotEmpty) {
          _activeWebTab = null;
          _activeFile = _openFiles.last;
        } else {
          _activeWebTab = null;
        }
      }
    });
  }

  /// Runs a whitelisted command in the terminal panel.
  Future<void> _runCommand(AllowedCommand command) async {
    await _flushActiveFile();
    if (!mounted) return;
    setState(() {
      _isOutputVisible = true;
      _pendingCommand = command;
    });
  }

  /// Same, but from text: only exact whitelist matches are accepted.
  void _runTypedCommand(String text) {
    final normalized = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final command = kTypedCommands[normalized];
    if (command == null) {
      _toast('Blocked: "$normalized" is not an allowed command.');
      return;
    }
    _runCommand(command);
  }

  void _toggleOutput() {
    setState(() {
      _isOutputVisible = !_isOutputVisible;
    });
  }

  List<FileNodeFile> _collectAllFiles(FileNodeDirectory dir) {
    final files = <FileNodeFile>[];

    void traverse(FileNodeDirectory directory) {
      for (final child in directory.children) {
        if (child is FileNodeFile) {
          files.add(child);
        } else if (child is FileNodeDirectory) {
          traverse(child);
        }
      }
    }

    traverse(dir);
    return files;
  }

  void _showQuickOpen() {
    if (_rootNode == null) return;

    final allFiles = _collectAllFiles(_rootNode!);

    showDialog(
      context: context,
      builder: (context) => QuickOpenDialog(
        files: allFiles,
        rootPath: _rootNode!.path,
        onFileSelected: (file) {
          Navigator.of(context).pop();
          _openFile(file);
        },
      ),
    );
  }

  bool _removeFromTree(FileNodeDirectory dir, FileNode target) {
    if (dir.children.remove(target)) return true;
    for (final child in dir.children) {
      if (child is FileNodeDirectory && _removeFromTree(child, target)) {
        return true;
      }
    }
    return false;
  }

  Future<void> _deleteNode(FileNode node) async {
    final isDirectory = node is FileNodeDirectory;
    final name = node.name;

    if (!(_policy?.canDelete(node.path, isDirectory: isDirectory) ?? false)) {
      _toast('"$name" is protected and cannot be deleted.');
      return;
    }

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${isDirectory ? 'Folder' : 'File'}'),
        content: Text(
          'Are you sure you want to delete "$name"?${isDirectory ? '\n\nThis will delete all contents.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await _flushActiveFile();
    _loadingFile = true;

    // Perform deletion
    bool success;
    if (isDirectory) {
      success = await fileService.deleteDirectory(node.path);
    } else {
      success = await fileService.deleteFile(node.path);
    }

    _loadingFile = false;
    if (!mounted) return;
    if (success) {
      final affected = _openFiles
          .where(
            (file) =>
                file.path == node.path || p.isWithin(node.path, file.path),
          )
          .toList();
      final activeDeleted = affected.any(
        (file) => file.path == _activeFile?.path,
      );
      for (final file in affected) {
        _stopWatchingFile(file.path);
      }
      setState(() {
        _openFiles.removeWhere((file) => affected.contains(file));
        if (activeDeleted) {
          _activeFile = null;
          _currentCode = '// Open a file to start editing\n';
        }
      });
      if (activeDeleted && _openFiles.isNotEmpty) {
        await _openFile(_openFiles.last);
      }
      if (_selectedDirectory != null &&
          (node.path == _selectedDirectory!.path ||
              p.isWithin(node.path, _selectedDirectory!.path))) {
        _selectedDirectory = null;
      }

      // Refresh the file tree
      if (_rootNode != null) {
        setState(() {
          _removeFromTree(_rootNode!, node);
          if (_selectedDirectory?.path == node.path) _selectedDirectory = null;
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Deleted $name')));
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete $name')));
      }
    }
  }

  Future<void> _renameNode(FileNode node) async {
    final directory = node is FileNodeDirectory;
    final name = await _showNameDialog(
      directory ? 'Rename Folder' : 'Rename File',
      'New name',
    );
    if (name == null || name == node.name || !mounted) return;
    if (!(_policy?.canRename(node.path, name, isDirectory: directory) ??
        false)) {
      _toast(
        'Use a valid ${directory ? "folder" : ".dart file"} name inside lib/.',
      );
      return;
    }
    await _flushActiveFile();
    _loadingFile = true;
    final success = await fileService.rename(node.path, name);
    _loadingFile = false;
    if (!mounted) return;
    if (!success) {
      _toast(
        'Could not rename ${node.name}; check whether the name already exists.',
      );
      return;
    }
    final newPath = p.join(p.dirname(node.path), name);
    FileNode remap(FileNode item) {
      final path = item.path == node.path
          ? newPath
          : p.join(newPath, p.relative(item.path, from: node.path));
      if (item is FileNodeDirectory) {
        return FileNodeDirectory(
          p.basename(path),
          path,
          children: item.children.map(remap).toList(),
        );
      }
      return FileNodeFile(p.basename(path), path);
    }

    final replacement = remap(node);
    void replaceIn(FileNodeDirectory parent) {
      final index = parent.children.indexWhere(
        (child) => child.path == node.path,
      );
      if (index >= 0) {
        parent.children[index] = replacement;
        return;
      }
      for (final child in parent.children.whereType<FileNodeDirectory>()) {
        replaceIn(child);
      }
    }

    setState(() {
      replaceIn(_rootNode!);
      for (var i = 0; i < _openFiles.length; i++) {
        final file = _openFiles[i];
        if (file.path == node.path || p.isWithin(node.path, file.path)) {
          _stopWatchingFile(file.path);
          final updated = remap(file) as FileNodeFile;
          _openFiles[i] = updated;
          if (_activeFile?.path == file.path) _activeFile = updated;
          _watchFile(updated);
        }
      }
      if (_selectedDirectory != null &&
          (_selectedDirectory!.path == node.path ||
              p.isWithin(node.path, _selectedDirectory!.path))) {
        _selectedDirectory = null;
      }
    });
    _toast('Renamed to $name');
  }

  Future<String?> _showNameDialog(String title, String label) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(labelText: label),
          autofocus: true,
          onSubmitted: (_) => Navigator.of(context).pop(controller.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(title.startsWith('Rename') ? 'Rename' : 'Create'),
          ),
        ],
      ),
    );
  }

  static const _imageExtensions = {'.png', '.jpg', '.jpeg', '.gif', '.webp'};

  bool _isImage(String path) =>
      _imageExtensions.contains(p.extension(path).toLowerCase());

  Future<void> _openFile(FileNodeFile file) async {
    await _flushActiveFile();
    _loadingFile = true;
    try {
      // Images are shown as pictures, not read as text.
      final content = _isImage(file.path)
          ? ''
          : (await fileService.readFile(file) ?? '');
      if (!mounted) return;

      final editable = _canEdit(file.path);
      final isNew = !_openFiles.any((f) => f.path == file.path);

      setState(() {
        if (isNew) _openFiles.add(file);
        _activeFile = file;
        _activeWebTab = null;
        _currentCode = content;
        if (!editable) _editorController = null; // editor is not on screen
      });
      if (isNew) _watchFile(file);

      if (editable) {
        try {
          _editorController?.setValue(_currentCode);
          _editorController?.setLanguage(_getLanguage(file.path));
        } catch (e) {
          // Editor not ready yet: it will start from initialValue instead.
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error reading file: $e')));
      }
    } finally {
      _loadingFile = false;
    }
  }

  Future<void> _closeFile(FileNodeFile file) async {
    await _flushActiveFile();
    if (!mounted) return;
    // Stop watching this file
    _stopWatchingFile(file.path);

    setState(() {
      _openFiles.removeWhere((f) => f.path == file.path);
      if (_activeFile?.path == file.path) {
        if (_openFiles.isNotEmpty) {
          final next = _openFiles.last;
          _activeFile = null;
          _openFile(
            next,
          ); // Load the new active file without saving stale editor text.
        } else {
          _activeFile = null;
          _currentCode = '// Open a file to start editing\n';
          try {
            _editorController?.setValue(_currentCode);
          } catch (e) {
            // Editor is not on screen
          }
        }
      }
    });
  }

  MonacoLanguage _getLanguage(String path) {
    final ext = p.extension(path).toLowerCase();
    switch (ext) {
      case '.dart':
        return MonacoLanguage.dart;
      case '.js':
        return MonacoLanguage.javascript;
      case '.ts':
        return MonacoLanguage.typescript;
      case '.html':
        return MonacoLanguage.html;
      case '.css':
        return MonacoLanguage.css;
      case '.json':
        return MonacoLanguage.json;
      case '.yaml':
      case '.yml':
        return MonacoLanguage.yaml;
      case '.md':
        return MonacoLanguage.markdown;
      case '.sql':
        return MonacoLanguage.sql;
      case '.xml':
        return MonacoLanguage.xml;
      default:
        return MonacoLanguage.dart;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                // Activity Bar
                _buildActivityBar(),

                // Sidebar with resizable width
                if (_selectedActivityIndex == 0)
                  SizedBox(width: _sidebarWidth, child: _buildSidebar()),
                if (_selectedActivityIndex == 1)
                  SizedBox(
                    width: _sidebarWidth,
                    child: FlutterSidebar(
                      rootNode: _rootNode,
                      onFileSelected: _openFile,
                      onPickDirectory: _pickDirectory,
                    ),
                  ),
                if (_selectedActivityIndex == 2)
                  SizedBox(
                    width: _sidebarWidth + 50, // PubDev sidebar is wider
                    child: PubDevSidebar(
                      onOpenInBrowser: _openWebTab,
                      onAddPackage: _addApprovedPackage,
                    ),
                  ),

                // Horizontal resize handle for sidebar
                HorizontalResizeHandle(
                  onDrag: (delta) {
                    setState(() {
                      _sidebarWidth = (_sidebarWidth + delta).clamp(
                        150.0,
                        500.0,
                      );
                    });
                  },
                ),

                // Main Editor Area
                Expanded(
                  child: Column(
                    children: [
                      // Tab Bar
                      _buildTabBar(),

                      // Breadcrumbs
                      if (_activeFile != null && _activeWebTab == null)
                        _buildBreadcrumbs(),

                      // Editor, WebView, or Welcome Screen
                      Expanded(
                        child: _activeWebTab != null
                            ? _buildWebView()
                            : _activeFile == null
                            ? WelcomeScreen(
                                rootName: _rootNode?.name,
                                onPickDirectory: _pickDirectory,
                                onCreateNewFile: _rootNode != null
                                    ? _createNewFile
                                    : null,
                              )
                            : _canEdit(_activeFile!.path)
                            ? _buildEditor()
                            : _buildReadOnlyViewer(),
                      ),

                      // Vertical resize handle for terminal
                      if (_isOutputVisible)
                        VerticalResizeHandle(
                          onDrag: (delta) {
                            setState(() {
                              _terminalHeight = (_terminalHeight - delta).clamp(
                                100.0,
                                500.0,
                              );
                            });
                          },
                        ),

                      // Output Panel (Terminal)
                      OutputPanel(
                        isVisible: _isOutputVisible,
                        height: _terminalHeight,
                        workingDirectory: _rootNode?.path,
                        pendingCommand: _pendingCommand,
                        onCloseTerminal: () {
                          setState(() {
                            _isOutputVisible = false;
                          });
                        },
                        onCommandExecuted: () {
                          setState(() {
                            _pendingCommand = null;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Status Bar
          _buildStatusBar(),
        ],
      ),
    );
  }

  Widget _buildActivityBar() {
    final activities = [
      (Icons.insert_drive_file_outlined, 'Explorer'),
      (Icons.explore, 'Flutter explorer'),
      (Icons.inventory_2_outlined, 'Approved Packages'),
    ];

    return Container(
      width: 48,
      color: const Color(0xFF333333),
      child: Column(
        children: [
          ...activities.asMap().entries.map((entry) {
            final index = entry.key;
            final (icon, tooltip) = entry.value;
            final isSelected = index == _selectedActivityIndex;
            return ActivityBarItem(
              icon: icon,
              tooltip: tooltip,
              isSelected: isSelected,
              onTap: () => setState(() => _selectedActivityIndex = index),
            );
          }),
          const Spacer(),
          ActivityBarItem(
            icon: Icons.terminal,
            tooltip: 'Terminal',
            isSelected: false,
            onTap: () {
              setState(() {
                _isOutputVisible = !_isOutputVisible;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      color: const Color(0xFF181818),
      child: Column(
        children: [
          // Explorer Header
          if (_rootNode != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              width: double.infinity,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      SidebarIconButton(
                        icon: Icons.create_new_folder_outlined,
                        tooltip: 'New Folder',
                        onPressed: _createNewFolder,
                      ),
                      const SizedBox(width: 4),
                      SidebarIconButton(
                        icon: Icons.note_add_outlined,
                        tooltip: 'New File',
                        onPressed: _createNewFile,
                      ),
                      const SizedBox(width: 4),
                      SidebarIconButton(
                        icon: Icons.add_photo_alternate_outlined,
                        tooltip: 'Add Image',
                        onPressed: _addImage,
                      ),
                      const SizedBox(width: 4),
                      SidebarIconButton(
                        icon: Icons.folder_open,
                        tooltip: 'Open Folder',
                        onPressed: _pickDirectory,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          // Project Header
          if (_rootNode != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Color(0xFF3C3C3C), width: 1),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.keyboard_arrow_down,
                    size: 16,
                    color: Colors.white70,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _rootNode!.name.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

          Expanded(
            child: FileTree(
              rootNode: _rootNode,
              onFileSelected: _openFile,
              onDirectorySelected: (dir) {
                setState(() {
                  _selectedDirectory = dir;
                });
              },
              onPickDirectory: _pickDirectory,
              onDelete: _deleteNode,
              onRename: _renameNode,
              canRename: (node) =>
                  _policy?.canDelete(
                    node.path,
                    isDirectory: node is FileNodeDirectory,
                  ) ??
                  false,
              canDelete: (node) =>
                  _policy?.canDelete(
                    node.path,
                    isDirectory: node is FileNodeDirectory,
                  ) ??
                  false,
              isLocked: (node) => node is FileNodeFile && !_canEdit(node.path),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      height: 35,
      decoration: const BoxDecoration(
        color: Color(0xFF252526),
        border: Border(bottom: BorderSide(color: Color(0xFF3C3C3C), width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                // File tabs
                ..._openFiles.map((file) {
                  final isActive =
                      file.path == _activeFile?.path && _activeWebTab == null;
                  return EditorTab(
                    file: file,
                    isActive: isActive,
                    onTap: () {
                      setState(() {
                        _activeWebTab = null;
                      });
                      _openFile(file);
                    },
                    onClose: () => _closeFile(file),
                    icon: _getFileIcon(file.name),
                  );
                }),
                // Web tabs
                ..._webTabs.map((webTab) {
                  final isActive = webTab == _activeWebTab;
                  return WebEditorTab(
                    webTab: webTab,
                    isActive: isActive,
                    onTap: () {
                      setState(() {
                        _activeWebTab = webTab;
                        _activeFile = null;
                      });
                    },
                    onClose: () => _closeWebTab(webTab),
                  );
                }),
              ],
            ),
          ),

          // Actions
          if (_rootNode != null)
            IconButton(
              icon: const Icon(
                Icons.fact_check_outlined,
                color: Colors.white54,
                size: 20,
              ),
              tooltip: 'Analyze (flutter analyze)',
              onPressed: () => _runCommand(kCmdAnalyze),
              padding: const EdgeInsets.all(8),
            ),

          if (_rootNode != null)
            IconButton(
              icon: const Icon(Icons.play_arrow, color: Colors.green, size: 20),
              tooltip: 'Run in Chrome (flutter run -d $kRunDevice)',
              onPressed: () => _runCommand(kCmdRunChrome),
              padding: const EdgeInsets.all(8),
            ),

          if (_rootNode != null)
            IconButton(
              icon: Icon(
                _isOutputVisible ? Icons.expand_more : Icons.expand_less,
                color: Colors.white54,
                size: 20,
              ),
              tooltip: _isOutputVisible ? 'Hide Output' : 'Show Output',
              onPressed: _toggleOutput,
              padding: const EdgeInsets.all(8),
            ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildBreadcrumbs() {
    final parts = _activeFile!.path.split('/');
    final relevantParts = <String>[];
    bool foundRoot = false;

    for (final part in parts) {
      if (part == _rootNode?.name) foundRoot = true;
      if (foundRoot) relevantParts.add(part);
    }

    return Container(
      height: 22,
      color: const Color(0xFF1E1E1E),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          for (int i = 0; i < relevantParts.length; i++) ...[
            if (i > 0)
              const Icon(Icons.chevron_right, size: 14, color: Colors.white30),
            Text(
              relevantParts[i],
              style: TextStyle(
                color: i == relevantParts.length - 1
                    ? Colors.white70
                    : Colors.white38,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEditor() {
    return Listener(
      child: MonacoEditor(
        loadingBuilder: (context) => Container(
          color: const Color(0xFF1E1E1E),
          child: const Center(
            child: CircularProgressIndicator(color: Color(0xFF42A5F5)),
          ),
        ),
        initialValue: _currentCode,
        options: const EditorOptions(
          language: MonacoLanguage.dart,
          theme: MonacoTheme.vsDark,
          automaticLayout: true,
          readOnly: false,
          smoothScrolling: true,
        ),
        onReady: (controller) {
          _editorController = controller;
          _startAutoSave();
        },
      ),
    );
  }

  Widget _buildReadOnlyViewer() {
    final file = _activeFile!;
    return Container(
      color: const Color(0xFF1E1E1E),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: const Color(0xFF3A3A1E),
            child: const Row(
              children: [
                Icon(Icons.lock_outline, size: 14, color: Colors.amber),
                SizedBox(width: 8),
                Text(
                  'Read-only - this file is locked for the event.',
                  style: TextStyle(color: Colors.amber, fontSize: 12),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isImage(file.path)
                ? Center(child: Image.file(File(file.path)))
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      width: double.infinity,
                      child: SelectableText(
                        _currentCode,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebView() {
    if (_activeWebTab == null) return const SizedBox.shrink();

    return Container(
      color: const Color(0xFF1E1E1E),
      child: Column(
        children: [
          // URL bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: const Color(0xFF252526),
            child: Row(
              children: [
                const Icon(Icons.public, size: 16, color: Colors.white54),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3C3C3C),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _activeWebTab!.url,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // WebView content
          Expanded(
            child: WebViewWidget(
              controller: _getOrCreateWebViewController(_activeWebTab!.url),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    final language = _activeFile != null
        ? _getLanguage(_activeFile!.path).name
        : 'Plain Text';

    return Container(
      height: 22,
      color: const Color(0xFF007ACC),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          if (_activeFile != null && !_canEdit(_activeFile!.path)) ...[
            const StatusBarItem(
              icon: Icons.lock_outline,
              label: 'Read-only',
              onPressed: _noop,
            ),
          ],
          const Spacer(),

          // Right side
          StatusBarItem(label: 'Spaces: 2', onPressed: () {}),
          const StatusBarDivider(),
          StatusBarItem(label: 'UTF-8', onPressed: () {}),
          const StatusBarDivider(),
          StatusBarItem(label: language, onPressed: () {}),
        ],
      ),
    );
  }

  Icon _getFileIcon(String fileName) {
    final ext = p.extension(fileName).toLowerCase();
    IconData icon = Icons.insert_drive_file_outlined;
    Color color = Colors.grey;

    switch (ext) {
      case '.dart':
        icon = FontAwesomeIcons.dartLang.data;
        color = const Color(0xFF42A5F5);
        break;
      case '.html':
        icon = Icons.html;
        color = const Color(0xFFE65100);
        break;
      case '.css':
        icon = Icons.css;
        color = const Color(0xFF1E88E5);
        break;
      case '.js':
      case '.ts':
        icon = Icons.javascript;
        color = const Color(0xFFFFCA28);
        break;
      case '.json':
        icon = Icons.data_object;
        color = const Color(0xFF66BB6A);
        break;
      default:
      // keep defaults
    }
    return Icon(icon, size: 14, color: color);
  }
}
