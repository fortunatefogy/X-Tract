import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../services/device_media_channel.dart';
import '../../services/device_resources.dart';
import '../../services/playback_position_service.dart';
import '../../theme/app_theme.dart';

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
  bool _showChrome = true;
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

  Future<void> _share() async {
    try {
      await DeviceMediaChannel().shareFile(widget.file.path);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not share the file: $error')),
      );
    }
  }

  void _toggleChrome() => setState(() => _showChrome = !_showChrome);

  Future<void> _pickSpeed() async {
    final speed = await showModalBottomSheet<double>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text('Playback speed', style: AppText.heading(18)),
            ),
            for (final option in _speeds)
              ListTile(
                title: Text(option == option.roundToDouble()
                    ? '${option.toInt()}x'
                    : '${option}x'),
                trailing: option == _speed
                    ? const Icon(Icons.check_rounded,
                        color: AppColors.primary)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(option),
              ),
          ],
        ),
      ),
    );
    if (speed == null) return;
    setState(() => _speed = speed);
    await _controller.setPlaybackSpeed(speed);
  }

  @override
  Widget build(BuildContext context) {
    final value = _controller.value;
    return Scaffold(
      backgroundColor: AppColors.forest,
      body: GestureDetector(
        onTap: _toggleChrome,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_error != null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'This video could not be played. Its format or codec may not be supported.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              )
            else if (!value.isInitialized)
              const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            else
              _fill
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
                        aspectRatio:
                            value.aspectRatio > 0 ? value.aspectRatio : 16 / 9,
                        child: VideoPlayer(_controller),
                      ),
                    ),
            AnimatedOpacity(
              opacity: _showChrome ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_showChrome,
                child: _chrome(value),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chrome(VideoPlayerValue value) {
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.55),
                  Colors.transparent,
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.75),
                ],
                stops: const [0, 0.25, 0.6, 1],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                Row(
                  children: [
                    _CircleButton(
                      icon: Icons.arrow_back_rounded,
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.file.uri.pathSegments.last,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _CircleButton(
                      icon: Icons.ios_share_rounded,
                      onPressed: _share,
                    ),
                    const SizedBox(width: 8),
                    _CircleButton(
                      icon: _fill
                          ? Icons.fit_screen_rounded
                          : Icons.aspect_ratio_rounded,
                      onPressed: () => setState(() => _fill = !_fill),
                    ),
                    const SizedBox(width: 8),
                    _CircleButton(
                      icon: Icons.picture_in_picture_alt_rounded,
                      onPressed: _enterPip,
                    ),
                  ],
                ),
                const Spacer(),
                if (value.isInitialized)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _CircleButton(
                        icon: Icons.replay_10_rounded,
                        size: 48,
                        onPressed: () => _controller.seekTo(
                          value.position - const Duration(seconds: 10),
                        ),
                      ),
                      const SizedBox(width: 20),
                      GestureDetector(
                        onTap: () => value.isPlaying
                            ? _controller.pause()
                            : _controller.play(),
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            value.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            size: 38,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      _CircleButton(
                        icon: Icons.forward_10_rounded,
                        size: 48,
                        onPressed: () => _controller.seekTo(
                          value.position + const Duration(seconds: 10),
                        ),
                      ),
                    ],
                  ),
                const Spacer(),
                if (value.isInitialized) ...[
                  Row(
                    children: [
                      Text(_time(value.position),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12)),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 7),
                            activeTrackColor: AppColors.primary,
                            inactiveTrackColor: Colors.white24,
                            thumbColor: Colors.white,
                          ),
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
                      ),
                      Text(_time(value.duration),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _Pill(
                        icon: Icons.speed_rounded,
                        label: _speed == _speed.roundToDouble()
                            ? '${_speed.toInt()}x'
                            : '${_speed}x',
                        onTap: _pickSpeed,
                      ),
                      const SizedBox(width: 10),
                      _Pill(
                        icon: _fill
                            ? Icons.fit_screen_rounded
                            : Icons.aspect_ratio_rounded,
                        label: _fill ? 'Fill' : 'Fit',
                        onTap: () => setState(() => _fill = !_fill),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.onPressed,
    this.size = 40,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: Material(
          color: AppColors.forestSurface,
          shape: const CircleBorder(
            side: BorderSide(color: AppColors.forestBorder),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Center(
              child: Icon(icon,
                  size: size * 0.45, color: AppColors.forestText),
            ),
          ),
        ),
      );
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: AppColors.forestSurface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.forestBorder),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onTap,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: AppColors.forestText),
                  const SizedBox(width: 6),
                  Text(label,
                      style: AppText.body(12,
                          weight: FontWeight.w600,
                          color: AppColors.forestText)),
                ],
              ),
            ),
          ),
        ),
      );
}
