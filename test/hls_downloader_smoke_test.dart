import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:linky/services/hls_downloader.dart';

void main() {
  test('downloads the best variant, init segment, and all media segments',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final base = 'http://127.0.0.1:${server.port}';
    final routes = <String, List<int>>{
      '/master.m3u8': utf8.encode('''#EXTM3U
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="English",DEFAULT=YES,URI="audio.m3u8"
#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="English",URI="subs.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=1280x720,CODECS="avc1.4d401f,mp4a.40.2",AUDIO="aud",SUBTITLES="subs"
high.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=400000,RESOLUTION=640x360,CODECS="avc1.4d401e,mp4a.40.2"
low.m3u8
'''),
      '/high.m3u8': utf8.encode('''#EXTM3U
#EXT-X-TARGETDURATION:4
#EXT-X-MEDIA-SEQUENCE:7
#EXT-X-MAP:URI="init.mp4"
#EXTINF:4,
seg0.m4s
#EXTINF:4,
seg1.m4s
#EXTINF:4,
seg2.m4s
#EXT-X-ENDLIST
'''),
      '/init.mp4': [1, 2, 3],
      '/seg0.m4s': [10, 11],
      '/seg1.m4s': [20, 21],
      '/seg2.m4s': [30, 31],
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

    final directory = await Directory.systemTemp.createTemp('linky-hls-test');
    addTearDown(() async {
      await server.close(force: true);
      await directory.delete(recursive: true);
    });
    final progress = <(int, int)>[];
    final result = await HlsDownloader(workers: 2).download(
      url: '$base/master.m3u8',
      destination: File('${directory.path}/movie.ts'),
      workDirectory: Directory('${directory.path}/work'),
      onProgress: (completed, total) => progress.add((completed, total)),
    );
    expect(result.file.path, endsWith('.mp4'));
    expect(result.isLive, isFalse);
    expect(result.variantLabel, '720p');
    expect(await result.file.readAsBytes(), [1, 2, 3, 10, 11, 20, 21, 30, 31]);
    expect(progress.last, (3, 3));
  });

  test('resolves segment URIs against the redirected playlist location',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final base = 'http://127.0.0.1:${server.port}';
    server.listen((request) {
      final path = request.uri.path;
      if (path == '/start/index.m3u8') {
        request.response.statusCode = HttpStatus.found;
        request.response.headers
            .set(HttpHeaders.locationHeader, '/cdn/index.m3u8');
      } else if (path == '/cdn/index.m3u8') {
        request.response.add(utf8.encode('''#EXTM3U
#EXT-X-TARGETDURATION:4
#EXTINF:4,
seg0.m4s
#EXT-X-ENDLIST
'''));
      } else if (path == '/cdn/seg0.m4s') {
        request.response.add([7, 8, 9]);
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      request.response.close();
    });

    final directory = await Directory.systemTemp.createTemp('linky-hls-test');
    addTearDown(() async {
      await server.close(force: true);
      await directory.delete(recursive: true);
    });
    final result = await HlsDownloader(workers: 1).download(
      url: '$base/start/index.m3u8',
      destination: File('${directory.path}/movie.ts'),
      workDirectory: Directory('${directory.path}/work'),
      onProgress: (_, __) {},
    );
    expect(await result.file.readAsBytes(), [7, 8, 9]);
  });
}
