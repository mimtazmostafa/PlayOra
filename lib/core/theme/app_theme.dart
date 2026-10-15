import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_typography.dart';

/// PlayNest App ThemeData (light + dark).
///
/// Color scheme encodes the playful 3D PlayNest brand roles:
///
/// * `primary`         → Royal Soft Blue (primary actions)
/// * `secondary`       → Vibrant Mint (PLAY actions / success)
/// * `tertiary`        → Warm Yellow (rewards / streaks)
/// * `error`           → Soft Coral (destructive)
///
/// Cards are squircle (24 dp radius) with soft drop-shadows. The
/// AppBar uses Poppins w800 for chunky display feel.
class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final background = isDark ? AppColors.backgroundDark : AppColors.backgroundLight;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final bodyColor = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;

    final colorScheme = ColorScheme(
      brightness: brightness,
      // Royal Soft Blue — primary brand colour for filled buttons,
      // active nav indicators, primary CTAs.
      primary: AppColors.play,
      onPrimary: Colors.white,
      primaryContainer: isDark
          ? const Color(0xFF1A2B5E)
          : const Color(0xFFE0E8FF),
      onPrimaryContainer: isDark
          ? const Color(0xFFD8E2FF)
          : AppColors.playInk,
      // Vibrant Mint — PLAY actions, positive feedback.
      secondary: AppColors.mint,
      onSecondary: isDark ? const Color(0xFF00281A) : Colors.white,
      secondaryContainer: isDark
          ? const Color(0xFF0E3B22)
          : const Color(0xFFD9F5E3),
      onSecondaryContainer: isDark
          ? const Color(0xFFB7F0C8)
          : const Color(0xFF0E5C2C),
      // Warm Yellow — streaks, rewards, achievements.
      tertiary: AppColors.reward,
      onTertiary: const Color(0xFF1A1625),
      tertiaryContainer: isDark
          ? const Color(0xFF4A3700)
          : const Color(0xFFFFF3D6),
      onTertiaryContainer: isDark
          ? const Color(0xFFFFE7A8)
          : AppColors.rewardInk,
      // Soft Coral — destructive, errors, "NEW" badges.
      error: AppColors.error,
      onError: Colors.white,
      errorContainer: isDark
          ? const Color(0xFF5E1F2E)
          : const Color(0xFFFCE3E3),
      onErrorContainer: isDark
          ? const Color(0xFFFFD2DC)
          : AppColors.errorInk,
      surface: surface,
      onSurface: bodyColor,
      onSurfaceVariant: isDark
          ? AppColors.textSecondaryDark
          : AppColors.textSecondaryLight,
      surfaceContainerHighest: isDark
          ? AppColors.surfaceVariantDark
          : AppColors.surfaceVariantLight,
      outline: isDark
          ? AppColors.outlineDark
          : AppColors.outlineLight,
      outlineVariant: isDark
          ? const Color(0xFF2A3760)
          : const Color(0xFFC7D2EE),
    );

    final textTheme = AppTypography.textTheme(bodyColor, bodyColor).copyWith(
      bodyMedium: AppTypography.inter(
        fontSize: 14,
        color: colorScheme.onSurfaceVariant,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      // Scaffold uses the brand background colour in both modes so
      // screens that don't paint their own background (BottomNavShell,
      // most secondary tabs) don't expose the underlying Android window
      // as a black surface in light mode. Home wraps its body in
      // [FloatingBackgroundShapes], which paints the redesigned warm
      // pastel gradient on top of this base, so the change is invisible
      // there — it only matters for surfaces without a custom paint.
      scaffoldBackgroundColor: background,
      canvasColor: background,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: bodyColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppTypography.poppins(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
          color: bodyColor,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 2,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shadowColor: isDark
            ? Colors.black.withValues(alpha: 0.35)
            : const Color(0xFF0F172A).withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
            color: isDark
                ? colorScheme.outline
                : colorScheme.outline.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
      ),
      // Capsule (stadium) buttons — matching the playful 3D PlayNest
      // spec's "Start Playing →" / "Play Now →" style. Both filled
      // and outlined variants share the shape so they swap cleanly.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: const StadiumBorder(),
          textStyle: AppTypography.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.1,
          ),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: const StadiumBorder(),
          side: BorderSide(color: colorScheme.outline),
          textStyle: AppTypography.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.1,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: const StadiumBorder(),
          elevation: 2,
          textStyle: AppTypography.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.1,
          ),
        ),
      ),
      // Subtle bounce on tap for any button theme — keeps the playful
      // arcade feel without the cost of continuous animations.
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}