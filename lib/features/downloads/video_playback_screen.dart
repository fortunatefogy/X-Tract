import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoPlaybackScreen extends StatefulWidget {
  const VideoPlaybackScreen({required this.file, super.key});

  final File file;

  @override
  State<VideoPlaybackScreen> createState() => _VideoPlaybackScreenState();
}

class _VideoPlaybackScreenState extends State<VideoPlaybackScreen> {
  late final VideoPlayerController _controller;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file)
      ..addListener(_onChanged);
    _controller.initialize().then((_) {
      if (mounted) {
        setState(() {});
        _controller.play();
      }
    }).catchError((Object error) {
      if (mounted) setState(() => _error = error);
    });
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  String _time(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = duration.inHours;
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final value = _controller.value;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.file.uri.pathSegments.last,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      backgroundColor: Colors.black,
      body: Center(
        child: _error != null
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'This video could not be played. Its format or codec may not be supported.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white),
                ),
              )
            : !value.isInitialized
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AspectRatio(
                        aspectRatio:
                            value.aspectRatio > 0 ? value.aspectRatio : 16 / 9,
                        child: VideoPlayer(_controller),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            IconButton(
                              color: Colors.white,
                              onPressed: () => value.isPlaying
                                  ? _controller.pause()
                                  : _controller.play(),
                              icon: Icon(
                                value.isPlaying
                                    ? Icons.pause
                                    : Icons.play_arrow,
                              ),
                            ),
                            Text(
                              _time(value.position),
                              style: const TextStyle(color: Colors.white),
                            ),
                            Expanded(
                              child: Slider(
                                value: value.duration.inMilliseconds == 0
                                    ? 0
                                    : value.position.inMilliseconds
                                        .clamp(0, value.duration.inMilliseconds)
                                        .toDouble(),
                                min: 0,
                                max: value.duration.inMilliseconds == 0
                                    ? 1
                                    : value.duration.inMilliseconds.toDouble(),
                                onChanged: value.duration.inMilliseconds == 0
                                    ? null
                                    : (position) => _controller.seekTo(
                                          Duration(
                                            milliseconds: position.round(),
                                          ),
                                        ),
                              ),
                            ),
                            Text(
                              _time(value.duration),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}
