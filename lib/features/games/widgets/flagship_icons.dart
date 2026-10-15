import 'package:flutter/material.dart';

/// Hand-tuned icons for the six flagship catalog titles.
///
/// Every painter draws inside a 1×1 logical unit square (origin
/// top-left, +x right, +y down) and is scaled by the host [CustomPaint].
/// Keeping the canvas normalized lets us reuse the painters inside
/// any square frame without per-painter offsets.
///
/// Visual weight intentionally matches the generic category icons
/// shipped by [GameCategoryVisual]: opaque white at 92% so the icon
/// reads as part of the same family. The "extra polish" comes from
/// the silhouette and composition — not from a heavier stroke or
/// bolder fill.
class FlagshipIcons {
  const FlagshipIcons._();

  /// Render the flagship icon for [id] inside [size].
  ///
  /// Returns null when [id] is not a flagship — callers should fall
  /// back to the generic category icon in that case.
  static Widget? build({
    required String id,
    required double size,
  }) {
    final painter = painterFor(id);
    if (painter == null) return null;
    return CustomPaint(
      size: Size.square(size),
      painter: painter,
    );
  }

  static CustomPainter? painterFor(String id) {
    switch (id) {
      case 'ludo-royale':
        return const _LudoBoardPainter();
      case 'carrom-clash':
        return const _CarromPainter();
      case 'call-break':
        return const _CallBreakPainter();
      case 'chess-master':
        return const _ChessKnightPainter();
      case 'sudoku-master':
        return const _SudokuGridPainter();
      case 'cricket-clash':
        return const _CricketPainter();
      default:
        return null;
    }
  }
}

/// All painters render white at 92% opacity so they sit visually
/// alongside the generic Material icons on the same gradient surface.
const Color _flagshipFill = Color(0xFFFFFFEB); // 92% white

// ---------------------------------------------------------------------------
// Ludo — 4-color quadrant board + a die in the center.
// ---------------------------------------------------------------------------

class _LudoBoardPainter extends CustomPainter {
  const _LudoBoardPainter();

  // Traditional Ludo quadrant colors. Used as fills on the four
  // home yards so the board reads as the actual game at a glance,
  // not a generic 4-tile grid.
  static const _red = Color(0xFFEF4444);
  static const _green = Color(0xFF22C55E);
  static const _yellow = Color(0xFFFACC15);
  static const _blue = Color(0xFF3B82F6);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final unit = s / 16;
    final stroke = Paint()
      ..color = _flagshipFill
      ..style = PaintingStyle.stroke
      ..strokeWidth = unit * 0.6;

