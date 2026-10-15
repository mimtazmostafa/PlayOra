import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Recipe slot that drives the generic `GameIconPainter`.
///
/// A recipe is a small, declarative bundle of "draw this shape, in this
/// color, with this glyph on top". The painter turns it into a tile-sized
/// `CustomPaint` for any non-flagship game. The 6 flagship titles
/// bypass the recipe system and use the hand-tuned `FlagshipIcons` painters
/// instead (see `game_category_visual.flagshipIconFor`).
///
/// Recipes are intentionally tiny — they're a styling hook, not a graphics
/// engine. To design a new icon, pick one shape + one glyph + the brand
/// color slot and the painter does the rest.
@immutable
class IconRecipe {
  const IconRecipe({
    required this.shape,
    required this.background,
    this.foreground,
    this.glyph = IconRecipeGlyph.none,
    this.tilt = 0,
    this.scene = IconRecipeScene.none,
    this.accentUnderline,
  });

  /// The background tile shape (circle, rounded square, hexagon, etc.).
  final IconRecipeShape shape;

  /// Background fill for the tile. Usually a brand color or a category tint.
  final Color background;

  /// Foreground color for the glyph. Defaults to `Colors.white` at 92% opacity
  /// — the same tone used by the flagship icons so the two systems feel like
  /// one family.
  final Color? foreground;

  /// The glyph stamped on top of the shape. `none` draws a blank tile.
  final IconRecipeGlyph glyph;

/// Optional rotation in radians applied to the glyph (lets you tilt a
  /// sword, a chess piece, etc. without inventing a new shape).
  final double tilt;

  /// Optional richer illustration drawn instead of (or layered with) the
  /// single glyph. Lets the painter fill the tile with a small composed
  /// scene (a memory grid, a cluster of bubbles, a die on a Ludo quadrant)
  /// instead of a single centered icon. `none` keeps the original
  /// glyph-only behavior so every existing recipe still renders the same.
  final IconRecipeScene scene;

  /// Accent color used by the card's title underline. When non-null, the
  /// painter draws a short colored line beneath the title row on the card,
  /// tying the card artwork to the title. Null = no underline.
  final Color? accentUnderline;

  IconRecipe copyWith({
    IconRecipeShape? shape,
    Color? background,
    Color? foreground,
    IconRecipeGlyph? glyph,
    double? tilt,
    IconRecipeScene? scene,
    Color? accentUnderline,
  }) {
    return IconRecipe(
      shape: shape ?? this.shape,
      background: background ?? this.background,
      foreground: foreground ?? this.foreground,
      glyph: glyph ?? this.glyph,
      tilt: tilt ?? this.tilt,
      scene: scene ?? this.scene,
      accentUnderline: accentUnderline ?? this.accentUnderline,
    );
  }

  /// Default foreground for any recipe that doesn't override it.
  static Color get defaultForeground => const Color(0xFFFFFFEB);

  /// Decode a recipe from the JSON wire format used in `games_seed.json`.
  ///
  /// Wire shape (all fields optional except `shape` + `background`):
  /// ```json
  /// {
  ///   "shape": "hexagon",
  ///   "background": "#7C3AED",
  ///   "foreground": "#FFFFFF",
  ///   "glyph": "play",
  ///   "tilt": 0
  /// }
  /// ```
  /// Unknown tokens fall back to safe defaults so an old seed never crashes
  /// the painter.
  static IconRecipe? fromWire(Object? raw) {
    if (raw is! Map) return null;
    final IconRecipeShape? shape = IconRecipeShape.fromWire(raw['shape']);
    final Color? background = _parseColor(raw['background']);
    if (shape == null || background == null) return null;

    return IconRecipe(
      shape: shape,
      background: background,
      foreground: _parseColor(raw['foreground']),
      glyph: IconRecipeGlyph.fromWire(raw['glyph']) ?? IconRecipeGlyph.none,
      tilt: (raw['tilt'] is num) ? (raw['tilt'] as num).toDouble() : 0,
      scene: IconRecipeScene.fromWire(raw['scene']) ?? IconRecipeScene.none,
      accentUnderline: _parseColor(raw['accentUnderline']),
    );
  }

  /// Encode a recipe to the JSON wire format.
  Map<String, Object?> toWire() {
    return <String, Object?>{
      'shape': shape.wire,
      'background': _toHex(background),
      'foreground': foreground == null ? null : _toHex(foreground!),
      'glyph': glyph.wire,
      'tilt': tilt,
      'scene': scene == IconRecipeScene.none ? null : scene.wire,
      'accentUnderline':
          accentUnderline == null ? null : _toHex(accentUnderline!),
    };
  }

