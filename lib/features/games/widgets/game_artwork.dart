import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Local vector artwork for game tiles.
///
/// Why CustomPainter instead of bundled assets?
///
///   * The redesigned launcher needs artwork for all 35 game tiles.
///     Shipping bitmap assets doubles APK size and forces us to
///     rebuild on every accent tweak.
///   * `CustomPainter` lets the artwork inherit the current theme
///     (light / dark) and the per-game accent color at zero cost.
///   * Each recipe is small (~40 lines) so adding a new game is a
///     5-minute task.
///
/// Every game id from [RegistryGame] has a dedicated recipe — no
/// fallback '?' placeholders. Unknown ids use a soft accent disc as
/// a last-resort visual cue, but every shipped game renders a real,
/// representative icon.
class GameArtwork extends StatelessWidget {
  const GameArtwork({
    super.key,
    required this.id,
    required this.accent,
    this.size = 72,
    this.cornerRadius = 16,
    this.padding = 8,
    this.transparent = false,
  });

  /// Stable game id — see [RegistryGame.id].
  final String id;

  /// Per-game accent color (already in [RegistryGame.accent]).
  final Color accent;
  final double size;
  final double cornerRadius;
  final double padding;

  /// When `true`, skip the surface background and outline so the icon
  /// fills the whole tile. Use this from contexts that already paint
  /// their own coloured backdrop (e.g. the catalog [VibrantGameCard]).
  /// When `false` (default), the artwork paints its own surface tile
  /// with a subtle outline — suitable for surfaces without a coloured
  /// backdrop (favorites list, profile header, etc.).
  final bool transparent;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final painterSize = Size.square(size - padding * 2);
    final child = CustomPaint(
      painter: _ArtworkPainter(
        id: id,
        accent: accent,
        brightness: brightness,
      ),
      size: painterSize,
    );
    if (transparent) {
      return SizedBox(
        width: size,
        height: size,
        child: Padding(
          padding: EdgeInsets.all(padding),
          child: child,
        ),
      );
    }
    // Use the theme's surface tokens instead of pure white / hard navy
    // so light-mode tiles don't read as blank white slabs against a
    // lightly tinted background.
    final bg = AppColors.surface(brightness);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(cornerRadius),
        border: Border.all(
          color: brightness == Brightness.dark
              ? Colors.white.withValues(alpha: 0.06)
              : AppColors.outline(brightness).withValues(alpha: 0.55),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: child,
      ),
    );
  }
}

class _ArtworkPainter extends CustomPainter {
  _ArtworkPainter({
    required this.id,
    required this.accent,
    required this.brightness,
  });

  final String id;
  final Color accent;
  final Brightness brightness;

  @override
  void paint(Canvas canvas, Size size) {
    switch (id) {
      // ── Existing recipes ─────────────────────────────────────
      case 'block-puzzle':
        return _paintBlockPuzzle(canvas, size);
      case 'snake':
      case 'snake-duel':
        return _paintSnake(canvas, size);
      case 'game-2048':
        return _paint2048(canvas, size);
      case 'water-sort':
        return _paintWaterSort(canvas, size);
      case 'memory-match':
      case 'daily-memory-match':
        return _paintMemoryMatch(canvas, size);
      case 'tic-tac-toe':
      case 'daily-tic-tac-toe':
        return _paintTicTacToe(canvas, size);
      case 'four-in-a-row':
        return _paintFourInARow(canvas, size);
      case 'mini-carrom':
      case 'mini-carrom-2p':
        return _paintCarrom(canvas, size);
      case 'mini-pool':
        return _paintMiniPool(canvas, size);
      case 'billiards':
      case 'billiards-8-ball':
      case 'pool-8':
        return _paintBilliards(canvas, size);

      // ── New recipes ──────────────────────────────────────────
      case 'mini-ludo':
        return _paintMiniLudo(canvas, size);
      case 'minesweeper':
        return _paintMinesweeper(canvas, size);
      case 'bangla-word-connect':
        return _paintBanglaWordConnect(canvas, size);
      case 'bangla-word-search':
        return _paintBanglaWordSearch(canvas, size);
      case 'bangladesh-quiz':
        return _paintBangladeshQuiz(canvas, size);
      case 'sudoku':
        return _paintSudoku(canvas, size);
      case 'tile-match':
        return _paintTileMatch(canvas, size);
      case 'connect-lines':
        return _paintConnectLines(canvas, size);
      case 'maze-escape':
        return _paintMazeEscape(canvas, size);
      case 'stack-tower':
        return _paintStackTower(canvas, size);
      case 'tap-reaction':
        return _paintTapReaction(canvas, size);
      case 'cricket-batting':
        return _paintCricketBatting(canvas, size);
      case 'lumberjack-battle':
        return _paintLumberjack(canvas, size);
      case 'pong':
        return _paintPong(canvas, size);
      case 'flappy-bird':
        return _paintFlappyBird(canvas, size);
      case 'snake-ladders':
        return _paintSnakeLadders(canvas, size);
      case 'battleship':
        return _paintBattleship(canvas, size);
      case 'chess':
        return _paintChess(canvas, size);
      case 'backgammon':
        return _paintBackgammon(canvas, size);
      case 'bomberman':
        return _paintBomberman(canvas, size);
      case 'pacman':
        return _paintPacman(canvas, size);

      // ── Featured top-9 games ────────────────────────────────
      case 'racing-rush':
        return _paintRacingRush(canvas, size);
      case 'fruit-slice':
      case 'daily-fruit-slice':
        return _paintFruitSlice(canvas, size);
      case 'basket-bounce':
        return _paintBasketBounce(canvas, size);
      case 'darts-club':
        return _paintDartsClub(canvas, size);
      case 'treasure-hunt':
        return _paintTreasureHunt(canvas, size);

      // ── 20-game catalog ─────────────────────────────────────
      case 'snake-master':
      case 'snakes':
        return _paintSnake(canvas, size);
      case 'subway-run':
        return _paintSubwayRun(canvas, size);
      case 'space-blast':
        return _paintSpaceBlast(canvas, size);
      case 'word-master':
        return _paintWordMaster(canvas, size);
      case 'candy-drop':
        return _paintCandyDrop(canvas, size);
      case 'fruit-merge':
      case 'daily-fruit-merge':
        return _paintFruitMerge(canvas, size);
      case 'memory-cards':
        return _paintMemoryCards(canvas, size);
      case 'balloon-pop':
      case 'daily-balloon-pop':
        return _paintBalloonPop(canvas, size);
      case 'jelly-jump':
        return _paintJellyJump(canvas, size);
      case 'tower-builder':
        return _paintTowerBuilder(canvas, size);
      case 'golf-star':
        return _paintGolfStar(canvas, size);
      case 'bowling-pro':
        return _paintBowlingPro(canvas, size);
      case 'knife-hit':
        return _paintKnifeHit(canvas, size);
      case 'soccer-hero':
        return _paintSoccerHero(canvas, size);
      case 'bubble-pop':
        return _paintBubbleShooter(canvas, size);
      case 'typing-race':
        return _paintTypingRace(canvas, size);
      case 'dots-and-boxes':
        return _paintDotsAndBoxes(canvas, size);
      case 'chess-master':
        return _paintChess(canvas, size);
      default:
        return _paintGeneric(canvas, size);
    }
  }

  @override
  bool shouldRepaint(_ArtworkPainter old) =>
      old.id != id ||
      old.accent != accent ||
      old.brightness != brightness;

  // ─────────────────────────────────────────────────────────────
  // Existing recipes (preserved)
  // ─────────────────────────────────────────────────────────────

