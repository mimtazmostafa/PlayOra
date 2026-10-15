import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/game_category.dart';

/// Small rounded category-tag pill shown on top of [VibrantGameCard]
/// thumbnails. Maps a [GameCategory] to a short uppercase label and a
/// brand-friendly tint.
class CategoryTagPill extends StatelessWidget {
  const CategoryTagPill({
    super.key,
    required this.category,
    this.compact = true,
  });

  final GameCategory category;

  /// `true` → smaller padding for thumbnail overlays (default).
  /// `false` → looser padding for inline rows on the home screen.
  final bool compact;

  static const Map<GameCategory, String> _labels = {
    GameCategory.puzzle: 'PUZZLE',
    GameCategory.arcade: 'ARCADE',
    GameCategory.board: 'BOARD',
    GameCategory.sports: 'SPORTS',
    GameCategory.brain: 'BRAIN',
    GameCategory.word: 'WORD',
    GameCategory.action: 'ACTION',
    GameCategory.racing: 'RACING',
    GameCategory.strategy: 'STRATEGY',
    GameCategory.educational: 'EDU',
  };

  static const Map<GameCategory, Color> _accents = {
    GameCategory.puzzle: AppColors.feature,
    GameCategory.arcade: AppColors.play,
    GameCategory.board: AppColors.streak,
    GameCategory.sports: AppColors.accent,
    GameCategory.brain: AppColors.feature,
    GameCategory.word: AppColors.play,
    GameCategory.action: AppColors.error,
    GameCategory.racing: AppColors.streak,
    GameCategory.strategy: AppColors.feature,
    GameCategory.educational: AppColors.play,
  };

  @override
  Widget build(BuildContext context) {
    final label = _labels[category] ?? category.name.toUpperCase();
    final accent = _accents[category] ?? AppColors.feature;
    final hPad = compact ? 8.0 : 12.0;
    final vPad = compact ? 3.0 : 5.0;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: accent.withValues(alpha: 0.85),
          width: 1,
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
