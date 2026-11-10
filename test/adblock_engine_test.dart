import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:linky/services/adblock/adblock_engine.dart';

void main() {
  test('engine can be built inside an isolate', () async {
    final engine = await Isolate.run(() => AdblockEngine.build([
          '||isolate.test^',
        ]));
    expect(engine.match(Uri.parse('https://isolate.test/a')), isNotNull);
  });

  group('network rules', () {
    test('blocks host-anchored rules and subdomains only', () {
      final engine = AdblockEngine.build([
        '||doubleclick.net^',
      ]);
      expect(
        engine.match(Uri.parse('https://ad.doubleclick.net/pixel')) != null,
        isTrue,
      );
      expect(
        engine.match(Uri.parse('https://doubleclick.net/x')) != null,
        isTrue,
      );
      expect(
        engine.match(Uri.parse('https://doubleclick.net.evil.example/x')),
        isNull,
      );
    });

    test('honours exception rules', () {
      final engine = AdblockEngine.build([
        '||example.com^',
        '@@||example.com/allowed^',
      ]);
      expect(
        engine.match(Uri.parse('https://example.com/ads/banner.js')) != null,
        isTrue,
      );
      expect(
        engine.match(Uri.parse('https://example.com/allowed/file.js')),
        isNull,
      );
    });

    test('supports wildcards and separators in path rules', () {
      final engine = AdblockEngine.build([
        '/ads/*.js',
      ]);
      expect(
        engine.match(Uri.parse('https://site.test/assets/ads/banner.js')) != null,
        isTrue,
      );
      expect(
        engine.match(Uri.parse('https://site.test/assets/content.js')),
        isNull,
      );
    });

    test('applies third-party and domain options', () {
      final engine = AdblockEngine.build([
        '||tracker.test^\$third-party',
        '||partnerads.test^\$domain=example.com|~notexample.com',
      ]);
      final document = Uri.parse('https://example.com/watch');
      final thirdPartyDoc = Uri.parse('https://other.test/page');
      expect(
        engine.match(
          Uri.parse('https://tracker.test/pixel'),
          documentUri: thirdPartyDoc,
        ) != null,
        isTrue,
      );
      expect(
        engine.match(
          Uri.parse('https://tracker.test/pixel'),
          documentUri: Uri.parse('https://tracker.test/page'),
        ),
        isNull,
      );
      expect(
        engine.match(
          Uri.parse('https://partnerads.test/x'),
          documentUri: document,
        ) != null,
        isTrue,
      );
      expect(
        engine.match(
          Uri.parse('https://partnerads.test/x'),
          documentUri: Uri.parse('https://notexample.com/'),
        ),
        isNull,
      );
    });

    test('applies resource type options', () {
      final engine = AdblockEngine.build([
        '||cdn.test^\$image',
      ]);
      expect(
        engine.match(Uri.parse('https://cdn.test/banner.png')) != null,
        isTrue,
      );
      expect(
        engine.match(Uri.parse('https://cdn.test/app.js')),
        isNull,
      );
    });

    test('supports hosts files, badfilter and important', () {
      final engine = AdblockEngine.build([
        '0.0.0.0 ads.hosts.test',
        '127.0.0.1 tracker.hosts.test',
        '||disabled.test^',
        '||disabled.test^\$badfilter',
        '||example.com^',
        '@@||example.com/x^',
        '||example.com/x^\$important',
      ]);
      expect(
        engine.match(Uri.parse('https://ads.hosts.test/a')) != null,
        isTrue,
      );
      expect(
        engine.match(Uri.parse('https://tracker.hosts.test/a')) != null,
        isTrue,
      );
      expect(engine.match(Uri.parse('https://disabled.test/a')), isNull);
      expect(
        engine.match(Uri.parse('https://example.com/x/file')) != null,
        isTrue,
      );
    });

    test('supports start and end anchors', () {
      final engine = AdblockEngine.build([
        '|https://anchor.test/ad',
        '|https://end.test/banner.gif|',
      ]);
      expect(
        engine.match(Uri.parse('https://anchor.test/ad.js')) != null,
        isTrue,
      );
      expect(
        engine.match(Uri.parse('https://other.test/https://anchor.test/ad')),
        isNull,
      );
      expect(
        engine.match(Uri.parse('https://end.test/banner.gif')) != null,
        isTrue,
      );
      expect(
        engine.match(Uri.parse('https://end.test/banner.gif?x=1')),
        isNull,
      );
    });

    test('ignores unsupported option rules instead of overblocking', () {
      final engine = AdblockEngine.build([
        '||safe.test^\$removeparam=utm_source',
      ]);
      expect(engine.match(Uri.parse('https://safe.test/a')), isNull);
    });
  });

  group('cosmetic rules', () {
    test('injects generic and site-specific selectors with exceptions', () {
      final engine = AdblockEngine.build([
        '##.generic-ad',
        'site.test##.site-ad',
        'example.com##.example-ad',
        'site.test#@#.allowed-ad',
        'site.test##.allowed-ad',
        'ok.test#@#.generic-ad',
      ]);
      final script = engine.cosmeticScript(Uri.parse('https://site.test/page'));
      expect(script, contains('.generic-ad'));
      expect(script, contains('.site-ad'));
      expect(script, isNot(contains('.allowed-ad')));
      expect(script, isNot(contains('.example-ad')));

      final allowed = engine.cosmeticScript(Uri.parse('https://ok.test/'));
      expect(allowed, isNot(contains('.generic-ad')));
    });

    test('skips procedural and scriptlet rules', () {
      final engine = AdblockEngine.build([
        'example.com##+js(set, foo, false)',
        'example.com#?#div:has-text(ad)',
        'example.com##:style(color: red)',
        'example.com##.plain',
      ]);
      final script = engine.cosmeticScript(Uri.parse('https://example.com/'));
      expect(script, contains('.plain'));
      expect(script, isNot(contains('+js(')));
      expect(script, isNot(contains(':has-text(')));
    });
  });
}
