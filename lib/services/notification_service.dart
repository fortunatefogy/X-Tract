import 'package:flutter/services.dart';

class NotificationService {
  static const _channel = MethodChannel('linky/notifications');
  static const _minInterval = Duration(milliseconds: 400);
  static final _lastProgress = <String, _ProgressSnapshot>{};

  static Future<void> downloadProgress(
    String taskId,
    String title,
    double progress, {
    bool indeterminate = false,
  }) async {
    if (taskId.isEmpty) return;
    final percent = indeterminate ? -1 : (progress * 100).round().clamp(0, 100);
    final now = DateTime.now();
    final last = _lastProgress[taskId];
    if (last != null && last.percent == percent) return;
    if (last != null && now.difference(last.at) < _minInterval) return;
    _lastProgress[taskId] = _ProgressSnapshot(percent, now);
    try {
      await _channel.invokeMethod<bool>('downloadProgress', {
        'taskId': taskId,
        'title': title,
        'progress': percent,
        'indeterminate': indeterminate,
      });
    } catch (_) {}
  }

  static Future<void> downloadComplete(String title, {String? taskId}) async {
    if (taskId != null) _lastProgress.remove(taskId);
    try {
      await _channel.invokeMethod<bool>(
        'downloadComplete',
        {
          'title': title,
          if (taskId != null) 'taskId': taskId,
        },
      );
    } catch (_) {}
  }

  static Future<void> dismiss(String taskId) async {
    if (taskId.isEmpty) return;
    _lastProgress.remove(taskId);
    try {
      await _channel.invokeMethod<bool>(
        'dismissNotification',
        {'taskId': taskId},
      );
    } catch (_) {}
  }

  static Future<bool> startDownloadService() async {
    try {
      return await _channel.invokeMethod<bool>('startDownloadService') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> stopDownloadService() async {
    try {
      return await _channel.invokeMethod<bool>('stopDownloadService') ?? false;
    } catch (_) {
      return false;
    }
  }
}

class _ProgressSnapshot {
  const _ProgressSnapshot(this.percent, this.at);

  final int percent;
  final DateTime at;
}
