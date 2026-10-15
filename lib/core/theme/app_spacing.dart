import 'package:flutter/widgets.dart';

/// 8pt spacing scale.
/// Use these tokens (instead of raw doubles) so layout stays consistent.
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;   // 4
  static const double sm = 8;   // 8
  static const double md = 12;  // 12
  static const double lg = 16;  // 16
  static const double xl = 24;  // 24
  static const double xxl = 32; // 32
  static const double xxxl = 48;// 48

  // Common paddings / gaps as EdgeInsets for one-line use.
  static const EdgeInsets paddingSm = EdgeInsets.all(sm);
  static const EdgeInsets paddingMd = EdgeInsets.all(md);
  static const EdgeInsets paddingLg = EdgeInsets.all(lg);
  static const EdgeInsets paddingXl = EdgeInsets.all(xl);

  static const SizedBox gapXs = SizedBox(width: xs, height: xs);
  static const SizedBox gapSm = SizedBox(width: sm, height: sm);
  static const SizedBox gapMd = SizedBox(width: md, height: md);
  static const SizedBox gapLg = SizedBox(width: lg, height: lg);
  static const SizedBox gapXl = SizedBox(width: xl, height: xl);
  static const SizedBox gapXxl = SizedBox(width: xxl, height: xxl);

  // ───────── Border-radius constants ─────────
  /// Game card / general card body radius (24dp).
  static const double cardRadius = 24;
  /// Capsule (pill) radius — stadium border.
  static const double pillRadius = 999;
  /// Category accent badge radius.
  static const double badgeRadius = 14;
  /// Hero banner corner radius.
  static const double heroCornerRadius = 28;
  /// Floating bottom-nav radius.
  static const double navCornerRadius = 28;
}