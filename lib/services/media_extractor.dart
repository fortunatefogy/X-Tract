import 'dart:convert';
import 'dart:io';

import '../models/media_item.dart';

class MediaExtractor {
  static const _maxPageBytes = 2 * 1024 * 1024;
  static const _timeout = Duration(seconds: 20);

  Future<List<MediaItem>> extract(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null ||
        !uri.hasAuthority ||
        !{'http', 'https'}.contains(uri.scheme.toLowerCase())) {
      throw const FormatException('Enter a valid http or https link.');
    }

    final directType = _typeFromPath(uri);
    if (directType != null) {
      return [
        MediaItem(
          url: uri.toString(),
          type: directType,
          sourcePage: uri.toString(),
          mimeType: _mimeFromPath(uri),
          isDownloadable: !_isPlaylist(uri),
        ),
      ];
    }
    final embedded = _embeddedMediaUrl(uri);
    if (embedded != null) {
      final embeddedType = _typeFromPath(embedded);
      if (embeddedType != null) {
        return [
          MediaItem(
            url: embedded.toString(),
            type: embeddedType,
            sourcePage: uri.toString(),
            mimeType: _mimeFromPath(embedded),
            foundIn: 'embedded URL parameter',
          ),
        ];
      }
      final embeddedPlatformType = _platformType(embedded);
      if (embeddedPlatformType != null) {
        return [
          MediaItem(
            url: embedded.toString(),
            type: embeddedPlatformType,
            sourcePage: uri.toString(),
            mimeType: 'text/html',
            foundIn: 'embedded platform URL',
            isDownloadable: false,
          ),
        ];
      }
    }
    final platformType = _platformType(uri);
    if (platformType != null) {
      return [
        MediaItem(
          url: uri.toString(),
          type: platformType,
          title: '${platformType.toUpperCase()} page · ${uri.host}',
          sourcePage: uri.toString(),
          mimeType: 'text/html',
          foundIn: 'supported platform link',
          isDownloadable: false,
        ),
      ];
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..userAgent = 'Linky Android';
    try {
      final headRequest = await client.headUrl(uri).timeout(_timeout);
      headRequest.followRedirects = true;
      final headResponse = await headRequest.close().timeout(_timeout);
      final headType = _typeFromMime(
        headResponse.headers.contentType?.mimeType ?? '',
      );
      final headUri = _redirectedUri(uri, headResponse.redirects);
      await headResponse.drain<void>();
      if (headType != null &&
          headResponse.statusCode >= 200 &&
          headResponse.statusCode < 300) {
        return [
          MediaItem(
            url: headUri.toString(),
            type: headType,
            sourcePage: rawUrl,
            mimeType: headResponse.headers.contentType?.mimeType,
            isDownloadable: !_isPlaylist(headUri) &&
                !headResponse.headers.contentType!.mimeType
                    .contains('mpegurl') &&
                !headResponse.headers.contentType!.mimeType
                    .contains('dash+xml'),
          ),
        ];
      }

      final (response, finalUri) = await _get(client, uri);
      final contentType = response.headers.contentType?.mimeType ?? '';
      final responseType = _typeFromMime(contentType);
      if (responseType != null) {
        return [
          MediaItem(
            url: finalUri.toString(),
            type: responseType,
            sourcePage: rawUrl,
            mimeType: contentType,
            isDownloadable: !_isPlaylist(finalUri) &&
                !contentType.contains('mpegurl') &&
                !contentType.contains('dash+xml'),
          ),
        ];
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('The page returned HTTP ${response.statusCode}.');
      }
      if (!contentType.toLowerCase().contains('html')) {
        return const [];
      }

      final bytes = <int>[];
      await for (final chunk in response.timeout(_timeout)) {
        final remaining = _maxPageBytes - bytes.length;
        if (remaining <= 0) break;
        bytes.addAll(chunk.take(remaining));
        if (chunk.length > remaining) break;
      }
      final html = utf8.decode(bytes, allowMalformed: true);
      return _parseHtml(html, finalUri, rawUrl);
    } finally {
      client.close(force: true);
    }
  }