  static Color? _parseColor(Object? raw) {
    if (raw is String) {
      final String hex = raw.replaceFirst('#', '').trim();
      if (hex.length == 6) {
        final int? value = int.tryParse('FF$hex', radix: 16);
        if (value != null) return Color(value);
      } else if (hex.length == 8) {
        final int? value = int.tryParse(hex, radix: 16);
        if (value != null) return Color(value);
      }
      // Named brand colors.
      switch (hex.toLowerCase()) {
        case 'primary':
          return AppColors.primary;
        case 'accent':
          return AppColors.accent;
        case 'secondary':
          return AppColors.secondary;
        case 'streak':
          return AppColors.streak;
        case 'dailygold':
          return AppColors.dailyGold;
      }
    }
    return null;
  }

  static String _toHex(Color c) {
    final int r = (c.r * 255.0).round() & 0xFF;
    final int g = (c.g * 255.0).round() & 0xFF;
    final int b = (c.b * 255.0).round() & 0xFF;
    final int a = (c.a * 255.0).round() & 0xFF;
    return '#${(a << 24 | r << 16 | g << 8 | b).toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  }
}

/// The geometry of the background tile. Keep this list small — every new
/// shape has to be drawn by the painter and tested in CI.
enum IconRecipeShape {
  circle('circle'),
  roundedSquare('roundedSquare'),
  hexagon('hexagon'),
  shield('shield'),
  ring('ring'),
  star('star'),
  diamond('diamond'),
  triangle('triangle'),
  cross('cross'),
  leaf('leaf'),
  droplet('droplet'),
  hexagonGrid('hexagonGrid');

  const IconRecipeShape(this.wire);

  final String wire;

  static IconRecipeShape? fromWire(Object? raw) {
    if (raw is! String) return null;
    for (final IconRecipeShape shape in IconRecipeShape.values) {
      if (shape.wire == raw) return shape;
    }
    return null;
  }
}

/// The glyph stamped on top of the shape. Pair with a shape and you've
/// got an icon. Keep the glyphs simple — they're tiny shapes drawn at
/// painter scale, not Material icons.
enum IconRecipeGlyph {
  none('none'),
  play('play'),
  heart('heart'),
  star('star'),
  bolt('bolt'),
  lock('lock'),
  key('key'),
  brain('brain'),
  dice('dice'),
  controller('controller'),
  music('music'),
  eye('eye'),
  shield('shield'),
  puzzle('puzzle'),
  target('target'),
  crown('crown'),
  flag('flag'),
  paw('paw');

  const IconRecipeGlyph(this.wire);

  final String wire;

  static IconRecipeGlyph? fromWire(Object? raw) {
    if (raw is! String) return null;
    for (final IconRecipeGlyph glyph in IconRecipeGlyph.values) {
      if (glyph.wire == raw) return glyph;
    }
    return null;
  }
}
/// Optional scene drawn by the painter instead of (or layered over) the
/// single glyph. Each scene is a small composed illustration built from
/// shapes layered with shadow/depth so the tile reads as a fuller picture
/// of the game rather than one floating icon.
///
/// `none` keeps the legacy glyph-only rendering so every pre-existing
/// recipe continues to look the same.
enum IconRecipeScene {
  none('none'),

  /// 3×2 grid of rounded cards, two flipped showing a heart and a star,
  /// the rest face-down. Memory Match.
  memoryGrid('memoryGrid'),

  /// Spotlight on goal corner, net silhouette, ball, glove. Penalty Kick.
  penaltyBox('penaltyBox'),

  /// Four Ludo quadrant corners (red/yellow/green/blue) plus a die
  /// centerpiece. Ludo Royale.
  ludoBoard('ludoBoard'),

  /// Cluster of overlapping bubbles in three or four fills. Bubble Pop.
  bubbleCluster('bubbleCluster'),

  /// Stack of tetromino pieces on a faint 3×3 grid. Block Puzzle.
  blockStack('blockStack');

  const IconRecipeScene(this.wire);

  final String wire;

  static IconRecipeScene? fromWire(Object? raw) {
    if (raw is! String) return null;
    for (final IconRecipeScene scene in IconRecipeScene.values) {
      if (scene.wire == raw) return scene;
    }
    return null;
  }
}