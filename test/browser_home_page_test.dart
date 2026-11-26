import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linky/features/browser/browser_home_page.dart';
import 'package:linky/services/bookmarks_service.dart';
import 'package:linky/services/history_service.dart';
import 'package:linky/theme/app_theme.dart';
import 'package:linky/widgets/site_favicon.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'test_support/fake_path_provider.dart';

Widget _host(Widget child) => MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: child),
    );

void main() {
  late Directory temp;

  setUpAll(() async {
    SiteFavicon.disableNetwork = true;
    temp = await Directory.systemTemp.createTemp('linky_home_test');
    PathProviderPlatform.instance = FakePathProviderPlatform(temp);
  });

  tearDownAll(() async {
    try {
      await temp.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    await BookmarksService.instance.clear();
    await HistoryService.instance.clear();
  });

  testWidgets('home shows search, paste, and empty feed hints', (tester) async {
    await tester.pumpWidget(
      _host(
        BrowserHomePage(
          onNavigate: (_) {},
          onOpenUrl: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Comet Browser'), findsOneWidget);
    expect(find.text('Search or type a website'), findsOneWidget);
    expect(find.text('Paste'), findsOneWidget);
    expect(find.text('Bookmarked pages will appear here.'), findsOneWidget);
    expect(find.text('Sites you visit will appear here.'), findsOneWidget);
    expect(find.byTooltip('Voice search'), findsOneWidget);
  });

  testWidgets('home renders saved bookmarks and frequent sites', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await BookmarksService.instance.add(
        url: 'https://example.com/watch',
        title: 'Example Clip',
      );
      await HistoryService.instance.addVisit(
        url: 'https://news.example.org/story',
        title: 'Example Story',
      );
    });

    await tester.pumpWidget(
      _host(
        BrowserHomePage(
          onNavigate: (_) {},
          onOpenUrl: (_) {},
          onOpenInNewTab: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Example Clip'), findsOneWidget);
    expect(find.text('Example Story'), findsOneWidget);
    expect(find.byType(SiteFavicon), findsNWidgets(2));
  });

  testWidgets('long press exposes new tab and remove actions', (tester) async {
    await tester.runAsync(
      () => BookmarksService.instance.add(
        url: 'https://example.com/watch',
        title: 'Example Clip',
      ),
    );

    await tester.pumpWidget(
      _host(
        BrowserHomePage(
          onNavigate: (_) {},
          onOpenUrl: (_) {},
          onOpenInNewTab: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Example Clip'));
    await tester.pumpAndSettle();

    expect(find.text('Open in new tab'), findsOneWidget);
    expect(find.text('Copy link'), findsOneWidget);
    expect(find.text('Remove bookmark'), findsOneWidget);

    await tester.tap(find.text('Remove bookmark'));
    await tester.pumpAndSettle();

    expect(find.text('Example Clip'), findsNothing);
    expect(find.text('Bookmarked pages will appear here.'), findsOneWidget);
  });
}
