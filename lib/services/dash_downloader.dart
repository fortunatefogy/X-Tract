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

class DashRepresentationInfo {
  const DashRepresentationInfo({
    required this.id,
    required this.kind,
    required this.label,
    required this.bandwidth,
    this.width,
    this.height,
    this.mimeType,
  });

  final String id;
  final String kind;
  final String label;
  final int bandwidth;
  final int? width;
  final int? height;
  final String? mimeType;
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
    this.drmProtected = false,
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
  final bool drmProtected;

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
    bool audioOnly = false,
    void Function()? onLiveDetected,
    String? preferredFormatId,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme)) {
      throw const FormatException(
          'Only http and https DASH streams are supported.');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30)
      ..idleTimeout = const Duration(seconds: 30)
      ..userAgent = 'Linky Android';
    ProxyService.applyToClient(client);
    await SecureDnsService.instance.configure(client);
    try {
      final bytes = await _fetch(client, uri, headers);
      final document =
          XmlDocument.parse(utf8.decode(bytes, allowMalformed: true));
      final parsed = _parseMpd(document, uri);
      if (parsed.representations.isEmpty) {
        throw const FormatException('The DASH manifest has no media tracks.');
      }
      final video = _byId(parsed.representations, 'video', preferredFormatId) ??
          _best(parsed.representations, 'video');
      final audio = _best(parsed.representations, 'audio');
      if (video == null && audio == null) {
        throw const FormatException(
            'The DASH manifest has no playable tracks.');
      }
      if ((video?.drmProtected ?? false) || (audio?.drmProtected ?? false)) {
        throw const FormatException(
          'This DASH stream is DRM-protected and cannot be downloaded.',
        );
      }
      final liveRecordable = (video?.segments.isNotEmpty ?? false) ||
          (audio?.segments.isNotEmpty ?? false);
      if (parsed.isLive && liveRecordable) {
        onLiveDetected?.call();
        return await _recordLive(
          client: client,
          uri: uri,
          initial: parsed,
          destination: destination,
          workDirectory: workDirectory,
          headers: headers,
          onProgress: onProgress,
          isCancelled: isCancelled,
          audioOnly: audioOnly,
        );
      }
      final skipVideo = audioOnly && audio != null;
      File? videoFile;
      File? audioFile;
      if (video != null && !skipVideo) {
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
          !skipVideo &&
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
      } else if (skipVideo) {
        audioFile = await _downloadRepresentation(
          client: client,
          representation: audio,
          destination: File('${_stem(destination.path)}.m4a'),
          workDirectory: Directory(
            '${workDirectory.path}${Platform.pathSeparator}audio',
          ),
          headers: headers,
          onProgress: onProgress,
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

  Future<List<DashRepresentationInfo>> listRepresentations({
    required String url,
    Map<String, String> headers = const {},
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme)) return const [];
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..idleTimeout = const Duration(seconds: 20)
      ..userAgent = 'Linky Android';
    ProxyService.applyToClient(client);
    await SecureDnsService.instance.configure(client);
    try {
      final parsed = await _loadParsed(client, uri, headers);
      final representations = parsed.representations
          .where((representation) => representation.kind == 'video')
          .toList()
        ..sort((a, b) {
          final height = (b.height ?? 0).compareTo(a.height ?? 0);
          if (height != 0) return height;
          return b.bandwidth.compareTo(a.bandwidth);
        });
      return [
        for (final representation in representations)
          DashRepresentationInfo(
            id: representation.id,
            kind: representation.kind,
            label: representation.label,
            bandwidth: representation.bandwidth,
            width: representation.width,
            height: representation.height,
            mimeType: representation.mimeType,
          ),
      ];
    } catch (_) {
      return const [];
    } finally {
      client.close(force: true);
    }
  }

  Future<DashDownloadResult> _recordLive({
    required HttpClient client,
    required Uri uri,
    required _ParsedMpd initial,
    required File destination,
    required Directory workDirectory,
    required Map<String, String> headers,
    required void Function(int completed, int total) onProgress,
    bool Function()? isCancelled,
    required bool audioOnly,
  }) async {
    await workDirectory.create(recursive: true);
    final videoInit = File(
      '${workDirectory.path}${Platform.pathSeparator}video-init.mp4',
    );
    final audioInit = File(
      '${workDirectory.path}${Platform.pathSeparator}audio-init.mp4',
    );
    final seen = <String>{};
    var videoIndex = 0;
    var audioIndex = 0;
    var bytes = 0;
    final videoId = _best(initial.representations, 'video')?.id;
    final audioId = _best(initial.representations, 'audio')?.id;
    var warning = initial.isLive ? null : 'The manifest is no longer live.';
    var stopped = false;
    var idlePolls = 0;

    while (true) {
      if (isCancelled?.call() == true) {
        stopped = true;
        break;
      }
      _ParsedMpd current;
      try {
        current = await _loadParsed(client, uri, headers);
      } catch (error) {
        warning = 'Live manifest refresh failed: $error';
        if (await _interruptibleDelay(
            const Duration(seconds: 4), isCancelled)) {
          stopped = true;
          break;
        }
        continue;
      }
      final video = _byId(current.representations, 'video', videoId) ??
          _best(current.representations, 'video');
      final audio = _byId(current.representations, 'audio', audioId) ??
          _best(current.representations, 'audio');
      if ((video?.drmProtected ?? false) || (audio?.drmProtected ?? false)) {
        throw const FormatException(
          'This DASH stream is DRM-protected and cannot be downloaded.',
        );
      }
      final includeAudio = audio != null && !(video?.hasAudio ?? false);
      var newSegments = 0;

      if (!audioOnly || audio == null) {
        if (video?.init != null) {
          final key = 'vi:${video!.init!.url}';
          if (seen.add(key)) {
            try {
              final data = await _fetchWithRetry(
                client,
                video.init!.url,
                headers,
                range: video.init!.range,
                isCancelled: isCancelled,
              );
              await videoInit.writeAsBytes(data, flush: true);
              bytes += data.length;
            } catch (error) {
              warning = 'Live video init segment failed: $error';
            }
          }
        }
        for (final segment in video?.segments ?? const <_DashSegment>[]) {
          if (isCancelled?.call() == true) {
            stopped = true;
            break;
          }
          if (!seen.add('v:${segment.url}')) continue;
          try {
            final data = await _fetchWithRetry(
              client,
              segment.url,
              headers,
              range: segment.range,
              isCancelled: isCancelled,
            );
            await _writeLivePart(workDirectory, 'v', videoIndex++, data);
            bytes += data.length;
            newSegments++;
          } catch (error) {
            warning = 'Live video segment failed: $error';
          }
        }
        if (stopped) break;
      }

      if (audio != null && includeAudio) {
        if (audio.init != null) {
          final key = 'ai:${audio.init!.url}';
          if (seen.add(key)) {
            try {
              final data = await _fetchWithRetry(
                client,
                audio.init!.url,
                headers,
                range: audio.init!.range,
                isCancelled: isCancelled,
              );
              await audioInit.writeAsBytes(data, flush: true);
              bytes += data.length;
            } catch (error) {
              warning = 'Live audio init segment failed: $error';
            }
          }
        }
        for (final segment in audio.segments) {
          if (isCancelled?.call() == true) {
            stopped = true;
            break;
          }
          if (!seen.add('a:${segment.url}')) continue;
          try {
            final data = await _fetchWithRetry(
              client,
              segment.url,
              headers,
              range: segment.range,
              isCancelled: isCancelled,
            );
            await _writeLivePart(workDirectory, 'a', audioIndex++, data);
            bytes += data.length;
            newSegments++;
          } catch (error) {
            warning = 'Live audio segment failed: $error';
          }
        }
        if (stopped) break;
      }

      onProgress(videoIndex + audioIndex, 0);
      if (!current.isLive) break;
      if (newSegments == 0) {
        idlePolls++;
      } else {
        idlePolls = 0;
      }
      if (idlePolls > 900) {
        warning ??= 'Stopped after a long period without new segments.';
        break;
      }
      if (bytes > 8 * 1024 * 1024 * 1024 || videoIndex + audioIndex > 20000) {
        warning ??= 'Live recording reached the size limit.';
        break;
      }
      final update = current.minimumUpdatePeriod;
      final delayMs =
          update == null ? 4000 : (update * 1000).clamp(1000, 10000).toInt();
      if (await _interruptibleDelay(
        Duration(milliseconds: delayMs),
        isCancelled,
      )) {
        stopped = true;
        break;
      }
    }

    if (videoIndex == 0 && audioIndex == 0) {
      throw const FormatException(
        'No live segments were captured before the stream stopped.',
      );
    }
    final merged = await _mergeLiveParts(
      workDirectory: workDirectory,
      destination: destination,
      videoInit: videoInit.existsSync() ? videoInit : null,
      audioInit: audioInit.existsSync() ? audioInit : null,
      includeVideo: !audioOnly || audioIndex == 0,
    );
    try {
      await workDirectory.delete(recursive: true);
    } catch (_) {}
    return DashDownloadResult(
      file: merged.$1,
      isLive: true,
      label: audioOnly
          ? 'Audio'
          : (_byId(initial.representations, 'video', videoId)?.label ?? 'DASH'),
      warning: warning ??
          merged.$2 ??
          (stopped
              ? 'Live recording stopped; saved the captured segments.'
              : null),
    );
  }

  Future<_ParsedMpd> _loadParsed(
    HttpClient client,
    Uri uri,
    Map<String, String> headers,
  ) async {
    final bytes = await _fetch(client, uri, headers);
    final document = XmlDocument.parse(
      utf8.decode(bytes, allowMalformed: true),
    );
    return _parseMpd(document, uri);
  }

  _DashRepresentation? _byId(
    List<_DashRepresentation> representations,
    String kind,
    String? id,
  ) {
    if (id == null) return null;
    for (final representation in representations) {
      if (representation.kind == kind && representation.id == id) {
        return representation;
      }
    }
    return null;
  }

  Future<Uint8List> _fetchWithRetry(
    HttpClient client,
    Uri uri,
    Map<String, String> headers, {
    (int, int)? range,
    bool Function()? isCancelled,
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= retries; attempt++) {
      if (isCancelled?.call() == true) throw const DashCanceled();
      try {
        return await _fetch(client, uri, headers, range: range);
      } catch (error) {
        if (error is DashCanceled) rethrow;
        lastError = error;
        if (attempt < retries) {
          await Future<void>.delayed(
            Duration(milliseconds: 500 * attempt),
          );
        }
      }
    }
    throw HttpException(
      'The DASH segment could not be downloaded after $retries attempts: '
      '$lastError',
    );
  }

  Future<void> _writeLivePart(
    Directory workDirectory,
    String prefix,
    int index,
    Uint8List data,
  ) async {
    final file = File(
      '${workDirectory.path}${Platform.pathSeparator}live-$prefix-'
      '${index.toString().padLeft(6, '0')}.m4s',
    );
    await file.writeAsBytes(data, flush: true);
  }

  List<File> _liveParts(Directory directory, String prefix) {
    final files = <File>[];
    try {
      for (final entity in directory.listSync()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (name.startsWith('live-$prefix-') && name.endsWith('.m4s')) {
          files.add(entity);
        }
      }
    } catch (_) {}
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  Future<void> _concatFiles(List<File> inputs, File output) async {
    final sink = output.openWrite();
    try {
      for (final input in inputs) {
        if (await input.exists()) await sink.addStream(input.openRead());
      }
      await sink.flush();
      await sink.close();
    } catch (_) {
      try {
        await sink.close();
      } catch (_) {}
      rethrow;
    }
  }

  Future<bool> _interruptibleDelay(
    Duration duration,
    bool Function()? isCancelled,
  ) async {
    final end = DateTime.now().add(duration);
    while (DateTime.now().isBefore(end)) {
      if (isCancelled?.call() == true) return true;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return isCancelled?.call() == true;
  }

  Future<(File, String?)> _mergeLiveParts({
    required Directory workDirectory,
    required File destination,
    required File? videoInit,
    required File? audioInit,
    required bool includeVideo,
  }) async {
    final videoParts = _liveParts(workDirectory, 'v');
    final audioParts = _liveParts(workDirectory, 'a');
    File? videoFile;
    File? audioFile;
    String? warning;

    if (includeVideo && videoParts.isNotEmpty) {
      videoFile = File(
        '${workDirectory.path}${Platform.pathSeparator}video.bin',
      );
      await _concatFiles([
        if (videoInit != null) videoInit,
        ...videoParts,
      ], videoFile);
    }
    if (audioParts.isNotEmpty) {
      audioFile = File(
        '${workDirectory.path}${Platform.pathSeparator}audio.bin',
      );
      await _concatFiles([
        if (audioInit != null) audioInit,
        ...audioParts,
      ], audioFile);
    }
    if (videoFile == null && audioFile == null) {
      throw const FormatException('No live segments were captured.');
    }

    if (videoFile != null && audioFile != null) {
      final muxedPath = '${_stem(destination.path)}.mp4';
      final muxed = await DeviceResources.instance
          .muxMedia(videoFile.path, audioFile.path, muxedPath);
      if (muxed != null && await File(muxed).exists()) {
        return (File(muxed), null);
      }
      warning =
          'The separate live audio track could not be merged; saved the video track only.';
    }

    final source = videoFile ?? audioFile!;
    final target = File(
      '${_stem(destination.path)}.${videoFile != null ? 'mp4' : 'm4a'}',
    );
    await target.parent.create(recursive: true);
    await _deleteQuietly(target);
    await source.rename(target.path);
    return (target, warning);
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
      final periodDuration =
          _parseIsoDuration(period.getAttribute('duration')) ??
              presentationDuration;
      final liveTiming = _LiveTiming(
        availabilityStartTime: DateTime.tryParse(
          root.getAttribute('availabilityStartTime') ?? '',
        ),
        publishTime: DateTime.tryParse(root.getAttribute('publishTime') ?? ''),
        timeShiftBufferDepth:
            _parseIsoDuration(root.getAttribute('timeShiftBufferDepth')),
        suggestedPresentationDelay:
            _parseIsoDuration(root.getAttribute('suggestedPresentationDelay')),
        periodStart: _parseIsoDuration(period.getAttribute('start')) ?? 0,
      );
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
                int.tryParse(representation.getAttribute('bandwidth') ?? '') ??
                    0,
            id: representation.getAttribute('id') ?? '',
            width: int.tryParse(representation.getAttribute('width') ?? ''),
            height: int.tryParse(representation.getAttribute('height') ?? ''),
            codecs: representation.getAttribute('codecs'),
            periodDuration: periodDuration,
            isLive: isLive,
            liveTiming: liveTiming,
            drmProtected: _hasDrm(representation) ||
                _hasDrm(adaptation) ||
                _hasDrm(period),
          );
          if (parsed != null) representations.add(parsed);
        }
      }
      if (representations.isNotEmpty) break;
    }
    return _ParsedMpd(
      representations,
      isLive: isLive,
      minimumUpdatePeriod: _parseIsoDuration(
        root.getAttribute('minimumUpdatePeriod'),
      ),
    );
  }

  bool _hasDrm(XmlElement element) {
    for (final child in element.children.whereType<XmlElement>()) {
      if (child.name.local == 'ContentProtection') return true;
    }
    return false;
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
    required _LiveTiming liveTiming,
    required bool drmProtected,
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
        liveTiming: liveTiming,
        drmProtected: drmProtected,
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
        drmProtected: drmProtected,
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
        drmProtected: drmProtected,
      );
    }
    if (baseUrl != mpdUri &&
        (mimeType.startsWith('video/') || mimeType.startsWith('audio/'))) {
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
        drmProtected: drmProtected,
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
    required _LiveTiming liveTiming,
    required bool drmProtected,
  }) {
    final mediaTemplate = template.getAttribute('media');
    if (mediaTemplate == null || mediaTemplate.isEmpty) return null;
    final timescale =
        int.tryParse(template.getAttribute('timescale') ?? '') ?? 1;
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
    } else if (duration > 0 && isLive) {
      final availability = liveTiming.availabilityStartTime;
      final segmentDuration = duration / timescale;
      if (availability != null && segmentDuration > 0) {
        final reference = liveTiming.publishTime ?? DateTime.now().toUtc();
        final elapsed =
            reference.difference(availability).inMilliseconds / 1000.0 -
                liveTiming.periodStart;
        final delay =
            liveTiming.suggestedPresentationDelay ?? segmentDuration * 2;
        final window = liveTiming.timeShiftBufferDepth == null
            ? 10
            : (liveTiming.timeShiftBufferDepth! / segmentDuration).ceil();
        final count = window.clamp(1, 30);
        final lastIndex = ((elapsed - delay) / segmentDuration).floor() - 1;
        for (var offset = count - 1; offset >= 0; offset--) {
          final index = lastIndex - offset;
          if (index < 0) continue;
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
      drmProtected: drmProtected,
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
    required bool drmProtected,
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
      drmProtected: drmProtected,
    );
  }

  String _expand(
      String template, String id, int bandwidth, int number, int time) {
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

    for (var index = 0; index < representation.segments.length; index++) {
      final existing = File(
        '${workDirectory.path}${Platform.pathSeparator}seg-$index.m4s',
      );
      if (existing.existsSync() && existing.lengthSync() > 0) {
        completed.add(index);
      } else {
        completed.remove(index);
      }
    }
    var next = 0;
    onProgress(completed.length, representation.segments.length);
    final workerCount = min(workers, max(1, representation.segments.length));
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
      throw HttpException(
          'The DASH server returned HTTP ${response.statusCode}.');
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
        throw const HttpException(
            'The DASH manifest redirected too many times.');
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

class _LiveTiming {
  const _LiveTiming({
    this.availabilityStartTime,
    this.publishTime,
    this.timeShiftBufferDepth,
    this.suggestedPresentationDelay,
    this.periodStart = 0,
  });

  final DateTime? availabilityStartTime;
  final DateTime? publishTime;
  final double? timeShiftBufferDepth;
  final double? suggestedPresentationDelay;
  final double periodStart;
}

class _ParsedMpd {
  const _ParsedMpd(
    this.representations, {
    this.isLive = false,
    this.minimumUpdatePeriod,
  });

  final List<_DashRepresentation> representations;
  final bool isLive;
  final double? minimumUpdatePeriod;
}
