import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/random_utils.dart';
import '../game_widgets.dart';
import '../mini_game.dart';

/// Fruit Merge — Suika-style drop & merge with cartoon-fruit visuals.
///
/// Tap anywhere inside the playfield to drop the held fruit from the
/// horizontal dropper at the top. Same-tier fruits touching each
/// other inside the glass vessel merge into the next tier up the
/// 11-step ladder (grape → cherry → orange → watermelon slice →
/// green apple → strawberry → apple → lemon → pumpkin → plum →
/// watermelon). Visual chrome and palette match the reference
/// screenshot: tan-striped background, settings gear top-left,
/// score cloud top-center, coin pill top-right, mallet boosters
/// + next-fruit preview, white glass vessel with dotted drop-line,
/// cartoon fruits with kawaii faces, and a "PLAY FOR FUN" green
/// banner at the bottom.
class FruitMergeGame extends MiniGame {
  const FruitMergeGame({
    super.key,
    required super.callbacks,
    this.dailyChallenge = false,
  });

  /// When true, the next-fruit queue is seeded by today's UTC date so
  /// every player faces the same fruit sequence on a given day.
  final bool dailyChallenge;

  @override
  State<FruitMergeGame> createState() => _State();
}

// ─────────────────────────────────────────────────────────────────
// Fruit kinds & palette
// ─────────────────────────────────────────────────────────────────

/// The merge ladder — 11 tiers, each with its own cartoon look.
/// Order matches the reference screenshot's bottom strip and the
/// merge progression (tier N + tier N → tier N+1).
enum _FruitKind {
  grape,        // 0 — purple cluster
  cherry,       // 1 — red pair with stems
  orange,       // 2 — orange slice
  watermelonSlice, // 3 — half-watermelon (red flesh, green rind, striped)
  greenApple,   // 4 — green apple with leaf
  strawberry,   // 5 — strawberry with seeds + leaves
  apple,        // 6 — red apple with leaf
  lemon,        // 7 — yellow lemon
  pumpkin,      // 8 — orange pumpkin with ridges
  plum,         // 9 — purple plum
  watermelon,   // 10 — full watermelon (final mega fruit)
}

const int _maxTier = 10;

class _FruitPalette {
  const _FruitPalette({
    required this.body,
    required this.highlight,
    required this.shadow,
    required this.outline,
    required this.accent,
    required this.points,
    required this.drawFace,
  });
  final Color body;
  final Color highlight;
  final Color shadow;
  final Color outline;
  final Color accent;
  final int points;
  /// Whether the fruit gets a kawaii face on it. The reference shows
  /// faces on all fruits except the watermelon slice (which has its
  /// own dotted pattern) — keep that exception.
  final bool drawFace;
}

const List<_FruitPalette> _kFruits = [
  // 0 grape — purple cluster with highlight.
  _FruitPalette(
    body: Color(0xFF8E3A9F),
    highlight: Color(0xFFC78BD7),
    shadow: Color(0xFF4A1860),
    outline: Color(0xFF220830),
    accent: Color(0xFFEAD3F1),
    points: 10,
    drawFace: true,
  ),
  // 1 cherry — red pair.
  _FruitPalette(
    body: Color(0xFFE63946),
    highlight: Color(0xFFFF8FA3),
    shadow: Color(0xFF8B0E1F),
    outline: Color(0xFF4A0710),
    accent: Color(0xFFFFE0E5),
    points: 20,
    drawFace: true,
  ),
  // 2 orange — citrus slice.
  _FruitPalette(
    body: Color(0xFFFF9234),
    highlight: Color(0xFFFFD9B5),
    shadow: Color(0xFFB85F1F),
    outline: Color(0xFF6B3005),
    accent: Color(0xFFFFEDD8),
    points: 40,
    drawFace: true,
  ),
  // 3 watermelon slice — no face, has its own dotted pattern.
  _FruitPalette(
    body: Color(0xFFEF5350),
    highlight: Color(0xFFFF8FA3),
    shadow: Color(0xFF8B1F1F),
    outline: Color(0xFF2E5527),
    accent: Color(0xFFFFE0E0),
    points: 80,
    drawFace: false,
  ),
  // 4 green apple — kawaii face, leaf on top.
  _FruitPalette(
    body: Color(0xFF8BC34A),
    highlight: Color(0xFFD4EB9F),
    shadow: Color(0xFF557A1F),
    outline: Color(0xFF26400C),
    accent: Color(0xFFE9F7CF),
    points: 160,
    drawFace: true,
  ),
  // 5 strawberry — red with seeds, leafy crown.
  _FruitPalette(
    body: Color(0xFFFF4757),
    highlight: Color(0xFFFFB1BA),
    shadow: Color(0xFFB8283A),
    outline: Color(0xFF6E0E1F),
    accent: Color(0xFFFFE0E5),
    points: 320,
    drawFace: true,
  ),
  // 6 apple — red apple with leaf.
  _FruitPalette(
    body: Color(0xFFD64545),
    highlight: Color(0xFFFF8FA3),
    shadow: Color(0xFF7A1F1F),
    outline: Color(0xFF3A0A0A),
    accent: Color(0xFFFFE0E5),
    points: 640,
    drawFace: true,
  ),
  // 7 lemon — bright yellow.
  _FruitPalette(
    body: Color(0xFFFFD23F),
    highlight: Color(0xFFFFF6BD),
    shadow: Color(0xFFB97A00),
    outline: Color(0xFF4A2E00),
    accent: Color(0xFFFFF8DD),
    points: 1280,
    drawFace: true,
  ),
  // 8 pumpkin — orange with ridges.
  _FruitPalette(
    body: Color(0xFFFF6F1A),
    highlight: Color(0xFFFFC78A),
    shadow: Color(0xFFB85105),
    outline: Color(0xFF5C2400),
    accent: Color(0xFFFFE5C2),
    points: 2560,
    drawFace: true,
  ),
  // 9 plum — dark purple, glossy.
  _FruitPalette(
    body: Color(0xFF6B21A8),
    highlight: Color(0xFFB388FF),
    shadow: Color(0xFF3A0B5A),
    outline: Color(0xFF1F0528),
    accent: Color(0xFFE9D5FF),
    points: 5000,
    drawFace: true,
  ),
  // 10 watermelon — full mega fruit.
  _FruitPalette(
    body: Color(0xFF22C55E),
    highlight: Color(0xFF86EFAC),
    shadow: Color(0xFF14532D),
    outline: Color(0xFF052E16),
    accent: Color(0xFFD1FAE5),
    points: 10000,
    drawFace: true,
  ),
];

