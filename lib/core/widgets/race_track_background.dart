import 'package:flutter/material.dart';

/// Perspective race-track background painter — converging lane lines,
/// dashed center stripes, and a checkered finish line.
///
/// Designed to sit inside the Game of the Day hero so the red→orange
/// gradient reads like a fast racetrack. Subtle (10-15% white) so it
/// never competes with the foreground text and artwork.
class RaceTrackBackground extends StatelessWidget {
  const RaceTrackBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RaceTrackPainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _RaceTrackPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final white = Colors.white.withValues(alpha: 0.12);
    final whiteStrong = Colors.white.withValues(alpha: 0.20);

    // Vanishing point near top centre — 30% from top.
    final vp = Offset(w / 2, h * 0.30);

    // Lane edges — converge at the vanishing point, spread at bottom.
    final bottomLeft = Offset(0, h);
    final bottomRight = Offset(w, h);

    final lanePaint = Paint()
      ..color = white
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // 5 vertical-ish lane lines (3 inside the track + 2 edges).
    for (var i = 0; i <= 5; i++) {
      final x = w * (i / 5);
      canvas.drawLine(vp, Offset(x, h), lanePaint);
    }
    // Outline the track.
    canvas.drawLine(bottomLeft, vp, lanePaint);
    canvas.drawLine(bottomRight, vp, lanePaint);

    // Dashed center stripes near the bottom — gives motion feel.
    final dashPaint = Paint()
      ..color = whiteStrong
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const dashCount = 6;
    final dashWidth = w * 0.04;
    final dashGap = w * 0.04;
    final totalDash = dashCount * (dashWidth + dashGap);
    var xStart = (w - totalDash) / 2;
    final yDash = h * 0.78;
    for (var i = 0; i < dashCount; i++) {
      final start = Offset(xStart, yDash);
      final end = Offset(xStart + dashWidth, yDash);
      canvas.drawLine(start, end, dashPaint);
      xStart += dashWidth + dashGap;
    }

    // Checkered finish line near the top of the visible track.
    _paintChecker(canvas, vp.translate(0, -8), w * 0.20, h * 0.04);
  }

  void _paintChecker(Canvas canvas, Offset center, double width, double height) {
    final cols = 8;
    final rows = 2;
    final cw = width / cols;
    final ch = height / rows;
    final rect = Rect.fromCenter(
      center: center,
      width: width,
      height: height,
    );
    final white = Colors.white.withValues(alpha: 0.55);
    final dim = Colors.white.withValues(alpha: 0.18);
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final on = (r + c).isEven;
        final cell = Rect.fromLTWH(
          rect.left + c * cw,
          rect.top + r * ch,
          cw,
          ch,
        );
        canvas.drawRect(cell, Paint()..color = on ? white : dim);
      }
    }
  }

  @override
  bool shouldRepaint(_RaceTrackPainter old) => false;
}
