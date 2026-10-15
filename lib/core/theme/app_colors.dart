import 'package:flutter/material.dart';

/// PlayNest — playful 3D-leaning visual identity.
///
/// Five brand roles drive every screen:
///
/// * **Royal Soft Blue** (`#4C73FF`) → Primary actions, navigation,
///   filled buttons. The dominant brand colour.
/// * **Pastel Purple** (`#A073FF`) → Categories, features,
///   secondary highlights.
/// * **Warm Yellow** (`#FFC837`) → Streaks, rewards, achievements.
/// * **Soft Coral** (`#FF6584`) → Destructive, errors, "NEW" badges.
/// * **Vibrant Mint** (`#30D158`) → Success, positive feedback, "PLAY"
///   states.
///
/// Each role ships with an "ink" variant (deeper shade) used for chip
/// foregrounds in light mode so labels stay legible on tinted surfaces.
class AppColors {
  AppColors._();

  // ───────── Brand roles ─────────
  /// Royal Soft Blue — the primary brand colour. Use for filled
  /// buttons, the active bottom-nav indicator, and primary CTAs.
  static const Color play = Color(0xFF4C73FF);
  /// Deeper royal blue for chip foregrounds in light mode.
  static const Color playInk = Color(0xFF3B62F6);

  /// Pastel Purple — categories, features, secondary highlights.
  static const Color feature = Color(0xFFA073FF);
  /// Deeper purple for chip foregrounds in light mode.
  static const Color featureInk = Color(0xFF7C4DFF);

  /// Warm Yellow — streaks, rewards, achievements.
  static const Color reward = Color(0xFFFFC837);
  /// Deeper gold for chip foregrounds in light mode.
  static const Color rewardInk = Color(0xFFA07A00);

  // ───────── HUD framework tokens (capsule redesign) ─────────
  /// Soft indigo used as the active-button background in the top HUD
  /// bar (Pause, Sound, etc.). Slightly lighter than [play] so the
  /// capsule reads as a distinct surface instead of merging with the
  /// brand primary.
  static const Color hudIndigo = Color(0xFF4E6CF5);

  /// Vivid yellow used for accent text inside HUD chips (timer counts,
  /// score numerals, level flag foregrounds). Distinct from
  /// [reward] / [warmYellow] so the HUD reads as a separate visual
  /// layer rather than a reward badge.
  static const Color hudAccentYellow = Color(0xFFFFC529);

  /// Night-arcade canvas gradient — deep indigo top → slightly lighter
  /// indigo bottom. Used as the default fallback background for action
  /// and puzzle games.
  static const Color nightArcadeGradientStart = Color(0xFF1E1B4B);
  static const Color nightArcadeGradientEnd = Color(0xFF312E81);

  /// Outdoor / sports canvas gradient — sky blue top → deeper sky
  /// blue bottom. Used for sports and outdoor-themed games.
  static const Color outdoorSkyGradientStart = Color(0xFF38BDF8);
  static const Color outdoorSkyGradientEnd = Color(0xFF0284C7);

  /// Soft drop-shadow opacity used by floating HUD capsules. Picked
  /// once here so every HUD element lands the same shadow strength.
  static const double hudCapsuleShadowOpacity = 0.15;

  /// Vibrant Mint Green — success, positive feedback, "PLAY" CTAs.
  static const Color mint = Color(0xFF30D158);

  /// Soft Coral — destructive, errors, "NEW" badges with warmth.
  static const Color coral = Color(0xFFFF6584);

  // ───────── Semantic aliases (used elsewhere) ─────────
  /// Alias for [feature] so existing callers keep working. (Will be
  /// phased out in favour of [feature].)
  static const Color primary = feature;
  /// Alias for [play] so existing callers keep working. (Will be
  /// phased out in favour of [play].)
  static const Color secondary = play;
  /// Alias for [reward] so existing callers keep working. (Will be
  /// phased out in favour of [reward].)
  static const Color accent = reward;

  /// Error / destructive — uses [coral] for the warm PlayNest feel.
  static const Color error = coral;

  /// Streak flame — orange-red. Reuses [coral] for consistency.
  static const Color streak = coral;

  /// Daily-challenge trophy — distinct gold accent used only by the
  /// daily-completion overlay so it doesn't clash with the level-up
  /// purple.
  static const Color dailyGold = Color(0xFFFACC15);

  // ───────── Surfaces (Dark, default) ─────────
  // Deep navy background with lifted navy surface tokens so cards
  // visibly "float" off the background. Pure charcoal was too cold;
  // the navy hue matches the new Royal Soft Blue brand colour.
  static const Color backgroundDark = Color(0xFF0F1424);
  static const Color surfaceDark = Color(0xFF1B2440);
  static const Color surfaceVariantDark = Color(0xFF243056);
  static const Color textPrimaryDark = Color(0xFFFFFFFF);
  static const Color textSecondaryDark = Color(0xFFB8C2E0);
  static const Color outlineDark = Color(0xFF3A4870);

  /// Royal blue accent for dark-mode primary states.
  static const Color royalBlue = Color(0xFF4C73FF);
  /// Pastel purple accent for dark-mode secondary.
  static const Color pastelPurple = Color(0xFFA073FF);
  /// Warm yellow accent for dark-mode rewards.
  static const Color warmYellow = Color(0xFFFFC837);

