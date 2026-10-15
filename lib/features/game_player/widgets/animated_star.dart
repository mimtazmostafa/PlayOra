import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Fills a 5-pointed star outline progressively from 0 → 1 over
/// [fillDuration] with a [delay] before starting. Used in victory
/// overlays to celebrate performance.
class AnimatedStar extends StatefulWidget {
  const AnimatedStar({
    super.key,
    this.size = 48,
    this.delay = Duration.zero,
    this.fillDuration = const Duration(milliseconds: 700),
    this.filled = true,
  });
  final double size;
  final Duration delay;
  final Duration fillDuration;
  final bool filled;

  @override
  State<AnimatedStar> createState() => _AnimatedStarState();
}

class _AnimatedStarState extends State<AnimatedStar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _tween;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.fillDuration);
    _tween = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
    );
    if (widget.filled) {
      Future.delayed(widget.delay, () {
        if (mounted) _ctrl.forward();
      });
    } else {
      _ctrl.value = 0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _tween,
        builder: (_, _) => CustomPaint(
          painter: _StarFillPainter(
            fill: _tween.value,
            size: widget.size,
          ),
        ),
      ),
    );
  }
}

class _StarFillPainter extends CustomPainter {
  _StarFillPainter({required this.fill, required this.size});
  final double fill;
  final double size;

  // Used in victory overlays painted on top of the always-dark game
  // canvas — the unfilled ring shows the missing star slots against
  // that dark backdrop regardless of the app's theme mode.
  static const Brightness _overlayBrightness = Brightness.dark;

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final c = canvasSize.center(Offset.zero);
    final outer = size * 0.42;
    final inner = size * 0.18;
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final isOuter = i.isEven;
      final r = isOuter ? outer : inner;
      final a = -math.pi / 2 + (i / 10) * 2 * math.pi;
      final p = c + Offset(math.cos(a) * r, math.sin(a) * r);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();

    // Background ring.
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.outline(_overlayBrightness)
        ..style = PaintingStyle.fill,
    );

    // Clip fill.
    if (fill > 0) {
      final fillPath = Path()
        ..addRect(Rect.fromLTWH(0, 0, size * fill, size));
      canvas.save();
      canvas.clipPath(path);
      canvas.drawPath(
        fillPath,
        Paint()..color = AppColors.reward,
      );
      canvas.restore();
    }

    // Outline.
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.rewardInk.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
  }

  @override
  bool shouldRepaint(_StarFillPainter old) =>
      old.fill != fill || old.size != size;
}