  void _paintBlockPuzzle(Canvas canvas, Size s) {
    // Redesigned for the PlayNest light theme: a colorful 8-block
    // tetromino grid using a small pastel palette so each tile pops,
    // plus a soft inner highlight on every cell. Falls back to the
    // accent colour when fewer than four pastels are needed.
    final cell = s.width / 4;
    final gap = cell * 0.12;
    final radius = Radius.circular(cell * 0.24);

    final tilePalette = <Color>[
      const Color(0xFFFF5A6E), // coral pink
      const Color(0xFF22B8FF), // cyan
      const Color(0xFFFFC837), // golden yellow
      const Color(0xFF22C55E), // emerald
      const Color(0xFFA073FF), // pastel purple
      accent, // accent fallback (rotates by index)
    ];

    final filled = <List<int>>[
      [0, 0],
      [0, 1],
      [0, 2],
      [1, 0],
      [1, 1],
      [2, 1],
      [2, 2],
      [1, 2],
    ];

    for (var i = 0; i < filled.length; i++) {
      final pos = filled[i];
      final tileColor = tilePalette[i % tilePalette.length];
      final rect = Rect.fromLTWH(
        pos[1] * cell + gap,
        pos[0] * cell + gap,
        cell - gap,
        cell - gap,
      );
      final rrect = RRect.fromRectAndRadius(rect, radius);

      // Soft outer shadow under each tile for the 3D feel.
      canvas.drawRRect(
        rrect.shift(const Offset(0, 1)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.10)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
      );
      // Tile fill.
      canvas.drawRRect(rrect, Paint()..color = tileColor);
      // Top inner highlight — gives the glossy 3D effect.
      canvas.save();
      canvas.clipRRect(rrect);
      canvas.drawRect(
        Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height * 0.45),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: 0.45),
              Colors.white.withValues(alpha: 0.0),
            ],
          ).createShader(rect),
      );
      canvas.restore();
    }

    // Faint outer outline of the entire board.
    _drawBoardOutline(canvas, s);
  }

  void _paintSnake(Canvas canvas, Size s) {
    // Smooth S-curve snake. We draw the body as a stroked Path with
    // round line caps so adjacent segments visually merge into a
    // single tube — the blocky rounded-rect zigzag from the previous
    // version read as a chain of squares, not a snake. Lime `#4ADE80`
    // head → darker green `#16A34A` tail gradient matches the
    // canonical Snake.io look from the research pass.
    final accentLime = const Color(0xFF4ADE80);
    final accentTail = const Color(0xFF16A34A);
    final tubeWidth = s.width * 0.085;
    final headR = tubeWidth * 0.95;
    final tailR = tubeWidth * 0.45;

    // Apple position — top-left.
    final appleCenter = Offset(s.width * 0.20, s.height * 0.28);

    // Apple (red disc + white highlight + green leaf).
    canvas.drawCircle(
      appleCenter,
      s.width * 0.06,
      Paint()..color = const Color(0xFFFF3B30),
    );
    canvas.drawCircle(
      appleCenter.translate(-s.width * 0.02, -s.width * 0.02),
      s.width * 0.018,
      Paint()..color = Colors.white.withValues(alpha: 0.55),
    );
    final leafPath = Path()
      ..moveTo(appleCenter.dx, appleCenter.dy - s.width * 0.06)
      ..quadraticBezierTo(
        appleCenter.dx + s.width * 0.035,
        appleCenter.dy - s.width * 0.085,
        appleCenter.dx + s.width * 0.012,
        appleCenter.dy - s.width * 0.045,
      )
      ..close();
    canvas.drawPath(leafPath, Paint()..color = const Color(0xFF22C55E));

    // S-curve path: head at top-right (near apple), tail at bottom-left.
    // Five control points yield a clean sinusoidal shape that reads
    // as "snake" at a glance even on small cards.
    final path = Path()
      ..moveTo(s.width * 0.85, s.height * 0.28)
      ..cubicTo(
        s.width * 0.85, s.height * 0.10,
        s.width * 0.25, s.height * 0.18,
        s.width * 0.25, s.height * 0.45,
      )
      ..cubicTo(
        s.width * 0.25, s.height * 0.72,
        s.width * 0.85, s.height * 0.62,
        s.width * 0.85, s.height * 0.85,
      );

    // Body shadow underneath the tube for a sense of depth.
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.15)
        ..strokeWidth = tubeWidth + 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    // Gradient body — lime head → darker tail. We approximate with a
    // two-stop linear gradient along the path direction.
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [accentLime, accentTail],
        ).createShader(Rect.fromLTWH(0, 0, s.width, s.height))
        ..strokeWidth = tubeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    // Top highlight stripe for dimensionality.
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.25)
        ..strokeWidth = tubeWidth * 0.25
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Head — solid disc at the path start, slightly larger than the
    // tube so the merge looks deliberate.
    final headCenter = Offset(s.width * 0.85, s.height * 0.28);
    canvas.drawCircle(
      headCenter,
      headR,
      Paint()..color = accentLime,
    );
    canvas.drawCircle(
      headCenter,
      headR,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    // Eyes — two small white circles with black pupils, facing the
    // direction of travel (toward the apple, i.e. left + up).
    canvas.drawCircle(
      headCenter.translate(-headR * 0.55, -headR * 0.30),
      headR * 0.28,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      headCenter.translate(-headR * 0.55, -headR * 0.30),
      headR * 0.14,
      Paint()..color = const Color(0xFF0E1730),
    );
    canvas.drawCircle(
      headCenter.translate(-headR * 0.30, -headR * 0.50),
      headR * 0.28,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      headCenter.translate(-headR * 0.30, -headR * 0.50),
      headR * 0.14,
      Paint()..color = const Color(0xFF0E1730),
    );
    // Forked red tongue flicking out toward the apple.
    final tongue = Path()
      ..moveTo(headCenter.dx - headR * 0.85, headCenter.dy - headR * 0.05)
      ..lineTo(
          headCenter.dx - headR * 1.65, headCenter.dy - headR * 0.35)
      ..moveTo(headCenter.dx - headR * 1.30, headCenter.dy - headR * 0.20)
      ..lineTo(
          headCenter.dx - headR * 1.65, headCenter.dy - headR * 0.35)
      ..moveTo(headCenter.dx - headR * 1.30, headCenter.dy - headR * 0.20)
      ..lineTo(
          headCenter.dx - headR * 1.65, headCenter.dy - headR * 0.05);
    canvas.drawPath(
      tongue,
      Paint()
        ..color = const Color(0xFFFF3B30)
        ..strokeWidth = headR * 0.20
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Tail — small darker disc at the path end, slightly tapered.
    final tailCenter = Offset(s.width * 0.85, s.height * 0.85);
    canvas.drawCircle(
      tailCenter,
      tailR,
      Paint()..color = accentTail,
    );

    // Subtle accent ring inside the card to echo the playfield vibe.
    canvas.drawCircle(
      Offset(s.width * 0.5, s.height * 0.5),
      s.width * 0.46,
      Paint()
        ..color = (brightness == Brightness.dark
                ? Colors.white
                : const Color(0xFF1E3A8A))
            .withValues(alpha: 0.06)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  void _paint2048(Canvas canvas, Size s) {
    final cell = s.width / 2;
    final gap = cell * 0.12;

    final empty = Paint()
      ..color = brightness == Brightness.dark
          ? Colors.white.withValues(alpha: 0.08)
          : Colors.black.withValues(alpha: 0.06);
    final accentPaint = Paint()..color = accent;

    for (var r = 0; r < 2; r++) {
      for (var c = 0; c < 2; c++) {
        final rect = Rect.fromLTWH(
          c * cell + gap,
          r * cell + gap,
          cell - gap * 2,
          cell - gap * 2,
        );
        final isAccent = r == 0 && c == 0;
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(8)),
          isAccent ? accentPaint : empty,
        );
      }
    }
    final tp = TextPainter(
      text: TextSpan(
        text: '2',
        style: TextStyle(
          color: brightness == Brightness.dark ? Colors.black : Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: cell * 0.55,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(minWidth: 0, maxWidth: cell);
    tp.paint(
      canvas,
      Offset(
        cell * 0.5 - tp.width / 2,
        cell * 0.5 - tp.height / 2,
      ),
    );
  }

  void _paintWaterSort(Canvas canvas, Size s) {
    // Tile: 3 glass test tubes, each partially filled with a different
    // liquid color, drawn against a soft violet→indigo gradient so the
    // transparent glass reads at tile size.
    final bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF1E1B4B), Color(0xFF4C1D95)],
      ).createShader(Rect.fromLTWH(0, 0, s.width, s.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, s.width, s.height), bg);

    final tubeCount = 3;
    final tubeW = s.width / (tubeCount + 0.4);
    final gap = tubeW * 0.25;
    final startX =
        (s.width - (tubeW * tubeCount + gap * (tubeCount - 1))) / 2;
    final tubeH = s.height * 0.78;
    final tubeTop = (s.height - tubeH) / 2;

    // Liquid palette: cherry red, leaf green, sky blue.
    const liquids = [
      Color(0xFFFF5252),
      Color(0xFF4ADE80),
      Color(0xFF38BDF8),
    ];
    // Fill ratios per tube: 2 of 4, 3 of 4, 1 of 4 — sells the puzzle.
    const fills = [0.50, 0.75, 0.25];

    for (var i = 0; i < tubeCount; i++) {
      final x = startX + i * (tubeW + gap);
      final rect = Rect.fromLTWH(x, tubeTop, tubeW, tubeH);

      // Tube glass body — faint inner fill so it reads as hollow.
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          rect,
          bottomLeft: Radius.circular(tubeW * 0.40),
          bottomRight: Radius.circular(tubeW * 0.40),
          topLeft: Radius.circular(tubeW * 0.16),
          topRight: Radius.circular(tubeW * 0.16),
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.10),
      );

      // Liquid layer (clipped to inner cavity).
      final fillH = tubeH * fills[i];
      final liquidRect = Rect.fromLTRB(
        rect.left + tubeW * 0.08,
        rect.bottom - tubeW * 0.10 - fillH,
        rect.right - tubeW * 0.08,
        rect.bottom - tubeW * 0.10,
      );
      canvas.save();
      canvas.clipRRect(
        RRect.fromRectAndCorners(
          liquidRect,
          bottomLeft: Radius.circular(tubeW * 0.34),
          bottomRight: Radius.circular(tubeW * 0.34),
          topLeft: const Radius.circular(2),
          topRight: const Radius.circular(2),
        ),
      );
      // Vertical gradient on the liquid for depth.
      canvas.drawRect(
        liquidRect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              liquids[i].withValues(alpha: 0.95),
              liquids[i],
              liquids[i].withValues(alpha: 0.78),
            ],
          ).createShader(liquidRect),
      );
      // Inner highlight strip on the left for the "wet" look.
      canvas.drawRect(
        Rect.fromLTWH(
          liquidRect.left + tubeW * 0.10,
          liquidRect.top + tubeW * 0.05,
          tubeW * 0.10,
          liquidRect.height - tubeW * 0.10,
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.30),
      );
      canvas.restore();

      // Glass outline — thick white stroke.
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          rect,
          bottomLeft: Radius.circular(tubeW * 0.40),
          bottomRight: Radius.circular(tubeW * 0.40),
          topLeft: Radius.circular(tubeW * 0.16),
          topRight: Radius.circular(tubeW * 0.16),
        ),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = tubeW * 0.06,
      );

      // Specular highlight on the left edge for premium glass feel.
      canvas.drawLine(
        Offset(rect.left + tubeW * 0.18, rect.top + tubeH * 0.10),
        Offset(rect.left + tubeW * 0.18, rect.bottom - tubeH * 0.15),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.45)
          ..strokeWidth = tubeW * 0.06
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _paintMemoryMatch(Canvas canvas, Size s) {
    final cell = s.width / 2;
    final gap = cell * 0.12;

    final faceDown = Paint()
      ..color = brightness == Brightness.dark
          ? Colors.white.withValues(alpha: 0.12)
          : Colors.black.withValues(alpha: 0.10);

    // Top-left card: accent face-up with a fruit glyph (🍎).
    // Top-right & bottom-left: face-down (decorative pattern, no '?').
    // Bottom-right: face-up with a different fruit (🍌).
    final cards = <List<dynamic>>[
      [true, '🍎'],
      [false, null],
      [false, null],
      [true, '🍌'],
    ];

    var i = 0;
    for (var r = 0; r < 2; r++) {
      for (var c = 0; c < 2; c++) {
        final faceUp = cards[i][0] as bool;
        final glyph = cards[i][1] as String?;
        i++;
        final rect = Rect.fromLTWH(
          c * cell + gap,
          r * cell + gap,
          cell - gap * 2,
          cell - gap * 2,
        );
        if (faceUp) {
          // White card with accent stripe + emoji glyph.
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(8)),
            Paint()
              ..color = brightness == Brightness.dark
                  ? Colors.white
                  : const Color(0xFFFFFFFF),
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(8)),
            Paint()
              ..color = accent.withValues(alpha: 0.85)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2,
          );
          if (glyph != null) {
            final tp = TextPainter(
              text: TextSpan(
                text: glyph,
                style: TextStyle(fontSize: cell * 0.55),
              ),
              textDirection: TextDirection.ltr,
            )..layout();
            tp.paint(
              canvas,
              Offset(
                rect.center.dx - tp.width / 2,
                rect.center.dy - tp.height / 2,
              ),
            );
          }
        } else {
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(8)),
            faceDown,
          );
          // Decorative diamond pattern instead of '?'.
          canvas.save();
          canvas.clipRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(8)),
          );
          final diamondColor = Paint()
            ..color = accent.withValues(alpha: 0.35);
          final cx = rect.center.dx;
          final cy = rect.center.dy;
          final d = cell * 0.18;
          final path = Path()
            ..moveTo(cx, cy - d)
            ..lineTo(cx + d, cy)
            ..lineTo(cx, cy + d)
            ..lineTo(cx - d, cy)
            ..close();
          canvas.drawPath(path, diamondColor);
          canvas.restore();
        }
      }
    }
  }

  void _paintTicTacToe(Canvas canvas, Size s) {
    final cell = s.width / 3;
    final stroke = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(cell, 0), Offset(cell, s.height), stroke);
    canvas.drawLine(Offset(cell * 2, 0), Offset(cell * 2, s.height), stroke);
    canvas.drawLine(Offset(0, cell), Offset(s.width, cell), stroke);
    canvas.drawLine(Offset(0, cell * 2), Offset(s.width, cell * 2), stroke);

    final x = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = cell * 0.18
      ..strokeCap = StrokeCap.round;
    void drawCross(Offset c) {
      // Diagonal 1 — top-left → bottom-right.
      canvas.drawLine(
        c + const Offset(-1, -1) * cell * 0.28,
        c + const Offset(1, 1) * cell * 0.28,
        x,
      );
      // Diagonal 2 — top-right → bottom-left.
      canvas.drawLine(
        c + const Offset(1, -1) * cell * 0.28,
        c + const Offset(-1, 1) * cell * 0.28,
        x,
      );
    }

    drawCross(Offset(cell * 0.5, cell * 0.5));
    drawCross(Offset(cell * 1.5, cell * 1.5));

    final ring = Paint()
      ..color = const Color(0xFFFFD166)
      ..style = PaintingStyle.stroke
      ..strokeWidth = cell * 0.18;
    final center = Offset(cell * 2.5, cell * 0.5);
    canvas.drawCircle(center, cell * 0.28, ring);
  }

  void _paintFourInARow(Canvas canvas, Size s) {
    final slot = s.width / 3;
    final gap = slot * 0.18;
    final r = (slot - gap * 2) / 2;

    final colors = <Color>[
      const Color(0xFFEF4444),
      const Color(0xFFFACC15),
      const Color(0xFFEF4444),
      const Color(0xFFFACC15),
    ];
    for (var i = 0; i < 4; i++) {
      final center = Offset(s.width / 2, slot + i * slot);
      final fill = Paint()..color = colors[i];
      canvas.drawCircle(center, r, fill);
      final hl = Paint()
        ..color = Colors.white.withValues(alpha: 0.18);
      canvas.drawCircle(
        Offset(center.dx - r * 0.35, center.dy - r * 0.35),
        r * 0.18,
        hl,
      );
    }
  }

  void _paintCarrom(Canvas canvas, Size s) {
    final inset = s.width * 0.06;
    final boardRect = Rect.fromLTWH(
      inset,
      inset,
      s.width - inset * 2,
      s.height - inset * 2,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(boardRect, const Radius.circular(8)),
      Paint()..color = const Color(0xFFFDE68A),
    );
    canvas.drawCircle(
      boardRect.center,
      boardRect.width * 0.18,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.drawCircle(
      boardRect.center,
      boardRect.width * 0.05,
      Paint()..color = accent,
    );

    final pocketR = boardRect.width * 0.06;
    final pocketOffsets = [
      Offset(boardRect.left + 8, boardRect.top + 8),
      Offset(boardRect.right - 8, boardRect.top + 8),
      Offset(boardRect.left + 8, boardRect.bottom - 8),
      Offset(boardRect.right - 8, boardRect.bottom - 8),
    ];
    for (final p in pocketOffsets) {
      canvas.drawCircle(p, pocketR, Paint()..color = Colors.black87);
    }

    canvas.drawCircle(
      boardRect.center + Offset(-boardRect.width * 0.10, 0),
      boardRect.width * 0.045,
      Paint()..color = const Color(0xFFB91C1C),
    );
    canvas.drawCircle(
      boardRect.center + Offset(boardRect.width * 0.10, 0),
      boardRect.width * 0.045,
      Paint()..color = const Color(0xFF1E3A8A),
    );
  }

  /// Mini Pool — green-felt table with cue ball and a rack of
  /// striped + solid balls. Used for the simplified drag-and-pocket
  /// variant.
  void _paintMiniPool(Canvas canvas, Size s) {
    final inset = s.width * 0.06;
    final boardRect = Rect.fromLTWH(
      inset,
      inset + s.height * 0.04,
      s.width - inset * 2,
      s.height - inset * 2 - s.height * 0.04,
    );

    // Wooden rail frame.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        boardRect.inflate(s.width * 0.025),
        const Radius.circular(10),
      ),
      Paint()..color = const Color(0xFF6B4226),
    );
    // Felt.
    canvas.drawRRect(
      RRect.fromRectAndRadius(boardRect, const Radius.circular(6)),
      Paint()..color = const Color(0xFF15803D),
    );
    // Centre line + baulk.
    canvas.drawLine(
      Offset(boardRect.center.dx, boardRect.top),
      Offset(boardRect.center.dx, boardRect.bottom),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.18)
        ..strokeWidth = 1,
    );

    // Pockets.
    final pocketR = boardRect.width * 0.045;
    final pocketPositions = [
      Offset(boardRect.left + 6, boardRect.top + 6),
      Offset(boardRect.center.dx, boardRect.top + 4),
      Offset(boardRect.right - 6, boardRect.top + 6),
      Offset(boardRect.left + 6, boardRect.bottom - 6),
      Offset(boardRect.center.dx, boardRect.bottom - 4),
      Offset(boardRect.right - 6, boardRect.bottom - 6),
    ];
    for (final p in pocketPositions) {
      canvas.drawCircle(p, pocketR, Paint()..color = Colors.black87);
    }

    // Cue ball (white) on the left.
    final ballR = boardRect.width * 0.038;
    final cuePos = Offset(
      boardRect.left + boardRect.width * 0.22,
      boardRect.center.dy,
    );
    canvas.drawCircle(cuePos, ballR, Paint()..color = Colors.white);
    // Subtle shadow.
    canvas.drawCircle(
      cuePos + Offset(1, 2),
      ballR,
      Paint()..color = Colors.black.withValues(alpha: 0.25),
    );

    // Rack of 5 striped + solid balls on the right.
    final colors = [
      const Color(0xFFFCD34D),
      const Color(0xFFEF4444),
      const Color(0xFF1E3A8A),
      const Color(0xFFEC4899),
      const Color(0xFF8B5CF6),
    ];
    final rackCx = boardRect.right - boardRect.width * 0.22;
    final rackCy = boardRect.center.dy;
    final dx = ballR * 2.05;
    final dy = ballR * 1.78;
    // Triangle: row 0 has 1 ball, row 1 has 2, row 2 has 2.
    final offsets = <List<Offset>>[
      [Offset(0, 0)],
      [Offset(-dx, -dy), Offset(-dx, dy)],
      [Offset(-dx * 2, -dy * 1.5), Offset(-dx * 2, dy * 1.5)],
    ];
    for (final row in offsets) {
      for (var i = 0; i < row.length; i++) {
        final pos = Offset(rackCx + row[i].dx, rackCy + row[i].dy);
        canvas.drawCircle(
          pos + const Offset(1, 2),
          ballR,
          Paint()..color = Colors.black.withValues(alpha: 0.25),
        );
        canvas.drawCircle(pos, ballR, Paint()..color = colors[i + row.indexOf(row[i])]);
      }
    }
  }

  /// Billiards 8-Ball — blue-felt table with the iconic 8-ball front
  /// and centre, surrounded by 6 object balls (solids + stripes).
  void _paintBilliards(Canvas canvas, Size s) {
    final inset = s.width * 0.06;
    final boardRect = Rect.fromLTWH(
      inset,
      inset + s.height * 0.04,
      s.width - inset * 2,
      s.height - inset * 2 - s.height * 0.04,
    );

    // Wooden rail.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        boardRect.inflate(s.width * 0.025),
        const Radius.circular(10),
      ),
      Paint()..color = const Color(0xFF6B4226),
    );
    // Royal-blue felt.
    canvas.drawRRect(
      RRect.fromRectAndRadius(boardRect, const Radius.circular(6)),
      Paint()..color = const Color(0xFF1E40AF),
    );
    // Subtle vignette.
    canvas.drawRRect(
      RRect.fromRectAndRadius(boardRect, const Radius.circular(6)),
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.35),
          ],
        ).createShader(boardRect),
    );

    // Pockets.
    final pocketR = boardRect.width * 0.05;
    final pocketPositions = [
      Offset(boardRect.left + 4, boardRect.top + 4),
      Offset(boardRect.center.dx, boardRect.top + 2),
      Offset(boardRect.right - 4, boardRect.top + 4),
      Offset(boardRect.left + 4, boardRect.bottom - 4),
      Offset(boardRect.center.dx, boardRect.bottom - 2),
      Offset(boardRect.right - 4, boardRect.bottom - 4),
    ];
    for (final p in pocketPositions) {
      canvas.drawCircle(p, pocketR, Paint()..color = Colors.black);
    }

    // Center spot + diamond.
    canvas.drawCircle(
      boardRect.center,
      boardRect.width * 0.04,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Cue ball (white) on the left.
    final ballR = boardRect.width * 0.042;
    final cuePos = Offset(
      boardRect.left + boardRect.width * 0.22,
      boardRect.center.dy,
    );
    canvas.drawCircle(
      cuePos + const Offset(1, 2),
      ballR,
      Paint()..color = Colors.black.withValues(alpha: 0.3),
    );
    canvas.drawCircle(cuePos, ballR, Paint()..color = Colors.white);
    // Pool cue stick behind the cue ball.
    final stickStart = Offset(
      cuePos.dx - boardRect.width * 0.10,
      cuePos.dy + boardRect.height * 0.35,
    );
    final stickEnd = Offset(
      cuePos.dx - boardRect.width * 0.02,
      cuePos.dy + ballR * 0.7,
    );
    canvas.drawLine(
      stickStart,
      stickEnd,
      Paint()
        ..color = const Color(0xFFFDE68A)
        ..strokeWidth = ballR * 0.4
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      stickStart + Offset(0, ballR * 0.5),
      stickStart + Offset(0, -ballR * 0.4),
      Paint()
        ..color = const Color(0xFF7C2D12)
        ..strokeWidth = ballR * 0.5
        ..strokeCap = StrokeCap.round,
    );

    // Right side: prominent 8-ball centre + 3 object balls.
    final eightPos = Offset(
      boardRect.right - boardRect.width * 0.26,
      boardRect.center.dy,
    );
    canvas.drawCircle(
      eightPos + const Offset(1, 2),
      ballR,
      Paint()..color = Colors.black.withValues(alpha: 0.3),
    );
    canvas.drawCircle(eightPos, ballR, Paint()..color = const Color(0xFF111111));
    canvas.drawCircle(eightPos, ballR * 0.55, Paint()..color = Colors.white);
    canvas.drawCircle(eightPos, ballR * 0.22, Paint()..color = const Color(0xFF111111));

    final dx = ballR * 2.0;
    final dy = ballR * 1.8;
    final sideColors = [
      const Color(0xFFFCD34D), // solid 1 — yellow
      const Color(0xFFEF4444), // solid 3 — red
      const Color(0xFFEC4899), // stripe 11 — pink
    ];
    final sidePos = [
      Offset(eightPos.dx + dx, eightPos.dy - dy),
      Offset(eightPos.dx + dx, eightPos.dy + dy),
      Offset(eightPos.dx + dx * 1.8, eightPos.dy),
    ];
    for (var i = 0; i < sidePos.length; i++) {
      final p = sidePos[i];
      canvas.drawCircle(
        p + const Offset(1, 2),
        ballR,
        Paint()..color = Colors.black.withValues(alpha: 0.3),
      );
      canvas.drawCircle(p, ballR, Paint()..color = sideColors[i]);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // New recipes
  // ─────────────────────────────────────────────────────────────

  /// Mini Ludo — square board with 4 colored home quadrants + a
  /// central cross-shaped finish slot.
  void _paintMiniLudo(Canvas canvas, Size s) {
    final cell = s.width / 6;
    final gap = cell * 0.12;

    // Board outline.
    final board = Rect.fromLTWH(0, 0, s.width, s.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(board, const Radius.circular(10)),
      Paint()
        ..color = brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.10)
            : Colors.black.withValues(alpha: 0.08),
    );

    // 4 colored corner squares.
    final corners = <Offset, Color>{
      Offset.zero: const Color(0xFFEF4444),
      Offset(s.width - cell * 2, 0): const Color(0xFF22C55E),
      Offset(0, s.height - cell * 2): const Color(0xFFFACC15),
      Offset(s.width - cell * 2, s.height - cell * 2): const Color(0xFF3B82F6),
    };
    for (final entry in corners.entries) {
      final rect = Rect.fromLTWH(
        entry.key.dx + gap,
        entry.key.dy + gap,
        cell * 2 - gap * 2,
        cell * 2 - gap * 2,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        Paint()..color = entry.value.withValues(alpha: 0.85),
      );
    }

    // Center diamond.
    final cx = s.width / 2;
    final cy = s.height / 2;
    final path = Path()
      ..moveTo(cx, cy - cell * 0.9)
      ..lineTo(cx + cell * 0.9, cy)
      ..lineTo(cx, cy + cell * 0.9)
      ..lineTo(cx - cell * 0.9, cy)
      ..close();
    canvas.drawPath(
      path,
      Paint()..color = accent.withValues(alpha: 0.95),
    );
  }

  /// Minesweeper — 3×3 grid; one cell shows a mine, others show
  /// numeric counters (1, 2, 3).
  void _paintMinesweeper(Canvas canvas, Size s) {
    final n = 3;
    final cell = s.width / n;
    final gap = cell * 0.10;

    final cellFill = Paint()
      ..color = brightness == Brightness.dark
          ? Colors.white.withValues(alpha: 0.12)
          : Colors.black.withValues(alpha: 0.10);

    final labels = <String, Color>{
      '1': const Color(0xFF3B82F6),
      '2': const Color(0xFF22C55E),
      '3': const Color(0xFFEF4444),
    };

    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        final rect = Rect.fromLTWH(
          c * cell + gap,
          r * cell + gap,
          cell - gap * 2,
          cell - gap * 2,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(4)),
          cellFill,
        );
        String? text;
        Color? color;
        if (r == 0 && c == 2) {
          // mine — accent disc with prongs.
          canvas.drawCircle(rect.center, cell * 0.20, Paint()..color = accent);
          final prong = Paint()
            ..color = Colors.black87
            ..strokeWidth = cell * 0.06
            ..strokeCap = StrokeCap.round;
          canvas.drawLine(
            rect.center + Offset(-cell * 0.30, 0),
            rect.center + Offset(cell * 0.30, 0),
            prong,
          );
          canvas.drawLine(
            rect.center + Offset(0, -cell * 0.30),
            rect.center + Offset(0, cell * 0.30),
            prong,
          );
        } else if (r == 0 && c == 0) {
          text = '1';
          color = labels['1'];
        } else if (r == 1 && c == 1) {
          text = '2';
          color = labels['2'];
        } else if (r == 2 && c == 0) {
          text = '3';
          color = labels['3'];
        }
        if (text != null) {
          final tp = TextPainter(
            text: TextSpan(
              text: text,
              style: TextStyle(
                color: color,
                fontSize: cell * 0.45,
                fontWeight: FontWeight.w900,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(
            canvas,
            Offset(
              rect.center.dx - tp.width / 2,
              rect.center.dy - tp.height / 2,
            ),
          );
        }
      }
    }
  }

  /// Bangla Word Connect — grid of Bengali syllables connected by
  /// accent strokes.
  void _paintBanglaWordConnect(Canvas canvas, Size s) {
    final cell = s.width / 4;
    final letters = ['ক', 'ল', 'ম', 'ন'];

    final dotPaint = Paint()
      ..color = accent
      ..style = PaintingStyle.fill;

    final positions = <Offset>[
      Offset(cell * 0.7, cell * 0.7),
      Offset(cell * 1.7, cell * 1.7),
      Offset(cell * 2.7, cell * 2.7),
      Offset(cell * 3.3, cell * 0.7),
    ];

    // Connecting line through all four.
    final path = Path()..moveTo(positions[0].dx, positions[0].dy);
    for (var i = 1; i < positions.length; i++) {
      path.lineTo(positions[i].dx, positions[i].dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = accent.withValues(alpha: 0.55)
        ..strokeWidth = cell * 0.20
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // Letter dots.
    for (var i = 0; i < positions.length; i++) {
      final p = positions[i];
      canvas.drawCircle(p, cell * 0.45, dotPaint);
      final tp = TextPainter(
        text: TextSpan(
          text: letters[i],
          style: TextStyle(
            color: brightness == Brightness.dark
                ? Colors.black
                : Colors.white,
            fontSize: cell * 0.45,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(p.dx - tp.width / 2, p.dy - tp.height / 2));
    }
  }

  /// Bangla Word Search — magnifying glass over a grid of letters.
  void _paintBanglaWordSearch(Canvas canvas, Size s) {
    final cell = s.width / 4;

    // Grid background.
    final gridPaint = Paint()
      ..color = brightness == Brightness.dark
          ? Colors.white.withValues(alpha: 0.08)
          : Colors.black.withValues(alpha: 0.06);
    final gridRect = Rect.fromLTWH(cell * 0.5, cell * 0.5, cell * 3, cell * 3);
    canvas.drawRRect(
      RRect.fromRectAndRadius(gridRect, const Radius.circular(6)),
      gridPaint,
    );

    // Letters.
    final letters = ['ব', 'া', 'ং', 'ল', 'া', 'দ', 'ে', 'শ'];
    for (var i = 0; i < letters.length; i++) {
      final r = i ~/ 3;
      final c = i % 3;
      final pos = Offset(cell * 1.5 + c * cell, cell * 1.5 + r * cell);
      final tp = TextPainter(
        text: TextSpan(
          text: letters[i],
          style: TextStyle(
            color: brightness == Brightness.dark
                ? Colors.white70
                : Colors.black87,
            fontSize: cell * 0.42,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy - tp.height / 2));
    }

    // Magnifying glass.
    final lensCenter = Offset(s.width * 0.78, s.height * 0.78);
    final lensR = s.width * 0.20;
    canvas.drawCircle(
      lensCenter,
      lensR,
      Paint()
        ..color = accent.withValues(alpha: 0.35),
    );
    canvas.drawCircle(
      lensCenter,
      lensR,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell * 0.16,
    );
    // Handle.
    final handleStart = lensCenter + Offset(lensR * 0.7, lensR * 0.7);
    final handleEnd = handleStart + Offset(cell * 0.5, cell * 0.5);
    canvas.drawLine(
      handleStart,
      handleEnd,
      Paint()
        ..color = accent
        ..strokeWidth = cell * 0.20
        ..strokeCap = StrokeCap.round,
    );
  }

  /// Bangladesh Quiz — academic book / quiz badge with the
  /// Bangladesh flag circle.
  void _paintBangladeshQuiz(Canvas canvas, Size s) {
    final cx = s.width / 2;
    final cy = s.height / 2;
    final r = s.width * 0.32;

    // Outer ring.
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..color = accent.withValues(alpha: 0.25),
    );

    // Book pages (folded paper).
    final book = Rect.fromCenter(
      center: Offset(cx, cy),
      width: r * 1.6,
      height: r * 1.1,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(book, const Radius.circular(6)),
      Paint()..color = brightness == Brightness.dark
          ? Colors.white
          : const Color(0xFFF1F5F9),
    );
    // Center spine.
    canvas.drawLine(
      Offset(cx, book.top + 4),
      Offset(cx, book.bottom - 4),
      Paint()
        ..color = accent.withValues(alpha: 0.5)
        ..strokeWidth = 1.5,
    );

    // Three horizontal text lines on the right page (decorative
    // "quiz content" — no '?' glyph).
    final linePaint = Paint()
      ..color = accent.withValues(alpha: 0.5)
      ..strokeWidth = 1.5;
    for (var i = 0; i < 3; i++) {
      final y = book.top + 6 + i * (book.height - 12) / 3;
      canvas.drawLine(
        Offset(cx + 4, y),
        Offset(book.right - 6, y),
        linePaint,
      );
    }

    // BD flag circle — green disc with red dot.
    final flagCx = Offset(s.width * 0.20, s.height * 0.22);
    final flagR = s.width * 0.10;
    canvas.drawCircle(flagCx, flagR, Paint()..color = const Color(0xFF22C55E));
    canvas.drawCircle(
      flagCx + Offset(flagR * 0.55, 0),
      flagR * 0.32,
      Paint()..color = const Color(0xFFEF4444),
    );
  }

  /// Sudoku — 3×3 mini-grid with one or two filled cells showing
  /// numbers (1, 2, 3).
  void _paintSudoku(Canvas canvas, Size s) {
    final n = 3;
    final cell = s.width / n;
    final gap = cell * 0.08;

    final cellFill = Paint()
      ..color = brightness == Brightness.dark
          ? Colors.white.withValues(alpha: 0.12)
          : Colors.black.withValues(alpha: 0.10);

    final numbers = <int, String>{
      0: '1',
      2: '3',
      4: '2',
      8: '9',
    };

    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        final idx = r * n + c;
        final rect = Rect.fromLTWH(
          c * cell + gap,
          r * cell + gap,
          cell - gap * 2,
          cell - gap * 2,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(4)),
          cellFill,
        );
        final n_ = numbers[idx];
        if (n_ != null) {
          final isAccent = idx == 0 || idx == 8;
          final tp = TextPainter(
            text: TextSpan(
              text: n_,
              style: TextStyle(
                color: isAccent
                    ? accent
                    : (brightness == Brightness.dark
                        ? Colors.white
                        : Colors.black87),
                fontSize: cell * 0.45,
                fontWeight: FontWeight.w900,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(
            canvas,
            Offset(
              rect.center.dx - tp.width / 2,
              rect.center.dy - tp.height / 2,
            ),
          );
        }
      }
    }

    // Outer bold border to read as a sudoku subgrid.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, s.width, s.height),
        const Radius.circular(6),
      ),
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  /// Tile Match — Cute 3D kitten face on a sunny yellow background.
  ///
  /// Visual recipe:
  ///   * Warm yellow rounded-square background.
  ///   * Pink nose triangle.
  ///   * Two large round eyes with accent iris + white highlight.
  ///   * Whisker dots + tiny smile.
  void _paintTileMatch(Canvas canvas, Size s) {
    final cx = s.width / 2;
    final cy = s.height / 2;

    // Two triangular ears (top-left + top-right).
    final ear = Path()
      ..moveTo(cx - s.width * 0.32, cy - s.height * 0.18)
      ..lineTo(cx - s.width * 0.10, cy - s.height * 0.42)
      ..lineTo(cx - s.width * 0.20, cy - s.height * 0.08)
      ..close();
    canvas.drawPath(ear, Paint()..color = accent);
    final ear2 = Path()
      ..moveTo(cx + s.width * 0.32, cy - s.height * 0.18)
      ..lineTo(cx + s.width * 0.10, cy - s.height * 0.42)
      ..lineTo(cx + s.width * 0.20, cy - s.height * 0.08)
      ..close();
    canvas.drawPath(ear2, Paint()..color = accent);

    // Inner-ear pink.
    final innerEar = Path()
      ..moveTo(cx - s.width * 0.26, cy - s.height * 0.18)
      ..lineTo(cx - s.width * 0.16, cy - s.height * 0.32)
      ..lineTo(cx - s.width * 0.18, cy - s.height * 0.12)
      ..close();
    canvas.drawPath(innerEar, Paint()..color = const Color(0xFFFFB199));
    final innerEar2 = Path()
      ..moveTo(cx + s.width * 0.26, cy - s.height * 0.18)
      ..lineTo(cx + s.width * 0.16, cy - s.height * 0.32)
      ..lineTo(cx + s.width * 0.18, cy - s.height * 0.12)
      ..close();
    canvas.drawPath(innerEar2, Paint()..color = const Color(0xFFFFB199));

    // Head — large accent circle.
    final headR = s.width * 0.32;
    canvas.drawCircle(
      Offset(cx, cy + s.height * 0.04),
      headR,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(accent, Colors.white, 0.20) ?? accent,
            accent,
          ],
        ).createShader(
          Rect.fromCircle(
            center: Offset(cx, cy + s.height * 0.04),
            radius: headR,
          ),
        ),
    );

    // Cheek blush — two small coral dots.
    canvas.drawCircle(
      Offset(cx - s.width * 0.20, cy + s.height * 0.10),
      s.width * 0.05,
      Paint()..color = const Color(0xFFFF6584).withValues(alpha: 0.55),
    );
    canvas.drawCircle(
      Offset(cx + s.width * 0.20, cy + s.height * 0.10),
      s.width * 0.05,
      Paint()..color = const Color(0xFFFF6584).withValues(alpha: 0.55),
    );

    // Eyes — white circles + accent iris + black pupil + white glint.
    final eyeY = cy - s.height * 0.02;
    final eyeOffsetX = s.width * 0.13;
    final eyeR = s.width * 0.07;
    final pupilR = s.width * 0.04;
    final glintR = s.width * 0.02;
    for (final sign in [-1, 1]) {
      final ex = cx + sign * eyeOffsetX;
      canvas.drawCircle(Offset(ex, eyeY), eyeR, Paint()..color = Colors.white);
      canvas.drawCircle(Offset(ex, eyeY), pupilR, Paint()..color = Colors.black);
      canvas.drawCircle(
        Offset(ex + eyeR * 0.35, eyeY - eyeR * 0.35),
        glintR,
        Paint()..color = Colors.white,
      );
    }

    // Nose — small pink triangle.
    final nose = Path()
      ..moveTo(cx, cy + s.height * 0.06)
      ..lineTo(cx - s.width * 0.04, cy + s.height * 0.12)
      ..lineTo(cx + s.width * 0.04, cy + s.height * 0.12)
      ..close();
    canvas.drawPath(nose, Paint()..color = const Color(0xFFFF6584));

    // Smile — small mouth arc.
    final smile = Path()
      ..moveTo(cx - s.width * 0.06, cy + s.height * 0.18)
      ..quadraticBezierTo(
        cx,
        cy + s.height * 0.24,
        cx + s.width * 0.06,
        cy + s.height * 0.18,
      );
    canvas.drawPath(
      smile,
      Paint()
        ..color = const Color(0xFF1F2937)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s.width * 0.012
        ..strokeCap = StrokeCap.round,
    );

    // Whiskers — three short lines per side.
    final whisker = Paint()
      ..color = const Color(0xFF1F2937).withValues(alpha: 0.6)
      ..strokeWidth = s.width * 0.008
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final wy = cy + s.height * 0.10 + i * s.height * 0.04;
      canvas.drawLine(
        Offset(cx - s.width * 0.10, wy),
        Offset(cx - s.width * 0.36, wy - s.height * 0.02),
        whisker,
      );
      canvas.drawLine(
        Offset(cx + s.width * 0.10, wy),
        Offset(cx + s.width * 0.36, wy - s.height * 0.02),
        whisker,
      );
    }
  }

  /// Connect Lines — pairs of dots connected by accent paths (a
  /// 2×2 of small flow-free segments).
  void _paintConnectLines(Canvas canvas, Size s) {
    final cell = s.width / 4;

    final dotColors = [
      accent,
      const Color(0xFFEF4444),
      const Color(0xFFFACC15),
      const Color(0xFF3B82F6),
    ];

    final pairs = <List<Offset>>[
      [
        Offset(cell * 0.7, cell * 0.7),
        Offset(cell * 3.3, cell * 0.7),
      ],
      [
        Offset(cell * 3.3, cell * 0.7),
        Offset(cell * 3.3, cell * 3.3),
      ],
      [
        Offset(cell * 0.7, cell * 3.3),
        Offset(cell * 3.3, cell * 3.3),
      ],
    ];

    for (final pair in pairs) {
      canvas.drawLine(
        pair[0],
        pair[1],
        Paint()
          ..color = dotColors[pairs.indexOf(pair)]
          ..strokeWidth = cell * 0.18
          ..strokeCap = StrokeCap.round,
      );
    }

    for (var i = 0; i < dotColors.length; i++) {
      final p = i == 0
          ? Offset(cell * 0.7, cell * 0.7)
          : i == 1
              ? Offset(cell * 3.3, cell * 0.7)
              : i == 2
                  ? Offset(cell * 3.3, cell * 3.3)
                  : Offset(cell * 0.7, cell * 3.3);
      canvas.drawCircle(
        p,
        cell * 0.30,
        Paint()..color = dotColors[i],
      );
    }
  }

  /// Maze Escape — small grid maze with a green player ball + a
  /// gold exit dot.
  void _paintMazeEscape(Canvas canvas, Size s) {
    final n = 4;
    final cell = s.width / n;

    // Faint background grid.
    final gridPaint = Paint()
      ..color = brightness == Brightness.dark
          ? Colors.white.withValues(alpha: 0.10)
          : Colors.black.withValues(alpha: 0.08);

    // Draw some wall segments to suggest a maze.
    final walls = <List<Offset>>[
      [Offset(0, cell), Offset(cell, cell)],
      [Offset(cell * 2, 0), Offset(cell * 2, cell)],
      [Offset(cell, cell), Offset(cell, cell * 2)],
      [Offset(cell * 3, cell), Offset(cell * 3, cell * 3)],
      [Offset(0, cell * 3), Offset(cell * 2, cell * 3)],
      [Offset(cell * 2, cell * 2), Offset(cell * 2, cell * 4)],
      [Offset(cell, cell * 3), Offset(cell, cell * 4)],
    ];

    final wallPaint = Paint()
      ..color = accent
      ..strokeWidth = cell * 0.18
      ..strokeCap = StrokeCap.round;
    for (final w in walls) {
      canvas.drawLine(w[0], w[1], wallPaint);
    }

    // Faint grid squares.
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        final rect = Rect.fromLTWH(
          c * cell + cell * 0.05,
          r * cell + cell * 0.05,
          cell - cell * 0.10,
          cell - cell * 0.10,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(2)),
          gridPaint,
        );
      }
    }

    // Player dot — accent.
    canvas.drawCircle(
      Offset(cell * 0.5, cell * 0.5),
      cell * 0.30,
      Paint()..color = accent,
    );

    // Exit dot — gold.
    canvas.drawCircle(
      Offset(cell * 3.5, cell * 3.5),
      cell * 0.30,
      Paint()..color = const Color(0xFFFFB800),
    );
  }

  /// Stack Tower — three stacked blocks with subtle perspective.
  void _paintStackTower(Canvas canvas, Size s) {
    final blockH = s.height / 4;
    final blockW = s.width;
    final gap = blockH * 0.10;

    final blockColors = [
      accent,
      _darker(accent, 0.15),
      _darker(accent, 0.30),
    ];

    for (var i = 0; i < 3; i++) {
      final y = (3 - i - 1) * blockH + gap;
      final w = blockW * (0.85 - i * 0.10);
      final x = (s.width - w) / 2;
      final rect = Rect.fromLTWH(x, y, w, blockH - gap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        Paint()..color = blockColors[i],
      );
      // Highlight strip.
      canvas.drawRect(
        Rect.fromLTWH(x + 4, y + 4, w - 8, (blockH - gap) * 0.15),
        Paint()..color = Colors.white.withValues(alpha: 0.20),
      );
    }
  }

  /// Tap Reaction — stopwatch + lightning bolt.
  void _paintTapReaction(Canvas canvas, Size s) {
    final cx = s.width / 2;
    final cy = s.height / 2;
    final r = s.width * 0.30;

    // Stopwatch body.
    canvas.drawCircle(
      Offset(cx, cy + r * 0.10),
      r,
      Paint()
        ..color = accent.withValues(alpha: 0.30),
    );
    canvas.drawCircle(
      Offset(cx, cy + r * 0.10),
      r,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.15,
    );
    // Crown (top knob).
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - r * 0.18, cy + r * 0.10 - r * 0.85, r * 0.36, r * 0.25),
        const Radius.circular(2),
      ),
      Paint()..color = accent,
    );

    // Lightning bolt — overlaid.
    final bolt = Path()
      ..moveTo(cx + r * 0.10, cy - r * 0.80)
      ..lineTo(cx - r * 0.20, cy + r * 0.10)
      ..lineTo(cx + r * 0.05, cy + r * 0.10)
      ..lineTo(cx - r * 0.10, cy + r * 0.85)
      ..lineTo(cx + r * 0.30, cy - r * 0.20)
      ..lineTo(cx + r * 0.05, cy - r * 0.20)
      ..close();
    canvas.drawPath(
      bolt,
      Paint()..color = const Color(0xFFFACC15),
    );
  }

  /// Cricket Batting — crossed bat + ball.
  void _paintCricketBatting(Canvas canvas, Size s) {
    // Cricket pitch scene: green oval pitch with three stumps on the
    // right, a batter silhouette with bat mid-swing on the left, and
    // a red cricket ball trailing a motion arc through the centre.
    final cx = s.width / 2;
    final cy = s.height / 2;

    // Sky / pitch background.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, s.width, s.height),
        const Radius.circular(8),
      ),
      Paint()..color = const Color(0xFF1F4D2C),
    );
    // Pitch strip (vertical, lighter green).
    final pitchRect = Rect.fromLTWH(
      cx - s.width * 0.08,
      s.height * 0.10,
      s.width * 0.16,
      s.height * 0.80,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(pitchRect, const Radius.circular(4)),
      Paint()..color = const Color(0xFFD9B26A),
    );
    // Crease lines.
    canvas.drawLine(
      Offset(pitchRect.left, pitchRect.top),
      Offset(pitchRect.right, pitchRect.top),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 1.2,
    );
    canvas.drawLine(
      Offset(pitchRect.left, pitchRect.bottom),
      Offset(pitchRect.right, pitchRect.bottom),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 1.2,
    );

    // Three stumps + bails on top of pitch.
    final stumpW = pitchRect.width * 0.16;
    final stumpH = pitchRect.height * 0.18;
    final stumpBaseY = pitchRect.top - stumpH + 2;
    for (var i = 0; i < 3; i++) {
      final stumpRect = Rect.fromLTWH(
        pitchRect.left + (i + 0.5) * (pitchRect.width - stumpW) / 3 +
            pitchRect.width * 0.04,
        stumpBaseY,
        stumpW,
        stumpH,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(stumpRect, const Radius.circular(1)),
        Paint()..color = const Color(0xFFFDE68A),
      );
    }
    // Bails (two thin crossbars).
    final bailY = stumpBaseY - 1;
    canvas.drawLine(
      Offset(pitchRect.left + pitchRect.width * 0.30, bailY),
      Offset(pitchRect.left + pitchRect.width * 0.72, bailY),
      Paint()
        ..color = const Color(0xFFFDE68A)
        ..strokeWidth = 1.5,
    );

    // Batsman silhouette on the lower-right of the pitch.
    final batCx = pitchRect.right + pitchRect.width * 0.6;
    final batCy = pitchRect.bottom - pitchRect.height * 0.10;
    // Body.
    canvas.drawCircle(
      Offset(batCx, batCy - pitchRect.height * 0.10),
      pitchRect.width * 0.10,
      Paint()..color = const Color(0xFF1E3A8A),
    );
    // Head.
    canvas.drawCircle(
      Offset(batCx, batCy - pitchRect.height * 0.22),
      pitchRect.width * 0.06,
      Paint()..color = const Color(0xFFFBCFA0),
    );
    // Bat angled up.
    canvas.save();
    canvas.translate(batCx - pitchRect.width * 0.18, batCy);
    canvas.rotate(-0.6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-pitchRect.width * 0.06, -pitchRect.height * 0.20,
            pitchRect.width * 0.10, pitchRect.height * 0.35),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFFFDE68A),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-pitchRect.width * 0.02, -pitchRect.height * 0.20,
            pitchRect.width * 0.05, pitchRect.height * 0.10),
        const Radius.circular(1),
      ),
      Paint()..color = const Color(0xFF7C2D12),
    );
    canvas.restore();

    // Cricket ball with motion arc, mid-flight.
    final ballR = s.width * 0.08;
    final ballPos = Offset(cx + s.width * 0.04, cy - s.height * 0.05);
    // Trailing dashes for motion.
    final trail = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.6;
    canvas.drawLine(
      ballPos + Offset(-ballR * 2.5, -ballR * 0.6),
      ballPos + Offset(-ballR * 1.2, -ballR * 0.2),
      trail,
    );
    canvas.drawLine(
      ballPos + Offset(-ballR * 3.8, -ballR * 1.0),
      ballPos + Offset(-ballR * 2.6, -ballR * 0.5),
      trail,
    );
    // Ball.
    canvas.drawCircle(
      ballPos + const Offset(0.8, 1.5),
      ballR,
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );
    canvas.drawCircle(
      ballPos,
      ballR,
      Paint()..color = accent,
    );
    // Seam.
    canvas.drawLine(
      ballPos + Offset(-ballR * 0.6, ballR * 0.6),
      ballPos + Offset(ballR * 0.6, -ballR * 0.6),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..strokeWidth = 1.2,
    );
  }

  /// Lumberjack Battle — axe + log stack.
  void _paintLumberjack(Canvas canvas, Size s) {
    final cx = s.width / 2;
    final cy = s.height / 2;

    // Log stack (3 horizontal rounded rectangles).
    final logPaint = Paint()
      ..color = const Color(0xFFA16207);
    final logHl = Paint()
      ..color = const Color(0xFFFCD34D);
    for (var i = 0; i < 3; i++) {
      final y = cy + i * s.width * 0.10;
      final rect = Rect.fromLTWH(
        s.width * 0.10,
        y,
        s.width * 0.80,
        s.width * 0.12,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        logPaint,
      );
      // End rings.
      canvas.drawCircle(
        Offset(rect.left + rect.width * 0.08, rect.center.dy),
        rect.height * 0.35,
        logHl,
      );
      canvas.drawCircle(
        Offset(rect.left + rect.width * 0.08, rect.center.dy),
        rect.height * 0.20,
        Paint()..color = const Color(0xFF92400E),
      );
    }

    // Axe head.
    final axePath = Path()
      ..moveTo(cx - s.width * 0.25, cy - s.width * 0.40)
      ..lineTo(cx + s.width * 0.10, cy - s.width * 0.20)
      ..lineTo(cx + s.width * 0.20, cy - s.width * 0.40)
      ..lineTo(cx + s.width * 0.10, cy - s.width * 0.55)
      ..close();
    canvas.drawPath(axePath, Paint()..color = const Color(0xFFE5E7EB));
    // Handle.
    canvas.drawLine(
      Offset(cx + s.width * 0.15, cy - s.width * 0.40),
      Offset(cx + s.width * 0.45, cy - s.width * 0.05),
      Paint()
        ..color = const Color(0xFF7C2D12)
        ..strokeWidth = s.width * 0.05
        ..strokeCap = StrokeCap.round,
    );
  }

  /// Pong — two paddles + ball + centre dashed line.
  void _paintPong(Canvas canvas, Size s) {
    final pw = s.width * 0.10;
    final ph = s.height * 0.20;

    // Centre dashed line.
    final dashPaint = Paint()
      ..color = accent
      ..strokeWidth = s.width * 0.025
      ..strokeCap = StrokeCap.round;
    final segments = 6;
    final segH = s.height / segments;
    for (var i = 0; i < segments; i += 2) {
      canvas.drawLine(
        Offset(s.width / 2, i * segH + segH * 0.25),
        Offset(s.width / 2, (i + 1) * segH - segH * 0.25),
        dashPaint,
      );
    }

    // Left paddle.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s.width * 0.08, s.height * 0.40, pw, ph),
        const Radius.circular(2),
      ),
      Paint()..color = Colors.white,
    );

    // Right paddle — accent.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s.width * 0.82, s.height * 0.40, pw, ph),
        const Radius.circular(2),
      ),
      Paint()..color = accent,
    );

    // Ball.
    canvas.drawCircle(
      Offset(s.width * 0.55, s.height * 0.42),
      s.width * 0.045,
      Paint()..color = Colors.white,
    );
  }

  /// Flappy Bird — bird silhouette + pipe.
  void _paintFlappyBird(Canvas canvas, Size s) {
    final cx = s.width * 0.42;
    final cy = s.height * 0.50;

    // Pipe (right side, top half).
    final pipeTop = s.height * 0.05;
    final pipeBot = s.height * 0.45;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s.width * 0.70, pipeTop, s.width * 0.18, pipeBot - pipeTop),
        const Radius.circular(4),
      ),
      Paint()..color = const Color(0xFF22C55E),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          s.width * 0.66,
          pipeBot - s.width * 0.04,
          s.width * 0.26,
          s.width * 0.08,
        ),
        const Radius.circular(3),
      ),
      Paint()..color = const Color(0xFF22C55E),
    );

    // Bird body.
    final birdR = s.width * 0.18;
    canvas.drawCircle(
      Offset(cx, cy),
      birdR,
      Paint()..color = accent,
    );
    // Wing.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx - birdR * 0.10, cy + birdR * 0.10),
        width: birdR * 1.2,
        height: birdR * 0.7,
      ),
      Paint()..color = _darker(accent, 0.20),
    );
    // Eye.
    canvas.drawCircle(
      Offset(cx + birdR * 0.45, cy - birdR * 0.25),
      birdR * 0.18,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      Offset(cx + birdR * 0.50, cy - birdR * 0.25),
      birdR * 0.10,
      Paint()..color = Colors.black,
    );
    // Beak.
    final beak = Path()
      ..moveTo(cx + birdR * 0.85, cy - birdR * 0.05)
      ..lineTo(cx + birdR * 1.20, cy + birdR * 0.05)
      ..lineTo(cx + birdR * 0.85, cy + birdR * 0.20)
      ..close();
    canvas.drawPath(beak, Paint()..color = const Color(0xFFF59E0B));
  }

  /// Snake & Ladders — zig-zag board with snake + ladder silhouettes.
  void _paintSnakeLadders(Canvas canvas, Size s) {
    // 3×3 cell grid.
    final n = 3;
    final cell = s.width / n;
    final gridPaint = Paint()
      ..color = brightness == Brightness.dark
          ? Colors.white.withValues(alpha: 0.08)
          : Colors.black.withValues(alpha: 0.06);

    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        final rect = Rect.fromLTWH(
          c * cell,
          r * cell,
          cell,
          cell,
        );
        canvas.drawRect(
          rect,
          gridPaint,
        );
      }
    }

    // Ladder (vertical, on the right).
    for (var i = 0; i < 4; i++) {
      final y = cell * 0.10 + i * (cell * 0.80);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(s.width * 0.65, y, s.width * 0.04, cell * 0.30),
          const Radius.circular(1),
        ),
        Paint()..color = const Color(0xFFFCD34D),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(s.width * 0.78, y, s.width * 0.04, cell * 0.30),
          const Radius.circular(1),
        ),
        Paint()..color = const Color(0xFFFCD34D),
      );
    }

    // Snake — serpentine accent curve on the left.
    final snakePath = Path()
      ..moveTo(s.width * 0.20, cell * 0.20)
      ..cubicTo(
        s.width * 0.05, cell * 0.40,
        s.width * 0.40, cell * 0.70,
        s.width * 0.20, s.height * 0.85,
      );
    canvas.drawPath(
      snakePath,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = s.width * 0.08
        ..strokeCap = StrokeCap.round,
    );
  }

  /// Battleship — top-down boat silhouette on water.
  void _paintBattleship(Canvas canvas, Size s) {
    final cx = s.width / 2;
    final cy = s.height / 2;

    // Water.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, s.width, s.height),
      Paint()
        ..color = const Color(0xFF1E3A8A).withValues(alpha: 0.18),
    );

    // Hull.
    final hull = Path()
      ..moveTo(cx - s.width * 0.40, cy + s.width * 0.05)
      ..lineTo(cx - s.width * 0.30, cy + s.width * 0.18)
      ..lineTo(cx + s.width * 0.30, cy + s.width * 0.18)
      ..lineTo(cx + s.width * 0.40, cy + s.width * 0.05)
      ..lineTo(cx + s.width * 0.30, cy - s.width * 0.05)
      ..lineTo(cx - s.width * 0.30, cy - s.width * 0.05)
      ..close();
    canvas.drawPath(hull, Paint()..color = const Color(0xFF6B7280));

    // Deck.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - s.width * 0.25, cy - s.width * 0.18, s.width * 0.50, s.width * 0.18),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFFE5E7EB),
    );

    // Turret.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - s.width * 0.10, cy - s.width * 0.30, s.width * 0.20, s.width * 0.14),
        const Radius.circular(2),
      ),
      Paint()..color = accent,
    );
    // Gun barrel.
    canvas.drawRect(
      Rect.fromLTWH(cx + s.width * 0.05, cy - s.width * 0.32, s.width * 0.20, s.width * 0.04),
      Paint()..color = const Color(0xFF1F2937),
    );
  }

  /// Chess — knight silhouette on a 2×2 alternating board.
  void _paintChess(Canvas canvas, Size s) {
    final cell = s.width / 2;
    final light = const Color(0xFFFDE68A);
    final dark = const Color(0xFF92400E);

    for (var r = 0; r < 2; r++) {
      for (var c = 0; c < 2; c++) {
        canvas.drawRect(
          Rect.fromLTWH(c * cell, r * cell, cell, cell),
          Paint()..color = (r + c).isEven ? light : dark,
        );
      }
    }

    // Knight — simplified silhouette.
    final cx = s.width / 2;
    final cy = s.height / 2;
    final knight = Path()
      ..moveTo(cx - s.width * 0.18, cy + s.height * 0.22)
      ..lineTo(cx + s.width * 0.18, cy + s.height * 0.22)
      ..lineTo(cx + s.width * 0.18, cy + s.height * 0.10)
      ..lineTo(cx + s.width * 0.10, cy + s.height * 0.10)
      ..lineTo(cx + s.width * 0.20, cy - s.height * 0.05)
      ..lineTo(cx + s.width * 0.08, cy - s.height * 0.20)
      ..lineTo(cx + s.width * 0.18, cy - s.height * 0.30)
      ..lineTo(cx + s.width * 0.05, cy - s.height * 0.30)
      ..lineTo(cx - s.width * 0.05, cy - s.height * 0.10)
      ..lineTo(cx - s.width * 0.20, cy + s.height * 0.10)
      ..close();
    canvas.drawPath(
      knight,
      Paint()..color = accent,
    );
  }

  /// Backgammon — 6 triangular points alternating two colours.
  void _paintBackgammon(Canvas canvas, Size s) {
    final board = Rect.fromLTWH(0, 0, s.width, s.height);
    canvas.drawRect(
      board,
      Paint()
        ..color = const Color(0xFF7C2D12).withValues(alpha: 0.18),
    );

    // Center bar.
    canvas.drawRect(
      Rect.fromLTWH(s.width * 0.45, 0, s.width * 0.10, s.height),
      Paint()..color = const Color(0xFF451A03),
    );

    final pointW = s.width * 0.45 / 6;
    final pointH = s.height * 0.85;

    for (var i = 0; i < 6; i++) {
      final x = i * pointW;
      final paint = Paint()..color = (i.isEven)
          ? accent.withValues(alpha: 0.85)
          : const Color(0xFFFDE68A).withValues(alpha: 0.85);

      // Top triangle.
      final top = Path()
        ..moveTo(x, s.height * 0.05)
        ..lineTo(x + pointW, s.height * 0.05)
        ..lineTo(x + pointW / 2, s.height * 0.05 + pointH * 0.45)
        ..close();
      canvas.drawPath(top, paint);

      // Bottom triangle (mirrored).
      final bot = Path()
        ..moveTo(x, s.height - s.height * 0.05)
        ..lineTo(x + pointW, s.height - s.height * 0.05)
        ..lineTo(x + pointW / 2, s.height - s.height * 0.05 - pointH * 0.45)
        ..close();
      canvas.drawPath(bot, paint);
    }

    // Right-side mirror.
    for (var i = 0; i < 6; i++) {
      final x = s.width * 0.55 + i * pointW;
      final paint = Paint()..color = (i.isEven)
          ? const Color(0xFFFDE68A).withValues(alpha: 0.85)
          : accent.withValues(alpha: 0.85);

      final top = Path()
        ..moveTo(x, s.height * 0.05)
        ..lineTo(x + pointW, s.height * 0.05)
        ..lineTo(x + pointW / 2, s.height * 0.05 + pointH * 0.45)
        ..close();
      canvas.drawPath(top, paint);

      final bot = Path()
        ..moveTo(x, s.height - s.height * 0.05)
        ..lineTo(x + pointW, s.height - s.height * 0.05)
        ..lineTo(x + pointW / 2, s.height - s.height * 0.05 - pointH * 0.45)
        ..close();
      canvas.drawPath(bot, paint);
    }
  }

  /// Bomberman — classic round bomb with a lit fuse.
  void _paintBomberman(Canvas canvas, Size s) {
    final cx = s.width / 2;
    final cy = s.height * 0.55;
    final r = s.width * 0.30;

    // Bomb body.
    canvas.drawCircle(Offset(cx, cy), r, Paint()..color = const Color(0xFF111827));

    // Highlight.
    canvas.drawCircle(
      Offset(cx - r * 0.40, cy - r * 0.40),
      r * 0.20,
      Paint()..color = Colors.white.withValues(alpha: 0.25),
    );

    // Fuse.
    canvas.drawLine(
      Offset(cx + r * 0.10, cy - r),
      Offset(cx + r * 0.45, cy - r * 1.30),
      Paint()
        ..color = const Color(0xFFFCD34D)
        ..strokeWidth = r * 0.10
        ..strokeCap = StrokeCap.round,
    );

    // Spark.
    canvas.drawCircle(
      Offset(cx + r * 0.55, cy - r * 1.30),
      r * 0.18,
      Paint()..color = accent,
    );
    canvas.drawCircle(
      Offset(cx + r * 0.55, cy - r * 1.30),
      r * 0.10,
      Paint()..color = Colors.white,
    );
  }

  /// Pac-Man — open-mouth yellow disc with a small dot.
  void _paintPacman(Canvas canvas, Size s) {
    final cx = s.width * 0.40;
    final cy = s.height / 2;
    final r = s.width * 0.30;

    // Mouth opening — wedge from -45° to +45°.
    final mouth = Path()
      ..moveTo(cx, cy)
      ..arcTo(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        (-0.6),
        1.2,
        true,
      )
      ..close();
    canvas.drawPath(mouth, Paint()..color = brightness == Brightness.dark ? const Color(0xFF111622) : const Color(0xFFF1F5F9));

    // Body.
    canvas.drawCircle(Offset(cx, cy), r, Paint()..color = accent);

    // Re-draw mouth on top.
    canvas.drawPath(mouth, Paint()..color = brightness == Brightness.dark ? const Color(0xFF111622) : const Color(0xFFF1F5F9));

    // Eye.
    canvas.drawCircle(
      Offset(cx + r * 0.05, cy - r * 0.55),
      r * 0.10,
      Paint()..color = Colors.black,
    );

    // Dot to chase.
    canvas.drawCircle(
      Offset(s.width * 0.85, cy),
      r * 0.10,
      Paint()..color = accent,
    );
  }

  /// Generic last-resort — soft accent disc with a stylized glyph
  /// for the title's first letter. Never a '?'.
  // ─────────────────────────────────────────────────────────────
