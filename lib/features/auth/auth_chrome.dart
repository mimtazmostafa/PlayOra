import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// Shared visual elements for the auth surfaces (`SubscribeScreen`,
/// `LoginScreen`) so the user feels they're inside one unified
/// landing surface rather than two distinct screens.
///
/// Kept intentionally simple — pure `StatelessWidget`s that take
/// only the data they need to render. No controllers, no Riverpod.

// ─────────────────────────────────────────────────────────────────
// Backdrop — navy gradient + scattered stars. Used as the body of
// every auth screen so the marketing vibe is consistent.
// ─────────────────────────────────────────────────────────────────

class DarkNavyBackdrop extends StatelessWidget {
  const DarkNavyBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF0B1E45),
            Color(0xFF1E3A8A),
            Color(0xFF0B1E45),
          ],
        ),
      ),
      child: CustomPaint(
        painter: _StarsPainter(),
        size: Size.infinite,
      ),
    );
  }
}

class _StarsPainter extends CustomPainter {
  static final List<Offset> _stars = List.generate(60, (i) {
    final t = (i * 0.137) % 1.0;
    final s = (i * 0.293) % 1.0;
    return Offset(t * 720, s * 1280);
  });

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white.withValues(alpha: 0.45);
    for (final star in _stars) {
      final scaled = Offset(
        star.dx * size.width / 720,
        star.dy * size.height / 1280,
      );
      canvas.drawCircle(scaled, 1.2, p);
    }
  }

  @override
  bool shouldRepaint(_StarsPainter old) => false;
}

// ─────────────────────────────────────────────────────────────────
// Header — back chip + PlayNest wordmark.
// ─────────────────────────────────────────────────────────────────

class AuthHeader extends StatelessWidget {
  const AuthHeader({super.key, required this.showBack});
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (showBack)
          Material(
            color: Colors.white.withValues(alpha: 0.1),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () {
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                }
              },
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 18,
                  color: Colors.white,
                ),
              ),
            ),
          )
        else
          const SizedBox(width: 40),
        const Spacer(),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.play,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.sports_esports_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 8),
            RichText(
              text: TextSpan(
                style: AppTypography.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
                children: const [
                  TextSpan(text: 'Play', style: TextStyle(color: Colors.white)),
                  TextSpan(
                    text: 'Nest',
                    style: TextStyle(color: Color(0xFFFBBF24)),
                  ),
                ],
              ),
            ),
          ],
        ),
        const Spacer(),
        const SizedBox(width: 40),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Powered-by line.
// ─────────────────────────────────────────────────────────────────

class PoweredByBdApps extends StatelessWidget {
  const PoweredByBdApps({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text.rich(
        TextSpan(
          style: AppTypography.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.85),
            letterSpacing: 0.3,
          ),
          children: const [
            TextSpan(text: '✨ Powered by '),
            TextSpan(
              text: 'bdapps',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}
