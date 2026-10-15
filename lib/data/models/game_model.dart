import 'package:playnest/core/visual_identity/icon_recipe.dart';

import 'game_category.dart';
import 'game_difficulty.dart';
import 'game_type.dart';

/// A playable game in the catalog.
///
/// Immutable; use [copyWith] to derive modified copies (e.g. toggling
/// `isFavorite` when user state changes).
class Game {
  const Game({
    required this.id,
    required this.title,
    required this.titleBangla,
    required this.category,
    required this.thumbnailAsset,
    required this.description,
    required this.difficulty,
    required this.avgSessionMinutes,
    required this.isOfflineAvailable,
    required this.isFavorite,
    required this.gameType,
    required this.entryPoint,
    this.howToPlay = '',
    this.isNew = false,
    this.isPopular = false,
    this.iconRecipe,
    this.comingSoon = false,
    this.showComingSoonBadge = true,
  });

  /// Stable unique id (slug) — used by the router and for `getById`.
  final String id;

  /// English title, e.g. "Sudoku Master".
  final String title;

  /// Bangla title for localized UI, e.g. "সুডোকু মাস্টার".
  final String titleBangla;

  final GameCategory category;

  /// Asset path for the catalog thumbnail, e.g. `assets/thumbs/sudoku.png`.
  /// Actual image assets are not bundled yet — placeholders only.
  final String thumbnailAsset;

  /// One-paragraph marketing / how-to-play blurb.
  final String description;

  final GameDifficulty difficulty;

  /// Average play session length — surfaced on the detail screen.
  final int avgSessionMinutes;

  /// Whether the game is playable without network after the first install.
  final bool isOfflineAvailable;

  /// Per-user favorite flag. The seed file ships `false` for every game;
  /// a future per-user Hive box will override this client-side.
  final bool isFavorite;

  /// Determines how [entryPoint] is interpreted.
  final GameType gameType;

  /// Route name for [GameType.nativeFlutter], or asset/URL path for
  /// [GameType.webview]. Treated as opaque by the model — the router /
  /// game-player code interprets it.
  final String entryPoint;

  /// Optional step-by-step "How to Play" blurb. Empty by default so older
  /// seed entries keep working; the details screen hides the section when
  /// it's blank.
  final String howToPlay;

  /// Editorial flag surfaced as a "NEW" corner ribbon on the card.
  /// Defaults to `false` so older seed entries and tests don't need to
  /// specify it.
  final bool isNew;

  /// Editorial flag surfaced as a "POPULAR" corner ribbon on the card.
  /// Defaults to `false` so older seed entries and tests don't need to
  /// specify it.
  final bool isPopular;

  /// Optional recipe describing how to paint this game's icon (shape,
  /// background color, glyph). Null on the 6 flagship titles — those
  /// use the dedicated `FlagshipIcons` painters instead.
  final IconRecipe? iconRecipe;

  /// `true` when this catalog entry has no playable module yet — the
  /// card renders greyscale + (when [showComingSoonBadge] is also
  /// true) a "Coming soon" badge, the details screen disables the
  /// Play button, and the player routes to
  /// [ComingSoonGameModule] (an honest placeholder) instead of any
  /// shared fallback. Defaults to `false` so the existing seed entries
  /// continue to behave as real games.
  final bool comingSoon;

  /// Editorial flag controlling only the COMING SOON corner ribbon.
  /// Split from [comingSoon] so the catalog can mark many games as
  /// "not yet playable" via the greyscale desaturation without every
  /// one of them shouting "COMING SOON" — the badge is reserved for
  /// the few titles we actively want to market as imminent. Defaults
  /// to `true` so existing seed entries keep their badge until
  /// explicitly opted out.
  final bool showComingSoonBadge;

  Game copyWith({
    String? id,
    String? title,
    String? titleBangla,
    GameCategory? category,
    String? thumbnailAsset,
    String? description,
    GameDifficulty? difficulty,
    int? avgSessionMinutes,
    bool? isOfflineAvailable,
    bool? isFavorite,
    GameType? gameType,
    String? entryPoint,
    String? howToPlay,
    bool? isNew,
    bool? isPopular,
    IconRecipe? iconRecipe,
    bool? comingSoon,
    bool? showComingSoonBadge,
  }) {
    return Game(
      id: id ?? this.id,
      title: title ?? this.title,
      titleBangla: titleBangla ?? this.titleBangla,
      category: category ?? this.category,
      thumbnailAsset: thumbnailAsset ?? this.thumbnailAsset,
      description: description ?? this.description,
      difficulty: difficulty ?? this.difficulty,
      avgSessionMinutes: avgSessionMinutes ?? this.avgSessionMinutes,
      isOfflineAvailable: isOfflineAvailable ?? this.isOfflineAvailable,
      isFavorite: isFavorite ?? this.isFavorite,
      gameType: gameType ?? this.gameType,
      entryPoint: entryPoint ?? this.entryPoint,
      howToPlay: howToPlay ?? this.howToPlay,
      isNew: isNew ?? this.isNew,
      isPopular: isPopular ?? this.isPopular,
      iconRecipe: iconRecipe ?? this.iconRecipe,
      comingSoon: comingSoon ?? this.comingSoon,
      showComingSoonBadge: showComingSoonBadge ?? this.showComingSoonBadge,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'titleBangla': titleBangla,
        'category': category.wire,
        'thumbnailAsset': thumbnailAsset,
        'description': description,
        'difficulty': difficulty.wire,
        'avgSessionMinutes': avgSessionMinutes,
        'isOfflineAvailable': isOfflineAvailable,
        'isFavorite': isFavorite,
        'gameType': gameType.wire,
        'entryPoint': entryPoint,
        'howToPlay': howToPlay,
        'isNew': isNew,
        'isPopular': isPopular,
        if (iconRecipe != null) 'iconRecipe': iconRecipe!.toWire(),
        'comingSoon': comingSoon,
        'showComingSoonBadge': showComingSoonBadge,
      };

  factory Game.fromJson(Map<String, dynamic> json) {
    return Game(
      id: (json['id'] ?? '') as String,
      title: (json['title'] ?? '') as String,
      titleBangla: (json['titleBangla'] ?? '') as String,
      category: GameCategory.fromWire(json['category'] as String?),
      thumbnailAsset: (json['thumbnailAsset'] ?? '') as String,
      description: (json['description'] ?? '') as String,
      difficulty: GameDifficulty.fromWire(json['difficulty'] as String?),
      avgSessionMinutes: (json['avgSessionMinutes'] ?? 5) as int,
      isOfflineAvailable: (json['isOfflineAvailable'] ?? false) as bool,
      isFavorite: (json['isFavorite'] ?? false) as bool,
      gameType: GameType.fromWire(json['gameType'] as String?),
      entryPoint: (json['entryPoint'] ?? '') as String,
      howToPlay: (json['howToPlay'] ?? '') as String,
      isNew: (json['isNew'] ?? false) as bool,
      isPopular: (json['isPopular'] ?? false) as bool,
      iconRecipe: IconRecipe.fromWire(json['iconRecipe']),
      comingSoon: (json['comingSoon'] ?? false) as bool,
      // Default `true` so existing seed entries keep their badge
      // until an editor opts the title out via the JSON field.
      showComingSoonBadge:
          (json['showComingSoonBadge'] ?? true) as bool,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Game && other.id == id);

  @override
  int get hashCode => id.hashCode;
}