    // 1. Outer cross outline — single closed shape so the home arms
    //    and the cross stem read as one continuous board.
    final outer = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, 16 * unit, 16 * unit),
        Radius.circular(unit * 0.6),
      ));
    canvas.drawPath(outer, stroke);

    // 2. Four colored home yards at each 6×6 corner — the filled
    //    inner yard (3×3) is the actual "home" a piece sits on
    //    before being released onto the track. The outer corner
    //    gets the traditional Ludo player color.
    _paintYard(
      canvas,
      Rect.fromLTWH(0, 0, 6 * unit, 6 * unit),
      _red,
      unit,
    );
    _paintYard(
      canvas,
      Rect.fromLTWH(10 * unit, 0, 6 * unit, 6 * unit),
      _blue,
      unit,
    );
    _paintYard(
      canvas,
      Rect.fromLTWH(0, 10 * unit, 6 * unit, 6 * unit),
      _yellow,
      unit,
    );
    _paintYard(
      canvas,
      Rect.fromLTWH(10 * unit, 10 * unit, 6 * unit, 6 * unit),
      _green,
      unit,
    );

    // 3. Inner center square — the "centre home" the pieces race
    //    into at the end. Outlined only.
    canvas.drawRect(
      Rect.fromLTWH(6 * unit, 6 * unit, 4 * unit, 4 * unit),
      stroke,
    );

    // 4. Central die — a filled rounded square with five pips. The
    //    five-pip face is intentional: it implies "rolling well"
    //    and is visually busier than a three-pip face.
    final dieRect = Rect.fromCenter(
      center: Offset(8 * unit, 8 * unit),
      width: 3.6 * unit,
      height: 3.6 * unit,
    );
    // Soft drop shadow behind the die so it floats off the board.
    canvas.drawRRect(
      RRect.fromRectAndRadius(dieRect.shift(Offset(0, unit * 0.25)),
          Radius.circular(unit * 0.5)),
      Paint()
        ..color = const Color(0x44000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.6),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(dieRect, Radius.circular(unit * 0.5)),
      Paint()..color = _flagshipFill,
    );
    _paintPips(canvas, dieRect, unit);
  }

  /// Paints a filled colored 6×6 home arm with a smaller filled
  /// rounded inner yard (3×3) and a darker accent triangle so the
  /// four colors feel like four distinct "home bases" instead of
  /// just four flat tiles.
  void _paintYard(Canvas canvas, Rect arm, Color color, double unit) {
    // Soft drop shadow under the colored tile so the board has
    // some depth between the white outline and the colored fill.
    canvas.drawRect(
      arm.shift(Offset(0, unit * 0.2)),
      Paint()
        ..color = const Color(0x33000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.5),
    );
    // Filled colored square (with a thin inset so it sits inside
    // the white outline).
    final inset = arm.deflate(unit * 0.6);
    canvas.drawRect(
      inset,
      Paint()..color = color.withValues(alpha: 0.92),
    );
    // Inner yard — 3×3, deeper tinted.
    final yardRect = Rect.fromLTWH(
      arm.left + unit * 0.5,
      arm.top + unit * 0.5,
      3 * unit,
      3 * unit,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(yardRect, Radius.circular(unit * 0.4)),
      Paint()..color = Colors.white.withValues(alpha: 0.30),
    );
  }

  /// Paints the five-pip pattern (the "five" face) inside [die].
  /// The four corner pips + a center pip — a busier, more
  /// visually-interesting face than the default 1 or 3.
  void _paintPips(Canvas canvas, Rect die, double unit) {
    final pipPaint = Paint()..color = const Color(0xFF7C3AED);
    final pipR = unit * 0.38;
    final cx = die.center.dx;
    final cy = die.center.dy;
    final inset = unit * 0.9;
    void pip(double x, double y) =>
        canvas.drawCircle(Offset(x, y), pipR, pipPaint);
    pip(die.left + inset, die.top + inset);
    pip(die.right - inset, die.top + inset);
    pip(cx, cy);
    pip(die.left + inset, die.bottom - inset);
    pip(die.right - inset, die.bottom - inset);
  }

  @override
  bool shouldRepaint(covariant _LudoBoardPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Carrom — wooden board square with corner pockets + a striker disc.
// ---------------------------------------------------------------------------

class _CarromPainter extends CustomPainter {
  const _CarromPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final unit = s / 12;
    final stroke = Paint()
      ..color = _flagshipFill
      ..style = PaintingStyle.stroke
      ..strokeWidth = unit * 0.55;

    // Outer square board with rounded corners.
    final board = Rect.fromLTWH(unit, unit, 10 * unit, 10 * unit);
    canvas.drawRRect(
      RRect.fromRectAndRadius(board, Radius.circular(unit * 0.8)),
      stroke,
    );

    // Inner playing field — slightly inset.
    final inner = board.deflate(unit * 1.2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(inner, Radius.circular(unit * 0.4)),
      Paint()
        ..color = _flagshipFill.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = unit * 0.3,
    );

    // Four corner pockets — small circles.
    final pocketPaint = Paint()..color = _flagshipFill;
    final pocketR = unit * 0.55;
    final pockets = <Offset>[
      Offset(board.left, board.top),
      Offset(board.right, board.top),
      Offset(board.left, board.bottom),
      Offset(board.right, board.bottom),
    ];
    for (final p in pockets) {
      canvas.drawCircle(p, pocketR, pocketPaint);
    }

    // Striker disc — a heavier filled disc in the lower-middle area.
    final strikerR = unit * 2.1;
    final strikerCenter = Offset(board.center.dx, board.bottom - unit * 2.4);
    canvas.drawCircle(
      strikerCenter,
      strikerR,
      Paint()..color = _flagshipFill,
    );
    // Inner ring on the striker.
    canvas.drawCircle(
      strikerCenter,
      strikerR * 0.55,
      Paint()
        ..color = const Color(0xFFD97706) // board gold gradient
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _CarromPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Call Break (Lakdi) — a fanned hand of three playing-card suits.
// ---------------------------------------------------------------------------

class _CallBreakPainter extends CustomPainter {
  const _CallBreakPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final unit = s / 12;
    final cardPaint = Paint()
      ..color = _flagshipFill
      ..style = PaintingStyle.stroke
      ..strokeWidth = unit * 0.45;

    // Three cards fanned left → right, each rotated a few degrees.
    final rotations = <double>[-0.35, 0, 0.35];
    final cardWidth = unit * 5.2;
    final cardHeight = unit * 7.6;
    final cx = s / 2;
    final cy = s / 2;
    for (var i = 0; i < rotations.length; i++) {
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(rotations[i]);
      final rect = Rect.fromCenter(
        center: Offset.zero,
        width: cardWidth,
        height: cardHeight,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(unit * 0.5)),
        cardPaint,
      );
      // Corner pip — tiny suit glyph in the top-left of each card.
      // We pick one suit per card so the fanned hand reads as varied.
      _drawSuitGlyph(
        canvas,
        center: Offset(rect.left + unit * 1.0, rect.top + unit * 1.4),
        size: unit * 1.4,
        suitIndex: i,
      );
      canvas.restore();
    }
  }

  void _drawSuitGlyph(
    Canvas canvas, {
    required Offset center,
    required double size,
    required int suitIndex,
  }) {
    final fill = Paint()..color = _flagshipFill;
    switch (suitIndex % 4) {
      case 0: // spade — diamond + stem
        final path = Path()
          ..moveTo(center.dx, center.dy - size * 0.5)
          ..quadraticBezierTo(
            center.dx + size * 0.6,
            center.dy - size * 0.1,
            center.dx,
            center.dy + size * 0.3,
          )
          ..quadraticBezierTo(
            center.dx - size * 0.6,
            center.dy - size * 0.1,
            center.dx,
            center.dy - size * 0.5,
          )
          ..close();
        canvas.drawPath(path, fill);
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset(center.dx, center.dy + size * 0.45),
            width: size * 0.25,
            height: size * 0.35,
          ),
          fill,
        );
        break;
      case 1: // heart
        final path = Path()
          ..moveTo(center.dx, center.dy + size * 0.5)
          ..quadraticBezierTo(
            center.dx - size * 0.7,
            center.dy,
            center.dx,
            center.dy - size * 0.35,
          )
          ..quadraticBezierTo(
            center.dx + size * 0.7,
            center.dy,
            center.dx,
            center.dy + size * 0.5,
          )
          ..close();
        canvas.drawPath(path, fill);
        break;
      case 2: // diamond
        final path = Path()
          ..moveTo(center.dx, center.dy - size * 0.5)
          ..lineTo(center.dx + size * 0.45, center.dy)
          ..lineTo(center.dx, center.dy + size * 0.5)
          ..lineTo(center.dx - size * 0.45, center.dy)
          ..close();
        canvas.drawPath(path, fill);
        break;
      case 3: // club
        canvas.drawCircle(
          Offset(center.dx, center.dy - size * 0.25),
          size * 0.25,
          fill,
        );
        canvas.drawCircle(
          Offset(center.dx - size * 0.3, center.dy + size * 0.1),
          size * 0.25,
          fill,
        );
        canvas.drawCircle(
          Offset(center.dx + size * 0.3, center.dy + size * 0.1),
          size * 0.25,
          fill,
        );
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset(center.dx, center.dy + size * 0.45),
            width: size * 0.2,
            height: size * 0.35,
          ),
          fill,
        );
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _CallBreakPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Chess — stylised knight silhouette.
// ---------------------------------------------------------------------------

