import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Reusable particle burst system used for game juice (hit feedback,
/// score popups, level-up bursts).
///
/// Games call [emit] with an [Offset] in the local widget coordinate
/// space and an optional colour. The widget renders every active
/// particle via a single [CustomPainter]; particles age out
/// automatically so call sites don't have to manage lifecycle.
///
/// Each particle is a small filled circle with an optional short
/// "tail" line indicating direction. Particles obey a configurable
/// gravity and shrink + fade as they age.
class ParticleSystemWidget extends StatefulWidget {
  const ParticleSystemWidget({
    super.key,
    this.maxParticles = 64,
    this.gravity = 240,
    this.seed,
    this.onParticleUpdate,
  });

  /// Hard cap on simultaneously-rendered particles. Older particles
  /// are dropped first if the buffer fills.
  final int maxParticles;

  /// Pulls particles downward (positive) or upward (negative) over
  /// time in dp/s². Default matches a soft "fall to the ground"
  /// arcade feel.
  final double gravity;

  /// Optional RNG seed so a given sequence of emits produces
  /// deterministic visuals (useful for tests and for repeat VFX in
  /// the same gameplay moment).
  final int? seed;

  /// Optional callback invoked once per frame so a host can read the
  /// current alive count (e.g. for a debug overlay).
  final ValueChanged<int>? onParticleUpdate;

  @override
  State<ParticleSystemWidget> createState() => ParticleSystemWidgetState();
}

class ParticleSystemWidgetState extends State<ParticleSystemWidget>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final Random _rng;
  DateTime _last = DateTime.now();
  final List<_Particle> _particles = [];

  @override
  void initState() {
    super.initState();
    _rng = Random(widget.seed);
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// Emit a burst of [count] particles at [origin] in this widget's
  /// local coordinate space. Colours default to the PlayNest brand
  /// palette if [colors] is omitted.
  void emit(
    Offset origin, {
    int count = 12,
    double speed = 220,
    List<Color>? colors,
    double lifeSeconds = 0.7,
    double spread = pi * 2,
    double? directionAngle,
  }) {
    final palette = colors ??
        const [
          Color(0xFF4C73FF),
          Color(0xFFFF6584),
          Color(0xFFFFC837),
          Color(0xFF30D158),
          Color(0xFFA073FF),
          Color(0xFF22D3EE),
        ];
    final baseAngle = directionAngle ?? 0;
    for (var i = 0; i < count; i++) {
      if (_particles.length >= widget.maxParticles) {
        _particles.removeAt(0);
      }
      // Spread evenly across the requested arc plus a little jitter
      // so the burst doesn't look like a perfect fan.
      final theta = baseAngle +
          (count == 1 ? 0 : -spread / 2) +
          (spread / (count - 1).clamp(1, 9999)) * i +
          (_rng.nextDouble() - 0.5) * 0.25;
      final v = speed * (0.7 + _rng.nextDouble() * 0.6);
      _particles.add(_Particle(
        origin: origin,
        velocity: Offset(cos(theta) * v, sin(theta) * v),
        color: palette[_rng.nextInt(palette.length)],
        life: lifeSeconds * (0.7 + _rng.nextDouble() * 0.6),
        maxLife: lifeSeconds,
        radius: 2.5 + _rng.nextDouble() * 3.5,
      ));
    }
  }

  /// Drop all in-flight particles. Useful when a game ends or
  /// navigates away.
  void clear() {
    if (_particles.isEmpty) return;
    setState(_particles.clear);
  }

  void _tick(Duration _) {
    if (!mounted) return;
    final now = DateTime.now();
    final dt = now.difference(_last).inMicroseconds / 1e6;
    _last = now;
    if (dt <= 0) return;
    final gravity = widget.gravity;
    var changed = false;
    for (final p in _particles) {
      p.velocity = p.velocity + Offset(0, gravity * dt);
      p.origin = p.origin + p.velocity * dt;
      p.life -= dt;
      changed = true;
    }
    final before = _particles.length;
    _particles.removeWhere((p) => p.life <= 0);
    if (changed || before != _particles.length) {
      widget.onParticleUpdate?.call(_particles.length);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _ParticlePainter(particles: _particles),
        size: Size.infinite,
      ),
    );
  }
}

class _Particle {
  _Particle({
    required this.origin,
    required this.velocity,
    required this.color,
    required this.life,
    required this.maxLife,
    required this.radius,
  });
  Offset origin;
  Offset velocity;
  Color color;
  double life;
  double maxLife;
  double radius;
}

class _ParticlePainter extends CustomPainter {
  _ParticlePainter({required this.particles});
  final List<_Particle> particles;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final t = (p.life / p.maxLife).clamp(0.0, 1.0);
      final radius = p.radius * t;
      if (radius <= 0) continue;
      final tail = p.velocity * -0.04;
      // Soft glow halo behind each particle.
      canvas.drawCircle(
        p.origin,
        radius * 2.0,
        Paint()..color = p.color.withValues(alpha: 0.18 * t),
      );
      // Tail line.
      canvas.drawLine(
        p.origin + tail,
        p.origin,
        Paint()
          ..color = p.color.withValues(alpha: 0.85 * t)
          ..strokeWidth = radius * 1.2
          ..strokeCap = StrokeCap.round,
      );
      // Core dot.
      canvas.drawCircle(
        p.origin,
        radius,
        Paint()..color = p.color.withValues(alpha: t),
      );
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) =>
      old.particles.length != particles.length || old.particles != particles;
}