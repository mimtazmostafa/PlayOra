import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../game_widgets.dart';
import '../mini_game.dart';

/// **Darts Club** — drag-and-flick darts (arcade scoring).
///
/// 10 darts per round. Player drags from anywhere on the canvas and
/// flicks toward the board; releasing with enough velocity launches a
/// dart along the flick vector. A wind indicator nudges the dart
/// mid-flight. While the dart is in the air an animated reticle
/// circles the board centre (decorative). Score tiers by ring
/// distance from centre:
///
///   50  bullseye  (< 5 % radius)
///   25  inner bull (< 12 % radius)
///   10  inner ring (< 35 %)
///    8  ring 2   (< 55 %)
///    6  ring 3   (< 72 %)
///    4  ring 4   (< 86 %)
///    2  outer ring
///    0  missed (bounced off board)
///
/// After the 10th dart lands, a "Play Again" prompt lets the player
/// reset without leaving the screen.
class DartsClubGame extends MiniGame {
  const DartsClubGame({super.key, required super.callbacks});

  @override
  State<DartsClubGame> createState() => _DartsClubState();
}

class _DartsClubState extends MiniGameState<DartsClubGame>
    with SingleTickerProviderStateMixin {
  static const int _maxDarts = 10;

  // Tunables.
  static const double _minThrowSpeed = 200;   // px/s
  static const double _maxThrowSpeed = 800;   // px/s (clamped)
  static const double _dartFlightTimeout = 1.6; // s — fallback if dart never lands
  static const double _windMin = 20;
  static const double _windMax = 100;

  late final Ticker _ticker;
  final Random _rng = Random();

  int _dartsThrown = 0;
  int _score = 0;

  final List<_Dart> _darts = [];
  final List<_FlyingDart> _flyingDarts = [];
  final List<_FloatingText> _floaters = [];

  DateTime _lastTick = DateTime.now();
  double _screenW = 0;
  double _screenH = 0;
  Offset _boardCenter = Offset.zero;
  double _boardRadius = 0;

  // Reticle animation (while a dart is in flight).
  double _reticleT = 0;
  double _reticleRadius = 18;

  // Wind (applied to in-flight darts only).
  double _windDir = 0;
  double _windStrength = 40;
  bool _windPulse = false;

  // Drag state.
  Offset? _dragOrigin;
  Offset _dragCurrent = Offset.zero;

  // Lifecycle flags.
  bool _roundOver = false;
  bool _gameOverReported = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reportScore(_score);
      _reportStats();
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  // ── Wind ──────────────────────────────────────────────────────
  void _rerollWind() {
    _windDir = _rng.nextDouble() * 2 * pi;
    _windStrength = _windMin + _rng.nextDouble() * (_windMax - _windMin);
    _windPulse = true;
    Future.delayed(const Duration(milliseconds: 220), () {
      if (mounted) setState(() => _windPulse = false);
    });
  }

  // ── Per-frame tick ────────────────────────────────────────────
  void _tick(Duration _) {
    if (!mounted) return;
    if (_roundOver) {
      if (_ticker.isActive) _ticker.stop();
      return;
    }
    final now = DateTime.now();
    final dt = (now.difference(_lastTick).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _lastTick = now;
    _reticleT += dt;
    _reticleRadius = 14 + sin(_reticleT * 2) * 4;

    setState(() {
      _stepFlight(dt);
      _stepFloaters(dt);
      _reportStats();

      if (_dartsThrown >= _maxDarts &&
          _flyingDarts.isEmpty &&
          !_gameOverReported) {
        _roundOver = true;
        _gameOverReported = true;
        Future.delayed(const Duration(milliseconds: 700), () {
          if (mounted) {
            reportScore(_score);
            reportStats('Final: $_score pts');
            reportGameOver();
          }
        });
      }
    });
  }

  void _stepFlight(double dt) {
    final landed = <_FlyingDart>[];
    for (final d in _flyingDarts) {
      // Apply wind acceleration to in-flight dart.
      d.vx += cos(_windDir) * _windStrength * dt;
      d.vy += sin(_windDir) * _windStrength * dt;
      d.x += d.vx * dt;
      d.y += d.vy * dt;
      d.t += dt;

      final rel = Offset(d.x, d.y) - _boardCenter;
      final dist = rel.distance;
      final timedOut = d.t > _dartFlightTimeout;
      final hitBoard = dist <= _boardRadius - 4;
      if (hitBoard || timedOut) {
        // Snap to board surface (or centre if dart hit dead-on). When
        // timed out without hitting, the dart drifts further out — the
        // nearest point on the board is its landing spot.
        if (dist <= 0.0001) {
          d.x = _boardCenter.dx;
          d.y = _boardCenter.dy;
        } else if (dist <= _boardRadius) {
          // Already on the board — leave in place.
        } else {
          d.x = _boardCenter.dx + rel.dx / dist * _boardRadius;
          d.y = _boardCenter.dy + rel.dy / dist * _boardRadius;
        }
        landed.add(d);
      }
    }
    for (final d in landed) {
      _flyingDarts.remove(d);
      _landDart(d);
    }

    // Landed-dart settle animation.
    for (final d in _darts) {
      d.settleT = (d.settleT + dt * 4).clamp(0.0, 1.0);
    }
  }

  void _landDart(_FlyingDart d) {
    final p = Offset(d.x, d.y);
    final dist = (p - _boardCenter).distance;
    final points = _scoreFor(dist);
    _dartsThrown += 1;
    _score += points;
    _darts.add(_Dart(
      position: p,
      angle: d.launchAngle, // Capture throw direction, not wind-blown velocity.
      points: points,
    ));
    _floaters.add(_FloatingText(
      x: p.dx,
      y: p.dy - 50,
      text: points == 50
          ? 'BULLSEYE!'
          : points == 25
              ? 'INNER BULL'
              : points == 0
                  ? 'MISS'
                  : '+$points',
      color: points >= 25
          ? const Color(0xFFFFC837)
          : points == 0
              ? const Color(0xFFEF4444)
              : Colors.white,
    ));
    if (points == 50) {
      haptic(HapticFeedbackType.heavy);
    } else if (points >= 25) {
      haptic(HapticFeedbackType.medium);
    } else if (points >= 6) {
      haptic(HapticFeedbackType.selection);
    } else {
      haptic(HapticFeedbackType.light);
    }
  }

  void _stepFloaters(double dt) {
    for (final f in _floaters) {
      f.y -= 36 * dt;
      f.life -= dt;
    }
    _floaters.removeWhere((f) => f.life <= 0);
  }

  void _reportStats() {
    if (_flyingDarts.isNotEmpty) {
      reportStats('Darts $_dartsThrown/$_maxDarts  •  In flight');
    } else if (!_roundOver) {
      reportStats(
        'Darts $_dartsThrown/$_maxDarts  •  Wind ${_windStrength.round()}',
      );
    }
  }

  int _scoreFor(double dist) {
    final r = _boardRadius;
    if (dist < r * 0.05) return 50;
    if (dist < r * 0.12) return 25;
    if (dist < r * 0.35) return 10;
    if (dist < r * 0.55) return 8;
    if (dist < r * 0.72) return 6;
    if (dist < r * 0.86) return 4;
    if (dist < r) return 2;
    return 0;
  }

  // ── Drag handlers ─────────────────────────────────────────────
  void _onPanStart(DragStartDetails d) {
    if (_roundOver) return;
    _dragOrigin = d.localPosition;
    _dragCurrent = d.localPosition;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_roundOver) return;
    _dragCurrent = d.localPosition;
  }

  void _onPanEnd(DragEndDetails d) {
    if (_roundOver || _dragOrigin == null) {
      _dragOrigin = null;
      return;
    }
    final velocity = d.velocity.pixelsPerSecond;
    final speed = velocity.distance;
    if (speed < _minThrowSpeed) {
      // Cancelled — too gentle.
      _dragOrigin = null;
      return;
    }
    final dirX = velocity.dx / speed;
    final dirY = velocity.dy / speed;
    final clampedSpeed = speed.clamp(_minThrowSpeed, _maxThrowSpeed);
    // Dart spawns at the throw line (bottom of canvas), biased back
    // from the flick direction so it visually arcs upward toward the
    // board.
    final spawnY = _screenH - 30;
    final spawnX = _screenW / 2 - dirX * 200;
    // Preserve the throw angle so the dart sprite faces the throw
    // direction (not the wind-blown velocity).
    final launchAngle = atan2(dirY, dirX);
    _flyingDarts.add(_FlyingDart(
      x: spawnX,
      y: spawnY,
      vx: dirX * clampedSpeed,
      vy: dirY * clampedSpeed,
      launchAngle: launchAngle,
    ));
    _dragOrigin = null;
    _rerollWind();
    haptic(HapticFeedbackType.selection);
  }

  // ── Round reset ───────────────────────────────────────────────
  void _resetRound() {
    setState(() {
      _dartsThrown = 0;
      _score = 0;
      _darts.clear();
      _flyingDarts.clear();
      _floaters.clear();
      _roundOver = false;
      _gameOverReported = false;
      _dragOrigin = null;
      _rerollWind();
    });
    reportScore(_score);
    _reportStats();
  }

  // ── Build ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        _screenW = c.maxWidth;
        _screenH = c.maxHeight;
        _boardCenter = Offset(_screenW / 2, _screenH * 0.42);
        _boardRadius = min(_screenW, _screenH) * 0.36;
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFA073FF), Color(0xFF6D28D9)],
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: _onPanStart,
                  onPanUpdate: _onPanUpdate,
                  onPanEnd: _onPanEnd,
                  child: CustomPaint(
                    painter: _DartboardPainter(
                      center: _boardCenter,
                      radius: _boardRadius,
                      darts: _darts,
                      flyingDarts: _flyingDarts,
                      floaters: _floaters,
                      reticleT: _reticleT,
                      reticleRadius: _reticleRadius,
                      windDir: _windDir,
                      windStrength: _windStrength,
                      windPulse: _windPulse,
                      dragOrigin: _dragOrigin,
                      dragCurrent: _dragCurrent,
                      screenH: _screenH,
                    ),
                  ),
                ),
              ),
              // Top HUD removed — host GameContainerScreen provides it.
              Positioned(
                bottom: 24,
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
                      _roundOver
                          ? 'Round complete'
                          : _flyingDarts.isNotEmpty
                              ? 'Dart in flight…'
                              : 'Drag & flick to throw',
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
              if (_roundOver)
                Positioned(
                  bottom: 80,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: FilledButton.icon(
                      onPressed: _resetRound,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Play again'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFFC837),
                        foregroundColor: const Color(0xFF1A1625),
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

// ─────────────────────────────────────────────────────────────
// Dart models
// ─────────────────────────────────────────────────────────────

class _Dart {
  _Dart({
    required this.position,
    required this.angle,
    required this.points,
  }) : settleT = 0;
  final Offset position;
  final double angle;
  final int points;
  double settleT;
}

class _FlyingDart {
  _FlyingDart({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.launchAngle,
  })  : t = 0,
        settled = false;
  double x;
  double y;
  double vx;
  double vy;
  /// Throw direction captured at launch — used for sprite rotation
  /// even though wind drifts the velocity in flight.
  final double launchAngle;
  double t;
  bool settled;
}

class _FloatingText {
  _FloatingText({
    required this.x,
    required this.y,
    required this.text,
    required this.color,
  }) : life = 1.0;
  final double x;
  double y;
  final String text;
  final Color color;
  double life;
}

// ─────────────────────────────────────────────────────────────
// HUD chips
// ─────────────────────────────────────────────────────────────


// ─────────────────────────────────────────────────────────────
// Painter
// ─────────────────────────────────────────────────────────────

class _DartboardPainter extends CustomPainter {
  _DartboardPainter({
    required this.center,
    required this.radius,
    required this.darts,
    required this.flyingDarts,
    required this.floaters,
    required this.reticleT,
    required this.reticleRadius,
    required this.windDir,
    required this.windStrength,
    required this.windPulse,
    required this.dragOrigin,
    required this.dragCurrent,
    required this.screenH,
  });

  final Offset center;
  final double radius;
  final List<_Dart> darts;
  final List<_FlyingDart> flyingDarts;
  final List<_FloatingText> floaters;
  final double reticleT;
  final double reticleRadius;
  final double windDir;
  final double windStrength;
  final bool windPulse;
  final Offset? dragOrigin;
  final Offset dragCurrent;
  final double screenH;

  @override
  void paint(Canvas canvas, Size size) {
    _drawBoard(canvas);
    _drawReticle(canvas);
    _drawDragGuide(canvas);
    _drawWindIndicator(canvas, size);
    _drawThrowLine(canvas, size);
    for (final d in darts) {
      _drawDart(canvas, d.position, d.angle, d.settleT);
    }
    for (final d in flyingDarts) {
      _drawDart(
        canvas,
        Offset(d.x, d.y),
        d.launchAngle,
        (d.t * 4).clamp(0.0, 1.0),
      );
    }
    _drawFloaters(canvas);
  }

  void _drawBoard(Canvas canvas) {
    // Outer wood ring.
    canvas.drawCircle(
      center,
      radius + 12,
      Paint()..color = const Color(0xFF78350F),
    );
    // Number-ring backing.
    canvas.drawCircle(
      center,
      radius + 8,
      Paint()..color = Colors.black,
    );
    // Number-ring segments (alternating cream/black).
    const segmentCount = 20;
    for (var i = 0; i < segmentCount; i++) {
      final start = -pi / 2 + (i / segmentCount) * 2 * pi;
      final sweep = (2 * pi) / segmentCount;
      final paint = Paint()
        ..color = i.isEven ? const Color(0xFFFEF3C7) : const Color(0xFF1F2937);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius + 4),
        start,
        sweep,
        true,
        paint,
      );
    }
    // Score segments (inner ring).
    const scoreColors = [
      Color(0xFFE11D48),
      Color(0xFFFEF3C7),
      Color(0xFFE11D48),
      Color(0xFFFEF3C7),
    ];
    for (var i = 0; i < segmentCount; i++) {
      final start = -pi / 2 + (i / segmentCount) * 2 * pi;
      final sweep = (2 * pi) / segmentCount;
      final paint = Paint()..color = scoreColors[i % scoreColors.length];
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius * 0.92),
        start,
        sweep,
        true,
        paint,
      );
    }
    canvas.drawCircle(
      center,
      radius * 0.72,
      Paint()..color = const Color(0xFFFEF3C7),
    );
    _drawStrokeCircle(canvas, center, radius * 0.42, radius * 0.05,
        const Color(0xFFE11D48));
    _drawStrokeCircle(canvas, center, radius * 0.36, radius * 0.05,
        const Color(0xFFE11D48));
    canvas.drawCircle(center, radius * 0.12,
        Paint()..color = const Color(0xFF30D158));
    canvas.drawCircle(center, radius * 0.06,
        Paint()..color = const Color(0xFFE11D48));

    // Wireframe segment dividers.
    final divider = Paint()
      ..color = Colors.black.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (var i = 0; i < segmentCount; i++) {
      final angle = -pi / 2 + (i / segmentCount) * 2 * pi;
      canvas.drawLine(
        center,
        center + Offset.fromDirection(angle, radius),
        divider,
      );
    }
  }

  void _drawStrokeCircle(
      Canvas canvas, Offset c, double r, double w, Color color) {
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = w,
    );
  }

  void _drawReticle(Canvas canvas) {
    if (flyingDarts.isEmpty) return;
    final phase = reticleT * 2.2;
    final cx = center.dx + cos(phase) * reticleRadius;
    final cy = center.dy + sin(phase) * reticleRadius;
    final reticleColor = const Color(0xFFFFC837);
    final stroke = Paint()
      ..color = reticleColor
      ..strokeWidth = 2.4;
    canvas.drawLine(Offset(cx - 8, cy), Offset(cx + 8, cy), stroke);
    canvas.drawLine(Offset(cx, cy - 8), Offset(cx, cy + 8), stroke);
    canvas.drawCircle(
      Offset(cx, cy),
      10,
      Paint()
        ..color = reticleColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  void _drawDragGuide(Canvas canvas) {
    final origin = dragOrigin;
    if (origin == null) return;
    final tip = dragCurrent;
    canvas.drawLine(
      origin,
      tip,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.55)
        ..strokeWidth = 2.5,
    );
    final dir = tip - origin;
    final d = dir.distance;
    if (d <= 4) return;
    final n = dir / d;
    final perp = Offset(-n.dy, n.dx);
    final head = tip;
    final back = tip - n * 12;
    final p1 = back + perp * 6;
    final p2 = back - perp * 6;
    final path = Path()
      ..moveTo(head.dx, head.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..close();
    canvas.drawPath(
      path,
      Paint()..color = Colors.white.withValues(alpha: 0.7),
    );
  }

  void _drawWindIndicator(Canvas canvas, Size size) {
    // Wind indicator floats in the top-right corner, well clear of
    // the dartboard so its label never lands on top of the dart pile.
    final windOrigin = Offset(size.width - 60, 70);
    final windLen = 24 + windStrength / 3;
    final windTip = windOrigin + Offset.fromDirection(windDir, windLen);
    final windColor = windStrength > 60
        ? const Color(0xFFEF4444)
        : const Color(0xFF60A5FA);
    canvas.drawCircle(
      windOrigin,
      18,
      Paint()..color = Colors.black.withValues(alpha: 0.5),
    );
    canvas.drawLine(
      windOrigin,
      windTip,
      Paint()
        ..color = windColor.withValues(alpha: windPulse ? 1.0 : 0.75)
        ..strokeWidth = windPulse ? 4.0 : 2.6,
    );
    final wtp = TextPainter(
      text: TextSpan(
        text: 'WIND ${windStrength.round()}',
        style: TextStyle(
          color: windColor,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    wtp.paint(
      canvas,
      Offset(windOrigin.dx - wtp.width / 2, windOrigin.dy + 24),
    );
  }

  void _drawThrowLine(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(0, screenH - 30),
      Offset(size.width, screenH - 30),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.25)
        ..strokeWidth = 1.5,
    );
  }

  void _drawDart(Canvas canvas, Offset p, double angle, double t) {
    canvas.save();
    canvas.translate(p.dx, p.dy);
    canvas.rotate(angle);
    final scale = 0.85 + 0.15 * t;
    canvas.scale(scale, scale);
    final shaftRect = Rect.fromCenter(
      center: const Offset(0, -12),
      width: 4,
      height: 22,
    );
    // Dart shaft (silver gradient).
    canvas.drawRRect(
      RRect.fromRectAndRadius(shaftRect, const Radius.circular(2)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFE5E7EB), Color(0xFF6B7280)],
        ).createShader(shaftRect),
    );
    // Gold tip.
    final tip = Path()
      ..moveTo(0, 8)
      ..lineTo(-3, 2)
      ..lineTo(3, 2)
      ..close();
    canvas.drawPath(tip, Paint()..color = const Color(0xFFFFC837));
    // Red flight.
    final flight = Path()
      ..moveTo(-5, -22)
      ..lineTo(5, -22)
      ..lineTo(3, -34)
      ..lineTo(0, -38)
      ..lineTo(-3, -34)
      ..close();
    canvas.drawPath(flight, Paint()..color = const Color(0xFFE11D48));
    canvas.restore();
  }

  void _drawFloaters(Canvas canvas) {
    for (final f in floaters) {
      final alpha = f.life.clamp(0.0, 1.0);
      final tp = TextPainter(
        text: TextSpan(
          text: f.text,
          style: TextStyle(
            color: f.color.withValues(alpha: alpha),
            fontSize: 18,
            fontWeight: FontWeight.w900,
            shadows: const [
              Shadow(blurRadius: 4, color: Colors.black54),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(f.x - tp.width / 2, f.y - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_DartboardPainter old) =>
      old.darts != darts ||
      old.flyingDarts != flyingDarts ||
      old.floaters != floaters ||
      old.reticleT != reticleT ||
      old.reticleRadius != reticleRadius ||
      old.windDir != windDir ||
      old.windStrength != windStrength ||
      old.windPulse != windPulse ||
      old.dragOrigin != dragOrigin ||
      old.dragCurrent != dragCurrent;
}
