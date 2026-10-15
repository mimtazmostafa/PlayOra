import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../game_widgets.dart';
import '../mini_game.dart';

/// Soccer Hero — 2D penalty shootout.
///
/// Top-down view of a green football pitch:
///   * Alternating light/dark grass stripes run vertically (the
///     classic stadium pattern).
///   * Goal area + penalty arc marked in white paint at the top.
///   * Dynamic 3-post goal frame at the top with a hanging net.
///   * Animated goalkeeper sprite patrols left↔right along the goal
///     line; dives on each shot.
///   * Drag-and-flick shot: pull-back vector → aim direction + curve.
///     The trajectory is a [Path] sampled each frame and drawn as a
///     dotted preview during drag.
///   * On goal: net-bulge animation + confetti/star burst + "GOAL!
///     +100" floater + heavy haptic.
///   * On save: ball deflects with physics + bounce + light haptic.
///
/// Class + ctor signatures stay byte-identical so the dispatcher
/// routing in `games_dispatcher.dart` keeps working.
class SoccerHeroGame extends MiniGame {
  const SoccerHeroGame({super.key, required super.callbacks});

  @override
  State<SoccerHeroGame> createState() => _State();
}

class _State extends MiniGameState<SoccerHeroGame>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final Random _rng = Random();
  DateTime _last = DateTime.now();

  static const int _maxShots = 5;

  int _score = 0;
  int _shotsTaken = 0;
  int _goals = 0;
  bool _gameOver = false;

  // ─── Ball state ────────────────────────────────────────────────
  /// Normalised ball position (0..1 of canvas). The ball rests at
  /// (0.5, ~0.86) at the kick spot.
  double _ballX = 0.5;
  double _ballY = 0.86;

  // Drag + shot state.
  bool _ballFlying = false;
  bool _ballSaved = false;
  bool _ballGoal = false;
  double _ballT = 0;
  Offset _ballStart = Offset.zero;
  Offset _ballEnd = Offset.zero;
  Offset _ballControl = Offset.zero; // Bezier control point (curve)
  double _ballSpin = 0;
  double _ballSpinV = 0;
  // After goal/save the ball continues with physics-driven motion.
  Offset _ballVel = Offset.zero;

  // ─── Goalkeeper state ──────────────────────────────────────────
  /// Lateral position along the goal mouth, 0..1.
  double _keeperX = 0.5;
  double _keeperPatrolT = 0;
  double _diveTargetX = 0.5;
  bool _keeperDiving = false;
  double _keeperDiveProgress = 0;

  // ─── Drag preview state ────────────────────────────────────────
  Offset? _dragStart;
  Offset? _dragCurrent;
  bool _dragging = false;

  // ─── VFX ───────────────────────────────────────────────────────
  final List<_Floater> _floaters = [];
  final List<_Confetto> _confetti = [];
  final List<_StarBurst> _stars = [];

  // ─── Goal / net animation ──────────────────────────────────────
  /// 0..1 amplitude of the net "bulge" inward at the impact point.
  double _netBulge = 0;
  double _netBulgeX = 0.5;

  // ─── Screen shake ──────────────────────────────────────────────
  double _shakeTime = 0;

  // ─── Geometry (set in build via LayoutBuilder) ─────────────────
  Size _canvasSize = Size.zero;
  static const double _goalAreaTop = 0.10;
  static const double _goalAreaBottom = 0.34;
  static const double _goalMouthY = 0.18; // y where the goal mouth sits

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reportScore(_score);
      reportStats('Shots 0/$_maxShots  •  Goals 0');
    });
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
    if (dt <= 0) return;

    setState(() {
      // ─── Keeper patrol ────────────────────────────────────────
      // Sin-wave patrol across the goal mouth. Speed ramps each
      // shot so the keeper reads harder to beat.
      _keeperPatrolT += dt * (1.2 + _shotsTaken * 0.18);
      if (!_keeperDiving) {
        _keeperX = 0.5 + 0.42 * sin(_keeperPatrolT);
      } else {
        // Diving interpolation toward the predicted x.
        _keeperDiveProgress = (_keeperDiveProgress + dt * 4).clamp(0.0, 1.0);
        final t = Curves.easeOutCubic.transform(_keeperDiveProgress);
        _keeperX = _lerpDouble(_keeperX, _diveTargetX, t);
      }

      // ─── Ball flight ──────────────────────────────────────────
      if (_ballFlying) {
        if (!_ballSaved && !_ballGoal) {
          _ballT += dt * 1.6;
          if (_ballT >= 1) {
            _resolveShot();
          }
        } else {
          // After resolution: physics-driven motion (post-goal tumble
          // or post-save bounce).
          _ballVel = _ballVel + const Offset(0, 900) * dt;
          _ballX += _ballVel.dx / _canvasSize.width * dt;
          _ballY += _ballVel.dy / _canvasSize.height * dt;
          _ballSpin += _ballSpinV * dt;
        }
        if (_ballX < -0.05 || _ballX > 1.05 || _ballY > 1.1) {
          _ballFlying = false;
        }
      }

      // ─── VFX decay ────────────────────────────────────────────
      if (_shakeTime > 0) {
        _shakeTime = (_shakeTime - dt).clamp(0.0, 99.0);
      }
      if (_netBulge > 0) {
        _netBulge = (_netBulge - dt * 1.6).clamp(0.0, 1.0);
      }
      for (final f in _floaters) {
        f.y -= 40 * dt;
        f.life -= dt;
      }
      _floaters.removeWhere((f) => f.life <= 0);
      for (final c in _confetti) {
        c.vel = c.vel + const Offset(0, 600) * dt;
        c.pos = c.pos + c.vel * dt;
        c.rot += c.rotV * dt;
        c.life -= dt;
      }
      _confetti.removeWhere((c) => c.life <= 0);
      for (final s in _stars) {
        s.r += 80 * dt;
        s.life -= dt;
      }
      _stars.removeWhere((s) => s.life <= 0);
    });
  }

  // ─── Drag handlers ─────────────────────────────────────────────
  void _onPanStart(DragStartDetails d) {
    if (_ballFlying || _gameOver) return;
    final py = d.localPosition.dy / _canvasSize.height;
    // Only allow drag starting near the ball (bottom area).
    if (py < 0.65) return;
    _dragging = true;
    _dragStart = d.localPosition;
    _dragCurrent = d.localPosition;
    haptic(HapticFeedbackType.selection);
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (!_dragging) return;
    _dragCurrent = d.localPosition;
  }

  void _onPanEnd(DragEndDetails d) {
    if (!_dragging) return;
    _dragging = false;
    final start = _dragStart;
    final end = _dragCurrent;
    _dragStart = null;
    _dragCurrent = null;
    if (start == null || end == null) return;
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    if (dx.abs() < 20 && dy.abs() < 20) return;

    final size = _canvasSize;
    // Direction: shot goes opposite to drag (pull-back-and-release).
    final aimX = (size.width / 2 - dx * 2.2).clamp(60.0, size.width - 60);
    final aimY =
        (size.height * _goalMouthY - dy * 0.5).clamp(40.0, size.height * 0.5);
    // Curve: side-component of drag creates mid-flight curve via
    // Bezier control point offset.
    final curve = dx / size.width;
    final controlX = (size.width / 2 - dx * 1.0).clamp(40.0, size.width - 40);
    final controlY = (size.height * 0.55 - dy * 0.2)
        .clamp(size.height * 0.4, size.height * 0.7);

    setState(() {
      _ballFlying = true;
      _ballGoal = false;
      _ballSaved = false;
      _ballT = 0;
      _ballStart = Offset(size.width * 0.5, size.height * 0.86);
      _ballEnd = Offset(aimX, aimY);
      _ballControl = Offset(controlX, controlY);
      _ballVel = Offset.zero;
      _ballSpin = 0;
      _ballSpinV = 8 + curve.abs() * 6;
      // Keeper dives toward predicted ball end position.
      _diveTargetX = aimX / size.width;
      _keeperDiving = true;
      _keeperDiveProgress = 0;
      haptic(HapticFeedbackType.medium);
    });
  }

  // ─── Resolve shot (collision detection) ─────────────────────────
  void _resolveShot() {
    _ballT = 1;
    final w = _canvasSize.width;
    final size = _canvasSize;

    // Ball position at moment of resolution (top of arc).
    final ballEndX = _ballEnd.dx;
    final ballEndY = _ballEnd.dy;

    // Keeper hitbox at impact.
    final keeperWidth = w * 0.18;
    final keeperHeight = size.height * 0.16;
    final keeperCenterX = w * _keeperX;
    final keeperY = size.height * _goalMouthY;
    final keeperLeft = keeperCenterX - keeperWidth / 2;
    final keeperRight = keeperCenterX + keeperWidth / 2;
    final keeperTop = keeperY - keeperHeight / 2;
    final keeperBottom = keeperY + keeperHeight / 2;

    // Was the keeper's dive on the same side the ball ended up?
    final keeperCovers = ballEndX >= keeperLeft && ballEndX <= keeperRight &&
        ballEndY >= keeperTop && ballEndY <= keeperBottom;

    // Within goal area?
    final goalLeft = w * 0.12;
    final goalRight = w * 0.88;
    final goalTopPx = size.height * _goalAreaTop;
    final goalBottomPx = size.height * _goalAreaBottom;
    final inGoalArea = ballEndX >= goalLeft &&
        ballEndX <= goalRight &&
        ballEndY >= goalTopPx &&
        ballEndY <= goalBottomPx;

    if (keeperCovers) {
      _triggerSave();
    } else if (inGoalArea) {
      _triggerGoal();
    } else {
      // Miss (wide / over). Treat as save: ball tumbles away.
      _triggerMiss();
    }
  }

  void _triggerGoal() {
    _ballGoal = true;
    _goals += 1;
    _score += 100;
    _netBulge = 1;
    _netBulgeX = _ballEnd.dx / _canvasSize.width;
    _shakeTime = 0.45;
    // Confetti burst at the goal mouth.
    for (var i = 0; i < 28; i++) {
      final a = _rng.nextDouble() * 6.2831853;
      final v = 180 + _rng.nextDouble() * 240;
      _confetti.add(_Confetto(
        pos: Offset(_ballEnd.dx, _ballEnd.dy),
        vel: Offset(cos(a) * v, sin(a) * v - 200),
        rot: _rng.nextDouble() * 6.28,
        rotV: (_rng.nextDouble() - 0.5) * 14,
        life: 1.2 + _rng.nextDouble() * 0.5,
        color: _goalColors[_rng.nextInt(_goalColors.length)],
      ));
    }
    // Star burst.
    for (var i = 0; i < 5; i++) {
      _stars.add(_StarBurst(
        x: _ballEnd.dx + (_rng.nextDouble() - 0.5) * 60,
        y: _ballEnd.dy - 20 + (_rng.nextDouble() - 0.5) * 30,
        life: 0.7,
      ));
    }
    // Big "GOAL!" floater.
    _floaters.add(_Floater(
      x: _ballEnd.dx,
      y: _ballEnd.dy - 80,
      text: 'GOAL! +100',
      color: const Color(0xFF4CD171),
      life: 1.4,
      scale: 1.5,
      fontSize: 36,
    ));
    // Reset keeper to standing.
    _keeperDiving = false;
    _keeperDiveProgress = 0;
    haptic(HapticFeedbackType.heavy);
    _advanceShot();
  }

  void _triggerSave() {
    _ballSaved = true;
    // Deflect the ball back away from the keeper.
    final defX = (_ballEnd.dx - _canvasSize.width * _keeperX) * 1.2;
    final defY = _canvasSize.height * 0.18; // bounce downward
    _ballVel = Offset(defX, defY);
    _ballSpinV = -16;
    _floaters.add(_Floater(
      x: _ballEnd.dx,
      y: _ballEnd.dy - 40,
      text: 'SAVED',
      color: const Color(0xFFEF4444),
      life: 1.0,
      scale: 1.3,
      fontSize: 30,
    ));
    _shakeTime = 0.25;
    _keeperDiving = false;
    _keeperDiveProgress = 0;
    haptic(HapticFeedbackType.light);
    _advanceShot();
  }

  void _triggerMiss() {
    _ballSaved = true;
    _ballVel = Offset((_rng.nextDouble() - 0.5) * 280, -180);
    _ballSpinV = -8;
    _floaters.add(_Floater(
      x: _canvasSize.width / 2,
      y: _canvasSize.height * 0.32,
      text: 'MISS',
      color: const Color(0xFFF59E0B),
      life: 0.9,
      scale: 1.2,
      fontSize: 28,
    ));
    _keeperDiving = false;
    _keeperDiveProgress = 0;
    haptic(HapticFeedbackType.light);
    _advanceShot();
  }

  void _advanceShot() {
    _shotsTaken += 1;
    reportScore(_score);
    reportStats('Shots $_shotsTaken/$_maxShots  •  Goals $_goals');
    if (_shotsTaken >= _maxShots) {
      _gameOver = true;
      haptic(HapticFeedbackType.heavy);
      reportScore(_score);
      reportStats('Final: $_goals goals in $_shotsTaken shots');
      // Slight delay so the last goal/save VFX plays before overlay.
      Future.delayed(const Duration(milliseconds: 700), () {
        if (!mounted) return;
        reportGameOver();
      });
    } else {
      // Reset ball to kick spot after a brief delay.
      Future.delayed(const Duration(milliseconds: 900), () {
        if (!mounted) return;
        setState(() {
          _ballFlying = false;
          _ballX = 0.5;
          _ballY = 0.86;
        });
      });
    }
  }

  // ─── Build ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, c) {
        _canvasSize = Size(c.maxWidth, c.maxHeight);
        final shakeX = _shakeTime > 0
            ? (_rng.nextDouble() - 0.5) * 10 * _shakeTime
            : 0.0;
        final shakeY = _shakeTime > 0
            ? (_rng.nextDouble() - 0.5) * 4 * _shakeTime
            : 0.0;
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF86EFAC), Color(0xFF22C55E)],
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Transform.translate(
                  offset: Offset(shakeX, shakeY),
                  child: CustomPaint(
                    painter: _SoccerPainter(
                      ballX: _ballX,
                      ballY: _ballY,
                      ballFlying: _ballFlying,
                      ballSaved: _ballSaved,
                      ballT: _ballT,
                      ballStart: _ballStart,
                      ballEnd: _ballEnd,
                      ballControl: _ballControl,
                      ballSpin: _ballSpin,
                      dragging: _dragging,
                      dragStart: _dragStart,
                      dragCurrent: _dragCurrent,
                      keeperX: _keeperX,
                      keeperDiving: _keeperDiving,
                      netBulge: _netBulge,
                      netBulgeX: _netBulgeX,
                      floaters: _floaters,
                      confetti: _confetti,
                      stars: _stars,
                      size: _canvasSize,
                    ),
                  ),
                ),
              ),
              // Top HUD removed — host GameContainerScreen paints
              // the score / shots / goals chips on its own HUD bar.
              // Gesture detector layer.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: _onPanStart,
                  onPanUpdate: _onPanUpdate,
                  onPanEnd: _onPanEnd,
                ),
              ),
              // Bottom hint.
              Positioned(
                bottom: 24,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: _HintChip(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static double _lerpDouble(double a, double b, double t) => a + (b - a) * t;
}

// ─────────────────────────────────────────────────────────────────
// State helpers
// ─────────────────────────────────────────────────────────────────

class _Floater {
  _Floater({
    required this.x,
    required this.y,
    required this.text,
    required this.color,
    required this.life,
    this.scale = 1.0,
    this.fontSize = 28,
  });
  double x;
  double y;
  String text;
  Color color;
  double life;
  double scale;
  double fontSize;
}

class _Confetto {
  _Confetto({
    required this.pos,
    required this.vel,
    required this.rot,
    required this.rotV,
    required this.life,
    required this.color,
  });
  Offset pos;
  Offset vel;
  double rot;
  double rotV;
  double life;
  Color color;
}

class _StarBurst {
  _StarBurst({required this.x, required this.y, required this.life}) : r = 0;
  double x;
  double y;
  double life;
  double r;
}

const List<Color> _goalColors = [
  Color(0xFF4CD171),
  Color(0xFFFF6584),
  Color(0xFFFFC529),
  Color(0xFF60A5FA),
  Color(0xFFA855F7),
  Color(0xFF22D3EE),
];

// ─────────────────────────────────────────────────────────────────
// HUD widgets
// ─────────────────────────────────────────────────────────────────

// _TopHud and _HudPill removed — host GameContainerScreen owns the
// score / shots / goals chips via GameHudBar + reportScore/reportStats.

class _HintChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.18),
          width: 1.2,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.15),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.touch_app_rounded, color: Colors.white, size: 16),
          SizedBox(width: 6),
          Text(
            'PULL BACK + CURVE TO SHOOT',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Field + goal + ball painter
// ─────────────────────────────────────────────────────────────────

class _SoccerPainter extends CustomPainter {
  _SoccerPainter({
    required this.ballX,
    required this.ballY,
    required this.ballFlying,
    required this.ballSaved,
    required this.ballT,
    required this.ballStart,
    required this.ballEnd,
    required this.ballControl,
    required this.ballSpin,
    required this.dragging,
    required this.dragStart,
    required this.dragCurrent,
    required this.keeperX,
    required this.keeperDiving,
    required this.netBulge,
    required this.netBulgeX,
    required this.floaters,
    required this.confetti,
    required this.stars,
    required this.size,
  });
  final double ballX;
  final double ballY;
  final bool ballFlying;
  final bool ballSaved;
  final double ballT;
  final Offset ballStart;
  final Offset ballEnd;
  final Offset ballControl;
  final double ballSpin;
  final bool dragging;
  final Offset? dragStart;
  final Offset? dragCurrent;
  final double keeperX;
  final bool keeperDiving;
  final double netBulge;
  final double netBulgeX;
  final List<_Floater> floaters;
  final List<_Confetto> confetti;
  final List<_StarBurst> stars;
  final Size size;

  // Grass palette.
  static const Color _grassLight = Color(0xFF86EFAC);
  static const Color _grassDark = Color(0xFF22C55E);
  static const Color _grassShadow = Color(0xFF15803D);
  static const Color _lineWhite = Color(0xCCFFFFFF);

  @override
  void paint(Canvas canvas, Size s) {
    _paintPitch(canvas, s);
    _paintGoalArea(canvas, s);
    _paintGoalFrame(canvas, s);
    _paintNetBulge(canvas, s);
    _paintKeeper(canvas, s);
    _paintBallTrail(canvas, s);
    _paintDragPreview(canvas, s);
    _paintBall(canvas, s);
    _paintStars(canvas);
    _paintConfetti(canvas);
    _paintFloaters(canvas, s);
  }

  // ─── Pitch (alternating stripes + markings) ──────────────────
  void _paintPitch(Canvas canvas, Size s) {
    final w = s.width;
    final h = s.height;
    // Base solid color (fallback if gradient missed).
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = _grassLight,
    );
    // Vertical stripes (alternating light/dark).
    const stripeCount = 10;
    final stripeW = w / stripeCount;
    for (var i = 0; i < stripeCount; i++) {
      if (i.isOdd) {
        canvas.drawRect(
          Rect.fromLTWH(i * stripeW, 0, stripeW, h),
          Paint()..color = _grassDark.withValues(alpha: 0.55),
        );
      }
    }
    // Subtle vignette darkening toward the top so the goal reads.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0x33000000),
            Color(0x00000000),
            Color(0x33000000),
          ],
          stops: [0, 0.5, 1],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );
    // Field line: penalty box outline (top half).
    final linePaint = Paint()
      ..color = _lineWhite
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    // Goal-line at top.
    canvas.drawLine(
      Offset(w * 0.05, h * 0.10),
      Offset(w * 0.95, h * 0.10),
      linePaint,
    );
    // Penalty box outline.
    final penBox = Rect.fromLTWH(
      w * 0.22,
      h * 0.10,
      w * 0.56,
      h * 0.22,
    );
    canvas.drawRect(penBox, linePaint);
    // Goal area (small box).
    final goalBox = Rect.fromLTWH(
      w * 0.32,
      h * 0.10,
      w * 0.36,
      h * 0.10,
    );
    canvas.drawRect(goalBox, linePaint);
    // Penalty spot.
    canvas.drawCircle(
      Offset(w * 0.5, h * 0.24),
      4,
      Paint()..color = _lineWhite,
    );
    // Penalty arc (D).
    final arcPaint = Paint()
      ..color = _lineWhite
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(w * 0.5, h * 0.24), radius: h * 0.06),
      pi - 0.5,
      1.0,
      false,
      arcPaint,
    );
    // Center circle at kick spot (subtle).
    canvas.drawCircle(
      Offset(w * 0.5, h * 0.86),
      24,
      Paint()
        ..color = _lineWhite.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    canvas.drawCircle(
      Offset(w * 0.5, h * 0.86),
      3,
      Paint()..color = _lineWhite.withValues(alpha: 0.6),
    );
    // Side-line + bottom-line.
    canvas.drawLine(
      Offset(w * 0.05, h * 0.10),
      Offset(w * 0.05, h * 0.95),
      linePaint,
    );
    canvas.drawLine(
      Offset(w * 0.95, h * 0.10),
      Offset(w * 0.95, h * 0.95),
      linePaint,
    );
    canvas.drawLine(
      Offset(w * 0.05, h * 0.95),
      Offset(w * 0.95, h * 0.95),
      linePaint,
    );
  }

  // ─── Goal area + 6-yard box shading ──────────────────────────
  void _paintGoalArea(Canvas canvas, Size s) {
    final w = s.width;
    final h = s.height;
    // Soft shadow inside the goal area for depth.
    canvas.drawRect(
      Rect.fromLTWH(w * 0.22, h * 0.10, w * 0.56, h * 0.22),
      Paint()
        ..color = _grassShadow.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
  }

  // ─── Goal frame + net ─────────────────────────────────────────
  void _paintGoalFrame(Canvas canvas, Size s) {
    final w = s.width;
    final h = s.height;
    // Goal mouth geometry: posts at left/right, crossbar at top.
    final goalLeft = w * 0.30;
    final goalRight = w * 0.70;
    final goalTop = h * 0.08;
    final goalBottom = h * 0.18;
    final postW = 6.0;

    // Net background (white-ish with crosshatch).
    final netRect = Rect.fromLTRB(goalLeft, goalTop, goalRight, goalBottom);
    canvas.drawRect(
      netRect,
      Paint()..color = const Color(0xFFE2E8F0).withValues(alpha: 0.92),
    );
    // Net crosshatch lines.
    final netLinePaint = Paint()
      ..color = const Color(0xFF64748B).withValues(alpha: 0.5)
      ..strokeWidth = 0.9;
    const netStep = 12.0;
    // Vertical strands.
    for (var x = goalLeft + netStep; x < goalRight; x += netStep) {
      canvas.drawLine(
        Offset(x, goalTop),
        Offset(x, goalBottom),
        netLinePaint,
      );
    }
    // Horizontal strands.
    for (var y = goalTop + netStep; y < goalBottom; y += netStep) {
      canvas.drawLine(
        Offset(goalLeft, y),
        Offset(goalRight, y),
        netLinePaint,
      );
    }
    // Net depth shading — darker at the back.
    canvas.drawRect(
      netRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0x22000000),
            Color(0x44000000),
          ],
        ).createShader(netRect),
    );
    // Goal posts (white with red caps).
    _drawGoalPost(canvas, goalLeft - postW / 2, goalTop, postW,
        goalBottom - goalTop, leftPost: true);
    _drawGoalPost(canvas, goalRight - postW / 2, goalTop, postW,
        goalBottom - goalTop, leftPost: false);
    _drawGoalPost(canvas, goalLeft, goalTop - postW / 2,
        goalRight - goalLeft, postW, crossbar: true);
  }

  void _drawGoalPost(
    Canvas canvas,
    double x,
    double y,
    double w,
    double h, {
    bool leftPost = false,
    bool crossbar = false,
  }) {
    final rect = Rect.fromLTWH(x, y, w, h);
    // White body.
    canvas.drawRect(rect, Paint()..color = Colors.white);
    // Subtle shadow on the inside edge.
    final shadowPaint = Paint()
      ..color = const Color(0x55000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawRect(rect, shadowPaint);
    // Red cap on the top of each post (crossbar doesn't get one).
    if (!crossbar) {
      final cap = Rect.fromCenter(
        center: Offset(x + w / 2, y - 1.5),
        width: w + 2,
        height: 4,
      );
      canvas.drawRect(
        cap,
        Paint()..color = const Color(0xFFDC2626),
      );
    }
  }

  // ─── Net bulge on goal ────────────────────────────────────────
  void _paintNetBulge(Canvas canvas, Size s) {
    if (netBulge <= 0) return;
    final w = s.width;
    final h = s.height;
    final goalLeft = w * 0.30;
    final goalRight = w * 0.70;
    final goalBottom = h * 0.18;
    final cx = w * netBulgeX;
    final amp = netBulge * 14;
    // Draw a "pulled-in" net shape: arc bulging inward.
    final path = Path();
    final steps = 32;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final x = goalLeft + (goalRight - goalLeft) * t;
      final dist = (x - cx).abs() / ((goalRight - goalLeft) / 2);
      final localAmp = amp * (1 - dist * dist).clamp(0.0, 1.0);
      final y = goalBottom - localAmp;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.lineTo(goalRight, goalBottom);
    path.lineTo(goalLeft, goalBottom);
    path.close();
    final bulgePaint = Paint()
      ..color = const Color(0xFFE2E8F0).withValues(alpha: 0.55)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, bulgePaint);
    // Mesh lines along the bulge.
    final meshPaint = Paint()
      ..color = const Color(0xFF64748B).withValues(alpha: 0.7)
      ..strokeWidth = 1.0;
    for (var i = 1; i < 6; i++) {
      final t = i / 6;
      final x = goalLeft + (goalRight - goalLeft) * t;
      final dist = (x - cx).abs() / ((goalRight - goalLeft) / 2);
      final localAmp = amp * (1 - dist * dist).clamp(0.0, 1.0);
      final y = goalBottom - localAmp;
      canvas.drawLine(
        Offset(x, goalBottom),
        Offset(x, y),
        meshPaint,
      );
    }
  }

  // ─── Goalkeeper ──────────────────────────────────────────────
  void _paintKeeper(Canvas canvas, Size s) {
    final w = s.width;
    final h = s.height;
    final cx = w * keeperX;
    final goalBottom = h * 0.18;
    final keeperW = w * 0.16;
    final keeperH = h * 0.12;
    // Diving rotation (tilt left/right based on dive direction).
    final diveTilt = keeperDiving ? (_diveDelta().clamp(-1.0, 1.0)) * 0.6 : 0.0;
    canvas.save();
    canvas.translate(cx, goalBottom - keeperH * 0.2);
    canvas.rotate(diveTilt);
    canvas.translate(-cx, -(goalBottom - keeperH * 0.2));
    // Body shadow.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, goalBottom + 2),
        width: keeperW * 0.9,
        height: 8,
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );
    // Body (jersey + shorts).
    final bodyRect = Rect.fromCenter(
      center: Offset(cx, goalBottom - keeperH * 0.4),
      width: keeperW * 0.85,
      height: keeperH * 0.7,
    );
    // Jersey.
    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, const Radius.circular(8)),
      Paint()..color = const Color(0xFFF59E0B),
    );
    // Jersey stripe.
    canvas.drawRect(
      Rect.fromLTWH(bodyRect.left, bodyRect.top + bodyRect.height * 0.5,
          bodyRect.width, bodyRect.height * 0.18),
      Paint()..color = const Color(0xFFFBBF24),
    );
    // Head.
    canvas.drawCircle(
      Offset(cx, goalBottom - keeperH * 0.85),
      keeperW * 0.28,
      Paint()..color = const Color(0xFFFCD34D),
    );
    // Hair / cap.
    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(cx, goalBottom - keeperH * 0.85),
        radius: keeperW * 0.28,
      ),
      pi,
      pi,
      false,
      Paint()..color = const Color(0xFF1F2937)
        ..style = PaintingStyle.fill,
    );
    // Gloves (extended toward predicted shot side).
    final gloveR = keeperW * 0.18;
    final gloveY = goalBottom - keeperH * 0.3;
    final gloveDx = keeperDiving ? _diveDelta() * keeperW * 0.4 : 0.0;
    canvas.drawCircle(
      Offset(cx - keeperW * 0.35 + gloveDx, gloveY),
      gloveR,
      Paint()..color = const Color(0xFF22C55E),
    );
    canvas.drawCircle(
      Offset(cx + keeperW * 0.35 + gloveDx, gloveY),
      gloveR,
      Paint()..color = const Color(0xFF22C55E),
    );
    // Shorts.
    canvas.drawRect(
      Rect.fromLTWH(
        cx - keeperW * 0.32,
        bodyRect.bottom - 2,
        keeperW * 0.64,
        keeperH * 0.18,
      ),
      Paint()..color = const Color(0xFF1F2937),
    );
    canvas.restore();
  }

  double _diveDelta() {
    // Signed delta from keeper's resting position toward dive target.
    // Approximation: ballEnd.x / w vs keeperX.
    return (ballEnd.dx / size.width) - keeperX;
  }

  // ─── Ball trail ──────────────────────────────────────────────
  void _paintBallTrail(Canvas canvas, Size s) {
    if (!ballFlying || ballSaved) return;
    for (var i = 0; i < 6; i++) {
      final t = (ballT - i * 0.04).clamp(0.0, 1.0);
      if (t <= 0) continue;
      final p = _sampleBezierLocal(t);
      canvas.drawCircle(
        p,
        12 * (1 - i * 0.13),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.45 - i * 0.07)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }
  }

  Offset _sampleBezierLocal(double t) {
    final u = 1 - t;
    return ballStart * (u * u) +
        ballControl * (2 * u * t) +
        ballEnd * (t * t);
  }

  // ─── Drag preview ────────────────────────────────────────────
  void _paintDragPreview(Canvas canvas, Size s) {
    if (!dragging) return;
    final start = dragStart;
    final end = dragCurrent;
    if (start == null || end == null) return;
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    if (dx.abs() < 12 && dy.abs() < 12) return;

    final aimX = (s.width / 2 - dx * 2.2).clamp(60.0, s.width - 60);
    final aimY = (s.height * 0.18 - dy * 0.5).clamp(40.0, s.height * 0.5);
    final controlX =
        (s.width / 2 - dx * 1.0).clamp(40.0, s.width - 40);
    final controlY =
        (s.height * 0.55 - dy * 0.2).clamp(s.height * 0.4, s.height * 0.7);

    final pStart = Offset(s.width * 0.5, s.height * 0.86);
    final pEnd = Offset(aimX, aimY);
    final pCtrl = Offset(controlX, controlY);
    // Dotted Bezier preview.
    final path = Path();
    const steps = 24;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final u = 1 - t;
      final p = pStart * (u * u) + pCtrl * (2 * u * t) + pEnd * (t * t);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    // White stroke.
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
    // Yellow dashes on top.
    final dashPaint = Paint()
      ..color = const Color(0xFFFFC529)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final metrics = path.computeMetrics();
    for (final m in metrics) {
      var d = 0.0;
      while (d < m.length) {
        final next = d + 8.0;
        canvas.drawPath(
          m.extractPath(d, next.clamp(0, m.length)),
          dashPaint,
        );
        d = next + 6.0;
      }
    }
    // Target reticle at end.
    canvas.drawCircle(
      pEnd,
      10,
      Paint()..color = const Color(0xFF4E6CF5).withValues(alpha: 0.85),
    );
    canvas.drawCircle(
      pEnd,
      16,
      Paint()
        ..color = const Color(0xFF4E6CF5).withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    // Pull-back line (white).
    canvas.drawLine(
      start,
      end,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  // ─── Ball ─────────────────────────────────────────────────────
  void _paintBall(Canvas canvas, Size s) {
    Offset pos;
    double spin;
    if (ballFlying && !ballSaved) {
      pos = _sampleBezierLocal(ballT.clamp(0.0, 1.0));
      spin = ballSpin;
    } else if (ballFlying && ballSaved) {
      pos = Offset(s.width * ballX, s.height * ballY);
      spin = ballSpin;
    } else {
      pos = Offset(s.width * ballX, s.height * ballY);
      spin = 0;
    }
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(spin);
    // Shadow.
    canvas.drawCircle(
      const Offset(2, 3),
      12,
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );
    // Body (white + radial highlight).
    canvas.drawCircle(
      Offset.zero,
      12,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFFE2E8F0)],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: 12)),
    );
    // Outline.
    canvas.drawCircle(
      Offset.zero,
      12,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    // Pentagon pattern.
    final pentagonPaint = Paint()..color = Colors.black;
    canvas.drawCircle(const Offset(0, -4), 3.0, pentagonPaint);
    canvas.drawCircle(const Offset(-3.6, 2), 3.0, pentagonPaint);
    canvas.drawCircle(const Offset(3.6, 2), 3.0, pentagonPaint);
    canvas.drawCircle(const Offset(-1.5, 6), 2.4, pentagonPaint);
    canvas.drawCircle(const Offset(1.5, 6), 2.4, pentagonPaint);
    canvas.restore();
  }

  // ─── Confetti ─────────────────────────────────────────────────
  void _paintConfetti(Canvas canvas) {
    for (final c in confetti) {
      canvas.save();
      canvas.translate(c.pos.dx, c.pos.dy);
      canvas.rotate(c.rot);
      final t = (c.life / 1.5).clamp(0.0, 1.0);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: 8, height: 5),
          const Radius.circular(1.5),
        ),
        Paint()..color = c.color.withValues(alpha: t),
      );
      canvas.restore();
    }
  }

  // ─── Stars ────────────────────────────────────────────────────
  void _paintStars(Canvas canvas) {
    for (final s in stars) {
      final t = (s.life / 0.7).clamp(0.0, 1.0);
      _drawStar(canvas, Offset(s.x, s.y), 6 + s.r,
          const Color(0xFFFFC529).withValues(alpha: t));
    }
  }

  void _drawStar(Canvas canvas, Offset center, double size, Color fill) {
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
    canvas.drawPath(path, Paint()..color = fill);
  }

  // ─── Floaters ─────────────────────────────────────────────────
  void _paintFloaters(Canvas canvas, Size s) {
    for (final f in floaters) {
      final t = (f.life / 1.2).clamp(0.0, 1.0);
      final scale = f.scale * (0.85 + 0.15 * (1 - t).clamp(0.0, 1.0));
      final tp = TextPainter(
        text: TextSpan(
          text: f.text,
          style: TextStyle(
            color: f.color.withValues(alpha: t),
            fontSize: f.fontSize,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.6,
            shadows: const [
              Shadow(blurRadius: 8, color: Colors.black87),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate(f.x, f.y);
      canvas.scale(scale, scale);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_SoccerPainter old) =>
      old.ballX != ballX ||
      old.ballY != ballY ||
      old.ballFlying != ballFlying ||
      old.ballSaved != ballSaved ||
      old.ballT != ballT ||
      old.ballStart != ballStart ||
      old.ballEnd != ballEnd ||
      old.ballControl != ballControl ||
      old.ballSpin != ballSpin ||
      old.dragging != dragging ||
      old.dragStart != dragStart ||
      old.dragCurrent != dragCurrent ||
      old.keeperX != keeperX ||
      old.keeperDiving != keeperDiving ||
      old.netBulge != netBulge ||
      old.netBulgeX != netBulgeX ||
      old.floaters != floaters ||
      old.confetti != confetti ||
      old.stars != stars;
}