// Featured top-9 recipes
// ─────────────────────────────────────────────────────────────

void _paintRacingRush(Canvas canvas, Size s) {
  // Vibrant red gradient background.
  final bg = Paint()
    ..shader = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [const Color(0xFFFF6B6B), const Color(0xFFD62828)],
    ).createShader(Offset.zero & s);
  canvas.drawRRect(
    RRect.fromRectAndRadius(Offset.zero & s, const Radius.circular(16)),
    bg,
  );

  // Speed-line streaks (diagonal white strokes).
  final streak = Paint()
    ..color = Colors.white.withValues(alpha: 0.25)
    ..strokeWidth = 3
    ..strokeCap = StrokeCap.round;
  for (var i = 0; i < 6; i++) {
    final x = s.width * 0.05 + i * s.width * 0.13;
    canvas.drawLine(
      Offset(x, s.height * 0.08),
      Offset(x + s.width * 0.08, s.height * 0.30),
      streak,
    );
  }

  // Red car body (rounded squircle) — centered.
  final carW = s.width * 0.55;
  final carH = s.height * 0.5;
  final carRect = Rect.fromCenter(
    center: s.center(Offset.zero).translate(0, s.height * 0.08),
    width: carW,
    height: carH,
  );

  // Drop shadow.
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      carRect.translate(0, 4),
      const Radius.circular(14),
    ),
    Paint()..color = Colors.black.withValues(alpha: 0.25),
  );

  // Body.
  canvas.drawRRect(
    RRect.fromRectAndRadius(carRect, const Radius.circular(16)),
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [const Color(0xFFFF3B30), const Color(0xFF8B0000)],
      ).createShader(carRect),
  );

  // White roof.
  final roofRect = Rect.fromCenter(
    center: carRect.center.translate(0, -carH * 0.05),
    width: carW * 0.7,
    height: carH * 0.5,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(roofRect, const Radius.circular(10)),
    Paint()..color = Colors.white,
  );

  // Windshield (black tinted).
  final windRect = Rect.fromCenter(
    center: roofRect.center.translate(0, -carH * 0.05),
    width: roofRect.width * 0.85,
    height: roofRect.height * 0.5,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(windRect, const Radius.circular(6)),
    Paint()..color = const Color(0xFF1A1A2E),
  );

  // 4 tires.
  final tirePaint = Paint()..color = const Color(0xFF1A1A1A);
  for (final dx in [-carW * 0.32, carW * 0.32]) {
    for (final dy in [-carH * 0.45, carH * 0.45]) {
      canvas.drawCircle(
        carRect.center.translate(dx, dy),
        carW * 0.07,
        tirePaint,
      );
    }
  }

  // Headlights (yellow circles).
  final lightPaint = Paint()..color = const Color(0xFFFFE66D);
  for (final dx in [-carW * 0.18, carW * 0.18]) {
    canvas.drawCircle(
      carRect.center.translate(dx, -carH * 0.5 + 4),
      carW * 0.05,
      lightPaint,
    );
  }
}

