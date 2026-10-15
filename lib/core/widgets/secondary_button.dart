import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Outlined, secondary CTA. Same shape as [PrimaryButton] so they swap cleanly.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18),
          AppSpacing.gapSm,
        ],
        // Expanded (not Flexible) so the label gets the remaining width
        // after the icon + gap. Without it the Row's intrinsic width
        // can exceed the available constraint when the button is
        // squeezed inside a modal (e.g. GamePauseOverlay's 360px
        // ConstrainedBox), causing a 5.5px RenderFlex overflow.
        Expanded(
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    final button = OutlinedButton(
      onPressed: onPressed,
      child: child,
    );

    return expand
        ? SizedBox(width: double.infinity, child: button)
        : button;
  }
}