/// Radius (px) per tier — tuned for an 11-tier ladder. The smallest
/// grape fits comfortably in the vessel mouth; the largest watermelon
/// spans ~80 % of the vessel width at typical phone widths.
double _radiusForTier(int tier) {
  return 18.0 + tier * 5.0;
}

// ─────────────────────────────────────────────────────────────────
// Game state
// ─────────────────────────────────────────────────────────────────

class _State extends MiniGameState<FruitMergeGame>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  // Daily challenge games share a deterministic seed so every player
  // gets the same fruit sequence on the same UTC date.
  late final Random _rng = widget.dailyChallenge
      ? Random(dailySeedFor('fruit-merge'))
      : Random();

  String _statsLine() {
    final tier = _stage.clamp(1, 99);
    return 'Score $_score  •  Tier $tier';
  }

  // Vessel geometry in px — recomputed in [_recalc] once we know
  // the canvas size.
  double _vesselLeft = 0;
  double _vesselRight = 0;
  double _vesselTop = 0;
  double _vesselBottom = 0;
  double _floorY = 0;

  // Dropper state.
  double _clawX = 0;
  int _holdTier = 0;
  int _nextTier = 0;
  double _clawDir = 1.0;

  // Physics bodies in the vessel.
  final List<_FruitBody> _bodies = [];
  final List<_FruitBody> _pending = [];

  // Visual effects.
  final List<_Spark> _sparks = [];
  final List<_Ring> _rings = [];
  final List<_Floater> _floaters = [];

  // Overfill timer.
  double _overfillTimer = 0;
  bool _overfillActive = false;

  // Lives.
  int _hearts = 3;
  double _heartsPulse = 0;

  // Score + Stage.
  int _score = 0;
  int _stage = 1;
  int _mergesThisStage = 0;

  // Pause / tutorial / game-over flags. `_showTutorial` is derived from
  // `_tutorialDismissed` so it doesn't need a separate field.
  bool _paused = false;
  bool _tutorialDismissed = false;
  double _idleTime = 0;
  bool _isGameOver = false;

  DateTime _last = DateTime.now();

  // Physics tunables — slightly heavier than v1 for a more
  // satisfying settle.
  static const double _g = 1100;
  static const double _restitution = 0.32;
  static const double _friction = 0.78;
  static const double _sleepThreshold = 4.0;
  static const double _wallStopper = 0.001;

  @override
  void initState() {
    super.initState();
    _holdTier = _rng.nextInt(5); // first 5 tiers from claw
    _nextTier = _rng.nextInt(5);
    _ticker = createTicker(_tick)..start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      reportScore(_score);
      reportStats(_statsLine());
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _recalc(Size size) {
    final w = size.width;
    final h = size.height;
    final vesselPad = w * 0.06;
    _vesselLeft = vesselPad;
    _vesselRight = w - vesselPad;
    _vesselTop = h * 0.30; // lower than candy-drop so the top
    _vesselBottom = h * 0.85;
    _floorY = _vesselBottom - 8;
    if (_clawX == 0) {
      _clawX = w / 2;
    }
  }

  // ───────────────────────────────────────────────────────────────
  // Tick loop
  // ───────────────────────────────────────────────────────────────

  void _tick(Duration _) {
    if (!mounted) return;
    if (_isGameOver) {
      if (_ticker.isActive) _ticker.stop();
      return;
    }
    final now = DateTime.now();
    var dt = now.difference(_last).inMicroseconds / 1e6;
    _last = now;
    if (dt <= 0) return;
    if (dt > 0.05) dt = 0.05;
    if (_paused) {
      return;
    }
    _idleTime += dt;

    setState(() {
      // Claw sway.
      final w = (_vesselRight - _vesselLeft).abs();
      final ax = _vesselLeft + w * 0.12;
      final bx = _vesselRight - w * 0.12;
      const speed = 130.0;
      _clawX += _clawDir * speed * dt;
      if (_clawX > bx) {
        _clawX = bx;
        _clawDir = -1;
      } else if (_clawX < ax) {
        _clawX = ax;
        _clawDir = 1;
      }

      // Pull pending drops into the body list.
      if (_pending.isNotEmpty) {
        _bodies.addAll(_pending);
        _pending.clear();
      }

      // Physics + merges.
      _integrate(dt);
      _collide();
      _mergeStep();
      _overfillStep(dt);

      // VFX lifecycle.
      for (final s in _sparks) {
        s.life -= dt * 1.4;
      }
      _sparks.removeWhere((s) => s.life <= 0);

      for (final r in _rings) {
        r.life -= dt * 1.6;
        r.radius += 90 * dt;
      }
      _rings.removeWhere((r) => r.life <= 0);

      for (final f in _floaters) {
        f.y -= 36 * dt;
        f.life -= dt;
      }
      _floaters.removeWhere((f) => f.life <= 0);

      if (_heartsPulse > 0) _heartsPulse = max(0, _heartsPulse - dt * 2.0);

      // Stage progression (every 8 merges).
      if (_mergesThisStage >= 8) {
        _mergesThisStage = 0;
        _stage += 1;
        _floaters.add(_Floater(
          x: 0.5,
          y: 0.20,
          text: 'STAGE $_stage!',
          color: const Color(0xFFFF5BAA),
          size: 32,
        ));
        haptic(HapticFeedbackType.heavy);
      }
    });
  }

  // ───────────────────────────────────────────────────────────────
  // Physics
  // ───────────────────────────────────────────────────────────────

  void _integrate(double dt) {
    for (final b in _bodies) {
      if (b.resting) continue;
      b.vy += _g * dt;
      b.x += b.vx * dt;
      b.y += b.vy * dt;
      b.rotVel *= pow(0.001, dt);
      b.rot += b.rotVel * dt;
    }
  }

  void _collide() {
    final n = _bodies.length;
    for (final b in _bodies) {
      final r = b.r;
      if (b.y + r > _floorY) {
        b.y = _floorY - r;
        if (b.vy > 0) b.vy = -b.vy * _restitution;
        b.vx *= _friction;
        if (b.vy.abs() < _sleepThreshold && b.vx.abs() < _sleepThreshold) {
          b.vy = 0;
          b.vx = 0;
          b.resting = true;
        }
      }
      if (b.x - r < _vesselLeft) {
        b.x = _vesselLeft + r + _wallStopper;
        if (b.vx < 0) b.vx = -b.vx * _restitution;
        b.vy *= 0.9;
      }
      if (b.x + r > _vesselRight) {
        b.x = _vesselRight - r - _wallStopper;
        if (b.vx > 0) b.vx = -b.vx * _restitution;
        b.vy *= 0.9;
      }
      if (b.y - r < _vesselTop) {
        b.y = _vesselTop + r;
        if (b.vy < 0) b.vy = -b.vy * 0.2;
      }
    }
    for (var i = 0; i < n; i++) {
      final a = _bodies[i];
      for (var j = i + 1; j < n; j++) {
        final b = _bodies[j];
        final dx = b.x - a.x;
        final dy = b.y - a.y;
        final rsum = a.r + b.r;
        final dist2 = dx * dx + dy * dy;
        if (dist2 > rsum * rsum) continue;
        final dist = sqrt(dist2);
        if (dist < 0.0001) continue;
        final nx = dx / dist;
        final ny = dy / dist;
        final overlap = rsum - dist;
        a.x -= nx * overlap * 0.5;
        a.y -= ny * overlap * 0.5;
        b.x += nx * overlap * 0.5;
        b.y += ny * overlap * 0.5;
        final rvx = b.vx - a.vx;
        final rvy = b.vy - a.vy;
        final velAlong = rvx * nx + rvy * ny;
        if (velAlong > 0) continue;
        final e = _restitution * 0.75;
        final jImp = -(1 + e) * velAlong / 2;
        final ix = jImp * nx;
        final iy = jImp * ny;
        a.vx -= ix;
        a.vy -= iy;
        b.vx += ix;
        b.vy += iy;
        if (a.vy.abs() < _sleepThreshold && a.vx.abs() < _sleepThreshold) {
          a.resting = true;
        }
        if (b.vy.abs() < _sleepThreshold && b.vx.abs() < _sleepThreshold) {
          b.resting = true;
        }
      }
    }
  }

  // ───────────────────────────────────────────────────────────────
  // Merging
  // ───────────────────────────────────────────────────────────────

  void _mergeStep() {
    final n = _bodies.length;
    final consumed = <int>{};
    for (var i = 0; i < n; i++) {
      if (consumed.contains(i)) continue;
      final a = _bodies[i];
      for (var j = i + 1; j < n; j++) {
        if (consumed.contains(j)) continue;
        final b = _bodies[j];
        if (a.tier != b.tier) continue;
        final dx = b.x - a.x;
        final dy = b.y - a.y;
        final dist2 = dx * dx + dy * dy;
        final rsum = a.r + b.r;
        final mergeR = rsum * 1.02;
        if (dist2 > mergeR * mergeR) continue;
        consumed.add(i);
        consumed.add(j);
        final avgX = (a.x + b.x) * 0.5;
        final avgY = (a.y + b.y) * 0.5;
        final newTier = a.tier + 1;
        if (newTier > _maxTier) {
          _score += _kFruits[_maxTier].points * 2;
          reportScore(_score);
          _spawnMergeVfx(avgX, avgY, _kFruits[_maxTier], 'MEGA!');
          _floaters.add(_Floater(
            x: avgX,
            y: avgY,
            text: 'MEGA! +${_kFruits[_maxTier].points * 2}',
            color: const Color(0xFFFF5BAA),
            size: 30,
          ));
        } else {
          _bodies.add(_FruitBody(
            x: avgX,
            y: avgY,
            vx: (a.vx + b.vx) * 0.25,
            vy: -260,
            r: _radiusForTier(newTier),
            tier: newTier,
          ));
          final combo = _mergesThisStage + 1;
          final bonus = combo >= 3 ? combo * 20 : 0;
          final pts = _kFruits[a.tier].points * 2 + bonus;
          _score += pts;
          reportScore(_score);
          reportStats(_statsLine());
          _mergesThisStage += 1;
          _spawnMergeVfx(avgX, avgY, _kFruits[a.tier], null);
          final banner = combo >= 4
              ? 'DELICIOUS!'
              : combo == 3
                  ? 'SWEET!'
                  : combo == 2
                      ? 'NICE!'
                      : 'DROP!';
          final floaterText =
              combo >= 2 ? '$banner +$pts' : '+$pts';
          _floaters.add(_Floater(
            x: avgX,
            y: avgY,
            text: floaterText,
            color: combo >= 3
                ? const Color(0xFFFF5BAA)
                : combo == 2
                    ? const Color(0xFFFF9CCC)
                    : const Color(0xFFFFC837),
            size: combo >= 3 ? 28 : 24,
          ));
        }
        _wakeAround(avgX, avgY);
        haptic(HapticFeedbackType.medium);
        break;
      }
    }
    if (consumed.isNotEmpty) {
      final ordered = consumed.toList()..sort((a, b) => b.compareTo(a));
      for (final idx in ordered) {
        _bodies.removeAt(idx);
      }
    }
  }

  void _wakeAround(double x, double y) {
    for (final b in _bodies) {
      final dx = b.x - x;
      final dy = b.y - y;
      if (dx * dx + dy * dy < 80 * 80) {
        b.resting = false;
      }
    }
  }

  void _spawnMergeVfx(double x, double y, _FruitPalette p, String? extra) {
    _rings.add(_Ring(x: x, y: y, color: p.body, life: 1.0, r0: 4));
    for (var i = 0; i < 14; i++) {
      final a = (i / 14) * 2 * pi + _rng.nextDouble() * 0.4;
      final sp = 80 + _rng.nextDouble() * 90;
      _sparks.add(_Spark(
        x: x,
        y: y,
        vx: cos(a) * sp,
        vy: sin(a) * sp - 30,
        life: 1.0,
        color: i.isEven ? p.body : p.accent,
        size: 4 + _rng.nextDouble() * 3,
      ));
    }
    if (extra != null) {
      _score += 50;
      reportScore(_score);
    }
  }

  // ───────────────────────────────────────────────────────────────
  // Overfill
  // ───────────────────────────────────────────────────────────────

  void _overfillStep(double dt) {
    final dangerLine = _vesselTop + (_floorY - _vesselTop) * 0.30;
    bool danger = false;
    for (final b in _bodies) {
      if (b.y - b.r < dangerLine) {
        danger = true;
        break;
      }
    }
    if (danger) {
      _overfillTimer += dt;
      _overfillActive = true;
      if (_overfillTimer >= 3.0 && _hearts > 0) {
        _overfillTimer = 0;
        _overfillActive = false;
        _loseLife();
      }
    } else {
      _overfillTimer = max(0, _overfillTimer - dt * 1.5);
      if (_overfillTimer == 0) _overfillActive = false;
    }
  }

  void _loseLife() {
    _hearts -= 1;
    _heartsPulse = 1.0;
    HapticFeedback.heavyImpact();
    haptic(HapticFeedbackType.heavy);
    _floaters.add(_Floater(
      x: 0.5,
      y: 0.42,
      text: '-1 ♥',
      color: const Color(0xFFFF3B5C),
      size: 34,
    ));
    if (_hearts <= 0) {
      _endGame();
    }
  }

  // ───────────────────────────────────────────────────────────────
  // Input → drop
  // ───────────────────────────────────────────────────────────────

  void _drop() {
    if (_paused || _isGameOver) return;
    if (_bodies.length > 60) return;
    final w = _vesselRight - _vesselLeft;
    if (_clawX < _vesselLeft + w * 0.05 ||
        _clawX > _vesselRight - w * 0.05) {
      return;
    }
    final r = _radiusForTier(_holdTier);
    _pending.add(_FruitBody(
      x: _clawX,
      y: _vesselTop + r + 12,
      vx: 0,
      vy: 60,
      r: r,
      tier: _holdTier,
    ));
    _holdTier = _nextTier;
    _nextTier = _rng.nextInt(5);
    HapticFeedback.lightImpact();
    haptic(HapticFeedbackType.light);
    _dismissTutorial();
  }

  void _dismissTutorial() {
    if (!_tutorialDismissed) {
      _tutorialDismissed = true;
    }
  }

  // ───────────────────────────────────────────────────────────────
  // End-game
  // ───────────────────────────────────────────────────────────────

  void _endGame() {
    if (_isGameOver) return;
    _isGameOver = true;
    _paused = false;
    haptic(HapticFeedbackType.heavy);
    reportScore(_score);
    reportGameOver();
  }

  // ───────────────────────────────────────────────────────────────
  // Build
  // ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        _recalc(c.biggest);
        return Stack(
          children: [
            // Canvas.
            Positioned.fill(
              child: CustomPaint(
                painter: _FruitMergePainter(
                  vesselLeft: _vesselLeft,
                  vesselRight: _vesselRight,
                  vesselTop: _vesselTop,
                  vesselBottom: _vesselBottom,
                  floorY: _floorY,
                  bodies: _bodies,
                  sparks: _sparks,
                  rings: _rings,
                  floaters: _floaters,
                  overfillActive: _overfillActive,
                  overfillTimer: _overfillTimer,
                  clawX: _clawX,
                  holdTier: _holdTier,
                  nextTier: _nextTier,
                  idleTime: _idleTime,
                  heartsPulse: _heartsPulse,
                  isGameOver: _isGameOver,
                  paused: _paused,
                  score: _score,
                  hearts: _hearts,
                  rng: _rng,
                ),
              ),
            ),
            // Tap-to-drop.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) {
                  if (!_tutorialDismissed) {
                    _dismissTutorial();
                  }
                  _drop();
                },
              ),
            ),
            // Tutorial overlay (game-specific, not host chrome).
            if (!_tutorialDismissed)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: _TutorialOverlayFruit(onDismiss: _dismissTutorial),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Records
