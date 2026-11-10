import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../services/device_resources.dart';
import '../../services/playback_position_service.dart';

class VideoPlaybackScreen extends StatefulWidget {
  const VideoPlaybackScreen({required this.file, super.key});

  final File file;

  @override
  State<VideoPlaybackScreen> createState() => _VideoPlaybackScreenState();
}

class _VideoPlaybackScreenState extends State<VideoPlaybackScreen> {
  static const _speeds = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  late final VideoPlayerController _controller;
  Object? _error;
  double _speed = 1.0;
  bool _fill = false;
  int _lastSavedSecond = -1;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file)
      ..addListener(_onChanged);
    _controller.initialize().then((_) async {
      if (!mounted) return;
      final duration = _controller.value.duration;
      final saved =
          PlaybackPositionService.instance.positionFor(widget.file.path);
      if (saved != null &&
          saved.inMilliseconds > 3000 &&
          saved < duration - const Duration(seconds: 3)) {
        await _controller.seekTo(saved);
      }
      await _controller.setPlaybackSpeed(_speed);
      if (!mounted) return;
      setState(() {});
      await _controller.play();
    }).catchError((Object error) {
      if (mounted) setState(() => _error = error);
    });
  }

  void _onChanged() {
    if (!mounted) return;
    final value = _controller.value;
    if (value.isInitialized && value.isPlaying) {
      final second = value.position.inSeconds;
      if (second > 0 && second != _lastSavedSecond && second % 5 == 0) {
        _lastSavedSecond = second;
        unawaited(
          PlaybackPositionService.instance
              .save(widget.file.path, value.position),
        );
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    final value = _controller.value;
    if (value.isInitialized) {
      unawaited(
        PlaybackPositionService.instance
            .save(widget.file.path, value.position),
      );
    }
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

  Future<void> _enterPip() async {
    final entered = await DeviceResources.instance.enterPip();
    if (!entered && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Picture-in-picture is unavailable.')),
      );
    }
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
        actions: [
          PopupMenuButton<double>(
            tooltip: 'Playback speed',
            icon: const Icon(Icons.speed),
            initialValue: _speed,
            onSelected: (speed) {
              setState(() => _speed = speed);
              _controller.setPlaybackSpeed(speed);
            },
            itemBuilder: (context) => [
              for (final speed in _speeds)
                PopupMenuItem(
                  value: speed,
                  child: Text('${speed == speed.roundToDouble() ? speed.toInt() : speed}x'),
                ),
            ],
          ),
          IconButton(
            tooltip: _fill ? 'Fit video' : 'Fill screen',
            onPressed: () => setState(() => _fill = !_fill),
            icon: Icon(_fill ? Icons.fit_screen : Icons.aspect_ratio),
          ),
          IconButton(
            tooltip: 'Picture-in-picture',
            onPressed: _enterPip,
            icon: const Icon(Icons.picture_in_picture_alt),
          ),
        ],
      ),
      backgroundColor: Colors.black,
      body: _error != null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'This video could not be played. Its format or codec may not be supported.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white),
                ),
              ),
            )
          : !value.isInitialized
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Expanded(
                      child: _fill
                          ? SizedBox.expand(
                              child: FittedBox(
                                fit: BoxFit.cover,
                                child: SizedBox(
                                  width: value.size.width,
                                  height: value.size.height,
                                  child: VideoPlayer(_controller),
                                ),
                              ),
                            )
                          : Center(
                              child: AspectRatio(
                                aspectRatio: value.aspectRatio > 0
                                    ? value.aspectRatio
                                    : 16 / 9,
                                child: VideoPlayer(_controller),
                              ),
                            ),
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
    );
  }
}
