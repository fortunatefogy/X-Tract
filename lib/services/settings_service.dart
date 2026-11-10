import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'adblock/adblock_defaults.dart';

class SettingsService extends ChangeNotifier {
  SettingsService._();

  static final SettingsService instance = SettingsService._();

  static const defaultSupportedHosts = <String>{
    'youtube.com',
    'youtu.be',
    'youtube-nocookie.com',
    'vimeo.com',
    'player.vimeo.com',
    'dailymotion.com',
    'twitch.tv',
    'clips.twitch.tv',
    'tiktok.com',
    'facebook.com',
    'fb.watch',
    'instagram.com',
    'twitter.com',
    'x.com',
    'spotify.com',
    'open.spotify.com',
    'soundcloud.com',
    'bandcamp.com',
    'mixcloud.com',
    'audiomack.com',
    'podcasts.apple.com',
    'anchor.fm',
    'docs.google.com',
    'drive.google.com',
    'dropbox.com',
    'scribd.com',
    'slideshare.net',
    'issuu.com',
    'box.com',
    'sharepoint.com',
  };

  static const minMediaSizePresets = <int>[
    0,
    10 * 1024,
    50 * 1024,
    100 * 1024,
    500 * 1024,
    1024 * 1024,
  ];

  static const downloadThreadPresets = <int>[1, 2, 4, 6, 8, 12];
  static const simultaneousDownloadPresets = <int>[1, 2, 3, 4, 6, 8];

  ThemeMode _themeMode = ThemeMode.system;
  bool _onlyPlayingVideo = true;
  bool _filterJunkMedia = true;
  bool _detectImages = true;
  bool _detectVideos = true;
  bool _detectAudio = true;
  bool _detectDocuments = true;
  int _minMediaSizeBytes = 0;
  bool _onlySupportedSites = false;
  String _supportedSitesUrl = '';
  List<String> _remoteSupportedHosts = const [];
  int _downloadThreadCount = 4;
  int _maxSimultaneousDownloads = 3;
  bool _remuxDownloads = false;
  bool _fastStartDownloads = false;
  bool _repairStreams = false;
  bool _audioOnlyDownloads = false;
  String _downloadLocation = 'app';
  bool _copyToPublicDownloads = false;
  bool _desktopMode = false;
  bool _redirectPromptEnabled = true;
  bool _blockPopups = true;
  String _searchEngine = 'google';
  String _customSearchUrl = '';
  String _customHomeUrl = '';
  String _suggestionListUrl = '';
  bool _adBlockEnabled = true;
  bool _adBlockSeeded = false;
  bool _adBlockBuiltInEnabled = true;
  Set<String> _adBlockDisabledListUrls = <String>{};
  List<String> _adBlockListUrls = AdblockDefaults.recommendedListUrls;
  bool _proxyEnabled = false;
  List<String> _proxyChain = const [];
  String _secureDnsMode = 'off';
  String _secureDnsCustom = '';
  bool _initialized = false;

  ThemeMode get themeMode => _themeMode;
  bool get onlyPlayingVideo => _onlyPlayingVideo;
  bool get filterJunkMedia => _filterJunkMedia;
  bool get detectImages => _detectImages;
  bool get detectVideos => _detectVideos;
  bool get detectAudio => _detectAudio;
  bool get detectDocuments => _detectDocuments;
  int get minMediaSizeBytes => _minMediaSizeBytes;
  bool get onlySupportedSites => _onlySupportedSites;
  String get supportedSitesUrl => _supportedSitesUrl;
  List<String> get remoteSupportedHosts =>
      List.unmodifiable(_remoteSupportedHosts);
  int get downloadThreadCount => _downloadThreadCount;
  int get maxSimultaneousDownloads => _maxSimultaneousDownloads;
  bool get remuxDownloads => _remuxDownloads;
  bool get fastStartDownloads => _fastStartDownloads;
  bool get repairStreams => _repairStreams;
  bool get audioOnlyDownloads => _audioOnlyDownloads;
  String get downloadLocation => _downloadLocation;
  bool get copyToPublicDownloads => _copyToPublicDownloads;
  bool get desktopMode => _desktopMode;
  bool get redirectPromptEnabled => _redirectPromptEnabled;
  bool get blockPopups => _blockPopups;
  String get searchEngine => _searchEngine;
  String get customSearchUrl => _customSearchUrl;
  String get customHomeUrl => _customHomeUrl;
  String get suggestionListUrl => _suggestionListUrl;