class _ChessKnightPainter extends CustomPainter {
  const _ChessKnightPainter();

  // Tinted squares (light side) vs. dark squares. Using the
  // flagship fill color (near-white) for the light squares and a
  // dark teal for the dark squares so the board reads as chess
  // even at thumbnail scale.
  static const _dark = Color(0xFF134E4A); // dark teal — pairs with the
                                          // brain category gradient

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final unit = s / 12;

    // 1. 6×6 board (cropped from the standard 8×8 to leave room for
    //    pieces). Alternating tinted squares via evenodd path so we
    //    pay one draw call instead of 36.
    final boardRect = Rect.fromLTWH(
      unit * 0.5,
      unit * 1.5,
      unit * 6,
      unit * 6,
    );
    final lightSquare = Paint()..color = _flagshipFill;
    final darkSquare = Paint()..color = _dark.withValues(alpha: 0.85);

    // First paint the whole board in light, then stamp dark squares.
    canvas.drawRect(boardRect, lightSquare);
    for (var r = 0; r < 6; r++) {
      for (var c = 0; c < 6; c++) {
        if ((r + c).isOdd) {
          final cell = Rect.fromLTWH(
            boardRect.left + c * unit,
            boardRect.top + r * unit,
            unit,
            unit,
          );
          canvas.drawRect(cell, darkSquare);
        }
      }
    }

