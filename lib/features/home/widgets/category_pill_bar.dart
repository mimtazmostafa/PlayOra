import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/registry/game_registry.dart';

/// Sticky bottom pill bar for jumping between the four Home sections
/// (ACTION & ARCADE / CASUAL & FUN / MATCH & PUZZLES / SPORTS &
/// TARGETS).
///
/// Redesigned: each pill has a bold pastel background, dark bold
/// typography, and a bouncy elastic animation on tap (320 ms
/// `Curves.elasticOut`, 1.0 → 1.15 → 1.0).
class CategoryPillBar extends StatelessWidget {
  const CategoryPillBar({
    super.key,
    required this.onJumpToSection,
    this.activeSection,
  });

  /// Called when the user taps a section pill. The Home screen
  /// scrolls its [CustomScrollView] to the matching section banner.
  final ValueChanged<GameCollection> onJumpToSection;

  /// Currently visible section — pill renders in highlighted state.
  final GameCollection? activeSection;

  static const List<_SectionSpec> _sections = [
    _SectionSpec(
      collection: GameCollection.actionArcade,
      label: 'Action',
      color: AppColors.categoryAccentAction,
      icon: Icons.flash_on_rounded,
    ),
    _SectionSpec(
      collection: GameCollection.casualFun,
      label: 'Casual',
      color: AppColors.categoryAccentCasual,
      icon: Icons.casino_rounded,
    ),
    _SectionSpec(
      collection: GameCollection.matchPuzzles,
      label: 'Puzzle',
      color: AppColors.categoryAccentPuzzle,
      icon: Icons.extension_rounded,
    ),
    _SectionSpec(
      collection: GameCollection.sportsTargets,
      label: 'Sports',
      color: AppColors.categoryAccentSports,
      icon: Icons.sports_baseball_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final surfaceColor = isLight
        ? Colors.white.withValues(alpha: 0.92)
        : theme.colorScheme.surface.withValues(alpha: 0.92);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: surfaceColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final s in _sections)
              _CategoryPill(
                spec: s,
                active: activeSection == s.collection,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onJumpToSection(s.collection);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionSpec {
  const _SectionSpec({
    required this.collection,
    required this.label,
    required this.color,
    required this.icon,
  });
  final GameCollection collection;
  final String label;
  final Color color;
  final IconData icon;
}

class _CategoryPill extends StatelessWidget {
  const _CategoryPill({
    required this.spec,
    required this.active,
    required this.onTap,
  });
  final _SectionSpec spec;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final color = spec.color;
    final activeBg = isLight ? color.withValues(alpha: 0.22) : color;
    final inactiveBg = color.withValues(alpha: 0.10);
    final bg = active ? activeBg : inactiveBg;
    final fg = isLight
        ? (active ? AppColors.textPrimaryLight : color)
        : (active ? Colors.white : color);

    // `key` swaps on each tap so TweenAnimationBuilder fires its
    // tween from 1.15 (overshoot) → 1.0 (settle) every press,
    // giving the elastic bounce.
    return GestureDetector(
      onTap: onTap,
      child: TweenAnimationBuilder<double>(
        key: ValueKey('${spec.label}-${DateTime.now().microsecondsSinceEpoch}'),
        tween: Tween(begin: 1.15, end: 1.0),
        duration: const Duration(milliseconds: 320),
        curve: Curves.elasticOut,
        builder: (context, scale, child) => Transform.scale(
          scale: scale.clamp(1.0, 1.18),
          child: child,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: isLight && !active
                ? Border.all(color: color.withValues(alpha: 0.25), width: 1)
                : null,
            boxShadow: active
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.45),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(spec.icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Text(
                spec.label,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
