import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:linky/services/browser_session_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'test_support/fake_path_provider.dart';

void main() {
  test('session saves tabs and the home scroll offset', () async {
    final temp = await Directory.systemTemp.createTemp('linky_session_test');
    PathProviderPlatform.instance = FakePathProviderPlatform(temp);
    addTearDown(() async {
      try {
        await temp.delete(recursive: true);
      } catch (_) {}
    });

    final service = BrowserSessionService.instance;
    await service.load();
    service.saveTabs(
      tabs: const [
        BrowserSessionTab(
          url: 'https://example.com/a',
          title: 'A',
          desktopMode: true,
        ),
        BrowserSessionTab(url: 'https://example.com/b', title: 'B'),
        BrowserSessionTab(url: '', title: 'Home'),
      ],
      activeIndex: 1,
    );
    service.updateHomeScroll(240);
    await service.flush();

    expect(service.tabs, hasLength(2));
    expect(service.activeIndex, 1);
    expect(service.homeScrollOffset, 240);

    final file = File('${temp.path}/linky_browser_session.json');
    final decoded = jsonDecode(await file.readAsString()) as Map;
    expect(decoded['active_index'], 1);
    expect(decoded['home_scroll'], 240);
    final tabs = decoded['tabs'] as List;
    expect(tabs, hasLength(2));
    expect((tabs.first as Map)['url'], 'https://example.com/a');
    expect((tabs.first as Map)['desktop_mode'], isTrue);
  });
}
