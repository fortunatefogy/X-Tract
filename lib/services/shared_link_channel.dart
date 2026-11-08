import 'package:flutter/services.dart';

class SharedLinkChannel {
  static const _channel = MethodChannel('linky/share_intent');
  void Function(String text)? onSharedText;

  SharedLinkChannel() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sharedText' && call.arguments is String) {
        onSharedText?.call(call.arguments as String);
      }
    });
  }

  Future<String?> getInitialText() =>
      _channel.invokeMethod<String>('getInitialSharedText');
}
