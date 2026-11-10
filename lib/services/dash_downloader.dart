import 'dart:convert';
import 'dart:io';

import 'proxy_service.dart';
import 'secure_dns_service.dart';
import 'dart:math';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import 'device_resources.dart';

class DashDownloadResult {
  const DashDownloadResult({
    required this.file,
    required this.isLive,
    required this.label,
    this.warning,
  });

  final File file;
  final bool isLive;
  final String label;
  final String? warning;
}

class DashCanceled implements Exception {
  const DashCanceled();
}

class _DashInit {
  const _DashInit({required this.url, this.range});

  final Uri url;
  final (int, int)? range;
}

class _DashSegment {
  const _DashSegment({required this.url, this.range});

  final Uri url;
  final (int, int)? range;
}

class _DashRepresentation {
  const _DashRepresentation({
    required this.id,
    required this.kind,
    required this.mimeType,
    required this.bandwidth,
    required this.segments,
    required this.isLive,
    this.width,
    this.height,
    this.codecs,
    this.init,
    this.singleFile,
  });

  final String id;
  final String kind;
  final String mimeType;
  final int bandwidth;
  final int? width;
  final int? height;
  final String? codecs;
  final _DashInit? init;
  final List<_DashSegment> segments;
  final Uri? singleFile;
  final bool isLive;

  bool get hasAudio {
    final value = codecs?.toLowerCase() ?? '';
    return RegExp(r'mp4a|ac-3|ec-3|opus|vorbis|flac|aac').hasMatch(value);
  }

  String get label {
    if (kind == 'video' && height != null && height! > 0) {
      return '${height}p';
    }
    if (bandwidth > 0) return '${(bandwidth / 1000).round()} kbps';
    return id;
  }
}

class DashDownloader {
  DashDownloader({
    this.workers = 4,
    this.retries = 3,
  });

  final int workers;
  final int retries;

