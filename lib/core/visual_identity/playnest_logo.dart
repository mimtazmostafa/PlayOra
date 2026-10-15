import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// PlayNest wordmark / app icon.
///
/// A geometric "P" fused with a play-triangle, drawn in primary purple
/// (`AppColors.primary`) and accent gold (`AppColors.accent`) on a rounded
/// square tile. The whole composition is normalized to a 1.0 × 1.0 canvas so
/// it rasterizes crisply to any target size (launcher icon, splash screen,
/// marketing renders, watermarks).
///
/// Design notes:
/// - Pill-shaped vertical stem + rounded bowl form the "P".
/// - The bowl's negative space opens to the right, which is shaped like a
///   play triangle so the "P" reads as "PlayNest" at a glance.
/// - A small gold dot sits inside the bowl's curve as a punctuation mark
///   ("the play button is the dot") and also tracks the brand gold accent.
class PlayNestLogo extends StatelessWidget {
  const PlayNestLogo({
    super.key,
    this.size = 112,
    this.background = Colors.white,
    this.primary = AppColors.primary,
    this.accent = AppColors.accent,
  });

  /// Edge length in logical pixels. The painter is resolution-independent so
  /// this can be anything (e.g. 112 for the splash tile, 1024 for the
  /// launcher icon rasterization).
  final double size;

  /// Tile background. Defaults to white for high-contrast launcher contexts.
  final Color background;

  /// Primary brand color used for the "P".
  final Color primary;

  /// Brand gold used for the play-triangle dot.
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _PlayNestLogoPainter(
          background: background,
          primary: primary,
          accent: accent,
        ),
      ),
    );
  }
}

class _PlayNestLogoPainter extends CustomPainter {
  _PlayNestLogoPainter({
    required this.background,
    required this.primary,
    required this.accent,
  });

  final Color background;
  final Color primary;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final double side = math.min(size.width, size.height);
    final Rect canvasRect = Rect.fromLTWH(0, 0, size.width, size.height);
    // Center the artwork in the available box so callers can render the logo
    // in any aspect-ratio slot without distortion.
    final Rect artRect = Rect.fromCircle(
      center: canvasRect.center,
      radius: side / 2,
    );

    _paintBackground(canvas, canvasRect);
    _paintP(canvas, artRect);
    _paintPlayDot(canvas, artRect);
  }

  // 1) Rounded-square tile.
  void _paintBackground(Canvas canvas, Rect rect) {
    final double radius = rect.shortestSide * 0.22;
    final RRect rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final Paint paint = Paint()..color = background;
    canvas.drawRRect(rrect, paint);
  }

  // 2) The "P". Built from two primitives:
  //   - a vertical pill (stem)
  //   - an upper-half rounded-rect "bowl" with a triangular negative-space
  //     cut on the right so the opening reads as a play triangle.
  void _paintP(Canvas canvas, Rect art) {
    final double w = art.width;
    final double h = art.height;

    // Stem: left-aligned vertical pill, ~22% of width, full height.
    final double stemWidth = w * 0.22;
    final double stemX = art.left + w * 0.18;
    final Rect stemRect = Rect.fromLTWH(stemX, art.top + h * 0.14, stemWidth, h * 0.72);
    final RRect stem = RRect.fromRectAndRadius(
      stemRect,
      Radius.circular(stemWidth / 2),
    );

    // Bowl: upper half, hugs the right side of the stem, opens downward.
    final double bowlLeft = stemX + stemWidth * 0.5;
    final double bowlRight = art.left + w * 0.84;
    final double bowlTop = art.top + h * 0.14;
    final double bowlBottom = art.top + h * 0.58;
    final double bowlHeight = bowlBottom - bowlTop;
    final Rect bowlRect = Rect.fromLTRB(bowlLeft, bowlTop, bowlRight, bowlBottom);
    final RRect bowl = RRect.fromRectAndRadius(
      bowlRect,
      Radius.circular(bowlHeight / 2),
    );

    // Outer "P" shape: union of stem + bowl.
    final Path outer = Path()
      ..addRRect(stem)
      ..addRRect(bowl);

    // Negative-space cut: a play-triangle carved out of the bowl. The
    // triangle points right, so the "P" reads as a play button too.
    final double cutInset = bowlHeight * 0.22;
    final double cutLeft = bowlLeft + bowlHeight * 0.12;
    final double cutRight = bowlRight - cutInset;
    final double cutMidY = (bowlTop + bowlBottom) / 2;
    final double cutHalf = bowlHeight * 0.28;
    final Path playCut = Path()
      ..moveTo(cutLeft, cutMidY - cutHalf)
      ..lineTo(cutRight, cutMidY)
      ..lineTo(cutLeft, cutMidY + cutHalf)
      ..close();

    final Path pShape = Path.combine(
      PathOperation.difference,
      outer,
      playCut,
    );

    final Paint paint = Paint()..color = primary;
    canvas.drawPath(pShape, paint);
  }

  // 3) A small gold dot filling the play-triangle's interior — punctuates the
  // logo with the brand accent and reinforces the "play" reading.
  void _paintPlayDot(Canvas canvas, Rect art) {
    final double h = art.height;

    // Same triangle geometry as the cutout, but inset slightly so the dot
    // never touches the purple outline.
    final double bowlLeft = art.left + art.width * 0.18 + art.width * 0.22 * 0.5;
    final double bowlTop = art.top + h * 0.14;
    final double bowlBottom = art.top + h * 0.58;
    final double bowlHeight = bowlBottom - bowlTop;
    final double cutInset = bowlHeight * 0.22;
    final double cutLeft = bowlLeft + bowlHeight * 0.12;
    final double cutRight = art.left + art.width * 0.84 - cutInset;
    final double cutMidY = (bowlTop + bowlBottom) / 2;
    final double cutHalf = bowlHeight * 0.16;

    final Path playFill = Path()
      ..moveTo(cutLeft, cutMidY - cutHalf)
      ..lineTo(cutRight - cutHalf * 0.4, cutMidY)
      ..lineTo(cutLeft, cutMidY + cutHalf)
      ..close();

    final Paint paint = Paint()..color = accent;
    canvas.drawPath(playFill, paint);
  }

  @override
  bool shouldRepaint(covariant _PlayNestLogoPainter old) {
    return old.background != background ||
        old.primary != primary ||
        old.accent != accent;
  }
}
