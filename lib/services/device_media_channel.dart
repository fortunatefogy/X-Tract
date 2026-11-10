import 'package:flutter/services.dart';

class DeviceMediaChannel {
  static const _channel = MethodChannel('linky/share_intent');

  Future<void> saveToGallery(String path) async {
    await _channel.invokeMethod<String>(
      'saveToGallery',
      {'path': path},
    );
  }

  Future<void> shareFile(String path) async {
    await _channel.invokeMethod<bool>('shareFile', {'path': path});
  }

  Future<void> shareFiles(List<String> paths) async {
    if (paths.isEmpty) return;
    await _channel.invokeMethod<bool>('shareFiles', {'paths': paths});
  }

  Future<void> openWithFile(String path) async {
    await _channel.invokeMethod<bool>('openWithFile', {'path': path});
  }
}