  String? _platformType(Uri uri) {
    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    final path = '${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}';
    if (host == 'youtube.com' &&
            RegExp(r'^/watch\?|^/embed/|^/v/').hasMatch(path) ||
        host == 'youtu.be') return 'video';
    if (host == 'vimeo.com' && RegExp(r'^/\d+|^/video/').hasMatch(path) ||
        host == 'player.vimeo.com') return 'video';
    if (host == 'dailymotion.com' &&
        RegExp(r'^/video/|^/embed/').hasMatch(path)) return 'video';
    if ((host == 'twitch.tv' && RegExp(r'^/videos/|^/clip/').hasMatch(path)) ||
        host == 'clips.twitch.tv') return 'video';
    if (host == 'tiktok.com' && RegExp(r'^/@[\w.-]+/video/').hasMatch(path))
      return 'video';
    if (['facebook.com', 'instagram.com', 'twitter.com', 'x.com']
            .contains(host) &&
        RegExp(r'/watch/|/videos/|/reel/|/tv/|/status/').hasMatch(path))
      return 'video';
    if ([
          'spotify.com',
          'open.spotify.com',
          'soundcloud.com',
          'mixcloud.com',
          'audiomack.com',
          'podcasts.apple.com',
          'anchor.fm'
        ].contains(host) &&
        (host != 'spotify.com' ||
            RegExp(r'/track/|/episode/|/album/').hasMatch(path)))
      return 'audio';
    if ((host == 'bandcamp.com' || host.endsWith('.bandcamp.com')) &&
        host != 'bandcamp.com') return 'audio';
    if (host == 'docs.google.com' &&
        !RegExp(r'^/document/|^/spreadsheets/|^/presentation/|^/viewer')
            .hasMatch(path)) return null;
    if (host == 'drive.google.com' &&
        !RegExp(r'^/file/|^/viewer').hasMatch(path)) return null;
    if (host == 'dropbox.com' && !RegExp(r'^/s/').hasMatch(path)) return null;
    if (host == 'scribd.com' && !RegExp(r'^/document/|^/doc/').hasMatch(path))
      return null;
    if (host == 'box.com' && !RegExp(r'^/s/|^/file/').hasMatch(path))
      return null;
    if (host.endsWith('.sharepoint.com') &&
        !RegExp(r'^/_layouts/|^/Documents/').hasMatch(path)) return null;
    if ([
          'docs.google.com',
          'drive.google.com',
          'dropbox.com',
          'scribd.com',
          'slideshare.net',
          'issuu.com',
          'box.com'
        ].contains(host) ||
        host.endsWith('.sharepoint.com')) return 'document';
    return null;
  }

  Uri? _embeddedMediaUrl(Uri uri) {
    const parameterNames = {
      'url',
      'u',
      'imgurl',
      'media',
      'image',
      'video',
      'src',
      'file',
      'contenturl',
      'redirect',
      'target',
    };
    for (final entry in uri.queryParameters.entries) {
      if (!parameterNames.contains(entry.key.toLowerCase())) continue;
      var value = entry.value;
      for (var decodePass = 0; decodePass < 2; decodePass++) {
        final candidate = Uri.tryParse(value);
        if (candidate != null &&
            {'http', 'https'}.contains(candidate.scheme.toLowerCase()) &&
            (_typeFromPath(candidate) != null ||
                _platformType(candidate) != null)) {
          return candidate;
        }
        try {
          final decoded = Uri.decodeComponent(value);
          if (decoded == value) break;
          value = decoded;
        } catch (_) {
          break;
        }
      }
    }
    return null;
  }

  Future<(HttpClientResponse, Uri)> _get(HttpClient client, Uri uri) async {
    final request = await client.getUrl(uri).timeout(_timeout);
    request.followRedirects = true;
    final response = await request.close().timeout(_timeout);
    return (response, _redirectedUri(uri, response.redirects));
  }

  Uri _redirectedUri(Uri original, List<RedirectInfo> redirects) {
    var current = original;
    for (final redirect in redirects) {
      current = current.resolve(redirect.location.toString());
    }
    return current;
  }

