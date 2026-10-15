import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

// Dark-mode canvas stops — deep indigo top → slightly lighter indigo
// bottom. Reads as the brand-correct background in night theme so
// surface text stays legible without the floating shapes fighting
// the foreground.
const Color _darkCanvasTop = Color(0xFF1A1E36);
const Color _darkCanvasBottom = Color(0xFF0F1424);

/// Paints the redesigned warm-pastel canvas (sky-blue → lavender) plus
/// a small constellation of faded floating shapes — game controllers,
/// stars, bubbles, d-pads — drifting on an 18-second sine loop.
///
/// Wrap any screen with [FloatingBackgroundShapes] inside a [Stack]; it
/// fills the available space behind its [child] (or paints-only when
/// [child] is null).
///
/// Designed for the **light** redesign surface. On dark surfaces the
/// shapes still draw, but at `floatingShapeOpacity = 0.10` they
/// effectively disappear against the navy background.
class FloatingBackgroundShapes extends StatefulWidget {
  const FloatingBackgroundShapes({
    super.key,
    this.child,
    this.seed = 7,
    this.shapeCount = 10,
  });

  /// Optional content stacked on top of the painted background.
  final Widget? child;

  /// Seed for deterministic shape placement so the canvas is stable
  /// across rebuilds.
  final int seed;

  /// Number of floating shapes to draw.
  final int shapeCount;

  @override
  State<FloatingBackgroundShapes> createState() =>
      _FloatingBackgroundShapesState();
}

class _FloatingBackgroundShapesState extends State<FloatingBackgroundShapes>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, _) => CustomPaint(
              painter: _FloatingBackgroundPainter(
                seed: widget.seed,
                shapeCount: widget.shapeCount,
                t: _ctrl.value,
                isDark: isDark,
              ),
            ),
          ),
        ),
        if (widget.child != null) widget.child!,
      ],
    );
  }
}

class _FloatingBackgroundPainter extends CustomPainter {
  _FloatingBackgroundPainter({
    required this.seed,
    required this.shapeCount,
    required this.t,
    required this.isDark,
  });

  final int seed;
  final int shapeCount;
  final double t;
  final bool isDark;

  static const List<Color> _lightPalette = [
    AppColors.categoryAccentAction, // coral pink
    AppColors.categoryAccentPuzzle, // cyan
    Color(0xFFFFC837),              // golden yellow
    AppColors.categoryAccentSports, // emerald
    AppColors.feature,              // pastel purple
    AppColors.play,                 // royal blue
  ];

  /// Same hues but with boosted saturation / brightness so the shapes
  /// still register against the deep-indigo dark canvas instead of
  /// disappearing into the navy.
  static const List<Color> _darkPalette = [
    Color(0xFFFF7A8E), // coral pink, lightened
    Color(0xFF67D6FF), // cyan, lightened
    Color(0xFFFFD86B), // golden yellow, lightened
    Color(0xFF66E59A), // emerald, lightened
    Color(0xFFBFA0FF), // pastel purple, lightened
    Color(0xFF7C99FF), // royal blue, lightened
  ];

  List<Color> get _palette => isDark ? _darkPalette : _lightPalette;

  // Per-shape deterministic parameters — computed once per seed so
  // the painter doesn't allocate or recompute them per frame.
  static final Map<int, List<_ShapeSpec>> _shapeCache = {};

  List<_ShapeSpec> _shapes() {
    final key = seed * 1000 + shapeCount + (isDark ? 50000 : 0);
    return _shapeCache.putIfAbsent(
      key,
      () => _buildShapes(seed, shapeCount, _palette),
    );
  }