  static const searchEnginePresets = <String>[
    'google',
    'duckduckgo',
    'bing',
    'custom',
  ];

  static const searchEngineLabel = <String, String>{
    'google': 'Google',
    'duckduckgo': 'DuckDuckGo',
    'bing': 'Bing',
    'custom': 'Custom',
  };

  String get searchEngineName => searchEngineLabel[_searchEngine] ?? 'Google';

  String get startPageUrl {
    switch (_searchEngine) {
      case 'duckduckgo':
        return 'https://duckduckgo.com/';
      case 'bing':
        return 'https://www.bing.com/';
      case 'custom':
        final uri = Uri.tryParse(_customHomeUrl.trim());
        if (uri != null &&
            {'http', 'https'}.contains(uri.scheme.toLowerCase()) &&
            uri.hasAuthority) {
          return uri.toString();
        }
        return 'https://www.google.com/';
      default:
        return 'https://www.google.com/';
    }
  }

  Uri searchUri(String query) {
    final encoded = Uri.encodeQueryComponent(query);
    switch (_searchEngine) {
      case 'duckduckgo':
        return Uri.parse('https://duckduckgo.com/?q=$encoded');
      case 'bing':
        return Uri.parse('https://www.bing.com/search?q=$encoded');
      case 'custom':
        final template = _customSearchUrl.trim();
        if (template.isNotEmpty) {
          final replaced = template.contains('{query}')
              ? template.replaceAll('{query}', encoded)
              : template.contains('%s')
                  ? template.replaceAll('%s', encoded)
                  : '$template$encoded';
          final uri = Uri.tryParse(replaced);
          if (uri != null &&
              {'http', 'https'}.contains(uri.scheme.toLowerCase()) &&
              uri.hasAuthority) {
            return uri;
          }
        }
        return Uri.parse('https://www.google.com/search?q=$encoded');
      default:
        return Uri.parse('https://www.google.com/search?q=$encoded');
    }
  }

  bool get adBlockEnabled => _adBlockEnabled;
  bool get adBlockSeeded => _adBlockSeeded;
  bool get adBlockBuiltInEnabled => _adBlockBuiltInEnabled;
  Set<String> get adBlockDisabledListUrls =>
      Set.unmodifiable(_adBlockDisabledListUrls);
  bool isAdBlockListEnabled(String url) =>
      !_adBlockDisabledListUrls.contains(url);
  List<String> get adBlockListUrls => List.unmodifiable(_adBlockListUrls);
  bool get proxyEnabled => _proxyEnabled;
  List<String> get proxyChain => List.unmodifiable(_proxyChain);
  String get secureDnsMode => _secureDnsMode;
  String get secureDnsCustom => _secureDnsCustom;
  bool get isInitialized => _initialized;

  bool isTypeEnabled(String type) {
    final base = type.startsWith('platform-')
        ? type.substring('platform-'.length)
        : type;
    return switch (base) {
      'image' => _detectImages,
      'video' => _detectVideos,
      'audio' => _detectAudio,
      'document' => _detectDocuments,
      _ => true,
    };
  }

  bool passesSizeThreshold(int? size) {
    if (_minMediaSizeBytes <= 0) return true;
    if (size == null || size <= 0) return true;
    return size >= _minMediaSizeBytes;
  }

