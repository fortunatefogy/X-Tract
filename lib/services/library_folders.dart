import 'dart:io';

import 'storage_service.dart';

class LibraryFolder {
  const LibraryFolder({
    required this.relativePath,
    required this.name,
    required this.depth,
  });

  /// Path relative to the library root, using forward slashes.
  final String relativePath;
  final String name;
  final int depth;

  String get parent {
    final slash = relativePath.lastIndexOf('/');
    return slash < 0 ? '' : relativePath.substring(0, slash);
  }
}

/// Manages the user-created folders inside the library root.
class LibraryFolders {
  LibraryFolders._();

  static final LibraryFolders instance = LibraryFolders._();

  static String sanitize(String raw) {
    var name = raw
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    while (name.startsWith('.')) {
      name = name.substring(1).trim();
    }
    if (name.length > 60) name = name.substring(0, 60).trim();
    return name.isEmpty ? 'Folder' : name;
  }

  static String normalize(String? relative) {
    if (relative == null) return '';
    final segments = relative
        .split('/')
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty && segment != '.')
        .toList(growable: false);
    return segments.join('/');
  }

  Future<Directory> rootDirectory() => StorageService.instance.downloadDirectory();

  Future<Directory> directoryFor(String relative) async {
    final root = await rootDirectory();
    final clean = normalize(relative);
    if (clean.isEmpty) return root;
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}'
      '${clean.split('/').join(Platform.pathSeparator)}',
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<List<LibraryFolder>> children([String relative = '']) async {
    final directory = await directoryFor(relative);
    if (!await directory.exists()) return const [];
    final clean = normalize(relative);
    final folders = <LibraryFolder>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = _nameOf(entity);
      if (name.isEmpty || name.startsWith('.')) continue;
      final path = clean.isEmpty ? name : '$clean/$name';
      folders.add(
        LibraryFolder(relativePath: path, name: name, depth: _depth(path)),
      );
    }
    folders.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return folders;
  }

  /// Every folder in the library, sorted by path, for pickers.
  Future<List<LibraryFolder>> all() async {
    const maxDepth = 6;
    final result = <LibraryFolder>[];
    Future<void> walk(String relative) async {
      if (_depth(relative) >= maxDepth) return;
      for (final folder in await children(relative)) {
        result.add(folder);
        await walk(folder.relativePath);
      }
    }

    await walk('');
    return result;
  }

  Future<Directory> create(String name, {String parent = ''}) async {
    final clean = normalize(parent);
    final safe = sanitize(name);
    final path = clean.isEmpty ? safe : '$clean/$safe';
    final directory = await directoryFor(path);
    await directory.create(recursive: true);
    return directory;
  }

  Future<String> rename(LibraryFolder folder, String newName) async {
    final source = await directoryFor(folder.relativePath);
    if (!await source.exists()) return folder.relativePath;
    final safe = sanitize(newName);
    final parent = folder.parent;
    var candidate = safe;
    var target = await directoryFor(_join(parent, candidate));
    var counter = 1;
    while (await target.exists() && target.path != source.path) {
      candidate = '$safe ($counter)';
      target = await directoryFor(_join(parent, candidate));
      counter++;
    }
    if (target.path == source.path) return folder.relativePath;
    await source.rename(target.path);
    return _join(parent, candidate);
  }

  Future<void> delete(LibraryFolder folder) async {
    final directory = await directoryFor(folder.relativePath);
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  Future<bool> isEmpty(LibraryFolder folder) async {
    final directory = await directoryFor(folder.relativePath);
    if (!await directory.exists()) return true;
    await for (final _ in directory.list(followLinks: false)) {
      return false;
    }
    return true;
  }

  Future<File> moveFile(File file, String targetRelative) async {
    final target = await directoryFor(targetRelative);
    final name = file.uri.pathSegments.last;
    var destination = File('${target.path}${Platform.pathSeparator}$name');
    if (await destination.exists() && destination.path != file.path) {
      final dot = name.lastIndexOf('.');
      final stem = dot > 0 ? name.substring(0, dot) : name;
      final extension = dot > 0 ? name.substring(dot) : '';
      var counter = 1;
      while (await destination.exists()) {
        destination = File(
          '${target.path}${Platform.pathSeparator}$stem ($counter)$extension',
        );
        counter++;
      }
    }
    if (destination.path == file.path) return file;
    try {
      return await file.rename(destination.path);
    } on FileSystemException {
      final copied = await file.copy(destination.path);
      await file.delete();
      return copied;
    }
  }

  static String _join(String parent, String name) =>
      parent.isEmpty ? name : '$parent/$name';

  static String _nameOf(Directory directory) {
    final segments = directory.uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    return segments.isEmpty ? '' : segments.last;
  }

  static int _depth(String relative) {
    final clean = normalize(relative);
    return clean.isEmpty ? 0 : clean.split('/').length;
  }
}
