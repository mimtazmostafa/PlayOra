import 'dart:math';

import 'package:flutter/material.dart';

/// A reusable confetti shower used behind the victory overlay.
///
/// 30 colored rectangles fall + rotate, recycled when they leave the
/// bottom edge. Pure CustomPaint + AnimationController — no asset
/// files required.
class ConfettiShower extends StatefulWidget {
  const ConfettiShower({super.key, this.count = 30, this.seed});
  final int count;
  final int? seed;

  @override
  State<ConfettiShower> createState() => _ConfettiShowerState();
}

class _ConfettiShowerState extends State<ConfettiShower>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<_Confetto> _pieces;
  final Random _rng = Random();

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    _pieces = List.generate(widget.count, (_) => _Confetto.random(_rng));
    // Auto-play the loop. We do NOT call repeat() to keep widget tests
    // pump-and-settle friendly; the painter uses `progress % 1.4`
    // internally so each tick still renders confetti at a new
    // position. Tests can call setState / pump without hanging.
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(covariant ConfettiShower oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_ctrl.status == AnimationStatus.completed) {
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => CustomPaint(
        painter: _ConfettiPainter(
          pieces: _pieces,
          progress: _ctrl.value,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _Confetto {
  _Confetto({
    required this.color,
    required this.x,
    required this.size,
    required this.fallSpeed,
    required this.rotSpeed,
    required this.swayAmp,
    required this.swaySpeed,
    required this.phase,
    required this.startY,
  });
  final Color color;
  double x;
  final double size;
  final double fallSpeed;
  final double rotSpeed;
  final double swayAmp;
  final double swaySpeed;
  final double phase;
  final double startY;

  factory _Confetto.random(Random rng) {
    const palette = [
      Color(0xFF4C73FF),
      Color(0xFFFF6584),
      Color(0xFFFFC837),
      Color(0xFF30D158),
      Color(0xFFA073FF),
      Color(0xFF22D3EE),
    ];
    return _Confetto(
      color: palette[rng.nextInt(palette.length)],
      x: rng.nextDouble(),
      size: 6 + rng.nextDouble() * 6,
      fallSpeed: 1.0 + rng.nextDouble() * 0.6,
      rotSpeed: (rng.nextDouble() - 0.5) * 6,
      swayAmp: 12 + rng.nextDouble() * 16,
      swaySpeed: 0.6 + rng.nextDouble() * 1.0,
      phase: rng.nextDouble() * 6.28,
      startY: -rng.nextDouble() * 0.4,
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.pieces, required this.progress});
  final List<_Confetto> pieces;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    for (final p in pieces) {
      final baseY = p.startY + progress * p.fallSpeed * 2.2;
      final modY = baseY % 1.4;
      final y = modY * h;
      final sway = sin(progress * 6 * p.swaySpeed + p.phase) * p.swayAmp;
      final rot = progress * 6 * p.rotSpeed + p.phase;
      canvas.save();
      canvas.translate(p.x * w + sway, y);
      canvas.rotate(rot);
      final rect = Rect.fromCenter(
        center: Offset.zero,
        width: p.size,
        height: p.size * 0.5,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        Paint()..color = p.color.withValues(alpha: 0.85),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) =>
      old.progress != progress || old.pieces != pieces;
}
