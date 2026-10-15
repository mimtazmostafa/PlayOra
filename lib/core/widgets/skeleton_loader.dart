import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../theme/app_colors.dart';

/// Shimmer placeholder. Pass a child that describes the layout you're loading
/// (use grey boxes / lines) — the shimmer sweeps over it.
class SkeletonLoader extends StatelessWidget {
  const SkeletonLoader({
    super.key,
    required this.child,
    this.baseColor,
    this.highlightColor,
    this.duration = const Duration(milliseconds: 1400),
  });

  final Widget child;
  final Color? baseColor;
  final Color? highlightColor;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = baseColor ??
        (isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariantLight);
    final highlight = highlightColor ??
        (isDark
            ? AppColors.surfaceDark.withValues(alpha: 0.9)
            : Colors.white);

    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      period: duration,
      child: child,
    );
  }
}

/// Convenience — a single rounded rectangle placeholder.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 16,
    this.borderRadius = 8,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariantLight,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}