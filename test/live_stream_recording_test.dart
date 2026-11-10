import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:linky/services/dash_downloader.dart';
import 'package:linky/services/hls_downloader.dart';

void main() {
  test('records a live HLS playlist and saves captured segments', () async {
    var playlistRequests = 0;
    final watch = Stopwatch()..start();
    final segments = <List<int>>[
      [1, 2],
      [3, 4],
      [5, 6],
    ];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final base = 'http://127.0.0.1:${server.port}';
    server.listen((request) {
      final path = request.uri.path;
      if (path == '/live.m3u8') {
        playlistRequests++;
        final visible = segments.take(playlistRequests).toList();
        final body = StringBuffer()
          ..writeln('#EXTM3U')
          ..writeln('#EXT-X-VERSION:3')
          ..writeln('#EXT-X-TARGETDURATION:1')
          ..writeln('#EXT-X-MEDIA-SEQUENCE:0');
        for (var index = 0; index < visible.length; index++) {
          body.writeln('#EXTINF:1.0,');
          body.writeln('/seg$index.ts');
        }
        request.response
          ..statusCode = 200
          ..headers.set('content-type', 'application/vnd.apple.mpegurl')
          ..write(body.toString());
      } else if (path.startsWith('/seg')) {
        final index = int.tryParse(
          RegExp(r'seg(\d+)').firstMatch(path)?.group(1) ?? '',
        );
        request.response
          ..statusCode = 200
          ..add(index != null && index < segments.length
              ? segments[index]
              : const <int>[]);
      } else {
        request.response.statusCode = 404;
      }
      request.response.close();
    });
    final directory = await Directory.systemTemp.createTemp('linky-hls-live');
    addTearDown(() async {
      await server.close(force: true);
      await directory.delete(recursive: true);
    });

    final result = await HlsDownloader(workers: 2).download(
      url: '$base/live.m3u8',
      destination: File('${directory.path}/recording.mp4'),
      workDirectory: Directory('${directory.path}/work'),
      onProgress: (_, __) {},
      isCancelled: () =>
          playlistRequests >= 4 || watch.elapsed > const Duration(seconds: 10),
    );

    expect(result.isLive, isTrue);
    expect(await result.file.exists(), isTrue);
    final bytes = await result.file.readAsBytes();
    expect(bytes, [1, 2, 3, 4, 5, 6]);
  });

  test('records a live DASH manifest with a segment timeline', () async {
    var manifestRequests = 0;
    final watch = Stopwatch()..start();
    final init = [9, 9];
    final segments = <List<int>>[
      [1],
      [2],
      [3],
    ];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final base = 'http://127.0.0.1:${server.port}';
    server.listen((request) {
      final path = request.uri.path;
      if (path == '/live.mpd') {
        manifestRequests++;
        request.response
          ..statusCode = 200
          ..headers.set('content-type', 'application/dash+xml')
          ..write('''<?xml version="1.0"?>
<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" type="dynamic"
     minimumUpdatePeriod="PT1S" availabilityStartTime="2026-01-01T00:00:00Z">
  <Period>
    <AdaptationSet mimeType="video/mp4" contentType="video">
      <Representation id="v" bandwidth="1000" width="1280" height="720" codecs="avc1.4d401f">
        <SegmentTemplate timescale="1000" startNumber="1"
            initialization="init.mp4"
            media="seg-\$Number\$.m4s">
          <SegmentTimeline>
            <S t="0" d="1000"/>
            <S d="1000"/>
            <S d="1000"/>
          </SegmentTimeline>
        </SegmentTemplate>
      </Representation>
    </AdaptationSet>
  </Period>
</MPD>
''');
      } else if (path == '/init.mp4') {
        request.response
          ..statusCode = 200
          ..add(init);
      } else if (path.startsWith('/seg-')) {
        final index = int.tryParse(
          RegExp(r'seg-(\d+)').firstMatch(path)?.group(1) ?? '',
        );
        if (index == null || index < 1 || index > segments.length) {
          request.response.statusCode = 404;
        } else {
          request.response
            ..statusCode = 200
            ..add(segments[index - 1]);
        }
      } else {
        request.response.statusCode = 404;
      }
      request.response.close();
    });
    final directory = await Directory.systemTemp.createTemp('linky-dash-live');
    addTearDown(() async {
      await server.close(force: true);
      await directory.delete(recursive: true);
    });

    final result = await DashDownloader(workers: 2).download(
      url: '$base/live.mpd',
      destination: File('${directory.path}/recording.mp4'),
      workDirectory: Directory('${directory.path}/work'),
      onProgress: (_, __) {},
      isCancelled: () =>
          manifestRequests >= 3 || watch.elapsed > const Duration(seconds: 10),
    );

    expect(result.isLive, isTrue);
    expect(await result.file.exists(), isTrue);
    final bytes = await result.file.readAsBytes();
    expect(bytes, [9, 9, 1, 2, 3]);
  });

  test('records a live DASH manifest using a duration template', () async {
    var manifestRequests = 0;
    final watch = Stopwatch()..start();
    final start = DateTime.now().toUtc().subtract(const Duration(seconds: 10));
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final base = 'http://127.0.0.1:${server.port}';
    server.listen((request) {
      final path = request.uri.path;
      if (path == '/live.mpd') {
        manifestRequests++;
        request.response
          ..statusCode = 200
          ..headers.set('content-type', 'application/dash+xml')
          ..write('''<?xml version="1.0"?>
<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" type="dynamic"
     minimumUpdatePeriod="PT1S"
     availabilityStartTime="${start.toIso8601String()}"
     timeShiftBufferDepth="PT10S">
  <Period>
    <AdaptationSet mimeType="video/mp4" contentType="video">
      <Representation id="v" bandwidth="1000" width="1280" height="720" codecs="avc1.4d401f">
        <SegmentTemplate timescale="1" startNumber="1" duration="1"
            initialization="init.mp4"
            media="seg-\$Number\$.m4s"/>
      </Representation>
    </AdaptationSet>
  </Period>
</MPD>
''');
      } else if (path == '/init.mp4') {
        request.response
          ..statusCode = 200
          ..add([7]);
      } else if (path.startsWith('/seg-')) {
        request.response
          ..statusCode = 200
          ..add([1]);
      } else {
        request.response.statusCode = 404;
      }
      request.response.close();
    });
    final directory = await Directory.systemTemp.createTemp('linky-dash-dur');
    addTearDown(() async {
      await server.close(force: true);
      await directory.delete(recursive: true);
    });

    final result = await DashDownloader(workers: 2).download(
      url: '$base/live.mpd',
      destination: File('${directory.path}/recording.mp4'),
      workDirectory: Directory('${directory.path}/work'),
      onProgress: (_, __) {},
      isCancelled: () =>
          manifestRequests >= 3 || watch.elapsed > const Duration(seconds: 10),
    );

    expect(result.isLive, isTrue);
    expect(await result.file.exists(), isTrue);
    expect(await result.file.length(), greaterThan(1));
  });

  test('refuses DRM-protected DASH streams', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final base = 'http://127.0.0.1:${server.port}';
    server.listen((request) {
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType('application', 'dash+xml')
        ..write('''<?xml version="1.0"?>
<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" type="static"
     mediaPresentationDuration="PT2S">
  <Period>
    <AdaptationSet mimeType="video/mp4" contentType="video">
      <ContentProtection schemeIdUri="urn:uuid:edef8ba9-79d6-4ace-a3c8-27dcd51d21ed"/>
      <Representation id="v" bandwidth="1000">
        <SegmentTemplate media="seg-\$Number\$.m4s" duration="1" timescale="1" startNumber="1"/>
      </Representation>
    </AdaptationSet>
  </Period>
</MPD>
''');
      request.response.close();
    });
    final directory = await Directory.systemTemp.createTemp('linky-dash-drm');
    addTearDown(() async {
      await server.close(force: true);
      await directory.delete(recursive: true);
    });

    await expectLater(
      DashDownloader(workers: 1).download(
        url: '$base/drm.mpd',
        destination: File('${directory.path}/drm.mp4'),
        workDirectory: Directory('${directory.path}/work'),
        onProgress: (_, __) {},
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
