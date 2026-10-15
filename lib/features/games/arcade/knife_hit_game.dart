import 'dart:math';

import 'package:flutter/material.dart';

import '../game_widgets.dart';
import '../mini_game.dart';

/// Knife Hit — polished 2D target shooter.
///
/// Scene:
///   * Wooden target wheel with concentric wood-grain rings, a
///     metallic rim, and a red bullseye decal on its front face.
///   * The wheel rotates continuously via [AnimationController]; speed
///     and direction ramp with each successful embed. Every 4 embeds
///     the wheel wobbles (3× speed for 220 ms) and flips direction.
///   * Bottom tray shows the remaining knives (15 → 0) as small
///     chef-knife silhouettes over a launcher capsule.
///   * Tap anywhere to throw a knife straight up at full velocity.
///   * Knife-on-knife collision = DEFLECT + Game Over. Knife-on-log
///     collision = EMBED, +100 / +150 / +200 by bullseye proximity,
///     wood-chip burst, screen shake, "+N" floater.
///
/// Per the unified HUD refresh, the top status row uses
/// `GameHudBar` capsules (indigo + yellow accent) consistent with
/// every other catalog game.
class KnifeHitGame extends MiniGame {
  const KnifeHitGame({super.key, required super.callbacks});

  @override
  State<KnifeHitGame> createState() => _State();
}

