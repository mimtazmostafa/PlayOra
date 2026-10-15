import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/models/game_category.dart';
import '../../../data/registry/game_registry.dart';
import 'vibrant_game_card.dart';

/// 2-column responsive grid of [VibrantGameCard]s with an optional
/// category filter row above it.
///
/// Used by both the Home screen (with all games) and the Categories
/// screen (with a category-restricted list). The grid is a Sliver so
/// the caller can drop it inside a `CustomScrollView` alongside other
/// slivers (hero, banners, etc.).
class RegistryGameGrid extends ConsumerStatefulWidget {
  const RegistryGameGrid({
    super.key,
    this.games,
    this.showCategoryFilter = false,
    this.crossAxisCount = 4,
    this.childAspectRatio = 0.78,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      0,
      AppSpacing.lg,
      AppSpacing.xxl,
    ),
  });

  /// Override the source list. Defaults to every non-daily game in
  /// the registry — dailies surface through [DailyChallengeCard].
  final List<RegistryGame>? games;

  /// When `true`, render the horizontally scrollable category filter
  /// row above the grid.
  final bool showCategoryFilter;

  final int crossAxisCount;
  final double childAspectRatio;
  final EdgeInsets padding;

  @override
  ConsumerState<RegistryGameGrid> createState() => _RegistryGameGridState();
}

class _RegistryGameGridState extends ConsumerState<RegistryGameGrid> {
  /// `null` means "All".
  GameCategory? _active;

  static const List<_FilterSpec> _filters = [
    _FilterSpec(label: 'All', wire: null, icon: Icons.apps_rounded),
    _FilterSpec(label: 'Puzzle', wire: 'puzzle', icon: Icons.extension_rounded),
    _FilterSpec(
        label: 'Arcade', wire: 'arcade', icon: Icons.sports_esports_rounded),
    _FilterSpec(label: 'Board', wire: 'board', icon: Icons.grid_4x4_rounded),
    _FilterSpec(
        label: 'Sports',
        wire: 'sports',
        icon: Icons.sports_cricket_rounded),
    _FilterSpec(label: 'Word', wire: 'word', icon: Icons.text_fields_rounded),
    _FilterSpec(
        label: 'Brain', wire: 'brain', icon: Icons.psychology_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final all = widget.games ?? GameRegistry.nonDaily;
    final filtered = _active == null
        ? all
        : all.where((g) => g.category == _active).toList(growable: false);

    return SliverMainAxisGroup(
      slivers: [
        if (widget.showCategoryFilter)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  itemCount: _filters.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final f = _filters[i];
                    final selected = f.wire == (_active?.wire ?? '');
                    return _FilterChip(
                      label: f.label,
                      icon: f.icon,
                      selected: selected,
                      onTap: () {
                        setState(() {
                          _active = f.wire == null
                              ? null
                              : GameCategory.fromWire(f.wire);
                        });
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        SliverPadding(
          padding: widget.padding,
          sliver: SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: widget.crossAxisCount,
              mainAxisSpacing: AppSpacing.md,
              crossAxisSpacing: AppSpacing.md,
              childAspectRatio: widget.childAspectRatio,
            ),
            itemCount: filtered.length,
            itemBuilder: (context, i) {
              final game = filtered[i];
              return VibrantGameCard(
                key: ValueKey(game.id),
                game: game,
                onTap: () => context.push('${AppRoutes.gamePlayer}/${game.id}'),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FilterSpec {
  const _FilterSpec({required this.label, required this.wire, required this.icon});
  final String label;
  final String? wire;
  final IconData icon;
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = selected ? theme.colorScheme.primary : theme.colorScheme.onSurface;
    final bg = selected
        ? theme.colorScheme.primary.withValues(alpha: 0.12)
        : theme.colorScheme.surface;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withValues(alpha: 0.5),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
