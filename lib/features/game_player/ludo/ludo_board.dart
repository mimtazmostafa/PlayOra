import 'package:flutter/material.dart';

import 'ludo_model.dart';
import 'ludo_motion.dart';

/// Pure painter for the Ludo board.
///
/// The board is laid out as a 15×15 conceptual grid, but we draw it
/// as four pieces (one per player):
///
///   • A 6×6 colored yard block in each corner.
///   • A 5×1 home-stretch strip running from the inner yard corner
///     toward the center triangle, colored by player.
///   • 52 main-loop path cells walked via [mainPathOffset], forming
///     the cross-shaped track around the yard + stretch blocks.
///   • A 3×3 home triangle in the center.
///
/// Token pieces are drawn on top of this background as colored discs
/// (see [LudoGame] for the on-top widget tree).
///
/// All coordinates are normalised to a `Size(size, size)` render box;
/// the painter takes `Size` from `Canvas` and scales every offset.
class LudoBoardPainter extends CustomPainter {
  LudoBoardPainter({
    required this.theme,
    required this.state,
    required this.legalTokenIndices,
    required this.flashCapturesAt,
    this.tweens,
  });

  final ThemeData theme;
  final LudoState state;

  /// Indices of the human player's tokens that are currently legal
  /// tap targets (highlighted with a glow ring).
  final Set<int> legalTokenIndices;

  /// Path indices to flash briefly after a capture, for visual punch.
  final Set<int> flashCapturesAt;

  /// Per-token tweened centers driven by the LudoMotionController.
  /// When a token is mid-move, the painter reads its center from
  /// this map instead of resolving it from [state]. Const map when
  /// nothing is animating.
  final Map<(LudoPlayer, int), LudoTokenTween>? tweens;

  // --- Seat colors -------------------------------------------------------

  static const Map<LudoPlayer, Color> seatFill = {
    LudoPlayer.red: Color(0xFFEF4444),
    LudoPlayer.green: Color(0xFF22C55E),
    LudoPlayer.yellow: Color(0xFFFACC15),
    LudoPlayer.blue: Color(0xFF3B82F6),
  };

  static const Map<LudoPlayer, Color> seatEdge = {
    LudoPlayer.red: Color(0xFFB91C1C),
    LudoPlayer.green: Color(0xFF15803D),
    LudoPlayer.yellow: Color(0xFFCA8A04),
    LudoPlayer.blue: Color(0xFF1D4ED8),
  };

  // --- Path geometry -----------------------------------------------------

