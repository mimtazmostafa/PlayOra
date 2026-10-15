import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/secondary_button.dart';

/// In-game pause modal — shared by every playable game.
///
/// Hosts mount this however they prefer:
///   - As a [StatefulWidget] inside a `Stack` with a `bool _isPaused` flag
///   - Via [GamePauseOverlay.show], which uses [showGeneralDialog] for a
///     true fullscreen modal with its own scrim and barrier dismissal
///
/// The modal animates in with a fade + scale spring (240ms) and out with
/// the inverse. The Resume button closes the overlay; Quit to Details
/// pops the player screen and navigates to the game's details page;
/// Quit to Home pops back to the bottom-nav shell.
class GamePauseOverlay extends StatelessWidget {
  const GamePauseOverlay({
    super.key,
    required this.onResume,
    required this.onQuitToDetails,
    required this.onQuitToHome,
  });

  final VoidCallback onResume;
  final VoidCallback onQuitToDetails;
  final VoidCallback onQuitToHome;

  /// Show as a fullscreen modal dialog. Returns a [Future] that resolves
  /// when the dialog is dismissed (the user tapped Resume, the scrim,
  /// or hit the system back gesture).
  static Future<void> show(
    BuildContext context, {
    required Future<void> Function() onResume,
    required Future<void> Function() onQuitToDetails,
    required Future<void> Function() onQuitToHome,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Pause',
      barrierColor: Colors.black.withValues(alpha: 0.6),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (ctx, anim, secondary) {
        return GamePauseOverlay(
          onResume: () {
            Navigator.of(ctx).pop();
            onResume();
          },
          onQuitToDetails: () {
            Navigator.of(ctx).pop();
            onQuitToDetails();
          },
          onQuitToHome: () {
            Navigator.of(ctx).pop();
            onQuitToHome();
          },
        );
      },
      transitionBuilder: (ctx, anim, secondary, child) {
        final eased = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: eased,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(eased),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Container(
          margin: const EdgeInsets.all(AppSpacing.lg),
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            color: AppColors.surface(theme.brightness),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.pause_circle_filled_rounded,
                size: 56,
                color: theme.colorScheme.primary,
              ),
              AppSpacing.gapMd,
              Text(
                'Paused',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              AppSpacing.gapSm,
              Text(
                'Take a break. Your progress is safe.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary(theme.brightness),
                ),
                textAlign: TextAlign.center,
              ),
              AppSpacing.gapLg,
              PrimaryButton(
                label: 'Resume',
                icon: Icons.play_arrow_rounded,
                onPressed: onResume,
              ),
              AppSpacing.gapSm,
              SecondaryButton(
                label: 'Quit to Details',
                icon: Icons.info_outline_rounded,
                onPressed: onQuitToDetails,
              ),
              AppSpacing.gapSm,
              SecondaryButton(
                label: 'Quit to Home',
                icon: Icons.home_rounded,
                onPressed: onQuitToHome,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