// ─────────────────────────────────────────────────────────────────

class _FruitBody {
  _FruitBody({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.r,
    required this.tier,
  });
  double x;
  double y;
  double vx;
  double vy;
  double r;
  int tier;
  double rot = 0;
  double rotVel = 0;
  bool resting = false;
}

class _Spark {
  _Spark({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.life,
    required this.color,
    required this.size,
  });
  double x;
  double y;
  double vx;
  double vy;
  double life;
  Color color;
  double size;
}

class _Ring {
  _Ring({
    required this.x,
    required this.y,
    required this.color,
    required this.life,
    required this.r0,
  });
  double x;
  double y;
  Color color;
  double life;
  double r0;
  double radius = 0;
}

class _Floater {
  _Floater({
    required this.x,
    required this.y,
    required this.text,
    required this.color,
    required this.size,
  }) : life = 1.4;
  double x;
  double y;
  String text;
  Color color;
  double size;
  double life;
}

// ─────────────────────────────────────────────────────────────────
// Tutorial overlay (game-specific, not host chrome)
// ─────────────────────────────────────────────────────────────────

class _TutorialOverlayFruit extends StatefulWidget {
  const _TutorialOverlayFruit({required this.onDismiss});
  final VoidCallback onDismiss;

  @override
  State<_TutorialOverlayFruit> createState() => _TutorialOverlayFruitState();
}

