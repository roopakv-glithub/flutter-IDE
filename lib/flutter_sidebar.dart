import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'models/file_system_entity.dart';

class FlutterSidebar extends StatefulWidget {
  final FileNodeDirectory? rootNode;
  final Function(FileNodeFile) onFileSelected;
  final VoidCallback onPickDirectory;

  const FlutterSidebar({
    super.key,
    required this.rootNode,
    required this.onFileSelected,
    required this.onPickDirectory,
  });

  @override
  State<FlutterSidebar> createState() => _FlutterSidebarState();
}

class _FlutterSidebarState extends State<FlutterSidebar> {
  final Set<String> _expandedFolders = {'lib'}; // lib expanded by default
  String? _selectedPath;

  @override
  Widget build(BuildContext context) {
    if (widget.rootNode == null) {
      return Container(
        color: const Color(0xFF181818),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.folder_open, size: 48, color: Colors.white24),
              const SizedBox(height: 16),
              const Text(
                'No folder opened',
                style: TextStyle(color: Colors.white54),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: widget.onPickDirectory,
                child: const Text('Open Folder'),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      color: const Color(0xFF181818),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Project Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFF3C3C3C), width: 1),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.flutter_dash,
                  size: 20,
                  color: Color(0xFF42A5F5),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.rootNode!.name.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // Flutter Project Structure (scrollable content)
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLibFolder(),
                  _buildTestFolder(),
                  _buildPubspecFile(),
                  const SizedBox(height: 8),
                  _buildPlatformSection(),
                  _buildOtherFoldersSection(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLibFolder() {
    final libPath = p.join(widget.rootNode!.path, 'lib');
    final libDir = Directory(libPath);

    if (!libDir.existsSync()) return const SizedBox.shrink();

    final isExpanded = _expandedFolders.contains('lib');

    return Column(
      children: [
        _buildFolderHeader('lib', Icons.folder, isExpanded, () {
          setState(() {
            if (isExpanded) {
              _expandedFolders.remove('lib');
            } else {
              _expandedFolders.add('lib');
            }
          });
        }),
        if (isExpanded) _buildLibContents(libDir),
      ],
    );
  }

  Widget _buildTestFolder() {
    final testPath = p.join(widget.rootNode!.path, 'test');
    final testDir = Directory(testPath);

    if (!testDir.existsSync()) return const SizedBox.shrink();

    final isExpanded = _expandedFolders.contains('test');

    return Column(
      children: [
        _buildFolderHeader('test', Icons.science_outlined, isExpanded, () {
          setState(() {
            if (isExpanded) {
              _expandedFolders.remove('test');
            } else {
              _expandedFolders.add('test');
            }
          });
        }, iconColor: const Color(0xFF66BB6A)),
        if (isExpanded) _buildFolderContents(testDir, 1),
      ],
    );
  }

  Widget _buildLibContents(Directory libDir) {
    final files = <FileSystemEntity>[];
    try {
      files.addAll(libDir.listSync());
      files.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
    } catch (e) {
      return const SizedBox.shrink();
    }

    return Column(
      children: files.map((entity) {
        final name = p.basename(entity.path);
        if (name.startsWith('.') || (entity is Directory && name == 'build')) {
          return const SizedBox.shrink();
        }

        if (entity is File) {
          final isMain = name == 'main.dart';
          return _buildFileItem(
            name,
            entity.path,
            isMain ? Icons.flutter_dash : Icons.insert_drive_file_outlined,
            isMain ? const Color(0xFF42A5F5) : Colors.grey,
            1,
          );
        } else if (entity is Directory) {
          return _buildSubFolder(name, entity.path, 1);
        }
        return const SizedBox.shrink();
      }).toList(),
    );
  }

  Widget _buildSubFolder(String name, String path, int depth) {
    final isExpanded = _expandedFolders.contains(path);

    return Column(
      children: [
        _buildFolderHeader(
          name,
          isExpanded ? Icons.folder_open : Icons.folder,
          isExpanded,
          () {
            setState(() {
              if (isExpanded) {
                _expandedFolders.remove(path);
              } else {
                _expandedFolders.add(path);
              }
            });
          },
          depth: depth,
        ),
        if (isExpanded) _buildFolderContents(Directory(path), depth + 1),
      ],
    );
  }

  Widget _buildFolderContents(Directory dir, int depth) {
    final files = <FileSystemEntity>[];
    try {
      files.addAll(dir.listSync());
      files.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
    } catch (e) {
      return const SizedBox.shrink();
    }

    return Column(
      children: files.map((entity) {
        final name = p.basename(entity.path);
        if (name.startsWith('.') || (entity is Directory && name == 'build')) {
          return const SizedBox.shrink();
        }

        if (entity is File) {
          return _buildFileItem(
            name,
            entity.path,
            Icons.insert_drive_file_outlined,
            Colors.grey,
            depth,
          );
        } else if (entity is Directory) {
          return _buildSubFolder(name, entity.path, depth);
        }
        return const SizedBox.shrink();
      }).toList(),
    );
  }

  Widget _buildPubspecFile() {
    final pubspecPath = p.join(widget.rootNode!.path, 'pubspec.yaml');
    final pubspecFile = File(pubspecPath);

    if (!pubspecFile.existsSync()) return const SizedBox.shrink();

    return _buildFileItem(
      'pubspec.yaml',
      pubspecPath,
      Icons.settings,
      const Color(0xFFEF5350),
      0,
    );
  }

  Widget _buildPlatformSection() {
    final platforms = [
      ('android', Icons.android, Colors.green),
      ('ios', Icons.phone_iphone, Colors.grey),
      ('macos', Icons.laptop_mac, Colors.grey),
      ('windows', Icons.window, Colors.blue),
      ('linux', Icons.computer, Colors.orange),
      ('web', Icons.web, const Color(0xFF42A5F5)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            'PLATFORMS',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        ...platforms.map((platform) {
          final (name, icon, color) = platform;
          final platformPath = p.join(widget.rootNode!.path, name);
          final platformDir = Directory(platformPath);

          if (!platformDir.existsSync()) {
            return const SizedBox.shrink();
          }

          final isExpanded = _expandedFolders.contains(name);

          return Column(
            children: [
              _buildFolderHeader(name, icon, isExpanded, () {
                setState(() {
                  if (isExpanded) {
                    _expandedFolders.remove(name);
                  } else {
                    _expandedFolders.add(name);
                  }
                });
              }, iconColor: color),
              if (isExpanded) _buildFolderContents(platformDir, 1),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildOtherFoldersSection() {
    // Folders to exclude (already shown elsewhere)
    const excludedFolders = {
      'lib',
      'test',
      'android',
      'ios',
      'macos',
      'windows',
      'linux',
      'web',
    };

    final rootDir = Directory(widget.rootNode!.path);
    final otherFolders = <Directory>[];

    try {
      for (final entity in rootDir.listSync()) {
        if (entity is Directory) {
          final name = p.basename(entity.path);
          // Skip hidden folders and excluded folders
          if (!name.startsWith('.') &&
              name != 'build' &&
              !excludedFolders.contains(name)) {
            otherFolders.add(entity);
          }
        }
      }
      otherFolders.sort(
        (a, b) => p.basename(a.path).compareTo(p.basename(b.path)),
      );
    } catch (e) {
      return const SizedBox.shrink();
    }

    if (otherFolders.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            'OTHER',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        ...otherFolders.map((folder) {
          final name = p.basename(folder.path);
          final isExpanded = _expandedFolders.contains(folder.path);

          return Column(
            children: [
              _buildFolderHeader(
                name,
                isExpanded ? Icons.folder_open : Icons.folder,
                isExpanded,
                () {
                  setState(() {
                    if (isExpanded) {
                      _expandedFolders.remove(folder.path);
                    } else {
                      _expandedFolders.add(folder.path);
                    }
                  });
                },
              ),
              if (isExpanded) _buildFolderContents(folder, 1),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildFolderHeader(
    String name,
    IconData icon,
    bool isExpanded,
    VoidCallback onTap, {
    int depth = 0,
    Color? iconColor,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.only(
          left: depth * 16.0 + 8,
          top: 6,
          bottom: 6,
          right: 8,
        ),
        child: Row(
          children: [
            Icon(
              isExpanded
                  ? Icons.keyboard_arrow_down
                  : Icons.keyboard_arrow_right,
              size: 16,
              color: Colors.white54,
            ),
            const SizedBox(width: 4),
            Icon(icon, size: 16, color: iconColor ?? const Color(0xFF90A4AE)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(fontSize: 13, color: Colors.white),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileItem(
    String name,
    String path,
    IconData icon,
    Color iconColor,
    int depth,
  ) {
    final isSelected = path == _selectedPath;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedPath = path;
        });
        widget.onFileSelected(FileNodeFile(name, path));
      },
      child: Container(
        padding: EdgeInsets.only(
          left: depth * 16.0 + 28,
          top: 6,
          bottom: 6,
          right: 8,
        ),
        color: isSelected ? const Color(0x33007ACC) : null,
        child: Row(
          children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(fontSize: 13, color: Colors.white),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
