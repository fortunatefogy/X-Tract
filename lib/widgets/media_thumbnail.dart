import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// A compact visual preview for image and video media.
/// Videos show their poster when available, otherwise the paused first frame.
class MediaThumbnail extends StatefulWidget {
  const MediaThumbnail({
    super.key,
    required this.type,
    this.url,
    this.file,
    this.poster,
    this.headers,
    this.size = 56,
    this.fallback,
  });

  final String type;
  final String? url;
  final File? file;
  final String? poster;
  final Map<String, String>? headers;
  final double size;
  final Widget? fallback;

  @override
  State<MediaThumbnail> createState() => _MediaThumbnailState();
}

class _MediaThumbnailState extends State<MediaThumbnail> {
  VideoPlayerController? _controller;
  bool _videoFailed = false;
  Uint8List? _bytes;
  String? _loadedUrl;

  bool get _isVideo => widget.type.toLowerCase() == 'video';
  bool get _isImage => widget.type.toLowerCase() == 'image';

  @override
  void initState() {
    super.initState();
    _startVideoPreview();
    _loadHeaderImage();
  }

  @override
  void didUpdateWidget(covariant MediaThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.file?.path != widget.file?.path ||
        oldWidget.poster != widget.poster ||
        oldWidget.type != widget.type) {
      _controller?.dispose();
      _controller = null;
      _videoFailed = false;
      _startVideoPreview();
      _bytes = null;
      _loadedUrl = null;
      _loadHeaderImage();
    }
  }

  bool get _useHeaderLoader =>
      _isImage && widget.headers != null && widget.headers!.isNotEmpty;

  void _loadHeaderImage() {
    final url = widget.url;
    if (!_useHeaderLoader || url == null || url.isEmpty) return;
    if (_loadedUrl == url) return;
    _loadedUrl = url;
    _bytes = null;
    _fetchBytes(url, widget.headers!).then((bytes) {
      if (!mounted || _loadedUrl != url) return;
      setState(() => _bytes = bytes);
    }).catchError((Object _) {});
  }

  Future<Uint8List> _fetchBytes(
    String url,
    Map<String, String> headers,
  ) async {
    final attempts = <Map<String, String>>[
      headers,
      {
        for (final entry in headers.entries)
          if (entry.key.toLowerCase() != 'cookie') entry.key: entry.value,
      },
      const <String, String>{},
    ];
    Object? lastError;
    for (final attempt in attempts) {
      try {
        final bytes = await _getBytes(url, attempt);
        if (_looksLikeImage(bytes)) return bytes;
        lastError = const FormatException('Not an image response');
      } catch (error) {
        lastError = error;
      }
    }
    throw HttpException('Thumbnail fetch failed: $lastError');
  }

  Future<Uint8List> _getBytes(
    String url,
    Map<String, String> headers,
  ) async {
    final client = HttpClient();
    try {
      String? userAgent;
      for (final entry in headers.entries) {
        if (entry.key.toLowerCase() == 'user-agent') {
          userAgent = entry.value;
          break;
        }
      }
      if (userAgent != null && userAgent.isNotEmpty) {
        client.userAgent = userAgent;
      }
      final request = await client.getUrl(Uri.parse(url));
      request.followRedirects = true;
      headers.forEach((key, value) {
        if (key.toLowerCase() == 'user-agent') return;
        try {
          request.headers.set(key, value);
        } catch (_) {}
      });
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        throw HttpException('HTTP ${response.statusCode}');
      }
      return consolidateHttpClientResponseBytes(response);
    } finally {
      client.close();
    }
  }

  bool _looksLikeImage(Uint8List bytes) {
    if (bytes.length < 12) return false;
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return true;
    }
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return true;
    }
    if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
      return true;
    }
    if (bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return true;
    }
    if (bytes[4] == 0x66 &&
        bytes[5] == 0x74 &&
        bytes[6] == 0x79 &&
        bytes[7] == 0x70) {
      return true;
    }
    return false;
  }

  void _startVideoPreview() {
    if (!_isVideo || widget.poster?.isNotEmpty == true) return;
    final file = widget.file;
    final url = widget.url;
    if (file == null && (url == null || url.isEmpty)) return;
    final controller = file != null
        ? VideoPlayerController.file(file)
        : VideoPlayerController.networkUrl(Uri.parse(url!));
    _controller = controller;
    controller.initialize().then((_) async {
      await controller.setVolume(0);
      await controller.pause();
      if (mounted && identical(_controller, controller)) setState(() {});
    }).catchError((Object _) {
      if (mounted && identical(_controller, controller)) {
        setState(() => _videoFailed = true);
      }
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isImage) {
      final file = widget.file;
      final url = widget.url;
      if (file != null) {
        return _image(Image.file(file,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _placeholder(context, video: false)));
      }
      if (_useHeaderLoader) {
        final bytes = _bytes;
        if (bytes != null) {
          return _image(Image.memory(
            bytes,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                _placeholder(context, video: false),
          ));
        }
        return _image(
          widget.fallback ?? _placeholder(context, video: false),
        );
      }
      if (url != null && url.isNotEmpty) {
        return _image(Image.network(
          url,
          headers: widget.headers,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(context, video: false),
        ));
      }
    }

    if (_isVideo) {
      final poster = widget.poster;
      if (poster != null && poster.isNotEmpty) {
        return _image(
          Image.network(
            poster,
            headers: widget.headers,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _placeholder(context, video: true),
          ),
          video: true,
        );
      }
      final controller = _controller;
      if (!_videoFailed && controller?.value.isInitialized == true) {
        final dimensions = controller!.value.size;
        return _image(
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: dimensions.width,
              height: dimensions.height,
              child: VideoPlayer(controller),
            ),
          ),
          video: true,
        );
      }
    }
    return _image(widget.fallback ?? _placeholder(context, video: _isVideo),
        video: _isVideo);
  }

  Widget _image(Widget image, {bool video = false}) => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            fit: StackFit.expand,
            children: [
              image,
              if (video)
                const Center(
                  child: Icon(Icons.play_circle_fill,
                      color: Colors.white,
                      size: 25,
                      shadows: [Shadow(blurRadius: 4, color: Colors.black87)]),
                ),
            ],
          ),
        ),
      );

  Widget _placeholder(BuildContext context, {required bool video}) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(video ? Icons.movie_outlined : Icons.image_outlined,
            color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
}
