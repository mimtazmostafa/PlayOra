import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../game_widgets.dart';
import '../mini_game.dart';
import '../widgets/game_flow_overlays.dart';

/// Flappy Bird — single-screen tap-to-fly game in the "Pool /
/// Backgammon / Maze Escape" mini-game family.
///
/// Match the reference: side-on cartoon sky with green pipes and a
/// yellow bird. Tap to flap upward; gravity drags the bird down.
/// Pass through as many pipes as possible — reach the target score
/// to win, otherwise it's an endless run until you crash.
///
/// Phases: `start → ready → play → win|trophy`.
class FlappyBirdGame extends MiniGame {
  const FlappyBirdGame({
    super.key,
    required super.callbacks,
    this.level = 1,
  });

  /// 1 = easy, 2 = medium, 3+ = hard pipe difficulty. Kept for
  /// dispatcher back-compat — same difficulty curve regardless.
  final int level;

  @override
  State<FlappyBirdGame> createState() => _FlappyBirdGameState();
}

enum _FBPhase { start, ready, play, win, trophy }

class _FlappyBirdGameState extends MiniGameState<FlappyBirdGame>
    with SingleTickerProviderStateMixin {
  static const double _gravity = 0.55;
  static const double _jumpStrength = -8.5;
  static const double _pillarWidth = 70;
  static const double _pillarGap = 180;
  static const double _pillarSpeed = 2.0;
  static const double _birdRadius = 12;

  /// Visual cushion between bird center and game-over floor — lets the
  /// bird's body actually touch the ground before the run ends.
  static const double _floorCushion = 8;

  /// Target score to win — matches the reference's "Best 15 / Target 15".
  static const int _targetScore = 15;

  late final Ticker _ticker;
  final Random _rng = Random();

  double _birdY = 0;
  double _birdVy = 0;
  int _score = 0;
  int _bestScore = 0;
  bool _gameOver = false;
  final List<_Pillar> _pillars = <_Pillar>[];
  int _spawnTimer = 0;
  _FBPhase _phase = _FBPhase.start;

  double _boardW = 0;
  double _boardH = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reportScore(_score);
      reportStats('Best 0  •  Tap to flap');
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _refreshHud() {
    reportScore(_score);
    reportStats('Score $_score  •  Best $_bestScore');
  }

  void _resetGame() {
    _birdY = _boardH > 0 ? _boardH / 2 : 250;
    _birdVy = 0;
    _score = 0;
    _pillars.clear();
    _spawnTimer = 0;
    _gameOver = false;
    if (_boardW > 0) _spawnPillar();
  }

  void _onPlay() {
    setState(() {
      _phase = _FBPhase.ready;
      _resetGame();
    });
    _refreshHud();
  }

  void _onPlayAgain() {
    setState(() {
      _phase = _FBPhase.start;
      _score = 0;
      _resetGame();
    });
    _refreshHud();
  }

  void _onTick(Duration elapsed) {
    if (_gameOver) {
      if (_ticker.isActive) _ticker.stop();
      return;
    }
    if (_phase != _FBPhase.play && _phase != _FBPhase.ready) return;
    if (_boardW <= 0) return;
    setState(() {
      // Pillars scroll in BOTH ready + play so the world feels alive
      // before the first tap.
      for (final p in _pillars) {
        p.x -= _pillarSpeed;
      }
      _pillars.removeWhere((p) => p.x + _pillarWidth <= 0);

      _spawnTimer++;
      if (_spawnTimer > 110) {
        _spawnTimer = 0;
        _spawnPillar();
      }

      if (_phase == _FBPhase.play) {
        _birdVy += _gravity;
        _birdY += _birdVy;

        for (final p in _pillars) {
          if (!p.passed && p.x + _pillarWidth < _boardW * 0.33) {
            p.passed = true;
            _score++;
            _bestScore = max(_bestScore, _score);
            reportScore(_score);
          }
        }

        if (_birdY < _birdRadius ||
            _birdY > _boardH - _birdRadius - _floorCushion) {
          _crash();
        } else if (_checkPillarCollision()) {
          _crash();
        }
      }
    });
  }

  void _spawnPillar() {
    final margin = 80.0;
    final gapY = margin + _rng.nextDouble() * (_boardH - margin * 2 - _pillarGap);
    _pillars.add(
      _Pillar(
        x: _boardW,
        topH: gapY,
        bottomY: gapY + _pillarGap,
      ),
    );
  }

  bool _checkPillarCollision() {
    final x = _boardW * 0.33;
    for (final p in _pillars) {
      final left = p.x;
      final right = p.x + _pillarWidth;
      if (x + _birdRadius > left && x - _birdRadius < right) {
        if (_birdY - _birdRadius < p.topH ||
            _birdY + _birdRadius > p.bottomY) {
          return true;
        }
      }
    }
    return false;
  }

  void _crash() {
    if (_gameOver) return;
    _gameOver = true;
    _bestScore = max(_bestScore, _score);
    haptic(HapticFeedbackType.heavy);
    reportScore(_score);
    reportStats('Score $_score  •  Best $_bestScore');
    reportGameOver();
    if (_score >= _targetScore) {
      setState(() {
        _phase = _FBPhase.win;
      });
    } else {
      setState(() {
        _phase = _FBPhase.trophy;
      });
    }
  }

  void _jump() {
    if (_phase != _FBPhase.play && _phase != _FBPhase.ready) return;
    if (_gameOver) return;
    if (_phase == _FBPhase.ready) {
      // First tap leaves the ready phase and starts physics.
      setState(() {
        _phase = _FBPhase.play;
      });
    }
    _birdVy = _jumpStrength;
    haptic(HapticFeedbackType.light);
    _refreshHud();
  }

  void _onContinueAfterWin() {
    setState(() {
      _phase = _FBPhase.trophy;
    });
  }

  // ── Build ────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: LayoutBuilder(
              builder: (context, c) {
                _boardW = c.maxWidth;
                _boardH = c.maxHeight;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _jump,
                  child: CustomPaint(
                    painter: _FlappyPainter(
                      birdY: _birdY,
                      birdVy: _birdVy,
                      pillars: _pillars,
                      boardW: _boardW,
                      score: _score,
                      pillarWidth: _pillarWidth,
                      showTapHint: _phase == _FBPhase.ready,
                    ),
                    size: Size(_boardW, _boardH),
                  ),
                );
              },
            ),
          ),
        ),
        if (_phase == _FBPhase.start)
          GameStartOverlay(
            title: 'FLAPPY BIRD',
            subtitle: 'Fly through the pipes\nand beat your best!',
            youScore: _bestScore,
            targetScore: _targetScore,
            instruction:
                'Tap to flap. Don\'t hit the pipes or the ground. Reach the target score to win.',
            illustration: const BoyCharacter(pose: BoyPose.walking),
            onPlay: _onPlay,
            onBack: () => Navigator.of(context).maybePop(),
          ),
        if (_phase == _FBPhase.win)
          GameWinOverlay(
            title: 'YOU WIN!',
            subtitle: 'TARGET REACHED!',
            scoreValue: _score,
            scoreLabel: 'Pipes Cleared',
            statRows: [
              ('Best', '$_bestScore'),
              ('Target', '$_targetScore'),
            ],
            onContinue: _onContinueAfterWin,
          ),
        if (_phase == _FBPhase.trophy)
          GameTrophyOverlay(
            iconData: Icons.emoji_events_rounded,
            iconGradient: const [Color(0xFFFCD34D), Color(0xFFF59E0B)],
            title: _score >= _targetScore ? 'Great Job!' : 'Keep Going!',
            subtitle: _score >= _targetScore
                ? 'You hit the target score.'
                : 'Try again — beat your best!',
            score: _score,
            statRows: [
              ('Score', '$_score'),
              ('Best', '$_bestScore'),
              ('Target', '$_targetScore'),
            ],
            onPlayAgain: _onPlayAgain,
            onBack: () => Navigator.of(context).maybePop(),
          ),
        // Top HUD removed — host GameContainerScreen provides it.
      ],
    );
  }
}

