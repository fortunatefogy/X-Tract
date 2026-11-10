import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'adblock/adblock_defaults.dart';
import 'adblock/adblock_engine.dart';
import 'challenge_hosts.dart';
import 'proxy_service.dart';
import 'settings_service.dart';

class AdBlockRefreshResult {
  const AdBlockRefreshResult({
    required this.networkRules,
    required this.cosmeticRules,
    required this.lists,
    required this.failed,
  });

  final int networkRules;
  final int cosmeticRules;
  final int lists;
  final int failed;
}

/// Content blocker inspired by the engines Brave and Helium ship.
///
/// Network filtering uses a token/host indexed uBlock Origin (ABP) parser and
/// cosmetic filtering injects a stylesheet built from the same lists. Lists are
/// cached on disk, individually toggleable, and compiled in a background
/// isolate so startup stays fast.
class AdBlockService extends ChangeNotifier {
  AdBlockService._() {
    _engine = _seedEngine;
  }

  static final AdBlockService instance = AdBlockService._();

  static const _maxDecisionCache = 20000;
  static const _maxListBytes = 32 * 1024 * 1024;

  final Map<String, String> _cacheEntries = {};
  final Map<String, DateTime> _listUpdatedAt = {};
  final Map<String, bool> _decisionCache = {};
  late AdblockEngine _engine;
  late final AdblockEngine _seedEngine = AdblockEngine.build(
    const [],
    extraHosts: AdblockDefaults.seedHosts,
    extraRules: AdblockDefaults.seedRules,
    extraSelectors: AdblockDefaults.seedCosmeticSelectors,
  );

  String? _builtInText;
  bool _initialized = false;
  bool _loading = false;
  bool _ready = false;
  Future<AdBlockRefreshResult>? _refreshing;
  DateTime? _updatedAt;
  String? _lastError;

