import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../game_widgets.dart';
import '../mini_game.dart';

/// Bowling Pro — swipe-with-curve bowling.
///
/// Player taps the foul line to set the ball's horizontal X, then
/// swipes forward (upward) to launch. The horizontal component of the
/// swipe imparts curve/spin to the ball. 10 pins in triangle, each
/// with its own impact physics + chain pin-pin collisions. Traditional
/// 10-frame scorecard with Strike/Spare bonus scoring.
class BowlingProGame extends MiniGame {
  const BowlingProGame({super.key, required super.callbacks});

  @override
  State<BowlingProGame> createState() => _State();
}

class _State extends MiniGameState<BowlingProGame>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final Random _rng = Random();
  DateTime _last = DateTime.now();

  static const int _totalFrames = 10;
  static const int _pinsPerFrame = 10;

  // Frame state.
  int _score = 0;
  int _frame = 0; // 0..9
  int _rollInFrame = 0; // 0 or 1 (or 2 for frame 10)
  bool _rolling = false;
  bool _gameOver = false;

  // Per-frame rolls: list of int pin counts per roll.
  // rolls[0] = frame 1 roll 1, rolls[1] = frame 1 roll 2, etc.
  final List<int> _rolls = [];

  // Input state.
  bool _aimingX = false;
  double _ballX = 0.5; // canvas fraction
  bool _spinAiming = false;
  Offset? _spinDragOrigin;
  Offset _spinDragCurrent = Offset.zero;

  // Ball physics.
  double _ballY = 0.85; // canvas fraction
  double _ballVx = 0;
  double _ballVy = 0;
  double _ballSpin = 0; // signed, applied as continuous lateral accel
  bool _launched = false;
  double _laneT = 0; // 0..1 from launch line to pin deck

  // Pin list.
  late List<_Pin> _pinList;
  final List<_FloatingText> _floaters = [];
  final List<_Particle> _particles = [];

  double _canvasW = 0;
  double _canvasH = 0;

  @override
  void initState() {
    super.initState();
    _initPins();
    _ticker = createTicker(_tick)..start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reportScore(_score);
      reportStats('Frame 1/$_totalFrames');
    });
  }

  void _initPins() {
    _pinList = [];
    final cx = 0.5;
    final cy = 0.18;
    const spacing = 0.06;
    var idx = 0;
    for (var row = 0; row < 4; row++) {
      final count = row + 1;
      for (var col = 0; col < count; col++) {
        final px = cx + (col - (count - 1) / 2) * spacing;
        final py = cy + row * spacing * 0.8;
        _pinList.add(_Pin(x: px, y: py, idx: idx));
        idx += 1;
      }
    }
  }

  void _resetPins() {
    for (final p in _pinList) {
      p
        ..vx = 0
        ..vy = 0
        ..fallT = 0
        ..fallen = false;
    }
    // Re-init positions.
    final cx = 0.5;
    final cy = 0.18;
    const spacing = 0.06;
    var idx = 0;
    for (var row = 0; row < 4; row++) {
      final count = row + 1;
      for (var col = 0; col < count; col++) {
        final px = cx + (col - (count - 1) / 2) * spacing;
        final py = cy + row * spacing * 0.8;
        final pin = _pinList[idx];
        pin.x = px;
        pin.y = py;
        idx += 1;
      }
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _tick(Duration _) {
    if (!mounted) return;
    final now = DateTime.now();
    final dt = now.difference(_last).inMicroseconds / 1e6;
    _last = now;
    if (dt > 0.05) return; // skip big jumps (e.g. backgrounded)

    setState(() {
      // Animate falling pins.
      for (final p in _pinList) {
        if (p.fallen && p.fallT < 1.0) {
          p.fallT = (p.fallT + dt * 4).clamp(0.0, 1.0);
        }
      }

      // Particles.
      for (final pt in _particles) {
        pt.x += pt.vx * dt;
        pt.y += pt.vy * dt;
        pt.vy += 240 * dt;
        pt.life -= dt;
      }
      _particles.removeWhere((pt) => pt.life <= 0);

      // Floaters.
      for (final f in _floaters) {
        f.y -= 28 * dt;
        f.life -= dt;
      }
      _floaters.removeWhere((f) => f.life <= 0);

      if (_rolling && _launched) {
        _laneT += dt * 1.5;

        // Apply spin as continuous lateral acceleration.
        _ballVx += _ballSpin * dt * 60;
        // Friction in lane.
        _ballVx *= (1.0 - 0.4 * dt);
        _ballVy *= (1.0 - 0.1 * dt);

        _ballX += _ballVx * dt;
        _ballY -= _ballVy * dt;

        // Gutter bounce.
        if (_ballX < 0.06) {
          _ballX = 0.06;
          _ballVx = _ballVx.abs() * 0.4;
        }
        if (_ballX > 0.94) {
          _ballX = 0.94;
          _ballVx = -_ballVx.abs() * 0.4;
        }

        // Ball-pin collisions.
        for (final p in _pinList) {
          if (p.fallen) continue;
          final dx = _ballX - p.x;
          final dy = _ballY - p.y;
          final d = sqrt(dx * dx + dy * dy);
          final hitR = 0.045;
          if (d < hitR) {
            // Knock down the pin.
            p.fallen = true;
            p.fallT = 0;
            final n = (d > 0.0001) ? Offset(dx, dy) / d : const Offset(0, -1);
            final impactSpeed = sqrt(_ballVx * _ballVx + _ballVy * _ballVy);
            p.vx = n.dx * impactSpeed * 4;
            p.vy = n.dy * impactSpeed * 4;
            // Spawn debris.
            for (var i = 0; i < 6; i++) {
              final a = _rng.nextDouble() * 2 * pi;
              final s = 40 + _rng.nextDouble() * 80;
              _particles.add(_Particle(
                x: p.x,
                y: p.y,
                vx: cos(a) * s / _canvasW,
                vy: sin(a) * s / _canvasH,
                life: 0.5,
              ));
            }
          }
        }

        // Pin-pin chain collisions.
        for (var i = 0; i < _pinList.length; i++) {
          final a = _pinList[i];
          for (var j = i + 1; j < _pinList.length; j++) {
            final b = _pinList[j];
            final dx = a.x - b.x;
            final dy = a.y - b.y;
            final d = sqrt(dx * dx + dy * dy);
            const pinR = 0.025;
            if (d < pinR * 2) {
              // Transfer momentum 50% — snapshot a's velocity before
              // mutating so b's update uses the pre-collision value.
              final m = 0.5;
              final ax = a.vx, ay = a.vy;
              a.vx = ax * (1 - m) + b.vx * m;
              a.vy = ay * (1 - m) + b.vy * m;
              b.vx = b.vx * (1 - m) + ax * m;
              b.vy = b.vy * (1 - m) + ay * m;
              if (!a.fallen && b.vx.abs() + b.vy.abs() > 0.5) {
                a.fallen = true;
                a.fallT = 0;
              }
              if (!b.fallen && a.vx.abs() + a.vy.abs() > 0.5) {
                b.fallen = true;
                b.fallT = 0;
              }
            }
          }
        }

        // Apply pin velocities.
        for (final p in _pinList) {
          p.x += p.vx * dt;
          p.y += p.vy * dt;
          p.vy += 0.3 * dt; // slight gravity on pins
          p.vx *= (1.0 - 0.5 * dt);
        }

        // End roll when ball reaches the pin deck.
        if (_laneT > 1.0 || _ballY < 0.10) {
          _finishRoll();
        }
      }
    });
  }

  void _finishRoll() {
    _rolling = false;
    _launched = false;
    final knocked = _pinList.where((p) => p.fallen).length;
    _rolls.add(knocked);
    _ballY = 0.85;
    _ballVx = 0;
    _ballVy = 0;
    _ballSpin = 0;
    _laneT = 0;

    if (knocked == _pinsPerFrame) {
      _floaters.add(_FloatingText(
        x: 0.5,
        y: 0.4,
        text: _rollInFrame == 0 ? 'STRIKE!' : 'SPARE!',
        color: const Color(0xFFFBBF24),
      ));
      haptic(HapticFeedbackType.heavy);
    } else if (knocked > 0) {
      _floaters.add(_FloatingText(
        x: 0.5,
        y: 0.4,
        text: '$knocked PINS',
        color: const Color(0xFF22C55E),
      ));
      haptic(HapticFeedbackType.medium);
    }

    _advanceFrame();
  }

  void _advanceFrame() {
    // Determine if frame is over.
    final isStrike = _rolls.isNotEmpty &&
        _frame < 9 &&
        _rollInFrame == 0 &&
        _rolls.last == _pinsPerFrame;

    if (_frame == 9) {
      // 10th frame: allow up to 3 rolls.
      if (_rollInFrame == 0) {
        if (isStrike) {
          // Strike: reset all pins, allow roll 2.
          _rollInFrame = 1;
          _resetPins();
          reportStats('Frame 10/10  •  Strike! Roll again');
        } else {
          _rollInFrame = 1;
          _clearFallenPins();
          reportStats('Frame 10/10  •  ${_pinsThisFrame()}/$_pinsPerFrame pins down');
        }
      } else if (_rollInFrame == 1) {
        final first = _rolls.length >= 2
            ? _rolls[_rolls.length - 2]
            : _rolls[_rolls.length - 1];
        final second = _rolls.last;
        if (first == _pinsPerFrame) {
          // After strike: reset, allow roll 3.
          _rollInFrame = 2;
          _resetPins();
          reportStats('Frame 10/10  •  Strike + spare roll');
        } else if (first + second == _pinsPerFrame) {
          // Spare: reset, allow roll 3.
          _rollInFrame = 2;
          _resetPins();
          reportStats('Frame 10/10  •  Spare roll');
        } else {
          _endGame();
          return;
        }
      } else {
        _endGame();
        return;
      }
    } else {
      // Frames 1..9: end frame on strike (reset all pins) or after roll 2.
      if (_rollInFrame == 0) {
        if (isStrike) {
          _resetPins();
          _frame += 1;
          _rollInFrame = 0;
          reportStats('Frame ${_frame + 1}/$_totalFrames');
        } else {
          _rollInFrame = 1;
          _clearFallenPins();
          reportStats('Frame ${_frame + 1}/$_totalFrames  •  ${_pinsThisFrame()}/$_pinsPerFrame');
        }
      } else {
        _frame += 1;
        _rollInFrame = 0;
        _resetPins();
        if (_frame >= _totalFrames) {
          _endGame();
        } else {
          reportStats('Frame ${_frame + 1}/$_totalFrames');
        }
      }
    }

    _score = _computeScore();
    reportScore(_score);
  }

  int _pinsThisFrame() {
    // Sum the last two rolls of the current frame.
    final last = _rolls.isEmpty ? 0 : _rolls.last;
    if (_rollInFrame == 0) return last;
    if (_rolls.length < 2) return last;
    return _rolls[_rolls.length - 2] + last;
  }

  void _clearFallenPins() {
    for (final p in _pinList) {
      if (p.fallen) {
        // Park it offscreen.
        p.x = -10;
        p.y = -10;
        p.vx = 0;
        p.vy = 0;
      }
    }
  }

  int _computeScore() {
    // Traditional bowling scoring.
    final r = _rolls;
    int score = 0;
    int rollIdx = 0;
    for (var f = 0; f < _totalFrames; f++) {
      if (rollIdx >= r.length) break;
      if (r[rollIdx] == _pinsPerFrame) {
        // Strike.
        final bonus = (rollIdx + 1 < r.length ? r[rollIdx + 1] : 0) +
            (rollIdx + 2 < r.length ? r[rollIdx + 2] : 0);
        score += _pinsPerFrame + bonus;
        rollIdx += 1;
      } else if (rollIdx + 1 < r.length &&
          r[rollIdx] + r[rollIdx + 1] == _pinsPerFrame) {
        // Spare.
        final bonus = rollIdx + 2 < r.length ? r[rollIdx + 2] : 0;
        score += _pinsPerFrame + bonus;
        rollIdx += 2;
      } else {
        score += r[rollIdx];
        if (rollIdx + 1 < r.length) score += r[rollIdx + 1];
        rollIdx += 2;
      }
    }
    return score;
  }

  void _endGame() {
    if (_gameOver) return;
    _gameOver = true;
    haptic(HapticFeedbackType.heavy);
    reportScore(_score);
    reportStats('Final: $_score pts');
    reportGameOver();
  }

  // ── Input ────────────────────────────────────────────────
  void _onTapDown(TapDownDetails d) {
    if (_rolling || _gameOver) return;
    final y = d.localPosition.dy / _canvasH;
    final x = d.localPosition.dx / _canvasW;
    if (!_spinAiming && !_aimingX && y > 0.78) {
      // Tap on the gutter / launch line area to lock horizontal X.
      setState(() {
        _aimingX = true;
        _ballX = x.clamp(0.06, 0.94);
      });
    }
  }

  void _onPanStart(DragStartDetails d) {
    if (_rolling || _gameOver) return;
    if (_aimingX && !_spinAiming) {
      // Start spin aim.
      _spinAiming = true;
      _spinDragOrigin = d.localPosition;
      _spinDragCurrent = d.localPosition;
    }
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_rolling || _gameOver) return;
    if (_spinAiming) {
      _spinDragCurrent = d.localPosition;
    } else if (_aimingX) {
      // Allow adjusting X while still in aiming mode.
      final x = d.localPosition.dx / _canvasW;
      _ballX = x.clamp(0.06, 0.94);
    }
  }

  void _onPanEnd(DragEndDetails d) {
    if (_rolling || _gameOver) {
      _aimingX = false;
      _spinAiming = false;
      return;
    }
    if (_spinAiming && _spinDragOrigin != null) {
      final velocity = d.velocity.pixelsPerSecond;
      // Forward swipe = upward (negative vy).
      if (velocity.dy < -200 && velocity.distance > 200) {
        // Launch!
        _ballVx = velocity.dx / _canvasW * 0.5;
        _ballVy = (-velocity.dy) / _canvasH * 0.7;
        // Curve from horizontal swipe component.
        _ballSpin = (velocity.dx / 600).clamp(-1.0, 1.0);
        _rolling = true;
        _launched = true;
        _aimingX = false;
        _spinAiming = false;
        _spinDragOrigin = null;
        haptic(HapticFeedbackType.heavy);
        return;
      }
    }
    _aimingX = false;
    _spinAiming = false;
    _spinDragOrigin = null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        _canvasW = c.maxWidth;
        _canvasH = c.maxHeight;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: _onTapDown,
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _BowlingPainter(
                    ballX: _ballX,
                    ballY: _ballY,
                    pins: _pinList,
                    floaters: _floaters,
                    particles: _particles,
                    aimingX: _aimingX,
                    spinAiming: _spinAiming,
                    spinOrigin: _spinDragOrigin,
                    spinCurrent: _spinDragCurrent,
                    spinBallX: _ballX,
                    spinBallY: 0.85,
                  ),
                ),
              ),
              // 10-frame scorecard removed — host
              // GameContainerScreen shows the score via GameHudBar
              // and the stats subtitle via reportStats/reportScore.
              Positioned(
                bottom: 16,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _gameOver
                          ? 'Game over — $_score pts'
                          : _rolling
                              ? 'Watching ball…'
                              : _spinAiming
                                  ? 'Swipe forward to launch'
                                  : _aimingX
                                      ? 'Swipe up to throw'
                                      : 'Tap the foul line to set X',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Pin {
  _Pin({required this.x, required this.y, required this.idx})
      : fallen = false,
        fallT = 0,
        vx = 0,
        vy = 0;
  double x;
  double y;
  int idx;
  bool fallen;
  double fallT;
  double vx;
  double vy;
}

class _Particle {
  _Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.life,
  });
  double x; // canvas fraction
  double y; // canvas fraction
  double vx; // fraction/s
  double vy;
  double life;
}

