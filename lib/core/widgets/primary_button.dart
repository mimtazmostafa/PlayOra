import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Filled, brand-primary CTA. Tinted on disabled; supports icons + loading.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final isDisabled = onPressed == null || loading;

    // The button is always filled with the brand purple (primary),
    // so its label + icon must be white in BOTH light and dark mode —
    // contrast must track the button's own surface, not the global
    // brightness. We force the colors here rather than relying on
    // theme.onPrimary so a future theme tweak can't silently regress.
    const onPrimary = AppColors.onColoredSurface;

    final child = loading
        ? const SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              valueColor: AlwaysStoppedAnimation<Color>(onPrimary),
            ),
          )
        : Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: onPrimary),
                AppSpacing.gapSm,
              ],
              // Expanded keeps the label from forcing the Row past
              // the parent's max width when squeezed inside a modal
              // (e.g. GamePauseOverlay's 360px ConstrainedBox).
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(color: onPrimary),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );

    final button = FilledButton(
      onPressed: isDisabled ? null : onPressed,
      child: child,
    );

    return expand
        ? SizedBox(width: double.infinity, child: button)
        : button;
  }
}