  List<MediaItem> _parseHtml(String html, Uri pageUri, String sourcePage) {
    final items = <String, MediaItem>{};
    final tagPattern = RegExp(
      r'<(img|video|audio|source|track|meta|link|a)\b[^>]*>',
      caseSensitive: false,
    );
    final attrPattern = RegExp(
      r'''([\w:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))''',
      caseSensitive: false,
    );

    for (final tagMatch in tagPattern.allMatches(html)) {
      final tag = tagMatch.group(1)!.toLowerCase();
      final attributes = <String, String>{};
      for (final match in attrPattern.allMatches(tagMatch.group(0)!)) {
        final value = match.group(2) ?? match.group(3) ?? match.group(4) ?? '';
        attributes[match.group(1)!.toLowerCase()] =
            _decodeEntities(value.trim());
      }

      final candidates = <(String, String)>[];
      if (tag == 'meta') {
        final property =
            (attributes['property'] ?? attributes['name'] ?? '').toLowerCase();
        final mediaType = switch (property) {
          'og:image' ||
          'og:image:url' ||
          'twitter:image' ||
          'twitter:image:src' =>
            'image',
          'og:video' ||
          'og:video:url' ||
          'og:video:secure_url' ||
          'twitter:player:stream' =>
            'video',
          'og:audio' || 'og:audio:url' || 'og:audio:secure_url' => 'audio',
          _ => null,
        };
        if (mediaType != null && attributes['content'] != null) {
          candidates.add((attributes['content']!, mediaType));
        }
      } else if (tag == 'img') {
        for (final key in [
          'src',
          'data-src',
          'data-lazy-src',
          'data-original',
          'data-original-src',
          'data-actualsrc',
          'data-url'
        ]) {
          if (attributes[key] case final value?) {
            candidates.add((value, 'image'));
          }
        }
        for (final key in ['data-lazy-srcset', 'data-srcset', 'srcset']) {
          if (attributes[key] case final value?) {
            for (final source in value.split(',')) {
              final url = source.trim().split(RegExp(r'\s+')).firstOrNull;
              if (url != null && url.isNotEmpty) candidates.add((url, 'image'));
            }
          }
        }
      } else if (tag == 'video') {
        if (attributes['src'] case final value?) {
          candidates.add((value, 'video'));
        }
        if (attributes['poster'] case final value?) {
          candidates.add((value, 'image'));
        }
      } else if (tag == 'source') {
        final sourceUrl = attributes['src'] ??
            attributes['data-src'] ??
            attributes['data-lazy-src'];
        if (sourceUrl case final value?) {
          final kind = _typeFromMime(attributes['type'] ?? '') ??
              _typeFromPath(Uri.tryParse(value) ?? Uri());
          if (kind != null) candidates.add((value, kind));
        }
      } else if (tag == 'audio' || tag == 'track') {
        if (attributes['src'] case final value?) {
          candidates.add((value, tag == 'track' ? 'subtitle' : 'audio'));
        }
      } else if (tag == 'a') {
        if (attributes['href'] case final value?) {
          final kind = _typeFromPath(Uri.tryParse(value) ?? Uri());
          if (kind != null) candidates.add((value, kind));
        }
      } else if (tag == 'link' &&
          RegExp(r'image_src|icon|apple-touch-icon|preload',
                  caseSensitive: false)
              .hasMatch(attributes['rel'] ?? '')) {
        if (attributes['href'] case final value?) {
          final kind = _typeFromMime(attributes['type'] ?? '') ??
              _typeFromPath(Uri.tryParse(value) ?? Uri());
          final isIconLink =
              RegExp(r'image_src|icon|apple-touch-icon', caseSensitive: false)
                  .hasMatch(attributes['rel'] ?? '');
          final preloadAs = (attributes['as'] ?? '').toLowerCase();
          final hintedKind = kind ??
              (isIconLink
                  ? 'image'
                  : switch (preloadAs) {
                      'image' => 'image',
                      'video' => 'video',
                      'audio' => 'audio',
                      _ => null,
                    });
          if (hintedKind != null) candidates.add((value, hintedKind));
        }
      }

      for (final (rawCandidate, hintedType) in candidates) {
        if (rawCandidate.isEmpty || rawCandidate.startsWith('data:')) continue;
        final candidate = pageUri.resolve(rawCandidate);
        if (!{'http', 'https'}.contains(candidate.scheme.toLowerCase())) {
          continue;
        }
        final type = _typeFromPath(candidate) ?? hintedType;
        final poster =
            tag == 'video' && type == 'video' ? attributes['poster'] : null;
        items.putIfAbsent(
            candidate.toString(),
            () => MediaItem(
                  url: candidate.toString(),
                  type: type,
                  sourcePage: sourcePage,
                  mimeType: _mimeFromPath(candidate),
                  thumbnail: poster == null || poster.isEmpty
                      ? null
                      : pageUri.resolve(poster).toString(),
                  title: attributes['title'],
                  alt: attributes['alt'],
                  width: int.tryParse(attributes['width'] ?? ''),
                  height: int.tryParse(attributes['height'] ?? ''),
                  foundIn: tag,
                ));
      }
    }

    final stylePattern = RegExp(r'''style\s*=\s*(?:"([^"]*)"|'([^']*)')''',
        caseSensitive: false);
    for (final styleMatch in stylePattern.allMatches(html)) {
      final style = styleMatch.group(1) ?? styleMatch.group(2) ?? '';
      for (final background
          in RegExp(r'''url\(["']?([^"')]+)["']?\)''', caseSensitive: false)
              .allMatches(style)) {
        _addHtmlCandidate(items, pageUri, background.group(1)!, 'image',
            sourcePage, 'css-background');
      }
    }

    final jsonLdPattern = RegExp(
        r'''<script[^>]+type\s*=\s*["']application/ld\+json["'][^>]*>(.*?)</script>''',
        caseSensitive: false, dotAll: true);
    for (final match in jsonLdPattern.allMatches(html)) {
      try {
        void inspect(Object? value) {
          if (value is List) {
            for (final entry in value) {
              inspect(entry);
            }
          } else if (value is Map) {
            value.forEach((key, child) {
              final name = key.toString().toLowerCase();
              final type = name.contains('image') || name.contains('thumbnail')
                  ? 'image'
                  : name.contains('audio')
                      ? 'audio'
                      : name.contains('video') || name.contains('contenturl')
                          ? 'video'
                          : null;
              if (type != null && child is String)
                _addHtmlCandidate(
                    items, pageUri, child, type, sourcePage, 'json-ld');
              else
                inspect(child);
            });
          }
        }

        inspect(jsonDecode(match.group(1) ?? ''));
      } catch (_) {}
    }
    return items.values.take(100).toList();
  }

