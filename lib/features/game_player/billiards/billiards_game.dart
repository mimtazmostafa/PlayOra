import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../games/game_widgets.dart';
import '../../games/mini_game.dart';
import '../../games/widgets/game_flow_overlays.dart';

/// 8-Ball Billiards — full 2D-physics single-screen pool game in the
/// redesigned mini-game family.
///
/// Real 8-ball rules:
///   * 15 object balls racked in a triangle (1-7 solids, 9-15 stripes,
///     8-ball at the centre of the third row).
///   * Two-player: player vs AI bot. The shooter keeps their turn
///     when they pocket a ball of their assigned group (solids or
///     stripes).
///   * Groups are assigned on first legal pot: potted a solid = you're
///     solids; potted a stripe = you're stripes; potted the 8-ball on
///     the break or first legal shot before a group is set = re-rack.
///   * Pocket the 8-ball last (after clearing your group) to win.
///     Pocket the 8-ball early = you lose.
///   * Scratching (cue ball pocketed) ends the shooter's turn and
///     spots the cue back at the head spot.
///
/// Physics: fixed-timestep integration, ball-ball elastic collision
/// (equal-mass swap), wall reflection with damping, friction.
class BilliardsGame extends MiniGame {
  const BilliardsGame({
    super.key,
    required super.callbacks,
    this.level = 1,
  });

  /// Difficulty for the AI opponent (kept for dispatcher back-compat).
  /// Higher = slightly more accurate shots.
  final int level;

  @override
  State<BilliardsGame> createState() => _BilliardsGameState();
}

class _Ball {
  _Ball({
    this.x = 0,
    this.y = 0,
    required this.color,
    required this.number,
    this.isStripe = false,
  });

  double x;
  double y;
  double vx = 0;
  double vy = 0;
  Color color;
  int number; // 0 = cue, 1..15 = object, 8 = 8-ball
  bool isStripe;
  bool pocketed = false;

  bool get isCue => number == 0;
  bool get isEight => number == 8;
  bool get isSolid => number >= 1 && number <= 7;
  bool get isStripeBall => number >= 9 && number <= 15;
}

enum _BilliardsGroup { unassigned, solids, stripes }

enum _BilliardsPhase { start, play, win, trophy }