class _State extends MiniGameState<KnifeHitGame>
    with SingleTickerProviderStateMixin {
  final Random _rng = Random();
  static const int _maxKnives = 15;
  static const double _twoPi = 6.28318530717958;

  // ─── Rotation ──────────────────────────────────────────────────
  /// Drives the wheel rotation. The actual displayed angle is
  /// `_spinCtrl.value * 2π * _spinDirection * _rotationSpeed`, so the
  /// controller can keep a stable period while we change direction /
  /// speed by mutating the multipliers.
  late final AnimationController _spinCtrl;
  double _rotationSpeed = 1.0; // scalar 0.4 .. 2.5
  int _spinDirection = 1; // +1 or -1
  int _wobbleTicksRemaining = 0;
  double _angle = 0;

  // ─── Throws / state ────────────────────────────────────────────
  int _score = 0;
  int _stuckCount = 0;
  bool _gameOver = false;

  /// Knives embedded in the wheel. Each entry stores the wheel-
  /// relative angle at impact and the score tier (0/1/2 → outer /
  /// front-face / bullseye). Rotation is applied at paint time.
  final List<_StuckKnife> _stuckKnives = [];

  /// The currently in-flight knife (one at a time). `null` when idle.
  _FlyingKnife? _flying;

  /// Knives that were deflected and are bouncing off the wheel; they
  /// persist for ~600 ms after game over so the player sees them fly
  /// away before the overlay covers the canvas.
  final List<_DeflectedKnife> _deflected = [];

  // ─── VFX lists ─────────────────────────────────────────────────
  final List<_WoodChip> _woodChips = [];
  final List<_Spark> _sparks = [];
  final List<_Floater> _floaters = [];
  final List<_WoodDust> _dustPuffs = [];

  // ─── Screen shake ──────────────────────────────────────────────
  double _shakeTime = 0; // counts down to 0

  // ─── Geometry (set in build) ───────────────────────────────────
  double _cx = 0;
  double _cy = 0;
  double _wheelR = 0;
  double _launcherY = 0;

  @override
  void initState() {
    super.initState();
    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    )
      ..addListener(_onSpinTick)
      ..repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reportScore(_score);
      reportStats('Targets 0/$_maxKnives');
    });
  }

  @override
  void dispose() {
    _spinCtrl
      ..removeListener(_onSpinTick)
      ..dispose();
    super.dispose();
  }

  void _onSpinTick() {
    if (!mounted) return;
    final wobble = _wobbleTicksRemaining > 0 ? 3.0 : 1.0;
    final delta = _spinCtrl.duration!.inMicroseconds /
        1e6; // 30 s per full revolution at base speed
    // We just want a frame-rate independent angle. The listener fires
    // each vsync; compute dt from the controller's last elapsed.
    final elapsed = _spinCtrl.lastElapsedDuration?.inMicroseconds ?? 0;
    final prevElapsed = _spinCtrl.lastElapsedDuration == null
        ? 0.0
        : (elapsed - 16667); // ~60fps frame; sufficient for visuals
    final dt = max(0.0, (elapsed - prevElapsed) / 1e6);
    setState(() {
      _angle +=
          _twoPi * _spinDirection * _rotationSpeed * wobble * (dt / delta);
      if (_angle > _twoPi) _angle -= _twoPi;
      if (_angle < -_twoPi) _angle += _twoPi;
      _advance(dt);
    });
  }

  void _advance(double dt) {
    // Shake decay.
    if (_shakeTime > 0) {
      _shakeTime = (_shakeTime - dt).clamp(0.0, 99.0);
    }
    // Wobble ticks.
    if (_wobbleTicksRemaining > 0) {
      _wobbleTicksRemaining = (_wobbleTicksRemaining - dt).ceil();
      if (_wobbleTicksRemaining < 0) _wobbleTicksRemaining = 0;
    }
    // Flying knife physics.
    final f = _flying;
    if (f != null) {
      f.vy += 1400 * dt;
      f.y += f.vy * dt;
      f.rotation += f.angularV * dt;
      f.angularV *= pow(0.96, dt * 60).toDouble();
      // Collision-resolve: when knife tip crosses wheel center y.
      if (!f.resolved && f.y <= _cy) {
        f.resolved = true;
        _resolveImpact(f);
      }
      // Off-screen cleanup.
      if (f.y < -100 || f.y > 2000) {
        _flying = null;
      }
    }
    // Deflected knives bounce and self-destruct.
    for (final d in _deflected) {
      d.vy += 900 * dt;
      d.x += d.vx * dt;
      d.y += d.vy * dt;
      d.rotation += d.angularV * dt;
      d.life -= dt;
    }
    _deflected.removeWhere((d) => d.life <= 0);
    // Wood chips.
    for (final c in _woodChips) {
      c.posLocal = c.posLocal + c.vel * dt;
      c.vel = c.vel + const Offset(0, 600) * dt;
      c.life -= dt;
    }
    _woodChips.removeWhere((c) => c.life <= 0);
    // Sparks.
    for (final s in _sparks) {
      s.pos = s.pos + s.vel * dt;
      s.vel = s.vel + const Offset(0, 400) * dt;
      s.life -= dt;
    }
    _sparks.removeWhere((s) => s.life <= 0);
    // Dust puffs.
    for (final p in _dustPuffs) {
      p.r += 60 * dt;
      p.life -= dt;
    }
    _dustPuffs.removeWhere((p) => p.life <= 0);
    // Floaters.
    for (final f2 in _floaters) {
      f2.y -= 90 * dt;
      f2.life -= dt;
    }
    _floaters.removeWhere((f2) => f2.life <= 0);
  }

  void _throwKnife() {
    if (_gameOver) return;
    if (_flying != null) return;
    if (_deflected.isNotEmpty) return;
    if (_stuckCount >= _maxKnives) return;
    setState(() {
      _flying = _FlyingKnife(
        y: _launcherY + 30,
        vy: -1200,
        rotation: 0,
        angularV: 6,
      );
      haptic(HapticFeedbackType.selection);
    });
  }

  void _resolveImpact(_FlyingKnife f) {
    // The knife always flies straight up to (cx, cy), which is the
    // top of the wheel. The wheel's current angle determines which
    // *wheel-local* radial slot the knife lands in. We store the
    // knife's wheel-local angle as `_angle + π/2` so that the
    // painter (which translates by `(cos(a - π/2) * r, sin(a - π/2)
    // * r)`) draws it at the top of the wheel at impact time.
    final embedAngle = _angle + pi / 2;
    // Knife-on-knife check: angular distance from each embedded knife.
    for (final stuck in _stuckKnives) {
      var diff = (embedAngle - stuck.angle).abs();
      if (diff > pi) diff = _twoPi - diff;
      if (diff < _deflectArc) {
        _triggerDeflect(f, embedAngle);
        return;
      }
    }
    // Successful embed. Byte stores the wheel-local angle of the
    // top-of-wheel reference: `stuckAngle = _angle + π/2`. The painter
    // uses `tipPos(angle) = (cos(a - π/2) * r, sin(a - π/2) * r)`,
    // which at `a = _angle + π/2` gives `(cos(_angle), sin(_angle)) *
    // r`. That point is on the rim, at the angle `_angle` from the
    // wheel's local "12 o'clock" — i.e., the actual rim point that
    // was at the top of the screen at the moment of impact.
    _score += _tierBonus(embedAngle);
    _stuckCount += 1;
    _stuckKnives.add(
      _StuckKnife(angle: embedAngle, tier: _tierOf(embedAngle)),
    );
    // VFX.
    _spawnWoodChips(embedAngle);
    _dustPuffs.add(
      _WoodDust(rot: embedAngle, r: 0, life: 0.25),
    );
    final tier = _tierOf(embedAngle);
    final pts = _tierBonus(embedAngle);
    _floaters.add(_Floater(
      x: _cx,
      y: _cy - _wheelR - 40,
      text: tier == 2 ? 'BULLSEYE! +$pts' : '+$pts',
      color: tier == 2
          ? const Color(0xFFFF5983)
          : const Color(0xFFFFC529),
      life: 1.0,
      scale: tier == 2 ? 1.2 : 1.0,
    ));
    _shakeTime = 0.35;
    haptic(HapticFeedbackType.medium);
    // Speed + direction ramp.
    _rotationSpeed = min(2.5, _rotationSpeed + 0.18);
    if (_stuckCount % 4 == 0) {
      _spinDirection *= -1;
      _wobbleTicksRemaining = 12; // ~200ms at 60fps
    }
    reportScore(_score);
    reportStats('Targets $_stuckCount/$_maxKnives');
    _flying = null;
    // Win condition.
    if (_stuckCount >= _maxKnives) {
      _gameOver = true;
      _floaters.add(_Floater(
        x: _cx,
        y: _cy - _wheelR - 90,
        text: 'LOG FILLED!',
        color: const Color(0xFF4CD171),
        life: 1.4,
        scale: 1.3,
      ));
      haptic(HapticFeedbackType.heavy);
      reportStats('All $_maxKnives knives stuck!');
      reportGameOver();
    }
  }

  /// Bullseye bonus: knife lands within ~32° of the wheel's top
  /// (where the camera is looking) on the front face → +200.
  /// Front face but not bullseye → +150. Back face → +100.
  int _tierOf(double embedAngle) {
    // `embedAngle = _angle + π/2`. In wheel-local space the "12
    // o'clock front" is at angle π/2 (the painter draws the
    // bullseye front-face at -π/2 .. +π/2 from the +X axis in wheel
    // space, but with the painter rotation applied, the front face
    // spans -π/2 .. +π/2 of *global* rotation. The position at the
    // top of the screen is the current global rotation `_angle`,
    // which corresponds to wheel-local `_angle + π/2` of a stuck
    // knife. We score based on how close that local angle is to
    // π/2 (the "front face center").
    final localFromFront = _wrapAngle(embedAngle - pi / 2);
    final cosLocal = cos(localFromFront);
    final inFrontFace = cosLocal > 0;
    final closeToCenter = cosLocal.abs() > 0.85;
    if (!inFrontFace) return 0;
    return closeToCenter ? 2 : 1;
  }

  int _tierBonus(double embedAngle) {
    return switch (_tierOf(embedAngle)) {
      2 => 200,
      1 => 150,
      _ => 100,
    };
  }

  void _triggerDeflect(_FlyingKnife f, double embedAngle) {
    // Tangent direction at the impact point (perpendicular to the
    // radial direction, which is `_angle` from the wheel's local up).
    final tangent = Offset(
      cos(embedAngle - pi / 2),
      sin(embedAngle - pi / 2),
    );
    // Spawn deflected knife with tangential bounce.
    _deflected.add(_DeflectedKnife(
      x: _cx,
      y: _cy,
      vx: tangent.dx * 340,
      vy: tangent.dy * 340 - 120,
      rotation: f.rotation,
      angularV: f.angularV + 6,
      life: 0.7,
    ));
    // Spark burst at impact.
    for (var i = 0; i < 10; i++) {
      final a = _rng.nextDouble() * _twoPi;
      final v = 180 + _rng.nextDouble() * 220;
      _sparks.add(_Spark(
        pos: Offset(
          _cx + cos(embedAngle - pi / 2) * _wheelR,
          _cy + sin(embedAngle - pi / 2) * _wheelR,
        ),
        vel: Offset(cos(a) * v, sin(a) * v - 80),
        life: 0.55,
      ));
    }
    _floaters.add(_Floater(
      x: _cx,
      y: _cy - _wheelR - 50,
      text: 'DEFLECT!',
      color: const Color(0xFFEF4444),
      life: 1.0,
      scale: 1.4,
    ));
    _shakeTime = 0.45;
    haptic(HapticFeedbackType.heavy);
    _flying = null;
    _gameOver = true;
    reportScore(_score);
    reportStats('Final: $_stuckCount knives stuck');
    // Defer game-over overlay so the deflected knife is visible first.
    Future.delayed(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      reportGameOver();
    });
  }

  void _spawnWoodChips(double localAngle) {
    final impact = Offset(
      cos(localAngle - pi / 2) * _wheelR,
      sin(localAngle - pi / 2) * _wheelR,
    );
    for (var i = 0; i < 12; i++) {
      final a = localAngle - pi / 2 +
          (_rng.nextDouble() - 0.5) * (pi * 0.9);
      final v = 140 + _rng.nextDouble() * 220;
      _woodChips.add(_WoodChip(
        posLocal: impact,
        vel: Offset(cos(a) * v, sin(a) * v),
        life: 0.55 + _rng.nextDouble() * 0.25,
        rot: _rng.nextDouble() * _twoPi,
        rotV: (_rng.nextDouble() - 0.5) * 12,
        size: 4 + _rng.nextDouble() * 4,
      ));
    }
  }

  static const double _deflectArc = 0.18;
  static double _wrapAngle(double a) {
    while (a > pi) {
      a -= _twoPi;
    }
    while (a < -pi) {
      a += _twoPi;
    }
    return a;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        // Initialize / refresh geometry on every frame (handles resize).
        final shortestSide =
            c.maxWidth < c.maxHeight ? c.maxWidth : c.maxHeight;
        _cx = c.maxWidth / 2;
        _cy = c.maxHeight * 0.42;
        _wheelR = shortestSide * 0.22;
        _launcherY = c.maxHeight - 110;
        final shakeX = _shakeTime > 0
            ? (_rng.nextDouble() - 0.5) * 12 * _shakeTime
            : 0.0;
        final shakeY = _shakeTime > 0
            ? (_rng.nextDouble() - 0.5) * 5 * _shakeTime
            : 0.0;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _throwKnife,
          child: Stack(
            children: [
              Positioned.fill(
                child: Transform.translate(
                  offset: Offset(shakeX, shakeY),
                  child: CustomPaint(
                    painter: _KnifePainter(
                      angle: _angle,
                      stuckKnives: _stuckKnives,
                      flying: _flying,
                      deflected: _deflected,
                      woodChips: _woodChips,
                      sparks: _sparks,
                      floaters: _floaters,
                      dustPuffs: _dustPuffs,
                      cx: _cx,
                      cy: _cy,
                      wheelR: _wheelR,
                    ),
                  ),
                ),
              ),
              // Top HUD removed — host GameContainerScreen provides it.
              // Bottom launcher tray.
              Positioned(
                left: 0,
                right: 0,
                bottom: 18,
                child: IgnorePointer(
                  child: _LauncherTray(
                    remaining: _maxKnives - _stuckCount,
                    max: _maxKnives,
                    launcherY: _launcherY,
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

// ─────────────────────────────────────────────────────────────────
// State helpers
// ─────────────────────────────────────────────────────────────────

class _StuckKnife {
  _StuckKnife({required this.angle, required this.tier});
  final double angle;
  final int tier; // 0 back, 1 front-face, 2 bullseye-front
}

class _FlyingKnife {
  _FlyingKnife({
    required this.y,
    required this.vy,
    required this.rotation,
    required this.angularV,
  }) : resolved = false;
  double y;
  double vy;
  double rotation;
  double angularV;
  bool resolved;
}

class _DeflectedKnife {
  _DeflectedKnife({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.rotation,
    required this.angularV,
    required this.life,
  });
  double x;
  double y;
  double vx;
  double vy;
  double rotation;
  double angularV;
  double life;
}

class _WoodChip {
  _WoodChip({
    required this.posLocal,
    required this.vel,
    required this.life,
    required this.rot,
    required this.rotV,
    required this.size,
  });
  Offset posLocal;
  Offset vel;
  double life;
  double rot;
  double rotV;
  double size;
}

class _Spark {
  _Spark({
    required this.pos,
    required this.vel,
    required this.life,
  });
  Offset pos;
  Offset vel;
  double life;
}

class _WoodDust {
  _WoodDust({required this.rot, required this.r, required this.life});
  double rot;
  double r;
  double life;
}

class _Floater {
  _Floater({
    required this.x,
    required this.y,
    required this.text,
    required this.color,
    required this.life,
    this.scale = 1.0,
  });
  double x;
  double y;
  String text;
  Color color;
  double life;
  double scale;
}

// ─────────────────────────────────────────────────────────────────
// HUD widgets
// ─────────────────────────────────────────────────────────────────



/// Bottom tray — shows the remaining knives above a launcher pad.
/// The pad mirrors the HUD capsule aesthetic (indigo + soft shadow).
class _LauncherTray extends StatelessWidget {
  const _LauncherTray({
    required this.remaining,
    required this.max,
    required this.launcherY,
  });
  final int remaining;
  final int max;
  final double launcherY;

  @override
  Widget build(BuildContext context) {
    // Lay out knife icons in two rows of 8 + 7 to keep them small.
    const perRow = 8;
    final rows = <Widget>[];
    var shown = 0;
    for (var r = 0; r < 2 && shown < max; r++) {
      final inRow = (r == 0) ? perRow : (max - perRow);
      final children = <Widget>[];
      for (var i = 0; i < inRow; i++) {
        final idx = r * perRow + i;
        final isAvailable = idx < remaining;
        children.add(Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Opacity(
              opacity: isAvailable ? 1.0 : 0.22,
              child: CustomPaint(
                size: const Size(20, 22),
                painter: _KnifeIconPainter(),
              ),
            ),
          ),
        ));
      }
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: children),
      ));
      shown += inRow;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...rows,
        const SizedBox(height: 10),
        // Launcher pad (mirrors HUD capsule style).
        Center(
          child: Container(
            width: 110,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFF4E6CF5),
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  color: Color.fromRGBO(0, 0, 0, 0.15),
                  blurRadius: 8,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: const Text(
              'TAP TO THROW',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.4,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _KnifeIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final blade = Paint()..color = const Color(0xFFE5E7EB);
    final outline = Paint()
      ..color = const Color(0xFF1F2937)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final handle = Paint()..color = const Color(0xFFB91C1C);
    final handleDark = Paint()..color = const Color(0xFF7F1D1D);
    final cx = size.width / 2;
    final w = size.width * 0.7;
    // Blade triangle (point up).
    final tip = Offset(cx, 2);
    final baseL = Offset(cx - w / 2, size.height * 0.55);
    final baseR = Offset(cx + w / 2, size.height * 0.55);
    final bladePath = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(baseR.dx, baseR.dy)
      ..lineTo(baseL.dx, baseL.dy)
      ..close();
    canvas.drawPath(bladePath, blade);
    canvas.drawPath(bladePath, outline);
    // Handle (rectangle below).
    final handleRect = Rect.fromLTWH(
      cx - w / 2 * 0.7,
      size.height * 0.55,
      w * 0.7,
      size.height * 0.32,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(handleRect, const Radius.circular(2)),
      handle,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(handleRect, const Radius.circular(2)),
      outline,
    );
    // Handle rivet.
    canvas.drawCircle(
      Offset(handleRect.center.dx, handleRect.center.dy),
      1.2,
      handleDark,
    );
  }

  @override
  bool shouldRepaint(_KnifeIconPainter old) => false;
}

// ─────────────────────────────────────────────────────────────────
// Painter — full wheel scene
// ─────────────────────────────────────────────────────────────────

class _KnifePainter extends CustomPainter {
  _KnifePainter({
    required this.angle,
    required this.stuckKnives,
    required this.flying,
    required this.deflected,
    required this.woodChips,
    required this.sparks,
    required this.floaters,
    required this.dustPuffs,
    required this.cx,
    required this.cy,
    required this.wheelR,
  });
  final double angle;
  final List<_StuckKnife> stuckKnives;
  final _FlyingKnife? flying;
  final List<_DeflectedKnife> deflected;
  final List<_WoodChip> woodChips;
  final List<_Spark> sparks;
  final List<_Floater> floaters;
  final List<_WoodDust> dustPuffs;
  final double cx;
  final double cy;
  final double wheelR;

  // ─── Palette ───────────────────────────────────────────────────
  static const Color _rimMetal = Color(0xFF9CA3AF);
  static const Color _rimMetalDark = Color(0xFF4B5563);
  static const Color _rimMetalLight = Color(0xFFE5E7EB);
  static const Color _woodCenter = Color(0xFFD6A36C);
  static const Color _woodEdge = Color(0xFF8B5A2B);
  static const Color _grainDark = Color(0x33000000);
  static const Color _bullseyeRed = Color(0xFFDC2626);
  static const Color _bullseyeWhite = Color(0xFFFEE2E2);
  static const Color _bullseyeOuter = Color(0xFFEF4444);

  @override
  void paint(Canvas canvas, Size size) {
    _paintBackground(canvas, size);
    _paintWheel(canvas);
    _paintStuckKnives(canvas);
    _paintWoodChips(canvas);
    _paintDustPuffs(canvas);
    _paintFlyingKnife(canvas);
    _paintDeflected(canvas);
    _paintSparks(canvas);
    _paintFloaters(canvas, size);
  }

  void _paintBackground(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1E1B4B), Color(0xFF7C3AED)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
  }

  // ─── Wheel (5 layers) ─────────────────────────────────────────
  void _paintWheel(Canvas canvas) {
    final r = wheelR;
    // 1. Drop shadow.
    canvas.drawCircle(
      Offset(cx, cy + 8),
      r + 6,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    // 2. Outer metallic rim (sweep gradient).
    final rimPaint = Paint()
      ..shader = const SweepGradient(
        colors: [
          _rimMetalLight,
          _rimMetal,
          _rimMetalDark,
          _rimMetal,
          _rimMetalLight,
          _rimMetal,
          _rimMetalDark,
          _rimMetal,
          _rimMetalLight,
        ],
        stops: [
          0,
          0.125,
          0.25,
          0.375,
          0.5,
          0.625,
          0.75,
          0.875,
          1,
        ],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r));
    canvas.drawCircle(Offset(cx, cy), r, rimPaint);
    // Rim outline.
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..color = const Color(0xFF1F2937)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    // 16 bolt heads.
    for (var i = 0; i < 16; i++) {
      final a = (i / 16) * 6.2831853;
      canvas.drawCircle(
        Offset(cx + cos(a) * (r - r * 0.05), cy + sin(a) * (r - r * 0.05)),
        r * 0.018,
        Paint()..color = const Color(0xFF374151),
      );
      canvas.drawCircle(
        Offset(cx + cos(a) * (r - r * 0.05), cy + sin(a) * (r - r * 0.05)),
        r * 0.008,
        Paint()..color = const Color(0xFFD1D5DB),
      );
    }
    // Inner rim line.
    canvas.drawCircle(
      Offset(cx, cy),
      r * 0.92,
      Paint()
        ..color = const Color(0xFF1F2937)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    // 3. Wooden body.
    canvas.save();
    canvas.clipPath(
      Path()
        ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.92)),
    );
    canvas.drawCircle(
      Offset(cx, cy),
      r * 0.92,
      Paint()
        ..shader = RadialGradient(
          colors: [_woodCenter, _woodEdge],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r)),
    );
    // 4. Wood-grain rings.
    for (var i = 0; i < 5; i++) {
      final rr = r * (0.22 + i * 0.16);
      canvas.drawCircle(
        Offset(cx, cy),
        rr,
        Paint()
          ..color = _grainDark
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
    // 5. Wood-grain radial strokes (organic, jittered).
    // Use a deterministic seed for repeat-frame consistency.
    final grainRng = _WoodGrainRng();
    for (var i = 0; i < 5; i++) {
      final baseA = grainRng.next() * 6.2831853;
      canvas.drawLine(
        Offset(cx, cy),
        Offset(cx + cos(baseA) * r * 0.9, cy + sin(baseA) * r * 0.9),
        Paint()
          ..color = const Color(0x22000000)
          ..strokeWidth = 0.9,
      );
    }
    // 6. Bullseye front-face (rotates with the wheel).
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(angle);
    _paintBullseyeFrontFace(canvas, r);
    canvas.restore();
    canvas.restore();
  }

  void _paintBullseyeFrontFace(Canvas canvas, double r) {
    // The bullseye decal lives on the front face of the wheel — a
    // semicircle facing the camera (angles -π/2 .. +π/2 local).
    // We construct a clipped Path so only the front-half gets the
    // decal.
    final frontPath = Path()
      ..addArc(
        Rect.fromCircle(center: Offset.zero, radius: r * 0.86),
        -pi / 2,
        pi,
      )
      ..close();
    canvas.save();
    canvas.clipPath(frontPath);
    // 4 concentric filled rings: outer red, white, red, white center.
    final radii = [r * 0.74, r * 0.58, r * 0.42, r * 0.26];
    final colors = [
      _bullseyeOuter,
      _bullseyeWhite,
      _bullseyeRed,
      _bullseyeWhite,
    ];
    for (var i = 0; i < radii.length; i++) {
      canvas.drawCircle(
        Offset.zero,
        radii[i],
        Paint()..color = colors[i],
      );
    }
    // Tiny center dot.
    canvas.drawCircle(
      Offset.zero,
      r * 0.10,
      Paint()..color = const Color(0xFFFBBF24),
    );
    canvas.drawCircle(
      Offset.zero,
      r * 0.06,
      Paint()..color = const Color(0xFF7F1D1D),
    );
    // Subtle highlight across the bullseye.
    final highlight = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.18),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: r * 0.86));
    canvas.drawCircle(
      Offset.zero,
      r * 0.86,
      highlight,
    );
    canvas.restore();
    // Outline of front face arc.
    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: r * 0.86),
      -pi / 2,
      pi,
      false,
      Paint()
        ..color = const Color(0xFF1F2937).withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  // ─── Stuck knives ─────────────────────────────────────────────
  void _paintStuckKnives(Canvas canvas) {
    final r = wheelR;
    for (final k in stuckKnives) {
      final tip = _tipPos(k.angle, r);
      final screenTip = Offset(tip.dx + cx, tip.dy + cy);
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(k.angle - pi / 2);
      _drawKnife(canvas, r, tier: k.tier);
      canvas.restore();
      // Subtle indent shadow on the wood surface (visible only for
      // bullseye-tier knives, sells the embed).
      if (k.tier == 2) {
        canvas.drawCircle(
          screenTip,
          4,
          Paint()
            ..color = const Color(0xFFFBBF24).withValues(alpha: 0.6)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
      }
    }
  }

  // ─── Wood chips (rotate with wheel) ───────────────────────────
  void _paintWoodChips(Canvas canvas) {
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(angle);
    for (final c in woodChips) {
      final t = (c.life / 0.7).clamp(0.0, 1.0);
      canvas.save();
      canvas.translate(c.posLocal.dx, c.posLocal.dy);
      canvas.rotate(c.rot);
      final rect = Rect.fromCenter(
        center: Offset.zero,
        width: c.size,
        height: c.size * 0.4,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(1)),
        Paint()..color = _woodEdge.withValues(alpha: t),
      );
      canvas.restore();
    }
    canvas.restore();
  }

  // ─── Dust puffs (rotate with wheel) ────────────────────────────
  void _paintDustPuffs(Canvas canvas) {
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(angle);
    for (final p in dustPuffs) {
      final t = (p.life / 0.25).clamp(0.0, 1.0);
      final pTip = Offset(
        cos(p.rot - pi / 2) * wheelR,
        sin(p.rot - pi / 2) * wheelR,
      );
      canvas.drawCircle(
        pTip,
        18 + p.r,
        Paint()
          ..color = const Color(0xFFFEF3C7).withValues(alpha: 0.45 * t)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
    canvas.restore();
  }

  // ─── Flying knife ─────────────────────────────────────────────
  void _paintFlyingKnife(Canvas canvas) {
    final f = flying;
    if (f == null) return;
    canvas.save();
    canvas.translate(cx, f.y);
    canvas.rotate(f.rotation);
    _drawKnife(canvas, wheelR * 0.95, tier: 0);
    canvas.restore();
  }

  // ─── Deflected knives ─────────────────────────────────────────
  void _paintDeflected(Canvas canvas) {
    for (final d in deflected) {
      final t = (d.life / 0.7).clamp(0.0, 1.0);
      canvas.save();
      canvas.translate(d.x, d.y);
      canvas.rotate(d.rotation);
      canvas.save();
      canvas.translate(0, -wheelR * 0.85);
      _drawKnife(canvas, wheelR * 0.85, tier: 0, alpha: t);
      canvas.restore();
      canvas.restore();
    }
  }

  // ─── Sparks ───────────────────────────────────────────────────
  void _paintSparks(Canvas canvas) {
    for (final s in sparks) {
      final t = (s.life / 0.55).clamp(0.0, 1.0);
      canvas.drawLine(
        s.pos,
        s.pos + s.vel * -0.04,
        Paint()
          ..color = const Color(0xFFFEF3C7).withValues(alpha: t)
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(
        s.pos,
        2.5 * t,
        Paint()..color = const Color(0xFFFFC529).withValues(alpha: t),
      );
    }
  }

  // ─── Floaters ─────────────────────────────────────────────────
  void _paintFloaters(Canvas canvas, Size size) {
    for (final f in floaters) {
      final t = (f.life / 1.0).clamp(0.0, 1.0);
      final scale = f.scale * (0.85 + 0.15 * (1 - t).clamp(0.0, 1.0));
      final tp = TextPainter(
        text: TextSpan(
          text: f.text,
          style: TextStyle(
            color: f.color.withValues(alpha: t),
            fontSize: 24,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.4,
            shadows: const [
              Shadow(blurRadius: 6, color: Colors.black54),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate(f.x, f.y);
      canvas.scale(scale, scale);
      tp.paint(
        canvas,
        Offset(-tp.width / 2, -tp.height / 2),
      );
      canvas.restore();
    }
  }

  // ─── Knife primitives ─────────────────────────────────────────
  void _drawKnife(Canvas canvas, double r, {required int tier, double alpha = 1}) {
    final blade = Paint()..color = const Color(0xFFE5E7EB).withValues(alpha: alpha);
    final bladeDark = Paint()
      ..color = const Color(0xFF9CA3AF).withValues(alpha: alpha);
    final outline = Paint()
      ..color = const Color(0xFF1F2937).withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final handle = Paint()
      ..color = tier == 2
          ? const Color(0xFFDC2626).withValues(alpha: alpha)
          : const Color(0xFFB91C1C).withValues(alpha: alpha);
    final handleDark = Paint()
      ..color = const Color(0xFF7F1D1D).withValues(alpha: alpha);
    final length = r * 0.85;
    // Blade (silver triangle, point up).
    final tip = Offset(0, -length);
    final baseL = Offset(-5, -length + 22);
    final baseR = Offset(5, -length + 22);
    final bladePath = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(baseR.dx, baseR.dy)
      ..lineTo(baseL.dx, baseL.dy)
      ..close();
    canvas.drawPath(bladePath, blade);
    // Blade shading line.
    canvas.drawLine(
      tip,
      Offset(0, -length + 18),
      Paint()
        ..color = bladeDark.color
        ..strokeWidth = 1.2,
    );
    canvas.drawPath(bladePath, outline);
    // Bolster (between blade and handle).
    final bolster = Rect.fromCenter(
      center: Offset(0, -length + 26),
      width: 11,
      height: 6,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bolster, const Radius.circular(1.5)),
      Paint()..color = const Color(0xFF6B7280).withValues(alpha: alpha),
    );
    // Handle (rectangle below bolster).
    final handleRect = Rect.fromCenter(
      center: Offset(0, -length + 38),
      width: 11,
      height: 18,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(handleRect, const Radius.circular(2)),
      handle,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(handleRect, const Radius.circular(2)),
      outline,
    );
    // Handle rivets.
    canvas.drawCircle(
      Offset(handleRect.center.dx, handleRect.top + 4),
      1.2,
      handleDark,
    );
    canvas.drawCircle(
      Offset(handleRect.center.dx, handleRect.bottom - 4),
      1.2,
      handleDark,
    );
    // Pommel (cap at bottom of handle).
    canvas.drawCircle(
      Offset(0, handleRect.bottom + 2),
      3,
      handleDark,
    );
  }

  Offset _tipPos(double a, double r) =>
      Offset(cos(a - pi / 2) * r, sin(a - pi / 2) * r);

  @override
  bool shouldRepaint(_KnifePainter old) =>
      old.angle != angle ||
      old.stuckKnives != stuckKnives ||
      old.flying != flying ||
      old.deflected != deflected ||
      old.woodChips != woodChips ||
      old.sparks != sparks ||
      old.floaters != floaters ||
      old.dustPuffs != dustPuffs ||
      old.cx != cx ||
      old.cy != cy ||
      old.wheelR != wheelR;
}

/// Tiny deterministic RNG (linear congruential generator) used to
/// position the wood-grain radial strokes. We don't need cryptographic
/// quality — just deterministic per-frame jitter so the painter
/// doesn't reallocate on every frame.
class _WoodGrainRng {
  int _state = 7;
  double next() {
    _state = (_state * 1103515245 + 12345) & 0x7fffffff;
    return _state / 0x7fffffff;
  }
}
