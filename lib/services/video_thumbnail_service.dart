import 'dart:io';

import 'package:flutter/services.dart';

/// Extracts and caches a representative frame for local video files so lists
/// can show a real poster without keeping video decoders alive.
class VideoThumbnailService {
  VideoThumbnailService._();

  static final VideoThumbnailService instance = VideoThumbnailService._();

  static const _channel = MethodChannel('linky/device');
  static const _maxCached = 200;

  final Map<String, String?> _cache = <String, String?>{};
  final Map<String, Future<String?>> _pending = <String, Future<String?>>{};

  Future<String?> thumbnailFor(File file, {int maxSize = 256}) {
    if (!file.existsSync()) return Future<String?>.value();
    final String key;
    try {
      key = '${file.path}|${file.lastModifiedSync().millisecondsSinceEpoch}';
    } on FileSystemException {
      return Future<String?>.value();
    }
    if (_cache.containsKey(key)) return Future<String?>.value(_cache[key]);
    final inFlight = _pending[key];
    if (inFlight != null) return inFlight;

    final future = _generate(file.path, maxSize);
    _pending[key] = future;
    return future.then((path) {
      if (_cache.length >= _maxCached) {
        _cache.remove(_cache.keys.first);
      }
      _cache[key] = path;
      return path;
    }).whenComplete(() => _pending.remove(key));
  }

  Future<String?> _generate(String path, int maxSize) async {
    try {
      final result = await _channel.invokeMethod<String>(
        'getVideoThumbnail',
        {'path': path, 'maxSize': maxSize},
      );
      return (result == null || result.isEmpty) ? null : result;
    } catch (_) {
      return null;
    }
  }
}
