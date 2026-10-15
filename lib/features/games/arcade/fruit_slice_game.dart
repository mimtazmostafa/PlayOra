import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/random_utils.dart';
import '../game_widgets.dart';
import '../mini_game.dart';

/// Fruit Slice — juicy vector slicing arcade game.
///
/// Visual upgrade (plan: tropical-slicing-zephyr):
///   * Warm pastel gradient canvas (soft coral-pink → light blue) with
///     a subtle radial light overlay at the top.
///   * Top HUD bar — white circular Pause button + LEVEL badge pill on
///     left, rounded white `SCORE N,NNN` card centred, red heart-lives
///     pill on right (replacing the legacy dark `_TopStatusBar`).
///   * Vibrant vector fruits (watermelon, kiwi, pineapple, orange,
///     dragon fruit, bomb) with thick dark outlines, body gradients
///     and glossy highlights.
///   * Slice halves drawn with detailed cross-sections (rind rings,
///     seeds, segmented flesh) that fly apart and tumble.
///   * Glowing sharp blade trail — outer white glow + cyan mid +
///     cyan-white gradient core + yellow edge shimmer + white spine.
///   * 3-D combo floaters — `+N`, `2x COMBO!`, `JUICY!`, `BOMB!` etc.
///     with star trail particles; layered TextPainter passes for the
///     glow / stroke / drop-shadow / base.
///   * Bombs trigger screen flash + shake + 20-particle explosion +
///     heavy haptic + lose 1 heart.
///   * First-launch tutorial overlay — "Swipe across fruits to
///     slice!" capsule + animated cartoon hand performing a diagonal
///     swipe motion; auto-dismissed after 6 s or on first swipe.
///   * Direct `HapticFeedback.lightImpact / mediumImpact / heavyImpact`
///     calls (per spec). Host-proxy calls kept as fallback for audio
///     cue compatibility.
///
/// Engine preserved from previous version: parabolic toss physics
/// (gravity-driven), segment→circle slice detection, halves flying
/// perpendicular to slice direction, combo multiplier, hearts on
/// fall-through, score floaters.
///
/// Public surface kept byte-identical with the previous engine so the
/// dispatcher (`case 'fruit-slice'`) keeps resolving:
///   `class FruitSliceGame extends MiniGame`
///   `const FruitSliceGame({super.key, required super.callbacks})`
class FruitSliceGame extends MiniGame {
  const FruitSliceGame({
    super.key,
    required super.callbacks,
    this.dailyChallenge = false,
  });

  /// When true, the spawn sequence is seeded by today's UTC date so
  /// every player gets the same bomb placement / fruit order on a
  /// given day.
  final bool dailyChallenge;

  @override
  State<FruitSliceGame> createState() => _FruitSliceState();
}

enum _FruitKind {
  watermelon,
  kiwi,
  pineapple,
  orange,
  dragonFruit,
  bomb,
}