    // 2. Soft drop shadow on the board so it floats off the
    //    gradient behind it.
    canvas.drawRect(
      boardRect.shift(Offset(0, unit * 0.2)),
      Paint()
        ..color = const Color(0x55000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.5),
    );
    // Redraw the board on top of the shadow to keep it crisp.
    canvas.drawRect(boardRect, lightSquare);
    for (var r = 0; r < 6; r++) {
      for (var c = 0; c < 6; c++) {
        if ((r + c).isOdd) {
          final cell = Rect.fromLTWH(
            boardRect.left + c * unit,
            boardRect.top + r * unit,
            unit,
            unit,
          );
          canvas.drawRect(cell, darkSquare);
        }
      }
    }

    // 3. Three pieces on the board — a knight, a pawn, and a rook —
    //    arranged so they sit on different colored squares.
    _paintPawn(
      canvas,
      center: Offset(
        boardRect.left + unit * 1.5,
        boardRect.top + unit * 4.5,
      ),
      unit: unit,
    );
    _paintRook(
      canvas,
      center: Offset(
        boardRect.left + unit * 3.5,
        boardRect.top + unit * 4.5,
      ),
      unit: unit,
    );
    _paintKnight(
      canvas,
      center: Offset(
        boardRect.left + unit * 5.5,
        boardRect.top + unit * 4.5,
      ),
      unit: unit,
    );
  }

  /// Pawn silhouette — circle head + rounded teardrop body.
  void _paintPawn(
    Canvas canvas, {
    required Offset center,
    required double unit,
  }) {
    final fill = Paint()..color = _flagshipFill;
    final r = unit * 0.32;
    final bodyRect = Rect.fromCenter(
      center: Offset(center.dx, center.dy + unit * 0.15),
      width: unit * 0.8,
      height: unit * 0.7,
    );
    canvas.drawCircle(center, r, fill);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, Radius.circular(unit * 0.15)),
      fill,
    );
  }

  /// Rook silhouette — flat crenellated top + tapered body.
  void _paintRook(
    Canvas canvas, {
    required Offset center,
    required double unit,
  }) {
    final fill = Paint()..color = _flagshipFill;
    final left = center.dx - unit * 0.5;
    final right = center.dx + unit * 0.5;
    final top = center.dy - unit * 0.4;
    final base = center.dy + unit * 0.4;
    final path = Path()
      ..moveTo(left, base)
      ..lineTo(left, top + unit * 0.2)
      ..lineTo(left + unit * 0.15, top + unit * 0.2)
      ..lineTo(left + unit * 0.15, top)
      ..lineTo(left + unit * 0.3, top)
      ..lineTo(left + unit * 0.3, top + unit * 0.2)
      ..lineTo(left + unit * 0.55, top + unit * 0.2)
      ..lineTo(left + unit * 0.55, top)
      ..lineTo(left + unit * 0.7, top)
      ..lineTo(left + unit * 0.7, top + unit * 0.2)
      ..lineTo(right, top + unit * 0.2)
      ..lineTo(right, base)
      ..close();
    canvas.drawPath(path, fill);
  }

  /// Knight silhouette — simplified horse head, the same family as
  /// the old single-glyph version but sized down so it sits on a
  /// board square next to the other pieces.
  void _paintKnight(
    Canvas canvas, {
    required Offset center,
    required double unit,
  }) {
    final fill = Paint()..color = _flagshipFill;
    final left = center.dx - unit * 0.45;
    final right = center.dx + unit * 0.45;
    final base = center.dy + unit * 0.4;
    final path = Path()
      ..moveTo(left, base)
      ..lineTo(right, base)
      ..lineTo(right, base - unit * 0.15)
      ..lineTo(right - unit * 0.05, base - unit * 0.3)
      ..lineTo(right - unit * 0.15, base - unit * 0.55)
      ..lineTo(right - unit * 0.05, base - unit * 0.55)
      ..lineTo(right - unit * 0.1, base - unit * 0.7)
      ..lineTo(right - unit * 0.25, base - unit * 0.7)
      ..lineTo(left + unit * 0.05, base - unit * 0.5)
      ..lineTo(left, base - unit * 0.3)
      ..close();
    canvas.drawPath(path, fill);
  }

  @override
  bool shouldRepaint(covariant _ChessKnightPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Sudoku — a 3×3 mini grid with one highlighted cell containing a "5".
// ---------------------------------------------------------------------------

class _SudokuGridPainter extends CustomPainter {
  const _SudokuGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final unit = s / 12;
    final stroke = Paint()
      ..color = _flagshipFill
      ..style = PaintingStyle.stroke
      ..strokeWidth = unit * 0.45;

    final grid = Rect.fromLTWH(unit, unit, 10 * unit, 10 * unit);
    // Outer frame.
    canvas.drawRect(grid, stroke);

    // 4 inner vertical/horizontal lines → 5×5 cells.
    for (var i = 1; i < 5; i++) {
      final t = i * 2 * unit;
      canvas.drawLine(
        Offset(grid.left + t, grid.top),
        Offset(grid.left + t, grid.bottom),
        stroke,
      );
      canvas.drawLine(
        Offset(grid.left, grid.top + t),
        Offset(grid.right, grid.top + t),
        stroke,
      );
    }

    // Highlight one cell in the centre — filled with the puzzle
    // gradient color so the "5" reads as selected.
    final cellSize = 2 * unit;
    final highlightLeft = grid.left + 2 * cellSize;
    final highlightTop = grid.top + 2 * cellSize;
    final highlight = Rect.fromLTWH(
      highlightLeft,
      highlightTop,
      cellSize,
      cellSize,
    );
    canvas.drawRect(
      highlight,
      Paint()..color = const Color(0xFF7C3AED), // puzzle purple
    );

    // The number "5" centered in the highlight cell.
    final textPainter = TextPainter(
      text: const TextSpan(
        text: '5',
        style: TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: 14,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(
        highlight.center.dx - textPainter.width / 2,
        highlight.center.dy - textPainter.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _SudokuGridPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Cricket — a bat silhouette crossed with a ball.
// ---------------------------------------------------------------------------

class _CricketPainter extends CustomPainter {
  const _CricketPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final unit = s / 12;
    final fill = Paint()..color = _flagshipFill;

    // Bat — a paddle shape oriented diagonally from bottom-left to
    // top-right, with a thin handle and a wider blade.
    canvas.save();
    canvas.translate(s / 2, s / 2);
    canvas.rotate(-0.6);
    final bat = Path()
      ..moveTo(-unit * 0.6, -unit * 5.0) // handle top
      ..lineTo(unit * 0.6, -unit * 5.0)
      ..lineTo(unit * 0.6, -unit * 3.0) // handle/blade join
      ..lineTo(unit * 2.4, -unit * 2.0) // blade right
      ..quadraticBezierTo(
        unit * 3.0,
        0,
        unit * 2.4,
        unit * 2.0,
      ) // blade tip
      ..lineTo(unit * 0.6, unit * 3.0) // blade bottom
      ..lineTo(-unit * 0.6, unit * 3.0)
      ..lineTo(-unit * 0.6, -unit * 5.0)
      ..close();
    canvas.drawPath(bat, fill);

    // Blade seam — a thin spine down the middle of the blade.
    canvas.drawLine(
      Offset(0, -unit * 2.6),
      Offset(0, unit * 2.6),
      Paint()
        ..color = const Color(0xFF16A34A) // sports green gradient
        ..strokeWidth = unit * 0.3
        ..style = PaintingStyle.stroke,
    );
    canvas.restore();

    // Cricket ball — a filled circle in the lower-right with a single
    // seam arc to suggest the stitched ball.
    final ballCenter = Offset(s - unit * 3, s - unit * 3);
    final ballR = unit * 2.2;
    canvas.drawCircle(
      ballCenter,
      ballR,
      Paint()..color = const Color(0xFFDC2626), // action red gradient
    );
    // Seam arc — a single curved stroke crossing the ball.
    final seam = Path()
      ..moveTo(ballCenter.dx - ballR * 0.9, ballCenter.dy - ballR * 0.2)
      ..quadraticBezierTo(
        ballCenter.dx,
        ballCenter.dy + ballR * 0.5,
        ballCenter.dx + ballR * 0.9,
        ballCenter.dy - ballR * 0.2,
      );
    canvas.drawPath(
      seam,
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = unit * 0.35,
    );
  }

  @override
  bool shouldRepaint(covariant _CricketPainter oldDelegate) => false;
}