void _paintFruitSlice(Canvas canvas, Size s) {
  // Coral-red gradient background.
  final bg = Paint()
    ..shader = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFFB199), Color(0xFFFF6584)],
    ).createShader(Offset.zero & s);
  canvas.drawRRect(
    RRect.fromRectAndRadius(Offset.zero & s, const Radius.circular(16)),
    bg,
  );

  // Watermelon slice (bottom-left).
  _drawWatermelonSlice(
    canvas,
    Rect.fromCenter(
      center: Offset(s.width * 0.30, s.height * 0.65),
      width: s.width * 0.42,
      height: s.height * 0.42,
    ),
  );

  // Banana curve (right side).
  _drawBanana(
    canvas,
    Rect.fromCenter(
      center: Offset(s.width * 0.72, s.height * 0.55),
      width: s.width * 0.35,
      height: s.height * 0.50,
    ),
  );

  // Kiwi cross-section (top).
  _drawKiwi(
    canvas,
    Rect.fromCenter(
      center: Offset(s.width * 0.65, s.height * 0.18),
      width: s.width * 0.30,
      height: s.height * 0.30,
    ),
  );

  // Splash droplets.
  final drop = Paint()..color = Colors.white.withValues(alpha: 0.45);
  for (final d in [
    [0.18, 0.20],
    [0.50, 0.85],
    [0.82, 0.30],
    [0.40, 0.10],
  ]) {
    canvas.drawCircle(
      Offset(s.width * d[0], s.height * d[1]),
      s.width * 0.025,
      drop,
    );
  }
}

