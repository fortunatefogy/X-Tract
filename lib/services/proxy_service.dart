import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'settings_service.dart';

class ProxyService {
  ProxyService._();

  static final ProxyService instance = ProxyService._();

  Future<void> applyWebView() async {
    try {
      final chain = SettingsService.instance.proxyChain;
      if (!SettingsService.instance.proxyEnabled || chain.isEmpty) {
        await ProxyController.instance().clearProxyOverride();
        return;
      }
      final rules = <ProxyRule>[];
      for (final entry in chain) {
        final uri = _parse(entry);
        if (uri == null) continue;
        rules.add(
          ProxyRule(url: '${uri.host}:${uri.port}'),
        );
      }
      if (rules.isEmpty) {
        await ProxyController.instance().clearProxyOverride();
        return;
      }
      await ProxyController.instance().setProxyOverride(
        settings: ProxySettings(
          proxyRules: rules,
          bypassRules: const ['<local>'],
        ),
      );
    } catch (_) {}
  }

  static void applyToClient(HttpClient client) {
    if (!SettingsService.instance.proxyEnabled) return;
    for (final entry in SettingsService.instance.proxyChain) {
      final uri = _parse(entry);
      if (uri == null) continue;
      if (uri.scheme == 'http' || uri.scheme == 'https') {
        client.findProxy = (requestUri) =>
            'PROXY ${uri.host}:${uri.port}';
        return;
      }
    }
  }

  static Uri? _parse(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final withScheme =
        trimmed.contains('://') ? trimmed : 'http://$trimmed';
    final uri = Uri.tryParse(withScheme);
    if (uri == null || uri.host.isEmpty) return null;
    final scheme = uri.scheme.toLowerCase();
    if (!{'http', 'https', 'socks', 'socks5'}.contains(scheme)) return null;
    final port = uri.hasPort
        ? uri.port
        : scheme.startsWith('socks')
            ? 1080
            : 80;
    return Uri(
      scheme: scheme,
      host: uri.host,
      port: port,
    );
  }

  static String normalise(String value) {
    final uri = _parse(value);
    if (uri == null) return value.trim();
    return '${uri.scheme}://${uri.host}:${uri.port}';
  }
}
