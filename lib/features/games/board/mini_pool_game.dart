import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../game_widgets.dart';
import '../mini_game.dart';
import '../widgets/game_flow_overlays.dart';

/// Mini Pool — full 2D-physics pocket game with proper ball-ball
/// collisions, wall bounce, and pocket detection.
///
/// The cue ball is racked on the left, a triangle of object balls on
/// the right. The player drags back from the cue ball to aim and
/// release to shoot. The cue ball collides with object balls (with
/// elastic equal-mass velocity exchange), bounces off the rails, and
/// pockets fall into any of six pockets around the table.
///
/// Phases: `start → play → win → trophy`.
class MiniPoolGame extends MiniGame {
  const MiniPoolGame({super.key, required super.callbacks});

  @override
  State<MiniPoolGame> createState() => _MiniPoolGameState();
}

class _PoolBall {
  _PoolBall({
    this.x = 0,
    this.y = 0,
    required this.color,
    this.isCue = false,
    this.isEight = false,
  });

  double x;
  double y;
  double vx = 0;
  double vy = 0;
  Color color;
  bool isCue;
  bool isEight;
  bool pocketed = false;
}

enum _PoolPhase { start, play, win, trophy }

class _MiniPoolGameState extends MiniGameState<MiniPoolGame>
    with SingleTickerProviderStateMixin {
  // ─── Table geometry (logical units; scaled to canvas) ─────────────
  static const double _tableW = 700;
  static const double _tableH = 420;
  static const double _ballR = 9;
  static const double _friction = 0.992;
  static const double _minSpeed = 0.05;
  static const double _wallDamp = 0.85;
  static const double _ballRestitution = 0.96;
  static const double _pocketRadius = 16;

  static const int _targetWins = 5;
  static const int _maxShots = 7;

  late final Ticker _ticker;
  final List<_PoolBall> _balls = [];
  final List<Offset> _pockets = const [
    Offset(14, 14),
    Offset(_tableW / 2, 12),
    Offset(_tableW - 14, 14),
    Offset(14, _tableH - 14),
    Offset(_tableW / 2, _tableH - 12),
    Offset(_tableW - 14, _tableH - 14),
  ];

  bool _aiming = true;
  Offset _aimFrom = Offset.zero;
  Offset _aimTo = Offset.zero;
  double _power = 0.5;

  int _pocketed = 0;
  int _youWins = 0;
  int _score = 0;
  int _shotsTaken = 0;
  _PoolPhase _phase = _PoolPhase.start;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    _setupBalls();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        reportScore(_score);
        _publishStats();
      }
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _setupBalls() {
    _balls.clear();
    // Cue ball at the head spot (left side).
    _balls.add(_PoolBall(
      x: _tableW * 0.22,
      y: _tableH / 2,
      color: const Color(0xFFFFFFFF),
      isCue: true,
    ));

    // Triangle of 5 object balls (red+yellow) on the right, with the
    // 8-ball at the front of the rack.
    const apexX = _tableW * 0.68;
    const apexY = _tableH / 2;
    final dx = _ballR * 2.05;
    final dy = _ballR * 1.78;
    final colors = [
      const Color(0xFF111111), // 8-ball (front apex)
      const Color(0xFFFBC02D), // 1 yellow
      const Color(0xFFD32F2F), // 3 red
      const Color(0xFF1976D2), // 2 blue
      const Color(0xFF7B1FA2), // 4 purple
      const Color(0xFFEF6C00), // 5 orange
    ];
    void place(int row, int col, _PoolBall b) {
      final xOffset = (row * dx);
      final yOffset = (col - row / 2.0) * dy * 2;
      b.x = apexX + xOffset;
      b.y = apexY + yOffset;
      _balls.add(b);
    }

    // Row 0: 8-ball (apex).
    place(0, 0, _PoolBall(
          color: const Color(0xFF111111),
          isEight: true,
        ));
    // Row 1: 2 balls.
    place(1, 0, _PoolBall(color: colors[1]));
    place(1, 1, _PoolBall(color: colors[2]));
    // Row 2: 3 balls.
    place(2, 0, _PoolBall(color: colors[3]));
    place(2, 1, _PoolBall(color: colors[4]));
    place(2, 2, _PoolBall(color: colors[5]));

    _pocketed = 0;
    _shotsTaken = 0;
    _aiming = true;
    _power = 0.5;
    _refreshStatus();
  }

  void _refreshStatus() {
    final ballsLeft = _balls.where((b) => !b.pocketed && !b.isCue).length;
    final stats =
        'You $_youWins  •  Balls Left $ballsLeft';
    if (stats != _lastStats) {
      _lastStats = stats;
      reportStats(stats);
    }
  }

  String _lastStats = '';

  void _publishStats() {
    _refreshStatus();
  }

  // ─── Physics + collision ──────────────────────────────────────────

  void _onTick(Duration elapsed) {
    if (_phase != _PoolPhase.play) return;
    setState(() {
      _stepPhysics();
      _checkPockets();
      final anyMoving = _balls.any((b) =>
          !b.pocketed &&
          (b.vx.abs() > _minSpeed || b.vy.abs() > _minSpeed));
      if (!anyMoving && !_aiming) {
        _aiming = true;
        // After each shot, check win/loss.
        _checkRoundEnd();
      }
      _publishStats();
    });
  }

  void _stepPhysics() {
    const dt = 1 / 60.0;
    for (final b in _balls) {
      if (b.pocketed) continue;
      b.x += b.vx * dt;
      b.y += b.vy * dt;
      b.vx *= _friction;
      b.vy *= _friction;
      // Walls.
      if (b.x < _ballR) {
        b.x = _ballR;
        b.vx = -b.vx * _wallDamp;
      }
      if (b.x > _tableW - _ballR) {
        b.x = _tableW - _ballR;
        b.vx = -b.vx * _wallDamp;
      }
      if (b.y < _ballR) {
        b.y = _ballR;
        b.vy = -b.vy * _wallDamp;
      }
      if (b.y > _tableH - _ballR) {
        b.y = _tableH - _ballR;
        b.vy = -b.vy * _wallDamp;
      }
      // Snap to rest.
      if (b.vx.abs() < _minSpeed && b.vy.abs() < _minSpeed) {
        b.vx = 0;
        b.vy = 0;
      }
    }
    // Ball-ball elastic collisions (equal mass swap on the contact
    // normal — the standard pool-ball approximation).
    for (var i = 0; i < _balls.length; i++) {
      for (var j = i + 1; j < _balls.length; j++) {
        final a = _balls[i];
        final b = _balls[j];
        if (a.pocketed || b.pocketed) continue;
        final dx = b.x - a.x;
        final dy = b.y - a.y;
        final dist2 = dx * dx + dy * dy;
        final minDist = _ballR * 2;
        if (dist2 < minDist * minDist && dist2 > 0.0001) {
          final dist = sqrt(dist2);
          final nx = dx / dist;
          final ny = dy / dist;
          // Position correction (separate overlapping balls).
          final overlap = minDist - dist;
          a.x -= nx * overlap * 0.5;
          a.y -= ny * overlap * 0.5;
          b.x += nx * overlap * 0.5;
          b.y += ny * overlap * 0.5;
          // Velocity exchange along the contact normal.
          final va = a.vx * nx + a.vy * ny;
          final vb = b.vx * nx + b.vy * ny;
          final diff = va - vb;
          if (diff > 0) {
            a.vx -= diff * nx * _ballRestitution;
            a.vy -= diff * ny * _ballRestitution;
            b.vx += diff * nx * _ballRestitution;
            b.vy += diff * ny * _ballRestitution;
            haptic(HapticFeedbackType.light);
          }
        }
      }
    }
  }

  bool _ballInPocket(_PoolBall b) {
    for (final p in _pockets) {
      final dx = b.x - p.dx;
      final dy = b.y - p.dy;
      if (dx * dx + dy * dy < _pocketRadius * _pocketRadius) return true;
    }
    return false;
  }

  void _checkPockets() {
    for (final b in _balls) {
      if (b.pocketed) continue;
      if (_ballInPocket(b)) {
        b.pocketed = true;
        b.vx = 0;
        b.vy = 0;
        haptic(HapticFeedbackType.medium);
        if (b.isCue) {
          // Scratch — spot back at head.
          b.x = _tableW * 0.22;
          b.y = _tableH / 2;
          b.pocketed = false;
          continue;
        }
        _pocketed++;
        if (b.isEight) {
          _youWins++;
          _score = _youWins * 50;
        }
      }
    }
  }

  void _checkRoundEnd() {
    // Win: pocket the 8-ball → YOU WIN.
    final eight = _balls.firstWhere(
      (b) => b.isEight,
      orElse: () => _PoolBall(x: 0, y: 0, color: const Color(0xFF000000)),
    );
    if (eight.pocketed) {
      reportScore(_score);
      reportGameOver();
      _phase = _PoolPhase.win;
      return;
    }
    // Out of shots → trophy.
    if (_shotsTaken >= _maxShots) {
      _score = _youWins * 50;
      reportScore(_score);
      reportGameOver();
      _phase = _PoolPhase.trophy;
      return;
    }
  }

  // ─── Input ───────────────────────────────────────────────────────

  void _onDragStart(DragStartDetails d, _PoolBall cue, double scale) {
    if (!_aiming || _phase != _PoolPhase.play) return;
    if (cue.pocketed) return;
    _aimFrom = Offset(cue.x * scale, cue.y * scale);
    _aimTo = d.localPosition;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (!_aiming) return;
    _aimTo = d.localPosition;
    final dx = _aimTo.dx - _aimFrom.dx;
    final dy = _aimTo.dy - _aimFrom.dy;
    final mag = sqrt(dx * dx + dy * dy);
    _power = (mag / 110).clamp(0.15, 1.0);
    setState(() {});
  }

  void _onDragEnd(DragEndDetails d, _PoolBall cue, double scale) {
    if (!_aiming || _phase != _PoolPhase.play) return;
    if (cue.pocketed) return;
    final dx = _aimTo.dx - _aimFrom.dx;
    final dy = _aimTo.dy - _aimFrom.dy;
    final mag = sqrt(dx * dx + dy * dy);
    if (mag < 14) return;
    final speed = 360 * _power;
    // Cue ball travels opposite of the pull-back direction (slingshot).
    cue.vx = -(dx / mag) * speed / scale;
    cue.vy = -(dy / mag) * speed / scale;
    _shotsTaken++;
    _aiming = false;
    haptic(HapticFeedbackType.medium);
  }

  _PoolBall _cueOrNull() {
    for (final b in _balls) {
      if (b.isCue && !b.pocketed) return b;
    }
    return _balls.firstWhere((b) => b.isCue);
  }

  // ─── Game flow ──────────────────────────────────────────────────

  void _onPlay() {
    setState(() {
      _phase = _PoolPhase.play;
      _setupBalls();
      _youWins = 0;
      _score = 0;
    });
    reportScore(_score);
    _publishStats();
  }

  void _onContinueAfterWin() {
    if (_youWins >= _targetWins) {
      setState(() {
        _phase = _PoolPhase.trophy;
      });
    } else {
      setState(() {
        _setupBalls();
        _phase = _PoolPhase.play;
      });
      reportScore(_score);
      _publishStats();
    }
  }

  void _onPlayAgain() {
    setState(() {
      _phase = _PoolPhase.start;
      _score = 0;
      _youWins = 0;
      _setupBalls();
    });
    reportScore(_score);
    _publishStats();
  }

  double _fitScale(double maxW, double maxH) {
    if (maxW <= 0 || maxH <= 0) return 1;
    return (maxW / _tableW).clamp(0.0, maxH / _tableH);
  }

  // ─── Build ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: LayoutBuilder(builder: (ctx, c) {
              final scale = _fitScale(c.maxWidth, c.maxHeight);
              final w = _tableW * scale;
              final h = _tableH * scale;
              return Center(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (d) =>
                      _onDragStart(d, _cueOrNull(), scale),
                  onPanUpdate: _onDragUpdate,
                  onPanEnd: (d) =>
                      _onDragEnd(d, _cueOrNull(), scale),
                  child: SizedBox(
                    width: w,
                    height: h,
                    child: CustomPaint(
                      painter: _MiniPoolPainter(
                        balls: _balls,
                        pockets: _pockets,
                        aimFrom: _aimFrom,
                        aimTo: _aimTo,
                        aiming: _aiming && _phase == _PoolPhase.play,
                        power: _power,
                        scale: scale,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        if (_phase == _PoolPhase.start)
          GameStartOverlay(
            title: 'MINI POOL',
            subtitle: 'Pocket the 8 ball\nto win 5 games!',
            youScore: _youWins,
            targetScore: _targetWins,
            instruction:
                'Drag back from the cue ball to aim, release to shoot. Balls bounce off the rails and each other — sink the 8 ball to win.',
            illustration: const BoyCharacter(pose: BoyPose.cueStick),
            onPlay: _onPlay,
            onBack: () => Navigator.of(context).maybePop(),
          ),
        if (_phase == _PoolPhase.win)
          GameWinOverlay(
            title: 'YOU WIN!',
            subtitle: '8 BALL SANK!',
            scoreValue: _score,
            scoreLabel: 'Wins',
            statRows: [
              ('Pocketed', '$_pocketed'),
              ('Shots', '$_shotsTaken'),
            ],
            onContinue: _onContinueAfterWin,
          ),
        if (_phase == _PoolPhase.trophy)
          GameTrophyOverlay(
            iconData: Icons.emoji_events_rounded,
            iconGradient: const [Color(0xFFFCD34D), Color(0xFFF59E0B)],
            title: _youWins >= _targetWins ? 'Champion!' : 'Great Job!',
            subtitle: _youWins >= _targetWins
                ? 'You sank the 8-ball $_youWins times!'
                : 'You won $_youWins of $_targetWins — try again!',
            score: _youWins * 50,
            statRows: [
              ('Wins', '$_youWins'),
              ('Pocketed', '$_pocketed'),
              ('Target', '$_targetWins'),
            ],
            onPlayAgain: _onPlayAgain,
            onBack: () => Navigator.of(context).maybePop(),
          ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// Painter
// ────────────────────────────────────────────────────────────────────

class _MiniPoolPainter extends CustomPainter {
  _MiniPoolPainter({
    required this.balls,
    required this.pockets,
    required this.aimFrom,
    required this.aimTo,
    required this.aiming,
    required this.power,
    required this.scale,
  });

  final List<_PoolBall> balls;
  final List<Offset> pockets;
  final Offset aimFrom;
  final Offset aimTo;
  final bool aiming;
  final double power;
  final double scale;

  static const _rail = Color(0xFF6B4226);
  static const _railLight = Color(0xFF8B5A2B);
  static const _felt = Color(0xFF15803D);
  static const _feltDark = Color(0xFF166534);

  @override
  void paint(Canvas canvas, Size size) {
    final feltRect = Rect.fromLTWH(0, 0, size.width, size.height);

    // Wooden rail.
    final railInset = size.width * 0.03;
    canvas.drawRRect(
      RRect.fromRectAndRadius(feltRect, Radius.circular(railInset)),
      Paint()..color = _rail,
    );
    final innerRail = feltRect.deflate(railInset * 0.5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(innerRail, Radius.circular(railInset * 0.6)),
      Paint()..color = _railLight,
    );

    // Felt.
    final feltInset = railInset + size.width * 0.02;
    final innerFelt = feltRect.deflate(feltInset);
    canvas.drawRRect(
      RRect.fromRectAndRadius(innerFelt, Radius.circular(8)),
      Paint()..color = _felt,
    );
    // Vignette.
    canvas.drawRRect(
      RRect.fromRectAndRadius(innerFelt, const Radius.circular(8)),
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.transparent,
            _feltDark.withValues(alpha: 0.35),
          ],
        ).createShader(innerFelt),
    );
    // Centre line.
    canvas.drawLine(
      Offset(innerFelt.center.dx, innerFelt.top + 4),
      Offset(innerFelt.center.dx, innerFelt.bottom - 4),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.18)
        ..strokeWidth = 1,
    );

    // Pockets.
    final pocketR = _MiniPoolGameState._pocketRadius * scale;
    for (final p in pockets) {
      canvas.drawCircle(
        Offset(p.dx * scale, p.dy * scale),
        pocketR * 1.3,
        Paint()..color = Colors.black,
      );
      canvas.drawCircle(
        Offset(p.dx * scale, p.dy * scale),
        pocketR * 0.85,
        Paint()..color = const Color(0xFF111111),
      );
    }

    // Aim line.
    if (aiming) {
      _PoolBall? cue;
      for (final b in balls) {
        if (b.isCue && !b.pocketed) {
          cue = b;
          break;
        }
      }
      if (cue != null) {
        final cx = cue.x * scale;
        final cy = cue.y * scale;
        final dx = aimFrom.dx - aimTo.dx;
        final dy = aimFrom.dy - aimTo.dy;
        final mag = sqrt(dx * dx + dy * dy);
        if (mag > 6) {
          final ux = dx / mag;
          final uy = dy / mag;
          // Pull-back stick.
          canvas.drawLine(
            Offset(cx, cy),
            Offset(cx + ux * 40, cy + uy * 40),
            Paint()
              ..color = const Color(0xFFFACC15)
              ..strokeWidth = 3
              ..strokeCap = StrokeCap.round,
          );
          // Forward aim line.
          final len = 60 + 180 * power;
          canvas.drawLine(
            Offset(cx, cy),
            Offset(cx - ux * len, cy - uy * len),
            Paint()
              ..color = Colors.white.withValues(alpha: 0.6)
              ..strokeWidth = 2
              ..strokeCap = StrokeCap.round,
          );
        }
      }
    }

    // Balls.
    final r = _MiniPoolGameState._ballR * scale;
    for (final b in balls) {
      if (b.pocketed) continue;
      final cx = b.x * scale;
      final cy = b.y * scale;
      // Shadow.
      canvas.drawCircle(
        Offset(cx + 1, cy + 2),
        r,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
      );
      // Body.
      canvas.drawCircle(Offset(cx, cy), r, Paint()..color = b.color);
      // 8-ball marker.
      if (b.isEight) {
        canvas.drawCircle(Offset(cx, cy), r * 0.55, Paint()..color = Colors.white);
        canvas.drawCircle(
          Offset(cx, cy),
          r * 0.22,
          Paint()..color = const Color(0xFF111111),
        );
      }
      // Cue ball highlight.
      if (b.isCue) {
        canvas.drawCircle(
          Offset(cx - r * 0.35, cy - r * 0.35),
          r * 0.25,
          Paint()..color = Colors.white.withValues(alpha: 0.85),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MiniPoolPainter old) {
    if (aiming != old.aiming) return true;
    if (power != old.power) return true;
    if (aimFrom != old.aimFrom || aimTo != old.aimTo) return true;
    if (balls.length != old.balls.length) return true;
    for (var i = 0; i < balls.length; i++) {
      final a = balls[i];
      final b = old.balls[i];
      if (a.x != b.x || a.y != b.y ||
          a.pocketed != b.pocketed ||
          a.vx != b.vx || a.vy != b.vy) {
        return true;
      }
    }
    return false;
  }
}
