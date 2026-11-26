import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:linky/services/library_folders.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'test_support/fake_path_provider.dart';

void main() {
  test('deletes a folder with nested files and spaces in its name', () async {
    final temp = await Directory.systemTemp.createTemp('linky_delete_test');
    PathProviderPlatform.instance = FakePathProviderPlatform(temp);
    addTearDown(() async {
      try {
        await temp.delete(recursive: true);
      } catch (_) {}
    });

    final root = await LibraryFolders.instance.rootDirectory();
    var notifications = 0;
    void onChange() => notifications++;
    LibraryFolders.instance.addListener(onChange);
    addTearDown(() => LibraryFolders.instance.removeListener(onChange));
    final folder = await LibraryFolders.instance.create(
      'My Folder',
      parent: '',
    );
    final child =
        await LibraryFolders.instance.create('Nested', parent: 'My Folder');
    await File('${folder.path}/clip.mp4').writeAsBytes([1, 2, 3]);
    await File('${child.path}/part.mp4').writeAsBytes([4, 5, 6]);
    expect(notifications, 2);

    final folders = await LibraryFolders.instance.all();
    final target = folders.firstWhere(
      (entry) => entry.relativePath == 'My Folder',
    );

    await LibraryFolders.instance.delete(target);

    expect(notifications, 3);
    expect(await Directory('${root.path}/My Folder').exists(), isFalse);
    expect(await LibraryFolders.instance.all(), isEmpty);
  });
}
