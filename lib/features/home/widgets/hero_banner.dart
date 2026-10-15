import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/glossy_gradient_button.dart';
import '../../../data/registry/game_registry.dart';

/// Featured hero card on the Home screen — the visual focal point
/// above the "Popular Games" grid.
///
/// Visual recipe (light theme, matches the PlayNest reference):
///
///   * Rounded squircle (28 dp) filled with a **sky-blue gradient**
///     (light cyan top → deeper sky blue bottom).
///   * Soft floating "blob" character on the right (CustomPainter
///     smiley face) — represents the friendly mascot without a
///     bundled bitmap asset.
///   * Two stars + a couple of tiny clouds floating behind the
///     blob for the playful scene.
///   * **Left column**: chunky title (Poppins w900 24 sp),
///     "Start Playing →" glossy yellow capsule CTA.
class HeroBanner extends StatelessWidget {
  const HeroBanner({
    super.key,
    required this.game,
    required this.onPlay,
    this.title = 'Play More\nGames\nBe Happier!',
    this.subtitle,
  });

  final RegistryGame game;
  final VoidCallback onPlay;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        // Cap height responsively — slightly taller than before to
        // give the blob room.
        final height = (c.maxWidth * 0.62).clamp(220.0, 260.0);
        return Container(
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.heroCornerRadius),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF7DD3FC), // light sky blue
                Color(0xFF38BDF8), // sky blue
                Color(0xFF0EA5E9), // deeper sky blue
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0EA5E9).withValues(alpha: 0.30),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // Background scenery — clouds, stars.
              Positioned.fill(
                child: CustomPaint(painter: _HeroSceneryPainter()),
              ),
              // The blob mascot on the right.
              Positioned(
                right: 10,
                bottom: -10,
                top: 10,
                width: height * 0.78,
                child: Center(
                  child: Transform.translate(
                    offset: const Offset(8, 4),
                    child: CustomPaint(
                      size: Size(height * 0.6, height * 0.6),
                      painter: _BlobMascotPainter(),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: c.maxWidth * 0.55,
                    ),
                    child: _LeftColumn(
                      title: title,
                      subtitle: subtitle ?? game.subtitle,
                      onPlay: onPlay,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LeftColumn extends StatelessWidget {
  const _LeftColumn({
    required this.title,
    required this.subtitle,
    required this.onPlay,
  });

  final String title;
  final String subtitle;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.hero(
            fontSize: 24,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        GlossyGradientButton(
          label: 'Start Playing',
          onPressed: onPlay,
        ),
      ],
    );
  }
}

/// Background scenery — two stars + two faint clouds for a playful
/// sky behind the blob.
class _HeroSceneryPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Stars (top-left, mid-right).
    _paintStar(canvas, Offset(size.width * 0.18, size.height * 0.20), 12);
    _paintStar(canvas, Offset(size.width * 0.46, size.height * 0.12), 8);
    _paintStar(canvas, Offset(size.width * 0.62, size.height * 0.34), 10);

    // Faint clouds near the bottom for a "soft" feel.
    _paintCloud(canvas, Offset(-20, size.height * 0.85), size.width * 0.55, 36);
    _paintCloud(canvas, Offset(size.width * 0.6, size.height * 1.05),
        size.width * 0.5, 30);
  }

  void _paintStar(Canvas canvas, Offset c, double r) {
    final path = Path();
    const points = 5;
    final inner = r * 0.45;
    for (var i = 0; i < points * 2; i++) {
      final theta = -math.pi / 2 + i * math.pi / points;
      final rad = i.isEven ? r : inner;
      final pt = c + Offset(math.cos(theta) * rad, math.sin(theta) * rad);
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()..color = const Color(0xFFFFC837),
    );
  }

  void _paintCloud(Canvas canvas, Offset c, double w, double h) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35);
    final r = h * 0.4;
    canvas.drawCircle(c.translate(r, -r * 0.4), r, paint);
    canvas.drawCircle(c.translate(w * 0.5, -r * 0.8), r * 1.1, paint);
    canvas.drawCircle(c.translate(w * 0.8, -r * 0.3), r * 0.85, paint);
    canvas.drawCircle(
      c.translate(w * 0.95, r * 0.05),
      r * 0.7,
      paint,
    );
  }

  @override
  bool shouldRepaint(_HeroSceneryPainter old) => false;
}