class _Pillar {
  _Pillar({required this.x, required this.topH, required this.bottomY});
  double x;
  final double topH;
  final double bottomY;
  bool passed = false;
}

// ────────────────────────────────────────────────────────────────────
// Painter
// ────────────────────────────────────────────────────────────────────

class _FlappyPainter extends CustomPainter {
  _FlappyPainter({
    required this.birdY,
    required this.birdVy,
    required this.pillars,
    required this.boardW,
    required this.score,
    required this.pillarWidth,
    required this.showTapHint,
  });

  final double birdY;
  final double birdVy;
  final List<_Pillar> pillars;
  final double boardW;
  final int score;
  final double pillarWidth;
  final bool showTapHint;

  static const _skyTop = Color(0xFF87CEEB);
  static const _skyBottom = Color(0xFFBFDBFE);
  static const _ground = Color(0xFF8B5A2B);
  static const _pillarGreen = Color(0xFF22C55E);
  static const _pillarDark = Color(0xFF166534);
  static const _birdYellow = Color(0xFFFACC15);
  static const _birdOrange = Color(0xFFEF6C00);

  @override
  void paint(Canvas canvas, Size size) {
    // Sky.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_skyTop, _skyBottom],
        ).createShader(Offset.zero & size),
    );

    // Clouds.
    final cloud = Paint()..color = Colors.white.withValues(alpha: 0.7);
    final cloudR = size.width * 0.08;
    final cloudY = size.height * 0.18;
    canvas.drawCircle(Offset(size.width * 0.18, cloudY), cloudR, cloud);
    canvas.drawCircle(Offset(size.width * 0.55, cloudY * 0.7), cloudR * 0.8, cloud);
    canvas.drawCircle(Offset(size.width * 0.82, cloudY * 1.2), cloudR * 0.9, cloud);

    // Pillars.
    for (final p in pillars) {
      _drawPillar(canvas, p.x, 0, pillarWidth, p.topH);
      _drawPillar(canvas, p.x, p.bottomY, pillarWidth, size.height - p.bottomY);
    }

    // Ground.
    final groundH = size.height * 0.08;
    final groundRect = Rect.fromLTWH(
      0,
      size.height - groundH,
      size.width,
      groundH,
    );
    canvas.drawRect(groundRect, Paint()..color = _ground);
    canvas.drawRect(
      Rect.fromLTWH(0, size.height - groundH, size.width, 4),
      Paint()..color = _pillarDark,
    );

    // Bird.
    final bx = size.width * 0.33;
    final by = birdY;
    final r = 14.0;
    canvas.drawCircle(
      Offset(bx, by + 2),
      r,
      Paint()..color = Colors.black.withValues(alpha: 0.3),
    );
    canvas.drawCircle(Offset(bx, by), r, Paint()..color = _birdYellow);
    // Wing.
    final wingY = by + (birdVy > 0 ? 3 : -3);
    canvas.drawOval(
      Rect.fromLTWH(bx - 8, wingY, 12, 6),
      Paint()..color = Colors.white.withValues(alpha: 0.7),
    );
    // Eye.
    canvas.drawCircle(Offset(bx + 4, by - 3), 4, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(bx + 5, by - 3), 2, Paint()..color = Colors.black);
    // Beak.
    final beak = Path()
      ..moveTo(bx + 10, by - 1)
      ..lineTo(bx + 18, by + 2)
      ..lineTo(bx + 10, by + 5)
      ..close();
    canvas.drawPath(beak, Paint()..color = _birdOrange);

    if (showTapHint) {
      _drawTapHint(canvas, size);
    }

    // In-painter score removed — host GameContainerScreen provides it.
  }

  void _drawTapHint(Canvas canvas, Size size) {
    final cx = size.width * 0.33 + 26;
    final cy = birdY - 36;
    // Pill background.
    final text = const TextSpan(
      text: 'TAP TO FLAP',
      style: TextStyle(
        color: Color(0xFF111827),
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.2,
      ),
    );
    final tp = TextPainter(
      text: text,
      textDirection: TextDirection.ltr,
    )..layout();
    final padX = 10.0;
    final padY = 6.0;
    final rect = Rect.fromLTWH(
      cx - tp.width / 2 - padX,
      cy - tp.height / 2 - padY,
      tp.width + padX * 2,
      tp.height + padY * 2,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(14)),
      Paint()..color = Colors.white.withValues(alpha: 0.92),
    );
    // Pointer triangle pointing to the bird.
    final tri = Path()
      ..moveTo(rect.center.dx - 6, rect.bottom)
      ..lineTo(rect.center.dx + 6, rect.bottom)
      ..lineTo(rect.center.dx, rect.bottom + 7)
      ..close();
    canvas.drawPath(tri, Paint()..color = Colors.white.withValues(alpha: 0.92));
    tp.paint(canvas, Offset(rect.left + padX, rect.top + padY));
  }

  void _drawPillar(Canvas canvas, double x, double y, double w, double h) {
    canvas.drawRect(Rect.fromLTWH(x, y, w, h), Paint()..color = _pillarGreen);
    canvas.drawRect(
      Rect.fromLTWH(x, y, 6, h),
      Paint()..color = _pillarDark,
    );
    canvas.drawRect(
      Rect.fromLTWH(x + w - 6, y, 6, h),
      Paint()..color = _pillarDark,
    );
    // Cap.
    final capH = h.clamp(8.0, 24.0);
    canvas.drawRect(
      Rect.fromLTWH(x - 4, y == 0 ? h - capH : y, w + 8, capH),
      Paint()..color = _pillarGreen,
    );
    canvas.drawRect(
      Rect.fromLTWH(x - 4, y == 0 ? h - capH : y, w + 8, 4),
      Paint()..color = _pillarDark,
    );
  }

  @override
  bool shouldRepaint(_FlappyPainter old) =>
      old.birdY != birdY ||
      old.birdVy != birdVy ||
      old.pillars != pillars ||
      old.score != score ||
      old.showTapHint != showTapHint;
}
