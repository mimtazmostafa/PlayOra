import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../game_widgets.dart';
import '../mini_game.dart';

/// Tower Builder — precision stacking.
///
/// Crane at top sways a block in a sin-wave. Tap to release; the block
/// falls and lands on the stack below. Each block may be sliced: any
/// overhang beyond the block beneath it spawns tumbling debris and
/// the new block is clipped to the overlap zone. Perfect drops (offset
/// < 4 dp) award bonus +30 and grow the block's stored width slightly
/// (up to +12 dp cumulative). The tower sways based on the running
/// center-of-mass offset — severe offset tips the tower (game over).
class TowerBuilderGame extends MiniGame {
  const TowerBuilderGame({super.key, required super.callbacks});

  @override
  State<TowerBuilderGame> createState() => _State();
}

class _State extends MiniGameState<TowerBuilderGame>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final Random _rng = Random();
  DateTime _last = DateTime.now();

  double _swingPhase = 0;
  int _score = 0;
  int _blocks = 0;
  int _perfectStreak = 0;
  bool _gameOver = false;
  static const int _maxBlocks = 20;
  static const double _baseBlockWidth = 0.4;
  static const double _blockHeight = 0.07;
  // PERFECT-drop bonus: each streak of perfect drops grows the new
  // block's width by this much, capped at _maxPerfectGrowth.
  static const double _perfectGrowthStep = 0.012;
  static const double _maxPerfectGrowth = 0.12;

  final List<_Block> _stack = [];
  final List<_Debris> _debris = [];
  double _activeX = 0.5;
  bool _falling = false;
  double _fallY = 0.0;
  // Sway: each block's screen-X offset from canvas center, accumulated.
  double _centerOfMassOffset = 0; // fraction of canvas width
  double _swayT = 0;
  double _tipTimer = 0;
  bool _tippingOver = false;
  final List<_FloatingText> _floaters = [];
  final List<_Flash> _flashes = [];

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reportScore(_score);
      reportStats('Height 0m  •  Ready');
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _tick(Duration _) {
    if (!mounted) return;
    if (_gameOver) {
      if (_ticker.isActive) _ticker.stop();
      return;
    }
    final now = DateTime.now();
    final dt = now.difference(_last).inMicroseconds / 1e6;
    _last = now;

    setState(() {
      _swingPhase += dt * 1.4;
      _swayT += dt;
      // Active block swings horizontally between edges.
      _activeX = 0.5 + sin(_swingPhase) * 0.45;

      if (_falling) {
        _fallY += 320 * dt;
        final topOfStack = _stack.length * _blockHeight;
        if (_fallY >= 1.0 - topOfStack - _blockHeight) {
          _land();
        }
      }

      // Debris falls with gravity + tumble.
      for (final d in _debris) {
        d.vy += 380 * dt;
        d.x += d.vx * dt;
        d.y += d.vy * dt;
        d.angle += d.spin * dt;
        d.life -= dt;
      }
      _debris.removeWhere((d) => d.life <= 0);

      // Floaters.
      for (final f in _floaters) {
        f.y -= 30 * dt;
        f.life -= dt;
      }
      _floaters.removeWhere((f) => f.life <= 0);

      // Flash overlay decay.
      for (final fl in _flashes) {
        fl.life -= dt;
      }
      _flashes.removeWhere((fl) => fl.life <= 0);

      // Tower tipping check.
      if (_stack.length >= 3) {
        final absOffset = _centerOfMassOffset.abs();
        if (absOffset > 0.16) {
          _tipTimer += dt;
        } else {
          _tipTimer = (_tipTimer - dt).clamp(0.0, 100.0);
        }
        if (_tipTimer > 1.5 && !_tippingOver) {
          _tippingOver = true;
          _gameOver = true;
          haptic(HapticFeedbackType.heavy);
          _floaters.add(_FloatingText(
            x: 0.5,
            y: 0.5,
            text: 'TOWER FELL!',
            color: const Color(0xFFEF4444),
          ));
          reportScore(_score);
          reportStats('Tower tipped! $_blocks blocks stacked');
          reportGameOver();
        }
      }
    });
  }

  void _drop() {
    if (_gameOver || _falling) return;
    setState(() {
      _falling = true;
      _fallY = 0.0;
      haptic(HapticFeedbackType.selection);
    });
  }

  void _land() {
    _falling = false;
    final newBlock = _Block(
      x: _activeX - _baseBlockWidth / 2,
      colorIndex: _rng.nextInt(5),
    );

    // First block lands centered.
    if (_stack.isEmpty) {
      newBlock.x = 0.5 - newBlock.width / 2;
      _stack.add(newBlock);
      _blocks = 1;
      _score += 15;
      _floaters.add(_FloatingText(
        x: 0.5,
        y: 0.4,
        text: '+15',
        color: const Color(0xFFFBBF24),
      ));
      haptic(HapticFeedbackType.medium);
      reportScore(_score);
      reportStats('Height ${_blocks}m  •  Steady!');
      return;
    }

    final last = _stack.last;
    final aLeft = last.x;
    final aRight = last.x + last.width;
    final bLeft = newBlock.x;
    final bRight = newBlock.x + newBlock.width;
    final overlap = (min(aRight, bRight) - max(aLeft, bLeft))
        .clamp(0.0, 1.0);
    if (overlap < 0.05) {
      _gameOver = true;
      haptic(HapticFeedbackType.heavy);
      _floaters.add(_FloatingText(
        x: 0.5,
        y: 0.5,
        text: 'MISS!',
        color: const Color(0xFFEF4444),
      ));
      reportScore(_score);
      reportStats('Final: $_blocks blocks stacked');
      reportGameOver();
      return;
    }

    // Center the new block on the overlap zone.
    final overlapLeft = max(aLeft, bLeft);
    newBlock.x = overlapLeft;
    newBlock.width = overlap;

    // Perfect detection: offset (in screen px) is small.
    // Approximate via fraction of canvas: < 0.01 of canvas width.
    final offset = (newBlock.x + newBlock.width / 2) -
        (last.x + last.width / 2);
    final isPerfect = offset.abs() < 0.01;

    // PERFECT bonus: each consecutive perfect drop adds growth (capped)
      // and a +30 score bonus. Imperfect drops reset the streak.
    if (isPerfect) {
      _perfectStreak = (_perfectStreak + 1).clamp(0, 50);
      final streakBonus = _perfectStreak * _perfectGrowthStep;
      final grow = streakBonus.clamp(0.0, _maxPerfectGrowth);
      newBlock.width += grow;
      // Re-center after growth.
      newBlock.x = (last.x + last.width / 2) - newBlock.width / 2;
      _score += 30;
      _floaters.add(_FloatingText(
        x: newBlock.x + newBlock.width / 2,
        y: 0.4,
        text: _perfectStreak > 1 ? 'PERFECT ×$_perfectStreak +30' : 'PERFECT +30',
        color: const Color(0xFFFACC15),
      ));
      _flashes.add(_Flash(life: 0.2));
      haptic(HapticFeedbackType.medium);
    } else {
      _perfectStreak = 0;
      _score += 15;
      _floaters.add(_FloatingText(
        x: newBlock.x + newBlock.width / 2,
        y: 0.4,
        text: '+15',
        color: const Color(0xFF22C55E),
      ));
      haptic(HapticFeedbackType.light);
    }

    // Sliced overhang debris: spawn small rectangles outside the
    // overlap zone.
    if (bLeft < overlapLeft) {
      final debrisW = overlapLeft - bLeft;
      _spawnDebris(bLeft, debrisW, _blockHeight, last.colorIndex);
    }
    if (bRight > overlapLeft + overlap) {
      final debrisW = bRight - (overlapLeft + overlap);
      _spawnDebris(overlapLeft + overlap, debrisW, _blockHeight, newBlock.colorIndex);
    }

    _stack.add(newBlock);
    _blocks += 1;
    // Recompute center-of-mass offset (canvas-fraction).
    double sum = 0;
    for (final b in _stack) {
      sum += (b.x + b.width / 2) - 0.5;
    }
    _centerOfMassOffset = sum / _stack.length;

    reportScore(_score);
    reportStats(
        'Height ${_blocks}m  •  ${isPerfect ? "PERFECT!" : "Stack"}  •  Off ${(_centerOfMassOffset * 100).toStringAsFixed(1)}%');

    if (_blocks >= _maxBlocks) {
      _gameOver = true;
      haptic(HapticFeedbackType.heavy);
      reportScore(_score);
      reportStats('Tower complete! $_blocks blocks');
      reportGameOver();
    }
  }

  void _spawnDebris(
      double xFrac, double wFrac, double hFrac, int colorIndex) {
    // Spawn 2 small debris fragments.
    for (var i = 0; i < 2; i++) {
      _debris.add(_Debris(
        x: xFrac + wFrac * (i == 0 ? 0.15 : 0.6),
        y: 1.0 - (_stack.length + 1) * _blockHeight,
        vx: (_rng.nextDouble() - 0.5) * 120,
        vy: -80 - _rng.nextDouble() * 60,
        angle: 0,
        spin: (_rng.nextDouble() - 0.5) * 12,
        colorIndex: colorIndex,
        width: wFrac * 0.4,
        life: 0.7,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _drop,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _TowerPainter(
                    activeX: _activeX,
                    falling: _falling,
                    fallY: _fallY,
                    stack: _stack,
                    floaters: _floaters,
                    flashes: _flashes,
                    debris: _debris,
                    centerOfMassOffset: _centerOfMassOffset,
                    swayT: _swayT,
                    blockWidth: _baseBlockWidth,
                    blockHeight: _blockHeight,
                    tipping: _tippingOver,
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

class _Block {
  _Block({required this.x, required this.colorIndex});
  double x;
  double width = 0.4;
  int colorIndex;
}

class _Debris {
  _Debris({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.angle,
    required this.spin,
    required this.colorIndex,
    required this.width,
    required this.life,
  });
  double x; // fraction of canvas
  double y; // fraction of canvas
  double vx; // fraction/s
  double vy; // fraction/s
  double angle;
  double spin;
  int colorIndex;
  double width;
  double life;
}

class _Flash {
  _Flash({required this.life});
  double life;
}

class _FloatingText {
  _FloatingText({required this.x, required this.y, required this.text, required this.color}) : life = 1.0;
  double x;
  double y;
  String text;
  Color color;
  double life;
}

class _TowerPainter extends CustomPainter {
  _TowerPainter({
    required this.activeX,
    required this.falling,
    required this.fallY,
    required this.stack,
    required this.floaters,
    required this.flashes,
    required this.debris,
    required this.centerOfMassOffset,
    required this.swayT,
    required this.blockWidth,
    required this.blockHeight,
    required this.tipping,
  });
  final double activeX;
  final bool falling;
  final double fallY;
  final List<_Block> stack;
  final List<_FloatingText> floaters;
  final List<_Flash> flashes;
  final List<_Debris> debris;
  final double centerOfMassOffset;
  final double swayT;
  final double blockWidth;
  final double blockHeight;
  final bool tipping;

  static const List<Color> _colors = [
    Color(0xFFEF4444),
    Color(0xFFFBBF24),
    Color(0xFF22C55E),
    Color(0xFF3B82F6),
    Color(0xFFA855F7),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    // Sky gradient.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFEF3C7), Color(0xFFFCA5A5)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    // Tower sway transform.
    final absOffset = centerOfMassOffset.abs();
    final swayAngle = tipping
        ? centerOfMassOffset * 1.6
        : sin(swayT * 3) * absOffset * 0.6;
    final swayX = tipping ? centerOfMassOffset * size.width : sin(swayT * 3) * absOffset * 12;

    // Crane at top.
    final craneY = 30.0;
    canvas.drawLine(
      Offset(0, craneY + 12),
      Offset(size.width * 0.5, craneY + 12),
      Paint()
        ..color = const Color(0xFF334155)
        ..strokeWidth = 4,
    );
    canvas.drawCircle(
      Offset(size.width * 0.5, craneY + 12),
      8,
      Paint()..color = const Color(0xFF334155),
    );

    // Active (swinging or falling) block.
    final blockW = size.width * blockWidth;
    final blockH = size.height * blockHeight;
    final activePx = size.width * activeX - blockW / 2;
    final activeY = falling
        ? size.height * fallY
        : craneY + 24;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(activePx, activeY, blockW, blockH),
        const Radius.circular(4),
      ),
      Paint()..color = const Color(0xFFFB923C),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(activePx + 4, activeY + 4, blockW - 8, blockH / 3),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFFFED7AA),
    );
    // Crane cable.
    if (!falling) {
      canvas.drawLine(
        Offset(size.width * 0.5, craneY + 12),
        Offset(activePx + blockW / 2, activeY),
        Paint()
          ..color = const Color(0xFF334155)
          ..strokeWidth = 2,
      );
    }

    // Stack — wrapped in a sway transform.
    canvas.save();
    canvas.translate(swayX, 0);
    canvas.rotate(swayAngle);

    for (var i = 0; i < stack.length; i++) {
      final b = stack[i];
      final y = size.height - (i + 1) * blockH;
      final rect = Rect.fromLTWH(
        size.width * b.x,
        y,
        size.width * b.width,
        blockH,
      );
      // Shadow.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect.translate(0, 2),
          const Radius.circular(4),
        ),
        Paint()..color = Colors.black.withValues(alpha: 0.25),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        Paint()..color = _colors[b.colorIndex % _colors.length],
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(rect.left + 4, rect.top + 3, rect.width - 8, blockH / 3),
          const Radius.circular(2),
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.3),
      );
    }
    canvas.restore();

    // Debris.
    for (final d in debris) {
      canvas.save();
      final cx = size.width * (d.x + d.width / 2);
      final cy = size.height * d.y;
      canvas.translate(cx, cy);
      canvas.rotate(d.angle);
      final alpha = (d.life / 0.7).clamp(0.0, 1.0);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset.zero,
              width: size.width * d.width,
              height: size.height * blockHeight * 0.7),
          const Radius.circular(2),
        ),
        Paint()
          ..color = _colors[d.colorIndex % _colors.length].withValues(alpha: alpha),
      );
      canvas.restore();
    }

    // Ground.
    final groundY = size.height - 6;
    canvas.drawRect(
      Rect.fromLTWH(0, groundY, size.width, 6),
      Paint()..color = const Color(0xFF334155),
    );

    // White flash overlay (PERFECT!).
    for (final fl in flashes) {
      final alpha = (fl.life / 0.2).clamp(0.0, 1.0) * 0.35;
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = Colors.white.withValues(alpha: alpha),
      );
    }

    // Floaters.
    for (final f in floaters) {
      final alpha = (f.life / 1.0).clamp(0.0, 1.0);
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

  @override
  bool shouldRepaint(_TowerPainter old) =>
      old.activeX != activeX ||
      old.falling != falling ||
      old.fallY != fallY ||
      old.stack != stack ||
      old.floaters != floaters ||
      old.flashes != flashes ||
      old.debris != debris ||
      old.centerOfMassOffset != centerOfMassOffset ||
      old.swayT != swayT ||
      old.tipping != tipping;
}
