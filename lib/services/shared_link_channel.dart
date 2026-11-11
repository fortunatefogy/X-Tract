import 'package:flutter/services.dart';

class SharedLinkChannel {
  static const _channel = MethodChannel('linky/share_intent');

  void Function(String text)? onSharedText;
  void Function(bool shareMode)? onLaunchModeChanged;
  void Function(bool openDownloads)? onOpenDownloads;
  void Function(bool hidden)? onAppHidden;

  SharedLinkChannel({bool listen = false}) {
    if (!listen) return;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'sharedText':
          if (call.arguments is String) {
            onSharedText?.call(call.arguments as String);
          }
        case 'shareModeChanged':
          if (call.arguments is bool) {
            onLaunchModeChanged?.call(call.arguments as bool);
          }
        case 'openDownloads':
          if (call.arguments is bool) {
            onOpenDownloads?.call(call.arguments as bool);
          }
        case 'appHidden':
          if (call.arguments is bool) {
            onAppHidden?.call(call.arguments as bool);
          }
      }
    });
  }

  static Future<String> getLaunchMode() async =>
      await _channel.invokeMethod<String>('getLaunchMode') ?? 'main';

  static Future<String?> getInitialText() =>
      _channel.invokeMethod<String>('getInitialSharedText');

  static Future<void> shareReady() async {
    try {
      await _channel.invokeMethod<bool>('shareReady');
    } catch (_) {}
  }

  static Future<void> minimizePopup() async {
    try {
      await _channel.invokeMethod<bool>('minimizeSharePopup');
    } catch (_) {}
  }

  static Future<void> closePopup() async {
    try {
      await _channel.invokeMethod<bool>('closeSharePopup');
    } catch (_) {}
  }
}
