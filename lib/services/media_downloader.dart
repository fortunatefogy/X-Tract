import 'dart:io';

import 'package:path_provider/path_provider.dart';

class MediaDownloader {
  static String extensionForMime(String? mimeType, {String fallback = 'mp4'}) {
    final mime = mimeType?.split(';').first.trim().toLowerCase();
    return switch (mime) {
      'audio/mpeg' => 'mp3',
      'audio/mp4' => 'm4a',
      'audio/aac' => 'aac',
      'audio/ogg' || 'audio/opus' => 'ogg',
      'audio/webm' => 'webm',
      'audio/wav' || 'audio/x-wav' => 'wav',
      'audio/flac' => 'flac',
      'audio/aiff' => 'aiff',
      'audio/x-ms-wma' => 'wma',
      'image/jpeg' => 'jpg',
      'image/png' => 'png',
      'image/webp' => 'webp',
      'image/gif' => 'gif',
      'image/avif' => 'avif',
      'image/svg+xml' => 'svg',
      'image/bmp' => 'bmp',
      'image/tiff' => 'tiff',
      'image/heic' => 'heic',
      'image/heif' => 'heif',
      'application/pdf' => 'pdf',
      'application/msword' => 'doc',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document' =>
        'docx',
      'application/vnd.ms-excel' => 'xls',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' =>
        'xlsx',
      'application/vnd.ms-powerpoint' => 'ppt',
      'application/vnd.openxmlformats-officedocument.presentationml.presentation' =>
        'pptx',
      'application/rtf' => 'rtf',
      'text/plain' => 'txt',
      'video/webm' => 'webm',
      'video/quicktime' => 'mov',
      'video/x-matroska' => 'mkv',
      'video/x-msvideo' => 'avi',
      'video/x-flv' => 'flv',
      'audio/*' => 'mp3',
      'image/*' => 'jpg',
      _ => fallback,
    };
  }

  static String sanitizeFilename(String rawName) {
    var name = rawName
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
        .trim()
        .replaceAll(RegExp(r'^[. ]+|[. ]+$'), '')
        .replaceAll(RegExp(r'[_-]{2,}'), '_');
    if (name.isEmpty || name == '.' || name == '..') name = 'media';
    const reserved = {
      'CON',
      'PRN',
      'AUX',
      'NUL',
      'COM1',
      'COM2',
      'COM3',
      'COM4',
      'COM5',
      'COM6',
      'COM7',
      'COM8',
      'COM9',
      'LPT1',
      'LPT2',
      'LPT3',
      'LPT4',
      'LPT5',
      'LPT6',
      'LPT7',
      'LPT8',
      'LPT9',
    };
    if (reserved.contains(name.split('.').first.toUpperCase())) name = '_$name';
    if (name.length > 180) name = name.substring(0, 180);
    return name;
  }

  Future<File> download(
    String url, {
    Map<String, String> headers = const {},
    String? mimeType,
  }) async {
    final uri = Uri.parse(url);
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory('${documents.path}/LinkyDownloads');
    await directory.create(recursive: true);

    final rawName = uri.pathSegments.isEmpty || uri.pathSegments.last.isEmpty
        ? 'video'
        : uri.pathSegments.last;
    final safeName = sanitizeFilename(rawName);
    final inferredExtension = '.${extensionForMime(mimeType)}';
    final name =
        safeName.contains('.') ? safeName : '$safeName$inferredExtension';
    var file = File('${directory.path}/$name');
    var duplicateIndex = 1;
    while (await file.exists()) {
      final dot = name.lastIndexOf('.');
      final stem = dot > 0 ? name.substring(0, dot) : name;
      final extension = dot > 0 ? name.substring(dot) : '.mp4';
      file = File('${directory.path}/$stem ($duplicateIndex)$extension');
      duplicateIndex++;
    }

    final client = HttpClient()..userAgent = 'Linky Android';
    IOSink? output;
    var current = uri;
    try {
      HttpClientResponse response;
      for (var redirects = 0;; redirects++) {
        final request = await client.getUrl(current);
        request.followRedirects = false;
        if (current.origin == uri.origin) {
          headers.forEach(request.headers.set);
        }
        response = await request.close();
        if (!response.isRedirect) break;
        if (redirects >= 5) {
          throw HttpException('The media link redirected too many times.');
        }
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location == null) throw HttpException('Invalid media redirect.');
        await response.drain<void>();
        current = current.resolve(location);
        if (!{'http', 'https'}.contains(current.scheme)) {
          throw HttpException('Unsupported media redirect.');
        }
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
            'The media server returned HTTP ${response.statusCode}.');
      }
      output = file.openWrite();
      await response.pipe(output);
      return file;
    } catch (_) {
      try {
        await output?.close();
      } catch (_) {}
      if (await file.exists()) await file.delete();
      rethrow;
    } finally {
      client.close(force: true);
    }
  }
}