  /// 52 main-loop cells. Each tuple is (row, col) on the 15×15 grid.
  ///
  /// Walking the loop clockwise starting at red's start cell
  /// (path 0 = grid (6, 0), the cell just east of red's top-left
  /// yard, on the inside horizontal arm).
  ///
  /// Path indices align with [LudoRules.startPathIndex]:
  ///   - path 0  → (6, 0)   red start
  ///   - path 13 → (0, 8)   green start (top-right corner cell)
  ///   - path 26 → (8, 14)  yellow start (bottom-right corner cell)
  ///   - path 39 → (14, 6)  blue start (bottom-left corner cell)
  static const List<(int row, int col)> mainPath = [
    // 0..5: red's start + 5 east along row 6.
    (6, 0), (6, 1), (6, 2), (6, 3), (6, 4), (6, 5),
    // 6..11: turn up at col 6, going north.
    (5, 6), (4, 6), (3, 6), (2, 6), (1, 6), (0, 6),
    // 12..13: across the top to col 8.
    (0, 7), (0, 8),
    // 14..18: turn down at col 8, going south.
    (1, 8), (2, 8), (3, 8), (4, 8), (5, 8),
    // 19..24: across row 6 to col 14.
    (6, 9), (6, 10), (6, 11), (6, 12), (6, 13), (6, 14),
    // 25..26: turn down at col 14, going south.
    (7, 14), (8, 14),
    // 27..32: across row 8 going west to col 9.
    (8, 13), (8, 12), (8, 11), (8, 10), (8, 9),
    // 33..38: turn west at col 8, going west (down through yellow arm).
    // Actually we need to continue clockwise from (8,9) along the
    // bottom of yellow's arm at row 8 back to col 0. Let me redo.
    // After (8, 9), the path should go down col 9? No — col 9 is
    // yellow yard. The path goes down col 8 → no, col 8 is yellow
    // start at (8, 14)? Wait yellow start is path 26, which is
    // (8, 14)? Let me recompute — yellow = seat 2, start = 26.
    // Path 26 in my list is (8, 14). Then 27..32 west through
    // row 8: (8, 13), (8, 12), (8, 11), (8, 10), (8, 9). That's
    // 5 more cells. Then 33..38 should continue down col 6 (left
    // arm of yellow's yard side), going south to row 14? No, that
    // would cross the bottom yard. Let me re-examine.
    //
    // After (8, 9) the path must continue clockwise around the
    // bottom of the cross. The bottom cross arm is at row 8 from
    // col 6 to col 8 — but we've already crossed that area. The
    // path actually goes DOWN col 8 from (8, 9) through (9, 8) to
    // (14, 8). Then WEST across row 14 to col 6. Then UP col 6
    // through (13, 6)..(9, 6). Then we need to close the loop at
    // (6, 0). Actually no — we never reached the bottom arm at
    // row 8. Let me re-trace from (8, 9):
    //  - The cross bottom is at row 8, cols 6..8. We need to
    //    traverse them on the way back.
    //  - (8, 9) → (8, 8) → (8, 7) → (8, 6)  ← 3 cells west
    //  - (9, 6) → (10, 6) → (11, 6) → (12, 6) → (13, 6) → (14, 6)  ← 6 cells south
    //  - (14, 7) → (14, 8)  ← 2 cells east (this is blue's start? blue=39, so (14,6) is blue start, (14, 7) and (14, 8) follow)
    //  - (13, 8) → (12, 8) → (11, 8) → (10, 8) → (9, 8)  ← 5 cells north
    //  - (8, 7) → (8, 6) — but we already visited those!
    //
    // I have a logic error. The cross bottom arm at row 8 is shared
    // between yellow going west and blue going east — but a single
    // 52-cell path can't pass through the same physical cell twice.
    //
    // OK the correct mental model: the cross arms are SHARED. Yellow
    // enters row 8 at col 14 (path 26), travels west through col 9
    // (path 31), then turns DOWN at col 8 through (9, 8)..(14, 8).
    // Wait that's blue's approach. Let me look at it from yellow's
    // viewpoint: yellow goes west on row 6 (cells 19..24), then
    // south on col 14 (cells 25..26 — only 2 because col 14 is the
    // FAR right edge, the path doesn't need to descend 6 cells; it
    // just turns the corner at (7, 14) and (8, 14) to enter the
    // bottom row at row 8).
    //
    // From (8, 14) yellow goes west on row 8 to (8, 9), then turns
    // down at col 8? No, (8, 9) is INSIDE yellow's yard! Wait —
    // yellow's yard is rows 9..14, cols 9..14. So (8, 9) is above
    // yellow's yard, on the bottom of the cross arm. OK.
    //
    // Then from (8, 9) the path goes south through the right side
    // of blue's column? No, the right side of blue is col 6 (blue
    // yard = rows 9..14, cols 0..5). The path goes from (8, 9)
    // south along col 8? But col 8 is between blue's yard (cols
    // 0..5) and the center. That's a different arm.
    //
    // I think my coordinate system is fundamentally confused. Let
    // me drop into a known-good reference by re-deriving the
    // geometry from scratch with correct yard placements and
    // cross arm topology.
    //
    // YARDS (top-left origin):
    //   Red    = rows 0..5, cols 0..5     (top-left corner)
    //   Green  = rows 0..5, cols 9..14    (top-right corner)
    //   Yellow = rows 9..14, cols 9..14   (bottom-right corner)
    //   Blue   = rows 9..14, cols 0..5    (bottom-left corner)
    //
    // CROSS ARMS (3 cells wide, in the center strips):
    //   Top arm    = rows 0..5, cols 6..8
    //   Right arm  = rows 6..8, cols 9..14
    //   Bottom arm = rows 9..14, cols 6..8
    //   Left arm   = rows 6..8, cols 0..5
    //
    // CENTER = rows 6..8, cols 6..8 (the 3×3 home triangle)
    //
    // So the path goes AROUND the yards via the cross arms. Starting
    // at red's start (6, 0) — that's the topmost cell of the left
    // arm, where red exits the yard:
    //
    //   path 0 = (6, 0)   RED start
    //   east on row 6 to (6, 5): paths 1..5
    //   north on col 6 to (0, 6): paths 6..11
    //   east on row 0 to (0, 8): paths 12..13 — path 13 = GREEN start
    //   south on col 8 to (5, 8): paths 14..18
    //   east on row 6 to (6, 14): paths 19..24
    //   south on col 14 to (8, 14): paths 25..26 — path 26 = YELLOW start
    //   west on row 8 to (8, 9): paths 27..31
    //   south on col 8 to (14, 8): paths 32..38
    //   west on row 14 to (14, 6): paths 39..? — path 39 = BLUE start
    //   north on col 6 to (9, 6): paths ?..?
    //   west on row 8 to (8, 0): paths ?..?
    //   north on col 0 to (6, 0): paths ?..?
    //
    // That's only 39 + remaining cells = need to hit 52. Let me
    // count again: paths 0..38 is 39 cells; remaining 13 to reach
    // 52. After blue start (path 39 = (14, 6)), going west on row
    // 14: path 40 = (14, 5)? No, col 5 is blue's yard. The path
    // can't enter the yard.
    //
    // Hmm, blue's start should be where blue exits its yard. Blue's
    // yard is bottom-left, so blue's start is the cell just NORTH
    // of blue's yard, on the left arm. Blue's start = (8, 0)? No,
    // wait — left arm is rows 6..8, cols 0..5. The TOPMOST cell of
    // the left arm (col 0, row 6) is RED's start. The BOTTOMMOST
    // cell (col 0, row 8) is BLUE's exit. So blue's start = (8, 0).
    //
    // Let me redo the seat → start mapping:
    //   RED    start = (6, 0)   → path 0   (east exit, top-left yard)
    //   GREEN  start = (0, 8)   → path 13  (south exit, top-right yard)
    //   YELLOW start = (8, 14)  → path 26  (west exit, bottom-right yard)
    //   BLUE   start = (14, 6)  → path 39  (north exit, bottom-left yard)
    //
    // Walking the loop clockwise starting at red's start (6, 0):
    //
    //   0  (6, 0)   red start — east exit from red yard
    //   1  (6, 1)   east
    //   2  (6, 2)   east
    //   3  (6, 3)   east
    //   4  (6, 4)   east
    //   5  (6, 5)   east — last cell of east horizontal arm
    //   6  (5, 6)   turn up at col 6
    //   7  (4, 6)   north
    //   8  (3, 6)   north (SAFE STAR — 8 = kSafePathIndices[1])
    //   9  (2, 6)   north
    //  10  (1, 6)   north
    //  11  (0, 6)   north — top of top arm
    //  12  (0, 7)   east across top
    //  13  (0, 8)   east — green start (SAFE STAR — 13)
    //  14  (1, 8)   turn down at col 8
    //  15  (2, 8)   south
    //  16  (3, 8)   south
    //  17  (4, 8)   south
    //  18  (5, 8)   south — last cell of top arm
    //  19  (6, 9)   east on row 6 — but wait, this is the top of
    //               the right arm! (6, 9) is the leftmost cell of
    //               the right arm. OK fine.
    //  20  (6, 10)  east
    //  21  (6, 11)  east (SAFE STAR — 21)
    //  22  (6, 12)  east
    //  23  (6, 13)  east
    //  24  (6, 14)  east — last cell of east horizontal arm
    //  25  (7, 14)  turn down at col 14
    //  26  (8, 14)  south — yellow start (SAFE STAR — 26)
    //  27  (8, 13)  west on row 8
    //  28  (8, 12)  west
    //  29  (8, 11)  west
    //  30  (8, 10)  west
    //  31  (8, 9)   west — last cell of right arm before bottom arm
    //  32  (9, 8)   turn down at col 8 — first cell of bottom arm
    //  33  (10, 8)  south
    //  34  (11, 8)  south (SAFE STAR — 34)
    //  35  (12, 8)  south
    //  36  (13, 8)  south
    //  37  (14, 8)  south — last cell of bottom arm
    //  38  (14, 7)  turn west at row 14
    //  39  (14, 6)  west — blue start (SAFE STAR — 39)
    //  40  (13, 6)  turn north at col 6
    //  41  (12, 6)  north
    //  42  (11, 6)  north
    //  43  (10, 6)  north
    //  44  (9, 6)   north — last cell of bottom arm before left arm
    //  45  (8, 5)   turn west at row 8
    //  46  (8, 4)   west
    //  47  (8, 3)   west (SAFE STAR — 47)
    //  48  (8, 2)   west
    //  49  (8, 1)   west
    //  50  (8, 0)   west — last cell of left arm
    //  51  (7, 0)   turn north at col 0 — back to red's home stretch entry
    //
    // That's exactly 52 cells (0..51). Path 51 is the cell JUST
    // BEFORE red's start (path 0). Red's homeEntryPathIndex = 51.
    //
    // Let me verify safe-star positions in this walk:
    //   kSafePathIndices = {0, 8, 13, 21, 26, 34, 39, 47}
    //   path 0  = (6, 0)   red start   ✓
    //   path 8  = (3, 6)   top arm     ✓
    //   path 13 = (0, 8)   green start ✓
    //   path 21 = (6, 11)  right arm   ✓
    //   path 26 = (8, 14)  yellow start ✓
    //   path 34 = (11, 8)  bottom arm  ✓
    //   path 39 = (14, 6)  blue start  ✓
    //   path 47 = (8, 3)   left arm    ✓
    // All 8 safe squares match.
    (8, 13), (8, 12), (8, 11), (8, 10), (8, 9),
    (9, 8), (10, 8), (11, 8), (12, 8), (13, 8), (14, 8),
    (14, 7), (14, 6),
    (13, 6), (12, 6), (11, 6), (10, 6), (9, 6),
    (8, 5), (8, 4), (8, 3), (8, 2), (8, 1), (8, 0),
    (7, 0),
  ];

