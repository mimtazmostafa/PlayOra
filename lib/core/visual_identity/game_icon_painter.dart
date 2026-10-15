import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'icon_recipe.dart';

/// Renders an [IconRecipe] as a tile-sized icon.
///
/// The painter is purely declarative — pass it the recipe and a size, and
/// you get a layered draw (background shape, optional inner ring, glyph on
/// top). The whole composition is normalized to a 1×1 canvas so it scales
/// cleanly to any thumbnail size.
///
/// This is the **generic** painter. The 6 flagship titles use the dedicated
/// `FlagshipIcons.byId(...)` painters instead — they share the same visual
/// language (white-at-92% glyphs, brand-colored backgrounds) but include
/// hand-tuned detail (the Ludo die, the Chess knight's eye, etc.).
class GameIconPainter extends CustomPainter {
  GameIconPainter(this.recipe);

  final IconRecipe recipe;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    _paintShape(canvas, rect);
    // A scene replaces the glyph — the scene already fills the tile,
    // so stamping a single glyph on top would muddy the composition.
    if (recipe.scene != IconRecipeScene.none) {
      _paintScene(canvas, rect);
    } else {
      _paintGlyph(canvas, rect);
    }
  }

  // 1) Background shape.
  void _paintShape(Canvas canvas, Rect rect) {
    final Paint paint = Paint()..color = recipe.background;
    switch (recipe.shape) {
      case IconRecipeShape.circle:
        canvas.drawCircle(rect.center, rect.shortestSide / 2, paint);
      case IconRecipeShape.roundedSquare:
        final double r = rect.shortestSide * 0.18;
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(r)),
          paint,
        );
      case IconRecipeShape.hexagon:
        canvas.drawPath(_hexagonPath(rect), paint);
      case IconRecipeShape.shield:
        canvas.drawPath(_shieldPath(rect), paint);
      case IconRecipeShape.ring:
        // Ring = filled circle with a white-painted hole.
        canvas.drawCircle(rect.center, rect.shortestSide / 2, paint);
        final double hole = rect.shortestSide * 0.32;
        final Paint holePaint = Paint()..color = const Color(0x33000000);
        canvas.drawCircle(rect.center, hole, holePaint);
      case IconRecipeShape.star:
        canvas.drawPath(_starPath(rect, 5), paint);
      case IconRecipeShape.diamond:
        canvas.drawPath(_diamondPath(rect), paint);
      case IconRecipeShape.triangle:
        canvas.drawPath(_trianglePath(rect), paint);
      case IconRecipeShape.cross:
        canvas.drawPath(_crossPath(rect), paint);
      case IconRecipeShape.leaf:
        canvas.drawPath(_leafPath(rect), paint);
      case IconRecipeShape.droplet:
        canvas.drawPath(_dropletPath(rect), paint);
      case IconRecipeShape.hexagonGrid:
        canvas.drawPath(_hexagonGridPath(rect), paint);
    }
  }

  // 2) Glyph on top.
  void _paintGlyph(Canvas canvas, Rect rect) {
    if (recipe.glyph == IconRecipeGlyph.none) return;
    final Color color = recipe.foreground ?? IconRecipe.defaultForeground;
    final Paint paint = Paint()..color = color;
    final Path glyph = _glyphPath(recipe.glyph, rect);

    if (recipe.tilt != 0) {
      canvas.save();
      canvas.translate(rect.center.dx, rect.center.dy);
      canvas.rotate(recipe.tilt);
      canvas.translate(-rect.center.dx, -rect.center.dy);
      canvas.drawPath(glyph, paint);
      canvas.restore();
    } else {
      canvas.drawPath(glyph, paint);
    }
  }

  // ── Scene composition ────────────────────────────────────────────────────
  //
  // Each scene is hand-built from primitives at normalized 0..1 coords
  // so the same composition scales cleanly from a 44px search-row tile
  // to a 96px detail-page hero. We always draw a soft shadow first
  // (using `Colors.black.withValues(alpha: 0.18)`) so the scene reads
  // as layered above the background gradient rather than printed on
  // it. Highlights use `Colors.white.withValues(alpha: 0.92)` to match
  // the flagship icons' vocabulary.

  // Common building blocks ────────────────────────────────────────────────

  Paint _shadowPaint() => Paint()
    ..color = const Color(0x2E000000)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.6);

  Paint _cardPaint(Color c) => Paint()..color = c;

  // 3) Scene.
  void _paintScene(Canvas canvas, Rect rect) {
    switch (recipe.scene) {
      case IconRecipeScene.none:
        return;
      case IconRecipeScene.memoryGrid:
        _paintMemoryGrid(canvas, rect);
      case IconRecipeScene.penaltyBox:
        _paintPenaltyBox(canvas, rect);
      case IconRecipeScene.ludoBoard:
        _paintLudoBoard(canvas, rect);
      case IconRecipeScene.bubbleCluster:
        _paintBubbleCluster(canvas, rect);
      case IconRecipeScene.blockStack:
        _paintBlockStack(canvas, rect);
    }
  }

  // ── Memory Match: 3×2 grid, two cards flipped to show glyphs ───────────
  void _paintMemoryGrid(Canvas canvas, Rect rect) {
    final double u = rect.shortestSide;
    final Rect inset = Rect.fromLTWH(
      rect.left + u * 0.10,
      rect.top + u * 0.10,
      u * 0.80,
      u * 0.80,
    );
    final double gap = u * 0.04;
    final double cw = (inset.width - gap * 2) / 3;
    final double ch = (inset.height - gap) / 2;
    final Color faceDown = Colors.white.withValues(alpha: 0.85);
    final Color faceEdge = Colors.white.withValues(alpha: 0.55);
    final Color heart = const Color(0xFFE91E63);
    final Color star = const Color(0xFFFBC02D);

    // Shadow pass under the whole grid (one soft drop).
    final RRect shadowRRect = RRect.fromRectAndRadius(
      inset,
      Radius.circular(u * 0.05),
    );
    canvas.drawRRect(shadowRRect.shift(const Offset(0, 1.0)), _shadowPaint());

    final List<_CardSlot> slots = <_CardSlot>[
      _CardSlot(0, 0, faceDown: true),
      _CardSlot(1, 0, glyphColor: heart, glyph: _CardGlyph.heart),
      _CardSlot(2, 0, faceDown: true),
      _CardSlot(0, 1, glyphColor: star, glyph: _CardGlyph.star),
      _CardSlot(1, 1, faceDown: true),
      _CardSlot(2, 1, faceDown: true),
    ];

    for (final _CardSlot slot in slots) {
      final Rect card = Rect.fromLTWH(
        inset.left + slot.col * (cw + gap),
        inset.top + slot.row * (ch + gap),
        cw,
        ch,
      );
      final RRect rr = RRect.fromRectAndRadius(
        card,
        Radius.circular(u * 0.025),
      );
      if (slot.faceDown) {
        canvas.drawRRect(rr, _cardPaint(faceDown));
        // Inner hairline so face-down cards read as "card backs".
        final RRect inner = RRect.fromRectAndRadius(
          card.deflate(u * 0.012),
          Radius.circular(u * 0.018),
        );
        canvas.drawRRect(inner, _cardPaint(faceEdge));
      } else {
        canvas.drawRRect(rr, _cardPaint(slot.glyphColor!));
        // White glyph centered on the flipped card.
        final Paint gp = Paint()..color = Colors.white;
        final Path glyph = _smallGlyphPath(
          slot.glyph!,
          card.deflate(u * 0.05),
        );
        canvas.drawPath(glyph, gp);
      }
    }
  }

  // ── Penalty Kick: goal corner, ball, glove silhouette ──────────────────
  void _paintPenaltyBox(Canvas canvas, Rect rect) {
    final double u = rect.shortestSide;

    // 1. Goal-frame outline (right side, partial).
    final Paint framePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = u * 0.035;
    final Path frame = Path()
      ..moveTo(rect.right - u * 0.08, rect.top + u * 0.12)
      ..lineTo(rect.right - u * 0.08, rect.top + u * 0.58)
      ..lineTo(rect.left + u * 0.20, rect.top + u * 0.58);
    canvas.drawPath(frame, framePaint);

    // 2. Net stripes (vertical hairlines inside the goal mouth).
    final Paint netPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = u * 0.012;
    final double netLeft = rect.left + u * 0.20;
    final double netRight = rect.right - u * 0.08;
    final double netTop = rect.top + u * 0.12;
    final double netBottom = rect.top + u * 0.58;
    for (double x = netLeft + u * 0.06;
        x < netRight;
        x += u * 0.07) {
      canvas.drawLine(Offset(x, netTop), Offset(x, netBottom), netPaint);
    }
    for (double y = netTop + u * 0.07; y < netBottom; y += u * 0.07) {
      canvas.drawLine(Offset(netLeft, y), Offset(netRight, y), netPaint);
    }

    // 3. Spot (penalty mark) on the pitch.
    final Paint spotPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85);
    canvas.drawCircle(
      Offset(rect.left + u * 0.34, rect.bottom - u * 0.22),
      u * 0.025,
      spotPaint,
    );

    // 4. Ball with shadow.
    final Offset ballCenter = Offset(rect.left + u * 0.42, rect.bottom - u * 0.32);
    canvas.drawCircle(ballCenter.translate(0, u * 0.012), u * 0.085, _shadowPaint());
    canvas.drawCircle(ballCenter, u * 0.085, _cardPaint(Colors.white));
    // Tiny pentagon hint.
    final Paint pentaPaint = Paint()
      ..color = recipe.background
      ..style = PaintingStyle.fill;
    final Path penta = _pentagonAt(ballCenter, u * 0.045);
    canvas.drawPath(penta, pentaPaint);

    // 5. Glove silhouette (bottom-right).
    final Paint glovePaint = Paint()
      ..color = const Color(0xFFFF7043);
    final Path glove = _glovePath(rect);
    canvas.drawPath(glove.shift(const Offset(0, 1.5)), _shadowPaint());
    canvas.drawPath(glove, glovePaint);
    // Glove highlight.
    final Paint gloveHi = Paint()
      ..color = Colors.white.withValues(alpha: 0.35);
    final Path gloveHiPath = _gloveHighlight(rect);
    canvas.drawPath(gloveHiPath, gloveHi);
  }

  // ── Ludo Royale: four quadrant triangles + center die ───────────────────
  void _paintLudoBoard(Canvas canvas, Rect rect) {
    final double u = rect.shortestSide;
    final Offset c = rect.center;
    final double inset = u * 0.12;

    // Quadrant arms (4 triangles meeting at center).
    final List<_Quad> quads = <_Quad>[
      _Quad(rect.left + inset, rect.top + inset, c.dx, c.dy, const Color(0xFFE53935)), // top-left red
      _Quad(c.dx, rect.top + inset, rect.right - inset, c.dy, const Color(0xFFFDD835)), // top-right yellow
      _Quad(rect.left + inset, c.dy, c.dx, rect.bottom - inset, const Color(0xFF43A047)), // bottom-left green
      _Quad(c.dx, c.dy, rect.right - inset, rect.bottom - inset, const Color(0xFF1E88E5)), // bottom-right blue
    ];
    for (final _Quad q in quads) {
      // Donut triangle: outer triangle minus a smaller inner triangle.
      final Path donut = Path()
        ..fillType = PathFillType.evenOdd
        ..moveTo(q.left, q.top)
        ..lineTo(q.right, q.top)
        ..lineTo(q.left, q.bottom)
        ..close()
        ..addPath(_innerTri(q), Offset.zero);
      canvas.drawPath(donut, _cardPaint(q.color));
      // Edge highlight (top).
      final Paint edge = Paint()
        ..color = Colors.white.withValues(alpha: 0.45)
        ..strokeWidth = u * 0.012
        ..style = PaintingStyle.stroke;
      canvas.drawPath(
        Path()
          ..moveTo(q.left + u * 0.005, q.top + u * 0.005)
          ..lineTo(q.right - u * 0.005, q.top + u * 0.005)
          ..lineTo(q.left + u * 0.005, q.bottom - u * 0.005),
        edge,
      );
    }

    // Central die.
    final double dieR = u * 0.16;
    final Rect die = Rect.fromCircle(center: c, radius: dieR);
    canvas.drawRRect(
      RRect.fromRectAndRadius(die.shift(const Offset(0, 1.2)), Radius.circular(dieR * 0.18)),
      _shadowPaint(),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(die, Radius.circular(dieR * 0.18)),
      _cardPaint(Colors.white),
    );
    // 5-pip die.
    final Paint pip = Paint()..color = recipe.background;
    final double pr = dieR * 0.18;
    final List<Offset> pips = <Offset>[
      Offset(die.left + dieR * 0.6, die.top + dieR * 0.6),
      Offset(die.right - dieR * 0.6, die.top + dieR * 0.6),
      Offset(c.dx, c.dy),
      Offset(die.left + dieR * 0.6, die.bottom - dieR * 0.6),
      Offset(die.right - dieR * 0.6, die.bottom - dieR * 0.6),
    ];
    for (final Offset p in pips) {
      canvas.drawCircle(p, pr, pip);
    }
  }

  Path _innerTri(_Quad q) {
    final double u = (q.right - q.left) * 0.55;
    return Path()
      ..moveTo(q.left + u, q.top + u)
      ..lineTo(q.right, q.top + u)
      ..lineTo(q.left + u, q.bottom)
      ..close();
  }

  // ── Bubble Pop: cluster of overlapping bubbles ──────────────────────────
  void _paintBubbleCluster(Canvas canvas, Rect rect) {
    final double u = rect.shortestSide;
    final Offset c = rect.center;
    final List<_Bubble> bubbles = <_Bubble>[
      _Bubble(Offset(c.dx - u * 0.20, c.dy - u * 0.06), u * 0.20, const Color(0xFFEF5350)),
      _Bubble(Offset(c.dx + u * 0.06, c.dy - u * 0.18), u * 0.18, const Color(0xFFFFCA28)),
      _Bubble(Offset(c.dx + u * 0.22, c.dy + u * 0.02), u * 0.16, const Color(0xFF66BB6A)),
      _Bubble(Offset(c.dx - u * 0.10, c.dy + u * 0.14), u * 0.17, const Color(0xFF42A5F5)),
      _Bubble(Offset(c.dx + u * 0.02, c.dy + u * 0.04), u * 0.14, const Color(0xFFAB47BC)),
      _Bubble(Offset(c.dx - u * 0.04, c.dy - u * 0.18), u * 0.10, const Color(0xFFFF7043)),
    ];
    // Shadow + bubble body + highlight per bubble.
    for (final _Bubble b in bubbles) {
      canvas.drawCircle(b.center.translate(0, u * 0.012), b.r, _shadowPaint());
      canvas.drawCircle(b.center, b.r, _cardPaint(b.color));
      // Glossy highlight: small white circle offset to upper-left.
      final Paint hi = Paint()..color = Colors.white.withValues(alpha: 0.55);
      canvas.drawCircle(
        b.center.translate(-b.r * 0.35, -b.r * 0.35),
        b.r * 0.22,
        hi,
      );
    }
  }

  // ── Block Puzzle: stack of tetrominos on a faint 3×3 grid ───────────────
  void _paintBlockStack(Canvas canvas, Rect rect) {
    final double u = rect.shortestSide;
    final Rect inset = Rect.fromLTWH(
      rect.left + u * 0.10,
      rect.top + u * 0.10,
      u * 0.80,
      u * 0.80,
    );
    final double gap = u * 0.025;
    final double cell = (inset.width - gap * 2) / 3;

    // Faint grid background.
    final Paint gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = u * 0.008;
    for (int r = 0; r < 3; r++) {
      for (int c = 0; c < 3; c++) {
        final Rect cellRect = Rect.fromLTWH(
          inset.left + c * (cell + gap),
          inset.top + r * (cell + gap),
          cell,
          cell,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(cellRect, Radius.circular(u * 0.012)),
          gridPaint,
        );
      }
    }

    // Tetrominos (L-shape bottom-left + horizontal bar top-right).
    final Paint piecePaint = Paint()..color = Colors.white;
    final Paint pieceHi = Paint()..color = Colors.white.withValues(alpha: 0.65);

    // L piece: (0,2) (0,1) (0,0) (1,0)
    final double cellSize = cell;
    final List<_Cell> lCells = <_Cell>[
      _Cell(0, 2, cellSize), _Cell(0, 1, cellSize), _Cell(0, 0, cellSize), _Cell(1, 0, cellSize),
    ];
    for (final _Cell cell in lCells) {
      final Rect cellRect = Rect.fromLTWH(
        inset.left + cell.c * (cell.s + gap),
        inset.top + cell.r * (cell.s + gap),
        cell.s,
        cell.s,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          cellRect.shift(const Offset(0, 1)),
          Radius.circular(u * 0.018),
        ),
        _shadowPaint(),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(cellRect, Radius.circular(u * 0.018)),
        piecePaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          cellRect.deflate(u * 0.012),
          Radius.circular(u * 0.010),
        ),
        pieceHi,
      );
    }

    // Bar piece: (1,0) (2,0)
    final List<_Cell> barCells = <_Cell>[
      _Cell(1, 0, cellSize), _Cell(2, 0, cellSize),
    ];
    for (final _Cell cell in barCells) {
      final Rect cellRect = Rect.fromLTWH(
        inset.left + cell.c * (cell.s + gap),
        inset.top + cell.r * (cell.s + gap),
        cell.s,
        cell.s,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          cellRect.shift(const Offset(0, 1)),
          Radius.circular(u * 0.018),
        ),
        _shadowPaint(),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(cellRect, Radius.circular(u * 0.018)),
        _cardPaint(const Color(0xFFFFCA28)),
      );
    }

    // Single square top-right (T-piece stem) — (2, 1)
    final Rect soloRect = Rect.fromLTWH(
      inset.left + 2 * (cell + gap),
      inset.top + 1 * (cell + gap),
      cell,
      cell,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        soloRect.shift(const Offset(0, 1)),
        Radius.circular(u * 0.018),
      ),
      _shadowPaint(),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(soloRect, Radius.circular(u * 0.018)),
      _cardPaint(const Color(0xFF42A5F5)),
    );
  }

  // Small reusable geometry helpers for scenes ────────────────────────────

  Path _smallGlyphPath(_CardGlyph g, Rect rect) {
    final Path p = Path();
    switch (g) {
      case _CardGlyph.heart:
        final double r = rect.width / 4;
        final Offset c = Offset(rect.center.dx, rect.top + r);
        p.moveTo(rect.center.dx, rect.bottom);
        p.quadraticBezierTo(rect.right, c.dy, rect.right, c.dy - r);
        p.arcToPoint(
          Offset(rect.center.dx, c.dy),
          radius: Radius.circular(r),
          clockwise: true,
        );
        p.arcToPoint(
          Offset(rect.left, c.dy - r),
          radius: Radius.circular(r),
          clockwise: true,
        );
        p.quadraticBezierTo(rect.left, c.dy, rect.center.dx, rect.bottom);
      case _CardGlyph.star:
        final double rOuter = rect.shortestSide / 2;
        final double rInner = rOuter * 0.42;
        final Offset c = rect.center;
        for (int i = 0; i < 5 * 2; i++) {
          final double r = i.isEven ? rOuter : rInner;
          final double a = -math.pi / 2 + i * (math.pi / 5);
          final double x = c.dx + r * math.cos(a);
          final double y = c.dy + r * math.sin(a);
          if (i == 0) {
            p.moveTo(x, y);
          } else {
            p.lineTo(x, y);
          }
        }
        p.close();
    }
    return p;
  }

  Path _pentagonAt(Offset c, double r) {
    final Path p = Path();
    for (int i = 0; i < 5; i++) {
      final double a = -math.pi / 2 + i * (2 * math.pi / 5);
      final double x = c.dx + r * math.cos(a);
      final double y = c.dy + r * math.sin(a);
      if (i == 0) {
        p.moveTo(x, y);
      } else {
        p.lineTo(x, y);
      }
    }
    p.close();
    return p;
  }

  Path _glovePath(Rect rect) {
    final double u = rect.shortestSide;
    final Path p = Path()
      ..moveTo(rect.right - u * 0.05, rect.bottom - u * 0.05)
      ..lineTo(rect.right - u * 0.05, rect.bottom - u * 0.18)
      ..quadraticBezierTo(
        rect.right - u * 0.05,
        rect.bottom - u * 0.30,
        rect.right - u * 0.16,
        rect.bottom - u * 0.30,
      )
      ..lineTo(rect.right - u * 0.30, rect.bottom - u * 0.30)
      ..quadraticBezierTo(
        rect.right - u * 0.40,
        rect.bottom - u * 0.30,
        rect.right - u * 0.40,
        rect.bottom - u * 0.20,
      )
      ..lineTo(rect.right - u * 0.40, rect.bottom - u * 0.05)
      ..close();
    return p;
  }

  Path _gloveHighlight(Rect rect) {
    final double u = rect.shortestSide;
    return Path()
      ..moveTo(rect.right - u * 0.07, rect.bottom - u * 0.08)
      ..lineTo(rect.right - u * 0.07, rect.bottom - u * 0.18)
      ..quadraticBezierTo(
        rect.right - u * 0.07,
        rect.bottom - u * 0.28,
        rect.right - u * 0.16,
        rect.bottom - u * 0.28,
      )
      ..lineTo(rect.right - u * 0.30, rect.bottom - u * 0.28)
      ..quadraticBezierTo(
        rect.right - u * 0.38,
        rect.bottom - u * 0.28,
        rect.right - u * 0.38,
        rect.bottom - u * 0.20,
      )
      ..lineTo(rect.right - u * 0.38, rect.bottom - u * 0.10);
  }

  // ── Shape geometry ──────────────────────────────────────────────────────

  Path _hexagonPath(Rect rect) {
    final double r = rect.shortestSide / 2;
    final Offset c = rect.center;
    final Path p = Path();
    for (int i = 0; i < 6; i++) {
      final double a = -math.pi / 2 + i * (math.pi / 3);
      final double x = c.dx + r * math.cos(a);
      final double y = c.dy + r * math.sin(a);
      if (i == 0) {
        p.moveTo(x, y);
      } else {
        p.lineTo(x, y);
      }
    }
    p.close();
    return p;
  }

  Path _shieldPath(Rect rect) {
    final double h = rect.height;
    final Path p = Path()
      ..moveTo(rect.left, rect.top)
      ..lineTo(rect.right, rect.top)
      ..lineTo(rect.right, rect.top + h * 0.55)
      ..quadraticBezierTo(
        rect.right, rect.bottom,
        rect.center.dx, rect.bottom,
      )
      ..quadraticBezierTo(
        rect.left, rect.bottom,
        rect.left, rect.top + h * 0.55,
      )
      ..close();
    return p;
  }

  Path _starPath(Rect rect, int points) {
    final double rOuter = rect.shortestSide / 2;
    final double rInner = rOuter * 0.42;
    final Offset c = rect.center;
    final Path p = Path();
    for (int i = 0; i < points * 2; i++) {
      final double r = i.isEven ? rOuter : rInner;
      final double a = -math.pi / 2 + i * (math.pi / points);
      final double x = c.dx + r * math.cos(a);
      final double y = c.dy + r * math.sin(a);
      if (i == 0) {
        p.moveTo(x, y);
      } else {
        p.lineTo(x, y);
      }
    }
    p.close();
    return p;
  }

  Path _diamondPath(Rect rect) {
    final Path p = Path()
      ..moveTo(rect.center.dx, rect.top)
      ..lineTo(rect.right, rect.center.dy)
      ..lineTo(rect.center.dx, rect.bottom)
      ..lineTo(rect.left, rect.center.dy)
      ..close();
    return p;
  }

  Path _trianglePath(Rect rect) {
    final Path p = Path()
      ..moveTo(rect.center.dx, rect.top)
      ..lineTo(rect.right, rect.bottom)
      ..lineTo(rect.left, rect.bottom)
      ..close();
    return p;
  }

  Path _crossPath(Rect rect) {
    final double t = rect.shortestSide * 0.32;
    final double cx = rect.center.dx;
    final double cy = rect.center.dy;
    final Path p = Path()
      ..addRect(Rect.fromLTRB(rect.left, cy - t / 2, rect.right, cy + t / 2))
      ..addRect(Rect.fromLTRB(cx - t / 2, rect.top, cx + t / 2, rect.bottom));
    return p;
  }

  Path _leafPath(Rect rect) {
    final Offset c = rect.center;
    final double r = rect.shortestSide / 2;
    final Path p = Path()
      ..moveTo(c.dx, rect.top)
      ..quadraticBezierTo(c.dx + r, c.dy, c.dx, rect.bottom)
      ..quadraticBezierTo(c.dx - r, c.dy, c.dx, rect.top)
      ..close();
    return p;
  }

  Path _dropletPath(Rect rect) {
    final double r = rect.shortestSide / 2;
    final Offset c = rect.center;
    final Path p = Path()
      ..moveTo(c.dx, rect.top)
      ..quadraticBezierTo(c.dx + r, c.dy * 0.95, c.dx + r, c.dy)
      ..arcToPoint(
        Offset(c.dx - r, c.dy),
        radius: Radius.circular(r),
        clockwise: true,
      )
      ..quadraticBezierTo(c.dx - r, c.dy * 0.95, c.dx, rect.top)
      ..close();
    return p;
  }

  Path _hexagonGridPath(Rect rect) {
    // Honeycomb: 7 hexes (1 center + 6 around).
    final Path p = Path();
    final double r = rect.shortestSide / 5;
    final Offset c = rect.center;
    p.addPath(_hexAt(c, r), Offset.zero);
    for (int i = 0; i < 6; i++) {
      final double a = i * (math.pi / 3);
      final Offset child = Offset(
        c.dx + r * math.sqrt(3) * math.cos(a),
        c.dy + r * math.sqrt(3) * math.sin(a),
      );
      p.addPath(_hexAt(child, r), Offset.zero);
    }
    return p;
  }

  Path _hexAt(Offset center, double r) {
    final Path p = Path();
    for (int i = 0; i < 6; i++) {
      final double a = -math.pi / 2 + i * (math.pi / 3);
      final double x = center.dx + r * math.cos(a);
      final double y = center.dy + r * math.sin(a);
      if (i == 0) {
        p.moveTo(x, y);
      } else {
        p.lineTo(x, y);
      }
    }
    p.close();
    return p;
  }

  // ── Glyph geometry (mostly simple shapes centered in the tile) ──────────

  Path _glyphPath(IconRecipeGlyph g, Rect rect) {
    final double inset = rect.shortestSide * 0.28;
    final Rect inner = Rect.fromLTWH(
      rect.left + inset,
      rect.top + inset,
      rect.width - inset * 2,
      rect.height - inset * 2,
    );
    final Path p = Path();
    switch (g) {
      case IconRecipeGlyph.none:
        return p;
      case IconRecipeGlyph.play:
        final double back = inner.width * 0.05;
        p
          ..moveTo(inner.left + back, inner.top)
          ..lineTo(inner.right, inner.center.dy)
          ..lineTo(inner.left + back, inner.bottom)
          ..close();
      case IconRecipeGlyph.heart:
        final double r = inner.width / 4;
        final Offset c = Offset(inner.center.dx, inner.top + r);
        p.moveTo(inner.center.dx, inner.bottom);
        p.quadraticBezierTo(inner.right, c.dy, inner.right, c.dy - r);
        p.arcToPoint(
          Offset(inner.center.dx, c.dy),
          radius: Radius.circular(r),
          clockwise: true,
        );
        p.arcToPoint(
          Offset(inner.left, c.dy - r),
          radius: Radius.circular(r),
          clockwise: true,
        );
        p.quadraticBezierTo(inner.left, c.dy, inner.center.dx, inner.bottom);
      case IconRecipeGlyph.star:
        return _starPath(inner, 5);
      case IconRecipeGlyph.bolt:
        final double w = inner.width;
        final double h = inner.height;
        p
          ..moveTo(inner.left + w * 0.55, inner.top)
          ..lineTo(inner.left + w * 0.15, inner.top + h * 0.55)
          ..lineTo(inner.left + w * 0.45, inner.top + h * 0.55)
          ..lineTo(inner.left + w * 0.35, inner.bottom)
          ..lineTo(inner.right, inner.top + h * 0.45)
          ..lineTo(inner.left + w * 0.55, inner.top + h * 0.45)
          ..close();
      case IconRecipeGlyph.lock:
        final double w = inner.width;
        final double h = inner.height;
        final double r = w * 0.18;
        final Rect body = Rect.fromLTRB(
          inner.left,
          inner.top + h * 0.45,
          inner.right,
          inner.bottom,
        );
        p.addRRect(
          RRect.fromRectAndRadius(body, Radius.circular(r)),
        );
        // Shackle.
        p.addPath(
          Path()
            ..addRRect(
              RRect.fromRectAndRadius(
                Rect.fromLTRB(
                  inner.left + w * 0.2,
                  inner.top,
                  inner.right - w * 0.2,
                  inner.top + h * 0.65,
                ),
                Radius.circular(r),
              ),
            )
            ..fillType = PathFillType.evenOdd,
          Offset.zero,
        );
      case IconRecipeGlyph.key:
        final double cy = inner.center.dy;
        final double r = inner.width * 0.18;
        p.addOval(Rect.fromCircle(center: Offset(inner.left + r, cy), radius: r));
        final Rect shaft = Rect.fromLTWH(
          inner.left + r * 1.5,
          cy - r * 0.35,
          inner.width - r * 1.5,
          r * 0.7,
        );
        p.addRect(shaft);
        p.addRect(Rect.fromLTWH(
          shaft.right - r * 0.6,
          shaft.bottom,
          r * 0.6,
          r * 0.7,
        ));
      case IconRecipeGlyph.brain:
        // Two stacked scallops — a deliberately abstract glyph.
        p.addOval(Rect.fromCenter(
          center: inner.center.translate(0, -inner.height * 0.1),
          width: inner.width * 0.85,
          height: inner.height * 0.55,
        ));
        p.addOval(Rect.fromCenter(
          center: inner.center.translate(0, inner.height * 0.1),
          width: inner.width * 0.85,
          height: inner.height * 0.55,
        ));
      case IconRecipeGlyph.dice:
        final double s = inner.width / 3;
        p.addRRect(RRect.fromRectAndRadius(
          inner,
          Radius.circular(s * 0.25),
        ));
      case IconRecipeGlyph.controller:
        final Rect body = Rect.fromCenter(
          center: inner.center,
          width: inner.width,
          height: inner.height * 0.6,
        );
        p.addRRect(RRect.fromRectAndRadius(
          body,
          Radius.circular(body.height / 2),
        ));
      case IconRecipeGlyph.music:
        final double w = inner.width;
        final double h = inner.height;
        p
          ..addRect(Rect.fromLTWH(
            inner.left + w * 0.45,
            inner.top,
            w * 0.1,
            h * 0.7,
          ))
          ..addOval(Rect.fromCircle(
            center: Offset(inner.left + w * 0.3, inner.bottom - w * 0.1),
            radius: w * 0.18,
          ));
      case IconRecipeGlyph.eye:
        final double r = inner.height / 2;
        p.addOval(Rect.fromCircle(center: inner.center, radius: r));
      case IconRecipeGlyph.shield:
        final Path sh = _shieldPath(inner);
        p.addPath(sh, Offset.zero);
      case IconRecipeGlyph.puzzle:
        final double t = inner.width / 3;
        p.addRect(inner);
        p.addOval(Rect.fromCircle(
          center: Offset(inner.left + t * 2.5, inner.top + t * 0.5),
          radius: t * 0.35,
        ));
      case IconRecipeGlyph.target:
        p.addOval(Rect.fromCircle(center: inner.center, radius: inner.width / 2));
      case IconRecipeGlyph.crown:
        final double w = inner.width;
        final Path crown = Path()
          ..moveTo(inner.left, inner.bottom)
          ..lineTo(inner.left, inner.top + w * 0.25)
          ..lineTo(inner.left + w * 0.25, inner.top)
          ..lineTo(inner.center.dx, inner.top + w * 0.25)
          ..lineTo(inner.right - w * 0.25, inner.top)
          ..lineTo(inner.right, inner.top + w * 0.25)
          ..lineTo(inner.right, inner.bottom)
          ..close();
        p.addPath(crown, Offset.zero);
      case IconRecipeGlyph.flag:
        final Path flag = Path()
          ..addRect(Rect.fromLTWH(
            inner.left + inner.width * 0.15,
            inner.top,
            inner.width * 0.08,
            inner.height,
          ))
          ..moveTo(inner.left + inner.width * 0.23, inner.top)
          ..lineTo(inner.right, inner.top + inner.height * 0.25)
          ..lineTo(inner.left + inner.width * 0.23, inner.top + inner.height * 0.5)
          ..close();
        p.addPath(flag, Offset.zero);
      case IconRecipeGlyph.paw:
        final double r = inner.width * 0.12;
        final Offset c = inner.center;
        // Pad.
        p.addOval(Rect.fromCenter(
          center: c.translate(0, r * 1.2),
          width: r * 2.4,
          height: r * 2,
        ));
        // Toes.
        for (int i = 0; i < 4; i++) {
          final double a = -math.pi * 0.85 + i * (math.pi * 0.55);
          final Offset toe = Offset(
            c.dx + r * 2.0 * math.cos(a),
            c.dy - r * 1.1 + r * math.sin(a) * 0.4,
          );
          p.addOval(Rect.fromCircle(center: toe, radius: r));
        }
    }
    return p;
  }

  @override
  bool shouldRepaint(covariant GameIconPainter old) {
    return old.recipe != recipe;
  }
}

/// Convenience widget that wraps [GameIconPainter] in a sized [CustomPaint].
class GameIconTile extends StatelessWidget {
  const GameIconTile({
    super.key,
    required this.recipe,
    this.size = 64,
  });

  final IconRecipe recipe;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: GameIconPainter(recipe)),
    );
  }
}

// Internal scene-only POD types. Kept tiny so the painter file stays the
// single source of truth for how a scene is composed.

enum _CardGlyph { heart, star }

class _CardSlot {
  const _CardSlot(this.col, this.row, {this.faceDown = false, this.glyph, this.glyphColor});
  final int col;
  final int row;
  final bool faceDown;
  final _CardGlyph? glyph;
  final Color? glyphColor;
}

class _Quad {
  const _Quad(this.left, this.top, this.right, this.bottom, this.color);
  final double left;
  final double top;
  final double right;
  final double bottom;
  final Color color;
}

class _Bubble {
  const _Bubble(this.center, this.r, this.color);
  final Offset center;
  final double r;
  final Color color;
}

class _Cell {
  const _Cell(this.c, this.r, this.s);
  final int c;
  final int r;
  final double s;
}
