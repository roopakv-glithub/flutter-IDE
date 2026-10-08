import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:path/path.dart' as p;
import 'models/file_system_entity.dart';

class FileTree extends StatefulWidget {
  final FileNodeDirectory? rootNode;
  final Function(FileNodeFile) onFileSelected;
  final Function(FileNodeDirectory) onDirectorySelected;
  final VoidCallback? onPickDirectory;
  final Function(FileNode)? onDelete;
  final Function(FileNode)? onRename;

  /// If given, nodes for which this returns false get no Delete menu.
  final bool Function(FileNode)? canDelete;
  final bool Function(FileNode)? canRename;

  /// If given, files for which this returns true show a lock icon.
  final bool Function(FileNode)? isLocked;

  const FileTree({
    super.key,
    required this.rootNode,
    required this.onFileSelected,
    required this.onDirectorySelected,
    this.onPickDirectory,
    this.onDelete,
    this.onRename,
    this.canDelete,
    this.canRename,
    this.isLocked,
  });

  @override
  State<FileTree> createState() => _FileTreeState();
}

class _FileTreeState extends State<FileTree> {
  // Track expanded directories
  final Set<String> _expandedPaths = {};
  String? _selectedPath;

  @override
  void initState() {
    super.initState();
    // Expand root by default
    if (widget.rootNode != null) {
      _expandedPaths.add(widget.rootNode!.path);
    }
  }

  @override
  void didUpdateWidget(FileTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.rootNode != null &&
        oldWidget.rootNode?.path != widget.rootNode!.path) {
      _expandedPaths.clear();
      _expandedPaths.add(widget.rootNode!.path);
      _selectedPath = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.rootNode == null) {
      // ... (No changes to empty state)
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('No folder opened'),
            if (widget.onPickDirectory != null) ...[
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: widget.onPickDirectory,
                child: const Text('Open Folder'),
              ),
            ],
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _buildNodeList(widget.rootNode!, depth: 0),
      ),
    );
  }

  List<Widget> _buildNodeList(FileNode node, {required int depth}) {
    List<Widget> widgets = [];

    if (node is FileNodeDirectory) {
      final isExpanded = _expandedPaths.contains(node.path);
      final isSelected = node.path == _selectedPath;

      widgets.add(
        _HoverableItem(
          isSelected: isSelected,
          onTap: () {
            setState(() {
              _selectedPath = node.path;
              if (isExpanded) {
                _expandedPaths.remove(node.path);
              } else {
                _expandedPaths.add(node.path);
              }
            });
            widget.onDirectorySelected(node);
          },
          onDelete: _deleteFor(node),
          onRename:
              widget.onRename != null && (widget.canRename?.call(node) ?? true)
              ? () => widget.onRename!(node)
              : null,
          child: Padding(
            padding: EdgeInsets.only(
              left: depth * 12.0 + 8,
              top: 4,
              bottom: 4,
              right: 8,
            ),
            child: Row(
              children: [
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  size: 16,
                  color: Colors.grey,
                ),
                Icon(
                  isExpanded ? Icons.folder_open : Icons.folder,
                  size: 16,
                  color: const Color(0xFF90A4AE),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    node.name,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.2,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      if (isExpanded) {
        for (var child in node.children) {
          widgets.addAll(_buildNodeList(child, depth: depth + 1));
        }
      }
    } else if (node is FileNodeFile) {
      widgets.add(_buildFileItem(node, depth));
    }

    return widgets;
  }

  VoidCallback? _deleteFor(FileNode node) {
    if (widget.onDelete == null) return null;
    if (widget.canDelete != null && !widget.canDelete!(node)) return null;
    return () => widget.onDelete!(node);
  }

  Widget _buildFileItem(FileNodeFile file, int depth) {
    final bool isSelected = file.path == _selectedPath;

    return _HoverableItem(
      isSelected: isSelected,
      onTap: () {
        setState(() {
          _selectedPath = file.path;
        });
        widget.onFileSelected(file);
      },
      onDelete: _deleteFor(file),
      onRename:
          widget.onRename != null && (widget.canRename?.call(file) ?? true)
          ? () => widget.onRename!(file)
          : null,
      child: Padding(
        padding: EdgeInsets.only(
          left: depth * 12.0 + 24,
          top: 4,
          bottom: 4,
          right: 8,
        ),
        child: Row(
          children: [
            _getFileIcon(file.name),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                file.name,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.white,
                  height: 1.2,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (widget.isLocked?.call(file) ?? false)
              const Icon(Icons.lock_outline, size: 12, color: Colors.white38),
          ],
        ),
      ),
    );
  }

  Widget _getFileIcon(String fileName) {
    final ext = p.extension(fileName).toLowerCase();
    IconData icon = Icons.insert_drive_file_outlined;
    Color color = Colors.grey;

    switch (ext) {
      case '.dart':
        icon = FontAwesomeIcons.dartLang.data;
        color = const Color(0xFF42A5F5); // Flutter Blue
        break;
      case '.html':
        icon = Icons.html;
        color = const Color(0xFFE65100); // Orange
        break;
      case '.css':
        icon = Icons.css;
        color = const Color(0xFF1E88E5); // Blue
        break;
      case '.js':
      case '.ts':
        icon = Icons.javascript;
        color = const Color(0xFFFFCA28); // Amber
        break;
      case '.json':
        icon = Icons.data_object;
        color = const Color(0xFF66BB6A); // Green
        break;
      case '.md':
        icon = Icons.description;
        color = const Color(0xFFAB47BC); // Purple
        break;
      case '.yaml':
      case '.yml':
        icon = Icons.settings;
        color = const Color(0xFFEF5350); // Red
        break;
      case '.xml':
        icon = Icons.code;
        color = const Color(0xFFFF7043); // Deep Orange
        break;
      case '.png':
      case '.jpg':
      case '.jpeg':
      case '.svg':
        icon = Icons.image;
        color = const Color(0xFF26A69A); // Teal
        break;
    }

    return Icon(icon, size: 16, color: color);
  }
}

class _HoverableItem extends StatefulWidget {
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onRename;
  final Widget child;

  const _HoverableItem({
    required this.isSelected,
    required this.onTap,
    this.onDelete,
    this.onRename,
    required this.child,
  });

  @override
  State<_HoverableItem> createState() => _HoverableItemState();
}

class _HoverableItemState extends State<_HoverableItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onSecondaryTapDown: widget.onDelete != null || widget.onRename != null
            ? (details) => _showContextMenu(context, details.globalPosition)
            : null,
        child: Container(
          color: widget.isSelected
              ? const Color(0x33007ACC)
              : _isHovered
              ? const Color(0x1AFFFFFF)
              : null,
          child: widget.child,
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context, Offset position) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: [
        if (widget.onRename != null)
          PopupMenuItem(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            height: 32,
            onTap: widget.onRename,
            child: const Text('Rename', style: TextStyle(fontSize: 13)),
          ),
        if (widget.onDelete != null)
          PopupMenuItem(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            height: 32,
            onTap: widget.onDelete,
            child: const Text('Delete', style: TextStyle(fontSize: 13)),
          ),
      ],
    );
  }
}
