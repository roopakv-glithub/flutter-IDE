import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
// ignore: avoid_web_libraries_in_flutter
// import 'dart:html' as html; // Unused
import '../models/file_system_entity.dart';
import 'file_service_interface.dart';

class FileServiceImpl implements FileService {
  @override
  Future<FileNodeDirectory> loadDirectory(String path) async =>
      throw UnsupportedError('Project setup requires the desktop IDE.');

  // Cache content since we can't re-read paths on web easily without keeping the file object
  // In a real app we might store the PlatformFile bytes in the FileNodeFile or a separate cache
  final Map<String, Uint8List> _contentCache = {};

  @override
  Future<FileNodeDirectory?> pickDirectory() async {
    // On Web, ensure we ask for files.
    // note: 'type: FileType.any' is default.
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true, // Important for Web to get bytes immediately
      );

      if (result == null || result.files.isEmpty) return null;

      // Web doesn't give us a folder structure, just a list of files.
      // We'll simulate a "root" folder containing these files.
      // If we wanted to preserve hierarchy (if drag-drop supported it), it's harder.
      // For standard 'pickFiles', it's usually flat list.

      List<FileNode> children = [];
      String rootName = 'Uploaded Files';

      for (var file in result.files) {
        // Create a unique path key
        final path = file.name;
        if (file.bytes != null) {
          _contentCache[path] = file.bytes!;
        }
        children.add(FileNodeFile(file.name, path));
      }

      return FileNodeDirectory(rootName, '/', children: children);
    } catch (e) {
      // Error picking files on web
      return null;
    }
  }

  @override
  Future<String?> readFile(FileNodeFile file) async {
    // On web, we hope we cached the bytes
    final bytes = _contentCache[file.path];
    if (bytes != null) {
      return utf8.decode(bytes);
    }
    return '// Error: Content lost or not loaded';
  }

  @override
  Future<FileNodeFile?> createFile(String parentPath, String name) async {
    // Web: Creating files in local FS not supported via browser directly
    return null;
  }

  @override
  Future<FileNodeDirectory?> createDirectory(
    String parentPath,
    String name,
  ) async {
    // Web: Creating folders not supported
    return null;
  }

  @override
  Future<void> saveFile(FileNodeFile file, String content) async {
    // Web: Saving files purely in browser memory/cache for now
    _contentCache[file.path] = utf8.encode(content);
    // Real persistence would require File System Access API or download trigger
  }

  @override
  Future<bool> deleteFile(String filePath) async {
    // Not supported on web
    return false;
  }

  @override
  Future<bool> deleteDirectory(String directoryPath) async {
    // Not supported on web
    return false;
  }

  @override
  Future<bool> rename(String oldPath, String newName) async {
    // Not supported on web
    return false;
  }
}
