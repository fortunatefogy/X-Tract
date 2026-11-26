import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class BrowserSessionTab {
  const BrowserSessionTab({
    required this.url,
    required this.title,
    this.desktopMode = false,
  });

  final String url;
  final String title;
  final bool desktopMode;

  Map<String, dynamic> toJson() => {
        'url': url,
        'title': title,
        'desktop_mode': desktopMode,
      };

  factory BrowserSessionTab.fromJson(Map<String, dynamic> json) =>
      BrowserSessionTab(
        url: json['url'] as String? ?? '',
        title: json['title'] as String? ?? '',
        desktopMode: json['desktop_mode'] as bool? ?? false,
      );
}

/// Persists the browser's tabs and the new-tab feed position so they survive
/// an app restart. Writes are debounced; [flush] forces an immediate write.
class BrowserSessionService {
  BrowserSessionService._();

  static final BrowserSessionService instance = BrowserSessionService._();

  List<BrowserSessionTab> _tabs = const [];
  int _activeIndex = 0;
  double _homeScrollOffset = 0;
  bool _loaded = false;
  Future<void>? _loading;
  Timer? _saveTimer;

  List<BrowserSessionTab> get tabs => List.unmodifiable(_tabs);
  int get activeIndex => _activeIndex;
  double get homeScrollOffset => _homeScrollOffset;

  Future<void> load() {
    if (_loaded) return Future.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final file = await _storeFile();
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          final rawTabs = decoded['tabs'];
          if (rawTabs is List) {
            _tabs = rawTabs
                .whereType<Map>()
                .map((raw) => BrowserSessionTab.fromJson(
                      Map<String, dynamic>.from(raw),
                    ))
                .where((tab) => tab.url.trim().isNotEmpty)
                .toList(growable: false);
          }
          _activeIndex = (decoded['active_index'] as num?)?.toInt() ?? 0;
          _homeScrollOffset = (decoded['home_scroll'] as num?)?.toDouble() ?? 0;
        }
      }
    } catch (_) {}
    if (_activeIndex < 0 || _activeIndex >= _tabs.length) _activeIndex = 0;
    if (_homeScrollOffset < 0) _homeScrollOffset = 0;
    _loaded = true;
  }

  void saveTabs({
    required List<BrowserSessionTab> tabs,
    required int activeIndex,
  }) {
    _tabs = List.unmodifiable(tabs.where((tab) => tab.url.trim().isNotEmpty));
    _activeIndex = tabs.isEmpty
        ? 0
        : activeIndex.clamp(0, _tabs.isEmpty ? 0 : _tabs.length - 1).toInt();
    _scheduleSave();
  }

  void updateHomeScroll(double offset) {
    if (!offset.isFinite || offset < 0) return;
    if ((_homeScrollOffset - offset).abs() < 1) return;
    _homeScrollOffset = offset;
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      _saveTimer = null;
      unawaited(flush());
    });
  }

  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    try {
      final file = await _storeFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'version': 1,
          'tabs': [for (final tab in _tabs) tab.toJson()],
          'active_index': _activeIndex,
          'home_scroll': _homeScrollOffset,
        }),
      );
    } catch (_) {}
  }

  Future<File> _storeFile() async {
    final support = await getApplicationSupportDirectory();
    return File('${support.path}/linky_browser_session.json');
  }
}
