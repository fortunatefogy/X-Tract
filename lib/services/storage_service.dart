import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'device_resources.dart';
import 'settings_service.dart';

class StorageService {
  StorageService._();

  static final StorageService instance = StorageService._();

  static const _folder = 'LinkyDownloads';

  List<String> _externalDirectories = const [];
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    _externalDirectories =
        await DeviceResources.instance.externalDirectories();
  }

  bool get hasSdCard => _externalDirectories.length > 1;

  List<String> get externalDirectories => List.unmodifiable(
        _externalDirectories,
      );

  Future<List<Directory>> sourceDirectories() async {
    final directories = <Directory>[];
    final documents = await getApplicationDocumentsDirectory();
    directories.add(Directory('${documents.path}/$_folder'));
    for (final path in _externalDirectories) {
      directories.add(Directory('$path/$_folder'));
    }
    return directories;
  }

  Future<Directory> downloadDirectory() async {
    final location = SettingsService.instance.downloadLocation;
    final documents = await getApplicationDocumentsDirectory();
    if (location == 'external' && _externalDirectories.isNotEmpty) {
      return _ensure(
        Directory('${_externalDirectories.first}/$_folder'),
      );
    }
    if (location == 'sd' && _externalDirectories.length > 1) {
      return _ensure(
        Directory('${_externalDirectories[1]}/$_folder'),
      );
    }
    return _ensure(Directory('${documents.path}/$_folder'));
  }

  Future<Directory> _ensure(Directory directory) async {
    await directory.create(recursive: true);
    return directory;
  }

  Future<int> moveExistingDownloads() async {
    final target = await downloadDirectory();
    final sources = await sourceDirectories();
    var moved = 0;
    for (final source in sources) {
      if (source.path == target.path || !await source.exists()) continue;
      await for (final entity in source.list(followLinks: false)) {
        if (entity is! File) continue;
        var destination = File(
          '${target.path}${Platform.pathSeparator}'
          '${entity.uri.pathSegments.last}',
        );
        if (await destination.exists()) {
          final name = entity.uri.pathSegments.last;
          final dot = name.lastIndexOf('.');
          final stem = dot > 0 ? name.substring(0, dot) : name;
          final extension = dot > 0 ? name.substring(dot) : '';
          var duplicate = 1;
          while (await destination.exists()) {
            destination = File(
              '${target.path}${Platform.pathSeparator}'
              '$stem ($duplicate)$extension',
            );
            duplicate++;
          }
        }
        try {
          await entity.rename(destination.path);
        } on FileSystemException {
          await entity.copy(destination.path);
          await entity.delete();
        }
        moved++;
      }
    }
    return moved;
  }

  Future<bool> openFolder() async {
    final directory = await downloadDirectory();
    return DeviceResources.instance.openFolder(directory.path);
  }
}