class _FloatingText {
  _FloatingText({required this.x, required this.y, required this.text, required this.color}) : life = 1.2;
  double x;
  double y;
  String text;
  Color color;
  double life;
}

// _Scorecard and _RollCell removed — host GameContainerScreen
// owns the score/stat display via GameHudBar + reportStats.

class _BowlingPainter extends CustomPainter {
  _BowlingPainter({
    required this.ballX,
    required this.ballY,
    required this.pins,
    required this.floaters,
    required this.particles,
    required this.aimingX,
    required this.spinAiming,
    required this.spinOrigin,
    required this.spinCurrent,
    required this.spinBallX,
    required this.spinBallY,
  });

  final double ballX;
  final double ballY;
  final List<_Pin> pins;
  final List<_FloatingText> floaters;
  final List<_Particle> particles;
  final bool aimingX;
  final bool spinAiming;
  final Offset? spinOrigin;
  final Offset spinCurrent;
  final double spinBallX;
  final double spinBallY;

  @override
  void paint(Canvas canvas, Size size) {
    // Lane background gradient (wood).
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xFFFBBF24), Color(0xFFFCD34D), Color(0xFFFDE68A)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    // Trapezoidal lane: narrower at top (far end).
    final laneTopWidth = size.width * 0.55;
    final laneBottomWidth = size.width * 0.95;
    final laneTopX = (size.width - laneTopWidth) / 2;
    final laneBottomX = (size.width - laneBottomWidth) / 2;
    final laneTopY = size.height * 0.05;
    final laneBottomY = size.height * 0.95;
    final lanePath = Path()
      ..moveTo(laneBottomX, laneBottomY)
      ..lineTo(laneBottomX + laneBottomWidth, laneBottomY)
      ..lineTo(laneTopX + laneTopWidth, laneTopY)
      ..lineTo(laneTopX, laneTopY)
      ..close();
    canvas.drawPath(
      lanePath,
      Paint()..color = const Color(0xFFFCD34D),
    );
    // Wood grain stripes (vertical, slightly varied).
    final grainPaint = Paint()
      ..color = const Color(0xFFB45309).withValues(alpha: 0.15)
      ..strokeWidth = 1.4;
    for (var i = 0; i < 10; i++) {
      final t = i / 9;
      final xBottom = laneBottomX + laneBottomWidth * t;
      final xTop = laneTopX + laneTopWidth * t;
      canvas.drawLine(
        Offset(xBottom, laneBottomY),
        Offset(xTop, laneTopY),
        grainPaint,
      );
    }

