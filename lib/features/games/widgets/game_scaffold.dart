import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/scale_tap_button.dart';

/// Unified game scaffold used by the mini-game catalogue.
///
/// Layout (top → bottom):
///
///   * **Header** — pastel-blue background (`#EAF4FF`) with a rounded
///     white "score card" on the left (dropshadow + 20 dp radius) for
///     the title + subtitle, and a row of circular icon buttons on
///     the right (back, settings, heart badge). Each button is a
///     [ScaleTapButton] so taps animate + fire light haptic + audio.
///   * **Canvas** — pastel blue/purple gradient backdrop that
///     replaces the plain dark fill that the games used to draw on.
///
/// Use as a drop-in for the in-game area of [GameContainerScreen]:
///
/// ```dart
/// GameScaffold(
///   title: 'WATER SORT',
///   subtitle: 'Lvl 3  •  Moves 12',
///   trailing: [...],
///   child: <myMiniGame>,
/// )
/// ```
class GameScaffold extends StatelessWidget {
  const GameScaffold({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing = const <Widget>[],
    this.backgroundVariant = GameScaffoldBackground.pastel,
    this.child,
  });

  /// Top-row title (e.g. "WATER SORT").
  final String title;

  /// Body content rendered inside the canvas area.
  final Widget? child;

  /// Smaller secondary label inside the score card (e.g. "Lvl 3" or
  /// "Moves 12"). Hidden when null.
  final String? subtitle;

  /// Optional content to show in the score card body, replacing the
  /// plain subtitle Text. Use when the caller needs a richer chip
  /// (e.g. dynamic score with an animated number).
  final Widget? leading;

  /// Trailing button row shown on the right of the header. Each
  /// entry should already be wrapped (or not) — anything you put in
  /// here is rendered as-is inside a spaced Row.
  final List<Widget> trailing;

  /// Canvas backdrop variant. [GameScaffoldBackground.pastel] is the
  /// default (light-mode-flavoured gradient). [nightArcade] and
  /// [outdoorSky] reuse the existing brand tokens in dark mode.
  final GameScaffoldBackground backgroundVariant;

  /// Pastel header background — icy light blue (`#EAF4FF`).
  static const Color headerBg = Color(0xFFEAF4FF);

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;

    final headerColor = isDark
        ? AppColors.nightArcadeGradientStart
        : headerBg;

    final canvasGradient = _canvasGradient(isDark);

    return Material(
      color: headerColor,
      child: Column(
        children: [
          _GameScaffoldHeader(
            title: title,
            subtitle: subtitle,
            leading: leading,
            trailing: trailing,
            isDark: isDark,
          ),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: canvasGradient,
              ),
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }

  LinearGradient _canvasGradient(bool isDark) {
    if (backgroundVariant == GameScaffoldBackground.nightArcade) {
      return const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppColors.nightArcadeGradientStart,
          AppColors.nightArcadeGradientEnd,
        ],
      );
    }
    if (backgroundVariant == GameScaffoldBackground.outdoorSky) {
      return const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppColors.outdoorSkyGradientStart,
          AppColors.outdoorSkyGradientEnd,
        ],
      );
    }
    // Default: pastel (light blue → light periwinkle).
    if (isDark) {
      return const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppColors.nightArcadeGradientStart,
          AppColors.nightArcadeGradientEnd,
        ],
      );
    }
    return const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0xFFEAF4FF),
        Color(0xFFE0E7FF),
      ],
    );
  }
}

/// Background variants for [GameScaffold]'s canvas area.
enum GameScaffoldBackground { pastel, nightArcade, outdoorSky }

// ─────────────────────────────────────────────────────────────────
// Header row
// ─────────────────────────────────────────────────────────────────

class _GameScaffoldHeader extends StatelessWidget {
  const _GameScaffoldHeader({
    required this.title,
    required this.subtitle,
    required this.leading,
    required this.trailing,
    required this.isDark,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> trailing;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimary(isDark ? Brightness.dark : Brightness.light);
    final textSecondary = AppColors.textSecondary(isDark ? Brightness.dark : Brightness.light);

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            // Title card — rounded white container with drop shadow.
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surfaceDark : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.10),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: leading ??
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
              ),
            ),
            const SizedBox(width: 12),
            // Trailing icon buttons.
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < trailing.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  trailing[i],
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Convenience: build a circular 40-dp icon button styled to match the
/// [GameScaffold] header. Wrap any tap callback.
class GameScaffoldIconButton extends StatelessWidget {
  const GameScaffoldIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.semanticsLabel,
    this.selected = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final String? semanticsLabel;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final bg = selected
        ? AppColors.play
        : (isDark ? AppColors.surfaceVariantDark : Colors.white);
    final fg = selected
        ? Colors.white
        : (isDark ? AppColors.textPrimaryDark : AppColors.playInk);

    return ScaleTapButton(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      padding: const EdgeInsets.all(10),
      color: bg,
      semanticsLabel: semanticsLabel ?? tooltip,
      child: Icon(icon, size: 20, color: fg),
    );
  }
}