class _FruitSliceState extends MiniGameState<FruitSliceGame>
    with TickerProviderStateMixin {
  // ───────────────────────────────────────────────────────────────
  // Tuning constants
  // ───────────────────────────────────────────────────────────────

  static const double _gravity = 380; // px/s²
  // Slower spawn gives the player time to actually swipe and slice —
  // a 1.1 s interval combined with 3 lives meant the game ended in
  // ~2–4 s if the player hadn't picked up the swipe gesture yet.
  static const double _spawnInterval = 2.4; // seconds
  static const double _tutorialDuration = 3.0;
  static const int _maxLives = 5;

  // ───────────────────────────────────────────────────────────────
  // State
  // ───────────────────────────────────────────────────────────────

  late final Ticker _ticker;
  DateTime _last = DateTime.now();
  double _spawnTimer = 0;
  // Daily challenge games share a deterministic seed so every player
  // gets the same fruit sequence on the same UTC date.
  late final Random _rng = widget.dailyChallenge
      ? Random(dailySeedFor('fruit-slice'))
      : Random();

  final List<_Fruit> _fruits = [];
  final List<_FruitHalf> _halves = [];
  final List<_Particle> _particles = [];
  final List<_SlashTrail> _trail = [];
  final List<_Floater> _floaters = [];
  final List<_Star> _stars = [];

  int _score = 0;
  int _lives = _maxLives;
  int _combo = 0;
  int _bestCombo = 0;
  bool _gameOver = false;
  Offset? _lastTouch;

  // Screen flash + shake.
  double _flashTime = 0;
  double _shakeTime = 0;
  double _shakeMag = 0;

  // Heart pulse (visual feedback when slice / heart lost).
  double _heartsPulse = 0;

  // Tutorial state.
  bool _showTutorial = true;
  // ignore: prefer_final_fields
  double _tutorialElapsed = 0;
  bool _tutorialDismissed = false;

  // Idle time for bomb spark flicker + tutorial hand animation.
  double _idleTime = 0;

  double _screenW = 0;
  double _screenH = 0;
  double _gameTop = 80;
  double _gameBottom = 0;

  // ───────────────────────────────────────────────────────────────
  // Lifecycle
  // ───────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reportScore(_score);
      _refreshStats();
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
    if (_screenW == 0) return;
    final now = DateTime.now();
    final dt = now.difference(_last).inMicroseconds / 1e6;
    _last = now;

    setState(() {
      // Spawn fruits periodically.
      _spawnTimer += dt;
      if (_spawnTimer > _spawnInterval) {
        _spawnTimer = 0;
        _spawnWave();
      }

      // Update fruits (parabolic motion under gravity).
      for (final f in _fruits) {
        f.vy += _gravity * dt;
        f.x += f.vx * dt;
        f.y += f.vy * dt;
        f.angle += f.spin * dt;
      }

      // Remove fruits that fall off-screen without being sliced.
      final fallen = _fruits.where((f) => f.y > _screenH + 60).toList();
      for (final f in fallen) {
        _fruits.remove(f);
        if (f.kind != _FruitKind.bomb) {
          _loseLife('Missed!');
        }
      }

      // Update halves.
      for (final h in _halves) {
        h.vy += _gravity * dt;
        h.x += h.vx * dt;
        h.y += h.vy * dt;
        h.angle += h.spin * dt;
        h.life -= dt;
      }
      _halves.removeWhere((h) => h.life <= 0 || h.y > _screenH + 50);

      // Update particles.
      for (final p in _particles) {
        p.x += p.vx * dt;
        p.y += p.vy * dt;
        p.vy += 60 * dt;
        p.life -= dt;
      }
      _particles.removeWhere((p) => p.life <= 0);

      // Trail decay.
      for (final t in _trail) {
        t.life -= dt;
      }
      _trail.removeWhere((t) => t.life <= 0);

      // Floaters drift up + fade.
      for (final f in _floaters) {
        f.y -= 60 * dt;
        f.life -= dt;
      }
      _floaters.removeWhere((f) => f.life <= 0);

      // Stars drift outward + fade.
      for (final s in _stars) {
        s.x += s.vx * dt;
        s.y += s.vy * dt;
        s.life -= dt;
        s.rot += s.spin * dt;
      }
      _stars.removeWhere((s) => s.life <= 0);

      // Tutorial auto-dismiss after timeout.
      if (_showTutorial && !_tutorialDismissed) {
        _tutorialElapsed += dt;
        if (_tutorialElapsed > _tutorialDuration) {
          _dismissTutorial();
        }
      }

      // Screen shake decay.
      if (_shakeTime > 0) {
        _shakeTime = (_shakeTime - dt).clamp(0.0, 99.0);
      }
      if (_flashTime > 0) {
        _flashTime = (_flashTime - dt).clamp(0.0, 99.0);
      }

      // Idle animations (bomb spark, tutorial hand, hearts pulse).
      _idleTime += dt;
      if (_heartsPulse > 0) {
        _heartsPulse = (_heartsPulse - dt * 4).clamp(0.0, 1.0);
      }
    });
  }

  void _spawnWave() {
    final waveSize = 1 + _rng.nextInt(3);
    // Hoist screen-relative constants out of the per-fruit loop.
    final targetSpread = _screenW * 0.6;
    final targetBase = _screenW * 0.2;
    final peakSpread = _screenH * 0.20;
    final peakBase = _screenH * 0.30;
    final startY = _screenH + 40; // offscreen below — fruit rises INTO play area
    for (var i = 0; i < waveSize; i++) {
      final fromLeft = _rng.nextBool();
      final startX = fromLeft ? -30.0 : _screenW + 30.0;
      final targetX = targetBase + _rng.nextDouble() * targetSpread;
      final peakY = peakBase + _rng.nextDouble() * peakSpread;
      final dy = peakY - startY;
      final tUp = sqrt(-2 * dy / _gravity);
      final vy = -sqrt(2 * -_gravity * dy);
      // Descent must end at the off-screen threshold (matches the
      // despawn check in _tick), not at the visible floor — using
      // _gameBottom here made the term negative and produced NaN
      // velocities, so fruits had NaN coordinates and never painted.
      final tTotal = tUp + sqrt(2 * (_screenH + 60 - peakY) / _gravity);
      final vx = (targetX - startX) / tTotal;

      final kindRoll = _rng.nextInt(20);
      _FruitKind kind;
      if (kindRoll < 2) {
        kind = _FruitKind.bomb;
      } else if (kindRoll < 6) {
        kind = _FruitKind.watermelon;
      } else if (kindRoll < 10) {
        kind = _FruitKind.kiwi;
      } else if (kindRoll < 14) {
        kind = _FruitKind.pineapple;
      } else if (kindRoll < 17) {
        kind = _FruitKind.orange;
      } else {
        kind = _FruitKind.dragonFruit;
      }
      _fruits.add(_Fruit(
        x: startX,
        y: startY,
        vx: vx,
        vy: vy,
        angle: 0,
        spin: (_rng.nextDouble() - 0.5) * 6,
        radius: _radiusFor(kind),
        kind: kind,
      ));
    }
  }

  double _radiusFor(_FruitKind k) {
    switch (k) {
      case _FruitKind.watermelon:
        return 36;
      case _FruitKind.pineapple:
        return 32;
      case _FruitKind.dragonFruit:
        return 30;
      case _FruitKind.kiwi:
        return 26;
      case _FruitKind.orange:
        return 28;
      case _FruitKind.bomb:
        return 26;
    }
  }

  // ───────────────────────────────────────────────────────────────
  // Slice detection
  // ───────────────────────────────────────────────────────────────

  void _onPanStart(DragStartDetails d) {
    if (_gameOver) return;
    HapticFeedback.selectionClick();
    _dismissTutorial();
    setState(() {
      _trail.clear();
      _lastTouch = d.localPosition;
      _trail.add(_SlashTrail(
        x: d.localPosition.dx,
        y: d.localPosition.dy,
      ));
    });
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_gameOver || _lastTouch == null) return;
    final pos = d.localPosition;
    final last = _lastTouch!;
    if ((pos - last).distance < 4) return;

    setState(() {
      _trail.add(_SlashTrail(x: pos.dx, y: pos.dy));
      _lastTouch = pos;

      // Check slice hits for any fruit whose center is near the trail
      // segment we just drew.
      final segmentStart = last;
      final segmentEnd = pos;
      for (final f in _fruits.toList()) {
        if (f.sliced) continue;
        final dist = _distToSegment(
          Offset(f.x, f.y),
          segmentStart,
          segmentEnd,
        );
        if (dist < f.radius + 12) {
          _sliceFruit(f, segmentStart, segmentEnd);
        }
      }
    });
  }

  void _onPanEnd(DragEndDetails _) {
    setState(() {
      _trail.clear();
      _lastTouch = null;
      _combo = 0;
    });
  }

  void _sliceFruit(_Fruit f, [Offset? sliceFrom, Offset? sliceTo]) {
    f.sliced = true;
    if (f.kind == _FruitKind.bomb) {
      _explodeBomb(f);
      return;
    }
    _combo += 1;
    if (_combo > _bestCombo) _bestCombo = _combo;
    final isCombo = _combo >= 3;
    final basePts = f.kind == _FruitKind.watermelon
        ? 50
        : f.kind == _FruitKind.pineapple
            ? 40
            : 25;
    final mult = _combo >= 4 ? 4 : (_combo == 3 ? 3 : (_combo == 2 ? 2 : 1));
    final pts = basePts * mult;
    _score += pts;
    _heartsPulse = 1.0;

    // Compute slice direction (unit vector) + perpendicular normal.
    Offset sliceDir;
    if (sliceFrom != null && sliceTo != null) {
      final raw = sliceTo - sliceFrom;
      final len = raw.distance;
      sliceDir = len > 0 ? raw / len : Offset(1, 0);
    } else {
      final a = atan2(f.vy, f.vx);
      sliceDir = Offset(cos(a), sin(a));
    }
    final sliceNormal = Offset(-sliceDir.dy, sliceDir.dx);
    final halfSpeed = 240.0;

    _halves.add(_FruitHalf(
      x: f.x - sliceNormal.dx * 6,
      y: f.y - sliceNormal.dy * 6,
      vx: sliceNormal.dx * halfSpeed + f.vx * 0.3,
      vy: sliceNormal.dy * halfSpeed + f.vy * 0.3 - 60,
      angle: -0.3,
      spin: -5,
      life: 1.2,
      kind: f.kind,
      side: -1,
    ));
    _halves.add(_FruitHalf(
      x: f.x + sliceNormal.dx * 6,
      y: f.y + sliceNormal.dy * 6,
      vx: -sliceNormal.dx * halfSpeed + f.vx * 0.3,
      vy: -sliceNormal.dy * halfSpeed + f.vy * 0.3 - 60,
      angle: 0.3,
      spin: 5,
      life: 1.2,
      kind: f.kind,
      side: 1,
    ));

    _spawnExplosion(f.x, f.y, _fruitColor(f.kind));
    _spawnStars(f.x, f.y, isCombo ? 10 : 6, _fruitColor(f.kind));

    // Score floater.
    _floaters.add(_Floater(
      x: f.x,
      y: f.y - 24,
      text: '+$pts',
      color: const Color(0xFFFFC837),
      fontSize: isCombo ? 24 : 20,
    ));
    if (isCombo) {
      _floaters.add(_Floater(
        x: f.x,
        y: f.y - 60,
        text: '${_combo}x COMBO!',
        color: const Color(0xFFFF6584),
        fontSize: 22,
        isBig: true,
      ));
    }
    if (f.kind == _FruitKind.watermelon || f.kind == _FruitKind.pineapple) {
      _floaters.add(_Floater(
        x: f.x,
        y: f.y - 92,
        text: 'JUICY!',
        color: const Color(0xFFFB7185),
        fontSize: 18,
      ));
    }

    HapticFeedback.lightImpact();
    haptic(HapticFeedbackType.selection);
    reportScore(_score);
    _refreshStats();
  }

  void _explodeBomb(_Fruit f) {
    _gameOver = false; // don't immediately end; lose a heart
    _lives -= 1;
    _combo = 0;
    _heartsPulse = 1.0;
    _floaters.add(_Floater(
      x: f.x,
      y: f.y - 20,
      text: 'BOMB!',
      color: const Color(0xFFFF6584),
      fontSize: 26,
      isBig: true,
    ));
    // 20 black/orange particles.
    for (var i = 0; i < 20; i++) {
      final angle = _rng.nextDouble() * 2 * pi;
      final speed = 100 + _rng.nextDouble() * 140;
      _particles.add(_Particle(
        x: f.x,
        y: f.y,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed - 30,
        color: i.isEven
            ? const Color(0xFF1A1A1A)
            : const Color(0xFFFB923C),
        life: 0.6 + _rng.nextDouble() * 0.4,
      ));
    }
    _flashTime = 0.2;
    _shake(0.25, 8);
    HapticFeedback.heavyImpact();
    haptic(HapticFeedbackType.heavy);
    if (_lives <= 0) {
      _gameOver = true;
      reportScore(_score);
      _refreshStats();
      reportGameOver();
    } else {
      reportScore(_score);
      _refreshStats();
    }
  }

  void _spawnExplosion(double x, double y, Color color) {
    for (var i = 0; i < 12; i++) {
      final angle = _rng.nextDouble() * 2 * pi;
      final speed = 80 + _rng.nextDouble() * 120;
      _particles.add(_Particle(
        x: x,
        y: y,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed - 30,
        color: color,
        life: 0.6 + _rng.nextDouble() * 0.3,
      ));
    }
  }

  void _spawnStars(double x, double y, int count, Color color) {
    for (var i = 0; i < count; i++) {
      final angle = (i / count) * 2 * pi + _rng.nextDouble() * 0.4;
      final speed = 60 + _rng.nextDouble() * 80;
      _stars.add(_Star(
        x: x,
        y: y,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed - 20,
        life: 0.6,
        color: color,
        rot: 0,
        spin: (_rng.nextDouble() - 0.5) * 8,
      ));
    }
  }

  void _loseLife(String reason) {
    if (_gameOver) return;
    _lives -= 1;
    _combo = 0;
    _heartsPulse = 1.0;
    HapticFeedback.mediumImpact();
    haptic(HapticFeedbackType.medium);
    _floaters.add(_Floater(
      x: _screenW / 2,
      y: _gameBottom - 60,
      text: reason,
      color: const Color(0xFFFF6584),
      fontSize: 18,
    ));
    if (_lives <= 0) {
      _gameOver = true;
      HapticFeedback.heavyImpact();
      haptic(HapticFeedbackType.heavy);
      reportScore(_score);
      _refreshStats();
      reportGameOver();
    } else {
      reportScore(_score);
      _refreshStats();
    }
  }

  Color _fruitColor(_FruitKind k) {
    switch (k) {
      case _FruitKind.watermelon:
        return const Color(0xFFE63946);
      case _FruitKind.kiwi:
        return const Color(0xFFA4C639);
      case _FruitKind.pineapple:
        return const Color(0xFFFFC837);
      case _FruitKind.orange:
        return const Color(0xFFFB923C);
      case _FruitKind.dragonFruit:
        return const Color(0xFFE879F9);
      case _FruitKind.bomb:
        return const Color(0xFF1A1A1A);
    }
  }

  double _distToSegment(Offset p, Offset a, Offset b) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final len2 = dx * dx + dy * dy;
    if (len2 == 0) return (p - a).distance;
    final t = (((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / len2)
        .clamp(0.0, 1.0);
    final proj = Offset(a.dx + t * dx, a.dy + t * dy);
    return (p - proj).distance;
  }

  void _dismissTutorial() {
    if (!_showTutorial || _tutorialDismissed) return;
    setState(() {
      _tutorialDismissed = true;
      _showTutorial = false;
    });
  }

  void _shake(double duration, double magnitude) {
    _shakeTime = duration;
    _shakeMag = magnitude;
  }

  void _refreshStats() {
    // Keep this short — it appears in the host subtitle line which is
    // roughly 30–40 chars wide. Best combo is surfaced separately via
    // the host's best-score chip.
    reportStats('Lives $_lives/$_maxLives  •  Combo ×$_combo');
  }

  // ───────────────────────────────────────────────────────────────
  // Build
  // ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        _screenW = c.maxWidth;
        _screenH = c.maxHeight;
        _gameTop = 84;
        _gameBottom = _screenH - 8;
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              // Dark wood cutting board (Fruit Ninja canonical
              // palette). Light backgrounds fought with the saturated
              // cartoon fruit colors and washed them out — dark wood
              // makes every fruit pop.
              colors: [
                Color(0xFF3A2418),
                Color(0xFF4F2F1E),
                Color(0xFF6B4423),
              ],
              stops: [0.0, 0.5, 1.0],
            ),
          ),
          child: Stack(
            children: [
              // Subtle dark vignette to focus attention on the play area. The
              // previous pastel gradient + white wash washed out the
              // fruits; switching to dark wood (Fruit Ninja canonical
              // palette) makes the saturated cartoon fruits pop.
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0.0, -0.4),
                        radius: 1.4,
                        colors: [
                          const Color(0xFF000000).withValues(alpha: 0.0),
                          const Color(0xFF000000).withValues(alpha: 0.30),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Game canvas.
              Positioned.fill(
                child: Transform.translate(
                  offset: _shakeTime > 0
                      ? Offset(
                          (_rng.nextDouble() - 0.5) * _shakeMag,
                          (_rng.nextDouble() - 0.5) * _shakeMag,
                        )
                      : Offset.zero,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: _onPanStart,
                    onPanUpdate: _onPanUpdate,
                    onPanEnd: _onPanEnd,
                    child: CustomPaint(
                      painter: _FruitSlicePainter(
                        fruits: _fruits,
                        halves: _halves,
                        particles: _particles,
                        trail: _trail,
                        floaters: _floaters,
                        stars: _stars,
                        idleTime: _idleTime,
                        gameTop: _gameTop,
                        gameBottom: _gameBottom,
                      ),
                    ),
                  ),
                ),
              ),
              // White flash overlay (bomb hit).
              if (_flashTime > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      color:
                          Colors.white.withValues(alpha: (_flashTime * 5).clamp(0.0, 0.85)),
                    ),
                  ),
                ),
              // The host's GameHudBar provides Pause/Level/Score/Haptics.
              // No in-game duplicate HUD — would compete for vertical
              // space and steal swipes from the play area.
              //
              // Tutorial overlay (auto-dismiss after 3 s or first swipe).
              if (_showTutorial && !_tutorialDismissed)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 48,
                  child: _TutorialOverlayFruit(
                    idleTime: _idleTime,
                    progress: _tutorialElapsed / _tutorialDuration,
                  ),
                ),
              // Pause + Game Over overlays are provided by the host
              // (GamePauseOverlay + _GameEndModal) — removed here so
              // they don't stack.
              // Pause + Game Over overlays are provided by the host.
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// VFX records
// ─────────────────────────────────────────────────────────────────

