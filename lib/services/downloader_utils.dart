import 'dart:io';

/// Tears down an in-flight response so the underlying socket is released
/// without buffering the rest of the body.
Future<void> discardResponse(HttpClientResponse response) async {
  try {
    final socket = await response.detachSocket();
    socket.destroy();
  } catch (_) {
    try {
      await response.drain<void>();
    } catch (_) {}
  }
}

/// Returns [path] without its final extension component.
String pathStem(String path) {
  final dot = path.lastIndexOf('.');
  return dot > 0 ? path.substring(0, dot) : path;
}

Future<void> deleteQuietly(File file) async {
  try {
    if (await file.exists()) await file.delete();
  } catch (_) {}
}

/// Opens [uri] and follows up to five redirects manually so the caller can
/// inspect headers (status, content-range, location) before committing.
///
/// Browser headers are only forwarded to the original origin. Error messages
/// are parameterised so each downloader keeps its existing wording.
Future<(HttpClientResponse, Uri)> openFollowingRedirects(
  HttpClient client,
  Uri uri,
  Map<String, String> headers, {
  String? range,
  bool skipCacheHeaders = false,
  bool identityEncoding = false,
  String redirectLimitMessage = 'The link redirected too many times.',
  String invalidRedirectMessage = 'Invalid redirect.',
  String unsupportedRedirectMessage = 'Unsupported redirect.',
}) async {
  var current = uri;
  for (var redirects = 0;; redirects++) {
    final request = await client.getUrl(current);
    request.followRedirects = false;
    if (current.origin == uri.origin) {
      if (skipCacheHeaders) {
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
      } else {
        headers.forEach(request.headers.set);
      }
    }
    if (identityEncoding) {
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    }
    if (range != null) request.headers.set(HttpHeaders.rangeHeader, range);
    final response = await request.close();
    if (!response.isRedirect) return (response, current);
    if (redirects >= 5) {
      await discardResponse(response);
      throw HttpException(redirectLimitMessage);
    }
    final location = response.headers.value(HttpHeaders.locationHeader);
    await discardResponse(response);
    if (location == null) throw HttpException(invalidRedirectMessage);
    current = current.resolve(location);
    if (!{'http', 'https'}.contains(current.scheme)) {
      throw HttpException(unsupportedRedirectMessage);
    }
  }
}