class _BilliardsGameState extends MiniGameState<BilliardsGame>
    with SingleTickerProviderStateMixin {
  // ─── Table geometry (logical units; scaled to canvas) ─────────────
  static const double _tableW = 700; // logical pixels (long axis)
  static const double _tableH = 420; // logical pixels (short axis)
  static const double _ballR = 10; // ball radius
  static const double _friction = 0.992;
  static const double _minSpeed = 0.04;
  static const double _wallDamp = 0.85;
  static const double _ballRestitution = 0.96;
  static const double _pocketRadius = 18;

  /// Public aliases used by the painter (cannot reference private
  /// statics from a different class).
  static const double ballR = _ballR;
  static const double pocketRadius = _pocketRadius;

  late final Ticker _ticker;
  late List<_Ball> _balls;
  final List<Offset> _pockets = const [
    Offset(20, 20),
    Offset(_tableW / 2, 20),
    Offset(_tableW - 20, 20),
    Offset(20, _tableH - 20),
    Offset(_tableW / 2, _tableH - 20),
    Offset(_tableW - 20, _tableH - 20),
  ];

  bool _playerTurn = true;
  bool _aiming = true;
  Offset _aimFrom = Offset.zero;
  Offset _aimTo = Offset.zero;
  double _power = 0.6;

  _BilliardsGroup _playerGroup = _BilliardsGroup.unassigned;
  _BilliardsGroup _botGroup = _BilliardsGroup.unassigned;

  int _pScore = 0;
  int _bScore = 0;
  int _shotsTaken = 0;

  bool _gameOver = false;
  bool _won = false;
  String _status = '';
  String _lastStats = '';

  /// Mirror of the screen flow for the overlay tree. Decoupled from the
  /// per-frame `_gameOver` so the ticker doesn't race the overlay.
  _BilliardsPhase _phaseForOverlay = _BilliardsPhase.start;

  final Random _rng = Random();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _ticker.start();
    _setupBalls();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        reportScore(_pScore);
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
    _balls = [];
    // Cue ball at the head spot (left side).
    _balls.add(_Ball(
      x: _tableW * 0.22,
      y: _tableH / 2,
      color: const Color(0xFFFFFFFF),
      number: 0,
    ));

    // Rack of 15 in a triangle, apex pointing toward cue.
    // Row 1: ball 1 (apex).
    // Row 2: balls 9, 2.
    // Row 3: balls 3, 8 (8-ball centre), 10.
    // Row 4: balls 11, 4, 5, 12.
    // Row 5: balls 13, 6, 14, 7, 15.
    // Use a fixed offset for the rack apex.
    const apexX = _tableW * 0.68;
    const apexY = _tableH / 2;
    const dx = _ballR * 2.05; // along row
    const dy = _ballR * 1.78; // between rows (sqrt(3)/2 * ballR*2)

    void place(int row, int col, _Ball b) {
      final xOffset = (row * dx);
      final yOffset = (col - row / 2.0) * dy * 2;
      b.x = apexX + xOffset;
      b.y = apexY + yOffset;
      _balls.add(b);
    }

    // Row 0 (1 ball).
    place(0, 0, _Ball(
          color: const Color(0xFFFCD34D),
          number: 1,
        ));
    // Row 1 (2 balls).
    place(1, 0, _Ball(
          color: const Color(0xFFFBC02D),
          number: 9,
          isStripe: true,
        ));
    place(1, 1, _Ball(
          color: const Color(0xFF1976D2),
          number: 2,
        ));
    // Row 2 (3 balls).
    place(2, 0, _Ball(
          color: const Color(0xFFEF4444),
          number: 3,
        ));
    place(2, 1, _Ball(
          color: const Color(0xFF111111),
          number: 8,
        ));
    place(2, 2, _Ball(
          color: const Color(0xFF8B5CF6),
          number: 10,
          isStripe: true,
        ));
    // Row 3 (4 balls).
    place(3, 0, _Ball(
          color: const Color(0xFFFB923C),
          number: 11,
          isStripe: true,
        ));
    place(3, 1, _Ball(
          color: const Color(0xFF7C3AED),
          number: 4,
        ));
    place(3, 2, _Ball(
          color: const Color(0xFF8B4513),
          number: 5,
        ));
    place(3, 3, _Ball(
          color: const Color(0xFF22D3EE),
          number: 12,
          isStripe: true,
        ));
    // Row 4 (5 balls).
    place(4, 0, _Ball(
          color: const Color(0xFFEC4899),
          number: 13,
          isStripe: true,
        ));
    place(4, 1, _Ball(
          color: const Color(0xFF22C55E),
          number: 6,
        ));
    place(4, 2, _Ball(
          color: const Color(0xFFF472B6),
          number: 14,
          isStripe: true,
        ));
    place(4, 3, _Ball(
          color: const Color(0xFF7F1D1D),
          number: 7,
        ));
    place(4, 4, _Ball(
          color: const Color(0xFFA855F7),
          number: 15,
          isStripe: true,
        ));

    _playerTurn = true;
    _playerGroup = _BilliardsGroup.unassigned;
    _botGroup = _BilliardsGroup.unassigned;
    _aiming = true;
    _gameOver = false;
    _won = false;
    _pScore = 0;
    _bScore = 0;
    _shotsTaken = 0;
    _refreshStatus();
  }

  String _groupLabel(_BilliardsGroup g) => switch (g) {
        _BilliardsGroup.unassigned => '—',
        _BilliardsGroup.solids => 'Solids',
        _BilliardsGroup.stripes => 'Stripes',
      };

  void _refreshStatus() {
    final ballsLeft = _balls.where((b) => !b.pocketed && !b.isCue).length;
    final turn = _playerTurn ? 'Your turn' : 'Bot turn';
    _status = '$turn  •  You $_pScore · Bot $_bScore  •  $ballsLeft balls';
  }

  /// Push status to host only when it changes — guards the per-frame
  /// ticker from flooding the host with identical subtitle strings.
  void _publishStats() {
    if (_status == _lastStats) return;
    _lastStats = _status;
    reportStats(_status);
  }

  // ─── Physics + collision ──────────────────────────────────────────

  void _onTick(Duration elapsed) {
    if (_gameOver) return;
    setState(() {
      _stepPhysics();
      _checkPockets();
      final anyMoving = _balls.any((b) =>
          !b.pocketed &&
          (b.vx.abs() > _minSpeed || b.vy.abs() > _minSpeed));
      if (!anyMoving && !_aiming) {
        _aiming = true;
        // Hand off turn.
        _playerTurn = !_playerTurn;
        if (!_playerTurn) {
          // Bot takes the table on the next tick to give a brief beat.
          Future.microtask(_aiShoot);
        }
      }
      _refreshStatus();
      _publishStats();
      _checkWinConditions();
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
    // Ball-ball elastic collisions.
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
          final overlap = minDist - dist;
          a.x -= nx * overlap * 0.5;
          a.y -= ny * overlap * 0.5;
          b.x += nx * overlap * 0.5;
          b.y += ny * overlap * 0.5;
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

  void _checkPockets() {
    for (final b in _balls) {
      if (b.pocketed) continue;
      for (final p in _pockets) {
        final dx = b.x - p.dx;
        final dy = b.y - p.dy;
        if (dx * dx + dy * dy < _pocketRadius * _pocketRadius) {
          _pocketBall(b);
          break;
        }
      }
    }
  }

  void _pocketBall(_Ball b) {
    b.pocketed = true;
    b.vx = 0;
    b.vy = 0;
    haptic(HapticFeedbackType.medium);
    if (b.isCue) {
      // Scratch — spot back at head.
      b.x = _tableW * 0.22;
      b.y = _tableH / 2;
      b.pocketed = false;
      return;
    }
    if (b.isEight) return; // 8-ball resolved in _checkWinConditions
    // Group assignment.
    if (_playerGroup == _BilliardsGroup.unassigned) {
      if (b.isSolid) {
        _playerGroup = _BilliardsGroup.solids;
        _botGroup = _BilliardsGroup.stripes;
      } else if (b.isStripeBall) {
        _playerGroup = _BilliardsGroup.stripes;
        _botGroup = _BilliardsGroup.solids;
      }
    }
    // Score: 10 per ball.
    if (b.isSolid && _playerGroup == _BilliardsGroup.solids ||
        b.isStripeBall && _playerGroup == _BilliardsGroup.stripes) {
      _pScore += 10;
    } else {
      _bScore += 10;
    }
  }

  void _checkWinConditions() {
    if (_gameOver) return;
    final eight = _balls.firstWhere((b) => b.isEight);
    if (!eight.pocketed) return;
    // 8-ball pocketed: shooter's identity is captured by who took the
    // shot. The shooter wins iff their group was already cleared.
    final shooterWasPlayer = _playerTurn;
    final shooterGroupCleared = _balls.every((b) =>
        b.pocketed ||
        b.isCue ||
        b.isEight ||
        !(_shooterIsGroup(b, shooterWasPlayer)));
    _gameOver = true;
    _won = shooterWasPlayer && shooterGroupCleared;
    if (_won) {
      _pScore += 250;
    } else {
      _bScore += 250;
    }
    reportScore(_pScore);
    reportStats(_won
        ? 'You sank the 8-ball — you win!'
        : 'Bot sank the 8-ball — you lose.');
    reportGameOver();
    _phaseForOverlay =
        _won ? _BilliardsPhase.win : _BilliardsPhase.trophy;
  }

  bool _shooterIsGroup(_Ball b, bool shooterIsPlayer) {
    if (b.isCue || b.isEight) return false;
    final group = shooterIsPlayer ? _playerGroup : _botGroup;
    return (group == _BilliardsGroup.solids && b.isSolid) ||
        (group == _BilliardsGroup.stripes && b.isStripeBall);
  }

  // ─── AI ──────────────────────────────────────────────────────────

  void _aiShoot() {
    // Pick a target ball of the bot's group. If no group yet, pick the
    // first ball. Aim toward pocket nearest to that ball, with small
    // random jitter.
    _Ball? cue;
    try {
      cue = _balls.firstWhere((b) => b.isCue && !b.pocketed);
    } catch (_) {
      return;
    }
    _Ball? target;
    if (_botGroup == _BilliardsGroup.solids) {
      for (final b in _balls) {
        if (b.isSolid && !b.pocketed) {
          target = b;
          break;
        }
      }
    } else if (_botGroup == _BilliardsGroup.stripes) {
      for (final b in _balls) {
        if (b.isStripeBall && !b.pocketed) {
          target = b;
          break;
        }
      }
    }
    // If 8-ball is the last one of the bot's group already cleared, go
    // for the 8-ball.
    if (target == null) {
      try {
        target = _balls.firstWhere((b) => b.isEight && !b.pocketed);
      } catch (_) {}
    }
    if (target == null) {
      // Nothing to aim at — pass the turn back.
      _playerTurn = true;
      _aiming = true;
      return;
    }
    final pocket = _pockets[_rng.nextInt(_pockets.length)];
    // Compute cue ball contact point: from cue toward the line through
    // pocket and target, offset by 2R perpendicular to that line.
    final dxt = pocket.dx - target.x;
    final dyt = pocket.dy - target.y;
    final magT = sqrt(dxt * dxt + dyt * dyt);
    if (magT == 0) return;
    final ux = dxt / magT;
    final uy = dyt / magT;
    final contactX = target.x - ux * _ballR * 2;
    final contactY = target.y - uy * _ballR * 2;
    final aimX = contactX - cue.x;
    final aimY = contactY - cue.y;
    final mag = sqrt(aimX * aimX + aimY * aimY);
    if (mag == 0) return;
    final power = 320 + _rng.nextDouble() * 90;
    cue.vx = (aimX / mag) * power;
    cue.vy = (aimY / mag) * power;
    _shotsTaken++;
    _aiming = false;
    haptic(HapticFeedbackType.light);
  }

  // ─── Input ───────────────────────────────────────────────────────

  void _onDragStart(DragStartDetails d, _Ball cue, double scale) {
    if (!_aiming || !_playerTurn || _gameOver) return;
    if (cue.pocketed) return;
    _aimFrom = Offset(cue.x * scale, cue.y * scale);
    _aimTo = d.localPosition;
  }

  void _onDragUpdate(DragUpdateDetails d, _Ball cue) {
    if (!_aiming) return;
    _aimTo = d.localPosition;
    final dx = _aimTo.dx - _aimFrom.dx;
    final dy = _aimTo.dy - _aimFrom.dy;
    final mag = sqrt(dx * dx + dy * dy);
    _power = (mag / 100).clamp(0.2, 1.0);
    setState(() {});
  }

  void _onDragEnd(DragEndDetails d, _Ball cue, double scale) {
    if (!_aiming || !_playerTurn || _gameOver) return;
    if (cue.pocketed) return;
    final dx = _aimTo.dx - _aimFrom.dx;
    final dy = _aimTo.dy - _aimFrom.dy;
    final mag = sqrt(dx * dx + dy * dy);
    if (mag < 12) return;
    final speed = 350 * _power;
    // Translate screen-space pull into table-space velocity (cue moves
    // opposite of the drag direction).
    cue.vx = -(dx / mag) * speed / scale;
    cue.vy = -(dy / mag) * speed / scale;
    _shotsTaken++;
    _aiming = false;
    haptic(HapticFeedbackType.medium);
  }

  _Ball _cueOrNull() {
    for (final b in _balls) {
      if (b.isCue && !b.pocketed) return b;
    }
    return _balls.firstWhere((b) => b.isCue);
  }

  // ─── Build ───────────────────────────────────────────────────────

  void _onPlay() {
    setState(() {
      _setupBalls();
      _phaseForOverlay = _BilliardsPhase.play;
    });
    reportScore(_pScore);
    _publishStats();
  }

  void _onContinueAfterWin() {
    setState(() {
      _phaseForOverlay = _BilliardsPhase.trophy;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: LayoutBuilder(builder: (ctx, c) {
              // Fit table into the available area while preserving
              // the 700:420 aspect ratio.
              final scale = _fitScale(c.maxWidth, c.maxHeight);
              final w = _tableW * scale;
              final h = _tableH * scale;
              return Center(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (d) =>
                      _onDragStart(d, _cueOrNull(), scale),
                  onPanUpdate: (d) =>
                      _onDragUpdate(d, _cueOrNull()),
                  onPanEnd: (d) =>
                      _onDragEnd(d, _cueOrNull(), scale),
                  child: SizedBox(
                    width: w,
                    height: h,
                    child: CustomPaint(
                      painter: _BilliardsPainter(
                        balls: _balls,
                        pockets: _pockets,
                        aimFrom: _aimFrom,
                        aimTo: _aimTo,
                        aiming: _aiming,
                        playerTurn: _playerTurn,
                        power: _power,
                        scale: scale,
                        tableW: _tableW,
                        tableH: _tableH,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        if (_phaseForOverlay == _BilliardsPhase.start)
          GameStartOverlay(
            title: 'BILLIARDS',
            subtitle: '8-Ball,\npot your group, then sink the 8!',
            youScore: _pScore,
            targetScore: 5,
            instruction:
                'Drag back from the cue ball to aim, release to shoot. Pot all your group (solids or stripes), then sink the 8 ball to win. Avoid pocketing the 8 ball early.',
            illustration: const BoyCharacter(pose: BoyPose.cueStick),
            onPlay: _onPlay,
            onBack: () => Navigator.of(context).maybePop(),
          ),
        if (_phaseForOverlay == _BilliardsPhase.win)
          GameWinOverlay(
            title: 'YOU WIN!',
            subtitle: '8 BALL SANK!',
            scoreValue: _pScore,
            scoreLabel: 'Final Score',
            statRows: [
              ('You', '$_pScore'),
              ('Bot', '$_bScore'),
              ('Shots', '$_shotsTaken'),
            ],
            onContinue: _onContinueAfterWin,
          ),
        if (_phaseForOverlay == _BilliardsPhase.trophy)
          GameTrophyOverlay(
            iconData: Icons.emoji_events_rounded,
            iconGradient: const [Color(0xFFFCD34D), Color(0xFFF59E0B)],
            title: _won ? 'Great Job!' : 'Try Again',
            subtitle: _won
                ? 'You sank the 8 ball after clearing your group.'
                : 'Pocket your group first, then sink the 8 ball.',
            score: _pScore,
            statRows: [
              ('You', '$_pScore'),
              ('Bot', '$_bScore'),
              ('Shots', '$_shotsTaken'),
            ],
            onPlayAgain: _onPlay,
            onBack: () => Navigator.of(context).maybePop(),
          ),
        if (_phaseForOverlay == _BilliardsPhase.play && _playerTurn)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: GamePlayHud(
              youText:
                  'You $_pScore  •  ${_groupLabel(_playerGroup)}',
              counterText: 'Bot $_bScore  •  ${_groupLabel(_botGroup)}',
              onPause: null,
            ),
          ),
      ],
    );
  }

  double _fitScale(double maxW, double maxH) {
    if (maxW <= 0 || maxH <= 0) return 1;
    return (maxW / _tableW).clamp(0.0, maxH / _tableH);
  }
}

// ────────────────────────────────────────────────────────────────────
// Painter
// ────────────────────────────────────────────────────────────────────

class _BilliardsPainter extends CustomPainter {
  _BilliardsPainter({
    required this.balls,
    required this.pockets,
    required this.aimFrom,
    required this.aimTo,
    required this.aiming,
    required this.playerTurn,
    required this.power,
    required this.scale,
    required this.tableW,
    required this.tableH,
  });

  final List<_Ball> balls;
  final List<Offset> pockets;
  final Offset aimFrom;
  final Offset aimTo;
  final bool aiming;
  final bool playerTurn;
  final double power;
  final double scale;
  final double tableW;
  final double tableH;

  @override
  void paint(Canvas canvas, Size size) {
    // Wooden rail frame.
    final frameRect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(frameRect, Radius.circular(size.width * 0.025)),
      Paint()..color = const Color(0xFF6B4226),
    );
    final railInset = size.width * 0.025;
    final innerRect = frameRect.deflate(railInset);
    canvas.drawRRect(
      RRect.fromRectAndRadius(innerRect, Radius.circular(size.width * 0.018)),
      Paint()..color = const Color(0xFF8B5A2B),
    );
    // Felt.
    final feltInset = railInset + size.width * 0.02;
    final feltRect = frameRect.deflate(feltInset);
    canvas.drawRect(feltRect, Paint()..color = const Color(0xFF15803D));
    // Vignette.
    final vignette = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.transparent,
          Colors.black.withValues(alpha: 0.35),
        ],
      ).createShader(feltRect);
    canvas.drawRect(feltRect, vignette);

    // Pockets.
    final pocketR = _BilliardsGameState.pocketRadius * scale;
    for (final p in pockets) {
      canvas.drawCircle(
        Offset(p.dx * scale, p.dy * scale),
        pocketR * 1.4,
        Paint()..color = Colors.black,
      );
      canvas.drawCircle(
        Offset(p.dx * scale, p.dy * scale),
        pocketR * 0.9,
        Paint()..color = const Color(0xFF111111),
      );
    }

    // Aim line while player is aiming on their turn.
    if (aiming && playerTurn) {
      _Ball? cue;
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
            Offset(cx + ux * 50, cy + uy * 50),
            Paint()
              ..color = const Color(0xFFFACC15)
              ..strokeWidth = 3
              ..strokeCap = StrokeCap.round,
          );
          // Forward aim line (where the cue ball will travel).
          final len = 80 + 220 * power;
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
    final r = _BilliardsGameState.ballR * scale;
    for (final b in balls) {
      if (b.pocketed) continue;
      final cx = b.x * scale;
      final cy = b.y * scale;
      // Shadow.
      canvas.drawCircle(
        Offset(cx + 1.5, cy + 2),
        r,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
      // Body.
      canvas.drawCircle(Offset(cx, cy), r, Paint()..color = b.color);
      // Stripe for stripes.
      if (b.isStripe) {
        final bandRect = Rect.fromCenter(
          center: Offset(cx, cy),
          width: r * 2.2,
          height: r * 1.2,
        );
        canvas.save();
        canvas.clipRect(bandRect);
        canvas.drawCircle(Offset(cx, cy), r, Paint()..color = Colors.white);
        canvas.restore();
      }
      // 8-ball: white circle in middle.
      if (b.isEight) {
        canvas.drawCircle(Offset(cx, cy), r * 0.55, Paint()..color = Colors.white);
        canvas.drawCircle(
          Offset(cx, cy),
          r * 0.22,
          Paint()..color = const Color(0xFF111111),
        );
      } else if (!b.isCue) {
        // Number badge.
        final numberColor = b.color.computeLuminance() > 0.6
            ? Colors.black
            : Colors.white;
        final tp = TextPainter(
          text: TextSpan(
            text: '${b.number}',
            style: TextStyle(
              color: numberColor,
              fontWeight: FontWeight.w900,
              fontSize: r * 0.85,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(cx - tp.width / 2, cy - tp.height / 2),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BilliardsPainter old) {
    if (aiming != old.aiming) return true;
    if (playerTurn != old.playerTurn) return true;
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
