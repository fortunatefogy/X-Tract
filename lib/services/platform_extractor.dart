import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/media_item.dart';

/// Calls the yt-dlp engine packaged inside Linky's Android application.
class PlatformExtractor {
  static const _channel = MethodChannel('linky/extractor');
  static final _progressListeners = <String, void Function(double)>{};
  static bool _progressHandlerInstalled = false;

  static void _ensureProgressHandler() {
    if (_progressHandlerInstalled) return;
    _progressHandlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'extractorProgress') return null;
      final args = call.arguments;
      if (args is Map) {
        final taskId = args['taskId']?.toString() ?? '';
        final listener = _progressListeners[taskId];
        if (listener != null) {
          final progress = (args['progress'] as num?)?.toDouble() ?? 0;
          listener(progress.clamp(0.0, 1.0).toDouble());
        }
      }
      return null;
    });
  }

  Future<String> cookieTextFor(String pageUrl,
      {InAppWebViewController? webViewController}) async {
    try {
      final host = Uri.parse(pageUrl).host.toLowerCase();
      final cookies = await CookieManager.instance().getCookies(
        url: WebUri(pageUrl),
        webViewController: webViewController,
      );
      final lines = <String>['# Netscape HTTP Cookie File'];
      for (final cookie in cookies.take(300)) {
        var domain = (cookie.domain ?? host).toLowerCase();
        final includeSubdomains = domain.startsWith('.');
        final bareDomain = domain.replaceFirst(RegExp(r'^\.'), '');
        if (bareDomain.isEmpty ||
            !(host == bareDomain || host.endsWith('.$bareDomain'))) {
          continue;
        }
        if (!RegExp(r'^\.?[a-z0-9.-]+$').hasMatch(domain)) continue;
        final name = cookie.name.replaceAll(RegExp(r'[\t\r\n]'), '');
        final value =
            cookie.value.toString().replaceAll(RegExp(r'[\t\r\n]'), '');
        final path = (cookie.path?.isNotEmpty == true ? cookie.path! : '/')
            .replaceAll(RegExp(r'[\t\r\n]'), '');
        if (name.isEmpty || name.contains(';')) continue;
        final expires = cookie.expiresDate == null
            ? '0'
            : (cookie.expiresDate! ~/ 1000).toString();
        final cookieDomain =
            cookie.isHttpOnly == true ? '#HttpOnly_$domain' : domain;
        lines.add([
          cookieDomain,
          includeSubdomains ? 'TRUE' : 'FALSE',
          path,
          cookie.isSecure == true ? 'TRUE' : 'FALSE',
          expires,
          name,
          value,
        ].join('\t'));
      }
      final result = lines.join('\n');
      return result.length <= 512 * 1024 ? result : '';
    } catch (_) {
      return '';
    }
  }

  Future<List<MediaItem>> extract(
    String pageUrl, {
    String cookieText = '',
  }) async {
    final raw = await _channel.invokeMethod<String>(
      'extractWithYtDlp',
      {'url': pageUrl, 'cookieText': cookieText},
    ).timeout(const Duration(seconds: 90));
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final media = decoded['media'];
    if (media is! List) return const [];
    return media
        .whereType<Map>()
        .map((item) => MediaItem.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<File> download({
    required String pageUrl,
    required String formatId,
    required Directory outputDirectory,
    String cookieText = '',
    String? audioFormatId,
    String? videoUrl,
    String? audioUrl,
    String? videoMimeType,
    String? audioMimeType,
    String? outputName,
    Map<String, String> headers = const {},
    String taskId = '',
    void Function(double progress)? onProgress,
  }) async {
    final trackProgress = taskId.isNotEmpty && onProgress != null;
    if (trackProgress) {
      _ensureProgressHandler();
      _progressListeners[taskId] = onProgress;
    }
    try {
      final path = await _channel.invokeMethod<String>(
        'downloadWithYtDlp',
        {
          'url': pageUrl,
          'formatId': formatId,
          'outputDirectory': outputDirectory.path,
          'cookieText': cookieText,
          'audioFormatId': audioFormatId ?? '',
          'videoUrl': videoUrl ?? '',
          'audioUrl': audioUrl ?? '',
          'headers': jsonEncode(headers),
          'outputName': outputName ?? '',
          'videoMimeType': videoMimeType ?? '',
          'audioMimeType': audioMimeType ?? '',
          'taskId': taskId,
        },
      ).timeout(const Duration(minutes: 10));
      if (path == null || path.isEmpty) {
        throw const FileSystemException(
            'yt-dlp did not return a saved file path.');
      }
      return File(path);
    } finally {
      if (trackProgress) _progressListeners.remove(taskId);
    }
  }
}
