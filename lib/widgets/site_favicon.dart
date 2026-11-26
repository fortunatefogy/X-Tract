import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// A cached site icon with a caller-provided fallback (usually an initial).
class SiteFavicon extends StatefulWidget {
  const SiteFavicon({
    super.key,
    required this.host,
    this.size = 30,
    this.radius = 10,
    this.background,
    required this.fallback,
  });

  @visibleForTesting
  static bool disableNetwork = false;

  final String host;
  final double size;
  final double radius;
  final Color? background;
  final Widget fallback;

  @override
  State<SiteFavicon> createState() => _SiteFaviconState();
}

class _SiteFaviconState extends State<SiteFavicon> {
  static final Map<String, Uint8List> _memory = {};
  static final Set<String> _failed = {};
  static final Map<String, Future<Uint8List?>> _inflight = {};

  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant SiteFavicon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.host != widget.host) {
      _bytes = null;
      _load();
    }
  }

  Future<void> _load() async {
    final host = widget.host.trim().toLowerCase();
    if (host.isEmpty) return;
    final cached = _memory[host];
    if (cached != null) {
      if (mounted) setState(() => _bytes = cached);
      return;
    }
    if (_failed.contains(host)) return;
    var pending = _inflight[host];
    if (pending == null) {
      pending = _loadFromDisk(host).then((bytes) async {
        return bytes ?? await _fetch(host);
      }).whenComplete(() => _inflight.remove(host));
      _inflight[host] = pending;
    }
    final bytes = await pending;
    if (!mounted || widget.host.trim().toLowerCase() != host) return;
    if (bytes == null || bytes.isEmpty) {
      _failed.add(host);
      return;
    }
    _memory[host] = bytes;
    setState(() => _bytes = bytes);
  }

  static Future<File> _cacheFile(String host) async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/linky_favicons');
    return File('${directory.path}/${Uri.encodeComponent(host)}.img');
  }

  static Future<Uint8List?> _loadFromDisk(String host) async {
    try {
      final file = await _cacheFile(host);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> _fetch(String host) async {
    if (SiteFavicon.disableNetwork) return null;
    final urls = [
      Uri.parse(
        'https://www.google.com/s2/favicons?domain=${Uri.encodeComponent(host)}&sz=128',
      ),
      Uri.parse('https://$host/favicon.ico'),
    ];
    for (final uri in urls) {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 6);
      try {
        final request = await client.getUrl(uri).timeout(
              const Duration(seconds: 8),
            );
        request.headers.set(
          HttpHeaders.userAgentHeader,
          'Mozilla/5.0 (Linux; Android 16) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/149.0.0.0 Mobile Safari/537.36',
        );
        final response = await request.close().timeout(
              const Duration(seconds: 8),
            );
        if (response.statusCode >= 200 && response.statusCode < 300) {
          final bytes = await consolidateHttpClientResponseBytes(response)
              .timeout(const Duration(seconds: 8));
          if (bytes.isNotEmpty) {
            _writeCache(host, bytes);
            return bytes;
          }
        }
      } catch (_) {
      } finally {
        client.close(force: true);
      }
    }
    return null;
  }

  static void _writeCache(String host, Uint8List bytes) {
    unawaited(_writeCacheAsync(host, bytes));
  }

  static Future<void> _writeCacheAsync(String host, Uint8List bytes) async {
    try {
      final file = await _cacheFile(host);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: false);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return Container(
      width: widget.size,
      height: widget.size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: widget.background,
        borderRadius: BorderRadius.circular(widget.radius),
      ),
      child: bytes == null
          ? widget.fallback
          : Padding(
              padding: EdgeInsets.all(widget.size * 0.18),
              child: Image.memory(
                bytes,
                width: widget.size,
                height: widget.size,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => widget.fallback,
              ),
            ),
    );
  }
}