  void _addHtmlCandidate(Map<String, MediaItem> items, Uri pageUri, String raw,
      String hintedType, String sourcePage, String foundIn) {
    if (raw.isEmpty || raw.startsWith('data:')) return;
    final uri = pageUri.resolve(raw);
    if (!{'http', 'https'}.contains(uri.scheme.toLowerCase())) return;
    items.putIfAbsent(
        uri.toString(),
        () => MediaItem(
              url: uri.toString(),
              type: _typeFromPath(uri) ?? hintedType,
              sourcePage: sourcePage,
              mimeType: _mimeFromPath(uri),
              foundIn: foundIn,
              isDownloadable: !_isPlaylist(uri),
            ));
  }

  String _decodeEntities(String value) => value
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');

  String? _typeFromPath(Uri uri) {
    var path = uri.path.toLowerCase();
    var extension =
        path.contains('.') ? path.substring(path.lastIndexOf('.') + 1) : '';
    if (extension.isEmpty || extension.length > 10) {
      for (final key in ['format', 'f', 'type', 'output', 'fm', 'ext']) {
        final value =
            uri.queryParameters[key]?.toLowerCase().replaceFirst('.', '');
        if (value != null && value.length <= 10) {
          extension = value;
          break;
        }
      }
      path = '.$extension';
    }
    if (RegExp(
            r'\.(jpe?g|png|gif|webp|avif|bmp|svg|tiff?|ico|jfif|jxl|heic|heif|apng|jp2|j2k|jpf|jpx|jpm|mj2|pcx|tga|wbmp|xbm|dib|emf|wmf|ras|icns|cur|fpx|bpg|qoi|hdr|exr|pbm|pgm|ppm|pam|dng|psd)$')
        .hasMatch(path)) {
      return 'image';
    }
    if (RegExp(
            r'\.(mp4|webm|mov|m4v|m3u8|mpd|3gp|3g2|ts|m4s|ism|isml|flv|mkv|avi|ogv|ogm|asf|wmv|mpg|mpeg|m2v|m2ts|mts|vob|mxf|f4v|f4p|rm|rmvb|dv|nut|mjpeg|3gpp|3gp2|wtv|dvr-ms|gxf|lxf|pva|roq|smk|bik|viv|yuv|y4m|h264|h265|hevc|vc1|mpegts)$')
        .hasMatch(path)) {
      return 'video';
    }
    if (RegExp(
            r'\.(mp3|m4a|aac|ogg|oga|opus|wav|flac|weba|amr|ac3|eac3|caf|aiff?|wma|mka|m4b|m4p|mid|midi|f4a|f4b|aifc|au|snd|ra|ram|rmi|mpc|ape|tak|tta|wv|spx|voc|8svx|pls|asx)$')
        .hasMatch(path)) return 'audio';
    if (RegExp(r'\.(pdf|docx?|xlsx?|pptx?|txt|rtf|odt|ods|odp|csv|epub|mobi)$')
        .hasMatch(path)) return 'document';
    if (RegExp(r'\.(vtt|srt|ttml|ass|ssa)$').hasMatch(path)) return 'subtitle';
    return null;
  }

