import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../data/models/game_model.dart';
import 'game_thumbnail.dart';

/// Horizontal scroll row of game thumbnails.
///
/// Shows a section title, a "See All" tap target, and up to [maxItems] games.
class CategoryRow extends StatelessWidget {
  const CategoryRow({
    super.key,
    required this.title,
    required this.games,
    required this.onTapGame,
    this.onSeeAll,
    this.maxItems = 5,
  });

  final String title;
  final List<Game> games;
  final ValueChanged<Game> onTapGame;
  final VoidCallback? onSeeAll;
  final int maxItems;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (games.isEmpty) return const SizedBox.shrink();

    final visible = games.take(maxItems).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (onSeeAll != null)
                TextButton(
                  onPressed: onSeeAll,
                  child: const Text('See All'),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            itemCount: visible.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (context, i) => GameThumbnail(
              game: visible[i],
              onTap: () => onTapGame(visible[i]),
            ),
          ),
        ),
      ],
    );
  }
}