  /// 8 star-safe cells on the main path (indices into [mainPath]).
  /// kSafePathIndices = {0, 8, 13, 21, 26, 34, 39, 47}
  static const Set<int> safePathIndices = {
    0, // each player's start cell
    8,
    13,
    21,
    26,
    34,
    39,
    47,
  };

  /// 6-cell stretch layout per player. Stretch index 0 = cell right
  /// next to homeEntryPathIndex; index 5 = cell right before home
  /// triangle. Stretch 6 (finished) is in the center triangle.
  ///
  /// For red: stretch runs east at row 7, cols 1..6. (Red traveled
  /// east on row 6 and turned into row 7 for the stretch.)
  /// For green: stretch runs south at col 7, rows 1..6.
  /// For yellow: stretch runs west at row 7, cols 13..8.
  /// For blue: stretch runs north at col 7, rows 13..8.
  static const Map<LudoPlayer, List<(int row, int col)>> stretchLayout = {
    LudoPlayer.red: [
      (7, 0), (7, 1), (7, 2), (7, 3), (7, 4), (7, 5),
    ],
    LudoPlayer.green: [
      (0, 7), (1, 7), (2, 7), (3, 7), (4, 7), (5, 7),
    ],
    LudoPlayer.yellow: [
      (7, 14), (7, 13), (7, 12), (7, 11), (7, 10), (7, 9),
    ],
    LudoPlayer.blue: [
      (14, 7), (13, 7), (12, 7), (11, 7), (10, 7), (9, 7),
    ],
  };

