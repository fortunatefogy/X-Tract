import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class BookmarkEntry {
  const BookmarkEntry({
    required this.id,
    required this.url,
    required this.title,
    required this.createdAt,
    this.thumbnail,
  });

  final String id;
  final String url;
  final String title;
  final String? thumbnail;
  final DateTime createdAt;

  BookmarkEntry copyWith({String? title, String? thumbnail}) => BookmarkEntry(
        id: id,
        url: url,
        title: title ?? this.title,
        thumbnail: thumbnail ?? this.thumbnail,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'title': title,
        'thumbnail': thumbnail,
        'created_at': createdAt.toIso8601String(),
      };

  factory BookmarkEntry.fromJson(Map<String, dynamic> json) => BookmarkEntry(
        id: json['id'] as String? ?? '',
        url: json['url'] as String? ?? '',
        title: json['title'] as String? ?? '',
        thumbnail: json['thumbnail'] as String?,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
            DateTime.now(),
      );
}

class BookmarksService extends ChangeNotifier {
  BookmarksService._();

  static final BookmarksService instance = BookmarksService._();

  final List<BookmarkEntry> _entries = [];
  bool _initialized = false;

  List<BookmarkEntry> get entries => List.unmodifiable(_entries);
  bool get isEmpty => _entries.isEmpty;

  bool isBookmarked(String url) =>
      _entries.any((entry) => entry.url == url.trim());

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final file = await _storeFile();
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is List) {
          for (final raw in decoded.whereType<Map>()) {
            final entry = BookmarkEntry.fromJson(
              Map<String, dynamic>.from(raw),
            );
            if (entry.url.isNotEmpty) _entries.add(entry);
          }
        }
      }
    } catch (_) {}
    _entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    notifyListeners();
  }

  Future<void> add({
    required String url,
    String? title,
    String? thumbnail,
  }) async {
    final normalized = url.trim();
    if (normalized.isEmpty) return;
    final uri = Uri.tryParse(normalized);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme)) return;
    final existingIndex =
        _entries.indexWhere((entry) => entry.url == normalized);
    if (existingIndex >= 0) {
      final existing = _entries[existingIndex];
      final cleanTitle = title?.trim();
      _entries[existingIndex] = existing.copyWith(
        title: cleanTitle == null || cleanTitle.isEmpty ? null : cleanTitle,
        thumbnail: thumbnail == null || thumbnail.isEmpty ? null : thumbnail,
      );
      notifyListeners();
      await _save();
      return;
    }
    final cleanTitle = title?.trim();
    _entries.insert(
      0,
      BookmarkEntry(
        id: '${DateTime.now().microsecondsSinceEpoch}-${_entries.length}',
        url: normalized,
        title: cleanTitle == null || cleanTitle.isEmpty
            ? uri.host
            : cleanTitle,
        thumbnail: thumbnail == null || thumbnail.isEmpty ? null : thumbnail,
        createdAt: DateTime.now(),
      ),
    );
    notifyListeners();
    await _save();
  }

  Future<void> removeByUrl(String url) async {
    final before = _entries.length;
    final normalized = url.trim();
    _entries.removeWhere((entry) => entry.url == normalized);
    if (_entries.length == before) return;
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

  Future<void> setThumbnail(String url, String? thumbnail) async {
    if (thumbnail == null || thumbnail.isEmpty) return;
    final normalized = url.trim();
    final index = _entries.indexWhere((entry) => entry.url == normalized);
    if (index < 0) return;
    final entry = _entries[index];
    if (entry.thumbnail == thumbnail) return;
    _entries[index] = entry.copyWith(thumbnail: thumbnail);
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
    return File('${support.path}/linky_bookmarks.json');
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
