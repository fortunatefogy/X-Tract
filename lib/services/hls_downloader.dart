import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'proxy_service.dart';
import 'secure_dns_service.dart';
import 'dart:math';
import 'dart:typed_data';

import 'device_resources.dart';

class HlsDownloadResult {
  const HlsDownloadResult({
    required this.file,
    required this.isLive,
    required this.variantLabel,
    this.warning,
  });

  final File file;
  final bool isLive;
  final String variantLabel;
  final String? warning;
}

class HlsCanceled implements Exception {
  const HlsCanceled();
}

class _HlsVariant {
  const _HlsVariant({
    required this.uri,
    required this.bandwidth,
    this.width,
    this.height,
    this.codecs,
    this.audioGroup,
    this.subtitlesGroup,
  });

  final Uri uri;
  final int bandwidth;
  final int? width;
  final int? height;
  final String? codecs;
  final String? audioGroup;
  final String? subtitlesGroup;

  String get label {
    if (height != null && height! > 0) return '${height}p';
    if (bandwidth > 0) return '${(bandwidth / 1000).round()} kbps';
    return 'HLS';
  }
}

class _HlsRendition {
  const _HlsRendition({
    required this.type,
    required this.groupId,
    required this.name,
    required this.isDefault,
    this.language,
    this.uri,
  });

  final String type;
  final String groupId;
  final String name;
  final bool isDefault;
  final String? language;
  final Uri? uri;
}

class _HlsSegment {
  const _HlsSegment({
    required this.uri,
    required this.sequence,
    this.keyUri,
    this.iv,
    this.byteRangeOffset,
    this.byteRangeLength,
  });

  final Uri uri;
  final int sequence;
  final Uri? keyUri;
  final Uint8List? iv;
  final int? byteRangeOffset;
  final int? byteRangeLength;
}

class _HlsPlaylist {
  _HlsPlaylist({
    required this.baseUri,
    this.variants = const [],
    this.renditions = const [],
    this.segments = const [],
    this.initUri,
    this.initByteRangeOffset,
    this.initByteRangeLength,
    this.initKeyUri,
    this.initIv,
    this.isLive = false,
    this.targetDuration = 0,
  });

  final Uri baseUri;
  final List<_HlsVariant> variants;
  final List<_HlsRendition> renditions;
  final List<_HlsSegment> segments;
  final Uri? initUri;
  final int? initByteRangeOffset;
  final int? initByteRangeLength;
  final Uri? initKeyUri;
  final Uint8List? initIv;
  final bool isLive;
  final int targetDuration;

  bool get isMaster => variants.isNotEmpty;
}

class HlsDownloader {
  HlsDownloader({
    this.workers = 4,
    this.retries = 3,
  });

  final int workers;
  final int retries;