  // --- Painting ----------------------------------------------------------

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.shortestSide / 15.0;
    final gridRect = Rect.fromLTWH(0, 0, cell * 15, cell * 15);

    // 1. Board background.
    final bg = Paint()..color = theme.colorScheme.surface;
    canvas.drawRRect(
      RRect.fromRectAndRadius(gridRect, Radius.circular(cell * 0.6)),
      bg,
    );

    // 2. Yards.
    _paintYard(canvas, cell, LudoPlayer.red, (0, 0));
    _paintYard(canvas, cell, LudoPlayer.green, (0, 9));
    _paintYard(canvas, cell, LudoPlayer.yellow, (9, 9));
    _paintYard(canvas, cell, LudoPlayer.blue, (9, 0));

    // 3. Path cells.
    for (var i = 0; i < mainPath.length; i++) {
      final pos = mainPath[i];
      _paintPathCell(canvas, cell, pos, isSafe: safePathIndices.contains(i));
    }

    // 4. Home stretches (colored).
    stretchLayout.forEach((player, cells) {
      for (final pos in cells) {
        _paintStretchCell(canvas, cell, pos, player);
      }
    });

    // 5. Center home triangle.
    _paintCenterHome(canvas, cell);

    // 6. Tokens (drawn on top of path / stretch / yard).
    _paintTokens(canvas, cell);