class _Fruit {
  _Fruit({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.angle,
    required this.spin,
    required this.radius,
    required this.kind,
  }) : sliced = false;
  double x;
  double y;
  double vx;
  double vy;
  double angle;
  double spin;
  double radius;
  _FruitKind kind;
  bool sliced;
}

class _FruitHalf {
  _FruitHalf({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.angle,
    required this.spin,
    required this.life,
    required this.kind,
    required this.side,
  });
  double x;
  double y;
  double vx;
  double vy;
  double angle;
  double spin;
  double life;
  _FruitKind kind;
  int side;
}

class _Particle {
  _Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.color,
    required this.life,
  });
  double x;
  double y;
  double vx;
  double vy;
  Color color;
  double life;
}

class _SlashTrail {
  _SlashTrail({required this.x, required this.y}) : life = 0.18;
  double x;
  double y;
  double life;
}

class _Floater {
  _Floater({
    required this.x,
    required this.y,
    required this.text,
    required this.color,
    this.fontSize = 20,
    this.isBig = false,
  }) : life = 0.9;
  double x;
  double y;
  String text;
  Color color;
  double fontSize;
  bool isBig;
  double life;
}

class _Star {
  _Star({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.life,
    required this.color,
    required this.rot,
    required this.spin,
  });
  double x;
  double y;
  double vx;
  double vy;
  double life;
  Color color;
  double rot;
  double spin;
}

