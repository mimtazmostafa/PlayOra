import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Rounded card (16dp) with a soft elevation. Use for tappable list rows,
/// game tiles, stats blocks, etc.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = AppSpacing.paddingLg,
    this.onTap,
    this.borderColor,
    this.elevation = 1,
    this.borderRadius = 16,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? borderColor;
  final double elevation;
  final double borderRadius;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(borderRadius);

    final card = Material(
      color: color ?? theme.colorScheme.surface,
      elevation: elevation,
      shadowColor: theme.colorScheme.primary.withValues(alpha: 0.12),
      surfaceTintColor: Colors.transparent,
      borderRadius: radius,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(
            color: borderColor ?? theme.colorScheme.outline,
            width: 1,
          ),
        ),
        child: Padding(padding: padding, child: child),
      ),
    );

    if (onTap == null) return card;
    return InkWell(
      onTap: onTap,
      borderRadius: radius,
      child: card,
    );
  }
}