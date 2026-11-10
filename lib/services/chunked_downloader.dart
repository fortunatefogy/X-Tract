import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'proxy_service.dart';
import 'secure_dns_service.dart';
import 'dart:math';

class ChunkedDownloadCanceled implements Exception {
  const ChunkedDownloadCanceled();
}

class _RangeUnsupported implements Exception {
  const _RangeUnsupported();
}

class _Probe {
  const _Probe({
    required this.total,
    required this.supportsRange,
    this.response,
  });

  final int? total;
  final bool supportsRange;
  final HttpClientResponse? response;
}

class _ChunkInfo {
  const _ChunkInfo({
    required this.start,
    required this.end,
    required this.path,
  });

  final int start;
  final int end;
  final String path;

  int get length => end - start + 1;
}

class ChunkedDownloader {
  ChunkedDownloader({
    this.threadCount = 4,
    this.minChunkBytes = 256 * 1024,
    this.minFileBytes = 512 * 1024,
    this.retries = 3,
  });

  final int threadCount;
  final int minChunkBytes;
  final int minFileBytes;
  final int retries;

  Future<File> download({
    required String url,
    required File destination,
    required Directory workDirectory,
    Map<String, String> headers = const {},
    int? expectedBytes,
    required void Function(int received, int? total) onProgress,
    bool Function()? isCancelled,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme)) {
      throw const FormatException(
          'Only http and https downloads support ranges.');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30)
      ..idleTimeout = const Duration(seconds: 30)
      ..userAgent = 'Linky Android';
    ProxyService.applyToClient(client);
    await SecureDnsService.instance.configure(client);
    try {
      final probe = await _probe(client, uri, headers, expectedBytes);
      if (probe.supportsRange) {
        try {
          return await _downloadChunks(
            client: client,
            uri: uri,
            headers: headers,
            total: probe.total!,
            destination: destination,
            workDirectory: workDirectory,
            onProgress: onProgress,
            isCancelled: isCancelled,
          );
        } on _RangeUnsupported {
          // The server advertised ranges but returned a full response.
        }
      }
      final response = probe.response ?? await _open(client, uri, headers);
      return await _downloadSingle(
        response: response,
        destination: destination,
        expectedBytes: probe.total ?? expectedBytes,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<_Probe> _probe(
    HttpClient client,
    Uri uri,
    Map<String, String> headers,
    int? expectedBytes,
  ) async {
    final response = await _open(
      client,
      uri,
      headers,
      range: 'bytes=0-0',
    );
    final status = response.statusCode;
    final contentRange = response.headers.value(HttpHeaders.contentRangeHeader);
    final acceptRanges =
        response.headers.value(HttpHeaders.acceptRangesHeader)?.toLowerCase();
    int? total;
    if (status == 206 && contentRange != null) {
      total = _totalFromContentRange(contentRange);
    }
    total ??= expectedBytes;
    if (status == 206 && total != null) {
      await _discard(response);
      return _Probe(total: total, supportsRange: true);
    }
    if (status == 200) {
      final length = response.contentLength;
      return _Probe(
        total: length > 0 ? length : expectedBytes,
        supportsRange: false,
        response: response,
      );
    }
    if (status == 416 && expectedBytes != null) {
      await _discard(response);
      return _Probe(total: expectedBytes, supportsRange: true);
    }
    await _discard(response);
    if (status >= 400) {
      // Some servers reject ranged requests (400/405/412/501) but serve the
      // file fine as a normal GET. Fall back to a single stream instead of
      // failing the whole download.
      if (status == 400 || status == 405 || status == 412 || status == 501) {
        try {
          final plain = await _open(client, uri, headers);
          final code = plain.statusCode;
          if (code >= 200 && code < 300) {
            return _Probe(
              total:
                  plain.contentLength > 0 ? plain.contentLength : expectedBytes,
              supportsRange: false,
              response: plain,
            );
          }
          await _discard(plain);
        } catch (_) {}
      }
      throw HttpException(
        'The media server returned HTTP $status for '
        '${uri.host}${uri.path}.',
      );
    }
    return _Probe(
      total: expectedBytes,
      supportsRange: acceptRanges?.contains('bytes') == true,
    );
  }

  Future<File> _downloadSingle({
    required HttpClientResponse response,
    required File destination,
    required int? expectedBytes,
    required void Function(int received, int? total) onProgress,
    bool Function()? isCancelled,
  }) async {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await _discard(response);
      throw HttpException(
        'The media server returned HTTP ${response.statusCode}.',
      );
    }
    final total =
        response.contentLength > 0 ? response.contentLength : expectedBytes;
    await destination.parent.create(recursive: true);
    final temporary = File('${destination.path}.linky-tmp');
    final sink = temporary.openWrite();
    var received = 0;
    try {
      await for (final chunk in response) {
        if (isCancelled?.call() == true) {
          throw const ChunkedDownloadCanceled();
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress(received, total);
      }
      await sink.flush();
      await sink.close();
      if (await destination.exists()) await destination.delete();
      await temporary.rename(destination.path);
      onProgress(received, total ?? received);
      return destination;
    } catch (_) {
      try {
        await sink.close();
      } catch (_) {}
      try {
        if (await temporary.exists()) await temporary.delete();
      } catch (_) {}
      rethrow;
    }
  }

  Future<File> _downloadChunks({
    required HttpClient client,
    required Uri uri,
    required Map<String, String> headers,
    required int total,
    required File destination,
    required Directory workDirectory,
    required void Function(int received, int? total) onProgress,
    bool Function()? isCancelled,
  }) async {
    await workDirectory.create(recursive: true);
    final channels = max(
      1,
      min(threadCount, max(1, (total / minChunkBytes).ceil())),
    );
    final base = total ~/ channels;
    final remainder = total % channels;
    final chunks = <_ChunkInfo>[];
    var offset = 0;
    for (var index = 0; index < channels; index++) {
      final length = base + (index < remainder ? 1 : 0);
      if (length <= 0) continue;
      chunks.add(_ChunkInfo(
        start: offset,
        end: offset + length - 1,
        path: '${workDirectory.path}${Platform.pathSeparator}part-$index.bin',
      ));
      offset += length;
    }
    if (chunks.isEmpty) {
      throw const FormatException('The media file has no downloadable bytes.');
    }

    final metadataFile = File(
      '${workDirectory.path}${Platform.pathSeparator}metadata.json',
    );
    var reusable = false;
    if (await metadataFile.exists()) {
      try {
        final raw = jsonDecode(await metadataFile.readAsString());
        final ranges = raw is Map ? raw['ranges'] : null;
        reusable = raw is Map &&
            raw['total'] == total &&
            ranges is List &&
            ranges.length == chunks.length &&
            List.generate(chunks.length, (index) {
              final range = ranges[index];
              return range is List &&
                  range.length == 2 &&
                  range[0] == chunks[index].start &&
                  range[1] == chunks[index].end;
            }).every((matches) => matches);
      } catch (_) {
        reusable = false;
      }
    }
    if (!reusable) {
      for (final chunk in chunks) {
        try {
          await File(chunk.path).delete();
        } catch (_) {}
      }
      await metadataFile.writeAsString(jsonEncode({
        'url': uri.toString(),
        'total': total,
        'channels': chunks.length,
        'ranges': [
          for (final chunk in chunks) [chunk.start, chunk.end],
        ],
        'createdAt': DateTime.now().toIso8601String(),
      }));
    }

    var received = 0;
    for (final chunk in chunks) {
      final file = File(chunk.path);
      final have = await file.exists() ? await file.length() : 0;
      received += have.clamp(0, chunk.length);
    }
    onProgress(received, total);

    var aborted = false;
    final failures = <Object>[];
    await Future.wait(chunks.map((chunk) async {
      try {
        await _downloadChunk(
          client: client,
          uri: uri,
          headers: headers,
          chunk: chunk,
          isCancelled: isCancelled,
          isAborted: () => aborted,
          onBytes: (bytes) {
            received += bytes;
            onProgress(received, total);
          },
        );
      } catch (error) {
        failures.add(error);
        if (error is _RangeUnsupported) aborted = true;
      }
    }));

    if (aborted || failures.any((error) => error is _RangeUnsupported)) {
      throw const _RangeUnsupported();
    }
    if (failures.any((error) => error is ChunkedDownloadCanceled)) {
      throw const ChunkedDownloadCanceled();
    }
    if (failures.isNotEmpty) throw failures.first;

    for (final chunk in chunks) {
      final file = File(chunk.path);
      final length = await file.exists() ? await file.length() : 0;
      if (length != chunk.length) {
        throw HttpException('A download chunk is incomplete.');
      }
    }

    await destination.parent.create(recursive: true);
    final temporary = File('${destination.path}.linky-tmp');
    final sink = temporary.openWrite();
    try {
      for (final chunk in chunks) {
        await sink.addStream(File(chunk.path).openRead());
      }
      await sink.flush();
      await sink.close();
      if (await destination.exists()) await destination.delete();
      await temporary.rename(destination.path);
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
    onProgress(total, total);
    return destination;
  }

  Future<void> _downloadChunk({
    required HttpClient client,
    required Uri uri,
    required Map<String, String> headers,
    required _ChunkInfo chunk,
    required void Function(int bytes) onBytes,
    required bool Function() isAborted,
    bool Function()? isCancelled,
  }) async {
    final file = File(chunk.path);
    var have = await file.exists() ? await file.length() : 0;
    if (have > chunk.length) {
      await file.delete();
      have = 0;
    }
    if (have == chunk.length) return;
    var start = chunk.start + have;
    var attempts = 0;
    while (true) {
      if (isAborted()) throw const _RangeUnsupported();
      if (isCancelled?.call() == true) throw const ChunkedDownloadCanceled();
      final response = await _open(
        client,
        uri,
        headers,
        range: 'bytes=$start-${chunk.end}',
      );
      if (response.statusCode == 206) {
        final sink = file.openWrite(mode: FileMode.append);
        var cursor = start;
        try {
          await for (final bytes in response) {
            if (isAborted()) throw const _RangeUnsupported();
            if (isCancelled?.call() == true) {
              throw const ChunkedDownloadCanceled();
            }
            sink.add(bytes);
            cursor += bytes.length;
            onBytes(bytes.length);
          }
          await sink.flush();
          await sink.close();
        } catch (error) {
          try {
            await sink.close();
          } catch (_) {}
          if (error is _RangeUnsupported || error is ChunkedDownloadCanceled) {
            rethrow;
          }
          attempts++;
          if (attempts > retries) rethrow;
          have = await file.exists() ? await file.length() : 0;
          if (have >= chunk.length) return;
          start = chunk.start + have;
          await Future<void>.delayed(
            Duration(milliseconds: 250 * attempts),
          );
          continue;
        }
        if (cursor - 1 == chunk.end) return;
        attempts++;
        if (attempts > retries) {
          throw HttpException('A download chunk ended early.');
        }
        have = await file.exists() ? await file.length() : 0;
        if (have >= chunk.length) return;
        start = chunk.start + have;
        continue;
      }
      if (response.statusCode == 200) {
        await _discard(response);
        throw const _RangeUnsupported();
      }
      if (response.statusCode == 416) {
        await _discard(response);
        have = await file.exists() ? await file.length() : 0;
        if (have >= chunk.length) return;
        throw HttpException('The server rejected the requested byte range.');
      }
      final status = response.statusCode;
      await _discard(response);
      attempts++;
      if (attempts > retries) {
        throw HttpException(
          'The media server returned HTTP $status for '
          '${uri.host}${uri.path}.',
        );
      }
      await Future<void>.delayed(Duration(milliseconds: 250 * attempts));
    }
  }

  Future<HttpClientResponse> _open(
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
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      if (range != null) request.headers.set(HttpHeaders.rangeHeader, range);
      final response = await request.close();
      if (!response.isRedirect) return response;
      if (redirects >= 5) {
        await _discard(response);
        throw const HttpException('The media link redirected too many times.');
      }
      final location = response.headers.value(HttpHeaders.locationHeader);
      await _discard(response);
      if (location == null)
        throw const HttpException('Invalid media redirect.');
      current = current.resolve(location);
      if (!{'http', 'https'}.contains(current.scheme)) {
        throw const HttpException('Unsupported media redirect.');
      }
    }
  }

  int? _totalFromContentRange(String value) {
    final slash = value.lastIndexOf('/');
    if (slash < 0) return null;
    final total = int.tryParse(value.substring(slash + 1).trim());
    return total != null && total > 0 ? total : null;
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
}
