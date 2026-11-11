import 'package:flutter/services.dart';

class NotificationService {
  static const _channel = MethodChannel('linky/notifications');

  static Future<void> downloadComplete(String title) async {
    try {
      await _channel.invokeMethod<bool>(
        'downloadComplete',
        {'title': title},
      );
    } catch (_) {}
  }
}
