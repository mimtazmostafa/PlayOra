import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Shared first-launch tutorial overlay used by arcade games that need
/// a quick "what to do" prompt.
///
/// Renders a white capsule with a kawaii pointing hand on the left and
/// a single-line label on the right. The capsule auto-fades based on
/// [progress] (0 = fully visible, 1 = dismissed) and is wrapped in a
/// drop-in intro animation.
class TutorialOverlay extends StatefulWidget {
  const TutorialOverlay({
    super.key,
    required this.idleTime,
    required this.progress,
    required this.message,
    this.handTilt = -0.4,
    this.pointDown = false,
    this.textColor = const Color(0xFF1E3A8A),
  });

  final double idleTime;
  final double progress;
  final String message;

  /// Rotation in radians applied to the pointing hand. Negative values
  /// tilt the finger down-left; positive values tilt down-right.
  final double handTilt;

  /// When true, the finger points down instead of to the left.
  final bool pointDown;

  /// Color of the message text inside the capsule.
  final Color textColor;

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 280))
        ..forward();

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final opacity = 1 - widget.progress * 0.3;
    return AnimatedBuilder(
      animation: _intro,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(_intro.value);
        return Transform.translate(
          offset: Offset(0, (1 - t) * 30),
          child: Opacity(opacity: t * opacity, child: child),
        );
      },
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 18,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.rotate(
                angle: widget.handTilt,
                child: CustomPaint(
                  size: const Size(34, 34),
                  painter: _PointingHandPainter(
                    idleTime: widget.idleTime,
                    pointDown: widget.pointDown,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                widget.message,
                style: TextStyle(
                  color: widget.textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kawaii cartoon hand — yellow palm + dark outline, with a finger
/// pointing in the direction of the rotation applied by the caller.
/// Bobs up and down with [idleTime] and "taps" every couple of cycles.
class _PointingHandPainter extends CustomPainter {
  _PointingHandPainter({required this.idleTime, this.pointDown = false});

  final double idleTime;
  final bool pointDown;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w * 0.45;
    final cy = h * 0.55;
    final bob = math.sin(idleTime * 4) * 3;
    final tap = math.sin(idleTime * 8) > 0.7 ? 6.0 : 0.0;

    canvas.save();
    canvas.translate(cx, cy + bob + tap);

    // Drop shadow.
    final palmRect = Rect.fromCenter(center: Offset.zero, width: 22, height: 22);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        palmRect.shift(const Offset(0, 2)),
        const Radius.circular(8),
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.20)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // Palm.
    canvas.drawRRect(
      RRect.fromRectAndRadius(palmRect, const Radius.circular(8)),
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFFFEF08A), Color(0xFFFCD34D)],
        ).createShader(palmRect),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(palmRect, const Radius.circular(8)),
      Paint()
        ..color = const Color(0xFF1E293B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    // Pointing finger.
    final fingerPath = pointDown
        ? (Path()
            ..moveTo(-2, 8)
            ..lineTo(-2, -4)
            ..lineTo(8, -4)
            ..arcToPoint(
              const Offset(8, 2),
              radius: const Radius.circular(4),
              clockwise: false,
            )
            ..lineTo(-2, 8)
            ..close())
        : (Path()
            ..moveTo(-2, -8)
            ..lineTo(-2, 4)
            ..lineTo(8, 4)
            ..arcToPoint(
              const Offset(8, -2),
              radius: const Radius.circular(4),
              clockwise: false,
            )
            ..lineTo(-2, -8)
            ..close());
    canvas.drawPath(
      fingerPath,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFEF08A), Color(0xFFF59E0B)],
        ).createShader(fingerPath.getBounds()),
    );
    canvas.drawPath(
      fingerPath,
      Paint()
        ..color = const Color(0xFF1E293B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(_PointingHandPainter old) =>
      old.idleTime != idleTime || old.pointDown != pointDown;
}