  bool get enabled => SettingsService.instance.adBlockEnabled;
  bool get isReady => _ready;
  bool get isLoading => _loading;
  bool get isRefreshing => _refreshing != null;
  String? get lastError => _lastError;
  DateTime? get lastUpdated => _updatedAt;
  List<String> get listUrls => SettingsService.instance.adBlockListUrls;
  int get cachedListCount => _cacheEntries.length;
  int get networkRuleCount => _engine.networkRuleCount;
  int get cosmeticRuleCount => _engine.cosmeticRuleCount;
  int get ruleCount => _engine.networkRuleCount + _engine.cosmeticRuleCount;
  bool get builtInEnabled => SettingsService.instance.adBlockBuiltInEnabled;
  bool isListEnabled(String url) =>
      SettingsService.instance.isAdBlockListEnabled(url);
  bool isListCached(String url) => _cacheEntries.containsKey(url);
  DateTime? lastUpdatedFor(String url) => _listUpdatedAt[url];
  String listLabel(String url) => AdblockDefaults.labelFor(url);

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    unawaited(_restore());
  }

  /// Makes sure cached lists are compiled before the first request in case the
  /// background restore has not finished yet.
  Future<void> ensureLoaded() async {
    if (_ready || _loading) return;
    await _restore();
  }

  bool get _hasEnabledCache {
    final settings = SettingsService.instance;
    return settings.adBlockListUrls.any(
      (url) =>
          settings.isAdBlockListEnabled(url) && _cacheEntries.containsKey(url),
    );
  }

  Future<void> _restore() async {
    if (_loading) return;
    _loading = true;
    notifyListeners();
    try {
      final manifest = await _readManifest();
      _cacheEntries
        ..clear()
        ..addAll(manifest.entries);
      _listUpdatedAt
        ..clear()
        ..addAll(manifest.updatedAtByUrl);
      if (manifest.updatedAt != null) _updatedAt = manifest.updatedAt;
      await _rebuildInternal();
    } catch (error) {
      _lastError = error.toString();
      _ready = true;
    } finally {
      _loading = false;
      notifyListeners();
    }
    if (enabled && !_hasEnabledCache) {
      unawaited(refresh().catchError((_) => const AdBlockRefreshResult(
            networkRules: 0,
            cosmeticRules: 0,
            lists: 0,
            failed: 0,
          )));
    }
  }

  bool shouldBlock(
    Uri uri, {
    Uri? documentUri,
    String? resourceType,
  }) {
    if (!enabled) return false;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return false;
    if (ChallengeHosts.isChallenge(uri)) return false;
    if (_engine.isEmpty) return false;
    final documentHost = documentUri?.host ?? '';
    final key = '${uri.toString()}|$documentHost|${resourceType ?? ''}';
    final cached = _decisionCache[key];
    if (cached != null) return cached;
    final match = _engine.match(
      uri,
      documentUri: documentUri,
      resourceType: resourceType,
    );
    final blocked = match != null;
    if (_decisionCache.length >= _maxDecisionCache) _decisionCache.clear();
    _decisionCache[key] = blocked;
    return blocked;
  }

  bool shouldBlockUrl(String? rawUrl, {Uri? documentUri}) {
    final uri = rawUrl == null ? null : Uri.tryParse(rawUrl);
    return uri != null && shouldBlock(uri, documentUri: documentUri);
  }

  String cosmeticScript(Uri? documentUri) =>
      _engine.cosmeticScript(documentUri);

  String baseCosmeticScript() => _seedEngine.cosmeticScript(null);

  Future<void> addListUrl(String value) async {
    final normalized = value.trim();
    if (normalized.isEmpty) return;
    final urls = [...SettingsService.instance.adBlockListUrls];
    if (!urls.contains(normalized)) urls.add(normalized);
    await SettingsService.instance.setAdBlockListUrls(urls);
    unawaited(refreshList(normalized).catchError((_) {}));
  }

  Future<void> removeListUrl(String value) async {
    final urls = [...SettingsService.instance.adBlockListUrls]..remove(value);
    await SettingsService.instance.setAdBlockListUrls(urls);
    await rebuild();
  }

  Future<void> setBuiltInEnabled(bool value) async {
    await SettingsService.instance.setAdBlockBuiltInEnabled(value);
    await rebuild();
  }

  Future<void> setListEnabled(String url, bool value) async {
    await SettingsService.instance.setAdBlockListEnabled(url, value);
    await rebuild();
    if (value && !_cacheEntries.containsKey(url)) {
      unawaited(refreshList(url).catchError((_) {}));
    }
  }

  Future<void> restoreRecommendedLists() async {
    await SettingsService.instance
        .setAdBlockListUrls(AdblockDefaults.recommendedListUrls);
    await rebuild();
    if (enabled) {
      unawaited(refresh().catchError((_) => const AdBlockRefreshResult(
            networkRules: 0,
            cosmeticRules: 0,
            lists: 0,
            failed: 0,
          )));
    }
  }

  /// Recompiles the engine from the cached files without downloading anything.
  Future<void> rebuild() async {
    if (_loading) return;
    _loading = true;
    notifyListeners();
    try {
      await _rebuildInternal();
      _lastError = null;
    } catch (error) {
      _lastError = error.toString();
      _ready = true;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<AdBlockRefreshResult> refresh() {
    final active = _refreshing;
    if (active != null) return active;
    final future = _refresh();
    _refreshing = future;
    notifyListeners();
    return future.whenComplete(() {
      _refreshing = null;
      notifyListeners();
    });
  }

  Future<void> refreshList(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme)) {
      throw const FormatException('The filter list URL is invalid.');
    }
    final directory = await _listsDirectory();
    await directory.create(recursive: true);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..userAgent = 'Linky/0.1 (Android)';
    ProxyService.applyToClient(client);
    try {
      final text = await _download(client, uri);
      if (text == null) {
        throw const HttpException('The filter list could not be downloaded.');
      }
      final file = '${_hash(url)}.txt';
      await File(
        '${directory.path}${Platform.pathSeparator}$file',
      ).writeAsString(text, flush: true);
      final now = DateTime.now();
      _cacheEntries[url] = file;
      _listUpdatedAt[url] = now;
      _updatedAt = now;
      await _writeManifest();
      await rebuild();
    } finally {
      client.close(force: true);
    }
  }

  Future<AdBlockRefreshResult> _refresh() async {
    final settings = SettingsService.instance;
    final urls = settings.adBlockListUrls
        .where(settings.isAdBlockListEnabled)
        .toList(growable: false);
    if (urls.isEmpty) {
      throw const FormatException('Enable at least one ad-block list URL.');
    }
    final directory = await _listsDirectory();
    await directory.create(recursive: true);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..userAgent = 'Linky/0.1 (Android)';
    ProxyService.applyToClient(client);
    final configured = settings.adBlockListUrls.toSet();
    final nextEntries = <String, String>{
      for (final entry in _cacheEntries.entries)
        if (configured.contains(entry.key)) entry.key: entry.value,
    };
    final nextUpdated = <String, DateTime>{
      for (final entry in _listUpdatedAt.entries)
        if (configured.contains(entry.key)) entry.key: entry.value,
    };
    var failed = 0;
    try {
      for (final url in urls) {
        final uri = Uri.tryParse(url);
        if (uri == null || !{'http', 'https'}.contains(uri.scheme)) {
          failed++;
          continue;
        }
        final text = await _download(client, uri);
        if (text == null) {
          failed++;
          continue;
        }
        final file = '${_hash(url)}.txt';
        try {
          await File(
            '${directory.path}${Platform.pathSeparator}$file',
          ).writeAsString(text, flush: true);
          nextEntries[url] = file;
          nextUpdated[url] = DateTime.now();
        } catch (_) {
          failed++;
        }
      }
    } finally {
      client.close(force: true);
    }
    if (nextEntries.isEmpty) {
      throw const HttpException('No ad-block lists could be downloaded.');
    }
    _cacheEntries
      ..clear()
      ..addAll(nextEntries);
    _listUpdatedAt
      ..clear()
      ..addAll(nextUpdated);
    _updatedAt = DateTime.now();
    await _rebuildInternal();
    _lastError = null;
    await _writeManifest();
    notifyListeners();
    return AdBlockRefreshResult(
      networkRules: _engine.networkRuleCount,
      cosmeticRules: _engine.cosmeticRuleCount,
      lists: urls.where(_cacheEntries.containsKey).length,
      failed: failed,
    );
  }

  Future<void> _rebuildInternal() async {
    final texts = await _collectTexts();
    _engine = await _build(texts);
    _ready = true;
    _decisionCache.clear();
  }

  Future<List<String>> _collectTexts() async {
    final settings = SettingsService.instance;
    final texts = <String>[];
    if (settings.adBlockBuiltInEnabled) {
      final builtIn = await _loadBuiltIn();
      if (builtIn.isNotEmpty) texts.add(builtIn);
    }
    final legacy = await _readLegacyHosts();
    if (legacy.isNotEmpty) texts.add(legacy);
    final configured = settings.adBlockListUrls.toSet();
    final directory = await _listsDirectory();
    for (final entry in _cacheEntries.entries) {
      if (!configured.contains(entry.key)) continue;
      if (!settings.isAdBlockListEnabled(entry.key)) continue;
      final file = File(
        '${directory.path}${Platform.pathSeparator}${entry.value}',
      );
      try {
        if (await file.exists()) texts.add(await file.readAsString());
      } catch (_) {}
    }
    return texts;
  }

  Future<String> _loadBuiltIn() async {
    final cached = _builtInText;
    if (cached != null) return cached;
    try {
      final text =
          await rootBundle.loadString(AdblockDefaults.builtInOisdAsset);
      _builtInText = text;
      return text;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('AdBlock: built-in list unavailable: $error');
      }
      return '';
    }
  }

  Future<String?> _download(HttpClient client, Uri uri) async {
    try {
      final request =
          await client.getUrl(uri).timeout(const Duration(seconds: 25));
      request.headers
        ..set(HttpHeaders.acceptEncodingHeader, 'identity')
        ..set(HttpHeaders.userAgentHeader, 'Linky/0.1 (Android)');
      final response =
          await request.close().timeout(const Duration(seconds: 25));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        return null;
      }
      final builder = BytesBuilder(copy: false);
      var total = 0;
      await for (final chunk in response.timeout(const Duration(seconds: 40))) {
        total += chunk.length;
        if (total > _maxListBytes) {
          throw const HttpException('The filter list is too large.');
        }
        builder.add(chunk);
      }
      return utf8.decode(builder.takeBytes(), allowMalformed: true);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('AdBlock: failed to download $uri: $error');
      }
      return null;
    }
  }

  Future<AdblockEngine> _build(List<String> texts) async {
    try {
      return await Isolate.run(
        () => AdblockEngine.build(
          texts,
          extraHosts: AdblockDefaults.seedHosts,
          extraRules: AdblockDefaults.seedRules,
          extraSelectors: AdblockDefaults.seedCosmeticSelectors,
        ),
      );
    } catch (_) {
      return AdblockEngine.build(
        texts,
        extraHosts: AdblockDefaults.seedHosts,
        extraRules: AdblockDefaults.seedRules,
        extraSelectors: AdblockDefaults.seedCosmeticSelectors,
      );
    }
  }

  Future<Directory> _baseDirectory() async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}${Platform.pathSeparator}adblock');
  }

  Future<Directory> _listsDirectory() async {
    final base = await _baseDirectory();
    return Directory('${base.path}${Platform.pathSeparator}lists');
  }

  Future<File> _manifestFile() async {
    final base = await _baseDirectory();
    return File('${base.path}${Platform.pathSeparator}manifest.json');
  }

  Future<File> _legacyFile() async {
    final support = await getApplicationSupportDirectory();
    return File('${support.path}${Platform.pathSeparator}linky_adblock.json');
  }

  Future<String> _readLegacyHosts() async {
    try {
      final file = await _legacyFile();
      if (!await file.exists()) return '';
      return await file.readAsString();
    } catch (_) {
      return '';
    }
  }

  Future<_Manifest> _readManifest() async {
    try {
      final file = await _manifestFile();
      if (!await file.exists()) return const _Manifest();
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return const _Manifest();
      final globalUpdated =
          DateTime.tryParse(decoded['updatedAt']?.toString() ?? '');
      final entries = <String, String>{};
      final updatedAtByUrl = <String, DateTime>{};
      final lists = decoded['lists'];
      if (lists is List) {
        for (final entry in lists) {
          if (entry is Map) {
            final url = entry['url']?.toString() ?? '';
            final name = entry['file']?.toString() ?? '';
            if (url.isEmpty || name.isEmpty) continue;
            entries[url] = name;
            final updated = DateTime.tryParse(
              entry['updatedAt']?.toString() ?? '',
            );
            if (updated != null) {
              updatedAtByUrl[url] = updated;
            } else if (globalUpdated != null) {
              updatedAtByUrl[url] = globalUpdated;
            }
          }
        }
      }
      return _Manifest(
        entries: entries,
        updatedAtByUrl: updatedAtByUrl,
        updatedAt: globalUpdated,
      );
    } catch (_) {
      return const _Manifest();
    }
  }

  Future<void> _writeManifest() async {
    try {
      final file = await _manifestFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode({
        'updatedAt': _updatedAt?.toIso8601String(),
        'lists': [
          for (final entry in _cacheEntries.entries)
            {
              'url': entry.key,
              'file': entry.value,
              'updatedAt': _listUpdatedAt[entry.key]?.toIso8601String(),
            },
        ],
      }));
    } catch (_) {}
  }

  static String _hash(String value) {
    var hash = 0x811c9dc5;
    for (final code in value.codeUnits) {
      hash ^= code;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}

class _Manifest {
  const _Manifest({
    this.entries = const {},
    this.updatedAtByUrl = const {},
    this.updatedAt,
  });

  final Map<String, String> entries;
  final Map<String, DateTime> updatedAtByUrl;
  final DateTime? updatedAt;
}
