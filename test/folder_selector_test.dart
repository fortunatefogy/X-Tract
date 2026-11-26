import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linky/features/library/folder_picker.dart';
import 'package:linky/theme/app_theme.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'test_support/fake_path_provider.dart';

void main() {
  late Directory temp;

  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('linky_folder_test');
    PathProviderPlatform.instance = FakePathProviderPlatform(temp);
  });

  tearDownAll(() async {
    try {
      await temp.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets('folder selector renders a dropdown field', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: FolderSelector(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Save to'), findsOneWidget);
    expect(find.text('Library (root)'), findsOneWidget);
    expect(find.byIcon(Icons.expand_more_rounded), findsOneWidget);
  });

  testWidgets('folder selector opens a dropdown menu', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: FolderSelector(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Library (root)'));
    await tester.pumpAndSettle();

    expect(find.text('New folder'), findsOneWidget);
    expect(find.text('Library (root)'), findsNWidgets(2));
    expect(find.byIcon(Icons.create_new_folder_outlined), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });
}