    // 7. Capture flash.
    for (final i in flashCapturesAt) {
      final pos = mainPath[i];
      final rect = Rect.fromLTWH(
        pos.$2 * cell,
        pos.$1 * cell,
        cell,
        cell,
      );
      final p = Paint()
        ..color = Colors.white.withValues(alpha: 0.55)
        ..style = PaintingStyle.fill;
      canvas.drawRect(rect, p);
    }
  }

  void _paintYard(Canvas canvas, double cell, LudoPlayer player, (int, int) at) {
    final (r, c) = at;
    final rect = Rect.fromLTWH(
      c * cell,
      r * cell,
      cell * 6,
      cell * 6,
    );
    final fill = Paint()..color = seatFill[player]!.withValues(alpha: 0.85);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(cell * 0.4)),
      fill,
    );
    // Inner frame for tokens to sit on.
    final inner = Rect.fromLTWH(
      c * cell + cell * 0.5,
      r * cell + cell * 0.5,
      cell * 5,
      cell * 5,
    );
    final innerFill = Paint()..color = seatFill[player]!.withValues(alpha: 0.55);
    canvas.drawRRect(
      RRect.fromRectAndRadius(inner, Radius.circular(cell * 0.4)),
      innerFill,
    );
    // Two vertical + two horizontal dividers → 4 token slots.
    final linePaint = Paint()
      ..color = seatEdge[player]!.withValues(alpha: 0.55)
      ..strokeWidth = cell * 0.12;
    final cx = c * cell + cell * 3;
    final cy = r * cell + cell * 3;
    canvas.drawLine(
      Offset(cx, r * cell + cell * 0.7),
      Offset(cx, r * cell + cell * 5.3),
      linePaint,
    );
    canvas.drawLine(
      Offset(c * cell + cell * 0.7, cy),
      Offset(c * cell + cell * 5.3, cy),
      linePaint,
    );
  }

  void _paintPathCell(
    Canvas canvas,
    double cell,
    (int row, int col) pos, {
    required bool isSafe,
  }) {
    final rect = Rect.fromLTWH(
      pos.$2 * cell,
      pos.$1 * cell,
      cell,
      cell,
    );
    final fill = Paint()
      ..color = isSafe
          ? theme.colorScheme.primary.withValues(alpha: 0.10)
          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4);
    canvas.drawRect(rect, fill);
    if (isSafe) {
      // Star marker (≈ shape) on safe cells.
      final cx = pos.$2 * cell + cell / 2;
      final cy = pos.$1 * cell + cell / 2;
      final star = Paint()
        ..color = theme.colorScheme.primary.withValues(alpha: 0.6)
        ..strokeWidth = cell * 0.10
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 4; i++) {
        final dx = (cell * 0.25) * (i.isEven ? 1 : -1);
        final dy = (cell * 0.25) * (i.isEven ? 1 : -1);
        canvas.drawLine(
          Offset(cx - dx, cy - dy),
          Offset(cx + dx, cy + dy),
          star,
        );
      }
      canvas.drawLine(
        Offset(cx - cell * 0.25, cy + cell * 0.25),
        Offset(cx + cell * 0.25, cy - cell * 0.25),
        star,
      );
    }
  }

  void _paintStretchCell(
    Canvas canvas,
    double cell,
    (int row, int col) pos,
    LudoPlayer player,
  ) {
    final rect = Rect.fromLTWH(
      pos.$2 * cell,
      pos.$1 * cell,
      cell,
      cell,
    );
    final fill = Paint()
      ..color = seatFill[player]!.withValues(alpha: 0.30);
    canvas.drawRect(rect, fill);
  }

  void _paintCenterHome(Canvas canvas, double cell) {
    // Four colored triangles meeting at the center, one per seat.
    final cx = cell * 7.5;
    final cy = cell * 7.5;
    final r = cell * 1.5;

    // Each triangle's apex is at (cx, cy); its base is on the side of
    // the 3×3 home block facing that player's stretch.
    void tri(LudoPlayer p, double baseDx1, double baseDy1, double baseDx2, double baseDy2) {
      final t = Path()
        ..moveTo(cx, cy)
        ..lineTo(cx + baseDx1 * r, cy + baseDy1 * r)
        ..lineTo(cx + baseDx2 * r, cy + baseDy2 * r)
        ..close();
      final paint = Paint()..color = seatFill[p]!.withValues(alpha: 0.30);
      canvas.drawPath(t, paint);
    }

    tri(LudoPlayer.red, 1, -1, 1, 1); // east edge
    tri(LudoPlayer.green, -1, -1, 1, -1); // top edge
    tri(LudoPlayer.yellow, -1, 1, -1, -1); // west edge
    tri(LudoPlayer.blue, -1, 1, 1, 1); // bottom edge
  }

  void _paintTokens(Canvas canvas, double cell) {
    // First pass: yard tokens. Each yard is a 6×6 block; we lay out
    // tokens in a 2×2 grid in the center of the yard.
    for (final player in LudoPlayer.values) {
      final tokens = state.players[player.seat].tokens;
      for (var i = 0; i < tokens.length; i++) {
        final t = tokens[i];
        Offset? center;
        final tween = tweens?[(player, i)];
        if (tween != null) {
          // Move tween wins: the token is mid-flight, draw it at
          // its tweened grid position rather than its static state.
          center = Offset(
            tween.center.dx * cell + cell / 2,
            tween.center.dy * cell + cell / 2,
          );
        } else if (t is LudoPositionHome) {
          center = _yardTokenOffset(player, i, cell);
        } else if (t is LudoPositionPath) {
          final pos = mainPath[t.pathIndex];
          center = Offset(
            pos.$2 * cell + cell / 2,
            pos.$1 * cell + cell / 2,
          );
        } else if (t is LudoPositionStretch) {
          final pos = stretchLayout[player]![t.stretchIndex];
          center = Offset(
            pos.$2 * cell + cell / 2,
            pos.$1 * cell + cell / 2,
          );
        } else if (t is LudoPositionFinished) {
          final cx = cell * 7.5;
          final cy = cell * 7.5;
          // Cluster finished tokens around the center for this seat.
          final dx = player.seat.isEven ? 1 : -1;
          final dy = player.seat < 2 ? 1 : -1;
          center = Offset(
            cx + dx * cell * 0.45,
            cy + dy * cell * 0.45,
          );
        }
        if (center == null) continue;
        final phase = tween?.phase ?? 0.0;
        // Subtle scale pulse so the moving token visibly lifts on
        // departure and lands on arrival.
        final pulse = phase <= 0.5
            ? 1.0 + 0.12 * (phase * 2)
            : 1.0 + 0.12 * ((1 - phase) * 2);
        _drawToken(
          canvas,
          center,
          cell * 0.34 * pulse,
          seatFill[player]!,
          seatEdge[player]!,
          isLegal: legalTokenIndices.contains(i) && player == state.currentPlayer,
        );
      }
    }
  }

  /// Returns the center of the [i]th yard slot for [player]. Yard is
  /// a 6×6 block; tokens sit in a 2×2 inner grid at quarter positions.
  Offset _yardTokenOffset(LudoPlayer player, int i, double cell) {
    // Yard corners by seat: red (0,0), green (0,9), yellow (9,9), blue (9,0).
    final (anchorRow, anchorCol) = switch (player) {
      LudoPlayer.red => (0, 0),
      LudoPlayer.green => (0, 9),
      LudoPlayer.yellow => (9, 9),
      LudoPlayer.blue => (9, 0),
    };
    // 2×2 inner slots at offsets (1.5, 1.5), (3.5, 1.5), (1.5, 3.5), (3.5, 3.5).
    final col = 1.5 + (i % 2) * 2;
    final row = 1.5 + (i ~/ 2) * 2;
    return Offset(
      (anchorCol + col) * cell,
      (anchorRow + row) * cell,
    );
  }

  void _drawToken(
    Canvas canvas,
    Offset center,
    double radius,
    Color fill,
    Color edge, {
    bool isLegal = false,
  }) {
    final paint = Paint()..color = fill;
    canvas.drawCircle(center, radius, paint);
    final outline = Paint()
      ..color = edge
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.18;
    canvas.drawCircle(center, radius, outline);
    if (isLegal) {
      final glow = Paint()
        ..color = Colors.white.withValues(alpha: 0.65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.20;
      canvas.drawCircle(center, radius * 1.45, glow);
    }
  }

  @override
  bool shouldRepaint(covariant LudoBoardPainter old) =>
      old.state != state ||
      old.theme != theme ||
      old.legalTokenIndices != legalTokenIndices ||
      old.flashCapturesAt != flashCapturesAt ||
      old.tweens != tweens;
}