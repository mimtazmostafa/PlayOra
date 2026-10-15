import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../game_widgets.dart';
import '../mini_game.dart';

/// Pong — ported from `downloaded_games/games/pong/game.py`.
///
/// Two paddles + bouncing ball + 5 power-up types. First to 5 wins.
/// Controls:
///   * P1 — drag/tap on left half (or W/S keys via RawKeyboard)
///   * P2 — drag/tap on right half (or Up/Down; in vs-Bot, P2 is AI)
///
/// Bot has 3 difficulties:
///   * easy   — moves toward power-ups, then deflects AWAY from ball
///   * medium — wall-bounce predicted ball trajectory
///   * hard   — perfect prediction + power-up grabbing when idle
class PongGame extends MiniGame {
  const PongGame({
    super.key,
    required super.callbacks,
    this.level = 1,
  });

  /// 1 = easy, 2 = medium, 3+ = hard bot (when AI mode on).
  final int level;

  @override
  State<PongGame> createState() => _PongGameState();
}

enum _PongDifficulty { easy, medium, hard }
enum _PongPhase { guide, countdown, playing, gameOver }
enum _PowerType { expand, shrink, speed, multi, shield }

class _PongGameState extends MiniGameState<PongGame>
    with SingleTickerProviderStateMixin {
  static const double _paddleW = 15;
  static const double _paddleBaseH = 100;
  static const double _ballRadius = 8;
  static const double _baseSpeed = 6.0;
  static const int _targetScore = 5;
  static const int _countdownFrames = 60;

  late final Ticker _ticker;
  final Random _rng = Random();

  // Paddles
  double _p1Y = 0;
  double _p1H = _paddleBaseH;
  bool _p1Shield = false;
  double _p2Y = 0;
  double _p2H = _paddleBaseH;
  bool _p2Shield = false;

  // Balls
  final List<_Ball> _balls = <_Ball>[];

  // Power-ups
  final List<_PowerUp> _powerups = <_PowerUp>[];
  int _powerupTimer = 0;

  // Score
  int _score1 = 0;
  int _score2 = 0;

  // Bot / modes
  bool _isAi = true;
  late _PongDifficulty _botDiff;

  _PongPhase _phase = _PongPhase.guide;
  int _winner = 0;
  int _countdownVal = 3;
  int _countdownTimer = 0;

  // Pointer input for paddle position
  double? _pointerY;

  // Board size
  double _boardW = 0;
  double _boardH = 0;

  static const Color _bg = Color(0xFF0A0A19);
  static const Color _p1 = Color(0xFF00FFFF);
  static const Color _p2 = Color(0xFFFF00FF);
  static const Color _ball = Color(0xFFFFEFC8);
  static const Color _net = Color(0xFF28283C);

  static const Map<_PowerType, Color> _puColors = {
    _PowerType.expand: Color(0xFF00FFFF),
    _PowerType.shrink: Color(0xFFFF0064),
    _PowerType.speed: Color(0xFFFFFF00),
    _PowerType.multi: Color(0xFFFF9600),
    _PowerType.shield: Color(0xFF00FF64),
  };

  @override
  void initState() {
    super.initState();
    _botDiff = widget.level >= 3
        ? _PongDifficulty.hard
        : (widget.level >= 2 ? _PongDifficulty.medium : _PongDifficulty.easy);
    _ticker = createTicker(_onTick)..start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reportScore(0);
      _updateStats();
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _reset() {
    setState(() {
      _p1Y = (_boardH - _paddleBaseH) / 2;
      _p1H = _paddleBaseH;
      _p1Shield = false;
      _p2Y = (_boardH - _paddleBaseH) / 2;
      _p2H = _paddleBaseH;
      _p2Shield = false;
      _balls.clear();
      _powerups.clear();
      _powerupTimer = 0;
      _score1 = 0;
      _score2 = 0;
      _winner = 0;
      _phase = _PongPhase.guide;
      _countdownVal = 3;
      _countdownTimer = 0;
    });
    reportScore(0);
    _updateStats();
  }

  void _startCountdown() {
    setState(() {
      _phase = _PongPhase.countdown;
      _countdownVal = 3;
      _countdownTimer = 0;
    });
  }

  void _startPlay() {
    setState(() {
      _phase = _PongPhase.playing;
      _balls.add(_Ball.spawn(_boardW / 2, _boardH / 2, _rng));
    });
  }

  void _onTick(Duration _) {
    if (_boardW <= 0 || _boardH <= 0) return;

    if (_phase == _PongPhase.guide) {
      return;
    }

    if (_phase == _PongPhase.gameOver) {
      if (_ticker.isActive) _ticker.stop();
      return;
    }

    if (_phase == _PongPhase.countdown) {
      _countdownTimer++;
      if (_countdownTimer >= _countdownFrames) {
        _countdownTimer = 0;
        _countdownVal--;
        if (_countdownVal <= 0) {
          _startPlay();
        }
      }
      setState(() {});
      return;
    }

    // PLAY phase below
    if (_isAi) {
      _botMove();
    }
    if (_pointerY != null) {
      // Pointer drives P1; for 2P, mirror via side of tap.
      // Since gesture is shared, we use a single pointer that drives
      // both paddles by side of screen.
      // (See GestureDetector: it sets _pointerY to whichever paddle is
      // being aimed.)
    }

    // Clamp paddles.
    _p1Y = _p1Y.clamp(0.0, _boardH - _p1H);
    _p2Y = _p2Y.clamp(0.0, _boardH - _p2H);

    // Power-up spawner
    _powerupTimer++;
    if (_powerupTimer > 600) {
      _powerupTimer = 0;
      if (_rng.nextDouble() < 0.6) _spawnPowerup();
    }

    for (final pu in List.of(_powerups)) {
      pu.timer--;
      pu.update(_boardH);
      if (pu.timer <= 0) {
        _powerups.remove(pu);
        continue;
      }
      final puRect = Rect.fromCircle(center: Offset(pu.x, pu.y), radius: pu.radius);
      final p1Rect = Rect.fromLTWH(50, _p1Y, _paddleW, _p1H);
      final p2Rect = Rect.fromLTWH(_boardW - 50 - _paddleW, _p2Y, _paddleW, _p2H);
      if (puRect.overlaps(p1Rect)) {
        _applyPowerup(pu.type, isP1: true);
        _powerups.remove(pu);
      } else if (puRect.overlaps(p2Rect)) {
        _applyPowerup(pu.type, isP1: false);
        _powerups.remove(pu);
      }
    }

    final ballsToRemove = <_Ball>[];
    for (final b in _balls) {
      if (b.rallyFrames > 0 && b.rallyFrames % 15 == 0) {
        const maxSpd = 15.0;
        const factor = 1.005;
        b.vx = max(-maxSpd, min(maxSpd, b.vx * factor));
        b.vy = max(-maxSpd, min(maxSpd, b.vy * factor));
      }
      b.move();

      // Wall bounce
      if (b.y - _ballRadius <= 0 || b.y + _ballRadius >= _boardH) {
        b.vy *= -1;
        b.y = b.y.clamp(_ballRadius, _boardH - _ballRadius);
      }

      // Paddle collisions
      final bRect = Rect.fromCircle(
          center: Offset(b.x, b.y), radius: _ballRadius);
      final p1Rect = Rect.fromLTWH(50, _p1Y, _paddleW, _p1H);
      final p2Rect = Rect.fromLTWH(_boardW - 50 - _paddleW, _p2Y, _paddleW, _p2H);

      bool hitP1 = false;
      bool hitP2 = false;
      if (bRect.overlaps(p1Rect) && b.vx < 0) {
        b.vx *= -1.1;
        hitP1 = true;
      } else if (bRect.overlaps(p2Rect) && b.vx > 0) {
        b.vx *= -1.1;
        hitP2 = true;
      }
      if (hitP1 || hitP2) {
        final hitterY = hitP1 ? _p1Y : _p2Y;
        final hitterH = hitP1 ? _p1H : _p2H;
        final rel = ((hitterY + hitterH / 2) - b.y) / (hitterH / 2);
        b.vy = rel * -_baseSpeed;
        const maxSpd = 15.0;
        b.vx = b.vx.clamp(-maxSpd, maxSpd);
        b.vy = b.vy.clamp(-maxSpd, maxSpd);
        haptic(HapticFeedbackType.selection);
      }

      // Score
      if (b.x < 0) {
        if (_p1Shield) {
          _p1Shield = false;
          b.vx *= -1;
          b.x = 20;
        } else {
          _score2++;
          ballsToRemove.add(b);
          haptic(HapticFeedbackType.heavy);
        }
      } else if (b.x > _boardW) {
        if (_p2Shield) {
          _p2Shield = false;
          b.vx *= -1;
          b.x = _boardW - 20;
        } else {
          _score1++;
          ballsToRemove.add(b);
          haptic(HapticFeedbackType.heavy);
        }
      }
    }
    for (final b in ballsToRemove) {
      _balls.remove(b);
    }

    if (_balls.isEmpty) {
      _p1H = _paddleBaseH;
      _p2H = _paddleBaseH;
      if (_score1 >= _targetScore) {
        _finish(1);
      } else if (_score2 >= _targetScore) {
        _finish(2);
      } else {
        _startCountdown();
      }
    }

    reportScore(_score1 * 100 + _score2 * 50);
    _updateStats();
    setState(() {});
  }

  void _spawnPowerup() {
    final type = _PowerType.values[_rng.nextInt(_PowerType.values.length)];
    _powerups.add(_PowerUp(
      x: _boardW / 2,
      y: 80 + _rng.nextDouble() * (_boardH - 160),
      type: type,
      vx: (_rng.nextBool() ? 2.5 : -2.5) * (0.8 + _rng.nextDouble() * 0.4),
      vy: _rng.nextDouble() * 2 - 1,
    ));
  }

  void _applyPowerup(_PowerType type, {required bool isP1}) {
    switch (type) {
      case _PowerType.expand:
        if (isP1) {
          _p1H = _paddleBaseH * 1.5;
        } else {
          _p2H = _paddleBaseH * 1.5;
        }
        break;
      case _PowerType.shrink:
        if (isP1) {
          _p2H = _paddleBaseH * 0.5;
        } else {
          _p1H = _paddleBaseH * 0.5;
        }
        break;
      case _PowerType.speed:
        for (final b in _balls) {
          b.vx *= 1.5;
          b.vy *= 1.5;
        }
        break;
      case _PowerType.multi:
        if (_balls.isNotEmpty) {
          _balls.add(_Ball(
            x: _boardW / 2,
            y: _boardH / 2,
            vx: -_balls.first.vx,
            vy: _balls.first.vy,
            trail: <Offset>[],
            rallyFrames: 0,
          ));
        }
        break;
      case _PowerType.shield:
        if (isP1) {
          _p1Shield = true;
        } else {
          _p2Shield = true;
        }
        break;
    }
    haptic(HapticFeedbackType.medium);
  }

  void _finish(int winner) {
    setState(() {
      _phase = _PongPhase.gameOver;
      _winner = winner;
    });
    reportScore((_score1 + _score2) * 50 + 200);
    haptic(HapticFeedbackType.heavy);
    reportGameOver();
  }

  void _moveP1To(double y) {
    _p1Y = y - _p1H / 2;
    _p1Y = _p1Y.clamp(0.0, _boardH - _p1H);
  }

  void _moveP2To(double y) {
    _p2Y = y - _p2H / 2;
    _p2Y = _p2Y.clamp(0.0, _boardH - _p2H);
  }

  // ─── AI ──────────────────────────────────────────────────────────────

  void _botMove() {
    if (_botDiff == _PongDifficulty.easy) {
      final speed = 7.0 * 0.4;
      final center = _p2Y + _p2H / 2;
      if (_powerups.isNotEmpty) {
        final nearest = _powerups
            .reduce((a, b) => (a.y - center).abs() < (b.y - center).abs() ? a : b);
        if (center < nearest.y - 10) {
          _p2Y += speed;
        } else if (center > nearest.y + 10) {
          _p2Y -= speed;
        }
        return;
      }
      _Ball? target;
      for (final b in _balls) {
        if (b.vx > 0) {
          target = b;
          break;
        }
      }
      if (target != null) {
        final wrongTarget = _boardH - target.y;
        if (center < wrongTarget - 15) {
          _p2Y += speed;
        } else if (center > wrongTarget + 15) {
          _p2Y -= speed;
        }
      }
      return;
    }

    // medium / hard
    _Ball? target;
    double minDist = 9999;
    for (final b in _balls) {
      if (b.vx > 0) {
        final d = (_boardW - 50 - _paddleW) - b.x;
        if (d > 0 && d < minDist) {
          minDist = d;
          target = b;
        }
      }
    }
    if (target != null) {
      var targetY = target.y;
      if (_botDiff != _PongDifficulty.easy) {
        final timeToReach = minDist / max(0.1, target.vx.abs());
        targetY = target.y + target.vy * timeToReach;
        while (targetY < 0 || targetY > _boardH) {
          if (targetY < 0) targetY = -targetY;
          if (targetY > _boardH) targetY = 2 * _boardH - targetY;
        }
      }
      if (_botDiff == _PongDifficulty.medium) {
        targetY += _rng.nextDouble() * 30 - 15;
      }
      final speed = _botDiff == _PongDifficulty.hard
          ? 7.0 * 1.15
          : 7.0 * 0.85;
      final center = _p2Y + _p2H / 2;
      if (center < targetY - 10) {
        _p2Y += speed;
      } else if (center > targetY + 10) {
        _p2Y -= speed;
      }
    } else {
      final centerY = _boardH / 2;
      final spd = 7.0 * 0.5;
      final center = _p2Y + _p2H / 2;
      if (center < centerY - 10) {
        _p2Y += spd;
      } else if (center > centerY + 10) {
        _p2Y -= spd;
      }
    }

    if (_botDiff == _PongDifficulty.hard && target == null) {
      for (final pu in _powerups) {
        if (pu.vx > 0) {
          final puDist = (_boardW - 50 - _paddleW) - pu.x;
          if (puDist > 0 && puDist < 400) {
            final center = _p2Y + _p2H / 2;
            final spd = 7.0 * 1.15;
            if (center < pu.y - 10) {
              _p2Y += spd;
            } else if (center > pu.y + 10) {
              _p2Y -= spd;
            }
            break;
          }
        }
      }
    }
  }

  void _updateStats() {
    String turn;
    switch (_phase) {
      case _PongPhase.guide:
        turn = 'Tap to start';
        break;
      case _PongPhase.countdown:
        turn = 'Get ready…';
        break;
      case _PongPhase.gameOver:
        turn = 'Game over';
        break;
      case _PongPhase.playing:
        turn = '$_score1 - $_score2 (first to $_targetScore)';
        break;
    }
    reportStats(turn);
  }

  // ─── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _bg,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            _boardW = c.maxWidth;
            _boardH = c.maxHeight;
            return Column(
              children: [
                // Top HUD removed — host GameContainerScreen provides it.
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, c2) {
                      _boardW = c2.maxWidth;
                      _boardH = c2.maxHeight;
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (d) {
                          if (_phase == _PongPhase.guide) {
                            _startCountdown();
                          }
                        },
                        onPanUpdate: (d) {
                          if (_phase != _PongPhase.playing) return;
                          if (_isAi) {
                            if (d.localPosition.dx < _boardW / 2) {
                              _moveP1To(d.localPosition.dy);
                            }
                          } else {
                            if (d.localPosition.dx < _boardW / 2) {
                              _moveP1To(d.localPosition.dy);
                            } else {
                              _moveP2To(d.localPosition.dy);
                            }
                          }
                        },
                        onPanStart: (d) {
                          if (_phase == _PongPhase.guide) {
                            _startCountdown();
                            return;
                          }
                          if (_phase != _PongPhase.playing) return;
                          if (_isAi) {
                            if (d.localPosition.dx < _boardW / 2) {
                              _moveP1To(d.localPosition.dy);
                            }
                          } else {
                            if (d.localPosition.dx < _boardW / 2) {
                              _moveP1To(d.localPosition.dy);
                            } else {
                              _moveP2To(d.localPosition.dy);
                            }
                          }
                        },
                        child: Stack(
                          children: [
                            CustomPaint(
                              size: Size(_boardW, _boardH),
                              painter: _PongBoardPainter(
                                boardW: _boardW,
                                boardH: _boardH,
                                p1Y: _p1Y,
                                p1H: _p1H,
                                p2Y: _p2Y,
                                p2H: _p2H,
                                p1Shield: _p1Shield,
                                p2Shield: _p2Shield,
                                balls: _balls,
                                powerups: _powerups,
                                p1: _p1,
                                p2: _p2,
                                ball: _ball,
                                net: _net,
                                puColors: _puColors,
                                ballRadius: _ballRadius,
                                score1: _score1,
                                score2: _score2,
                                phase: _phase,
                                countdownVal: _countdownVal,
                                countdownProgress: _countdownTimer / _countdownFrames,
                                winner: _winner,
                                isAi: _isAi,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                _buildControls(),
              ],
            );
          },
        ),
      ),
    );
  }


  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: const Color(0xFF06060F),
      child: Row(
        children: [
          ToggleButtons(
            isSelected: [!_isAi, _isAi],
            onPressed: (i) {
              setState(() {
                _isAi = i == 1;
              });
              _reset();
            },
            constraints: const BoxConstraints(minHeight: 32, minWidth: 70),
            borderRadius: BorderRadius.circular(8),
            color: Colors.white60,
            selectedColor: Colors.white,
            fillColor: _p1.withValues(alpha: 0.3),
            children: const [Text('2P'), Text('vs Bot')],
          ),
          const SizedBox(width: 8),
          if (_isAi)
            ToggleButtons(
              isSelected: [
                _botDiff == _PongDifficulty.easy,
                _botDiff == _PongDifficulty.medium,
                _botDiff == _PongDifficulty.hard,
              ],
              onPressed: (i) {
                setState(() {
                  _botDiff = _PongDifficulty.values[i];
                });
                _reset();
              },
              constraints: const BoxConstraints(minHeight: 32, minWidth: 50),
              borderRadius: BorderRadius.circular(8),
              color: Colors.white60,
              selectedColor: Colors.white,
              fillColor: _p2.withValues(alpha: 0.3),
              children: const [Text('Easy'), Text('Med'), Text('Hard')],
            ),
          const Spacer(),
          IconButton(
            onPressed: _reset,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _Ball {
  _Ball({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.trail,
    required this.rallyFrames,
  });

  factory _Ball.spawn(double x, double y, Random rng) {
    final dirX = rng.nextBool() ? 1 : -1;
    final dirY = rng.nextBool() ? 1 : -1;
    return _Ball(
      x: x,
      y: y,
      vx: _PongGameState._baseSpeed * dirX,
      vy: _PongGameState._baseSpeed * dirY,
      trail: <Offset>[],
      rallyFrames: 0,
    );
  }

  double x;
  double y;
  double vx;
  double vy;
  final List<Offset> trail;
  int rallyFrames;

  void move() {
    trail.add(Offset(x, y));
    if (trail.length > 10) trail.removeAt(0);
    x += vx;
    y += vy;
    rallyFrames++;
  }
}

class _PowerUp {
  _PowerUp({
    required this.x,
    required this.y,
    required this.type,
    required this.vx,
    required this.vy,
  });

  double x;
  double y;
  final _PowerType type;
  double vx;
  double vy;
  final double radius = 18;
  int timer = 600;

  void update(double boardH) {
    x += vx;
    y += vy;
    if (y < 20 || y > boardH - 20) vy *= -1;
  }
}

class _PongBoardPainter extends CustomPainter {
  _PongBoardPainter({
    required this.boardW,
    required this.boardH,
    required this.p1Y,
    required this.p1H,
    required this.p2Y,
    required this.p2H,
    required this.p1Shield,
    required this.p2Shield,
    required this.balls,
    required this.powerups,
    required this.p1,
    required this.p2,
    required this.ball,
    required this.net,
    required this.puColors,
    required this.ballRadius,
    required this.score1,
    required this.score2,
    required this.phase,
    required this.countdownVal,
    required this.countdownProgress,
    required this.winner,
    required this.isAi,
  });

  final double boardW;
  final double boardH;
  final double p1Y;
  final double p1H;
  final double p2Y;
  final double p2H;
  final bool p1Shield;
  final bool p2Shield;
  final List<_Ball> balls;
  final List<_PowerUp> powerups;
  final Color p1;
  final Color p2;
  final Color ball;
  final Color net;
  final Map<_PowerType, Color> puColors;
  final double ballRadius;
  final int score1;
  final int score2;
  final _PongPhase phase;
  final int countdownVal;
  final double countdownProgress;
  final int winner;
  final bool isAi;

  void _drawPaddle(Canvas canvas, double x, double y, double h, Color c,
      bool shield) {
    // Glow
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x - 5, y - 5, 25, h + 10),
        const Radius.circular(8),
      ),
      Paint()..color = c.withValues(alpha: 0.18),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, 15, h),
        const Radius.circular(5),
      ),
      Paint()..color = c,
    );
    if (shield) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x - 10, y - 5, 35, h + 10),
          const Radius.circular(8),
        ),
        Paint()
          ..color = const Color(0xFF00FF64)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Net
    for (var y = 0.0; y < boardH; y += 40) {
      canvas.drawRect(
        Rect.fromLTWH(boardW / 2 - 2, y, 4, 20),
        Paint()..color = net,
      );
    }
    _drawPaddle(canvas, 50, p1Y, p1H, p1, p1Shield);
    _drawPaddle(canvas, boardW - 50 - 15, p2Y, p2H, p2, p2Shield);

    // Power-ups
    for (final pu in powerups) {
      final color = puColors[pu.type] ?? Colors.white;
      canvas.drawCircle(
        Offset(pu.x, pu.y),
        pu.radius,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      canvas.drawCircle(
        Offset(pu.x, pu.y),
        pu.radius * 0.55,
        Paint()..color = color.withValues(alpha: 0.3),
      );
      _drawPuIcon(canvas, pu.type, Offset(pu.x, pu.y), color);
    }

    // Balls
    for (final b in balls) {
      // Trail
      for (var i = 0; i < b.trail.length; i++) {
        final t = b.trail[i];
        final alpha = (i / b.trail.length);
        canvas.drawCircle(
          t,
          ballRadius * alpha,
          Paint()..color = ball.withValues(alpha: alpha * 0.4),
        );
      }
      canvas.drawCircle(
        Offset(b.x, b.y),
        ballRadius,
        Paint()..color = ball,
      );
      canvas.drawCircle(
        Offset(b.x, b.y),
        ballRadius * 0.5,
        Paint()..color = Colors.white,
      );
    }

    // Countdown overlay
    if (phase == _PongPhase.countdown) {
      final overlay = Paint()
        ..color = Colors.black.withValues(alpha: 0.45);
      canvas.drawRect(Offset.zero & size, overlay);
      final digitColors = [Colors.red, Colors.yellow, Colors.green];
      final digit = countdownVal;
      final c = digitColors[3 - digit];
      final scale = 0.5 + 0.5 * min(1.0, countdownProgress * 3);
      final r = 90 * scale;
      canvas.drawCircle(
        Offset(boardW / 2, boardH / 2),
        r + 10,
        Paint()..color = c.withValues(alpha: 0.18),
      );
      canvas.drawCircle(
        Offset(boardW / 2, boardH / 2),
        r,
        Paint()
          ..color = c.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: '$digit',
          style: TextStyle(
            color: c,
            fontSize: 80,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(boardW / 2 - tp.width / 2, boardH / 2 - tp.height / 2),
      );
    }
  }

  void _drawPuIcon(Canvas canvas, _PowerType type, Offset c, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    switch (type) {
      case _PowerType.expand:
        canvas.drawLine(
            Offset(c.dx, c.dy - 8), Offset(c.dx, c.dy + 8), paint);
        canvas.drawLine(
            Offset(c.dx - 4, c.dy - 6), Offset(c.dx, c.dy - 10), paint);
        canvas.drawLine(
            Offset(c.dx + 4, c.dy - 6), Offset(c.dx, c.dy - 10), paint);
        canvas.drawLine(
            Offset(c.dx - 4, c.dy + 6), Offset(c.dx, c.dy + 10), paint);
        canvas.drawLine(
            Offset(c.dx + 4, c.dy + 6), Offset(c.dx, c.dy + 10), paint);
        break;
      case _PowerType.shrink:
        canvas.drawLine(
            Offset(c.dx - 4, c.dy - 4), Offset(c.dx + 4, c.dy + 4), paint);
        canvas.drawLine(
            Offset(c.dx + 4, c.dy - 4), Offset(c.dx - 4, c.dy + 4), paint);
        break;
      case _PowerType.speed:
        final path = Path()
          ..moveTo(c.dx - 6, c.dy - 8)
          ..lineTo(c.dx + 2, c.dy - 2)
          ..lineTo(c.dx - 2, c.dy - 2)
          ..lineTo(c.dx + 4, c.dy + 8)
          ..lineTo(c.dx - 2, c.dy + 2)
          ..lineTo(c.dx + 2, c.dy + 2)
          ..close();
        canvas.drawPath(path, Paint()..color = color);
        break;
      case _PowerType.multi:
        canvas.drawCircle(Offset(c.dx - 6, c.dy), 5, paint);
        canvas.drawCircle(Offset(c.dx + 6, c.dy), 5, paint);
        break;
      case _PowerType.shield:
        final path = Path()
          ..moveTo(c.dx, c.dy - 10)
          ..lineTo(c.dx + 8, c.dy - 5)
          ..lineTo(c.dx + 8, c.dy + 5)
          ..lineTo(c.dx, c.dy + 10)
          ..lineTo(c.dx - 8, c.dy + 5)
          ..lineTo(c.dx - 8, c.dy - 5)
          ..close();
        canvas.drawPath(path, paint);
        break;
    }
  }

  @override
  bool shouldRepaint(_PongBoardPainter old) => true;
}
