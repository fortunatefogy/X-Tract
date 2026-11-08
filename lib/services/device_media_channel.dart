import 'package:flutter/services.dart';

class DeviceMediaChannel {
  static const _channel = MethodChannel('linky/share_intent');

  Future<void> saveToGallery(String path) async {
    await _channel.invokeMethod<String>(
      'saveToGallery',
      {'path': path},
    );
  }
}
