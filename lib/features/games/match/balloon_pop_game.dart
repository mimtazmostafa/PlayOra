import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/utils/random_utils.dart';
import '../game_widgets.dart';
import '../mini_game.dart';

/// Balloon Pop — tap-to-pop rising balloons.
///
/// Sky-blue gradient with balloons rising from below. Tap a balloon
/// to pop it (+10 / +15 for the gold variant). Spawn speed + wave
/// intensity rise over time. Each balloon reaching the top un-popped
/// costs a life; bombs deduct a life on tap. 3 lives total; game over
/// at 0 or when 30 balloons have been popped.
class BalloonPopGame extends MiniGame {
  const BalloonPopGame({
    super.key,
    required super.callbacks,
    this.dailyChallenge = false,
  });

  /// When true, balloon spawn positions / bomb density are seeded by
  /// today's UTC date so every player faces the same challenge on a
  /// given day.
  final bool dailyChallenge;

  @override
  State<BalloonPopGame> createState() => _State();
}

class _State extends MiniGameState<BalloonPopGame>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  // Daily challenge games share a deterministic seed so every player
  // gets the same balloon sequence on the same UTC date.
  late final Random _rng = widget.dailyChallenge
      ? Random(dailySeedFor('balloon-pop'))
      : Random();

  /// Combo state — pops within [_comboWindow] of each other scale the
  /// score and trigger a "×2!" floater.
  double _comboClock = 0;
  int _combo = 1;
  static const double _comboWindow = 1.5;

  DateTime _last = DateTime.now();

  static const int _maxLives = 5;
  static const int _popTarget = 30;
  static const double _baseSpawnInterval = 1.1; // seconds
  /// Rise speed as a fraction of canvas height per second. 0.08 = a
  /// balloon crosses the full height in ~12 seconds at wave 1.
  static const double _baseSpeed = 0.08;
  /// Normalized y-position at which a balloon is considered fully off
  /// the top of the canvas and removed (10 % of canvas height above
  /// the visible area so it doesn't disappear mid-pixel).
  static const double _offScreenMargin = 0.1;

  // Pitch-scaling haptic → balloon size/color map.
  static const List<Color> _popColors = [
    Color(0xFFEF4444),
    Color(0xFFFBBF24),
    Color(0xFF22C55E),
    Color(0xFF3B82F6),
    Color(0xFFA855F7),
    Color(0xFFF472B6),
  ];

  int _score = 0;
  int _popped = 0;
  int _lives = _maxLives;
  bool _gameOver = false;
  int _spawnTimer = 0;
  double _elapsed = 0;
  int _wave = 1;
  final List<_Balloon> _balloons = [];
  final List<_PopBurst> _bursts = [];
  final List<_FloatingText> _floaters = [];
  final List<_Debris> _debris = [];

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reportScore(_score);
      reportStats('Popped 0/$_popTarget  •  Lives $_lives/$_maxLives');
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
    _elapsed += dt;
    // Round-over freeze: spawns + balloon motion stop once the round
    // is over so the player sees their final board, not new ones.
    final active = !_gameOver;

    // Speed-wave progression (scales both speed and spawn rate).
    final waveSpeed = 1.0 + (_elapsed / 60.0) * 0.6;
    final waveSpawnInterval =
        (_baseSpawnInterval - _elapsed * 0.01).clamp(0.45, 1.5);
    final bombChance = (0.05 + _elapsed / 60.0 * 0.15).clamp(0.05, 0.20);

    // Combo decay — if no pop happened within the combo window, reset.
    var comboChanged = false;
    if (_comboClock > 0) {
      _comboClock = (_comboClock - dt).clamp(0.0, 99.0);
      if (_comboClock == 0 && _combo > 1) {
        _combo = 1;
        comboChanged = true;
      }
    }

    setState(() {
      // Float balloons up.
      for (final b in _balloons) {
        b.y -= active ? _baseSpeed * waveSpeed * dt : 0;
        b.wobble += dt * 2;
        if (b.kind == _BalloonKind.bomb) {
          b.fuseT += dt;
        }
      }
      _balloons.removeWhere((b) {
        if (b.y < -_offScreenMargin) {
          if (b.kind == _BalloonKind.bomb) {
            // Bombs off-screen = no penalty (they didn't reach you).
            return true;
          }
          _lives -= 1;
          // Combo breaks when a balloon escapes un-popped.
          _combo = 1;
          _comboClock = 0;
          haptic(HapticFeedbackType.heavy);
          _floaters.add(_FloatingText(
            x: b.x,
            y: 0.1,
            text: 'LOST LIFE',
            color: const Color(0xFFEF4444),
          ));
          reportStats(_statsLine());
          if (_lives <= 0) {
            _endGame();
          }
          return true;
        }
        return false;
      });

      // Spawn balloons.
      if (active) {
        _spawnTimer += (dt * 1000).round();
        if (_spawnTimer > waveSpawnInterval * 1000 && _balloons.length < 8) {
          _spawnTimer = 0;
          final isBomb = _rng.nextDouble() < bombChance;
          if (isBomb) {
            _balloons.add(_Balloon(
              x: 0.1 + _rng.nextDouble() * 0.8,
              y: 1.05,
              color: const Color(0xFF111827),
              kind: _BalloonKind.bomb,
            ));
          } else {
            _balloons.add(_Balloon(
              x: 0.1 + _rng.nextDouble() * 0.8,
              y: 1.05,
              color: _popColors[_rng.nextInt(_popColors.length)],
              size: 26.0 + _rng.nextDouble() * 8.0,
            ));
          }
        }
      }

      // Animate bursts.
      for (final b in _bursts) {
        b.life -= dt * 2;
        b.r += 40 * dt;
      }
      _bursts.removeWhere((b) => b.life <= 0);

      // Animate debris (bomb fragments).
      for (final d in _debris) {
        d.vy += 280 * dt; // gravity
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

      // Wave progression (every 30 s).
      final newWave = 1 + (_elapsed ~/ 30);
      if (newWave > _wave) {
        _wave = newWave;
        _floaters.add(_FloatingText(
          x: 0.5,
          y: 0.45,
          text: 'WAVE $_wave!',
          color: const Color(0xFFFBBF24),
        ));
        haptic(HapticFeedbackType.heavy);
      }

      // Reflect combo decay in the host subtitle so the chip stays in
      // sync with the timer.
      if (comboChanged) {
        reportStats(_statsLine());
      }
    });
  }

  void _onTap(TapUpDetails d, Size size) {
    if (_gameOver) return;
    final tx = d.localPosition.dx / size.width;
    final ty = d.localPosition.dy / size.height;
    setState(() {
      _balloons.removeWhere((b) {
        // Tap within balloon radius (in canvas coords).
        final bx = size.width * b.x;
        final by = size.height * b.y;
        final dx = tx * size.width - bx;
        final dy = ty * size.height - by;
        final r = b.size;
        if (dx * dx + dy * dy < r * r) {
          if (b.kind == _BalloonKind.bomb) {
            // Bomb hit! Lose a life + reset combo.
            _lives -= 1;
            _combo = 1;
            _comboClock = 0;
            haptic(HapticFeedbackType.heavy);
            _floaters.add(_FloatingText(
              x: b.x,
              y: b.y - 0.05,
              text: 'BOOM!',
              color: const Color(0xFFEF4444),
            ));
            _bursts.add(_PopBurst(
                x: b.x, y: b.y, color: const Color(0xFFEF4444)));
            // Spawn dark debris fragments.
            final cx = b.x;
            final cy = b.y;
            for (var i = 0; i < 8; i++) {
              final angle = _rng.nextDouble() * 2 * pi;
              final speed = 80 + _rng.nextDouble() * 140;
              _debris.add(_Debris(
                x: cx,
                y: cy,
                vx: cos(angle) * speed,
                vy: sin(angle) * speed - 60,
                angle: 0,
                spin: (_rng.nextDouble() - 0.5) * 12,
                color: const Color(0xFF111827),
                life: 0.7,
              ));
            }
            reportStats(_statsLine());
            if (_lives <= 0) {
              _endGame();
            }
          } else {
            // Combo — pops within [_comboWindow] scale the score.
            // Bomb hits / un-popped escapes reset the combo.
            _comboClock = _comboWindow;
            _combo = (_combo + 1).clamp(1, 5);
            final basePts = b.size > 30 ? 15 : 10;
            final pts = basePts * _combo;
            _score += pts;
            _popped += 1;
            _bursts.add(_PopBurst(x: b.x, y: b.y, color: b.color));
            _floaters.add(_FloatingText(
              x: b.x,
              y: b.y - 0.05,
              text: _combo > 1 ? '+$pts ×$_combo' : '+$pts',
              color: _combo > 1
                  ? const Color(0xFFF472B6)
                  : const Color(0xFFFBBF24),
            ));
            if (_combo >= 2) {
              _floaters.add(_FloatingText(
                x: b.x,
                y: b.y - 0.12,
                text: 'COMBO ×$_combo!',
                color: const Color(0xFFF472B6),
              ));
            }
            haptic(b.size > 30
                ? HapticFeedbackType.medium
                : HapticFeedbackType.selection);
            reportScore(_score);
            reportStats(_statsLine());
            if (_popped >= _popTarget) {
              _endGame();
            }
          }
          return true;
        }
        return false;
      });
    });
  }

  /// Single source of truth for the host subtitle string.
  String _statsLine() {
    final comboSuffix = _combo > 1 ? ' • Combo ×$_combo' : '';
    return 'Popped $_popped/$_popTarget  •  Lives $_lives/$_maxLives$comboSuffix';
  }

  void _endGame() {
    if (_gameOver) return;
    setState(() {
      _gameOver = true;
      haptic(HapticFeedbackType.heavy);
      reportScore(_score);
      reportStats('Final: $_popped popped, $_lives lives left');
      reportGameOver();
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final size = Size(c.maxWidth, c.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _onTap(d, size),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _BalloonPainter(
                    balloons: _balloons,
                    bursts: _bursts,
                    floaters: _floaters,
                    debris: _debris,
                    wave: _wave,
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

enum _BalloonKind { pop, bomb }

class _Balloon {
  _Balloon({
    required this.x,
    required this.y,
    required this.color,
    this.size = 30.0,
    this.kind = _BalloonKind.pop,
  });
  double x;
  double y;
  Color color;
  double size;
  _BalloonKind kind;
  double wobble = 0;
  double fuseT = 0; // bomb fuse timer
}

class _Debris {
  _Debris({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.angle,
    required this.spin,
    required this.color,
    required this.life,
  });
  double x;
  double y;
  double vx;
  double vy;
  double angle;
  double spin;
  Color color;
  double life;
}

class _PopBurst {
  _PopBurst({required this.x, required this.y, required this.color}) : life = 1.0, r = 0;
  double x;
  double y;
  Color color;
  double life;
  double r;
}

class _FloatingText {
  _FloatingText({required this.x, required this.y, required this.text, required this.color}) : life = 1.0;
  double x;
  double y;
  String text;
  Color color;
  double life;
}

class _BalloonPainter extends CustomPainter {
  _BalloonPainter({
    required this.balloons,
    required this.bursts,
    required this.floaters,
    required this.debris,
    required this.wave,
  });
  final List<_Balloon> balloons;
  final List<_PopBurst> bursts;
  final List<_FloatingText> floaters;
  final List<_Debris> debris;
  final int wave;

  @override
  void paint(Canvas canvas, Size size) {
    // Sky gradient.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF38BDF8), Color(0xFFBAE6FD)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    // Clouds.
    final cloudPaint = Paint()..color = Colors.white.withValues(alpha: 0.5);
    for (final c in [
      [0.2, 0.15, 50.0],
      [0.7, 0.25, 60.0],
      [0.4, 0.4, 40.0],
    ]) {
      final cx = size.width * c[0];
      final cy = size.height * c[1];
      final r = c[2];
      canvas.drawCircle(Offset(cx, cy), r, cloudPaint);
      canvas.drawCircle(Offset(cx - r * 0.6, cy), r * 0.7, cloudPaint);
      canvas.drawCircle(Offset(cx + r * 0.6, cy), r * 0.7, cloudPaint);
    }

    // Balloons.
    for (final b in balloons) {
      final cx = size.width * b.x + sin(b.wobble) * 4;
      final cy = size.height * b.y;
      final r = b.size;
      final isBomb = b.kind == _BalloonKind.bomb;
      // Shadow.
      canvas.drawCircle(
        Offset(cx + 2, cy + 3),
        r,
        Paint()..color = Colors.black.withValues(alpha: 0.18),
      );
      if (isBomb) {
        // Bomb body with subtle red glow (heat).
        canvas.drawCircle(
          Offset(cx, cy),
          r,
          Paint()
            ..shader = RadialGradient(
              colors: [
                const Color(0xFF374151),
                const Color(0xFF111827),
                const Color(0xFF000000),
              ],
            ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r)),
        );
        // Blinking fuse spark.
        final blink = (sin(b.fuseT * 8) > 0)
            ? const Color(0xFFFACC15)
            : const Color(0xFFEF4444);
        canvas.drawCircle(
          Offset(cx + r * 0.4, cy - r * 0.7),
          5,
          Paint()..color = blink,
        );
        canvas.drawCircle(
          Offset(cx + r * 0.4, cy - r * 0.7),
          9,
          Paint()
            ..color = blink.withValues(alpha: 0.5)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
        // Fuse line.
        canvas.drawLine(
          Offset(cx, cy - r),
          Offset(cx + r * 0.4, cy - r * 0.7),
          Paint()
            ..color = const Color(0xFF94A3B8)
            ..strokeWidth = 2,
        );
      } else {
        // Body with vertical gradient (balloon shine).
        canvas.drawCircle(
          Offset(cx, cy),
          r,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(b.color, Colors.white, 0.30) ?? b.color,
                b.color,
                Color.lerp(b.color, Colors.black, 0.20) ?? b.color,
              ],
            ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r)),
        );
        // Specular highlight.
        canvas.drawCircle(
          Offset(cx - r * 0.35, cy - r * 0.4),
          r * 0.18,
          Paint()..color = Colors.white.withValues(alpha: 0.7),
        );
        // Outline.
        canvas.drawCircle(
          Offset(cx, cy),
          r,
          Paint()
            ..color = Color.lerp(b.color, Colors.black, 0.4) ?? b.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
      // Knot (always).
      final knot = Path()
        ..moveTo(cx - 4, cy + r)
        ..lineTo(cx, cy + r + 8)
        ..lineTo(cx + 4, cy + r)
        ..close();
      canvas.drawPath(
        knot,
        Paint()..color = isBomb ? const Color(0xFF374151) : b.color,
      );
      // String.
      final string = Path()
        ..moveTo(cx, cy + r + 8)
        ..quadraticBezierTo(
          cx + sin(b.wobble) * 8,
          cy + r + 30,
          cx + sin(b.wobble * 2) * 4,
          cy + r + 60,
        );
      canvas.drawPath(
        string,
        Paint()
          ..color = const Color(0xFF94A3B8)
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke,
      );
    }

    // Debris (bomb fragments).
    for (final d in debris) {
      canvas.save();
      canvas.translate(d.x, d.y);
      canvas.rotate(d.angle);
      final alpha = d.life.clamp(0.0, 0.7) / 0.7;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: 8, height: 8),
          const Radius.circular(1.5),
        ),
        Paint()..color = d.color.withValues(alpha: alpha),
      );
      canvas.restore();
    }

    // Pop bursts.
    for (final burst in bursts) {
      final cx = size.width * burst.x;
      final cy = size.height * burst.y;
      final alpha = burst.life.clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(cx, cy),
        30 + burst.r,
        Paint()..color = burst.color.withValues(alpha: alpha * 0.4),
      );
      // Star burst.
      for (var i = 0; i < 6; i++) {
        final angle = i * (pi / 3) + burst.r;
        canvas.drawLine(
          Offset(cx, cy),
          Offset(cx + cos(angle) * (40 + burst.r), cy + sin(angle) * (40 + burst.r)),
          Paint()
            ..color = burst.color.withValues(alpha: alpha)
            ..strokeWidth = 3,
        );
      }
    }

    // Floaters.
    for (final f in floaters) {
      final alpha = (f.life / 1.0).clamp(0.0, 1.0);
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
  bool shouldRepaint(_BalloonPainter old) =>
      old.balloons != balloons ||
      old.bursts != bursts ||
      old.floaters != floaters ||
      old.debris != debris ||
      old.wave != wave;
}