  Future<HlsDownloadResult> download({
    required String url,
    required File destination,
    required Directory workDirectory,
    Map<String, String> headers = const {},
    required void Function(int completedSegments, int totalSegments) onProgress,
    bool Function()? isCancelled,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme)) {
      throw const FormatException(
          'Only http and https HLS streams are supported.');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30)
      ..idleTimeout = const Duration(seconds: 30)
      ..userAgent = 'Linky Android';
    ProxyService.applyToClient(client);
    await SecureDnsService.instance.configure(client);
    try {
      final root = await _loadPlaylist(client, uri, headers);
      var media = root;
      _HlsVariant? variant;
      if (root.isMaster) {
        variant = _bestVariant(root.variants);
        media = await _loadPlaylist(client, variant.uri, headers);
        if (media.isMaster) {
          variant = _bestVariant(media.variants);
          media = await _loadPlaylist(client, variant.uri, headers);
        }
      }
      if (media.segments.isEmpty) {
        throw const FormatException('The HLS playlist has no media segments.');
      }
      final videoFile = await _downloadMedia(
        client: client,
        playlist: media,
        baseUrl: url,
        destination: destination,
        workDirectory: workDirectory,
        headers: headers,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );

      File output = videoFile;
      String? warning;
      final audioRendition = _audioRendition(root, variant);
      if (audioRendition?.uri != null && !_variantIncludesAudio(variant)) {
        try {
          final audioPlaylist =
              await _loadPlaylist(client, audioRendition!.uri!, headers);
          final audioFile = await _downloadMedia(
            client: client,
            playlist: audioPlaylist,
            baseUrl: url,
            destination: File('${_stem(destination.path)}.m4a'),
            workDirectory: Directory(
              '${workDirectory.path}${Platform.pathSeparator}audio',
            ),
            headers: headers,
            onProgress: (_, __) {},
            isCancelled: isCancelled,
          );
          final muxedPath = '${_stem(destination.path)}.mp4';
          final muxed = await DeviceResources.instance
              .muxMedia(videoFile.path, audioFile.path, muxedPath);
          if (muxed != null && await File(muxed).exists()) {
            output = File(muxed);
            await _deleteQuietly(videoFile);
            await _deleteQuietly(audioFile);
          } else {
            warning =
                'The separate audio track could not be merged; saved the video track only.';
          }
        } catch (_) {
          warning =
              'The separate audio track could not be downloaded; saved the video track only.';
        }
      }
      return HlsDownloadResult(
        file: output,
        isLive: media.isLive,
        variantLabel: variant?.label ?? 'HLS',
        warning: warning,
      );
    } finally {
      client.close(force: true);
    }
  }

  _HlsVariant _bestVariant(List<_HlsVariant> variants) {
    final sorted = List<_HlsVariant>.from(variants)
      ..sort((a, b) {
        final height = (b.height ?? 0).compareTo(a.height ?? 0);
        if (height != 0) return height;
        return b.bandwidth.compareTo(a.bandwidth);
      });
    return sorted.first;
  }

  _HlsRendition? _audioRendition(
    _HlsPlaylist root,
    _HlsVariant? variant,
  ) {
    if (variant?.audioGroup == null) return null;
    final matches = root.renditions.where(
      (rendition) =>
          rendition.type == 'AUDIO' &&
          rendition.groupId == variant!.audioGroup &&
          rendition.uri != null,
    );
    if (matches.isEmpty) return null;
    for (final rendition in matches) {
      if (rendition.isDefault) return rendition;
    }
    return matches.first;
  }

  bool _variantIncludesAudio(_HlsVariant? variant) {
    final codecs = variant?.codecs?.toLowerCase() ?? '';
    if (codecs.isEmpty) return true;
    return RegExp(r'mp4a|ac-3|ec-3|opus|vorbis|flac|aac').hasMatch(codecs);
  }

  Future<File> _downloadMedia({
    required HttpClient client,
    required _HlsPlaylist playlist,
    required String baseUrl,
    required File destination,
    required Directory workDirectory,
    required Map<String, String> headers,
    required void Function(int completedSegments, int totalSegments) onProgress,
    bool Function()? isCancelled,
  }) async {
    await workDirectory.create(recursive: true);
    final container = _containerFor(playlist);
    final output = File(
      '${_stem(destination.path)}.$container',
    );
    final keyCache = <String, Uint8List>{};
    final completedFile = File(
      '${workDirectory.path}${Platform.pathSeparator}completed.json',
    );
    final completed = <int>{};
    if (await completedFile.exists()) {
      try {
        final raw = jsonDecode(await completedFile.readAsString());
        if (raw is List) {
          completed.addAll(
            raw.whereType<num>().map((value) => value.toInt()),
          );
        }
      } catch (_) {}
    }
    var saveChain = Future<void>.value();
    Future<void> saveCompleted() {
      final snapshot = completed.toList()..sort();
      saveChain = saveChain.then((_) async {
        final temporary = File('${completedFile.path}.tmp');
        await temporary.writeAsString(jsonEncode(snapshot), flush: true);
        await temporary.rename(completedFile.path);
      }).catchError((_) {});
      return saveChain;
    }

    final initFile =
        File('${workDirectory.path}${Platform.pathSeparator}init.bin');
    if (playlist.initUri != null && !await initFile.exists()) {
      final bytes = await _fetch(
        client,
        playlist.initUri!,
        headers,
        byteRangeOffset: playlist.initByteRangeOffset,
        byteRangeLength: playlist.initByteRangeLength,
      );
      var data = bytes;
      if (playlist.initKeyUri != null) {
        data = await _decrypt(
          bytes,
          playlist.initKeyUri!,
          playlist.initIv,
          0,
          headers,
          client,
          keyCache,
        );
      }
      await initFile.writeAsBytes(data, flush: true);
    }

    var next = 0;
    var completedCount = completed.length;
    onProgress(completedCount, playlist.segments.length);
    final workerCount = min(workers, max(1, playlist.segments.length));
    await Future.wait(
      List.generate(workerCount, (_) async {
        while (true) {
          if (isCancelled?.call() == true) throw const HlsCanceled();
          final index = next++;
          if (index >= playlist.segments.length) return;
          if (completed.contains(index)) continue;
          final segment = playlist.segments[index];
          final raw = await _fetch(
            client,
            segment.uri,
            headers,
            byteRangeOffset: segment.byteRangeOffset,
            byteRangeLength: segment.byteRangeLength,
          );
          var data = raw;
          if (segment.keyUri != null) {
            data = await _decrypt(
              raw,
              segment.keyUri!,
              segment.iv,
              segment.sequence,
              headers,
              client,
              keyCache,
            );
          }
          final segmentFile = File(
            '${workDirectory.path}${Platform.pathSeparator}seg-$index.bin',
          );
          await segmentFile.writeAsBytes(data, flush: true);
          completed.add(index);
          completedCount = completed.length;
          await saveCompleted();
          onProgress(completedCount, playlist.segments.length);
        }
      }),
    );

    await destination.parent.create(recursive: true);
    final temporary = File('${output.path}.linky-tmp');
    final sink = temporary.openWrite();
    try {
      if (await initFile.exists()) {
        await sink.addStream(initFile.openRead());
      }
      for (var index = 0; index < playlist.segments.length; index++) {
        final segmentFile = File(
          '${workDirectory.path}${Platform.pathSeparator}seg-$index.bin',
        );
        if (!await segmentFile.exists()) {
          throw HttpException('The HLS segment $index is missing.');
        }
        await sink.addStream(segmentFile.openRead());
      }
      await sink.flush();
      await sink.close();
      if (await output.exists()) await output.delete();
      await temporary.rename(output.path);
    } catch (_) {
      try {
        await sink.close();
      } catch (_) {}
      try {
        if (await temporary.exists()) await temporary.delete();
      } catch (_) {}
      rethrow;
    }
    try {
      await workDirectory.delete(recursive: true);
    } catch (_) {}
    return output;
  }

  String _containerFor(_HlsPlaylist playlist) {
    if (playlist.initUri != null) return 'mp4';
    for (final segment in playlist.segments) {
      final path = segment.uri.path.toLowerCase();
      if (path.endsWith('.m4s') ||
          path.endsWith('.mp4') ||
          path.endsWith('.m4v')) {
        return 'mp4';
      }
    }
    return 'ts';
  }

  Future<Uint8List> _decrypt(
    Uint8List data,
    Uri keyUri,
    Uint8List? explicitIv,
    int sequence,
    Map<String, String> headers,
    HttpClient client,
    Map<String, Uint8List> keyCache,
  ) async {
    final key = keyCache[keyUri.toString()] ??
        await _loadKey(client, keyUri, headers, keyCache);
    final iv = explicitIv ?? _sequenceIv(sequence);
    final decrypted =
        await DeviceResources.instance.decryptAes128(data, key, iv);
    if (decrypted == null) {
      throw const FormatException(
        'AES-128 decryption is unavailable or the key is invalid.',
      );
    }
    return decrypted;
  }

  Future<Uint8List> _loadKey(
    HttpClient client,
    Uri uri,
    Map<String, String> headers,
    Map<String, Uint8List> cache,
  ) async {
    final existing = cache[uri.toString()];
    if (existing != null) return existing;
    final bytes = await _fetch(client, uri, headers);
    if (bytes.length != 16) {
      throw const FormatException('The HLS AES-128 key must be 16 bytes.');
    }
    cache[uri.toString()] = bytes;
    return bytes;
  }

  Uint8List _sequenceIv(int sequence) {
    final iv = Uint8List(16);
    var value = sequence;
    for (var index = 15; index >= 0 && value > 0; index--) {
      iv[index] = value & 0xff;
      value >>= 8;
    }
    return iv;
  }

  Future<Uint8List> _fetch(
    HttpClient client,
    Uri uri,
    Map<String, String> headers, {
    int? byteRangeOffset,
    int? byteRangeLength,
  }) async {
    final range = byteRangeOffset != null && byteRangeLength != null
        ? 'bytes=$byteRangeOffset-${byteRangeOffset + byteRangeLength - 1}'
        : null;
    var response = await _get(client, uri, headers, range: range);
    var status = response.statusCode;
    final hasOriginHeaders = headers.keys.any((key) {
      final name = key.toLowerCase();
      return name == 'referer' || name == 'origin';
    });
    if ((status == 400 || status == 403) && hasOriginHeaders) {
      // Some CDNs reject a mismatched Referer/Origin. Retry without them.
      await _discard(response);
      final retryHeaders = <String, String>{...headers}
        ..removeWhere((key, value) {
          final name = key.toLowerCase();
          return name == 'referer' || name == 'origin';
        });
      response = await _get(client, uri, retryHeaders, range: range);
      status = response.statusCode;
    }
    if ((status == 400 || status == 403) && headers.isNotEmpty) {
      // Last resort: retry with no forwarded browser headers at all.
      await _discard(response);
      response = await _get(client, uri, const {}, range: range);
      status = response.statusCode;
    }
    if (status < 200 || status >= 300) {
      final snippet = await _readSnippet(response, 200);
      await _discard(response);
      throw HttpException(
        'The HLS server returned HTTP $status for '
        '${uri.host}${uri.path}.'
        '${snippet.isEmpty ? '' : ' Server said: $snippet'}',
      );
    }
    final builder = BytesBuilder(copy: false);
    try {
      await for (final chunk in response) {
        builder.add(chunk);
      }
    } catch (error) {
      if (error is HlsCanceled) rethrow;
      throw HttpException('The HLS stream could not be read: $error');
    }
    return builder.takeBytes();
  }

  Future<_HlsPlaylist> _loadPlaylist(
    HttpClient client,
    Uri uri,
    Map<String, String> headers,
  ) async {
    final bytes = await _fetch(client, uri, headers);
    final text = utf8.decode(bytes, allowMalformed: true);
    return _parsePlaylist(text, uri);
  }

  /// Resolves a playlist-relative URI. Relative segment/variant/key URLs often
  /// rely on the manifest query string (signed tokens), which `Uri.resolve`
  /// drops; inherit it when the child has no query of its own.
  Uri _resolveChild(Uri base, String value) {
    final resolved = base.resolve(value);
    if (resolved.hasQuery || !base.hasQuery) return resolved;
    final reference = Uri.tryParse(value.trim());
    if (reference != null && (reference.hasScheme || reference.hasAuthority)) {
      return resolved;
    }
    return resolved.replace(query: base.query);
  }

  _HlsPlaylist _parsePlaylist(String text, Uri baseUri) {
    final variants = <_HlsVariant>[];
    final renditions = <_HlsRendition>[];
    final segments = <_HlsSegment>[];
    Uri? initUri;
    int? initRangeOffset;
    int? initRangeLength;
    Uri? initKeyUri;
    Uint8List? initIv;
    Uri? currentKeyUri;
    Uint8List? currentIv;
    var isLive = true;
    var targetDuration = 0;
    var sequence = 0;
    (int?, int?)? pendingByteRange;
    final lines = const LineSplitter().convert(text);
    for (var index = 0; index < lines.length; index++) {
      final rawLine = lines[index].trim();
      if (rawLine.isEmpty) continue;
      if (rawLine.startsWith('#EXT-X-TARGETDURATION:')) {
        targetDuration =
            int.tryParse(rawLine.split(':').last) ?? targetDuration;
        continue;
      }
      if (rawLine.startsWith('#EXT-X-MEDIA-SEQUENCE:')) {
        sequence = int.tryParse(rawLine.split(':').last) ?? 0;
        continue;
      }
      if (rawLine.startsWith('#EXT-X-ENDLIST')) {
        isLive = false;
        continue;
      }
      if (rawLine.startsWith('#EXT-X-STREAM-INF:')) {
        final attributes =
            _attributes(rawLine.substring(rawLine.indexOf(':') + 1));
        var uriLine = '';
        for (var lookahead = index + 1; lookahead < lines.length; lookahead++) {
          final candidate = lines[lookahead].trim();
          if (candidate.isEmpty) continue;
          if (candidate.startsWith('#')) break;
          uriLine = candidate;
          index = lookahead;
          break;
        }
        if (uriLine.isNotEmpty) {
          final resolution = _resolution(attributes['RESOLUTION']);
          variants.add(
            _HlsVariant(
              uri: _resolveChild(baseUri, uriLine),
              bandwidth: int.tryParse(attributes['BANDWIDTH'] ?? '') ?? 0,
              width: resolution.$1,
              height: resolution.$2,
              codecs: attributes['CODECS'],
              audioGroup: attributes['AUDIO'],
              subtitlesGroup: attributes['SUBTITLES'],
            ),
          );
        }
        continue;
      }
      if (rawLine.startsWith('#EXT-X-MEDIA:')) {
        final attributes =
            _attributes(rawLine.substring(rawLine.indexOf(':') + 1));
        final uriValue = attributes['URI'];
        renditions.add(
          _HlsRendition(
            type: (attributes['TYPE'] ?? '').toUpperCase(),
            groupId: attributes['GROUP-ID'] ?? '',
            name: attributes['NAME'] ?? '',
            isDefault: attributes['DEFAULT'] == 'YES',
            language: attributes['LANGUAGE'],
            uri: uriValue == null || uriValue.isEmpty
                ? null
                : _resolveChild(baseUri, uriValue),
          ),
        );
        continue;
      }
      if (rawLine.startsWith('#EXT-X-KEY:')) {
        final attributes =
            _attributes(rawLine.substring(rawLine.indexOf(':') + 1));
        final method = (attributes['METHOD'] ?? 'NONE').toUpperCase();
        final keyFormat = (attributes['KEYFORMAT'] ?? 'identity').toLowerCase();
        if (method == 'NONE') {
          currentKeyUri = null;
          currentIv = null;
        } else if (method == 'AES-128' && keyFormat == 'identity') {
          final keyValue = attributes['URI'];
          currentKeyUri =
              keyValue == null ? null : _resolveChild(baseUri, keyValue);
          currentIv = _parseIv(attributes['IV']);
        } else {
          throw FormatException(
            'Unsupported HLS encryption method: $method.',
          );
        }
        continue;
      }
      if (rawLine.startsWith('#EXT-X-MAP:')) {
        final attributes =
            _attributes(rawLine.substring(rawLine.indexOf(':') + 1));
        final uriValue = attributes['URI'];
        if (uriValue != null && uriValue.isNotEmpty) {
          initUri = _resolveChild(baseUri, uriValue);
          final range = _parseByteRange(attributes['BYTERANGE']);
          initRangeOffset = range?.$1;
          initRangeLength = range?.$2;
          initKeyUri = currentKeyUri;
          initIv = currentIv;
        }
        continue;
      }
      if (rawLine.startsWith('#EXT-X-BYTERANGE:')) {
        pendingByteRange = _parseByteRange(
          rawLine.substring(rawLine.indexOf(':') + 1),
        );
        continue;
      }
      if (rawLine.startsWith('#')) continue;
      final range = pendingByteRange;
      pendingByteRange = null;
      segments.add(
        _HlsSegment(
          uri: _resolveChild(baseUri, rawLine),
          sequence: sequence + segments.length,
          keyUri: currentKeyUri,
          iv: currentIv,
          byteRangeOffset: range?.$1,
          byteRangeLength: range?.$2,
        ),
      );
    }
    return _HlsPlaylist(
      baseUri: baseUri,
      variants: variants,
      renditions: renditions,
      segments: segments,
      initUri: initUri,
      initByteRangeOffset: initRangeOffset,
      initByteRangeLength: initRangeLength,
      initKeyUri: initKeyUri,
      initIv: initIv,
      isLive: isLive,
      targetDuration: targetDuration,
    );
  }

  (int?, int?)? _parseByteRange(String? value) {
    if (value == null || value.isEmpty) return null;
    final parts = value.split('@');
    final length = int.tryParse(parts.first);
    final offset = parts.length > 1 ? int.tryParse(parts[1]) : null;
    if (length == null) return null;
    return (offset ?? 0, length);
  }

  Uint8List? _parseIv(String? value) {
    if (value == null || value.isEmpty) return null;
    final normalized = value.toLowerCase().replaceFirst('0x', '');
    if (normalized.length > 32) return null;
    final padded = normalized.padLeft(32, '0');
    final bytes = Uint8List(16);
    for (var index = 0; index < 16; index++) {
      bytes[index] =
          int.parse(padded.substring(index * 2, index * 2 + 2), radix: 16);
    }
    return bytes;
  }

  Map<String, String> _attributes(String input) {
    final result = <String, String>{};
    final pattern = RegExp(r'''([A-Z0-9-]+)=("[^"]*"|[^,]*)''');
    for (final match in pattern.allMatches(input)) {
      var value = match.group(2) ?? '';
      if (value.startsWith('"') && value.endsWith('"') && value.length >= 2) {
        value = value.substring(1, value.length - 1);
      }
      result[match.group(1)!] = value;
    }
    return result;
  }

  (int?, int?) _resolution(String? value) {
    if (value == null) return (null, null);
    final parts = value.toLowerCase().split('x');
    if (parts.length != 2) return (null, null);
    return (int.tryParse(parts[0]), int.tryParse(parts[1]));
  }

  Future<HttpClientResponse> _get(
    HttpClient client,
    Uri uri,
    Map<String, String> headers, {
    String? range,
  }) async {
    var current = uri;
    for (var redirects = 0;; redirects++) {
      final request = await client.getUrl(current);
      request.followRedirects = false;
      if (current.origin == uri.origin) {
        headers.forEach((key, value) {
          final name = key.toLowerCase();
          if (name == 'range' ||
              name == 'if-range' ||
              name == 'if-none-match' ||
              name == 'if-modified-since' ||
              name == 'accept-encoding' ||
              name == 'content-length' ||
              name == 'host') {
            return;
          }
          try {
            request.headers.set(key, value);
          } catch (_) {}
        });
      }
      if (range != null) request.headers.set(HttpHeaders.rangeHeader, range);
      final response = await request.close();
      if (!response.isRedirect) return response;
      if (redirects >= 5) {
        await _discard(response);
        throw const HttpException(
            'The HLS playlist redirected too many times.');
      }
      final location = response.headers.value(HttpHeaders.locationHeader);
      await _discard(response);
      if (location == null) throw const HttpException('Invalid HLS redirect.');
      current = current.resolve(location);
      if (!{'http', 'https'}.contains(current.scheme)) {
        throw const HttpException('Unsupported HLS redirect.');
      }
    }
  }

  Future<String> _readSnippet(HttpClientResponse response, int maximum) async {
    final buffer = <int>[];
    try {
      await for (final chunk in response.timeout(const Duration(seconds: 4))) {
        buffer.addAll(chunk.take(maximum - buffer.length));
        if (buffer.length >= maximum) break;
      }
    } catch (_) {}
    return utf8
        .decode(buffer, allowMalformed: true)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<void> _discard(HttpClientResponse response) async {
    try {
      final socket = await response.detachSocket();
      socket.destroy();
    } catch (_) {
      try {
        await response.drain<void>();
      } catch (_) {}
    }
  }

  String _stem(String path) {
    final dot = path.lastIndexOf('.');
    return dot > 0 ? path.substring(0, dot) : path;
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