  bool isSupportedSite(String value) {
    var host = value.trim().toLowerCase();
    if (host.isEmpty) return false;
    if (host.contains('://')) {
      host = Uri.tryParse(host)?.host.toLowerCase() ?? host;
    }
    host = host.replaceFirst(RegExp(r'^www\.'), '');
    if (host.isEmpty) return false;
    final hosts = <String>{
      ...defaultSupportedHosts,
      ..._remoteSupportedHosts,
    };
    for (final supported in hosts) {
      if (host == supported || host.endsWith('.$supported')) return true;
    }
    return false;
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final file = await _storeFile();
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          _themeMode = switch (decoded['theme_mode']) {
            'light' => ThemeMode.light,
            'dark' => ThemeMode.dark,
            _ => ThemeMode.system,
          };
          _onlyPlayingVideo = decoded['only_playing_video'] as bool? ?? true;
          _filterJunkMedia = decoded['filter_junk_media'] as bool? ?? true;
          _detectImages = decoded['detect_images'] as bool? ?? true;
          _detectVideos = decoded['detect_videos'] as bool? ?? true;
          _detectAudio = decoded['detect_audio'] as bool? ?? true;
          _detectDocuments = decoded['detect_documents'] as bool? ?? true;
          _minMediaSizeBytes =
              (decoded['min_media_size_bytes'] as num?)?.toInt() ?? 0;
          _onlySupportedSites =
              decoded['only_supported_sites'] as bool? ?? false;
          _supportedSitesUrl = decoded['supported_sites_url'] as String? ?? '';
          _downloadThreadCount =
              (decoded['download_thread_count'] as num?)?.toInt() ?? 4;
          _maxSimultaneousDownloads =
              (decoded['max_simultaneous_downloads'] as num?)?.toInt() ?? 3;
          _remuxDownloads = decoded['remux_downloads'] as bool? ?? false;
          _fastStartDownloads =
              decoded['fast_start_downloads'] as bool? ?? false;
          _repairStreams = decoded['repair_streams'] as bool? ?? false;
          _audioOnlyDownloads =
              decoded['audio_only_downloads'] as bool? ?? false;
          _downloadLocation = decoded['download_location'] as String? ?? 'app';
          if (!{'app', 'external', 'sd'}.contains(_downloadLocation)) {
            _downloadLocation = 'app';
          }
          _copyToPublicDownloads =
              decoded['copy_to_public_downloads'] as bool? ?? false;
          _desktopMode = decoded['desktop_mode'] as bool? ?? false;
          _redirectPromptEnabled =
              decoded['redirect_prompt_enabled'] as bool? ?? true;
          _blockPopups = decoded['block_popups'] as bool? ?? true;
          _searchEngine = decoded['search_engine'] as String? ?? 'google';
          if (!searchEnginePresets.contains(_searchEngine)) {
            _searchEngine = 'google';
          }
          _customSearchUrl = decoded['custom_search_url'] as String? ?? '';
          _customHomeUrl = decoded['custom_home_url'] as String? ?? '';
          _suggestionListUrl = decoded['suggestion_list_url'] as String? ?? '';
          _adBlockEnabled = decoded['adblock_enabled'] as bool? ?? true;
          _adBlockSeeded = decoded['adblock_seeded'] as bool? ?? false;
          _adBlockBuiltInEnabled =
              decoded['adblock_builtin_enabled'] as bool? ?? true;
          final disabledLists = decoded['adblock_disabled_lists'];
          if (disabledLists is List) {
            _adBlockDisabledListUrls = disabledLists
                .whereType<String>()
                .map((value) => value.trim())
                .where((value) => value.isNotEmpty)
                .toSet();
          }
          final adBlockUrls = decoded['adblock_list_urls'];
          if (adBlockUrls is List) {
            _adBlockListUrls = adBlockUrls
                .whereType<String>()
                .map((value) => value.trim())
                .where((value) => value.isNotEmpty)
                .toList(growable: false);
          }
          if (!_adBlockSeeded) {
            if (_adBlockListUrls.isEmpty) {
              _adBlockListUrls = AdblockDefaults.recommendedListUrls;
            }
            _adBlockSeeded = true;
          }
          if (AdblockDefaults.matchesLegacyDefaults(_adBlockListUrls)) {
            _adBlockListUrls = AdblockDefaults.recommendedListUrls;
            _adBlockDisabledListUrls.clear();
          }
          _proxyEnabled = decoded['proxy_enabled'] as bool? ?? false;
          final proxies = decoded['proxy_chain'];
          if (proxies is List) {
            _proxyChain = proxies
                .whereType<String>()
                .map((value) => value.trim())
                .where((value) => value.isNotEmpty)
                .toList(growable: false);
          }
          _secureDnsMode = decoded['secure_dns_mode'] as String? ?? 'off';
          if (!{
            'off',
            'cloudflare',
            'google',
            'quad9',
            'adguard',
            'custom',
          }.contains(_secureDnsMode)) {
            _secureDnsMode = 'off';
          }
          _secureDnsCustom = decoded['secure_dns_custom'] as String? ?? '';
          if (_downloadThreadCount < 1 || _downloadThreadCount > 32) {
            _downloadThreadCount = 4;
          }
          if (_maxSimultaneousDownloads < 1 || _maxSimultaneousDownloads > 16) {
            _maxSimultaneousDownloads = 3;
          }
          final remote = decoded['remote_supported_hosts'];
          if (remote is List) {
            _remoteSupportedHosts = remote
                .whereType<String>()
                .map(_normalizeHost)
                .where((host) => host.isNotEmpty)
                .toSet()
                .toList(growable: false);
          }
        }
      }
    } catch (_) {
      // Keep defaults when the settings file cannot be read.
    }
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    await _save();
  }

  Future<void> setOnlyPlayingVideo(bool value) async {
    if (_onlyPlayingVideo == value) return;
    _onlyPlayingVideo = value;
    notifyListeners();
    await _save();
  }

  Future<void> setFilterJunkMedia(bool value) async {
    if (_filterJunkMedia == value) return;
    _filterJunkMedia = value;
    notifyListeners();
    await _save();
  }

  Future<void> setDetectImages(bool value) async {
    if (_detectImages == value) return;
    _detectImages = value;
    notifyListeners();
    await _save();
  }

  Future<void> setDetectVideos(bool value) async {
    if (_detectVideos == value) return;
    _detectVideos = value;
    notifyListeners();
    await _save();
  }

  Future<void> setDetectAudio(bool value) async {
    if (_detectAudio == value) return;
    _detectAudio = value;
    notifyListeners();
    await _save();
  }

  Future<void> setDetectDocuments(bool value) async {
    if (_detectDocuments == value) return;
    _detectDocuments = value;
    notifyListeners();
    await _save();
  }

  Future<void> setMinMediaSizeBytes(int value) async {
    final normalized = value < 0 ? 0 : value;
    if (_minMediaSizeBytes == normalized) return;
    _minMediaSizeBytes = normalized;
    notifyListeners();
    await _save();
  }

  Future<void> setOnlySupportedSites(bool value) async {
    if (_onlySupportedSites == value) return;
    _onlySupportedSites = value;
    notifyListeners();
    await _save();
  }

  Future<void> setSupportedSitesUrl(String value) async {
    final normalized = value.trim();
    if (_supportedSitesUrl == normalized) return;
    _supportedSitesUrl = normalized;
    notifyListeners();
    await _save();
  }

  Future<void> setDownloadThreadCount(int value) async {
    final normalized = value.clamp(1, 32);
    if (_downloadThreadCount == normalized) return;
    _downloadThreadCount = normalized;
    notifyListeners();
    await _save();
  }

  Future<void> setMaxSimultaneousDownloads(int value) async {
    final normalized = value.clamp(1, 16);
    if (_maxSimultaneousDownloads == normalized) return;
    _maxSimultaneousDownloads = normalized;
    notifyListeners();
    await _save();
  }

  Future<void> setRemuxDownloads(bool value) async {
    if (_remuxDownloads == value) return;
    _remuxDownloads = value;
    notifyListeners();
    await _save();
  }

  Future<void> setFastStartDownloads(bool value) async {
    if (_fastStartDownloads == value) return;
    _fastStartDownloads = value;
    notifyListeners();
    await _save();
  }

  Future<void> setRepairStreams(bool value) async {
    if (_repairStreams == value) return;
    _repairStreams = value;
    notifyListeners();
    await _save();
  }

  Future<void> setAudioOnlyDownloads(bool value) async {
    if (_audioOnlyDownloads == value) return;
    _audioOnlyDownloads = value;
    notifyListeners();
    await _save();
  }

  Future<void> setDownloadLocation(String value) async {
    if (!{'app', 'external', 'sd'}.contains(value)) return;
    if (_downloadLocation == value) return;
    _downloadLocation = value;
    notifyListeners();
    await _save();
  }

  Future<void> setCopyToPublicDownloads(bool value) async {
    if (_copyToPublicDownloads == value) return;
    _copyToPublicDownloads = value;
    notifyListeners();
    await _save();
  }

  Future<void> setDesktopMode(bool value) async {
    if (_desktopMode == value) return;
    _desktopMode = value;
    notifyListeners();
    await _save();
  }

  Future<void> setRedirectPromptEnabled(bool value) async {
    if (_redirectPromptEnabled == value) return;
    _redirectPromptEnabled = value;
    notifyListeners();
    await _save();
  }

  Future<void> setBlockPopups(bool value) async {
    if (_blockPopups == value) return;
    _blockPopups = value;
    notifyListeners();
    await _save();
  }

  Future<void> setSearchEngine(String value) async {
    if (!searchEnginePresets.contains(value)) return;
    if (_searchEngine == value) return;
    _searchEngine = value;
    notifyListeners();
    await _save();
  }

  Future<void> setCustomSearchUrl(String value) async {
    final normalized = value.trim();
    if (_customSearchUrl == normalized) return;
    _customSearchUrl = normalized;
    notifyListeners();
    await _save();
  }

  Future<void> setCustomHomeUrl(String value) async {
    final normalized = value.trim();
    if (_customHomeUrl == normalized) return;
    _customHomeUrl = normalized;
    notifyListeners();
    await _save();
  }

  Future<void> setSuggestionListUrl(String value) async {
    final normalized = value.trim();
    if (_suggestionListUrl == normalized) return;
    _suggestionListUrl = normalized;
    notifyListeners();
    await _save();
  }

  Future<void> setAdBlockEnabled(bool value) async {
    if (_adBlockEnabled == value) return;
    _adBlockEnabled = value;
    notifyListeners();
    await _save();
  }

  Future<void> setAdBlockListUrls(List<String> value) async {
    final normalized = value
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
    if (_adBlockListUrls.length == normalized.length &&
        List.generate(normalized.length, (index) {
          return _adBlockListUrls[index] == normalized[index];
        }).every((matches) => matches)) {
      return;
    }
    _adBlockListUrls = normalized;
    _adBlockSeeded = true;
    _adBlockDisabledListUrls.removeWhere((url) => !normalized.contains(url));
    notifyListeners();
    await _save();
  }

  Future<void> setAdBlockListEnabled(String url, bool enabled) async {
    final normalized = url.trim();
    if (normalized.isEmpty) return;
    final changed = enabled
        ? _adBlockDisabledListUrls.remove(normalized)
        : _adBlockDisabledListUrls.add(normalized);
    if (!changed) return;
    notifyListeners();
    await _save();
  }

  Future<void> setAdBlockBuiltInEnabled(bool value) async {
    if (_adBlockBuiltInEnabled == value) return;
    _adBlockBuiltInEnabled = value;
    notifyListeners();
    await _save();
  }

  Future<void> setProxyEnabled(bool value) async {
    if (_proxyEnabled == value) return;
    _proxyEnabled = value;
    notifyListeners();
    await _save();
  }

  Future<void> setProxyChain(List<String> value) async {
    final normalized = value
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
    _proxyChain = normalized;
    notifyListeners();
    await _save();
  }

  Future<void> setSecureDnsMode(String value) async {
    if (!{
      'off',
      'cloudflare',
      'google',
      'quad9',
      'adguard',
      'custom',
    }.contains(value)) {
      return;
    }
    if (_secureDnsMode == value) return;
    _secureDnsMode = value;
    notifyListeners();
    await _save();
  }

  Future<void> setSecureDnsCustom(String value) async {
    final normalized = value.trim();
    if (_secureDnsCustom == normalized) return;
    _secureDnsCustom = normalized;
    notifyListeners();
    await _save();
  }

  Future<int> refreshSupportedSites() async {
    final url = Uri.tryParse(_supportedSitesUrl);
    if (url == null ||
        !url.hasAuthority ||
        !{'http', 'https'}.contains(url.scheme.toLowerCase())) {
      throw const FormatException('Enter a valid http or https list URL.');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..userAgent = 'Linky Android';
    try {
      final request = await client.getUrl(url).timeout(
            const Duration(seconds: 20),
          );
      final response = await request.close().timeout(
            const Duration(seconds: 20),
          );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('The list server returned HTTP '
            '${response.statusCode}.');
      }
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 20));
      final decoded = jsonDecode(body);
      final raw = decoded is List
          ? decoded
          : decoded is Map
              ? (decoded['sites'] ?? decoded['hosts'] ?? const [])
              : const [];
      if (raw is! List) {
        throw const FormatException('The list must be a JSON array.');
      }
      final hosts = raw
          .whereType<String>()
          .map(_normalizeHost)
          .where((host) => host.isNotEmpty)
          .toSet()
          .toList(growable: false);
      _remoteSupportedHosts = hosts;
      notifyListeners();
      await _save();
      return hosts.length;
    } finally {
      client.close(force: true);
    }
  }

  String _normalizeHost(String value) {
    var host = value.trim().toLowerCase();
    if (host.isEmpty) return '';
    if (host.contains('://')) {
      host = Uri.tryParse(host)?.host.toLowerCase() ?? '';
    }
    host = host.split('/').first.split(':').first;
    return host.replaceFirst(RegExp(r'^www\.'), '');
  }

  Future<File> _storeFile() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory('${documents.path}/LinkyDownloads');
    await directory.create(recursive: true);
    return File('${directory.path}/linky_settings.json');
  }

  Future<void> _save() async {
    try {
      final file = await _storeFile();
      await file.writeAsString(jsonEncode({
        'theme_mode': switch (_themeMode) {
          ThemeMode.light => 'light',
          ThemeMode.dark => 'dark',
          ThemeMode.system => 'system',
        },
        'only_playing_video': _onlyPlayingVideo,
        'filter_junk_media': _filterJunkMedia,
        'detect_images': _detectImages,
        'detect_videos': _detectVideos,
        'detect_audio': _detectAudio,
        'detect_documents': _detectDocuments,
        'min_media_size_bytes': _minMediaSizeBytes,
        'only_supported_sites': _onlySupportedSites,
        'supported_sites_url': _supportedSitesUrl,
        'remote_supported_hosts': _remoteSupportedHosts,
        'download_thread_count': _downloadThreadCount,
        'max_simultaneous_downloads': _maxSimultaneousDownloads,
        'remux_downloads': _remuxDownloads,
        'fast_start_downloads': _fastStartDownloads,
        'repair_streams': _repairStreams,
        'audio_only_downloads': _audioOnlyDownloads,
        'download_location': _downloadLocation,
        'copy_to_public_downloads': _copyToPublicDownloads,
        'desktop_mode': _desktopMode,
        'redirect_prompt_enabled': _redirectPromptEnabled,
        'block_popups': _blockPopups,
        'search_engine': _searchEngine,
        'custom_search_url': _customSearchUrl,
        'custom_home_url': _customHomeUrl,
        'suggestion_list_url': _suggestionListUrl,
        'adblock_enabled': _adBlockEnabled,
        'adblock_seeded': _adBlockSeeded,
        'adblock_builtin_enabled': _adBlockBuiltInEnabled,
        'adblock_disabled_lists': _adBlockDisabledListUrls.toList()..sort(),
        'adblock_list_urls': _adBlockListUrls,
        'proxy_enabled': _proxyEnabled,
        'proxy_chain': _proxyChain,
        'secure_dns_mode': _secureDnsMode,
        'secure_dns_custom': _secureDnsCustom,
      }));
    } catch (_) {}
  }
}
