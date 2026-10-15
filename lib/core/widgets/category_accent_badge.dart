import 'package:flutter/material.dart';

import '../theme/app_typography.dart';

/// Top-left category accent pill badge.
///
/// Bold colored fill, white label, soft inner glow ring drawn via
/// [CustomPaint] so the pill reads as a "glowing" tag rather than a
/// flat chip. Used on every redesigned game card to anchor the
/// category colour at a glance.
class CategoryAccentBadge extends StatelessWidget {
  const CategoryAccentBadge({
    super.key,
    required this.label,
    required this.accent,
  });

  /// Short label like "ACTION", "PUZZLE", "SPORTS", "CASUAL".
  final String label;

  /// Section accent — drives both the fill and the inner glow colour.
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.45),
            blurRadius: 10,
            offset: const Offset(0, 3),
            spreadRadius: 0.5,
          ),
        ],
      ),
      child: Stack(
        children: [
          // Inner glow ring (drawn behind the text).
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _InnerGlowPainter(accent: accent)),
            ),
          ),
          Text(
            label,
            style: AppTypography.inter(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _InnerGlowPainter extends CustomPainter {
  _InnerGlowPainter({required this.accent});

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );
    // Soft inner highlight at the top edge.
    final highlight = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.45),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(Offset.zero & size);
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height * 0.55),
      highlight,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_InnerGlowPainter old) => old.accent != accent;
}