void _drawWatermelonSlice(Canvas canvas, Rect r) {
  // Green rind outline.
  final path = Path()
    ..moveTo(r.left, r.bottom)
    ..quadraticBezierTo(r.center.dx, r.top - 8, r.right, r.bottom)
    ..close();
  canvas.drawPath(path, Paint()..color = const Color(0xFF2D6A4F));
  // Red flesh (slightly inset).
  final fleshRect = r.deflate(6);
  final fleshPath = Path()
    ..moveTo(fleshRect.left, fleshRect.bottom)
    ..quadraticBezierTo(
      fleshRect.center.dx,
      fleshRect.top + 6,
      fleshRect.right,
      fleshRect.bottom,
    )
    ..close();
  canvas.drawPath(fleshPath, Paint()..color = const Color(0xFFE63946));
  // Inner pink ring.
  final inner = fleshRect.deflate(5);
  final innerPath = Path()
    ..moveTo(inner.left, inner.bottom)
    ..quadraticBezierTo(
      inner.center.dx,
      inner.top + 4,
      inner.right,
      inner.bottom,
    )
    ..close();
  canvas.drawPath(innerPath, Paint()..color = const Color(0xFFFFADAD));
  // Black seeds.
  final seedPaint = Paint()..color = const Color(0xFF1A1A1A);
  for (var i = 0; i < 5; i++) {
    final x = inner.left + (inner.width / 5) * i + inner.width * 0.1;
    final y = inner.bottom - inner.height * (0.3 + 0.1 * (i % 3));
    canvas.drawCircle(Offset(x, y), inner.width * 0.025, seedPaint);
  }
}

void _drawBanana(Canvas canvas, Rect r) {
  // Curved yellow body.
  final path = Path()
    ..moveTo(r.left + r.width * 0.10, r.top + r.height * 0.30)
    ..quadraticBezierTo(
      r.center.dx,
      r.top - r.height * 0.10,
      r.right - r.width * 0.10,
      r.top + r.height * 0.20,
    )
    ..quadraticBezierTo(
      r.center.dx + r.width * 0.05,
      r.center.dy + r.height * 0.30,
      r.left + r.width * 0.05,
      r.bottom - r.height * 0.10,
    )
    ..close();
  canvas.drawPath(path, Paint()..color = const Color(0xFFFFD93D));
  // Stem.
  canvas.drawRect(
    Rect.fromLTWH(
      r.right - r.width * 0.12,
      r.top + r.height * 0.10,
      r.width * 0.05,
      r.height * 0.10,
    ),
    Paint()..color = const Color(0xFF6B4423),
  );
  // Highlight stripe.
  final highlight = Path()
    ..moveTo(r.left + r.width * 0.20, r.top + r.height * 0.35)
    ..quadraticBezierTo(
      r.center.dx,
      r.top + r.height * 0.05,
      r.right - r.width * 0.20,
      r.top + r.height * 0.25,
    );
  canvas.drawPath(
    highlight,
    Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = r.width * 0.05
      ..strokeCap = StrokeCap.round,
  );
}

void _drawKiwi(Canvas canvas, Rect r) {
  canvas.drawCircle(r.center, r.width / 2, Paint()..color = const Color(0xFF8B6F47));
  canvas.drawCircle(r.center, r.width * 0.42, Paint()..color = const Color(0xFFA4C639));
  // Seeds (small black ovals).
  final seedPaint = Paint()..color = const Color(0xFF1A1A1A);
  final cx = r.center.dx;
  final cy = r.center.dy;
  for (var i = 0; i < 12; i++) {
    final angle = (i / 12) * 6.2831853;
    final rad = r.width * 0.30;
    final px = cx + (rad * 0.55) * _cos(angle);
    final py = cy + (rad * 0.55) * _sin(angle);
    canvas.save();
    canvas.translate(px, py);
    canvas.rotate(angle);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: r.width * 0.06,
        height: r.width * 0.03,
      ),
      seedPaint,
    );
    canvas.restore();
  }
  // White core.
  canvas.drawCircle(r.center, r.width * 0.08, Paint()..color = Colors.white);
}

double _cos(double a) => math.cos(a);
double _sin(double a) => math.sin(a);

