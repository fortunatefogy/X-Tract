import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Lightweight pulsing placeholder used while lists load, so content-shaped
/// space appears instead of a lone spinner.
class SkeletonPulse extends StatefulWidget {
  const SkeletonPulse({super.key, required this.child});

  final Widget child;

  @override
  State<SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<SkeletonPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  late final Animation<double> _opacity = Tween<double>(begin: 0.4, end: 0.75)
      .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _opacity, child: widget.child);
}

class SkeletonRows extends StatelessWidget {
  const SkeletonRows({
    super.key,
    this.count = 5,
    this.height = 64,
    this.spacing = 10,
    this.radius = 16,
  });

  final int count;
  final double height;
  final double spacing;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SkeletonPulse(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) SizedBox(height: spacing),
            Container(
              height: height,
              decoration: BoxDecoration(
                color: palette.secondary,
                borderRadius: BorderRadius.circular(radius),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
