import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.url,
    required this.title,
    required this.visitedAt,
    this.thumbnail,
    this.visitCount = 1,
  });

  final String id;
  final String url;
  final String title;
  final String? thumbnail;
  final DateTime visitedAt;
  final int visitCount;

  HistoryEntry copyWith({
    String? title,
    String? thumbnail,
    DateTime? visitedAt,
    int? visitCount,
  }) =>
      HistoryEntry(
        id: id,
        url: url,
        title: title ?? this.title,
        thumbnail: thumbnail ?? this.thumbnail,
        visitedAt: visitedAt ?? this.visitedAt,
        visitCount: visitCount ?? this.visitCount,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'title': title,
        'thumbnail': thumbnail,
        'visited_at': visitedAt.toIso8601String(),
        'visit_count': visitCount,
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
        id: json['id'] as String? ?? '',
        url: json['url'] as String? ?? '',
        title: json['title'] as String? ?? '',
        thumbnail: json['thumbnail'] as String?,
        visitedAt:
            DateTime.tryParse(json['visited_at'] as String? ?? '') ??
                DateTime.now(),
        visitCount: (json['visit_count'] as num?)?.toInt() ?? 1,
      );
}

class HistoryService extends ChangeNotifier {
  HistoryService._();

  static final HistoryService instance = HistoryService._();

  static const _maxEntries = 300;

  final List<HistoryEntry> _entries = [];
  bool _initialized = false;

  List<HistoryEntry> get entries => List.unmodifiable(_entries);
  bool get isEmpty => _entries.isEmpty;

  List<HistoryEntry> topPages({int limit = 20}) {
    final sorted = List<HistoryEntry>.from(_entries)
      ..sort((a, b) {
        final count = b.visitCount.compareTo(a.visitCount);
        if (count != 0) return count;
        return b.visitedAt.compareTo(a.visitedAt);
      });
    return sorted.take(limit).toList(growable: false);
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final file = await _storeFile();
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is List) {
          for (final raw in decoded.whereType<Map>()) {
            final entry = HistoryEntry.fromJson(
              Map<String, dynamic>.from(raw),
            );
            if (entry.url.isNotEmpty) _entries.add(entry);
          }
        }
      }
    } catch (_) {}
    _entries.sort((a, b) => b.visitedAt.compareTo(a.visitedAt));
    notifyListeners();
  }

  Future<void> addVisit({
    required String url,
    String? title,
    String? thumbnail,
  }) async {
    final normalized = url.trim();
    if (normalized.isEmpty) return;
    final uri = Uri.tryParse(normalized);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme)) return;
    final existingIndex = _entries.indexWhere((entry) => entry.url == normalized);
    final existing = existingIndex >= 0 ? _entries.removeAt(existingIndex) : null;
    final cleanTitle = title?.trim();
    final entry = HistoryEntry(
      id: existing?.id ??
          '${DateTime.now().microsecondsSinceEpoch}-${_entries.length}',
      url: normalized,
      title: cleanTitle == null || cleanTitle.isEmpty
          ? (existing?.title ?? uri.host)
          : cleanTitle,
      thumbnail: (thumbnail != null && thumbnail.isNotEmpty)
          ? thumbnail
          : existing?.thumbnail,
      visitedAt: DateTime.now(),
      visitCount: (existing?.visitCount ?? 0) + 1,
    );
    _entries.insert(0, entry);
    if (_entries.length > _maxEntries) {
      _entries.removeRange(_maxEntries, _entries.length);
    }
    notifyListeners();
    await _save();
  }

  Future<void> setThumbnail(String url, String? thumbnail) async {
    if (thumbnail == null || thumbnail.isEmpty) return;
    final index = _entries.indexWhere((entry) => entry.url == url);
    if (index < 0) return;
    final entry = _entries[index];
    if (entry.thumbnail == thumbnail) return;
    _entries[index] = entry.copyWith(thumbnail: thumbnail);
    notifyListeners();
    await _save();
  }

  Future<void> remove(String id) async {
    final before = _entries.length;
    _entries.removeWhere((entry) => entry.id == id);
    if (_entries.length == before) return;
    notifyListeners();
    await _save();
  }

  Future<void> clear() async {
    if (_entries.isEmpty) return;
    _entries.clear();
    notifyListeners();
    await _save();
  }

  Future<File> _storeFile() async {
    final support = await getApplicationSupportDirectory();
    return File('${support.path}/linky_history.json');
  }

  Future<void> _save() async {
    try {
      final file = await _storeFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode([for (final entry in _entries) entry.toJson()]),
      );
    } catch (_) {}
  }
}
