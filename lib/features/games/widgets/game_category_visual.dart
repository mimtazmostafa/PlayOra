import 'package:flutter/material.dart';

import '../../../core/visual_identity/icon_recipe.dart';
import '../../../data/models/game_category.dart';
import 'flagship_icons.dart';

/// Visual identity for a [GameCategory] used by the card thumbnail.
///
/// Each category gets a distinct gradient + a representative Material
/// icon so cards read as different even before real thumbnail art is
/// bundled. The colors here are intentionally tuned to:
///   - stay legible against white text in the icon tile,
///   - differ in hue enough that two adjacent cards in a grid are
///     visually distinguishable at a glance,
///   - lean warm to cool from top genres (puzzle purple) to fast
///     action (racing violet) so the catalog has a natural color flow.
///
/// Keeping this in the same file as the small `gradientFor` /
/// `iconFor` static helpers makes the card widget thinner and gives
/// tests a single import surface to assert against.
class GameCategoryVisual {
  const GameCategoryVisual._({
    required this.gradient,
    required this.icon,
  });

  /// Two-stop gradient used as the card thumbnail background.
  final LinearGradient gradient;

  /// Centered icon — a metaphor for the category, not the game.
  final IconData icon;

  /// Default category for anything missing an explicit visual.
  /// Arcade is the most generic catch-all.
  static final GameCategory _defaultCategory = GameCategory.arcade;

  /// Visual mapping. Keep keys in sync with the [GameCategory] enum.
  static final Map<GameCategory, LinearGradient> _gradients =
      <GameCategory, LinearGradient>{
    GameCategory.puzzle: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF7C3AED), Color(0xFFA78BFA)],
    ),
    GameCategory.arcade: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFEC4899), Color(0xFFF87171)],
    ),
    GameCategory.brain: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF0D9488), Color(0xFF34D399)],
    ),
    GameCategory.sports: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF16A34A), Color(0xFFA3E635)],
    ),
    GameCategory.board: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFD97706), Color(0xFFFCD34D)],
    ),
    GameCategory.action: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFDC2626), Color(0xFFFB923C)],
    ),
    GameCategory.racing: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF6D28D9), Color(0xFFE879F9)],
    ),
    GameCategory.strategy: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF0E7490), Color(0xFF67E8F9)],
    ),
    GameCategory.educational: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF1D4ED8), Color(0xFF60A5FA)],
    ),
    GameCategory.word: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFBE185D), Color(0xFFFBCFE8)],
    ),
  };

  static final Map<GameCategory, IconData> _icons =
      <GameCategory, IconData>{
    GameCategory.puzzle: Icons.extension_rounded,
    GameCategory.arcade: Icons.sports_esports_rounded,
    GameCategory.brain: Icons.psychology_rounded,
    GameCategory.sports: Icons.sports_soccer_rounded,
    GameCategory.board: Icons.grid_view_rounded,
    GameCategory.action: Icons.bolt_rounded,
    GameCategory.racing: Icons.speed_rounded,
    GameCategory.strategy: Icons.account_balance_rounded,
    GameCategory.educational: Icons.school_rounded,
    GameCategory.word: Icons.text_fields_rounded,
  };

  /// IDs that get a hand-tuned custom-painted icon instead of the
  /// generic category icon. The card widget asks
  /// [flagshipIconFor] with the game's id and falls back to
  /// [iconFor] when this returns null.
  static const Set<String> flagshipIds = <String>{
    'ludo-royale',
    'carrom-clash',
    'call-break',
    'chess-master',
    'sudoku-master',
    'cricket-clash',
  };

  /// Returns the flagship icon widget for [gameId], or null if the
  /// game isn't a flagship. Caller is responsible for sizing.
  static Widget? flagshipIconFor(String gameId) {
    if (!flagshipIds.contains(gameId)) return null;
    return FlagshipIcons.build(id: gameId, size: 64);
  }

  /// Returns the gradient for [category]. Falls back to the
  /// arcade gradient if a future enum value isn't mapped yet.
  static LinearGradient gradientFor(GameCategory category) =>
      _gradients[category] ?? _gradients[_defaultCategory]!;

  /// Returns the *primary* color of the gradient for [category] —
  /// i.e. the deep end-stop, not the lighter secondary. Used by the
  /// card title underline accent so the short stripe beneath the
  /// game title visually matches the card thumbnail gradient.
  static Color accentColorFor(GameCategory category) {
    final LinearGradient gradient =
        _gradients[category] ?? _gradients[_defaultCategory]!;
    return gradient.colors.first;
  }

  /// Returns the icon for [category]. Falls back to the
  /// arcade icon if a future enum value isn't mapped yet.
  static IconData iconFor(GameCategory category) =>
      _icons[category] ?? _icons[_defaultCategory]!;

  /// Per-category IconRecipe so category tiles can use the new
  /// `GameIconPainter` system instead of Material glyphs. Keeps the
  /// visual language consistent with per-game recipe icons.
  static IconRecipe categoryRecipeFor(GameCategory category) {
    switch (category) {
      case GameCategory.puzzle:
        return const IconRecipe(
          shape: IconRecipeShape.hexagon,
          background: Color(0xFF7C3AED),
          glyph: IconRecipeGlyph.puzzle,
        );
      case GameCategory.arcade:
        return const IconRecipe(
          shape: IconRecipeShape.roundedSquare,
          background: Color(0xFFEC4899),
          glyph: IconRecipeGlyph.controller,
        );
      case GameCategory.brain:
        return const IconRecipe(
          shape: IconRecipeShape.circle,
          background: Color(0xFF0D9488),
          glyph: IconRecipeGlyph.brain,
        );
      case GameCategory.sports:
        return const IconRecipe(
          shape: IconRecipeShape.roundedSquare,
          background: Color(0xFF16A34A),
          glyph: IconRecipeGlyph.flag,
        );
      case GameCategory.board:
        return const IconRecipe(
          shape: IconRecipeShape.hexagonGrid,
          background: Color(0xFFD97706),
          glyph: IconRecipeGlyph.dice,
        );
      case GameCategory.action:
        return const IconRecipe(
          shape: IconRecipeShape.diamond,
          background: Color(0xFFDC2626),
          glyph: IconRecipeGlyph.bolt,
        );
      case GameCategory.racing:
        return const IconRecipe(
          shape: IconRecipeShape.leaf,
          background: Color(0xFF6D28D9),
          glyph: IconRecipeGlyph.target,
        );
      case GameCategory.strategy:
        return const IconRecipe(
          shape: IconRecipeShape.shield,
          background: Color(0xFF0E7490),
          glyph: IconRecipeGlyph.crown,
        );
      case GameCategory.word:
        return const IconRecipe(
          shape: IconRecipeShape.roundedSquare,
          background: Color(0xFF0F766E),
          glyph: IconRecipeGlyph.eye,
        );
      case GameCategory.educational:
        return const IconRecipe(
          shape: IconRecipeShape.circle,
          background: Color(0xFF1D4ED8),
          glyph: IconRecipeGlyph.key,
        );
    }
  }
}