  Future<DashDownloadResult> download({
    required String url,
    required File destination,
    required Directory workDirectory,
    Map<String, String> headers = const {},
    required void Function(int completed, int total) onProgress,
    bool Function()? isCancelled,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme)) {
      throw const FormatException('Only http and https DASH streams are supported.');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30)
      ..idleTimeout = const Duration(seconds: 30)
      ..userAgent = 'Linky Android';
    ProxyService.applyToClient(client);
    await SecureDnsService.instance.configure(client);
    try {
      final bytes = await _fetch(client, uri, headers);
      final document = XmlDocument.parse(utf8.decode(bytes, allowMalformed: true));
      final parsed = _parseMpd(document, uri);
      if (parsed.representations.isEmpty) {
        throw const FormatException('The DASH manifest has no media tracks.');
      }
      final video = _best(parsed.representations, 'video');
      final audio = _best(parsed.representations, 'audio');
      if (video == null && audio == null) {
        throw const FormatException('The DASH manifest has no playable tracks.');
      }
      File? videoFile;
      File? audioFile;
      if (video != null) {
        videoFile = await _downloadRepresentation(
          client: client,
          representation: video,
          destination: File('${_stem(destination.path)}.mp4'),
          workDirectory: Directory(
            '${workDirectory.path}${Platform.pathSeparator}video',
          ),
          headers: headers,
          onProgress: onProgress,
          isCancelled: isCancelled,
        );
      }
      if (audio != null &&
          !(video != null && video.hasAudio) &&
          video?.kind != 'audio') {
        audioFile = await _downloadRepresentation(
          client: client,
          representation: audio,
          destination: File('${_stem(destination.path)}.m4a'),
          workDirectory: Directory(
            '${workDirectory.path}${Platform.pathSeparator}audio',
          ),
          headers: headers,
          onProgress: (_, __) {},
          isCancelled: isCancelled,
        );
      }
      File output = videoFile ?? audioFile!;
      String? warning;
      if (videoFile != null && audioFile != null) {
        final muxedPath = '${_stem(destination.path)}.mp4';
        final muxed = await DeviceResources.instance.muxMedia(
          videoFile.path,
          audioFile.path,
          muxedPath,
        );
        if (muxed != null && await File(muxed).exists()) {
          output = File(muxed);
          await _deleteQuietly(videoFile);
          await _deleteQuietly(audioFile);
        } else {
          warning =
              'The separate audio track could not be merged; saved the video track only.';
          await _deleteQuietly(audioFile);
        }
      }
      final chosen = video ?? audio!;
      return DashDownloadResult(
        file: output,
        isLive: chosen.isLive,
        label: chosen.label,
        warning: warning,
      );
    } finally {
      client.close(force: true);
    }
  }

  _DashRepresentation? _best(
    List<_DashRepresentation> representations,
    String kind,
  ) {
    final matches =
        representations.where((representation) => representation.kind == kind);
    if (matches.isEmpty) return null;
    final sorted = List<_DashRepresentation>.from(matches)
      ..sort((a, b) {
        if (kind == 'video') {
          final height = (b.height ?? 0).compareTo(a.height ?? 0);
          if (height != 0) return height;
        }
        return b.bandwidth.compareTo(a.bandwidth);
      });
    return sorted.first;
  }

  _ParsedMpd _parseMpd(XmlDocument document, Uri mpdUri) {
    final root = document.rootElement;
    final isLive =
        (root.getAttribute('type') ?? 'static').toLowerCase() == 'dynamic';
    final presentationDuration =
        _parseIsoDuration(root.getAttribute('mediaPresentationDuration'));
    final rootBase = _applyBaseUrl(mpdUri, root);
    final representations = <_DashRepresentation>[];
    final periods = _children(root, 'Period');
    for (final period in periods.isEmpty ? [root] : periods) {
      final periodBase = _applyBaseUrl(rootBase, period);
      final periodDuration = _parseIsoDuration(period.getAttribute('duration')) ??
          presentationDuration;
      for (final adaptation in _children(period, 'AdaptationSet')) {
        final adaptationBase = _applyBaseUrl(periodBase, adaptation);
        final adaptationMime =
            adaptation.getAttribute('mimeType')?.toLowerCase() ?? '';
        final declaredType =
            adaptation.getAttribute('contentType')?.toLowerCase();
        for (final representation in _children(adaptation, 'Representation')) {
          final baseUrl = _applyBaseUrl(adaptationBase, representation);
          final mime = representation.getAttribute('mimeType')?.toLowerCase() ??
              adaptationMime;
          final kind = declaredType == 'audio' || mime.startsWith('audio/')
              ? 'audio'
              : 'video';
          final parsed = _segmentsFor(
            representation: representation,
            adaptation: adaptation,
            period: period,
            baseUrl: baseUrl,
            mpdUri: mpdUri,
            kind: kind,
            mimeType: mime,
            bandwidth:
                int.tryParse(representation.getAttribute('bandwidth') ?? '') ?? 0,
            id: representation.getAttribute('id') ?? '',
            width: int.tryParse(representation.getAttribute('width') ?? ''),
            height: int.tryParse(representation.getAttribute('height') ?? ''),
            codecs: representation.getAttribute('codecs'),
            periodDuration: periodDuration,
            isLive: isLive,
          );
          if (parsed != null) representations.add(parsed);
        }
      }
      if (representations.isNotEmpty) break;
    }
    return _ParsedMpd(representations);
  }

  _DashRepresentation? _segmentsFor({
    required XmlElement representation,
    required XmlElement adaptation,
    required XmlElement period,
    required Uri baseUrl,
    required Uri mpdUri,
    required String kind,
    required String mimeType,
    required int bandwidth,
    required String id,
    required int? width,
    required int? height,
    required String? codecs,
    required double? periodDuration,
    required bool isLive,
  }) {
    final template = _firstChild(representation, 'SegmentTemplate') ??
        _firstChild(adaptation, 'SegmentTemplate') ??
        _firstChild(period, 'SegmentTemplate');
    final segmentList = _firstChild(representation, 'SegmentList') ??
        _firstChild(adaptation, 'SegmentList') ??
        _firstChild(period, 'SegmentList');
    final segmentBase = _firstChild(representation, 'SegmentBase') ??
        _firstChild(adaptation, 'SegmentBase');
    if (template != null) {
      return _fromTemplate(
        template: template,
        baseUrl: baseUrl,
        kind: kind,
        mimeType: mimeType,
        bandwidth: bandwidth,
        id: id,
        width: width,
        height: height,
        codecs: codecs,
        periodDuration: periodDuration,
        isLive: isLive,
      );
    }
    if (segmentList != null) {
      return _fromSegmentList(
        segmentList: segmentList,
        baseUrl: baseUrl,
        kind: kind,
        mimeType: mimeType,
        bandwidth: bandwidth,
        id: id,
        width: width,
        height: height,
        codecs: codecs,
        isLive: isLive,
      );
    }
    if (segmentBase != null) {
      if (baseUrl == mpdUri) return null;
      return _DashRepresentation(
        id: id,
        kind: kind,
        mimeType: mimeType,
        bandwidth: bandwidth,
        width: width,
        height: height,
        codecs: codecs,
        segments: const [],
        singleFile: baseUrl,
        isLive: isLive,
      );
    }
    if (baseUrl != mpdUri && (mimeType.startsWith('video/') || mimeType.startsWith('audio/'))) {
      return _DashRepresentation(
        id: id,
        kind: kind,
        mimeType: mimeType,
        bandwidth: bandwidth,
        width: width,
        height: height,
        codecs: codecs,
        segments: const [],
        singleFile: baseUrl,
        isLive: isLive,
      );
    }
    return null;
  }

  _DashRepresentation? _fromTemplate({
    required XmlElement template,
    required Uri baseUrl,
    required String kind,
    required String mimeType,
    required int bandwidth,
    required String id,
    required int? width,
    required int? height,
    required String? codecs,
    required double? periodDuration,
    required bool isLive,
  }) {
    final mediaTemplate = template.getAttribute('media');
    if (mediaTemplate == null || mediaTemplate.isEmpty) return null;
    final timescale = int.tryParse(template.getAttribute('timescale') ?? '') ?? 1;
    final startNumber =
        int.tryParse(template.getAttribute('startNumber') ?? '') ?? 1;
    final duration = int.tryParse(template.getAttribute('duration') ?? '') ?? 0;
    final initTemplate = template.getAttribute('initialization');
    final init = initTemplate == null || initTemplate.isEmpty
        ? null
        : _DashInit(
            url: baseUrl.resolve(
              _expand(initTemplate, id, bandwidth, startNumber, 0),
            ),
          );
    final segments = <_DashSegment>[];
    final timeline = _firstChild(template, 'SegmentTimeline');
    if (timeline != null) {
      final entries = _children(timeline, 'S');
      var time = 0;
      var number = startNumber;
      for (var index = 0; index < entries.length; index++) {
        final entry = entries[index];
        final start = int.tryParse(entry.getAttribute('t') ?? '');
        final step = int.tryParse(entry.getAttribute('d') ?? '') ?? 0;
        if (step <= 0) continue;
        if (start != null) time = start;
        var repeat = int.tryParse(entry.getAttribute('r') ?? '') ?? 0;
        if (repeat < 0) {
          final next = index + 1 < entries.length
              ? int.tryParse(entries[index + 1].getAttribute('t') ?? '')
              : null;
          final end = next ??
              (periodDuration != null
                  ? (periodDuration * timescale).round()
                  : time + step);
          repeat = max(0, ((end - time) / step).ceil() - 1);
        }
        for (var count = 0; count <= repeat; count++) {
          segments.add(
            _DashSegment(
              url: baseUrl.resolve(
                _expand(mediaTemplate, id, bandwidth, number, time),
              ),
            ),
          );
          number++;
          time += step;
          if (segments.length > 20000) break;
        }
      }
    } else if (duration > 0 && periodDuration != null) {
      final count = (periodDuration * timescale / duration).ceil();
      for (var index = 0; index < count; index++) {
        final number = startNumber + index;
        final time = index * duration;
        segments.add(
          _DashSegment(
            url: baseUrl.resolve(
              _expand(mediaTemplate, id, bandwidth, number, time),
            ),
          ),
        );
      }
    }
    if (segments.isEmpty) return null;
    return _DashRepresentation(
      id: id,
      kind: kind,
      mimeType: mimeType,
      bandwidth: bandwidth,
      width: width,
      height: height,
      codecs: codecs,
      init: init,
      segments: segments,
      isLive: isLive,
    );
  }

  _DashRepresentation? _fromSegmentList({
    required XmlElement segmentList,
    required Uri baseUrl,
    required String kind,
    required String mimeType,
    required int bandwidth,
    required String id,
    required int? width,
    required int? height,
    required String? codecs,
    required bool isLive,
  }) {
    final initialization = _firstChild(segmentList, 'Initialization');
    final initSource = initialization?.getAttribute('sourceURL');
    final initRange = _parseRange(initialization?.getAttribute('range'));
    final init = initialization == null
        ? null
        : _DashInit(
            url: initSource == null || initSource.isEmpty
                ? baseUrl
                : baseUrl.resolve(initSource),
            range: initRange,
          );
    final segments = <_DashSegment>[
      for (final entry in _children(segmentList, 'SegmentURL'))
        if (entry.getAttribute('media') != null &&
            entry.getAttribute('media')!.isNotEmpty)
          _DashSegment(
            url: baseUrl.resolve(entry.getAttribute('media')!),
            range: _parseRange(entry.getAttribute('mediaRange')),
          ),
    ];
    if (segments.isEmpty) return null;
    return _DashRepresentation(
      id: id,
      kind: kind,
      mimeType: mimeType,
      bandwidth: bandwidth,
      width: width,
      height: height,
      codecs: codecs,
      init: init,
      segments: segments,
      isLive: isLive,
    );
  }

  String _expand(String template, String id, int bandwidth, int number, int time) {
    var value = template
        .replaceAll(r'$RepresentationID$', id)
        .replaceAll(r'$Bandwidth$', '$bandwidth');
    value = value.replaceAllMapped(
      RegExp(r'\$(Number|Time)(?:%0(\d+)d)?\$'),
      (match) {
        final raw = match.group(1) == 'Number' ? number : time;
        final width = int.tryParse(match.group(2) ?? '');
        return width == null ? '$raw' : raw.toString().padLeft(width, '0');
      },
    );
    return value;
  }

  (int, int)? _parseRange(String? value) {
    if (value == null || value.isEmpty) return null;
    final parts = value.split('-');
    if (parts.length != 2) return null;
    final start = int.tryParse(parts[0]);
    final end = int.tryParse(parts[1]);
    if (start == null || end == null || end < start) return null;
    return (start, end);
  }

  double? _parseIsoDuration(String? value) {
    if (value == null || value.isEmpty) return null;
    final match = RegExp(
      r'^P(?:(\d+(?:\.\d+)?)D)?(?:T(?:(\d+(?:\.\d+)?)H)?(?:(\d+(?:\.\d+)?)M)?(?:(\d+(?:\.\d+)?)S)?)?$',
    ).firstMatch(value);
    if (match == null) return null;
    final days = double.tryParse(match.group(1) ?? '') ?? 0;
    final hours = double.tryParse(match.group(2) ?? '') ?? 0;
    final minutes = double.tryParse(match.group(3) ?? '') ?? 0;
    final seconds = double.tryParse(match.group(4) ?? '') ?? 0;
    return days * 86400 + hours * 3600 + minutes * 60 + seconds;
  }

  Future<File> _downloadRepresentation({
    required HttpClient client,
    required _DashRepresentation representation,
    required File destination,
    required Directory workDirectory,
    required Map<String, String> headers,
    required void Function(int completed, int total) onProgress,
    bool Function()? isCancelled,
  }) async {
    if (representation.singleFile != null) {
      await destination.parent.create(recursive: true);
      final temporary = File('${destination.path}.linky-tmp');
      final response = await _get(client, representation.singleFile!, headers);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await _discard(response);
        throw HttpException(
          'The DASH server returned HTTP ${response.statusCode}.',
        );
      }
      final sink = temporary.openWrite();
      try {
        await for (final chunk in response) {
          if (isCancelled?.call() == true) throw const DashCanceled();
          sink.add(chunk);
        }
        await sink.flush();
        await sink.close();
        if (await destination.exists()) await destination.delete();
        await temporary.rename(destination.path);
      } catch (_) {
        try {
          await sink.close();
        } catch (_) {}
        await _deleteQuietly(temporary);
        rethrow;
      }
      return destination;
    }

    await workDirectory.create(recursive: true);
    final completedFile = File(
      '${workDirectory.path}${Platform.pathSeparator}completed.json',
    );
    final completed = <int>{};
    if (await completedFile.exists()) {
      try {
        final raw = jsonDecode(await completedFile.readAsString());
        if (raw is List) {
          completed.addAll(raw.whereType<num>().map((value) => value.toInt()));
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
        File('${workDirectory.path}${Platform.pathSeparator}init.mp4');
    if (representation.init != null && !await initFile.exists()) {
      final bytes = await _fetch(
        client,
        representation.init!.url,
        headers,
        range: representation.init!.range,
      );
      await initFile.writeAsBytes(bytes, flush: true);
    }

    var next = 0;
    onProgress(completed.length, representation.segments.length);
    final workerCount =
        min(workers, max(1, representation.segments.length));
    await Future.wait(
      List.generate(workerCount, (_) async {
        while (true) {
          if (isCancelled?.call() == true) throw const DashCanceled();
          final index = next++;
          if (index >= representation.segments.length) return;
          if (completed.contains(index)) continue;
          final segment = representation.segments[index];
          var attempts = 0;
          while (true) {
            try {
              final bytes = await _fetch(
                client,
                segment.url,
                headers,
                range: segment.range,
              );
              await File(
                '${workDirectory.path}${Platform.pathSeparator}seg-$index.m4s',
              ).writeAsBytes(bytes, flush: true);
              break;
            } catch (error) {
              if (error is DashCanceled) rethrow;
              attempts++;
              if (attempts > retries) rethrow;
              await Future<void>.delayed(
                Duration(milliseconds: 250 * attempts),
              );
            }
          }
          completed.add(index);
          await saveCompleted();
          onProgress(completed.length, representation.segments.length);
        }
      }),
    );

    await destination.parent.create(recursive: true);
    final temporary = File('${destination.path}.linky-tmp');
    final sink = temporary.openWrite();
    try {
      if (await initFile.exists()) {
        await sink.addStream(initFile.openRead());
      }
      for (var index = 0; index < representation.segments.length; index++) {
        final segmentFile = File(
          '${workDirectory.path}${Platform.pathSeparator}seg-$index.m4s',
        );
        if (!await segmentFile.exists()) {
          throw HttpException('The DASH segment $index is missing.');
        }
        await sink.addStream(segmentFile.openRead());
      }
      await sink.flush();
      await sink.close();
      if (await destination.exists()) await destination.delete();
      await temporary.rename(destination.path);
    } catch (_) {
      try {
        await sink.close();
      } catch (_) {}
      await _deleteQuietly(temporary);
      rethrow;
    }
    try {
      await workDirectory.delete(recursive: true);
    } catch (_) {}
    return destination;
  }

  Future<Uint8List> _fetch(
    HttpClient client,
    Uri uri,
    Map<String, String> headers, {
    (int, int)? range,
  }) async {
    final response = await _get(
      client,
      uri,
      headers,
      range: range == null ? null : 'bytes=${range.$1}-${range.$2}',
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await _discard(response);
      throw HttpException('The DASH server returned HTTP ${response.statusCode}.');
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    return builder.takeBytes();
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
        headers.forEach(request.headers.set);
      }
      if (range != null) request.headers.set(HttpHeaders.rangeHeader, range);
      final response = await request.close();
      if (!response.isRedirect) return response;
      if (redirects >= 5) {
        await _discard(response);
        throw const HttpException('The DASH manifest redirected too many times.');
      }
      final location = response.headers.value(HttpHeaders.locationHeader);
      await _discard(response);
      if (location == null) throw const HttpException('Invalid DASH redirect.');
      current = current.resolve(location);
      if (!{'http', 'https'}.contains(current.scheme)) {
        throw const HttpException('Unsupported DASH redirect.');
      }
    }
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

  Uri _applyBaseUrl(Uri base, XmlElement element) {
    final node = _firstChild(element, 'BaseURL');
    final value = node?.innerText.trim();
    if (value == null || value.isEmpty) return base;
    return base.resolve(value);
  }

  XmlElement? _firstChild(XmlElement parent, String name) {
    for (final child in parent.children.whereType<XmlElement>()) {
      if (child.name.local == name) return child;
    }
    return null;
  }

  List<XmlElement> _children(XmlElement parent, String name) => [
        for (final child in parent.children.whereType<XmlElement>())
          if (child.name.local == name) child,
      ];

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

class _ParsedMpd {
  const _ParsedMpd(this.representations);

  final List<_DashRepresentation> representations;
}

