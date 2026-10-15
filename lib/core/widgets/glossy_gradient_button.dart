import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_typography.dart';

/// Glossy 3D-style capsule CTA button.
///
/// Designed for the "Start Playing →" call-to-action on the Game of
/// the Day hero. Features:
///   * Capsule shape (StadiumBorder).
///   * [gradient] fill (default: white → warm cream).
///   * Top white sheen overlay (drawn inside the capsule) so the
///     button reads as a 3D pill, not a flat rectangle.
///   * Soft multi-layer drop-shadow.
///   * [AnimatedScale] 0.96 press feedback (120 ms).
///   * Haptic light-impact + `HapticFeedback.lightImpact` on tap.
class GlossyGradientButton extends StatefulWidget {
  const GlossyGradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.arrow_forward_rounded,
  });

  /// Visible label (e.g. "Start Playing").
  final String label;

  /// Tap handler.
  final VoidCallback onPressed;

  /// Trailing icon. Defaults to a forward arrow.
  final IconData icon;

  /// Default fill — warm yellow → golden yellow so the CTA pops on
  /// the sky-blue hero.
  static const LinearGradient _fill = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFD66B), Color(0xFFFFC837)],
  );

  @override
  State<GlossyGradientButton> createState() => _GlossyGradientButtonState();
}

class _GlossyGradientButtonState extends State<GlossyGradientButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {

    return AnimatedScale(
      scale: _pressed ? 0.96 : 1.0,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: Material(
        color: Colors.transparent,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            widget.onPressed();
          },
          onHighlightChanged: (v) {
            if (mounted) setState(() => _pressed = v);
          },
          child: Ink(
            decoration: BoxDecoration(
              gradient: GlossyGradientButton._fill,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.20),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Stack(
              children: [
                // Top sheen highlight.
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: const Alignment(0, 0.5),
                        colors: [
                          Colors.white.withValues(alpha: 0.55),
                          Colors.white.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.label,
                        style: AppTypography.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF6B4A00),
                          letterSpacing: -0.1,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        widget.icon,
                        size: 16,
                        color: const Color(0xFF6B4A00),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