void _paintBasketBounce(Canvas canvas, Size s) {
  // Orange-to-blue gradient background.
  final bg = Paint()
    ..shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF1E3A8A), Color(0xFFFB923C)],
    ).createShader(Offset.zero & s);
  canvas.drawRRect(
    RRect.fromRectAndRadius(Offset.zero & s, const Radius.circular(16)),
    bg,
  );

  // Hoop backboard (white rectangle, top-center).
  final backboard = Rect.fromCenter(
    center: Offset(s.width * 0.5, s.height * 0.18),
    width: s.width * 0.45,
    height: s.height * 0.18,
  );
  canvas.drawRect(
    backboard,
    Paint()..color = Colors.white.withValues(alpha: 0.85),
  );
  canvas.drawRect(
    backboard,
    Paint()
      ..color = Colors.black.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2,
  );

  // Inner box on backboard.
  final innerBox = Rect.fromCenter(
    center: backboard.center,
    width: backboard.width * 0.45,
    height: backboard.height * 0.55,
  );
  canvas.drawRect(
    innerBox,
    Paint()
      ..color = Colors.transparent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2,
  );

  // Rim (orange ellipse).
  final rimRect = Rect.fromCenter(
    center: Offset(s.width * 0.5, s.height * 0.30),
    width: s.width * 0.32,
    height: s.height * 0.08,
  );
  canvas.drawOval(
    rimRect,
    Paint()
      ..color = const Color(0xFFFB923C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.height * 0.025,
  );

  // Net strands (white vertical lines fanning inward).
  final netPaint = Paint()
    ..color = Colors.white.withValues(alpha: 0.7)
    ..strokeWidth = 1.5;
  for (var i = 0; i < 7; i++) {
    final t = i / 6;
    final xTop = rimRect.left + rimRect.width * t;
    final xBot = rimRect.center.dx + (xTop - rimRect.center.dx) * 0.3;
    canvas.drawLine(
      Offset(xTop, rimRect.bottom + 2),
      Offset(xBot, rimRect.bottom + rimRect.height * 1.2),
      netPaint,
    );
  }

  // Trajectory dotted arc.
  final arcPaint = Paint()
    ..color = Colors.white.withValues(alpha: 0.55)
    ..strokeWidth = 2
    ..strokeCap = StrokeCap.round;
  for (var i = 0; i < 10; i++) {
    final t = i / 10;
    final x = s.width * 0.5 + (s.width * 0.18) * (t - 0.5) * 2 * (1 - t);
    final y = s.height * (0.55 - 0.20 * (1 - (t - 0.5).abs() * 2));
    if (i % 2 == 0) {
      canvas.drawCircle(Offset(x, y), 2, arcPaint);
    }
  }

  // Basketball (orange circle with black seams).
  final ballCenter = Offset(s.width * 0.30, s.height * 0.65);
  final ballR = s.width * 0.12;
  // Shadow.
  canvas.drawCircle(
    ballCenter.translate(2, 3),
    ballR,
    Paint()..color = Colors.black.withValues(alpha: 0.3),
  );
  // Body.
  canvas.drawCircle(
    ballCenter,
    ballR,
    Paint()
      ..shader = RadialGradient(
        colors: [const Color(0xFFFFB74D), const Color(0xFFE65100)],
      ).createShader(Rect.fromCircle(center: ballCenter, radius: ballR)),
  );
  // Seams.
  final seamPaint = Paint()
    ..color = const Color(0xFF1A1A1A)
    ..strokeWidth = 1.5
    ..style = PaintingStyle.stroke;
  canvas.drawLine(
    Offset(ballCenter.dx - ballR, ballCenter.dy),
    Offset(ballCenter.dx + ballR, ballCenter.dy),
    seamPaint,
  );
  canvas.drawArc(
    Rect.fromCircle(center: ballCenter, radius: ballR),
    -2.5,
    1.8,
    false,
    seamPaint,
  );
  canvas.drawArc(
    Rect.fromCircle(center: ballCenter, radius: ballR),
    0.7,
    1.8,
    false,
    seamPaint,
  );
}

void _paintDartsClub(Canvas canvas, Size s) {
  // Pastel purple gradient background.
  final bg = Paint()
    ..shader = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFC4B5FD), Color(0xFFA073FF)],
    ).createShader(Offset.zero & s);
  canvas.drawRRect(
    RRect.fromRectAndRadius(Offset.zero & s, const Radius.circular(16)),
    bg,
  );

  // Dartboard (concentric rings).
  final c = s.center(Offset.zero);
  final radii = [s.width * 0.40, s.width * 0.34, s.width * 0.28, s.width * 0.22, s.width * 0.10];
  final colors = [
    const Color(0xFF1A1A1A),
    const Color(0xFFFECACA),
    const Color(0xFF1A1A1A),
    const Color(0xFFFECACA),
    const Color(0xFF22C55E),
  ];
  for (var i = 0; i < radii.length; i++) {
    canvas.drawCircle(c, radii[i], Paint()..color = colors[i]);
  }
  // Bullseye inner red.
  canvas.drawCircle(c, s.width * 0.05, Paint()..color = const Color(0xFFDC2626));

  // Radial divider lines.
  final linePaint = Paint()
    ..color = Colors.black.withValues(alpha: 0.6)
    ..strokeWidth = 1;
  for (var i = 0; i < 4; i++) {
    final angle = (i / 4) * 6.2831853 + 0.4;
    canvas.drawLine(
      c,
      c + Offset.fromDirection(angle, s.width * 0.40),
      linePaint,
    );
  }

  // 3 darts stuck in the board at varied angles.
  final darts = [
    [0.22, 0.30, 0.6],
    [0.75, 0.32, -0.4],
    [0.50, 0.78, 0.0],
  ];
  for (final d in darts) {
    final dx = s.width * d[0];
    final dy = s.height * d[1];
    final ang = d[2];
    canvas.save();
    canvas.translate(dx, dy);
    canvas.rotate(ang);
    // Shaft.
    canvas.drawRect(
      Rect.fromLTWH(-s.width * 0.20, -1.5, s.width * 0.30, 3),
      Paint()..color = const Color(0xFF6B4423),
    );
    // Flight (fletching).
    final flight = Path()
      ..moveTo(-s.width * 0.05, -6)
      ..lineTo(s.width * 0.08, 0)
      ..lineTo(-s.width * 0.05, 6)
      ..close();
    canvas.drawPath(flight, Paint()..color = const Color(0xFFDC2626));
    // Tip.
    final tip = Path()
      ..moveTo(s.width * 0.10, 0)
      ..lineTo(s.width * 0.16, -3)
      ..lineTo(s.width * 0.16, 3)
      ..close();
    canvas.drawPath(tip, Paint()..color = const Color(0xFF94A3B8));
    canvas.restore();
  }
}

void _paintTreasureHunt(Canvas canvas, Size s) {
  // Warm yellow gradient background.
  final bg = Paint()
    ..shader = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFFE066), Color(0xFFFFC837)],
    ).createShader(Offset.zero & s);
  canvas.drawRRect(
    RRect.fromRectAndRadius(Offset.zero & s, const Radius.circular(16)),
    bg,
  );

  // Sparkles around the chest.
  final sparkle = Paint()..color = Colors.white;
  for (final sp in [
    [0.20, 0.20, 4.0],
    [0.80, 0.18, 3.0],
    [0.18, 0.75, 3.5],
    [0.82, 0.72, 4.0],
    [0.50, 0.12, 3.0],
  ]) {
    _drawStar(
      canvas,
      Offset(s.width * sp[0], s.height * sp[1]),
      sp[2],
      sparkle,
    );
  }

  // Chest body.
  final bodyRect = Rect.fromCenter(
    center: Offset(s.width * 0.5, s.height * 0.62),
    width: s.width * 0.55,
    height: s.height * 0.30,
  );
  // Shadow.
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      bodyRect.translate(2, 4),
      const Radius.circular(8),
    ),
    Paint()..color = Colors.black.withValues(alpha: 0.25),
  );
  // Wood body.
  canvas.drawRRect(
    RRect.fromRectAndRadius(bodyRect, const Radius.circular(10)),
    Paint()..color = const Color(0xFF8B4513),
  );
  // Gold trim bands.
  for (final t in [0.25, 0.75]) {
    canvas.drawRect(
      Rect.fromLTWH(
        bodyRect.left,
        bodyRect.top + bodyRect.height * t - 3,
        bodyRect.width,
        6,
      ),
      Paint()..color = const Color(0xFFFFD700),
    );
  }

  // Open lid (darker wood, tilted).
  final lidRect = Rect.fromCenter(
    center: Offset(s.width * 0.5, s.height * 0.40),
    width: bodyRect.width * 0.95,
    height: bodyRect.height * 0.40,
  );
  canvas.save();
  canvas.translate(lidRect.center.dx, lidRect.center.dy);
  canvas.rotate(-0.25);
  canvas.translate(-lidRect.center.dx, -lidRect.center.dy);
  canvas.drawRRect(
    RRect.fromRectAndRadius(lidRect, const Radius.circular(10)),
    Paint()..color = const Color(0xFF6B3410),
  );
  canvas.restore();

  // Gold coins overflowing from chest.
  for (var i = 0; i < 5; i++) {
    final cx = bodyRect.center.dx + (i - 2) * bodyRect.width * 0.08;
    final cy = bodyRect.top - 4 - (i % 2) * 6.0;
    canvas.drawCircle(
      Offset(cx, cy),
      bodyRect.width * 0.07,
      Paint()..color = const Color(0xFFFFD700),
    );
    canvas.drawCircle(
      Offset(cx, cy),
      bodyRect.width * 0.07,
      Paint()
        ..color = const Color(0xFFB8860B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  // Glowing gem on top.
  final gemCenter = Offset(s.width * 0.5, bodyRect.top - 12);
  final gemPath = Path()
    ..moveTo(gemCenter.dx, gemCenter.dy - 12)
    ..lineTo(gemCenter.dx + 9, gemCenter.dy - 4)
    ..lineTo(gemCenter.dx, gemCenter.dy + 6)
    ..lineTo(gemCenter.dx - 9, gemCenter.dy - 4)
    ..close();
  canvas.drawPath(gemPath, Paint()..color = const Color(0xFF38BDF8));
  // Gem highlight.
  final hl = Path()
    ..moveTo(gemCenter.dx - 4, gemCenter.dy - 8)
    ..lineTo(gemCenter.dx + 2, gemCenter.dy - 4)
    ..lineTo(gemCenter.dx - 2, gemCenter.dy - 2)
    ..close();
  canvas.drawPath(hl, Paint()..color = Colors.white.withValues(alpha: 0.7));
}

void _drawStar(Canvas canvas, Offset center, double size, Paint fill) {
  final path = Path();
  for (var i = 0; i < 5; i++) {
    final angle = -1.5708 + (i / 5) * 6.2831853;
    final p = center + Offset.fromDirection(angle, size);
    if (i == 0) {
      path.moveTo(p.dx, p.dy);
    } else {
      path.lineTo(p.dx, p.dy);
    }
    final innerAngle = angle + 0.628;
    final inner = center + Offset.fromDirection(innerAngle, size * 0.45);
    path.lineTo(inner.dx, inner.dy);
  }
  path.close();
  canvas.drawPath(path, fill);
}

// ─────────────────────────────────────────────────────────────
// Generic fallback
// ─────────────────────────────────────────────────────────────

void _paintSubwayRun(Canvas canvas, Size s) {
  // Background — blue-grey track gradient.
  final bg = Paint()
    ..shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF1E293B), Color(0xFF334155)],
    ).createShader(Rect.fromLTWH(0, 0, s.width, s.height));
  canvas.drawRect(Rect.fromLTWH(0, 0, s.width, s.height), bg);

  // 3 train-track lanes (vertical rails).
  final laneW = s.width / 3;
  final rail = Paint()
    ..color = const Color(0xFFFBBF24)
    ..strokeWidth = 1.4;
  for (var i = 0; i < 3; i++) {
    final cx = laneW * (i + 0.5);
    canvas.drawLine(
      Offset(cx, s.height * 0.15),
      Offset(cx, s.height * 0.9),
      rail,
    );
  }
  // Tie bars.
  final tie = Paint()..color = const Color(0xFF64748B);
  for (var y = 0; y < 12; y++) {
    final yy = s.height * (0.15 + y * 0.07);
    canvas.drawRect(
      Rect.fromLTWH(s.width * 0.05, yy, s.width * 0.9, 3),
      tie,
    );
  }

  // Runner character at bottom.
  final runnerRect = Rect.fromCenter(
    center: Offset(s.width * 0.5, s.height * 0.85),
    width: s.width * 0.16,
    height: s.height * 0.16,
  );
  canvas.drawOval(
    runnerRect.translate(0, 2),
    Paint()..color = Colors.black.withValues(alpha: 0.4),
  );
  canvas.drawCircle(
    runnerRect.center.translate(0, -8),
    s.width * 0.06,
    Paint()..color = const Color(0xFFFCD34D),
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: runnerRect.center.translate(0, 4),
        width: s.width * 0.13,
        height: s.height * 0.08,
      ),
      const Radius.circular(6),
    ),
    Paint()..color = const Color(0xFFEF4444),
  );

  // Coins floating up.
  for (final c in [
    [0.2, 0.35, 5.0],
    [0.55, 0.25, 5.0],
    [0.8, 0.42, 5.0],
  ]) {
    final cx = s.width * c[0];
    final cy = s.height * c[1];
    canvas.drawCircle(Offset(cx, cy), c[2], Paint()..color = const Color(0xFFFBBF24));
    canvas.drawCircle(
      Offset(cx, cy),
      c[2] * 0.55,
      Paint()..color = const Color(0xFFFEF3C7),
    );
  }
}

void _paintSpaceBlast(Canvas canvas, Size s) {
  // Deep space gradient.
  final bg = Paint()
    ..shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF0F172A), Color(0xFF1E1B4B)],
    ).createShader(Rect.fromLTWH(0, 0, s.width, s.height));
  canvas.drawRect(Rect.fromLTWH(0, 0, s.width, s.height), bg);

  // Stars.
  final starPaint = Paint()..color = Colors.white;
  final rng = math.Random(42);
  for (var i = 0; i < 18; i++) {
    final x = rng.nextDouble() * s.width;
    final y = rng.nextDouble() * s.height * 0.65;
    final r = 0.6 + rng.nextDouble() * 1.4;
    canvas.drawCircle(Offset(x, y), r, starPaint);
  }

  // Alien invaders (3 rows).
  for (var row = 0; row < 3; row++) {
    for (var col = 0; col < 6; col++) {
      final cx = s.width * (0.12 + col * 0.13);
      final cy = s.height * (0.12 + row * 0.1);
      final color = row == 0
          ? const Color(0xFFFB7185)
          : row == 1
              ? const Color(0xFFFBBF24)
              : const Color(0xFF34D399);
      final alienRect = Rect.fromCenter(
        center: Offset(cx, cy),
        width: s.width * 0.08,
        height: s.height * 0.06,
      );
      canvas.drawOval(alienRect, Paint()..color = color);
      // Eyes.
      canvas.drawCircle(
        Offset(cx - s.width * 0.012, cy - s.height * 0.005),
        1.2,
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(
        Offset(cx + s.width * 0.012, cy - s.height * 0.005),
        1.2,
        Paint()..color = Colors.white,
      );
    }
  }

  // Player rocket at bottom.
  final rocketRect = Rect.fromCenter(
    center: Offset(s.width * 0.5, s.height * 0.85),
    width: s.width * 0.14,
    height: s.height * 0.12,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      rocketRect.translate(0, 2),
      const Radius.circular(4),
    ),
    Paint()..color = Colors.black.withValues(alpha: 0.4),
  );
  final rocket = Path()
    ..moveTo(rocketRect.center.dx, rocketRect.top - 6)
    ..lineTo(rocketRect.right, rocketRect.bottom)
    ..lineTo(rocketRect.left, rocketRect.bottom)
    ..close();
  canvas.drawPath(rocket, Paint()..color = const Color(0xFFE5E7EB));
  // Window.
  canvas.drawCircle(
    rocketRect.center,
    s.width * 0.02,
    Paint()..color = const Color(0xFF60A5FA),
  );
  // Flame.
  final flame = Path()
    ..moveTo(rocketRect.center.dx - 4, rocketRect.bottom)
    ..lineTo(rocketRect.center.dx, rocketRect.bottom + 8)
    ..lineTo(rocketRect.center.dx + 4, rocketRect.bottom)
    ..close();
  canvas.drawPath(flame, Paint()..color = const Color(0xFFFB923C));
}

