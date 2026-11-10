import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'bookmarks_service.dart';
import 'history_service.dart';
import 'settings_service.dart';

class UrlSuggestion {
  const UrlSuggestion({
    required this.title,
    required this.url,
    required this.source,
  });

  final String title;
  final String url;
  final String source;
}

class _RemoteSuggestion {
  const _RemoteSuggestion({required this.title, required this.url});

  final String title;
  final String url;

  Map<String, dynamic> toJson() => {'title': title, 'url': url};
}

class SuggestionsService {
  SuggestionsService._();

  static final SuggestionsService instance = SuggestionsService._();

  final List<_RemoteSuggestion> _remote = [];
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final file = await _cacheFile();
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is List) {
          for (final entry in decoded.whereType<Map>()) {
            _remote.add(
              _RemoteSuggestion(
                title: entry['title']?.toString() ?? '',
                url: entry['url']?.toString() ?? '',
              ),
            );
          }
        }
      }
    } catch (_) {}
  }

  List<UrlSuggestion> suggest(String query, {int limit = 8}) {
    final normalized = query.trim().toLowerCase();
    final results = <UrlSuggestion>[];
    final seen = <String>{};

    void add(String title, String url, String source) {
      if (url.isEmpty || !seen.add(url)) return;
      results.add(UrlSuggestion(
        title: title.isEmpty ? url : title,
        url: url,
        source: source,
      ));
    }

    for (final entry in HistoryService.instance.topPages(limit: 40)) {
      add(entry.title, entry.url, 'History');
    }
    for (final entry in BookmarksService.instance.entries) {
      add(entry.title, entry.url, 'Bookmark');
    }
    for (final entry in _remote) {
      add(entry.title, entry.url, 'Suggested');
    }

    final filtered = normalized.isEmpty
        ? results
        : results.where((suggestion) {
            final host =
                Uri.tryParse(suggestion.url)?.host.toLowerCase() ?? '';
            return suggestion.title.toLowerCase().contains(normalized) ||
                suggestion.url.toLowerCase().contains(normalized) ||
                host.contains(normalized);
          }).toList(growable: false);
    return filtered.take(limit).toList(growable: false);
  }

  Future<int> refreshRemote() async {
    final url = Uri.tryParse(SettingsService.instance.suggestionListUrl);
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
        throw HttpException(
          'The suggestions server returned HTTP ${response.statusCode}.',
        );
      }
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 20));
      final decoded = jsonDecode(body);
      final raw = decoded is List
          ? decoded
          : decoded is Map
              ? (decoded['pages'] ?? decoded['suggestions'] ?? const [])
              : const [];
      if (raw is! List) {
        throw const FormatException('The suggestions list must be a JSON array.');
      }
      final entries = <_RemoteSuggestion>[];
      for (final item in raw) {
        if (item is String && item.startsWith('http')) {
          entries.add(_RemoteSuggestion(title: item, url: item));
        } else if (item is Map) {
          final pageUrl = item['url']?.toString() ?? '';
          if (!pageUrl.startsWith('http')) continue;
          entries.add(
            _RemoteSuggestion(
              title: item['title']?.toString() ?? pageUrl,
              url: pageUrl,
            ),
          );
        }
        if (entries.length >= 500) break;
      }
      _remote
        ..clear()
        ..addAll(entries);
      await _save();
      return entries.length;
    } finally {
      client.close(force: true);
    }
  }

  Future<File> _cacheFile() async {
    final support = await getApplicationSupportDirectory();
    return File('${support.path}/linky_suggestions.json');
  }

  Future<void> _save() async {
    try {
      final file = await _cacheFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode([for (final entry in _remote) entry.toJson()]),
      );
    } catch (_) {}
  }
}