class _TutorialOverlayFruitState extends State<_TutorialOverlayFruit>
    with SingleTickerProviderStateMixin {
  late final Ticker _tk;
  double _t = 0;
  @override
  void initState() {
    super.initState();
    _tk = createTicker(_onTick)..start();
  }
  void _onTick(Duration _) {
    if (!mounted) return;
    setState(() => _t += 1 / 60);
  }
  @override
  void dispose() {
    _tk.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final slide = Curves.easeOutCubic.transform((_t * 3.5).clamp(0.0, 1.0));
    final bob = sin(_t * 5) * 4.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + (1 - slide) * 60),
      child: Opacity(
        opacity: slide,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 44,
                height: 44,
                child: Transform.translate(
                  offset: Offset(0, bob),
                  child: const Icon(
                    Icons.touch_app_rounded,
                    color: Color(0xFFEC4899),
                    size: 36,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Flexible(
                child: Text(
                  'Tap to drop fruits. Match 2 to merge!',
                  style: TextStyle(
                    color: Color(0xFF1E3A8A),
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Painter
// ─────────────────────────────────────────────────────────────────

class _FruitMergePainter extends CustomPainter {
  _FruitMergePainter({
    required this.vesselLeft,
    required this.vesselRight,
    required this.vesselTop,
    required this.vesselBottom,
    required this.floorY,
    required this.bodies,
    required this.sparks,
    required this.rings,
    required this.floaters,
    required this.overfillActive,
    required this.overfillTimer,
    required this.clawX,
    required this.holdTier,
    required this.nextTier,
    required this.idleTime,
    required this.heartsPulse,
    required this.isGameOver,
    required this.paused,
    required this.score,
    required this.hearts,
    required this.rng,
  });

  final double vesselLeft;
  final double vesselRight;
  final double vesselTop;
  final double vesselBottom;
  final double floorY;
  final List<_FruitBody> bodies;
  final List<_Spark> sparks;
  final List<_Ring> rings;
  final List<_Floater> floaters;
  final bool overfillActive;
  final double overfillTimer;
  final double clawX;
  final int holdTier;
  final int nextTier;
  final double idleTime;
  final double heartsPulse;
  final bool isGameOver;
  final bool paused;
  final int score;
  final int hearts;
  final Random rng;

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackground(canvas, size);
    _drawVessel(canvas, size);
    _drawOverfillLine(canvas, size);
    _drawDropper(canvas, size);
    _drawBodies(canvas);
    _drawVfx(canvas, size);
    _drawFloaters(canvas, size);
  }

  void _drawBackground(Canvas canvas, Size size) {
    // Tan/cream base.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFFFFE7C5),
    );
    // Soft vertical stripes (alternating tans).
    final stripe = const Color(0xFFF5D4A0);
    final stripePaint = Paint()..color = stripe.withValues(alpha: 0.4);
    const stripeW = 16.0;
    for (var x = 0.0; x < size.width; x += stripeW * 2) {
      canvas.drawRect(
        Rect.fromLTWH(x, 0, stripeW, size.height),
        stripePaint,
      );
    }
    // Subtle vignette.
    final vignette = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.transparent,
          Colors.black.withValues(alpha: 0.08),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), vignette);
  }

  void _drawVessel(Canvas canvas, Size size) {
    final w = vesselRight - vesselLeft;
    final h = vesselBottom - vesselTop;
    // Soft drop shadow.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(vesselLeft + 4, vesselTop + 6, w, h),
        const Radius.circular(36),
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
    // Glass body — white translucent fill.
    final glassRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(vesselLeft, vesselTop, w, h),
      const Radius.circular(36),
    );
    canvas.drawRRect(
      glassRect,
      Paint()..color = Colors.white.withValues(alpha: 0.55),
    );
    // Outline.
    canvas.drawRRect(
      glassRect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    // Top highlight band.
    final hi = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.85),
          Colors.white.withValues(alpha: 0),
        ],
      ).createShader(
        Rect.fromLTWH(vesselLeft + 8, vesselTop + 4, w - 16, h * 0.20),
      );
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(vesselLeft + 8, vesselTop + 4, w - 16, h * 0.20),
        topLeft: const Radius.circular(28),
        topRight: const Radius.circular(28),
      ),
      hi,
    );
    // Side gleam (left).
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(vesselLeft + 6, vesselTop + h * 0.12, 5, h * 0.55),
        const Radius.circular(5),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.55),
    );
  }

  void _drawOverfillLine(Canvas canvas, Size size) {
    final dangerY = vesselTop + (floorY - vesselTop) * 0.30;
    final color = overfillActive
        ? const Color(0xFFFF3B5C)
        : const Color(0xFFFF3B5C).withValues(alpha: 0.40);
    final dashW = 8.0;
    final gap = 5.0;
    final p = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    var x = vesselLeft + 12;
    final end = vesselRight - 12;
    while (x < end) {
      final e = min(x + dashW, end);
      canvas.drawLine(Offset(x, dangerY), Offset(e, dangerY), p);
      x += dashW + gap;
    }
    if (overfillActive) {
      final t = (overfillTimer / 3.0).clamp(0.0, 1.0);
      canvas.drawRect(
        Rect.fromLTRB(vesselLeft, vesselTop + 4, vesselRight, dangerY),
        Paint()
          ..color = const Color(0xFFFF3B5C).withValues(alpha: 0.10 + t * 0.10),
      );
    }
  }

  void _drawDropper(Canvas canvas, Size size) {
    final cx = clawX;
    final headY = vesselTop - 36;
    // Drop-line trail (dotted) from dropper to vessel mouth.
    final dotP = Paint()
      ..color = const Color(0xFFEC4899).withValues(alpha: 0.55)
      ..style = PaintingStyle.fill;
    final startY = headY + 24;
    final endY = vesselTop - 4;
    var dy = startY;
    while (dy < endY) {
      canvas.drawCircle(Offset(cx, dy), 2.2, dotP);
      dy += 14;
    }
    // Rail across the top.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(vesselLeft, headY - 12, vesselRight, headY - 6),
        const Radius.circular(6),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );
    // Claw body (rounded rect).
    final headW = 56.0;
    final headH = 26.0;
    final headRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(cx, headY + headH / 2),
        width: headW,
        height: headH,
      ),
      const Radius.circular(10),
    );
    canvas.drawRRect(
      headRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [Color(0xFFFFE7C5), Color(0xFFFFB347)],
        ).createShader(headRect.outerRect),
    );
    canvas.drawRRect(
      headRect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    // Eyes on the claw (kawaii).
    canvas.drawCircle(
      Offset(cx - 7, headY + 12),
      2.5,
      Paint()..color = const Color(0xFF1F0A14),
    );
    canvas.drawCircle(
      Offset(cx + 7, headY + 12),
      2.5,
      Paint()..color = const Color(0xFF1F0A14),
    );
    // Held fruit below the claw.
    final bob = sin(idleTime * 3) * 1.5;
    _drawFruit(
      canvas,
      Offset(cx, headY + headH + 14 + bob),
      _radiusForTier(holdTier),
      holdTier,
    );
  }

  void _drawBodies(Canvas canvas) {
    for (final b in bodies) {
      canvas.save();
      canvas.translate(b.x, b.y);
      canvas.rotate(b.rot);
      // Soft shadow.
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(0, b.r * 0.85),
          width: b.r * 1.5,
          height: b.r * 0.4,
        ),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.18)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      _drawFruit(canvas, Offset.zero, b.r, b.tier);
      canvas.restore();
    }
  }

  void _drawVfx(Canvas canvas, Size size) {
    for (final r in rings) {
      canvas.drawCircle(
        Offset(r.x, r.y),
        r.r0 + r.radius,
        Paint()
          ..color = r.color.withValues(alpha: r.life.clamp(0.0, 1.0) * 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
    for (final s in sparks) {
      final alpha = s.life.clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(s.x, s.y),
        s.size,
        Paint()..color = s.color.withValues(alpha: alpha),
      );
    }
  }

  void _drawFloaters(Canvas canvas, Size size) {
    for (final f in floaters) {
      final alpha = (f.life / 1.4).clamp(0.0, 1.0);
      final cx = f.x;
      final tp = TextPainter(
        text: TextSpan(
          text: f.text,
          style: TextStyle(
            color: f.color.withValues(alpha: alpha),
            fontSize: f.size,
            fontWeight: FontWeight.w900,
            shadows: const [
              Shadow(blurRadius: 4, color: Color(0x66000000)),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(cx - tp.width / 2, f.y - tp.height / 2));
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Fruit dispatcher — picks the cartoon look per tier.
  // ─────────────────────────────────────────────────────────────

  void _drawFruit(Canvas canvas, Offset c, double r, int tier) {
    final kind = _FruitKind.values[tier.clamp(0, _FruitKind.values.length - 1)];
    final palette = _kFruits[tier.clamp(0, _maxTier)];
    switch (kind) {
      case _FruitKind.grape:
        _drawGrapeCluster(canvas, c, r, palette);
        break;
      case _FruitKind.cherry:
        _drawCherry(canvas, c, r, palette);
        break;
      case _FruitKind.orange:
        _drawOrange(canvas, c, r, palette);
        break;
      case _FruitKind.watermelonSlice:
        _drawWatermelonSlice(canvas, c, r, palette);
        break;
      case _FruitKind.greenApple:
        _drawGreenApple(canvas, c, r, palette);
        break;
      case _FruitKind.strawberry:
        _drawStrawberry(canvas, c, r, palette);
        break;
      case _FruitKind.apple:
        _drawApple(canvas, c, r, palette);
        break;
      case _FruitKind.lemon:
        _drawLemon(canvas, c, r, palette);
        break;
      case _FruitKind.pumpkin:
        _drawPumpkin(canvas, c, r, palette);
        break;
      case _FruitKind.plum:
        _drawPlum(canvas, c, r, palette);
        break;
      case _FruitKind.watermelon:
        _drawWatermelon(canvas, c, r, palette);
        break;
    }
  }

  void _drawFace(Canvas c, Offset pos, double r) {
    final eyeR = r * 0.13;
    final eyeOffset = r * 0.32;
    c.drawCircle(pos + Offset(-eyeOffset, -r * 0.05), eyeR,
        Paint()..color = const Color(0xFF1F0A14));
    c.drawCircle(pos + Offset(eyeOffset, -r * 0.05), eyeR,
        Paint()..color = const Color(0xFF1F0A14));
    c.drawCircle(pos + Offset(-eyeOffset + eyeR * 0.4, -r * 0.05 - eyeR * 0.4),
        eyeR * 0.45, Paint()..color = Colors.white);
    c.drawCircle(pos + Offset(eyeOffset + eyeR * 0.4, -r * 0.05 - eyeR * 0.4),
        eyeR * 0.45, Paint()..color = Colors.white);
    final smile = Path();
    smile.moveTo(pos.dx - r * 0.22, pos.dy + r * 0.18);
    smile.quadraticBezierTo(pos.dx, pos.dy + r * 0.30,
        pos.dx + r * 0.22, pos.dy + r * 0.18);
    c.drawPath(
      smile,
      Paint()
        ..color = const Color(0xFF1F0A14)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.10
        ..strokeCap = StrokeCap.round,
    );
    c.drawCircle(pos + Offset(-r * 0.45, r * 0.10), r * 0.10,
        Paint()..color = const Color(0xFFFF9CCC).withValues(alpha: 0.65));
    c.drawCircle(pos + Offset(r * 0.45, r * 0.10), r * 0.10,
        Paint()..color = const Color(0xFFFF9CCC).withValues(alpha: 0.65));
  }

  void _drawGlossyBody(
      Canvas c, Offset center, double r, _FruitPalette p, double aspect) {
    c.drawCircle(
      center,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [p.highlight, p.body],
        ).createShader(Rect.fromCircle(center: center, radius: r * aspect)),
    );
    c.drawCircle(
      center,
      r,
      Paint()
        ..color = p.outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    c.drawCircle(
      center + Offset(-r * 0.32, -r * 0.36),
      r * 0.20,
      Paint()..color = Colors.white.withValues(alpha: 0.65),
    );
  }

  // Grape — cluster of three small berries.
  void _drawGrapeCluster(Canvas c, Offset center, double r, _FruitPalette p) {
    final dx = r * 0.45;
    final dy = r * 0.30;
    final small = r * 0.55;
    final positions = [
      center + Offset(-dx, dy),
      center + Offset(dx, dy),
      center + Offset(0, -dy * 0.5),
    ];
    for (final pos in positions) {
      c.drawCircle(pos, small,
          Paint()..color = p.body);
      c.drawCircle(
        pos,
        small,
        Paint()
          ..color = p.outline
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      c.drawCircle(
        pos + Offset(-small * 0.32, -small * 0.36),
        small * 0.20,
        Paint()..color = Colors.white.withValues(alpha: 0.55),
      );
    }
    _drawFace(c, center + Offset(0, r * 0.10), r * 0.55);
  }

  void _drawCherry(Canvas c, Offset center, double r, _FruitPalette p) {
    final small = r * 0.55;
    final dy = r * 0.35;
    final positions = [
      center + Offset(-r * 0.4, dy),
      center + Offset(r * 0.4, dy),
    ];
    for (final pos in positions) {
      c.drawCircle(pos, small, Paint()..color = p.body);
      c.drawCircle(
        pos,
        small,
        Paint()
          ..color = p.outline
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      c.drawCircle(
        pos + Offset(-small * 0.3, -small * 0.35),
        small * 0.18,
        Paint()..color = Colors.white.withValues(alpha: 0.6),
      );
    }
    // Stems.
    final stem = Paint()
      ..color = const Color(0xFF557A1F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    c.drawLine(center + Offset(-r * 0.4, dy - small),
        center + Offset(0, -r * 0.6), stem);
    c.drawLine(center + Offset(r * 0.4, dy - small),
        center + Offset(0, -r * 0.6), stem);
    _drawFace(c, center + Offset(0, r * 0.45), r * 0.45);
  }

  void _drawOrange(Canvas c, Offset center, double r, _FruitPalette p) {
    _drawGlossyBody(c, center, r, p, 1.2);
    // Segment lines.
    final seg = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (var i = 0; i < 4; i++) {
      final a = (i / 4) * 2 * pi;
      c.drawLine(
        center,
        center + Offset(cos(a) * r * 0.7, sin(a) * r * 0.7),
        seg,
      );
    }
    // Leaf.
    c.drawOval(
      Rect.fromCenter(
        center: center + Offset(r * 0.35, -r * 0.85),
        width: r * 0.4,
        height: r * 0.22,
      ),
      Paint()..color = const Color(0xFF22C55E),
    );
    _drawFace(c, center + Offset(0, r * 0.1), r * 0.55);
  }

  void _drawWatermelonSlice(
      Canvas c, Offset center, double r, _FruitPalette p) {
    // Half-circle (D-shape): flat side down, dome up.
    final rect = Rect.fromCenter(
      center: center + Offset(0, r * 0.15),
      width: r * 1.9,
      height: r * 1.7,
    );
    final dome = Path()
      ..moveTo(rect.left, rect.bottom)
      ..lineTo(rect.left, rect.center.dy)
      ..arcToPoint(rect.topRight, radius: Radius.circular(r))
      ..lineTo(rect.right, rect.bottom)
      ..close();
    c.drawPath(dome, Paint()..color = const Color(0xFF22C55E));
    // Red flesh inset.
    final fleshRect = Rect.fromCenter(
      center: center + Offset(0, r * 0.15),
      width: r * 1.6,
      height: r * 1.4,
    );
    final flesh = Path()
      ..moveTo(fleshRect.left, fleshRect.bottom)
      ..lineTo(fleshRect.left, fleshRect.center.dy)
      ..arcToPoint(fleshRect.topRight, radius: Radius.circular(r * 0.85))
      ..lineTo(fleshRect.right, fleshRect.bottom)
      ..close();
    c.drawPath(flesh, Paint()..color = const Color(0xFFEF4444));
    // Seeds.
    final seed = Paint()..color = const Color(0xFF1F0A14);
    for (var i = 0; i < 6; i++) {
      final t = (i + 1) / 7;
      final ang = pi * t;
      final px = center.dx + cos(ang) * r * 0.5;
      final py = center.dy + r * 0.15 - sin(ang) * r * 0.55;
      c.drawOval(
        Rect.fromCenter(center: Offset(px, py), width: 4, height: 6),
        seed,
      );
    }
    // Outline.
    c.drawPath(
      dome,
      Paint()
        ..color = const Color(0xFF14532D)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  void _drawGreenApple(Canvas c, Offset center, double r, _FruitPalette p) {
    _drawGlossyBody(c, center, r, p, 1.0);
    _drawLeafAndStem(c, center, r);
    _drawFace(c, center + Offset(0, r * 0.10), r * 0.55);
  }

  /// Leaf (upper-right) + stem (top) shared by green apple, red apple,
  /// and plum. Plum uses a slightly taller stem — pass [stemTop] to
  /// override the default `-r * 1.10`.
  void _drawLeafAndStem(Canvas c, Offset center, double r,
      {double stemTop = -1.10}) {
    final leafRect = Rect.fromCenter(
      center: center + Offset(r * 0.35, -r * 0.95),
      width: r * 0.35,
      height: r * 0.22,
    );
    c.drawOval(leafRect, Paint()..color = const Color(0xFF22C55E));
    c.drawOval(
      leafRect,
      Paint()
        ..color = const Color(0xFF14532D)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    c.drawLine(
      center + Offset(0, -r * 0.95),
      center + Offset(0, r * stemTop),
      Paint()
        ..color = const Color(0xFF6B4226)
        ..strokeWidth = 2.5,
    );
  }

  void _drawStrawberry(Canvas c, Offset center, double r, _FruitPalette p) {
    // Body (heart-ish triangle).
    final path = Path();
    path.moveTo(center.dx - r * 0.85, center.dy - r * 0.20);
    path.quadraticBezierTo(center.dx, center.dy - r * 1.10,
        center.dx + r * 0.85, center.dy - r * 0.20);
    path.quadraticBezierTo(center.dx + r * 0.70, center.dy + r * 0.80,
        center.dx, center.dy + r * 0.95);
    path.quadraticBezierTo(center.dx - r * 0.70, center.dy + r * 0.80,
        center.dx - r * 0.85, center.dy - r * 0.20);
    path.close();
    c.drawPath(path, Paint()..color = p.body);
    c.drawPath(
      path,
      Paint()
        ..color = p.outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    // Leafy crown.
    final crown = Path();
    crown.moveTo(center.dx - r * 0.7, center.dy - r * 0.20);
    crown.quadraticBezierTo(center.dx - r * 0.4, center.dy - r * 0.85,
        center.dx, center.dy - r * 0.35);
    crown.quadraticBezierTo(center.dx + r * 0.4, center.dy - r * 0.85,
        center.dx + r * 0.7, center.dy - r * 0.20);
    crown.close();
    c.drawPath(crown, Paint()..color = const Color(0xFF22C55E));
    c.drawPath(
      crown,
      Paint()
        ..color = const Color(0xFF14532D)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    // Seeds.
    final seed = Paint()..color = const Color(0xFFFFE0E5);
    for (var i = 0; i < 8; i++) {
      final px = center.dx + (i.isEven ? -r * 0.4 : r * 0.4);
      final py = center.dy + r * 0.05 + (i % 3) * r * 0.25;
      c.drawOval(
        Rect.fromCenter(center: Offset(px, py), width: 3, height: 4),
        seed,
      );
    }
    _drawFace(c, center + Offset(0, r * 0.30), r * 0.45);
  }

  void _drawApple(Canvas c, Offset center, double r, _FruitPalette p) {
    _drawGlossyBody(c, center, r, p, 1.0);
    _drawLeafAndStem(c, center, r);
    _drawFace(c, center + Offset(0, r * 0.10), r * 0.55);
  }

  void _drawLemon(Canvas c, Offset center, double r, _FruitPalette p) {
    final path = Path();
    path.moveTo(center.dx - r * 1.0, center.dy);
    path.quadraticBezierTo(center.dx - r * 0.4, center.dy - r * 0.85,
        center.dx, center.dy - r * 0.55);
    path.quadraticBezierTo(center.dx + r * 0.5, center.dy - r * 0.30,
        center.dx + r * 1.0, center.dy - r * 0.10);
    path.quadraticBezierTo(center.dx + r * 0.5, center.dy + r * 0.40,
        center.dx, center.dy + r * 0.55);
    path.quadraticBezierTo(center.dx - r * 0.4, center.dy + r * 0.85,
        center.dx - r * 1.0, center.dy);
    path.close();
    c.drawPath(path, Paint()..color = p.body);
    c.drawPath(
      path,
      Paint()
        ..color = p.outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    _drawFace(c, center + Offset(0, r * 0.05), r * 0.45);
  }

  void _drawPumpkin(Canvas c, Offset center, double r, _FruitPalette p) {
    // Outer ellipse.
    c.drawOval(
      Rect.fromCenter(center: center, width: r * 2.0, height: r * 1.5),
      Paint()..color = p.body,
    );
    // Vertical ridges.
    final ridge = Paint()
      ..color = p.outline.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (var i = -2; i <= 2; i++) {
      final dx = i * r * 0.35;
      c.drawLine(
        Offset(center.dx + dx, center.dy - r * 0.7),
        Offset(center.dx + dx * 0.4, center.dy + r * 0.7),
        ridge,
      );
    }
    c.drawOval(
      Rect.fromCenter(center: center, width: r * 2.0, height: r * 1.5),
      Paint()
        ..color = p.outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    // Stem.
    c.drawLine(
      center + Offset(0, -r * 0.75),
      center + Offset(0, -r * 1.10),
      Paint()
        ..color = const Color(0xFF22C55E)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
    _drawFace(c, center + Offset(0, r * 0.10), r * 0.45);
  }

  void _drawPlum(Canvas c, Offset center, double r, _FruitPalette p) {
    _drawGlossyBody(c, center, r, p, 1.1);
    _drawLeafAndStem(c, center, r, stemTop: -1.20);
    _drawFace(c, center + Offset(0, r * 0.10), r * 0.45);
  }

  void _drawWatermelon(Canvas c, Offset center, double r, _FruitPalette p) {
    final body = Rect.fromCenter(
        center: center, width: r * 2.2, height: r * 1.55);
    c.drawOval(body, Paint()..color = const Color(0xFF22C55E));
    // Curved vertical stripes that follow the oval's contour, like a
    // real watermelon — each stripe is its own quadratic curve.
    final stripe = Paint()
      ..color = const Color(0xFF14532D)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (var i = -3; i <= 3; i++) {
      final topDx = i * r * 0.32;
      final botDx = topDx * 0.6;
      final path = Path()
        ..moveTo(center.dx + topDx, body.top + 6)
        ..quadraticBezierTo(
          center.dx + topDx * 0.3,
          center.dy,
          center.dx + botDx,
          body.bottom - 6,
        );
      c.drawPath(path, stripe);
    }
    c.drawOval(
      body,
      Paint()
        ..color = p.outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    _drawFace(c, center + Offset(0, r * 0.10), r * 0.40);
  }

  @override
  bool shouldRepaint(_FruitMergePainter old) =>
      old.bodies != bodies ||
      old.sparks != sparks ||
      old.rings != rings ||
      old.floaters != floaters ||
      old.clawX != clawX ||
      old.holdTier != holdTier ||
      old.nextTier != nextTier ||
      old.idleTime != idleTime ||
      old.overfillActive != overfillActive ||
      old.overfillTimer != overfillTimer ||
      old.heartsPulse != heartsPulse ||
      old.hearts != hearts;
}