void _paintWordMaster(Canvas canvas, Size s) {
  // Background — paper-cream gradient with a soft top-down fade.
  final bg = Paint()
    ..shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFFBBF24), Color(0xFFFCD34D)],
    ).createShader(Rect.fromLTWH(0, 0, s.width, s.height));
  canvas.drawRect(Rect.fromLTWH(0, 0, s.width, s.height), bg);

  // Crossword grid (5×5 — matches the in-game _rows / _cols).
  final gridW = s.width * 0.74;
  final cell = gridW / 5;
  final gridOrigin = Offset((s.width - gridW) / 2, s.height * 0.08);
  // Filled cells spell "WORD" in the centre row.
  // Row 2 (middle): cols 1, 2, 3, 4 spell "WORD" (W=col1, O=col2,
  // R=col3, D=col4). Plus a few decorative filled cells.
  const filled = <List<int>>[
    [0, 1],
    [1, 0],
    [1, 3],
    [2, 1], // W
    [2, 2], // O
    [2, 3], // R
    [2, 4], // D
    [3, 1],
    [3, 4],
    [4, 2],
  ];
  final cellPaint = Paint()..color = Colors.white;
  final emptyPaint = Paint()..color = Colors.white.withValues(alpha: 0.3);
  const letters = ['W', 'O', 'R', 'D'];
  // Map of (row, col) → letter index for the WORD row.
  const wordRow = {
    [2, 1]: 0, // W
    [2, 2]: 1, // O
    [2, 3]: 2, // R
    [2, 4]: 3, // D
  };
  for (var r = 0; r < 5; r++) {
    for (var c = 0; c < 5; c++) {
      final rect = Rect.fromLTWH(
        gridOrigin.dx + c * cell,
        gridOrigin.dy + r * cell,
        cell - 2,
        cell - 2,
      );
      final isFilled = filled.any((p) => p[0] == r && p[1] == c);
      if (isFilled) {
        // Soft drop shadow under each filled tile.
        canvas.drawRect(
          rect.shift(const Offset(0, 1.5)),
          Paint()..color = Colors.black.withValues(alpha: 0.10),
        );
        canvas.drawRect(rect, cellPaint);
      } else {
        canvas.drawRect(rect, emptyPaint);
      }
      if (isFilled) {
        final key = [r, c];
        final letter = wordRow[key] != null
            ? letters[wordRow[key]!]
            : '?';
        final tp = TextPainter(
          text: TextSpan(
            text: letter,
            style: TextStyle(
              color: const Color(0xFF1F2937),
              fontWeight: FontWeight.w900,
              fontSize: cell * 0.55,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(
            rect.center.dx - tp.width / 2,
            rect.center.dy - tp.height / 2,
          ),
        );
      }
    }
  }

  // Letter wheel at bottom — circle with 8 yellow tile dots.
  final wheelCenter = Offset(s.width * 0.5, s.height * 0.78);
  final wheelR = s.width * 0.22;
  // Soft outer glow.
  canvas.drawCircle(
    wheelCenter,
    wheelR + 4,
    Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
  );
  canvas.drawCircle(
    wheelCenter,
    wheelR,
    Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3,
  );
  const wheelLetters = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'];
  for (var i = 0; i < 8; i++) {
    final angle = -math.pi / 2 + i * (2 * math.pi / 8);
    final p =
        wheelCenter + Offset(math.cos(angle), math.sin(angle)) * wheelR;
    canvas.drawCircle(
      p,
      cell * 0.18,
      Paint()..color = const Color(0xFFFBBF24),
    );
    final tp = TextPainter(
      text: TextSpan(
        text: wheelLetters[i],
        style: TextStyle(
          color: const Color(0xFF1F2937),
          fontWeight: FontWeight.w900,
          fontSize: cell * 0.20,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(p.dx - tp.width / 2, p.dy - tp.height / 2));
  }
}

void _paintCandyDrop(Canvas canvas, Size s) {
  // Purple-pink background.
  final bg = Paint()
    ..shader = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)],
    ).createShader(Rect.fromLTWH(0, 0, s.width, s.height));
  canvas.drawRect(Rect.fromLTWH(0, 0, s.width, s.height), bg);

  // Candy cluster grid.
  const colors = [
    Color(0xFFEF4444),
    Color(0xFFFBBF24),
    Color(0xFF34D399),
    Color(0xFF60A5FA),
    Color(0xFFA855F7),
  ];
  final rng = math.Random(7);
  final cell = s.width * 0.12;
  for (var r = 0; r < 5; r++) {
    for (var c = 0; c < 5; c++) {
      final cx = s.width * 0.16 + c * (cell + 2);
      final cy = s.height * 0.12 + r * (cell + 2);
      final color = colors[rng.nextInt(colors.length)];
      // Highlight.
      canvas.drawCircle(
        Offset(cx, cy),
        cell * 0.42,
        Paint()
          ..shader = RadialGradient(
            colors: [Colors.white, color],
          ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: cell * 0.42)),
      );
      canvas.drawCircle(
        Offset(cx, cy),
        cell * 0.42,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }
}

void _paintFruitMerge(Canvas canvas, Size s) {
  // Warm mango → raspberry background to read as "fruit juice" rather
  // than the candy-cluster palette.
  final bg = Paint()
    ..shader = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFB923C), Color(0xFFEC4899)],
    ).createShader(Rect.fromLTWH(0, 0, s.width, s.height));
  canvas.drawRect(Rect.fromLTWH(0, 0, s.width, s.height), bg);

  // Soft white sheen across the top.
  canvas.drawRect(
    Rect.fromLTWH(0, 0, s.width, s.height * 0.55),
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.30),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, s.width, s.height * 0.55)),
  );

  // ── Watermelon slice (background, upper-left) ───────────────────
  _drawWatermelonSlice(
    canvas,
    Rect.fromCenter(
      center: Offset(s.width * 0.22, s.height * 0.35),
      width: s.width * 0.40,
      height: s.height * 0.42,
    ),
  );

  // ── Fruit tier (foreground, lower-right) — descending sizes ─────
  // Big orange → medium apple → small grape, stacked to imply
  // "merge into a bigger one".
  void drawFruit(
    double cx,
    double cy,
    double r,
    Color face,
    Color deep,
    Color highlight, {
    bool leaf = false,
  }) {
    canvas.drawCircle(
      Offset(cx + 1, cy + 2),
      r,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: [highlight, face, deep],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r)),
    );
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    // Specular dot.
    canvas.drawCircle(
      Offset(cx - r * 0.35, cy - r * 0.4),
      r * 0.18,
      Paint()..color = Colors.white.withValues(alpha: 0.65),
    );
    if (leaf) {
      final leafPath = Path()
        ..moveTo(cx, cy - r)
        ..quadraticBezierTo(
          cx + r * 0.5,
          cy - r * 1.1,
          cx + r * 0.35,
          cy - r * 0.65,
        )
        ..quadraticBezierTo(
          cx + r * 0.15,
          cy - r * 0.9,
          cx,
          cy - r,
        )
        ..close();
      canvas.drawPath(leafPath, Paint()..color = const Color(0xFF15803D));
    }
  }

  // Tier layout — diagonal cascade from lower-right to mid-left.
  drawFruit(
    s.width * 0.78,
    s.height * 0.70,
    s.width * 0.18,
    const Color(0xFFFB923C),
    const Color(0xFFC2410C),
    const Color(0xFFFED7AA),
    leaf: true,
  );
  drawFruit(
    s.width * 0.58,
    s.height * 0.82,
    s.width * 0.13,
    const Color(0xFFF87171),
    const Color(0xFFB91C1C),
    const Color(0xFFFECACA),
    leaf: true,
  );
  drawFruit(
    s.width * 0.40,
    s.height * 0.90,
    s.width * 0.085,
    const Color(0xFFA855F7),
    const Color(0xFF6B21A8),
    const Color(0xFFE9D5FF),
    leaf: true,
  );

  // ── Merge arrow / plus sign between tiers ───────────────────────
  final plusC = Offset(s.width * 0.69, s.height * 0.55);
  final plusR = s.width * 0.045;
  canvas.drawCircle(
    plusC,
    plusR,
    Paint()..color = Colors.white,
  );
  canvas.drawCircle(
    plusC,
    plusR,
    Paint()
      ..color = const Color(0xFFEC4899)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5,
  );
  canvas.drawLine(
    Offset(plusC.dx - plusR * 0.5, plusC.dy),
    Offset(plusC.dx + plusR * 0.5, plusC.dy),
    Paint()
      ..color = const Color(0xFFEC4899)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round,
  );
  canvas.drawLine(
    Offset(plusC.dx, plusC.dy - plusR * 0.5),
    Offset(plusC.dx, plusC.dy + plusR * 0.5),
    Paint()
      ..color = const Color(0xFFEC4899)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round,
  );

  // ── Sparkles ────────────────────────────────────────────────────
  final sparkle = Paint()..color = Colors.white.withValues(alpha: 0.9);
  for (final sp in [
    [0.15, 0.55, 3.5],
    [0.32, 0.18, 2.5],
    [0.88, 0.30, 3.0],
    [0.95, 0.85, 2.0],
    [0.05, 0.85, 2.5],
  ]) {
    final cx = s.width * sp[0];
    final cy = s.height * sp[1];
    final r = sp[2];
    canvas.drawCircle(Offset(cx, cy), r, sparkle);
    canvas.drawLine(
      Offset(cx - r * 1.8, cy),
      Offset(cx + r * 1.8, cy),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.7)
        ..strokeWidth = 1.2,
    );
    canvas.drawLine(
      Offset(cx, cy - r * 1.8),
      Offset(cx, cy + r * 1.8),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.7)
        ..strokeWidth = 1.2,
    );
  }
}

void _paintMemoryCards(Canvas canvas, Size s) {
  // Soft mint background.
  final bg = Paint()..color = const Color(0xFFA7F3D0);
  canvas.drawRect(Rect.fromLTWH(0, 0, s.width, s.height), bg);

  // 4×3 grid of cards.
  const cardColors = [
    Color(0xFFFBBF24),
    Color(0xFFF472B6),
    Color(0xFF60A5FA),
    Color(0xFFFB7185),
    Color(0xFF34D399),
    Color(0xFFA855F7),
  ];
  final cardW = s.width * 0.2;
  final cardH = s.height * 0.22;
  for (var r = 0; r < 3; r++) {
    for (var c = 0; c < 4; c++) {
      final idx = r * 4 + c;
      final cx = s.width * 0.1 + c * (cardW + 4);
      final cy = s.height * 0.1 + r * (cardH + 4);
      final rect = Rect.fromLTWH(cx, cy, cardW, cardH);
      // Shadow.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect.translate(1, 2),
          const Radius.circular(6),
        ),
        Paint()..color = Colors.black.withValues(alpha: 0.2),
      );
      // Card body.
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        Paint()..color = cardColors[idx % cardColors.length],
      );
      // Animal silhouette (simple circle + dot).
      canvas.drawCircle(
        rect.center,
        cardW * 0.15,
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(
        Offset(rect.center.dx - 2, rect.center.dy - 1),
        1,
        Paint()..color = const Color(0xFF1F2937),
      );
      canvas.drawCircle(
        Offset(rect.center.dx + 2, rect.center.dy - 1),
        1,
        Paint()..color = const Color(0xFF1F2937),
      );
    }
  }
}

void _paintBalloonPop(Canvas canvas, Size s) {
  // Sky gradient.
  final bg = Paint()
    ..shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF60A5FA), Color(0xFFBFDBFE)],
    ).createShader(Rect.fromLTWH(0, 0, s.width, s.height));
  canvas.drawRect(Rect.fromLTWH(0, 0, s.width, s.height), bg);

  // Clouds.
  final cloud = Paint()..color = Colors.white.withValues(alpha: 0.7);
  for (final cld in [
    [0.20, 0.15, 18.0],
    [0.65, 0.10, 14.0],
    [0.40, 0.22, 12.0],
  ]) {
    canvas.drawCircle(
      Offset(s.width * cld[0], s.height * cld[1]),
      cld[2],
      cloud,
    );
  }

  // Balloons.
  const balloonColors = [
    Color(0xFFEF4444),
    Color(0xFFFBBF24),
    Color(0xFF34D399),
    Color(0xFF60A5FA),
    Color(0xFFF472B6),
    Color(0xFFA855F7),
  ];
  for (var i = 0; i < 6; i++) {
    final cx = s.width * (0.15 + (i % 3) * 0.35);
    final cy = s.height * (0.45 + (i ~/ 3) * 0.18);
    final color = balloonColors[i];
    // Balloon body.
    final balloonRect = Rect.fromCenter(
      center: Offset(cx, cy),
      width: s.width * 0.16,
      height: s.height * 0.14,
    );
    canvas.drawOval(balloonRect, Paint()..color = color);
    // Highlight.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx - 4, cy - 4),
        width: 6,
        height: 8,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.5),
    );
    // String.
    canvas.drawLine(
      Offset(cx, balloonRect.bottom),
      Offset(cx, balloonRect.bottom + 12),
      Paint()
        ..color = Colors.black54
        ..strokeWidth = 1,
    );
  }
}

void _paintJellyJump(Canvas canvas, Size s) {
  // Soft sky.
  final bg = Paint()
    ..shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFFEF3C7), Color(0xFFFBCFE8)],
    ).createShader(Rect.fromLTWH(0, 0, s.width, s.height));
  canvas.drawRect(Rect.fromLTWH(0, 0, s.width, s.height), bg);

  // Platforms.
  const platColors = [
    Color(0xFFEC4899),
    Color(0xFFFBBF24),
    Color(0xFF34D399),
    Color(0xFF60A5FA),
  ];
  for (var i = 0; i < 4; i++) {
    final px = s.width * (0.1 + i * 0.22);
    final py = s.height * (0.7 - i * 0.12);
    final w = s.width * 0.18;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(px, py, w, s.height * 0.05),
        const Radius.circular(4),
      ),
      Paint()..color = platColors[i],
    );
  }

  // Squishy pink jelly character.
  final jellyCenter = Offset(s.width * 0.18, s.height * 0.5);
  canvas.drawCircle(
    jellyCenter.translate(0, 4),
    s.width * 0.10,
    Paint()..color = Colors.black.withValues(alpha: 0.25),
  );
  // Body — squished ellipse.
  canvas.drawOval(
    Rect.fromCenter(
      center: jellyCenter,
      width: s.width * 0.22,
      height: s.height * 0.18,
    ),
    Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xFFF9A8D4), Color(0xFFEC4899)],
      ).createShader(Rect.fromCenter(
        center: jellyCenter,
        width: s.width * 0.22,
        height: s.height * 0.18,
      )),
  );
  // Eyes.
  canvas.drawCircle(
    Offset(jellyCenter.dx - 4, jellyCenter.dy - 2),
    2.4,
    Paint()..color = const Color(0xFF1F2937),
  );
  canvas.drawCircle(
    Offset(jellyCenter.dx + 4, jellyCenter.dy - 2),
    2.4,
    Paint()..color = const Color(0xFF1F2937),
  );
  // Smile.
  canvas.drawArc(
    Rect.fromCenter(
      center: jellyCenter.translate(0, 4),
      width: 10,
      height: 6,
    ),
    0,
    math.pi,
    false,
    Paint()
      ..color = const Color(0xFF1F2937)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke,
  );
}

void _paintTowerBuilder(Canvas canvas, Size s) {
  // Warm orange background.
  final bg = Paint()
    ..shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFFED7AA), Color(0xFFFB923C)],
    ).createShader(Rect.fromLTWH(0, 0, s.width, s.height));
  canvas.drawRect(Rect.fromLTWH(0, 0, s.width, s.height), bg);

  // Crane arm at top.
  final craneRect = Rect.fromLTWH(
    s.width * 0.3,
    s.height * 0.05,
    s.width * 0.45,
    s.height * 0.06,
  );
  canvas.drawRect(craneRect, Paint()..color = const Color(0xFF1F293B));
  // Rope.
  canvas.drawLine(
    Offset(s.width * 0.5, craneRect.bottom),
    Offset(s.width * 0.5, s.height * 0.3),
    Paint()
      ..color = const Color(0xFF1F293B)
      ..strokeWidth = 1.5,
  );
  // Swaying block (red).
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(s.width * 0.5, s.height * 0.32),
        width: s.width * 0.18,
        height: s.height * 0.07,
      ),
      const Radius.circular(4),
    ),
    Paint()..color = const Color(0xFFEF4444),
  );

  // Stacked tower at bottom.
  const stackColors = [
    Color(0xFFFBBF24),
    Color(0xFF34D399),
    Color(0xFF60A5FA),
    Color(0xFFF472B6),
    Color(0xFFA855F7),
  ];
  for (var i = 0; i < 5; i++) {
    final by = s.height * (0.45 + i * 0.09);
    final bx = s.width * (0.25 + (i % 2) * 0.1);
    final w = s.width * (0.4 + (i % 2) * 0.1);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(bx, by, w, s.height * 0.07),
        const Radius.circular(4),
      ),
      Paint()..color = stackColors[i],
    );
  }
}

