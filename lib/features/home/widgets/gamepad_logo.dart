import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Gamepad logo — a 3D-feeling controller silhouette inside a squircle
/// tile. Designed to live at the top-left of the HomeTopBar.
///
/// Visual recipe (top → bottom):
///
///   * Squircle tile (12 dp radius) with a Royal Soft Blue gradient.
///   * Gamepad silhouette (rounded body + two grip nubs + d-pad + 4
///     small action buttons + center start pill) drawn in white.
///   * Tiny mint accent dot on the action button cluster so the logo
///     reads as "alive" rather than monochrome.
///
/// The painter is sized to the parent's box — pass any [size].
class GamepadLogo extends StatelessWidget {
  const GamepadLogo({super.key, this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.play,
            AppColors.playInk,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.play.withValues(alpha: 0.35),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: CustomPaint(
        painter: _GamepadLogoPainter(),
        size: Size.square(size),
      ),
    );
  }
}

class _GamepadLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final white = Paint()..color = Colors.white;

    // Gamepad body — rounded rectangle with two grip nubs.
    final w = size.width;
    final h = size.height;
    final pad = w * 0.12;

    // Main body.
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(pad, h * 0.32, w - pad * 2, h * 0.42),
      Radius.circular(w * 0.12),
    );
    canvas.drawRRect(body, white);

    // Left grip.
    final leftGrip = RRect.fromRectAndRadius(
      Rect.fromLTWH(pad * 0.3, h * 0.38, pad * 0.9, h * 0.4),
      Radius.circular(w * 0.1),
    );
    canvas.drawRRect(leftGrip, white);

    // Right grip.
    final rightGrip = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        w - pad * 0.3 - pad * 0.9,
        h * 0.38,
        pad * 0.9,
        h * 0.4,
      ),
      Radius.circular(w * 0.1),
    );
    canvas.drawRRect(rightGrip, white);

    // D-pad (left cluster) — cross shape.
    final dpadColor = Paint()..color = AppColors.play.withValues(alpha: 0.95);
    final dpadCx = w * 0.32;
    final dpadCy = h * 0.55;
    final dpadThick = w * 0.05;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(dpadCx, dpadCy),
          width: dpadThick * 2.2,
          height: dpadThick * 1.2,
        ),
        Radius.circular(dpadThick * 0.4),
      ),
      dpadColor,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(dpadCx, dpadCy),
          width: dpadThick * 1.2,
          height: dpadThick * 2.2,
        ),
        Radius.circular(dpadThick * 0.4),
      ),
      dpadColor,
    );

    // Action buttons (right cluster) — 4 tiny circles.
    final btnColor = Paint()..color = AppColors.mint;
    final btnCx = w * 0.66;
    final btnCy = h * 0.52;
    final btnR = w * 0.045;
    final btnGap = w * 0.08;
    final buttons = [
      Offset(btnCx, btnCy - btnGap),
      Offset(btnCx + btnGap, btnCy),
      Offset(btnCx, btnCy + btnGap),
      Offset(btnCx - btnGap, btnCy),
    ];
    for (final p in buttons) {
      canvas.drawCircle(p, btnR, btnColor);
    }

    // Center start pill — small horizontal pill between the dpad and
    // the action buttons.
    final startColor = Paint()..color = AppColors.play.withValues(alpha: 0.95);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(w * 0.49, h * 0.53),
          width: w * 0.1,
          height: h * 0.05,
        ),
        Radius.circular(w * 0.04),
      ),
      startColor,
    );
  }

  @override
  bool shouldRepaint(_GamepadLogoPainter old) => false;
}