    // Gutters.
    canvas.drawPath(
      Path()
        ..moveTo(0, size.height)
        ..lineTo(laneBottomX, laneBottomY)
        ..lineTo(laneTopX, laneTopY)
        ..lineTo(0, 0)
        ..close(),
      Paint()..color = const Color(0xFF334155),
    );
    canvas.drawPath(
      Path()
        ..moveTo(size.width, size.height)
        ..lineTo(laneBottomX + laneBottomWidth, laneBottomY)
        ..lineTo(laneTopX + laneTopWidth, laneTopY)
        ..lineTo(size.width, 0)
        ..close(),
      Paint()..color = const Color(0xFF334155),
    );

    // Center seam (faint).
    final seamPaint = Paint()
      ..color = const Color(0xFFB45309).withValues(alpha: 0.35)
      ..strokeWidth = 1.0;
    canvas.drawLine(
      Offset(size.width / 2, laneBottomY),
      Offset(size.width / 2, laneTopY),
      seamPaint,
    );

    // Foul line.
    canvas.drawRect(
      Rect.fromLTWH(laneBottomX, laneBottomY - 4, laneBottomWidth, 4),
      Paint()..color = const Color(0xFFEF4444),
    );

    // X aim marker on the foul line.
    if (aimingX) {
      final xPos = laneBottomX + laneBottomWidth * ballX;
      canvas.drawCircle(
        Offset(xPos, laneBottomY - 8),
        8,
        Paint()
          ..color = const Color(0xFFFBBF24)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    // Pins (back to front for proper z-order).
    final pinR = size.shortestSide * 0.018;
    final sortedPins = [...pins]..sort((a, b) => a.y.compareTo(b.y));
    for (final p in sortedPins) {
      if (p.x < -1 || p.y < -1) continue;
      final scale = 0.7 + (1 - p.y) * 0.6;
      final pr = pinR * scale;
      final laneXAtY = _laneXAt(size, p.y);
      final laneCenterX = size.width / 2;
      final pinPx = laneCenterX + (p.x - 0.5) * laneXAtY;
      final pinPy = size.height - (1 - p.y) * (size.height - laneTopY);
      // Shadow.
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(pinPx + 1, pinPy + pr * 0.5 + 1),
          width: pr * 1.4,
          height: pr * 0.4,
        ),
        Paint()..color = Colors.black.withValues(alpha: 0.3),
      );
      if (!p.fallen) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(pinPx, pinPy),
              width: pr * 1.4,
              height: pr * 2,
            ),
            const Radius.circular(3),
          ),
          Paint()..color = Colors.white,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(pinPx, pinPy + pr * 0.5),
              width: pr * 1.4,
              height: pr * 0.5,
            ),
            const Radius.circular(2),
          ),
          Paint()..color = const Color(0xFFEF4444),
        );
      } else {
        final fall = (p.fallT).clamp(0.0, 1.0);
        canvas.save();
        canvas.translate(pinPx, pinPy + pr * 0.5);
        canvas.rotate(fall * pi / 2);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: pr * 2,
              height: pr * 1.4,
            ),
            const Radius.circular(3),
          ),
          Paint()..color = Colors.white,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(pr * 0.3, 0),
              width: pr * 1.2,
              height: pr * 0.5,
            ),
            const Radius.circular(2),
          ),
          Paint()..color = const Color(0xFFEF4444),
        );
        canvas.restore();
      }
    }

    // Ball.
    final ballPx = laneBottomX + laneBottomWidth * ballX;
    final ballPy = laneBottomY - (1 - ballY) * (laneBottomY - laneTopY);
    final ballR = size.shortestSide * 0.035;
    canvas.drawCircle(
      Offset(ballPx + 1, ballPy + 2),
      ballR,
      Paint()..color = Colors.black.withValues(alpha: 0.4),
    );
    canvas.drawCircle(
      Offset(ballPx, ballPy),
      ballR,
      Paint()..color = const Color(0xFF1E293B),
    );
    canvas.drawCircle(
      Offset(ballPx - ballR * 0.3, ballPy - ballR * 0.3),
      ballR * 0.45,
      Paint()..color = Colors.white.withValues(alpha: 0.25),
    );
    // Finger holes.
    canvas.drawCircle(
      Offset(ballPx - ballR * 0.25, ballPy - ballR * 0.15),
      ballR * 0.12,
      Paint()..color = Colors.black,
    );
    canvas.drawCircle(
      Offset(ballPx + ballR * 0.25, ballPy - ballR * 0.15),
      ballR * 0.12,
      Paint()..color = Colors.black,
    );
    canvas.drawCircle(
      Offset(ballPx, ballPy + ballR * 0.3),
      ballR * 0.12,
      Paint()..color = Colors.black,
    );

    // Spin aim line.
    if (spinAiming && spinOrigin != null) {
      final origin = spinOrigin!;
      canvas.drawLine(
        origin,
        spinCurrent,
        Paint()
          ..color = const Color(0xFFFBBF24).withValues(alpha: 0.8)
          ..strokeWidth = 3,
      );
    }

    // Particles.
    for (final pt in particles) {
      final cx = laneBottomX + laneBottomWidth * pt.x;
      final cy = size.height - (1 - pt.y) * (size.height - laneTopY);
      final alpha = (pt.life / 0.5).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(cx, cy),
        2,
        Paint()..color = const Color(0xFFFEF3C7).withValues(alpha: alpha),
      );
    }

    // Floaters.
    for (final f in floaters) {
      final alpha = (f.life / 1.2).clamp(0.0, 1.0);
      final tp = TextPainter(
        text: TextSpan(
          text: f.text,
          style: TextStyle(
            color: f.color.withValues(alpha: alpha),
            fontSize: 22,
            fontWeight: FontWeight.w900,
            shadows: const [
              Shadow(blurRadius: 4, color: Colors.black54),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          size.width * f.x - tp.width / 2,
          size.height * f.y - tp.height / 2,
        ),
      );
    }
  }

  double _laneXAt(Size size, double yFrac) {
    final laneTopWidth = size.width * 0.55;
    final laneBottomWidth = size.width * 0.95;
    return laneTopWidth + (laneBottomWidth - laneTopWidth) * yFrac;
  }

  @override
  bool shouldRepaint(_BowlingPainter old) =>
      old.ballX != ballX ||
      old.ballY != ballY ||
      old.pins != pins ||
      old.floaters != floaters ||
      old.particles != particles ||
      old.aimingX != aimingX ||
      old.spinAiming != spinAiming ||
      old.spinOrigin != spinOrigin ||
      old.spinCurrent != spinCurrent;
}
