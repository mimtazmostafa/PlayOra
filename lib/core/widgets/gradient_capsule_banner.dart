import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Glossy gradient capsule banner used to replace the flat section
/// headers ("ACTION & ARCADE", "MATCH & PUZZLES", etc.) on the Home
/// screen.
///
/// Visual recipe:
///   * Full-bleed [gradient] (default: deep-coral → golden-yellow).
///   * Top highlight — a soft white sheen overlay at ~25% so the
///     capsule reads as a 3D pill, not a flat rectangle.
///   * Subtle multi-layer shadow for the floating effect.
///   * 3D-tilted icon slot on the right ([Transform] with a small
///     `rotateX` for depth).
class GradientCapsuleBanner extends StatelessWidget {
  const GradientCapsuleBanner({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  /// Bold uppercase title (e.g. "ACTION & ARCADE").
  final String title;

  /// Single-sentence subtitle.
  final String subtitle;

  /// Trailing icon — drawn with a small 3D tilt.
  final IconData icon;

  /// Banner fill — deep coral → golden yellow, glossy.
  static const LinearGradient _bannerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      AppColors.sectionBannerStart,
      AppColors.sectionBannerEnd,
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Container(
        height: 76,
        decoration: BoxDecoration(
          gradient: _bannerGradient,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          boxShadow: [
            BoxShadow(
              color: AppColors.sectionBannerStart.withValues(alpha: 0.30),
              blurRadius: 16,
              offset: const Offset(0, 8),
              spreadRadius: 0,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Top sheen highlight.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: const Alignment(-0.2, -1),
                    end: const Alignment(0.6, 0),
                    colors: [
                      Colors.white.withValues(alpha: 0.32),
                      Colors.white.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.92),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 3D-tilted icon — gentle rotateX for depth.
                  Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0012)
                      ..rotateY(-0.25),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Icon(icon, color: Colors.white, size: 24),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
