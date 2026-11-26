import 'dart:io';

import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// A path provider backed by a fresh temp directory, so service tests can
/// write real files without the native plugin.
class FakePathProviderPlatform extends PathProviderPlatform {
  FakePathProviderPlatform(this.root);

  final Directory root;

  @override
  Future<String?> getTemporaryPath() async => root.path;

  @override
  Future<String?> getApplicationSupportPath() async => root.path;

  @override
  Future<String?> getApplicationDocumentsPath() async => root.path;

  @override
  Future<String?> getApplicationCachePath() async => root.path;

  @override
  Future<String?> getExternalStoragePath() async => root.path;

  @override
  Future<List<String>?> getExternalCachePaths() async => [root.path];

  @override
  Future<List<String>?> getExternalStoragePaths({
    StorageDirectory? type,
  }) async =>
      [root.path];

  @override
  Future<String?> getDownloadsPath() async => root.path;

  @override
  Future<String?> getLibraryPath() async => root.path;
}
