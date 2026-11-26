import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linky/features/library/library_screen.dart';
import 'package:linky/services/library_folders.dart';
import 'package:linky/services/settings_service.dart';
import 'package:linky/theme/app_theme.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'test_support/fake_path_provider.dart';

Future<void> _settle(WidgetTester tester, {int rounds = 20}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _pumpLibrary(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(theme: AppTheme.dark, home: const LibraryScreen()),
  );
  await _settle(tester);
}

Future<void> _waitForText(WidgetTester tester, String text) async {
  for (var i = 0; i < 100; i++) {
    if (find.text(text).evaluate().isNotEmpty) return;
    await _settle(tester, rounds: 1);
  }
  fail('Timed out waiting for "$text"');
}

Future<void> _createFolder(WidgetTester tester, String name) async {
  await tester.tap(find.byTooltip('New folder'));
  await _settle(tester);
  await tester.enterText(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    ),
    name,
  );
  await tester.tap(find.text('Create'));
  await _settle(tester);
  await _waitForText(tester, name);
}

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('linky_folders_ui');
    PathProviderPlatform.instance = FakePathProviderPlatform(temp);
    await SettingsService.instance.setDownloadFolder('');
  });

  tearDown(() async {
    try {
      await temp.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets('create, open, nest, and go back to folders', (tester) async {
    await _pumpLibrary(tester);
    expect(find.text('Your saved media, available offline.'), findsOneWidget);

    await _createFolder(tester, 'Clips');
    expect(find.text('Clips'), findsOneWidget);

    await tester.tap(find.text('Clips'));
    await _settle(tester);
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.text('Clips'), findsOneWidget);

    await _createFolder(tester, 'Nested');
    expect(find.text('Nested'), findsOneWidget);

    expect(await tester.binding.handlePopRoute(), isTrue);
    await _settle(tester);
    expect(find.text('Your saved media, available offline.'), findsOneWidget);
    expect(find.text('Clips'), findsOneWidget);
    expect(find.text('Nested'), findsNothing);

    await tester.tap(find.text('Clips'));
    await _settle(tester);
    expect(find.text('Nested'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(find.text('Your saved media, available offline.'), findsOneWidget);
  });

  testWidgets('back shows the parent folder list, not the child files', (
    tester,
  ) async {
    await _pumpLibrary(tester);
    await _createFolder(tester, 'Parent');
    await tester.tap(find.text('Parent'));
    await _settle(tester);
    await _createFolder(tester, 'Child');

    final parentDirectory = await tester.runAsync(
      () => LibraryFolders.instance.directoryFor('Parent'),
    );
    await tester.runAsync(
      () => File('${parentDirectory!.path}/clip.mp4').writeAsBytes([1, 2, 3]),
    );
    // Reload the folder so the file appears.
    await tester.binding.handlePopRoute();
    await _settle(tester);
    await tester.tap(find.text('Parent'));
    await _settle(tester);
    await _waitForText(tester, 'clip.mp4');

    expect(await tester.binding.handlePopRoute(), isTrue);
    await _settle(tester);
    expect(find.text('Your saved media, available offline.'), findsOneWidget);
    expect(find.text('Parent'), findsOneWidget);
    // The child folder's file must not leak into the parent view.
    expect(find.text('clip.mp4'), findsNothing);
  });

  testWidgets('double tapping a folder does not navigate two levels', (
    tester,
  ) async {
    await _pumpLibrary(tester);
    await _createFolder(tester, 'Alpha');
    await tester.tap(find.text('Alpha'));
    await _settle(tester);
    await _createFolder(tester, 'Beta');
    await tester.binding.handlePopRoute();
    await _settle(tester);

    final center = tester.getCenter(find.text('Alpha'));
    await tester.tapAt(center);
    await tester.tapAt(center);
    await tester.pump();
    await _settle(tester);
    expect(find.text('Alpha'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(find.text('Your saved media, available offline.'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
  });

  testWidgets('three-dot delete removes the folder and its files', (
    tester,
  ) async {
    await _pumpLibrary(tester);
    await _createFolder(tester, 'Trash');
    final directory = await tester.runAsync(
      () => LibraryFolders.instance.directoryFor('Trash'),
    );
    await tester.runAsync(
      () => File('${directory!.path}/old.mp4').writeAsBytes([1, 2, 3]),
    );

    await tester.tap(find.byTooltip('Folder options'));
    await _settle(tester);
    expect(find.text('Delete folder'), findsOneWidget);
    await tester.tap(find.text('Delete folder'));
    await _settle(tester);
    expect(find.text('Delete folder?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await _settle(tester);

    expect(find.text('Trash'), findsNothing);
    expect(Directory(directory!.path).existsSync(), isFalse);
  });

  testWidgets('header delete removes the folder you are inside', (
    tester,
  ) async {
    await _pumpLibrary(tester);
    await _createFolder(tester, 'Current');
    await tester.tap(find.text('Current'));
    await _settle(tester);

    final directory = await tester.runAsync(
      () => LibraryFolders.instance.directoryFor('Current'),
    );
    await tester.tap(find.byTooltip('Delete folder'));
    await _settle(tester);
    expect(find.text('Delete folder?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await _settle(tester);

    expect(find.text('Your saved media, available offline.'), findsOneWidget);
    expect(find.text('Current'), findsNothing);
    expect(Directory(directory!.path).existsSync(), isFalse);
  });
}