  static List<_ShapeSpec> _buildShapes(
    int seed,
    int count,
    List<Color> palette,
  ) {
    final rng = math.Random(seed);
    return List.generate(count, (i) {
      return _ShapeSpec(
        baseX: rng.nextDouble(),
        baseY: rng.nextDouble(),
        radius: 14 + rng.nextDouble() * 26,
        color: palette[i % palette.length],
        phase: rng.nextDouble() * math.pi * 2,
        kind: i % 4,
      );
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Canvas gradient — same stops regardless of `t`. Dark mode paints
    // the deep-indigo brand canvas so on-surface text stays legible;
    // light mode keeps the warm-pastel gradient.
    final gradient = isDark
        ? const [_darkCanvasTop, _darkCanvasBottom]
        : const [
            AppColors.canvasTopLight,
            AppColors.canvasBottomLight,
          ];
    final bgPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        gradient,
      );
    canvas.drawRect(Offset.zero & size, bgPaint);

    // Floating shapes — only `dx`/`dy` and per-frame alpha differ.
    // In dark mode we lift the shape opacity so they register against
    // the navy backdrop instead of vanishing.
    final shapeOpacity = isDark
        ? AppColors.floatingShapeOpacity * 1.6
        : AppColors.floatingShapeOpacity;
    final shapePaint = Paint();
    final cutPaint = Paint();
    final highlightPaint = Paint()
      ..color = (isDark ? Colors.white : Colors.white)
            .withValues(alpha: shapeOpacity);
    final cutColor = (isDark ? const Color(0xFFB5C6FF) : const Color(0xFFEBF4FF))
        .withValues(alpha: shapeOpacity);

    for (final s in _shapes()) {
      final dx = math.sin(t * math.pi * 2 + s.phase) * 8;
      final dy = math.cos(t * math.pi * 2 + s.phase) * 8;
      final c = Offset(
        s.baseX * size.width + dx,
        s.baseY * size.height + dy,
      );
      shapePaint.color = s.color.withValues(alpha: shapeOpacity);
      final r = s.radius;

      switch (s.kind) {
        case 0:
          _paintBubble(canvas, c, r, shapePaint, highlightPaint);
          break;
        case 1:
          _paintStar(canvas, c, r, shapePaint);
          break;
        case 2:
          _paintDpad(canvas, c, r, shapePaint, cutPaint, cutColor);
          break;
        case 3:
          _paintPixel(canvas, c, r, shapePaint);
          break;
      }
    }
  }

  void _paintBubble(
    Canvas canvas,
    Offset c,
    double r,
    Paint fill,
    Paint highlight,
  ) {
    canvas.drawCircle(c, r, fill);
    canvas.drawCircle(c.translate(-r * 0.3, -r * 0.3), r * 0.25, highlight);
  }

  void _paintStar(Canvas canvas, Offset c, double r, Paint fill) {
    final path = Path();
    const points = 5;
    final inner = r * 0.45;
    for (var i = 0; i < points * 2; i++) {
      final theta = -math.pi / 2 + i * math.pi / points;
      final rad = i.isEven ? r : inner;
      final pt = c + Offset(math.cos(theta) * rad, math.sin(theta) * rad);
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    path.close();
    canvas.drawPath(path, fill);
  }

  void _paintDpad(
    Canvas canvas,
    Offset c,
    double r,
    Paint fill,
    Paint cut,
    Color cutColor,
  ) {
    final rrect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: c, width: r * 1.4, height: r * 1.4),
      Radius.circular(r * 0.2),
    );
    canvas.drawRRect(rrect, fill);
    cut.color = cutColor;
    canvas.drawRect(
      Rect.fromCenter(center: c, width: r * 0.3, height: r * 1.0),
      cut,
    );
    canvas.drawRect(
      Rect.fromCenter(center: c, width: r * 1.0, height: r * 0.3),
      cut,
    );
  }

  void _paintPixel(Canvas canvas, Offset c, double r, Paint fill) {
    final size = r * 1.2;
    final rect = Rect.fromCenter(center: c, width: size, height: size);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(0.3);
    canvas.translate(-c.dx, -c.dy);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(size * 0.18)),
      fill,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FloatingBackgroundPainter old) => old.t != t;
}

class _ShapeSpec {
  const _ShapeSpec({
    required this.baseX,
    required this.baseY,
    required this.radius,
    required this.color,
    required this.phase,
    required this.kind,
  });
  final double baseX;
  final double baseY;
  final double radius;
  final Color color;
  final double phase;
  final int kind; // 0 bubble, 1 star, 2 dpad, 3 pixel
}
