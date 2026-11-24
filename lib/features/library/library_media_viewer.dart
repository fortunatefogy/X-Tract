import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../services/device_media_channel.dart';
import '../../theme/app_theme.dart';
import '../../widgets/media_thumbnail.dart';
import '../downloads/video_playback_screen.dart';

/// Full-screen viewer that pages left/right through the files of a folder.
class LibraryMediaViewer extends StatefulWidget {
  const LibraryMediaViewer({
    super.key,
    required this.files,
    required this.initialIndex,
  });

  final List<File> files;
  final int initialIndex;

  @override
  State<LibraryMediaViewer> createState() => _LibraryMediaViewerState();
}

class _LibraryMediaViewerState extends State<LibraryMediaViewer>
    with WidgetsBindingObserver {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  VideoPlayerController? _video;
  int? _videoIndex;
  bool _wasPlayingBeforePause = false;

  File get _file => widget.files[_index];
  String get _type => _typeOf(_file.uri.pathSegments.last);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadVideo(_index));
  }

  void _loadVideo(int index) {
    _disposeVideo();
    if (index < 0 || index >= widget.files.length) return;
    final file = widget.files[index];
    if (_typeOf(file.uri.pathSegments.last) != 'video') return;
    final controller = VideoPlayerController.file(file);
    _video = controller;
    _videoIndex = index;
    controller.initialize().then((_) async {
      if (!mounted || !identical(_video, controller)) return;
      await controller.play();
      if (mounted && identical(_video, controller)) setState(() {});
    }).catchError((Object _) {});
  }

  void _disposeVideo() {
    final controller = _video;
    _video = null;
    _videoIndex = null;
    if (controller != null) {
      controller.pause();
      controller.dispose();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _video;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _wasPlayingBeforePause = controller.value.isPlaying;
      controller.pause();
    } else if (state == AppLifecycleState.resumed && _wasPlayingBeforePause) {
      _wasPlayingBeforePause = false;
      controller.play();
    }
  }

  static String _typeOf(String name) {
    final lower = name.toLowerCase();
    if (RegExp(r'\.(jpe?g|png|gif|webp|avif|bmp|heic|heif)$').hasMatch(lower)) {
      return 'image';
    }
    if (RegExp(r'\.(mp4|m4v|webm|mov|3gp|mkv|avi)$').hasMatch(lower)) {
      return 'video';
    }
    if (RegExp(r'\.(mp3|m4a|aac|ogg|oga|opus|wav|flac|weba)$').hasMatch(lower)) {
      return 'audio';
    }
    return 'document';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeVideo();
    _controller.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _share() async {
    try {
      await DeviceMediaChannel().shareFile(_file.path);
    } catch (error) {
      _toast('Could not share the file: $error');
    }
  }

  Future<void> _openWith() async {
    try {
      await DeviceMediaChannel().openWithFile(_file.path);
    } catch (error) {
      _toast('No app could open this file: $error');
    }
  }

  void _play() {
    // Avoid the inline video and the full player both playing at once.
    _video?.pause();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VideoPlaybackScreen(file: _file),
      ),
    );
  }

  void _primaryAction() {
    if (_type == 'video' || _type == 'audio') {
      _play();
    } else if (_type == 'document') {
      _openWith();
    }
  }

  String get _primaryLabel {
    if (_type == 'video') return 'Open player';
    if (_type == 'audio') return 'Play audio';
    if (_type == 'document') return 'Open with';
    return '';
  }

  IconData get _primaryIcon {
    if (_type == 'video') return Icons.play_arrow_rounded;
    if (_type == 'audio') return Icons.play_arrow_rounded;
    return Icons.open_in_new_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final name = _file.uri.pathSegments.last;
    final showAction = _type != 'image';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.body(15,
                  weight: FontWeight.w700, color: Colors.white),
            ),
            Text(
              '${_index + 1} of ${widget.files.length}',
              style: AppText.body(11, color: Colors.white60),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Share',
            onPressed: _share,
            icon: const Icon(Icons.share_rounded),
          ),
          IconButton(
            tooltip: 'Open with',
            onPressed: _openWith,
            icon: const Icon(Icons.open_in_new_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.files.length,
            onPageChanged: (value) {
              setState(() => _index = value);
              _loadVideo(value);
            },
            itemBuilder: (context, index) => _page(
              widget.files[index],
              _typeOf(widget.files[index].uri.pathSegments.last),
              index,
            ),
          ),
          if (showAction)
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: SafeArea(
                top: false,
                child: Center(
                  child: FilledButton.icon(
                    onPressed: _primaryAction,
                    icon: Icon(_primaryIcon, size: 18),
                    label: Text(_primaryLabel),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _page(File file, String type, int index) {
    final name = file.uri.pathSegments.last;
    switch (type) {
      case 'image':
        return Center(
          child: InteractiveViewer(
            child: Image.file(
              file,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => _info(
                icon: Icons.broken_image_outlined,
                name: name,
              ),
            ),
          ),
        );
      case 'video':
        final controller = _video;
        final isCurrent = index == _videoIndex;
        if (isCurrent &&
            controller != null &&
            controller.value.isInitialized) {
          return Center(
            child: GestureDetector(
              onTap: () async {
                if (controller.value.isPlaying) {
                  await controller.pause();
                } else {
                  if (controller.value.position >= controller.value.duration) {
                    await controller.seekTo(Duration.zero);
                  }
                  await controller.play();
                }
                if (mounted) setState(() {});
              },
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio <= 0
                    ? 16 / 9
                    : controller.value.aspectRatio,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    VideoPlayer(controller),
                    if (!controller.value.isPlaying)
                      const Icon(Icons.play_circle_fill_rounded,
                          size: 72, color: Colors.white70),
                  ],
                ),
              ),
            ),
          );
        }
        final size =
            (MediaQuery.sizeOf(context).shortestSide * 0.62).clamp(180.0, 340.0);
        return Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              MediaThumbnail(
                type: 'video',
                file: file,
                size: size,
                fallback: const Icon(Icons.movie_outlined,
                    size: 64, color: Colors.white38),
              ),
              if (isCurrent)
                const SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Colors.white70,
                  ),
                )
              else
                const Icon(Icons.play_circle_fill_rounded,
                    size: 72, color: Colors.white70),
            ],
          ),
        );
      case 'audio':
        return _info(
          icon: Icons.music_note_rounded,
          name: name,
          subtitle: 'Audio',
        );
      default:
        return _info(
          icon: Icons.insert_drive_file_outlined,
          name: name,
          subtitle: 'Document',
        );
    }
  }

  Widget _info({
    required IconData icon,
    required String name,
    String? subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: const BoxDecoration(
                color: Color(0xFF1C1F2A),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 56, color: Colors.white70),
            ),
            const SizedBox(height: 20),
            Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppText.body(15,
                  weight: FontWeight.w700, color: Colors.white),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: AppText.body(12, color: Colors.white54),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
