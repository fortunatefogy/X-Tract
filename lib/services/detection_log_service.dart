import 'package:flutter/foundation.dart';

class DetectionLogEntry {
  DetectionLogEntry({
    required this.source,
    required this.event,
    required this.url,
    this.detail,
  }) : time = DateTime.now();

  final DateTime time;
  final String source;
  final String event;
  final String url;
  final String? detail;
}

class DetectionLogService extends ChangeNotifier {
  DetectionLogService._();

  static final DetectionLogService instance = DetectionLogService._();

  static const _maxEntries = 300;

  final List<DetectionLogEntry> _entries = [];

  List<DetectionLogEntry> get entries =>
      List.unmodifiable(_entries.reversed.toList(growable: false));

  bool get isEmpty => _entries.isEmpty;

  void log(String source, String event, String url, {String? detail}) {
    _entries.add(DetectionLogEntry(
      source: source,
      event: event,
      url: url,
      detail: detail,
    ));
    if (_entries.length > _maxEntries) {
      _entries.removeRange(0, _entries.length - _maxEntries);
    }
    notifyListeners();
  }

  void clear() {
    if (_entries.isEmpty) return;
    _entries.clear();
    notifyListeners();
  }
}
