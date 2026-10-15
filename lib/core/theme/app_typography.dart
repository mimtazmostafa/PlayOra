import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Typography stack for the "PlayNest" playful 3D design system.
///
/// * Display / headlines / titles  → Poppins (heavier weights, tight
///   letter-spacing for chunkier display feel)
/// * Body / label                  → Inter
/// * Bangla glyph coverage         → Noto Sans Bengali (primary)
///                                  → Hind Siliguri (fallback)
///                                  → Poppins (last-resort latin)
///
/// Putting `Noto Sans Bengali` *first* in the fallback chain guarantees
/// that Bengali characters (e.g. "আজ কী খেলবে?") render with proper
/// joined-letter shaping instead of falling back to a glyph-less latin
/// face.
class AppTypography {
  AppTypography._();

  /// Ordered fallback chain. `google_fonts` returns a font that
  /// resolves glyphs via this list when the primary face misses a
  /// code-point (Bengali in particular).
  static const List<String> _banglaFallback = <String>[
    'Noto Sans Bengali',
    'Hind Siliguri',
    'Noto Sans',
    'sans-serif',
  ];

  /// Use for displayLarge/Medium/Small, headlineLarge/Medium/Small, titleLarge/Medium.
  static TextStyle poppins({
    required double fontSize,
    FontWeight fontWeight = FontWeight.w400,
    double? height,
    double? letterSpacing,
    Color? color,
  }) {
    return GoogleFonts.poppins(
      fontSize: fontSize,
      fontWeight: fontWeight,
      height: height,
      letterSpacing: letterSpacing,
      color: color,
    ).copyWith(
      fontFamilyFallback: _banglaFallback,
    );
  }

  /// Use for bodyLarge/Medium/Small, labelLarge/Medium/Small.
  static TextStyle inter({
    required double fontSize,
    FontWeight fontWeight = FontWeight.w400,
    double? height,
    double? letterSpacing,
    Color? color,
  }) {
    return GoogleFonts.inter(
      fontSize: fontSize,
      fontWeight: fontWeight,
      height: height,
      letterSpacing: letterSpacing,
      color: color,
    ).copyWith(
      fontFamilyFallback: _banglaFallback,
    );
  }

  /// Chunky hero banner style — used by the new home HeroBanner.
  /// Poppins w900 with negative letter-spacing for a friendly,
  /// compressed display look.
  static TextStyle hero({
    required double fontSize,
    Color? color,
  }) {
    return poppins(
      fontSize: fontSize,
      fontWeight: FontWeight.w900,
      letterSpacing: -0.4,
      color: color,
    );
  }

  /// Full Material 3 TextTheme — bumped weights + tighter letter-spacing
  /// for the chunkier "PlayNest" feel.
  static TextTheme textTheme(Color bodyColor, Color displayColor) {
    return TextTheme(
      displayLarge: poppins(fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: -0.6, color: displayColor),
      displayMedium: poppins(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: displayColor),
      displaySmall: poppins(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: displayColor),

      headlineLarge: poppins(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: displayColor),
      headlineMedium: poppins(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: displayColor),
      headlineSmall: poppins(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: displayColor),

      titleLarge: poppins(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: displayColor),
      titleMedium: poppins(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.1, color: displayColor),
      titleSmall: poppins(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: -0.1, color: displayColor),

      bodyLarge: inter(fontSize: 16, fontWeight: FontWeight.w400, height: 1.45, color: bodyColor),
      bodyMedium: inter(fontSize: 14, fontWeight: FontWeight.w400, height: 1.45, color: bodyColor),
      bodySmall: inter(fontSize: 12, fontWeight: FontWeight.w400, height: 1.4, color: bodyColor),

      labelLarge: inter(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.2, color: bodyColor),
      labelMedium: inter(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.2, color: bodyColor),
      labelSmall: inter(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: bodyColor),
    );
  }
}