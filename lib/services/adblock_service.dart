import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'settings_service.dart';

class AdBlockService {
  AdBlockService._();

  static final AdBlockService instance = AdBlockService._();

  static const _builtInHosts = <String>{
    'doubleclick.net',
    'googlesyndication.com',
    'googleadservices.com',
    'adservice.google.com',
    'adsystem.com',
    'amazon-adsystem.com',
    'adnxs.com',
    'rubiconproject.com',
    'pubmatic.com',
    'openx.net',
    'criteo.com',
    'criteo.net',
    'taboola.com',
    'outbrain.com',
    'scorecardresearch.com',
    'quantserve.com',
    'zedo.com',
    'adcolony.com',
    'applovin.com',
    'unityads.unity3d.com',
    'inmobi.com',
    'mopub.com',
    'smartadserver.com',
    'casalemedia.com',
    'adform.net',
    'serving-sys.com',
    'media.net',
    'revcontent.com',
    'mgid.com',
    'popads.net',
    'propellerads.com',
    'onclickads.net',
    'adsterra.com',
    'exoclick.com',
    'juicyads.com',
    'trafficjunky.com',
    'advertising.com',
    'yieldmo.com',
    'sharethrough.com',
    'teads.tv',
    'spotxchange.com',
  };

  static const _pathPatterns = <String>[
    '/ads/',
    '/adserver/',
    '/advert/',
    '/banners/',
    '/popunder/',
    '/prebid',
    'doubleclick',
    'googlesyndication',
    '/pagead/',
    '/ad_sense',
    '/adframe',
  ];

  final Set<String> _remoteHosts = {};
  bool _initialized = false;

  bool get enabled => SettingsService.instance.adBlockEnabled;
  int get ruleCount => _builtInHosts.length + _remoteHosts.length;
  List<String> get listUrls => SettingsService.instance.adBlockListUrls;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final file = await _storeFile();
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is List) {
          _remoteHosts.addAll(decoded.whereType<String>());
        }
      }
    } catch (_) {}
  }

  bool shouldBlock(Uri uri) {
    if (!enabled) return false;
    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    if (host.isEmpty) return false;
    for (final blocked in _builtInHosts) {
      if (host == blocked || host.endsWith('.$blocked')) return true;
    }
    for (final blocked in _remoteHosts) {
      if (host == blocked || host.endsWith('.$blocked')) return true;
    }
    final path = uri.path.toLowerCase();
    return _pathPatterns.any(path.contains);
  }

  bool shouldBlockUrl(String? rawUrl) {
    final uri = rawUrl == null ? null : Uri.tryParse(rawUrl);
    return uri != null && shouldBlock(uri);
  }

  Future<void> addListUrl(String value) async {
    final normalized = value.trim();
    if (normalized.isEmpty) return;
    final urls = [...SettingsService.instance.adBlockListUrls];
    if (!urls.contains(normalized)) urls.add(normalized);
    await SettingsService.instance.setAdBlockListUrls(urls);
  }

  Future<void> removeListUrl(String value) async {
    final urls = [...SettingsService.instance.adBlockListUrls]
      ..remove(value);
    await SettingsService.instance.setAdBlockListUrls(urls);
  }

  Future<int> refresh() async {
    final urls = SettingsService.instance.adBlockListUrls;
    if (urls.isEmpty) {
      throw const FormatException('Add at least one ad-block list URL.');
    }
    final hosts = <String>{};
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..userAgent = 'Linky Android';
    try {
      for (final rawUrl in urls) {
        final uri = Uri.tryParse(rawUrl);
        if (uri == null || !{'http', 'https'}.contains(uri.scheme)) continue;
        try {
          final request = await client.getUrl(uri).timeout(
                const Duration(seconds: 20),
              );
          final response = await request.close().timeout(
                const Duration(seconds: 20),
              );
          if (response.statusCode < 200 || response.statusCode >= 300) {
            await response.drain<void>();
            continue;
          }
          final body = await response
              .transform(utf8.decoder)
              .join()
              .timeout(const Duration(seconds: 20));
          _parseRules(body, hosts);
        } catch (_) {}
      }
    } finally {
      client.close(force: true);
    }
    _remoteHosts
      ..clear()
      ..addAll(hosts);
    await _save();
    return _remoteHosts.length;
  }

  void _parseRules(String body, Set<String> hosts) {
    final trimmed = body.trim();
    if (trimmed.startsWith('[')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is List) {
          for (final entry in decoded) {
            final value = entry.toString().trim();
            _addHost(value, hosts);
          }
          return;
        }
      } catch (_) {}
    }
    for (final line in const LineSplitter().convert(body)) {
      var value = line.trim();
      if (value.isEmpty || value.startsWith('!') || value.startsWith('#')) {
        continue;
      }
      if (value.startsWith('||')) {
        value = value.substring(2);
        final end = value.indexOf('^');
        if (end >= 0) value = value.substring(0, end);
      } else if (value.startsWith('0.0.0.0 ') ||
          value.startsWith('127.0.0.1 ')) {
        value = value.split(RegExp(r'\s+')).last;
      }
      _addHost(value, hosts);
      if (hosts.length >= 20000) break;
    }
  }

  void _addHost(String value, Set<String> hosts) {
    var host = value.toLowerCase().trim();
    if (host.contains('://')) {
      host = Uri.tryParse(host)?.host ?? '';
    }
    if (host.startsWith('.')) host = host.substring(1);
    if (host.isEmpty || host.contains('/') || host.contains(' ')) return;
    if (!RegExp(r'^[a-z0-9.-]+$').hasMatch(host)) return;
    if (host.split('.').length < 2) return;
    hosts.add(host);
  }

  Future<File> _storeFile() async {
    final support = await getApplicationSupportDirectory();
    return File('${support.path}/linky_adblock.json');
  }

  Future<void> _save() async {
    try {
      final file = await _storeFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(_remoteHosts.toList()..sort()));
    } catch (_) {}
  }
}
