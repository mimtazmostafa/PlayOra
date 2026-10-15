import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';

/// Subtle top banner featuring **Mithu Da** (the friendly parrot mascot)
/// offering today's challenge hint.
///
/// The banner sits between the greeting header and the Hero "Game of
/// the Day" card on the Home dashboard.
///
/// Design notes:
///   * Soft purple tint (matches the "categories / features" role) so
///     it doesn't compete with the green PLAY button below.
///   * Mithu is rendered as a flat colored "P" mark inside a circle —
///     no bitmap assets ship with this widget, so the layout never
///     breaks on a missing asset. A real illustrated avatar swaps in
///     for the placeholder via the `avatar` slot when art is ready.
///   * One micro-animation only: a 4px vertical bob on the avatar
///     every 2.4s. Subdued by design — no continuous glowing/moving
///     backgrounds.
class MithuMascotBanner extends StatefulWidget {
  const MithuMascotBanner({
    super.key,
    required this.hint,
    this.avatar,
    this.onTap,
  });

  /// Daily hint copy. Bengali is supported out of the box thanks to
  /// the Noto Sans Bengali fallback chain in [AppTypography].
  final String hint;

  /// Optional custom avatar widget. Defaults to a "M" letter glyph
  /// inside a green circle (Mithu the Parrot mark).
  final Widget? avatar;

  /// Tap handler — typically wires through to the daily challenge
  /// card / Mithu's story screen.
  final VoidCallback? onTap;

  @override
  State<MithuMascotBanner> createState() => _MithuMascotBannerState();
}

class _MithuMascotBannerState extends State<MithuMascotBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bob = AnimationController(
    vsync: this,
    // 2.4s — slow enough that it reads as ambient, not distracting.
    duration: const Duration(milliseconds: 2400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final feature = AppColors.feature;

    return Semantics(
      label: 'Mithu daily hint',
      button: widget.onTap != null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            decoration: BoxDecoration(
              color: feature.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: feature.withValues(alpha: 0.22),
                width: 1,
              ),
            ),
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Avatar slot — gentle bob animation, no glow.
                AnimatedBuilder(
                  animation: _bob,
                  builder: (context, child) {
                    // 0 → 1 → 0 cosine sway, ±4px vertical.
                    final dy = -4.0 + 4.0 * (1 - _bob.value);
                    return Transform.translate(
                      offset: Offset(0, dy),
                      child: child,
                    );
                  },
                  child: _MithuAvatar(avatar: widget.avatar),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Mithu Da',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          // Yellow dot for streak/reward role — but
                          // here it doubles as a "live / daily" badge.
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: AppColors.reward,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.hint,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Avatar slot — circular, green (PLAY role), centered letter glyph
/// by default. Sized so it stays consistent regardless of the asset.
class _MithuAvatar extends StatelessWidget {
  const _MithuAvatar({this.avatar});

  final Widget? avatar;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: AppColors.play.withValues(alpha: 0.18),
        shape: BoxShape.circle,
        border: Border.all(
          color: AppColors.play.withValues(alpha: 0.55),
          width: 1.5,
        ),
      ),
      alignment: Alignment.center,
      child: avatar ??
          Text(
            'M',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppColors.playInk,
                  fontWeight: FontWeight.w900,
                ),
          ),
    );
  }
}