  bool _isPlaylist(Uri uri) =>
      RegExp(r'\.(m3u8|m3u|mpd|pls|asx)$', caseSensitive: false)
          .hasMatch(uri.path);

  String? _typeFromMime(String mime) {
    final normalized = mime.toLowerCase();
    if (normalized.startsWith('image/')) return 'image';
    if (normalized.startsWith('audio/')) return 'audio';
    if (normalized.startsWith('video/') ||
        normalized.contains('mpegurl') ||
        normalized.contains('dash+xml')) {
      return 'video';
    }
    if (normalized.contains('pdf') ||
        normalized.contains('officedocument') ||
        normalized.contains('msword') ||
        normalized.contains('spreadsheet') ||
        normalized.contains('presentation') ||
        normalized.startsWith('text/plain')) return 'document';
    if (normalized.contains('vtt') || normalized.contains('subrip'))
      return 'subtitle';
    return null;
  }

  String? _mimeFromPath(Uri uri) {
    final path = uri.path.toLowerCase();
    if (path.endsWith('.jpg') || path.endsWith('.jpeg')) return 'image/jpeg';
    if (path.endsWith('.png')) return 'image/png';
    if (path.endsWith('.gif')) return 'image/gif';
    if (path.endsWith('.webp')) return 'image/webp';
    if (path.endsWith('.svg')) return 'image/svg+xml';
    if (path.endsWith('.avif')) return 'image/avif';
    if (path.endsWith('.mp4')) return 'video/mp4';
    if (path.endsWith('.webm')) return 'video/webm';
    if (path.endsWith('.mp3')) return 'audio/mpeg';
    if (path.endsWith('.pls')) return 'audio/x-scpls';
    if (path.endsWith('.asx')) return 'video/x-ms-asf';
    if (path.endsWith('.m4a')) return 'audio/mp4';
    if (path.endsWith('.ogg') || path.endsWith('.opus')) return 'audio/ogg';
    if (path.endsWith('.pdf')) return 'application/pdf';
    if (path.endsWith('.m3u8')) return 'application/vnd.apple.mpegurl';
    if (path.endsWith('.mpd')) return 'application/dash+xml';
    return null;
  }
}
