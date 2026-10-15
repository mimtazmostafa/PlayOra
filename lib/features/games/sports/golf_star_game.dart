import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../game_widgets.dart';
import '../mini_game.dart';
import '../widgets/game_flow_overlays.dart';

/// Golf Star — side-view drag-and-release putting game in the "Pool /
/// Backgammon / Maze Escape" mini-game family.
///
/// Match the reference: green fairway with a white golf ball and a
/// red flag marking the hole. Drag back from the ball to aim, release
/// to shoot. Land the ball in the hole to score. Score 3 strokes or
/// fewer across 3 holes to win.
///
/// Phases: `start → play → win → trophy`.
class GolfStarGame extends MiniGame {
  const GolfStarGame({super.key, required super.callbacks});

  @override
  State<GolfStarGame> createState() => _GolfStarGameState();
}

enum _GolfPhase { start, play, win, trophy }

class _GolfBall {
  _GolfBall(this.x, this.y);
  double x;
  double y;
  double vx = 0;
  double vy = 0;
}

class _GolfHole {
  _GolfHole(this.x, this.y, this.par);
  final double x;
  final double y;
  final int par;
}

class _GolfStarGameState extends MiniGameState<GolfStarGame>
    with SingleTickerProviderStateMixin {
  /// Target par for the round — wins at 3 strokes or fewer across 3 holes.
  static const int _targetStrokes = 3;

  /// Number of holes in the round.
  static const int _holeCount = 3;

  // ── Physics constants (units: pixels, seconds). ────────────────
  /// Pixels per second² — pulled-down value for a "heavy" feel.
  static const double _gravity = 980.0;
  /// How much horizontal velocity the ground kills per second.
  static const double _groundFrictionPerSec = 4.5;
  /// Cap on putt power — maps to a max launch speed (px/s).
  static const double _maxLaunchSpeed = 720.0;
  /// Below this speed (px/s) the ball is considered at rest.
  static const double _restSpeed = 28.0;
  /// Vertical tolerance for "ball in hole" detection.
  static const double _holeCaptureRadius = 14.0;

  late final Ticker _ticker;

  List<_GolfHole> _holes = const [];
  _GolfBall _ball = _GolfBall(0, 0);
  int _holeIndex = 0;
  int _strokes = 0;
  int _score = 0;
  int _bestStrokes = 99;
  _GolfPhase _phase = _GolfPhase.start;

  /// Drag state.
  Offset? _aimStart;
  Offset _aimCurrent = Offset.zero;
  bool _isAiming = false;

  double _boardW = 0;
  double _boardH = 0;
  /// Y-coordinate of the putting green (the ball sits on this line).
  double _groundY = 0;
  Duration _last = Duration.zero;
  bool _ballStopped = true;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reportScore(_score);
      reportStats('Strokes $_strokes  •  Best $_bestStrokes');
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _refreshHud() {
    reportScore(_score);
    reportStats(
      'Strokes $_strokes  •  Hole ${_holeIndex + 1}/$_holeCount',
    );
  }

  void _buildHoles() {
    _holes = [];
    if (_boardW <= 0 || _boardH <= 0) return;
    final maxX = max(140.0, _boardW - 100);
    // All holes sit on the putting green so the ball can actually
    // reach them. Place each hole a comfortable distance from the
    // previous one — staggered along the green.
    for (var i = 0; i < _holeCount; i++) {
      final x = (_boardW * (0.45 + i * 0.18)).clamp(120.0, maxX);
      _holes.add(_GolfHole(x, _groundY, 1));
    }
  }

  void _onPlay() {
    setState(() {
      _phase = _GolfPhase.play;
      _strokes = 0;
      _score = 0;
      _holeIndex = 0;
      _isAiming = false;
      _aimStart = null;
      _last = Duration.zero;
      // Hole / ball positions are computed lazily in the
      // LayoutBuilder once we know _boardW / _boardH.
    });
    _refreshHud();
  }

  void _onPlayAgain() {
    setState(() {
      _phase = _GolfPhase.start;
      _strokes = 0;
      _score = 0;
      _holeIndex = 0;
      _holes = const [];
      _last = Duration.zero;
    });
    _refreshHud();
  }

  void _tick(Duration elapsed) {
    if (_phase != _GolfPhase.play) return;
    if (_boardW == 0 || _groundY == 0) return;
    if (_ballStopped) {
      _last = elapsed;
      return;
    }
    var dt = _last == Duration.zero
        ? 0.0
        : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    // Clamp dt to a sane range — guards against huge jumps if the
    // ticker fires after a long pause.
    if (dt > 0.05) dt = 0.05;
    if (dt <= 0) return;

    setState(() {
      // Integrate position (semi-implicit Euler — more stable for
      // gravity than explicit Euler).
      _ball.vy += _gravity * dt;
      _ball.x += _ball.vx * dt;
      _ball.y += _ball.vy * dt;

      // Ground (putting green) collision — sit on the line, kill
      // vertical velocity, apply friction.
      if (_ball.y >= _groundY) {
        _ball.y = _groundY;
        _ball.vy = 0;
        // Exponential ground friction: slows the ball smoothly to
        // rest instead of slamming to a halt.
        final friction = exp(-_groundFrictionPerSec * dt);
        _ball.vx *= friction;
        if (_ball.vx.abs() < _restSpeed) {
          _ball.vx = 0;
        }
      }

      // Ceiling.
      if (_ball.y < 8) {
        _ball.y = 8;
        _ball.vy = -_ball.vy * 0.4;
      }

      // Side walls.
      if (_ball.x < 10) {
        _ball.x = 10;
        _ball.vx = -_ball.vx * 0.55;
      }
      if (_ball.x > _boardW - 10) {
        _ball.x = _boardW - 10;
        _ball.vx = -_ball.vx * 0.55;
      }

      // Stop at rest once the ball is on the green and barely moving.
      if (_ball.y >= _groundY - 0.5 &&
          _ball.vx.abs() < _restSpeed &&
          _ball.vy.abs() < _restSpeed) {
        _ball.x = _ball.x;
        _ball.y = _groundY;
        _ball.vx = 0;
        _ball.vy = 0;
        _ballStopped = true;
      }

      // Hole check.
      final hole = _holes[_holeIndex];
      final dx = _ball.x - hole.x;
      final dy = _ball.y - hole.y;
      if (dx * dx + dy * dy <= _holeCaptureRadius * _holeCaptureRadius) {
        _scoreHole();
      }
    });
  }

  void _scoreHole() {
    _bestStrokes = min(_bestStrokes, _strokes);
    haptic(HapticFeedbackType.heavy);
    _holeIndex++;
    if (_holeIndex >= _holeCount) {
      // Round over.
      _score = max(0, (_targetStrokes * 5) - _strokes * 3) * 20 + 100;
      reportGameOver();
      setState(() {
        _phase = _GolfPhase.win;
        _ballStopped = true;
      });
      return;
    }
    setState(() {
      _ball = _GolfBall(
        _holes[_holeIndex].x - 80,
        _groundY,
      );
      _ballStopped = true;
    });
    _refreshHud();
  }

  // ── Gesture handling ─────────────────────────────────────────────
  void _onPanStart(DragStartDetails d) {
    if (_phase != _GolfPhase.play) return;
    if (!_ballStopped) return;
    final ballCenter = Offset(_ball.x, _ball.y);
    if ((d.localPosition - ballCenter).distance > 60) return;
    setState(() {
      _aimStart = d.localPosition;
      _aimCurrent = d.localPosition;
      _isAiming = true;
    });
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (!_isAiming) return;
    setState(() {
      _aimCurrent = d.localPosition;
    });
  }

  void _onPanEnd(DragEndDetails d) {
    if (!_isAiming) return;
    final delta = _aimCurrent - _aimStart!;
    final dist = delta.distance;
    if (dist < 12) {
      setState(() {
        _isAiming = false;
      });
      return;
    }
    // The ball flies opposite the drag direction (slingshot).
    final dir = delta / dist;
    // Power ramps up with drag distance, capped at _maxLaunchSpeed.
    final power = (dist * 4.0).clamp(0.0, _maxLaunchSpeed);
    setState(() {
      _ball.vx = -dir.dx * power;
      // A small upward kick so the ball can fly over small bumps,
      // but mostly horizontal for putting.
      _ball.vy = -dir.dy * power * 0.55;
      _isAiming = false;
      _ballStopped = false;
      _strokes++;
      _last = Duration.zero;
    });
    haptic(HapticFeedbackType.medium);
    _refreshHud();
  }

  void _onContinueAfterWin() {
    setState(() {
      _phase = _GolfPhase.trophy;
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
                // Putting green sits at ~70% of board height — same
                // fraction the painter uses, but kept here so the
                // physics has a single source of truth.
                if (_groundY == 0) {
                  _groundY = _boardH * 0.7;
                }
                // Lazy-build holes / place the ball once we know
                // the real board size. Holes sit ON the green.
                if (_holes.isEmpty && _phase == _GolfPhase.play) {
                  _buildHoles();
                  if (_holes.isNotEmpty) {
                    _ball = _GolfBall(
                      _holes.first.x - 80,
                      _groundY,
                    );
                    _ballStopped = true;
                  }
                }
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: _onPanStart,
                  onPanUpdate: _onPanUpdate,
                  onPanEnd: _onPanEnd,
                  child: CustomPaint(
                    painter: _GolfPainter(
                      ball: _ball,
                      holes: _holes,
                      holeIndex: _holeIndex,
                      groundY: _groundY,
                      aimStart: _isAiming ? _aimStart : null,
                      aimCurrent: _isAiming ? _aimCurrent : null,
                    ),
                    size: Size(_boardW, _boardH),
                  ),
                );
              },
            ),
          ),
        ),
        if (_phase == _GolfPhase.start)
          GameStartOverlay(
            title: 'GOLF STAR',
            subtitle: 'Putt past the wind\nand into the hole!',
            youScore: 0,
            targetScore: _targetStrokes,
            instruction:
                'Drag back from the ball to aim, release to shoot. Sink the ball in 3 strokes or fewer to win.',
            illustration: const BoyCharacter(pose: BoyPose.cueStick),
            onPlay: _onPlay,
            onBack: () => Navigator.of(context).maybePop(),
          ),
        if (_phase == _GolfPhase.win)
          GameWinOverlay(
            title: 'YOU WIN!',
            subtitle: 'HOLE IN!',
            scoreValue: _score,
            scoreLabel: 'Round Score',
            statRows: [
              ('Strokes', '$_strokes'),
              ('Best', '$_bestStrokes'),
            ],
            onContinue: _onContinueAfterWin,
          ),
        if (_phase == _GolfPhase.trophy)
          GameTrophyOverlay(
            iconData: Icons.sports_golf_rounded,
            iconGradient: const [Color(0xFFFCD34D), Color(0xFFF59E0B)],
            title: _strokes <= _targetStrokes ? 'Great Job!' : 'Keep Going!',
            subtitle: _strokes <= _targetStrokes
                ? 'You beat par!'
                : 'Try again — fewer strokes next time!',
            score: _score,
            statRows: [
              ('Strokes', '$_strokes'),
              ('Best', '$_bestStrokes'),
              ('Target', '$_targetStrokes'),
            ],
            onPlayAgain: _onPlayAgain,
            onBack: () => Navigator.of(context).maybePop(),
          ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// Course painter
// ────────────────────────────────────────────────────────────────────

class _GolfPainter extends CustomPainter {
  _GolfPainter({
    required this.ball,
    required this.holes,
    required this.holeIndex,
    required this.groundY,
    required this.aimStart,
    required this.aimCurrent,
  });

  final _GolfBall ball;
  final List<_GolfHole> holes;
  final int holeIndex;
  final double groundY;
  final Offset? aimStart;
  final Offset? aimCurrent;

  static const _skyTop = Color(0xFF87CEEB);
  static const _skyBottom = Color(0xFFBFDBFE);
  static const _grass = Color(0xFF22C55E);
  static const _grassDark = Color(0xFF166534);
  static const _holeBlack = Color(0xFF111111);
  static const _flagRed = Color(0xFFEF4444);

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

    // Use the same ground Y as the physics — keeps the ball,
    // hole, and grass all aligned.
    final gy = groundY == 0 ? size.height * 0.7 : groundY;

    // Grass.
    canvas.drawRect(
      Rect.fromLTWH(0, gy, size.width, size.height - gy),
      Paint()..color = _grass,
    );
    // Grass top shading for depth.
    canvas.drawRect(
      Rect.fromLTWH(0, gy, size.width, 6),
      Paint()..color = _grassDark,
    );

    // Hole — only if we have one for this index.
    if (holeIndex >= 0 && holeIndex < holes.length) {
      final hole = holes[holeIndex];
      // Shadow under the cup.
      canvas.drawCircle(
        Offset(hole.x, gy + 2),
        12,
        Paint()..color = Colors.black.withValues(alpha: 0.35),
      );
      // The cup itself.
      canvas.drawCircle(Offset(hole.x, gy), 9, Paint()..color = _holeBlack);
      // Flag pole + flag.
      canvas.drawLine(
        Offset(hole.x, gy),
        Offset(hole.x, gy - 60),
        Paint()
          ..color = Colors.white
          ..strokeWidth = 2,
      );
      final flag = Path()
        ..moveTo(hole.x, gy - 60)
        ..lineTo(hole.x + 22, gy - 52)
        ..lineTo(hole.x, gy - 44)
        ..close();
      canvas.drawPath(flag, Paint()..color = _flagRed);
    }

    // Aim arrow — drawn from the ball opposite to the drag.
    if (aimStart != null && aimCurrent != null) {
      final delta = aimCurrent! - aimStart!;
      final dist = delta.distance;
      if (dist > 4) {
        final dir = -delta / dist;
        final power = (dist * 4.0).clamp(0.0, 720.0);
        // Visual length scales with launch power (px/s).
        final len = (power / 720.0 * 110 + 20).clamp(20.0, 130.0);
        final tip = Offset(ball.x + dir.dx * len, ball.y + dir.dy * len);
        final paint = Paint()
          ..color = Colors.white.withValues(alpha: 0.75)
          ..strokeWidth = 2;
        canvas.drawLine(Offset(ball.x, ball.y), tip, paint);
        // Arrowhead.
        final head = Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo(
            tip.dx - dir.dx * 8 + dir.dy * 4,
            tip.dy - dir.dy * 8 - dir.dx * 4,
          )
          ..lineTo(
            tip.dx - dir.dx * 8 - dir.dy * 4,
            tip.dy - dir.dy * 8 + dir.dx * 4,
          )
          ..close();
        canvas.drawPath(
          head,
          Paint()..color = Colors.white.withValues(alpha: 0.75),
        );
      }
    }

    // Ball.
    canvas.drawCircle(
      Offset(ball.x, ball.y + 2),
      8,
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );
    canvas.drawCircle(Offset(ball.x, ball.y), 8, Paint()..color = Colors.white);
    canvas.drawCircle(
      Offset(ball.x - 2, ball.y - 2),
      2,
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(_GolfPainter old) =>
      old.ball.x != ball.x ||
      old.ball.y != ball.y ||
      old.holeIndex != holeIndex ||
      old.groundY != groundY ||
      old.aimStart != aimStart ||
      old.aimCurrent != aimCurrent;
}
