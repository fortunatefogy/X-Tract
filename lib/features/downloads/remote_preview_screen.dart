import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class RemotePreviewScreen extends StatefulWidget {
  const RemotePreviewScreen({
    required this.url,
    required this.title,
    this.headers = const {},
    super.key,
  });

  final String url;
  final String title;
  final Map<String, String> headers;

  @override
  State<RemotePreviewScreen> createState() => _RemotePreviewScreenState();
}

class _RemotePreviewScreenState extends State<RemotePreviewScreen> {
  static const _speeds = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  late final VideoPlayerController _controller;
  Object? _error;
  double _speed = 1.0;
  bool _fill = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.url),
      httpHeaders: widget.headers,
    )..addListener(_onChanged);
    _controller.initialize().then((_) async {
      if (!mounted) return;
      await _controller.setPlaybackSpeed(_speed);
      if (!mounted) return;
      setState(() {});
      await _controller.play();
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
          widget.title,
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
                  child: Text(
                    '${speed == speed.roundToDouble() ? speed.toInt() : speed}x',
                  ),
                ),
            ],
          ),
          IconButton(
            tooltip: _fill ? 'Fit video' : 'Fill screen',
            onPressed: () => setState(() => _fill = !_fill),
            icon: Icon(_fill ? Icons.fit_screen : Icons.aspect_ratio),
          ),
        ],
      ),
      backgroundColor: Colors.black,
      body: _error != null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'This stream could not be previewed. Its format or headers may not be supported by the player.',
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
