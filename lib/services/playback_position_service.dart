import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class PlaybackPositionService {
  PlaybackPositionService._();

  static final PlaybackPositionService instance = PlaybackPositionService._();

  final Map<String, int> _positions = {};
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final file = await _storeFile();
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            final value = (entry.value as num?)?.toInt();
            if (value != null && value > 0) {
              _positions[entry.key.toString()] = value;
            }
          }
        }
      }
    } catch (_) {}
  }

  Duration? positionFor(String path) {
    final value = _positions[path];
    return value == null ? null : Duration(milliseconds: value);
  }

  Future<void> save(String path, Duration position) async {
    if (position.inSeconds <= 3) {
      if (_positions.remove(path) == null) return;
    } else {
      _positions[path] = position.inMilliseconds;
    }
    await _persist();
  }

  Future<void> clear(String path) async {
    if (_positions.remove(path) == null) return;
    await _persist();
  }

  Future<File> _storeFile() async {
    final support = await getApplicationSupportDirectory();
    return File('${support.path}/linky_playback.json');
  }

  Future<void> _persist() async {
    try {
      final file = await _storeFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(_positions));
    } catch (_) {}
  }
}
