import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:linky/services/dash_downloader.dart';

void main() {
  test('downloads a SegmentTimeline representation with init and ranges',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final base = 'http://127.0.0.1:${server.port}';
    final routes = <String, List<int>>{
      '/manifest.mpd': utf8.encode('''<?xml version="1.0"?>
<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" type="static" mediaPresentationDuration="PT12S">
  <Period>
    <AdaptationSet mimeType="video/mp4" contentType="video">
      <Representation id="v" bandwidth="1000" width="1280" height="720" codecs="avc1.4d401f">
        <SegmentTemplate timescale="1000" startNumber="1"
            initialization="init-\$RepresentationID\$.mp4"
            media="seg-\$RepresentationID\$-\$Time\$.m4s">
          <SegmentTimeline>
            <S t="0" d="4000"/>
            <S d="4000" r="1"/>
          </SegmentTimeline>
        </SegmentTemplate>
      </Representation>
    </AdaptationSet>
  </Period>
</MPD>
'''),
      '/init-v.mp4': [1, 2, 3],
      '/seg-v-0.m4s': [10, 11],
      '/seg-v-4000.m4s': [20, 21],
      '/seg-v-8000.m4s': [30, 31],
    };
    server.listen((request) {
      final body = routes[request.uri.path];
      if (body == null) {
        request.response.statusCode = HttpStatus.notFound;
      } else {
        request.response.add(body);
      }
      request.response.close();
    });

    final directory = await Directory.systemTemp.createTemp('linky-dash-test');
    addTearDown(() async {
      await server.close(force: true);
      await directory.delete(recursive: true);
    });
    final progress = <(int, int)>[];
    final result = await DashDownloader(workers: 2).download(
      url: '$base/manifest.mpd',
      destination: File('${directory.path}/movie.mp4'),
      workDirectory: Directory('${directory.path}/work'),
      onProgress: (completed, total) => progress.add((completed, total)),
    );
    expect(result.file.path, endsWith('.mp4'));
    expect(result.isLive, isFalse);
    expect(result.label, '720p');
    expect(await result.file.readAsBytes(), [1, 2, 3, 10, 11, 20, 21, 30, 31]);
    expect(progress.last, (3, 3));
  });
}