/// Friendly "blob" mascot — a rounded cream-coloured character with
/// a happy face (eyes + smile + pink cheeks) sitting on a small
/// grass hill.
class _BlobMascotPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Soft drop shadow under the blob.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w / 2, h * 0.92),
        width: w * 0.8,
        height: h * 0.12,
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.18),
    );

    // Main blob body — a rounded "pebble" shape.
    final blob = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: const [
          Color(0xFFFFFFFF),
          Color(0xFFE0E7FF),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    final body = Path()
      ..moveTo(w * 0.18, h * 0.30)
      ..cubicTo(
        w * 0.18, h * 0.05,
        w * 0.82, h * 0.05,
        w * 0.82, h * 0.30,
      )
      ..cubicTo(
        w * 0.92, h * 0.55,
        w * 0.85, h * 0.95,
        w * 0.50, h * 0.95,
      )
      ..cubicTo(
        w * 0.15, h * 0.95,
        w * 0.08, h * 0.55,
        w * 0.18, h * 0.30,
      )
      ..close();
    canvas.drawPath(body, blob);

    // Eyes — two black ovals.
    final eyePaint = Paint()..color = const Color(0xFF1F2937);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.38, h * 0.42), width: 14, height: 18),
      eyePaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.62, h * 0.42), width: 14, height: 18),
      eyePaint,
    );
    // Eye highlights — small white dots.
    final highlightPaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(w * 0.40, h * 0.39), 3, highlightPaint);
    canvas.drawCircle(Offset(w * 0.64, h * 0.39), 3, highlightPaint);

    // Smile — open-mouth happy curve with a tongue.
    final smile = Paint()
      ..color = const Color(0xFF1F2937)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final mouthPath = Path()
      ..moveTo(w * 0.36, h * 0.58)
      ..quadraticBezierTo(w * 0.50, h * 0.78, w * 0.64, h * 0.58);
    canvas.drawPath(mouthPath, smile);

    // Cheeks — soft pink ovals.
    final cheekPaint = Paint()
      ..color = const Color(0xFFFF7AA8).withValues(alpha: 0.55);
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(w * 0.30, h * 0.55), width: 16, height: 10),
      cheekPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(w * 0.70, h * 0.55), width: 16, height: 10),
      cheekPaint,
    );

    // A tiny crown — three points + a base — sitting on the head.
    final crown = Paint()..color = const Color(0xFFFFC837);
    final crownPath = Path()
      ..moveTo(w * 0.34, h * 0.16)
      ..lineTo(w * 0.40, h * 0.04)
      ..lineTo(w * 0.46, h * 0.12)
      ..lineTo(w * 0.50, h * 0.00)
      ..lineTo(w * 0.54, h * 0.12)
      ..lineTo(w * 0.60, h * 0.04)
      ..lineTo(w * 0.66, h * 0.16)
      ..close();
    canvas.drawPath(crownPath, crown);
    // Crown jewels — small red dots on the three peaks.
    canvas.drawCircle(Offset(w * 0.40, h * 0.05), 2.5, Paint()..color = const Color(0xFFFF3B30));
    canvas.drawCircle(Offset(w * 0.50, h * 0.02), 2.5, Paint()..color = const Color(0xFF2563EB));
    canvas.drawCircle(Offset(w * 0.60, h * 0.05), 2.5, Paint()..color = const Color(0xFF22C55E));

    // Grass hill at the bottom.
    final hill = Paint()
      ..color = const Color(0xFF22C55E);
    final hillPath = Path()
      ..moveTo(0, h)
      ..quadraticBezierTo(w * 0.5, h * 0.85, w, h)
      ..close();
    canvas.drawPath(hillPath, hill);
  }

  @override
  bool shouldRepaint(_BlobMascotPainter old) => false;
}