// ─────────────────────────────────────────────────────────────────
// Tutorial overlay (capsule + animated hand performing diagonal swipe)
// ─────────────────────────────────────────────────────────────────

class _TutorialOverlayFruit extends StatefulWidget {
  const _TutorialOverlayFruit({
    required this.idleTime,
    required this.progress,
  });
  final double idleTime;
  final double progress;

  @override
  State<_TutorialOverlayFruit> createState() => _TutorialOverlayFruitState();
}

class _TutorialOverlayFruitState extends State<_TutorialOverlayFruit>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 280))
        ..forward();

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final opacity = 1 - widget.progress * 0.3;
    return AnimatedBuilder(
      animation: _intro,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(_intro.value);
        return Transform.translate(
          offset: Offset(0, (1 - t) * 30),
          child: Opacity(opacity: t * opacity, child: child),
        );
      },
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 18,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Hand performing a diagonal swipe motion.
              Transform.rotate(
                angle: 0.4,
                child: CustomPaint(
                  size: const Size(34, 34),
                  painter: _FruitHandPainter(idleTime: widget.idleTime),
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Swipe across fruits to slice!',
                style: TextStyle(
                  color: Color(0xFF1E3A8A),
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FruitHandPainter extends CustomPainter {
  _FruitHandPainter({required this.idleTime});
  final double idleTime;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w * 0.5;
    final cy = h * 0.45;
    // Diagonal swipe motion — both axes oscillate (drawing a diagonal
    // stroke).
    final swipeX = sin(idleTime * 4) * 6;
    final swipeY = cos(idleTime * 4) * 6;

    canvas.save();
    canvas.translate(cx + swipeX, cy + swipeY);

    // Drop shadow.
    final palmRect = Rect.fromCenter(center: Offset.zero, width: 22, height: 22);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        palmRect.shift(const Offset(0, 2)),
        const Radius.circular(8),
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.20)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // Palm (yellow with radial gradient).
    canvas.drawRRect(
      RRect.fromRectAndRadius(palmRect, const Radius.circular(8)),
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFFFEF08A), Color(0xFFFCD34D)],
        ).createShader(palmRect),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(palmRect, const Radius.circular(8)),
      Paint()
        ..color = const Color(0xFF1E293B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    // Index finger pointing in diagonal swipe direction.
    final fingerPath = Path()
      ..moveTo(-2, 8)
      ..lineTo(-2, -4)
      ..lineTo(8, -4)
      ..arcToPoint(
        const Offset(8, 2),
        radius: const Radius.circular(4),
        clockwise: false,
      )
      ..lineTo(-2, 8)
      ..close();
    canvas.drawPath(
      fingerPath,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFEF08A), Color(0xFFF59E0B)],
        ).createShader(fingerPath.getBounds()),
    );
    canvas.drawPath(
      fingerPath,
      Paint()
        ..color = const Color(0xFF1E293B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    canvas.restore();

    // Diagonal swipe trail beneath the hand (visual cue).
    final trailPath = Path()
      ..moveTo(w * 0.10, h * 0.85)
      ..lineTo(w * 0.90, h * 0.15);
    canvas.drawPath(
      trailPath,
      Paint()
        ..color = const Color(0xFF22D3EE).withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      trailPath,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_FruitHandPainter old) =>
      old.idleTime != idleTime;
}

// ─────────────────────────────────────────────────────────────────
// Painter
// ─────────────────────────────────────────────────────────────────

class _FruitSlicePainter extends CustomPainter {
  _FruitSlicePainter({
    required this.fruits,
    required this.halves,
    required this.particles,
    required this.trail,
    required this.floaters,
    required this.stars,
    required this.idleTime,
    required this.gameTop,
    required this.gameBottom,
  });

  final List<_Fruit> fruits;
  final List<_FruitHalf> halves;
  final List<_Particle> particles;
  final List<_SlashTrail> trail;
  final List<_Floater> floaters;
  final List<_Star> stars;
  final double idleTime;
  final double gameTop;
  final double gameBottom;

  @override
  void paint(Canvas canvas, Size size) {
    _drawTrail(canvas);
    _drawStars(canvas);
    _drawHalves(canvas);
    _drawFruits(canvas);
    _drawParticles(canvas);
    _drawFloaters(canvas);
  }

  // ─────────────────────────────────────────────────────────────
  // Trail — outer white glow + cyan mid + gradient core + yellow
  // edge + white spine.
  // ─────────────────────────────────────────────────────────────
  void _drawTrail(Canvas canvas) {
    if (trail.length < 2) return;
    final path = Path()..moveTo(trail.first.x, trail.first.y);
    for (var i = 1; i < trail.length; i++) {
      path.lineTo(trail[i].x, trail[i].y);
    }
    final rect = path.getBounds();
    // 1. Outer white glow.
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 22
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
    // 2. Mid cyan glow.
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF67E8F9).withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    // 3. Core cyan-white gradient.
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            const Color(0xFF22D3EE),
            const Color(0xFFFFFFFF),
            const Color(0xFF22D3EE),
          ],
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );
    // 4. Yellow edge shimmer.
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFFDE047).withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );
    // 5. White spine.
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round
        ..blendMode = BlendMode.screen,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Halves — fruit cross-sections flying apart.
  // ─────────────────────────────────────────────────────────────
  void _drawHalves(Canvas canvas) {
    for (final h in halves) {
      final alpha = (h.life / 1.2).clamp(0.0, 1.0);
      canvas.save();
      canvas.translate(h.x, h.y);
      canvas.rotate(h.angle);
      _drawHalf(canvas, h, alpha);
      canvas.restore();
    }
  }

  void _drawHalf(Canvas canvas, _FruitHalf h, double alpha) {
    final size = h.kind == _FruitKind.watermelon
        ? 24.0
        : h.kind == _FruitKind.pineapple
            ? 22.0
            : 20.0;
    canvas.save();
    if (h.side < 0) {
      // Left half — clip to left side of a circle.
      canvas.clipRect(Rect.fromLTWH(-size * 2, -size, size * 2, size * 2));
    } else {
      // Right half — clip to right side of a circle.
      canvas.clipRect(Rect.fromLTWH(0, -size, size * 2, size * 2));
    }
    // Body.
    _drawFruitBody(canvas, Offset.zero, size, h.kind, alpha);
    canvas.restore();
    // Outline (drawn outside clip).
    final outline = Paint()
      ..color = const Color(0xFF1F2937).withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    canvas.drawArc(
      Rect.fromCenter(center: Offset.zero, width: size * 2, height: size * 2),
      h.side < 0 ? pi / 2 : -pi / 2,
      pi,
      false,
      outline,
    );
  }

  void _drawFruitBody(Canvas canvas, Offset c, double r, _FruitKind kind, double alpha) {
    final basePaint = Paint()
      ..color = Colors.white.withValues(alpha: alpha);
    canvas.drawCircle(c, r, basePaint);
    switch (kind) {
      case _FruitKind.watermelon:
        _drawWatermelonCrossSection(canvas, c, r, alpha);
        break;
      case _FruitKind.kiwi:
        _drawKiwiCrossSection(canvas, c, r, alpha);
        break;
      case _FruitKind.pineapple:
        _drawPineappleCrossSection(canvas, c, r, alpha);
        break;
      case _FruitKind.orange:
        _drawOrangeCrossSection(canvas, c, r, alpha);
        break;
      case _FruitKind.dragonFruit:
        _drawDragonFruitCrossSection(canvas, c, r, alpha);
        break;
      case _FruitKind.bomb:
        canvas.drawCircle(c, r, Paint()..color = const Color(0xFF1A1A1A).withValues(alpha: alpha));
        break;
    }
  }

  void _drawWatermelonCrossSection(Canvas canvas, Offset c, double r, double alpha) {
    // Rind ring.
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF166534).withValues(alpha: alpha));
    // Pink flesh.
    canvas.drawCircle(c, r * 0.85, Paint()..color = const Color(0xFFE63946).withValues(alpha: alpha));
    // Inner highlight.
    canvas.drawCircle(c, r * 0.75, Paint()..color = const Color(0xFFFFADAD).withValues(alpha: alpha * 0.7));
    // Black seeds.
    for (var i = 0; i < 3; i++) {
      final a = (i / 3) * 2 * pi + pi / 6;
      canvas.drawCircle(
        Offset.fromDirection(a, r * 0.4) + c,
        1.5,
        Paint()..color = const Color(0xFF1A1A1A).withValues(alpha: alpha),
      );
    }
  }

  void _drawKiwiCrossSection(Canvas canvas, Offset c, double r, double alpha) {
    // Brown fuzzy rind.
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF8B6F47).withValues(alpha: alpha));
    // Green flesh.
    canvas.drawCircle(c, r * 0.85, Paint()..color = const Color(0xFFA4C639).withValues(alpha: alpha));
    // White core.
    canvas.drawCircle(c, r * 0.2, Paint()..color = Colors.white.withValues(alpha: alpha));
    // Radiating seeds.
    for (var i = 0; i < 8; i++) {
      final a = (i / 8) * 2 * pi;
      canvas.drawCircle(
        Offset.fromDirection(a, r * 0.55) + c,
        1.0,
        Paint()..color = const Color(0xFF1A1A1A).withValues(alpha: alpha),
      );
    }
  }

  void _drawPineappleCrossSection(Canvas canvas, Offset c, double r, double alpha) {
    // Outer yellow rind.
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFFEAB308).withValues(alpha: alpha));
    // Inner yellow flesh.
    canvas.drawCircle(c, r * 0.85, Paint()..color = const Color(0xFFFACC15).withValues(alpha: alpha));
    // Center core.
    canvas.drawCircle(c, r * 0.25, Paint()..color = Colors.white.withValues(alpha: alpha));
    // Dotted pattern (skin pores) — small dots around the rind ring.
    for (var i = 0; i < 12; i++) {
      final a = (i / 12) * 2 * pi;
      canvas.drawCircle(
        Offset.fromDirection(a, r * 0.75) + c,
        0.8,
        Paint()..color = const Color(0xFF854D0E).withValues(alpha: alpha * 0.7),
      );
    }
  }

  void _drawOrangeCrossSection(Canvas canvas, Offset c, double r, double alpha) {
    // Orange rind.
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFFFB923C).withValues(alpha: alpha));
    // Inner orange flesh.
    canvas.drawCircle(c, r * 0.88, Paint()..color = const Color(0xFFFCA65A).withValues(alpha: alpha));
    // White pith ring.
    canvas.drawCircle(
      c,
      r * 0.78,
      Paint()
        ..color = Colors.white.withValues(alpha: alpha * 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    // Segments (lines radiating from center).
    for (var i = 0; i < 8; i++) {
      final a = (i / 8) * 2 * pi;
      final end = Offset.fromDirection(a, r * 0.7) + c;
      canvas.drawLine(
        c,
        end,
        Paint()
          ..color = Colors.white.withValues(alpha: alpha * 0.7)
          ..strokeWidth = 1.4,
      );
    }
  }

  void _drawDragonFruitCrossSection(Canvas canvas, Offset c, double r, double alpha) {
    // Magenta rind ring.
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFFE879F9).withValues(alpha: alpha));
    // White flesh.
    canvas.drawCircle(c, r * 0.85, Paint()..color = Colors.white.withValues(alpha: alpha));
    // Black seeds.
    final seedRng = Random(42);
    for (var i = 0; i < 12; i++) {
      final a = seedRng.nextDouble() * 2 * pi;
      final d = seedRng.nextDouble() * r * 0.7;
      canvas.drawCircle(
        Offset.fromDirection(a, d) + c,
        0.9,
        Paint()..color = const Color(0xFF1A1A1A).withValues(alpha: alpha),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Fruits — vector designs with thick outlines + glossy highlights.
  // ─────────────────────────────────────────────────────────────
  void _drawFruits(Canvas canvas) {
    for (final f in fruits) {
      if (f.sliced) continue;
      canvas.save();
      canvas.translate(f.x, f.y);
      canvas.rotate(f.angle);
      _drawFruit(canvas, f);
      canvas.restore();
    }
  }

  void _drawFruit(Canvas canvas, _Fruit f) {
    switch (f.kind) {
      case _FruitKind.watermelon:
        _drawWatermelon(canvas, f.radius);
        break;
      case _FruitKind.kiwi:
        _drawKiwi(canvas, f.radius);
        break;
      case _FruitKind.pineapple:
        _drawPineapple(canvas, f.radius);
        break;
      case _FruitKind.orange:
        _drawOrange(canvas, f.radius);
        break;
      case _FruitKind.dragonFruit:
        _drawDragonFruit(canvas, f.radius);
        break;
      case _FruitKind.bomb:
        _drawBomb(canvas, f.radius);
        break;
    }
  }

  void _drawWatermelon(Canvas canvas, double r) {
    // Drop shadow.
    canvas.drawCircle(
      Offset(1, 2),
      r,
      Paint()..color = Colors.black.withValues(alpha: 0.30),
    );
    // Body (striped sphere illusion).
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: const [Color(0xFF4ADE80), Color(0xFF16A34A)],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: r)),
    );
    // Stripes.
    for (var i = 0; i < 6; i++) {
      final a = (i / 6) * 2 * pi;
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: r * 0.95),
        a,
        pi / 12,
        false,
        Paint()
          ..color = const Color(0xFF166534).withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    // Glossy highlight.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(-r * 0.30, -r * 0.30),
        width: r * 0.55,
        height: r * 0.28,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.55),
    );
    // Outline.
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..color = const Color(0xFF1F2937)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  void _drawKiwi(Canvas canvas, double r) {
    canvas.drawCircle(
      Offset(1, 2),
      r,
      Paint()..color = Colors.black.withValues(alpha: 0.30),
    );
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: const [Color(0xFFB8A079), Color(0xFF6F4E37)],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: r)),
    );
    // Highlight.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(-r * 0.30, -r * 0.30),
        width: r * 0.50,
        height: r * 0.26,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.45),
    );
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..color = const Color(0xFF1F2937)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  void _drawPineapple(Canvas canvas, double r) {
    // Body (oval).
    final bodyRect = Rect.fromCenter(center: Offset.zero, width: r * 1.4, height: r * 1.7);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, const Radius.circular(8)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFACC15), Color(0xFFCA8A04)],
        ).createShader(bodyRect),
    );
    // Dotted skin pores.
    for (var i = 0; i < 8; i++) {
      for (var j = 0; j < 6; j++) {
        final px = -r * 0.7 + (i / 7) * r * 1.4;
        final py = -r * 0.85 + (j / 5) * r * 1.7;
        if (((i + j) % 2) == 0) {
          canvas.drawCircle(
            Offset(px, py),
            1.2,
            Paint()..color = const Color(0xFF854D0E).withValues(alpha: 0.6),
          );
        }
      }
    }
    // Crown (green leaves at top).
    final crownPath = Path()
      ..moveTo(-r * 0.4, -r * 0.85)
      ..lineTo(-r * 0.5, -r * 1.5)
      ..lineTo(0, -r * 1.2)
      ..lineTo(r * 0.4, -r * 1.55)
      ..lineTo(r * 0.5, -r * 0.85);
    canvas.drawPath(
      crownPath,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF22C55E), Color(0xFF15803D)],
        ).createShader(crownPath.getBounds()),
    );
    canvas.drawPath(
      crownPath,
      Paint()
        ..color = const Color(0xFF1F2937)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    // Highlight.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(-r * 0.30, -r * 0.30),
        width: r * 0.45,
        height: r * 0.25,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.55),
    );
    // Outline.
    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, const Radius.circular(8)),
      Paint()
        ..color = const Color(0xFF1F2937)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  void _drawOrange(Canvas canvas, double r) {
    canvas.drawCircle(
      Offset(1, 2),
      r,
      Paint()..color = Colors.black.withValues(alpha: 0.30),
    );
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: const [Color(0xFFFB923C), Color(0xFFC2410C)],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: r)),
    );
    // Subtle texture dimples.
    for (var i = 0; i < 8; i++) {
      final a = (i / 8) * 2 * pi + pi / 8;
      final d = r * 0.55;
      canvas.drawCircle(
        Offset.fromDirection(a, d),
        1.5,
        Paint()..color = const Color(0xFF9A3412).withValues(alpha: 0.4),
      );
    }
    // Highlight.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(-r * 0.30, -r * 0.30),
        width: r * 0.55,
        height: r * 0.28,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.55),
    );
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..color = const Color(0xFF1F2937)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  void _drawDragonFruit(Canvas canvas, double r) {
    canvas.drawCircle(
      Offset(1, 2),
      r,
      Paint()..color = Colors.black.withValues(alpha: 0.30),
    );
    // Magenta body.
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: const [Color(0xFFF0ABFC), Color(0xFFC026D3)],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: r)),
    );
    // Green-tipped scales (small ovals around the body).
    for (var i = 0; i < 6; i++) {
      final a = (i / 6) * 2 * pi;
      final tip = Offset.fromDirection(a, r * 0.95);
      final base = Offset.fromDirection(a, r * 0.55);
      canvas.drawLine(
        base,
        tip,
        Paint()
          ..color = const Color(0xFF22C55E)
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(
        tip,
        3.5,
        Paint()..color = const Color(0xFF16A34A),
      );
    }
    // Highlight.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(-r * 0.30, -r * 0.30),
        width: r * 0.55,
        height: r * 0.28,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.55),
    );
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..color = const Color(0xFF1F2937)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  void _drawBomb(Canvas canvas, double r) {
    canvas.drawCircle(
      Offset(1, 2),
      r,
      Paint()..color = Colors.black.withValues(alpha: 0.40),
    );
    // Sphere body.
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: const [Color(0xFF4B5563), Color(0xFF0F172A)],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: r)),
    );
    // Highlight.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(-r * 0.30, -r * 0.30),
        width: r * 0.55,
        height: r * 0.28,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.30),
    );
    // Outline.
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..color = const Color(0xFF1F2937)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    // Fuse + spark.
    canvas.drawLine(
      Offset(r * 0.4, -r * 0.6),
      Offset(r * 0.6, -r * 1.1),
      Paint()
        ..color = const Color(0xFFB45309)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    // Flickering spark.
    final flicker = sin(idleTime * 12) > 0.4 ? 1.0 : 0.4;
    canvas.drawCircle(
      Offset(r * 0.6, -r * 1.1),
      4.5 * flicker + 1.0,
      Paint()..color = const Color(0xFFFFC837).withValues(alpha: flicker),
    );
    canvas.drawCircle(
      Offset(r * 0.6, -r * 1.1),
      8 * flicker,
      Paint()..color = const Color(0xFFFFC837).withValues(alpha: 0.4 * flicker),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Stars (combo sparkle particles).
  // ─────────────────────────────────────────────────────────────
  void _drawStars(Canvas canvas) {
    for (final s in stars) {
      final alpha = (s.life / 0.6).clamp(0.0, 1.0);
      canvas.save();
      canvas.translate(s.x, s.y);
      canvas.rotate(s.rot);
      _drawStarShape(canvas, 6.0, s.color.withValues(alpha: alpha));
      canvas.restore();
    }
  }

  void _drawStarShape(Canvas canvas, double r, Color color) {
    final path = Path();
    const points = 4;
    for (var i = 0; i < points * 2; i++) {
      final angle = (i * pi) / points;
      final radius = i.isEven ? r : r * 0.35;
      final px = cos(angle) * radius;
      final py = sin(angle) * radius;
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Particles (juice drops).
  // ─────────────────────────────────────────────────────────────
  void _drawParticles(Canvas canvas) {
    for (final p in particles) {
      final alpha = (p.life / 0.8).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(p.x, p.y),
        4,
        Paint()..color = p.color.withValues(alpha: alpha),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────
  // 3-D floaters (layered TextPainter passes).
  // ─────────────────────────────────────────────────────────────
  void _drawFloaters(Canvas canvas) {
    for (final f in floaters) {
      final alpha = (f.life / 0.9).clamp(0.0, 1.0);
      _draw3DText(
        canvas,
        Offset(f.x, f.y - (0.9 - f.life) * 24),
        f.text,
        f.color,
        f.fontSize,
        alpha,
      );
    }
  }

  void _draw3DText(
    Canvas canvas,
    Offset center,
    String text,
    Color color,
    double fontSize,
    double alpha,
  ) {
    final style = TextStyle(
      color: Colors.white,
      fontSize: fontSize,
      fontWeight: FontWeight.w900,
      letterSpacing: 1.4,
    );
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final origin = Offset(center.dx - tp.width / 2, center.dy - tp.height / 2);
    final textRect = Rect.fromLTWH(origin.dx, origin.dy, tp.width, tp.height);

    // 1. Outer yellow glow.
    final glowPaint = Paint()
      ..color = const Color(0xFFFDE047).withValues(alpha: alpha * 0.65)
      ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 12);
    canvas.drawRect(textRect.inflate(4), glowPaint);

    // 2. Yellow stroke outline.
    final outlineTp = TextPainter(
      text: TextSpan(
        text: text,
        style: style.copyWith(
          foreground: Paint()
            ..color = const Color(0xFFFACC15).withValues(alpha: alpha)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4
            ..strokeJoin = StrokeJoin.round,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    outlineTp.paint(canvas, origin);

    // 3. Drop shadow.
    final shadowTp = TextPainter(
      text: TextSpan(
        text: text,
        style: style.copyWith(
          color: const Color(0xFF000000).withValues(alpha: alpha * 0.45),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    shadowTp.paint(canvas, origin.translate(0, 4));

    // 4. Base white text.
    tp.paint(canvas, origin);
  }

  @override
  bool shouldRepaint(_FruitSlicePainter old) =>
      old.fruits != fruits ||
      old.halves != halves ||
      old.particles != particles ||
      old.trail != trail ||
      old.floaters != floaters ||
      old.stars != stars ||
      old.idleTime != idleTime;
}