void _paintGolfStar(Canvas canvas, Size s) {
  // Sky gradient.
  final bg = Paint()
    ..shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFBAE6FD), Color(0xFF86EFAC)],
    ).createShader(Rect.fromLTWH(0, 0, s.width, s.height));
  canvas.drawRect(Rect.fromLTWH(0, 0, s.width, s.height), bg);

  // Green hill.
  final hill = Path()
    ..moveTo(0, s.height * 0.85)
    ..quadraticBezierTo(
      s.width * 0.5,
      s.height * 0.45,
      s.width,
      s.height * 0.85,
    )
    ..lineTo(s.width, s.height)
    ..lineTo(0, s.height)
    ..close();
  canvas.drawPath(hill, Paint()..color = const Color(0xFF22C55E));

  // Flag at top of hill.
  final flagPoleX = s.width * 0.72;
  final flagTopY = s.height * 0.5;
  canvas.drawLine(
    Offset(flagPoleX, flagTopY),
    Offset(flagPoleX, s.height * 0.78),
    Paint()
      ..color = const Color(0xFF1F293B)
      ..strokeWidth = 1.5,
  );
  // Flag triangle.
  final flag = Path()
    ..moveTo(flagPoleX, flagTopY)
    ..lineTo(flagPoleX + 12, flagTopY + 4)
    ..lineTo(flagPoleX, flagTopY + 8)
    ..close();
  canvas.drawPath(flag, Paint()..color = const Color(0xFFEF4444));

  // Hole.
  canvas.drawCircle(
    Offset(flagPoleX, s.height * 0.79),
    3.5,
    Paint()..color = const Color(0xFF1F293B),
  );

  // Ball + trajectory.
  final ball = Offset(s.width * 0.2, s.height * 0.78);
  canvas.drawCircle(ball, 4, Paint()..color = Colors.white);
  canvas.drawCircle(ball, 4, Paint()
    ..color = Colors.black.withValues(alpha: 0.3)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1);
  // Arc.
  final arc = Path()
    ..moveTo(ball.dx, ball.dy)
    ..quadraticBezierTo(
      s.width * 0.45,
      s.height * 0.55,
      flagPoleX,
      s.height * 0.78,
    );
  canvas.drawPath(
    arc,
    Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2,
  );
}

void _paintBowlingPro(Canvas canvas, Size s) {
  // Wood lane.
  final bg = Paint()
    ..shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFFEF3C7), Color(0xFFFBBF24)],
    ).createShader(Rect.fromLTWH(0, 0, s.width, s.height));
  canvas.drawRect(Rect.fromLTWH(0, 0, s.width, s.height), bg);

  // Lane outline.
  final laneRect = Rect.fromLTWH(
    s.width * 0.15,
    s.height * 0.2,
    s.width * 0.7,
    s.height * 0.7,
  );
  canvas.drawRect(laneRect, Paint()..color = const Color(0xFFFCD34D));
  canvas.drawRect(
    laneRect,
    Paint()
      ..color = const Color(0xFF92400E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2,
  );
  // Lane planks (horizontal lines).
  final plank = Paint()
    ..color = const Color(0xFFB45309)
    ..strokeWidth = 1;
  for (var i = 1; i < 5; i++) {
    final y = laneRect.top + laneRect.height * (i / 5);
    canvas.drawLine(
      Offset(laneRect.left, y),
      Offset(laneRect.right, y),
      plank,
    );
  }

  // 10 pins at the end (top).
  final pinColor = Colors.white;
  final pinRadius = s.width * 0.025;
  // Simplify to 10 pins: triangle 4-3-2-1.
  final pinPositions = [
    [0.5],
    [0.42, 0.58],
    [0.34, 0.5, 0.66],
    [0.26, 0.34, 0.42, 0.5],
  ];
  for (var r = 0; r < pinPositions.length; r++) {
    final py = laneRect.top + 8 + r * (pinRadius * 2.5);
    for (var c = 0; c < pinPositions[r].length; c++) {
      final px = laneRect.left + laneRect.width * pinPositions[r][c];
      canvas.drawCircle(
        Offset(px, py),
        pinRadius,
        Paint()..color = pinColor,
      );
      canvas.drawCircle(
        Offset(px, py),
        pinRadius,
        Paint()
          ..color = const Color(0xFFEF4444)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  // Ball at bottom.
  final ball = Offset(laneRect.center.dx, laneRect.bottom - 10);
  canvas.drawCircle(ball, 8, Paint()..color = const Color(0xFFEF4444));
  canvas.drawCircle(
    Offset(ball.dx - 1, ball.dy - 1),
    1.5,
    Paint()..color = Colors.white,
  );
}

void _paintKnifeHit(Canvas canvas, Size s) {
  // Wood-toned background.
  final bg = Paint()
    ..shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFA16207), Color(0xFF78350F)],
    ).createShader(Rect.fromLTWH(0, 0, s.width, s.height));
  canvas.drawRect(Rect.fromLTWH(0, 0, s.width, s.height), bg);

  // Central wood log (circle).
  final logCenter = Offset(s.width * 0.5, s.height * 0.5);
  final logR = s.width * 0.28;
  canvas.drawCircle(
    logCenter,
    logR,
    Paint()..color = const Color(0xFF92400E),
  );
  // Wood rings.
  for (final r in [0.7, 0.45, 0.2]) {
    canvas.drawCircle(
      logCenter,
      logR * r,
      Paint()
        ..color = const Color(0xFF78350F)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  // 3 knives already embedded.
  for (var i = 0; i < 3; i++) {
    final angle = -math.pi / 2 + i * (math.pi / 3);
    final start = logCenter + Offset(math.cos(angle), math.sin(angle)) * (logR - 4);
    final end = start + Offset(math.cos(angle), math.sin(angle)) * 16;
    // Blade.
    canvas.drawLine(
      start,
      end,
      Paint()
        ..color = const Color(0xFFE5E7EB)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    // Handle.
    final handleEnd = end + Offset(math.cos(angle), math.sin(angle)) * 8;
    canvas.drawLine(
      end,
      handleEnd,
      Paint()
        ..color = const Color(0xFF1F293B)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
  }
}

void _paintSoccerHero(Canvas canvas, Size s) {
  // Green grass field.
  canvas.drawRect(
    Rect.fromLTWH(0, 0, s.width, s.height),
    Paint()..color = const Color(0xFF22C55E),
  );
  // Field stripe.
  canvas.drawRect(
    Rect.fromLTWH(0, s.height * 0.5, s.width, s.height * 0.5),
    Paint()..color = const Color(0xFF16A34A),
  );

  // Goal at top.
  final goalRect = Rect.fromLTWH(
    s.width * 0.25,
    s.height * 0.1,
    s.width * 0.5,
    s.height * 0.2,
  );
  // Posts.
  canvas.drawRect(
    Rect.fromLTWH(goalRect.left, goalRect.top, 4, goalRect.height),
    Paint()..color = Colors.white,
  );
  canvas.drawRect(
    Rect.fromLTWH(goalRect.right - 4, goalRect.top, 4, goalRect.height),
    Paint()..color = Colors.white,
  );
  canvas.drawRect(
    Rect.fromLTWH(goalRect.left, goalRect.top, goalRect.width, 4),
    Paint()..color = Colors.white,
  );
  // Net.
  final net = Paint()
    ..color = Colors.white.withValues(alpha: 0.7)
    ..strokeWidth = 0.6;
  for (var i = 0; i < 8; i++) {
    final x = goalRect.left + goalRect.width * (i / 8);
    canvas.drawLine(
      Offset(x, goalRect.top),
      Offset(x, goalRect.bottom),
      net,
    );
  }

  // Goalkeeper.
  canvas.drawCircle(
    Offset(goalRect.center.dx, goalRect.center.dy),
    7,
    Paint()..color = const Color(0xFFFBBF24),
  );

  // Soccer ball at bottom.
  final ball = Offset(s.width * 0.5, s.height * 0.82);
  canvas.drawCircle(
    ball,
    12,
    Paint()..color = Colors.white,
  );
  canvas.drawCircle(
    ball,
    12,
    Paint()
      ..color = const Color(0xFF1F293B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2,
  );
  // Pentagon shape on ball.
  final pentagon = Path();
  for (var i = 0; i < 5; i++) {
    final angle = -math.pi / 2 + i * (2 * math.pi / 5);
    final p = ball + Offset(math.cos(angle), math.sin(angle)) * 4;
    if (i == 0) {
      pentagon.moveTo(p.dx, p.dy);
    } else {
      pentagon.lineTo(p.dx, p.dy);
    }
  }
  pentagon.close();
  canvas.drawPath(pentagon, Paint()..color = const Color(0xFF1F293B));

  // Trajectory arrow.
  final arrow = Path()
    ..moveTo(ball.dx, ball.dy - 8)
    ..quadraticBezierTo(
      ball.dx + 20,
      ball.dy - 30,
      goalRect.center.dx,
      goalRect.bottom - 4,
    );
  canvas.drawPath(
    arrow,
    Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2,
  );
}

void _paintBubbleShooter(Canvas canvas, Size s) {
  // Soft pastel backdrop (sky → lilac).
  final bg = Paint()
    ..shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFBAE6FD), Color(0xFFDDD6FE)],
    ).createShader(Rect.fromLTWH(0, 0, s.width, s.height));
  canvas.drawRect(Rect.fromLTWH(0, 0, s.width, s.height), bg);

  // 3x3 cluster of glossy bubbles.
  const palette = <Color>[
    Color(0xFF60A5FA), // sky blue
    Color(0xFFF472B6), // pink
    Color(0xFFFDE047), // bright yellow
    Color(0xFF86EFAC), // lime green
    Color(0xFFA78BFA), // violet
    Color(0xFFF87171), // soft red
  ];
  final cols = 3;
  final rows = 3;
  final spacing = s.width / 4;
  final radius = spacing * 0.45;
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      final x = spacing * (c + 1) + (r.isOdd ? spacing * 0.5 : 0);
      final y = spacing * (r + 0.7);
      if (x > s.width - radius * 0.4) continue;
      final color = palette[(r * cols + c) % palette.length];
      // Drop shadow.
      canvas.drawCircle(
        Offset(x, y + radius * 0.18),
        radius,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.20)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      // Bubble body with radial gradient.
      canvas.drawCircle(
        Offset(x, y),
        radius,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.3, -0.4),
            radius: 0.9,
            colors: [
              Color.lerp(color, Colors.white, 0.5) ?? color,
              color,
              Color.lerp(color, Colors.black, 0.15) ?? color,
            ],
          ).createShader(
            Rect.fromCircle(center: Offset(x, y), radius: radius),
          ),
      );
      // Glossy highlight.
      canvas.drawCircle(
        Offset(x - radius * 0.32, y - radius * 0.36),
        radius * 0.28,
        Paint()..color = Colors.white.withValues(alpha: 0.7),
      );
      // Outline.
      canvas.drawCircle(
        Offset(x, y),
        radius,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
    }
  }
}

void _paintGeneric(Canvas canvas, Size s) {
    // Redesigned fallback: a layered accent disc with a soft
    // highlight + a small sparkle on top so unknown game ids still
    // feel intentional rather than empty.
    final c = s.center(Offset.zero);

    // Outer soft halo.
    canvas.drawCircle(
      c,
      s.width * 0.40,
      Paint()..color = accent.withValues(alpha: 0.18),
    );
    // Disc fill.
    canvas.drawCircle(
      c,
      s.width * 0.32,
      Paint()..color = accent.withValues(alpha: 0.45),
    );
    // Glossy top sheen on the disc.
    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: c, radius: s.width * 0.32)),
    );
    canvas.drawRect(
      Rect.fromLTWH(c.dx - s.width * 0.32, c.dy - s.width * 0.32,
          s.width * 0.64, s.width * 0.40),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.40),
            Colors.white.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: c, radius: s.width * 0.32)),
    );
    canvas.restore();
    // Outline ring.
    canvas.drawCircle(
      c,
      s.width * 0.32,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = s.width * 0.04,
    );
    // Inner concentric ring for visual interest.
    canvas.drawCircle(
      c,
      s.width * 0.16,
      Paint()..color = accent.withValues(alpha: 0.7),
    );
    // Tiny sparkle in the top-right.
    final spark = Offset(c.dx + s.width * 0.18, c.dy - s.width * 0.20);
    final sparkPath = Path()
      ..moveTo(spark.dx, spark.dy - s.width * 0.06)
      ..lineTo(spark.dx + s.width * 0.04, spark.dy)
      ..lineTo(spark.dx, spark.dy + s.width * 0.06)
      ..lineTo(spark.dx - s.width * 0.04, spark.dy)
      ..close();
    canvas.drawPath(sparkPath, Paint()..color = Colors.white);
  }

  Color _darker(Color c, double amount) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .toColor();
  }

  /// Shared faint outer outline drawn around board-shaped artworks
  /// (block-puzzle, snake, etc.) so the per-recipe code stays focused
  /// on the unique shapes.
  void _drawBoardOutline(Canvas canvas, Size s) {
    final outline = Paint()
      ..color = Colors.white.withValues(
        alpha: brightness == Brightness.dark ? 0.15 : 0.25,
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, s.width, s.height),
        const Radius.circular(10),
      ),
      outline,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Newly added recipes — keep this section so future contributors
  // can see what was added vs the original 49-game set.
  // ─────────────────────────────────────────────────────────────

  void _paintTypingRace(Canvas canvas, Size s) {
    // Keyboard-row inspired: 3 rows of letter-keys with one key
    // highlighted mid-press. Communicates "typing" instantly without
    // text rendering (text glyphs vary wildly across Android emoji
    // fonts and looked broken in light-mode screenshots).
    final keyColor = Paint()
      ..color = brightness == Brightness.dark
          ? Colors.white.withValues(alpha: 0.14)
          : Colors.black.withValues(alpha: 0.10);
    final keyStroke = Paint()
      ..color = brightness == Brightness.dark
          ? Colors.white.withValues(alpha: 0.30)
          : Colors.black.withValues(alpha: 0.30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    const rows = 3;
    const cols = 5;
    final pad = s.width * 0.10;
    final gap = s.width * 0.04;
    final keyW = (s.width - pad * 2 - gap * (cols - 1)) / cols;
    final keyH = (s.height - pad * 2 - gap * (rows - 1)) / rows;

    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final rect = Rect.fromLTWH(
          pad + c * (keyW + gap),
          pad + r * (keyH + gap),
          keyW,
          keyH,
        );
        final isActive = r == 1 && c == 2;
        final rr = RRect.fromRectAndRadius(rect, const Radius.circular(4));
        if (isActive) {
          canvas.drawRRect(rr, Paint()..color = accent.withValues(alpha: 0.85));
        } else {
          canvas.drawRRect(rr, keyColor);
          canvas.drawRRect(rr, keyStroke);
        }
      }
    }
  }

  void _paintDotsAndBoxes(Canvas canvas, Size s) {
    // 4x4 dot grid with one box already claimed (filled accent
    // rectangle). Reads as "Dots and Boxes" without text.
    const rows = 4;
    const cols = 4;
    final pad = s.width * 0.15;
    final usable = s.width - pad * 2;
    final cell = usable / (cols - 1);

    // One claimed box (top-left) to suggest the "boxes" half.
    final claimedRect = Rect.fromLTWH(
      pad - cell * 0.18,
      pad - cell * 0.18,
      cell * 0.74,
      cell * 0.74,
    );
    canvas.drawRect(claimedRect, Paint()..color = accent.withValues(alpha: 0.85));

    // Connecting lines hinting at claimed edges.
    final lineColor = Paint()
      ..color = accent.withValues(alpha: 0.95)
      ..strokeWidth = cell * 0.12
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(pad - cell * 0.18, pad - cell * 0.18),
      Offset(pad + cell * 0.56, pad - cell * 0.18),
      lineColor,
    );
    canvas.drawLine(
      Offset(pad - cell * 0.18, pad - cell * 0.18),
      Offset(pad - cell * 0.18, pad + cell * 0.56),
      lineColor,
    );

    final dot = Paint()
      ..color = brightness == Brightness.dark
          ? Colors.white
          : Colors.black.withValues(alpha: 0.85);
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        canvas.drawCircle(
          Offset(pad + c * cell, pad + r * cell),
          cell * 0.10,
          dot,
        );
      }
    }
  }
}

/// Helper that returns a dark-mode-aware shadow color for cards that
/// host [GameArtwork] inside them.
Color gameArtworkShadowFor(Brightness b) => b == Brightness.dark
    ? Colors.black.withValues(alpha: 0.45)
    : Colors.black.withValues(alpha: 0.08);