import 'dart:io';

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

  bool get _isVideo => widget.type.toLowerCase() == 'video';
  bool get _isImage => widget.type.toLowerCase() == 'image';

  @override
  void initState() {
    super.initState();
    _startVideoPreview();
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
    }
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