  // ───────── Surfaces (Light) ─────────
  // Soft icy-tint background behind cool-tinted surface cards. The
  // icy hue (slight blue undertone) keeps the light theme feeling
  // cool and modern rather than warm-grey. [backgroundLight] and
  // [surfaceLight] are intentionally distinct shades — the background
  // sits a few steps darker than the surface so cards visibly
  // "lift off" the page instead of reading as flat white slabs.
  // This preserves the premium brand feel in light mode.
  static const Color backgroundLight = Color(0xFFEAEEF9);
  static const Color surfaceLight = Color(0xFFFBFBFE);
  static const Color surfaceVariantLight = Color(0xFFE8EEFB);
  static const Color textPrimaryLight = Color(0xFF0E1730);
  static const Color textSecondaryLight = Color(0xFF5A6B95);
  static const Color outlineLight = Color(0xFFD8E0F5);

  /// Foreground to use on a *colored* surface (filled button,
  /// gradient card, badge chip) for the given [Brightness]. Always
  /// white in both modes so contrast doesn't track the global theme.
  static const Color onColoredSurface = Color(0xFFFFFFFF);

  /// Royal Soft Blue ink used as the foreground of pill chips
  /// (`primary.withValues(alpha: 0.15)` background) in light mode.
  /// Kept as a backwards-compatible alias for [playInk].
  static const Color primaryInk = playInk;

  /// Slightly darker gold used as the foreground of the coin / accent
  /// chip in light mode. Kept as a backwards-compatible alias for
  /// [rewardInk].
  static const Color accentInk = rewardInk;

  /// Slightly darker streak orange for chip foregrounds in light mode.
  static const Color streakInk = Color(0xFFA83403);

  /// Darker green for chip foregrounds in light mode.
  static const Color secondaryInk = Color(0xFF0E5C2C);

  /// Darker red for chip foregrounds in light mode.
  static const Color errorInk = Color(0xFF8C1414);

  // ───────── Convenience accessors ─────────
  /// Text primary for the current brightness.
  static Color textPrimary(Brightness b) =>
      b == Brightness.dark ? textPrimaryDark : textPrimaryLight;

  /// Text secondary for the current brightness.
  static Color textSecondary(Brightness b) =>
      b == Brightness.dark ? textSecondaryDark : textSecondaryLight;

  /// Background for the current brightness.
  static Color background(Brightness b) =>
      b == Brightness.dark ? backgroundDark : backgroundLight;

  /// Surface (card/appbar) for the current brightness.
  static Color surface(Brightness b) =>
      b == Brightness.dark ? surfaceDark : surfaceLight;

  /// Slightly lifted surface (the "surface variant" token).
  static Color surfaceVariant(Brightness b) => b == Brightness.dark
      ? surfaceVariantDark
      : surfaceVariantLight;

  /// Outline (1dp) color for elevated surfaces.
  static Color outline(Brightness b) => b == Brightness.dark
      ? outlineDark
      : outlineLight;

  // ───────── Redesigned light canvas & category accents ─────────
  /// Warm pastel gradient top stop — sky blue, used as the canvas
  /// behind the redesigned Home surface.
  static const Color canvasTopLight = Color(0xFFEBF4FF);
  /// Warm pastel gradient bottom stop — soft lavender.
  static const Color canvasBottomLight = Color(0xFFF5EFFF);

  /// Opacity for floating decorative shapes drifting on the canvas.
  /// Tuned to ~10% so the surface stays clean but feels alive.
  static const double floatingShapeOpacity = 0.10;

  /// Category accent — Coral Pink (Action & Arcade badges).
  static const Color categoryAccentAction = Color(0xFFFF5A6E);
  /// Category accent — Cyan (Match & Puzzles badges).
  static const Color categoryAccentPuzzle = Color(0xFF22B8FF);
  /// Category accent — Emerald Green (Sports & Targets badges).
  static const Color categoryAccentSports = Color(0xFF22C55E);
  /// Category accent — Warm Yellow (Casual & Fun badges).
  static const Color categoryAccentCasual = Color(0xFFFFC837);

  /// Section banner glossy gradient — Deep Coral → Golden Yellow.
  static const Color sectionBannerStart = Color(0xFFFF5A4D);
  static const Color sectionBannerEnd = Color(0xFFFFC837);

  /// Game of the Day hero 3D gradient — vivid red → orange.
  static const Color heroGradientStart = Color(0xFFFF3B30);
  static const Color heroGradientEnd = Color(0xFFFF6B00);

  /// Bottom nav: vibrant blue for the selected tab indicator.
  static const Color navSelected = Color(0xFF2563EB);
  /// Bottom nav: muted foreground for unselected tabs (light theme).
  static const Color navUnselectedLight = Color(0xFF5A6B95);

  /// Multi-layered card drop-shadow colour (Offset(0,8), spread 2,
  /// blur 16). 10% black so cards visibly float without looking heavy.
  static const Color cardShadowColor = Color(0x1A000000);
}

/// Brightness-resolved variant of [kGamePanel].
Color kGamePanelOf(BuildContext context) =>
    AppColors.surfaceVariant(Theme.of(context).brightness);
