import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../profile/profile_controller.dart';
import '../../settings/settings_controller.dart';
import 'gamepad_logo.dart';

/// Top app bar for the Home + Categories screens.
///
/// Layout (left → right):
///
///   * **3D gamepad logo** — squircle tile with a Royal Soft Blue
///     gradient + gamepad silhouette.
///   * **Title block** — "PlayNest" (Poppins w900) + "Small Games.
///     Big Fun!" (Inter 12 sp secondary).
///   * **Player greeting** — "Hi, `name`" with the player's
///     full display name (not just an initial). Tapping pushes the
///     Profile route so the user can edit it.
///   * **Sound toggle** — flips the global `soundOn` flag.
///   * **Menu** — pushes the More tab.
///
/// All controls fire haptic feedback on tap.
class HomeTopBar extends ConsumerWidget {
  const HomeTopBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brightness = Theme.of(context).brightness;
    final name = ref.watch(profileControllerProvider);
    final controller = ref.read(profileControllerProvider.notifier);
    final initials = controller.initials;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const GamepadLogo(size: 48),
          const SizedBox(width: AppSpacing.md),
          const Expanded(
            child: _TitleBlock(),
          ),
          const SizedBox(width: AppSpacing.sm),
          _PlayerGreeting(name: name, initials: initials),
          const SizedBox(width: AppSpacing.xs),
          _SoundToggle(
            background: AppColors.surface(brightness),
          ),
          const SizedBox(width: AppSpacing.xs),
          _CircleIconButton(
            icon: Icons.menu_rounded,
            tooltip: 'Menu',
            onTap: () {
              HapticFeedback.selectionClick();
              context.push(AppRoutes.more);
            },
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Title + subtitle.
// ─────────────────────────────────────────────────────────────────

class _TitleBlock extends StatelessWidget {
  const _TitleBlock();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PlayNest',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.hero(
            fontSize: 22,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Small Games. Big Fun!',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 0.1,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Player greeting — circular monogram + full display name. Tap to
// open Profile so the user can edit the name.
// ─────────────────────────────────────────────────────────────────

class _PlayerGreeting extends StatelessWidget {
  const _PlayerGreeting({required this.name, required this.initials});

  final String name;
  final String initials;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Truncate display name to keep the bar tidy on narrow phones.
    final display = _truncate(name, 10);
    return Tooltip(
      message: 'Profile',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () {
            HapticFeedback.selectionClick();
            context.push(AppRoutes.profile);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
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
                        color: AppColors.play.withValues(alpha: 0.30),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initials,
                    style: AppTypography.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hi,',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.1,
                        ),
                      ),
                      Text(
                        display,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: theme.colorScheme.onSurface,
                          letterSpacing: -0.2,
                          height: 1.1,
                        ),
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

  static String _truncate(String value, int max) {
    if (value.length <= max) return value;
    return '${value.substring(0, max).trim()}…';
  }
}

// ─────────────────────────────────────────────────────────────────
// Sound toggle — pill button that flips the persisted soundOn flag.
// ─────────────────────────────────────────────────────────────────

class _SoundToggle extends ConsumerWidget {
  const _SoundToggle({required this.background});

  final Color background;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final notifier = ref.read(settingsControllerProvider.notifier);
    final theme = Theme.of(context);
    final on = settings.soundOn;
    return Material(
      color: background,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          HapticFeedback.selectionClick();
          notifier.setSoundOn(!on);
        },
        child: Tooltip(
          message: on ? 'Mute sound' : 'Enable sound',
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(
              on
                  ? Icons.volume_up_rounded
                  : Icons.volume_off_rounded,
              size: 20,
              color: on
                  ? AppColors.play
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Generic round icon button.
// ─────────────────────────────────────────────────────────────────

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: theme.colorScheme.surface,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, size: 20, color: theme.colorScheme.onSurface),
          ),
        ),
      ),
    );
  }
}