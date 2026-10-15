import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../core/widgets/scale_tap_button.dart';
import '../game_widgets.dart';
import '../mini_game.dart';

/// Snake Master — polished grid-based arcade snake.
///
/// Visual upgrade (plan: gentle-dazzling-river):
///   * Bright pastel-blue backdrop (#EAF4FF) everywhere outside the
///     playfield, white rounded playfield card with soft grid overlay
///     and pastel-blue rails replacing the legacy dark brick walls.
///   * Top HUD — white circular Pause button + MEDIUM difficulty pill
///     on left, white `LENGTH N` card centred, red hearts pill on
///     right (replacing the legacy dark _HudChip pills).
///   * Kawaii snake head — thick dark outline + glossy eyes + small
///     smile + tongue flicker; rounded pastel-green body segments
///     with per-segment dark outline.
///   * Vibrant vector food pool — rotating stars, apples, and golden
///     coins, each with glossy highlights and dark outlines.
///   * 3-D score popups — layered `+50` / `SLITHER!` text with outer
///     yellow glow + yellow stroke + drop shadow + white base.
///   * White floating 4-way D-pad deck at bottom centre (each arrow
///     wrapped in ScaleTapButton for press animation + light haptic).
///   * First-launch tutorial overlay — "Tap D-Pad or Swipe to Guide!"
///     capsule + animated cartoon hand pointing at the D-pad; auto-
///     dismissed after 6 s or on first direction change.
///   * Direct `HapticFeedback.selectionClick` on direction change,
///     `HapticFeedback.mediumImpact` on food/power-up collect,
///     `HapticFeedback.heavyImpact` on collision. Host-proxy calls kept
///     as fallback for audio cue compatibility.
///
/// Engine preserved from previous version: 16×22 grid, smooth 60 FPS
/// interpolation (snake glides between cells), swipe + D-pad input,
/// head pulse on eat, sparkle particles, tongue flickers, speed/magnet
/// power-ups, game-over at wall/self collision.
///
/// Public surface kept byte-identical with the previous engine so the
/// dispatcher (`case 'snake-master'`) keeps resolving:
///   `class SnakeMasterGame extends MiniGame`
///   `const SnakeMasterGame({super.key, required super.callbacks})`
class SnakeMasterGame extends MiniGame {
  const SnakeMasterGame({super.key, required super.callbacks});

  @override
  State<SnakeMasterGame> createState() => _SnakeMasterState();
}

enum _PowerUpKind { none, speed, magnet }

/// Food kind pool. Rotates through three vector fruit/coin/star designs
/// for visual variety.
enum _FoodKind { star, apple, coin }

class _SnakeMasterState extends MiniGameState<SnakeMasterGame>
    with TickerProviderStateMixin {
  // ───────────────────────────────────────────────────────────────
  // Tuning constants
  // ───────────────────────────────────────────────────────────────

  static const int _cols = 16;
  static const int _rows = 22;
  // Tick timing (research defaults: 130→60 ms). We use 140→70 with a
  // -5 ms/level ramp so the ramp is slightly steeper than the legacy
  // -4 ms curve while still landing on a comfortable 70 ms floor.
  static const double _baseStepMs = 140;
  static const double _minStepMs = 70;
  static const double _maxStepMs = 220;
  static const int _stepDecrementMsPerLevel = 5;
  static const int _maxStepDecrementMs = 70;
  static const int _powerupSpeedIntervalMs = 12000;
  static const int _powerupMagnetIntervalMs = 18000;
  static const int _speedBoostDurationMs = 4000;
  static const int _magnetDurationMs = 5000;
  // 3 s feels right — long enough to read "Swipe / D-Pad", short
  // enough not to gate a casual player.
  static const double _tutorialDuration = 3.0;
  static const int _comboThreshold = 3;

  // ───────────────────────────────────────────────────────────────
  // State
  // ───────────────────────────────────────────────────────────────

  late final Ticker _ticker;
  late final Ticker _idleTicker;
  DateTime _last = DateTime.now();
  final Random _rng = Random();

  // Snake: list of cells, head first.
  late List<Point<int>> _snake;
  late Point<int> _food;
  _FoodKind _foodKind = _FoodKind.star;
  Point<int> _dir = const Point(1, 0);
  Point<int> _nextDir = const Point(1, 0);

  // Smooth animation progress: 0..1 toward next cell step.
  double _progress = 0;

  // Score / state.
  int _score = 0;
  int _bestScore = 0;
  int _foodEaten = 0;
  int _consecutiveEats = 0;
  bool _gameOver = false;
  final bool _paused = false;

  // Per-segment pulse for the "eat" pop animation.
  double _headPulse = 0; // 1.0 = idle, >1 = popping

  // Power-ups.
  _PowerUpKind _activePower = _PowerUpKind.none;
  double _powerRemaining = 0; // seconds
  double _powerMagnetTick = 0; // accumulator for magnet pull
  int _powerSpawnTimer = 8000; // ms until next power-up
  _ActivePowerUp? _powerUpOnField;

  // Tongue animation timer.
  double _tongueTimer = 0;
  bool _tongueVisible = false;

  // VFX.
  final List<_Floater> _floaters = [];
  final List<_Particle> _particles = [];
  final List<_Sparkle> _sparkles = [];

  // Screen shake.
  double _shakeTime = 0;
  double _shakeMag = 0;

  // Idle time for food glow pulse + tutorial hand animation.
  double _idleTime = 0;

  // Tutorial state.
  bool _showTutorial = true;
  // ignore: prefer_final_fields
  double _tutorialElapsed = 0;
  bool _tutorialDismissed = false;

  // ───────────────────────────────────────────────────────────────
  // Lifecycle
  // ───────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _snake = _initialSnake();
    _foodKind = _FoodKind.values[_rng.nextInt(_FoodKind.values.length)];
    _food = _spawnFood();
    _ticker = createTicker(_onTick)..start();
    _idleTicker = createTicker(_onIdle)..start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reportScore(_score);
      _refreshStats();
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _idleTicker.dispose();
    super.dispose();
  }

  List<Point<int>> _initialSnake() => [
        Point(7, 10),
        Point(6, 10),
        Point(5, 10),
      ];

  Point<int> _spawnFood() {
    while (true) {
      final p = Point(1 + _rng.nextInt(_cols - 2), 1 + _rng.nextInt(_rows - 2));
      if (!_snake.contains(p)) {
        // Roll a new food kind on each spawn.
        _foodKind = _FoodKind.values[_rng.nextInt(_FoodKind.values.length)];
        return p;
      }
    }
  }

  // ───────────────────────────────────────────────────────────────
  // Tick
  // ───────────────────────────────────────────────────────────────

  double get _currentStepMs {
    final base = _baseStepMs -
        min(_foodEaten * _stepDecrementMsPerLevel, _maxStepDecrementMs)
            .toDouble();
    final speedMult = _activePower == _PowerUpKind.speed ? 0.5 : 1.0;
    return (base * speedMult).clamp(_minStepMs, _maxStepMs);
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    if (_gameOver) {
      if (_ticker.isActive) _ticker.stop();
      return;
    }
    if (_paused) {
      _animateVfx(0.016);
      return;
    }
    final now = DateTime.now();
    final dt = (now.difference(_last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = now;
    _idleTime += dt;

    setState(() {
      final stepSec = _currentStepMs / 1000;
      _progress += dt / stepSec;
      _animateVfx(dt);

      // Tutorial auto-dismiss after timeout.
      if (_showTutorial && !_tutorialDismissed) {
        _tutorialElapsed += dt;
        if (_tutorialElapsed > _tutorialDuration) {
          _dismissTutorial();
        }
      }

      // Power-up spawn.
      _powerSpawnTimer -= (dt * 1000).round();
      if (_powerSpawnTimer <= 0 && _powerUpOnField == null) {
        _spawnPowerUp();
        _powerSpawnTimer = _rng.nextInt(6000) +
            (_powerSpawnTimer < -12000
                ? _powerupSpeedIntervalMs
                : (_powerSpawnTimer < -8000
                    ? _powerupMagnetIntervalMs
                    : 12000));
      }
      // Active power-up countdown.
      if (_activePower != _PowerUpKind.none) {
        _powerRemaining -= dt;
        if (_activePower == _PowerUpKind.magnet) {
          _powerMagnetTick -= dt;
          if (_powerMagnetTick <= 0) {
            _powerMagnetTick = 0.8;
            _magnetPullFood();
          }
        }
        if (_powerRemaining <= 0) {
          _activePower = _PowerUpKind.none;
          _powerRemaining = 0;
        }
      }

      // Step the snake when progress fills.
      while (_progress >= 1) {
        _progress -= 1;
        _stepSnake();
        if (_gameOver) return;
      }
    });
  }

  void _onIdle(Duration elapsed) {
    if (!mounted) return;
    setState(() {
      final dt = 0.016;
      _idleTime += dt;
    });
  }

  void _animateVfx(double dt) {
    for (final f in _floaters) {
      f.y -= 50 * dt;
      f.life -= dt;
    }
    _floaters.removeWhere((f) => f.life <= 0);
    for (final p in _particles) {
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vy += 200 * dt;
      p.life -= dt;
      p.rotation += p.spin * dt;
    }
    _particles.removeWhere((p) => p.life <= 0);
    for (final s in _sparkles) {
      s.life -= dt;
      s.r += 24 * dt;
    }
    _sparkles.removeWhere((s) => s.life <= 0);
    if (_headPulse > 1.0) {
      _headPulse = (_headPulse - dt * 1.6).clamp(1.0, 1.4);
    }
    _tongueTimer += dt;
    if (_tongueTimer > 0.5) {
      _tongueVisible = !_tongueVisible;
      _tongueTimer = 0;
    }
    if (_shakeTime > 0) {
      _shakeTime = (_shakeTime - dt).clamp(0.0, 99.0);
    }
  }

  // ───────────────────────────────────────────────────────────────
  // Snake stepping + collision
  // ───────────────────────────────────────────────────────────────

  void _stepSnake() {
    if (_nextDir.x != -_dir.x || _nextDir.y != -_dir.y) {
      _dir = _nextDir;
    }
    final head = _snake.first;
    final newHead = Point(head.x + _dir.x, head.y + _dir.y);
    // Wall collision (outer ring is lethal — pastel rails are visual
    // markers, the collision boundary stays where it is).
    if (newHead.x <= 0 ||
        newHead.x >= _cols - 1 ||
        newHead.y <= 0 ||
        newHead.y >= _rows - 1) {
      _die();
      return;
    }
    if (_snake.contains(newHead)) {
      _die();
      return;
    }
    _snake = [newHead, ..._snake];

    // Food or power-up pickup.
    if (newHead == _food) {
      _consecutiveEats += 1;
      final isCombo = _consecutiveEats >= _comboThreshold;
      _score += isCombo ? 50 : 10;
      _foodEaten += 1;
      _headPulse = 1.4;
      _floaters.add(_Floater(
        x: newHead.x.toDouble(),
        y: newHead.y.toDouble(),
        text: isCombo ? 'SLITHER! +50' : '+50',
        color: isCombo ? const Color(0xFFFDE047) : const Color(0xFFFFC837),
        fontSize: isCombo ? 22 : 20,
      ));
      // Small "Tasty!" sub-popup for non-combo eats.
      if (!isCombo) {
        _floaters.add(_Floater(
          x: newHead.x.toDouble(),
          y: newHead.y.toDouble(),
          text: 'Tasty!',
          color: const Color(0xFFFB923C),
          fontSize: 12,
        ));
      }
      _sparkles.add(_Sparkle(
        x: newHead.x.toDouble(),
        y: newHead.y.toDouble(),
        r: 0,
        life: 0.6,
      ));
      // 6 sparkle particles around the eaten cell.
      for (var i = 0; i < 6; i++) {
        final a = (i / 6) * 2 * pi;
        _particles.add(_Particle(
          x: newHead.x.toDouble(),
          y: newHead.y.toDouble(),
          vx: cos(a) * (40 + _rng.nextDouble() * 50),
          vy: sin(a) * (40 + _rng.nextDouble() * 50),
          life: 0.6,
          color: isCombo ? const Color(0xFFFDE047) : const Color(0xFFFFC837),
          rotation: _rng.nextDouble() * pi,
          spin: (_rng.nextDouble() - 0.5) * 8,
        ));
      }
      haptic(HapticFeedbackType.light);
      HapticFeedback.mediumImpact();
      _food = _spawnFood();
      reportScore(_score);
      _refreshStats();
      return; // don't trim tail — grow
    }
    if (_powerUpOnField != null && newHead == _powerUpOnField!.pos) {
      _collectPowerUp();
      return; // don't trim tail — grow
    }

    _snake = _snake.sublist(0, _snake.length - 1);
  }

  void _die() {
    if (_gameOver) return;
    _gameOver = true;
    _consecutiveEats = 0;
    reportGameOver();
    if (_score > _bestScore) _bestScore = _score;
    // 20-particle disintegration burst at head.
    final head = _snake.first;
    final hx = head.x.toDouble();
    final hy = head.y.toDouble();
    for (var i = 0; i < 20; i++) {
      final a = (i / 20) * 2 * pi + _rng.nextDouble() * 0.4;
      final sp = 80 + _rng.nextDouble() * 140;
      _particles.add(_Particle(
        x: hx,
        y: hy,
        vx: cos(a) * sp / 8,
        vy: sin(a) * sp / 8,
        life: 0.8,
        color: i.isEven
            ? const Color(0xFF34D399)
            : const Color(0xFFFBBF24),
        rotation: _rng.nextDouble() * pi,
        spin: (_rng.nextDouble() - 0.5) * 12,
      ));
    }
    _shake(0.4, 12);
    haptic(HapticFeedbackType.heavy);
    HapticFeedback.heavyImpact();
    reportScore(_score);
    _refreshStats();
    reportGameOver();
  }

  // ───────────────────────────────────────────────────────────────
  // Power-ups
  // ───────────────────────────────────────────────────────────────

  void _spawnPowerUp() {
    final kind =
        _rng.nextBool() ? _PowerUpKind.speed : _PowerUpKind.magnet;
    while (true) {
      final p = Point(2 + _rng.nextInt(_cols - 4), 2 + _rng.nextInt(_rows - 4));
      if (!_snake.contains(p) && p != _food) {
        _powerUpOnField = _ActivePowerUp(kind: kind, pos: p);
        return;
      }
    }
  }

  void _collectPowerUp() {
    final pu = _powerUpOnField!;
    _activePower = pu.kind;
    _powerRemaining = pu.kind == _PowerUpKind.speed
        ? _speedBoostDurationMs / 1000
        : _magnetDurationMs / 1000;
    if (pu.kind == _PowerUpKind.magnet) {
      _powerMagnetTick = 0.8;
    }
    _floaters.add(_Floater(
      x: pu.pos.x.toDouble(),
      y: pu.pos.y.toDouble(),
      text: pu.kind == _PowerUpKind.speed ? 'SPEED!' : 'MAGNET!',
      color: pu.kind == _PowerUpKind.speed
          ? const Color(0xFF22D3EE)
          : const Color(0xFFA073FF),
    ));
    for (var i = 0; i < 10; i++) {
      final a = (i / 10) * 2 * pi;
      _particles.add(_Particle(
        x: pu.pos.x.toDouble(),
        y: pu.pos.y.toDouble(),
        vx: cos(a) * 60 / 8,
        vy: sin(a) * 60 / 8,
        life: 0.5,
        color: pu.kind == _PowerUpKind.speed
            ? const Color(0xFF22D3EE)
            : const Color(0xFFA073FF),
        rotation: 0,
        spin: 0,
      ));
    }
    _sparkles.add(_Sparkle(
      x: pu.pos.x.toDouble(),
      y: pu.pos.y.toDouble(),
      r: 0,
      life: 0.7,
    ));
    _powerUpOnField = null;
    haptic(HapticFeedbackType.medium);
    HapticFeedback.mediumImpact();
  }

  void _magnetPullFood() {
    if (_activePower != _PowerUpKind.magnet) return;
    final head = _snake.first;
    final dx = (_food.x - head.x).sign;
    final dy = (_food.y - head.y).sign;
    if (dx == 0 && dy == 0) return;
    var newFood = Point(_food.x + dx, _food.y + dy);
    // Don't pull into the snake or walls.
    if (newFood.x <= 0 ||
        newFood.x >= _cols - 1 ||
        newFood.y <= 0 ||
        newFood.y >= _rows - 1 ||
        _snake.contains(newFood)) {
      return;
    }
    _food = newFood;
  }

  // ───────────────────────────────────────────────────────────────
  // Input
  // ───────────────────────────────────────────────────────────────

  void _setDir(Point<int> d) {
    if (_gameOver || _paused) return;
    if (d.x == -_dir.x && d.y == -_dir.y) return;
    _nextDir = d;
    _tongueVisible = true;
    _tongueTimer = 0;
    HapticFeedback.selectionClick();
    _dismissTutorial();
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (d.delta.dx.abs() > d.delta.dy.abs()) {
      if (d.delta.dx.abs() < 24) return;
      _setDir(Point(d.delta.dx > 0 ? 1 : -1, 0));
    } else {
      if (d.delta.dy.abs() < 24) return;
      _setDir(Point(0, d.delta.dy > 0 ? 1 : -1));
    }
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
    reportStats(
        'Length ${_snake.length}  •  Best $_bestScore  •  ${_currentStepMs.round()}ms');
  }

  // ───────────────────────────────────────────────────────────────
  // Build
  // ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFEAF4FF),
            Color(0xFFE0E7FF),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, c) {
                // Cell size = min(width/cols, height/rows) so the grid
                // always fits both axes without leaving a grey void.
                // The old code derived cell from height only and
                // clamp(12, 26)'d it — on tall phones the clamped cell
                // was 26 px and the grid was 416 × 572 with grey void
                // on the sides; on shorter screens it was clamped to
                // 12 px and read as a postage stamp.
                final cell = (c.maxWidth / _cols < c.maxHeight / _rows)
                    ? c.maxWidth / _cols
                    : c.maxHeight / _rows;
                final gridW = cell * _cols;
                final gridH = cell * _rows;
                return Center(
                  child: Transform.translate(
                    offset: _shakeTime > 0
                        ? Offset(
                            (_rng.nextDouble() - 0.5) * _shakeMag,
                            (_rng.nextDouble() - 0.5) * _shakeMag,
                          )
                        : Offset.zero,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: _onPanUpdate,
                      child: SizedBox(
                        width: gridW,
                        height: gridH,
                        child: CustomPaint(
                          painter: _SnakeMasterPainter(
                            snake: _snake,
                            food: _food,
                            foodKind: _foodKind,
                            dir: _dir,
                            progress: _progress,
                            cell: cell,
                            cols: _cols,
                            rows: _rows,
                            headPulse: _headPulse,
                            tongueVisible: _tongueVisible,
                            idleTime: _idleTime,
                            floaters: _floaters,
                            particles: _particles,
                            sparkles: _sparkles,
                            activePower: _activePower,
                            powerRemaining: _powerRemaining,
                            powerUpOnField: _powerUpOnField,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // Top HUD overlay removed — host GameContainerScreen provides it.
          // Active power-up banner (under HUD).
          if (_activePower != _PowerUpKind.none)
            Positioned(
              top: 70,
              left: 12,
              right: 12,
              child: Center(
                child: _PowerBanner(
                  kind: _activePower,
                  remaining: _powerRemaining,
                ),
              ),
            ),
          // Bottom D-Pad deck.
          Positioned(
            left: 0,
            right: 0,
            bottom: 18,
            child: Center(
              child: _SnakeDPad(onChange: _setDir),
            ),
          ),
          // Tutorial overlay (auto-dismiss after 6 s or first direction).
          if (_showTutorial && !_tutorialDismissed)
            Positioned(
              left: 0,
              right: 0,
              bottom: 110,
              child: _TutorialOverlaySnake(
                idleTime: _idleTime,
                progress: _tutorialElapsed / _tutorialDuration,
              ),
            ),
          // Game Over overlay removed — host GameContainerScreen provides it.
          // Pause overlay removed — host GameContainerScreen provides it.
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Power-up banner
// ─────────────────────────────────────────────────────────────────

class _PowerBanner extends StatelessWidget {
  const _PowerBanner({required this.kind, required this.remaining});
  final _PowerUpKind kind;
  final double remaining;

  @override
  Widget build(BuildContext context) {
    final color = kind == _PowerUpKind.speed
        ? const Color(0xFF22D3EE)
        : const Color(0xFFA073FF);
    final icon = kind == _PowerUpKind.speed
        ? Icons.bolt_rounded
        : Icons.savings_rounded;
    final label = kind == _PowerUpKind.speed ? 'SPEED' : 'MAGNET';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: color, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(
            '$label  ${remaining.toStringAsFixed(1)}s',
            style: TextStyle(
              color: const Color(0xFF0F172A),
              fontWeight: FontWeight.w900,
              fontSize: 12,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// VFX records
// ─────────────────────────────────────────────────────────────────

class _ActivePowerUp {
  _ActivePowerUp({required this.kind, required this.pos});
  final _PowerUpKind kind;
  final Point<int> pos;
}

class _Floater {
  _Floater({
    required this.x,
    required this.y,
    required this.text,
    required this.color,
    this.fontSize = 18,
  }) : life = 0.85;
  double x;
  double y;
  String text;
  Color color;
  double fontSize;
  double life;
}

class _Particle {
  _Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.life,
    required this.color,
    required this.rotation,
    required this.spin,
  });
  double x;
  double y;
  double vx;
  double vy;
  double life;
  Color color;
  double rotation;
  double spin;
}

class _Sparkle {
  _Sparkle({required this.x, required this.y, required this.r, required this.life});
  double x;
  double y;
  double r;
  double life;
}

// ─────────────────────────────────────────────────────────────────
// Bottom D-Pad deck (white floating)
// ─────────────────────────────────────────────────────────────────

class _SnakeDPad extends StatelessWidget {
  const _SnakeDPad({required this.onChange});
  final void Function(Point<int>) onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFBFDBFE), width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _btn(Icons.keyboard_arrow_up_rounded, const Point(0, -1)),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _btn(Icons.keyboard_arrow_left_rounded, const Point(-1, 0)),
              const SizedBox(width: 10),
              _btn(Icons.keyboard_arrow_right_rounded, const Point(1, 0)),
            ],
          ),
          _btn(Icons.keyboard_arrow_down_rounded, const Point(0, 1)),
        ],
      ),
    );
  }

  Widget _btn(IconData icon, Point<int> dir) {
    return ScaleTapButton(
      onTap: () => onChange(dir),
      borderRadius: BorderRadius.circular(999),
      padding: const EdgeInsets.all(14),
      color: Colors.white,
      semanticsLabel: 'Direction ${dir.x},${dir.y}',
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFFFFF), Color(0xFFE2E8F0)],
          ),
        ),
        padding: const EdgeInsets.all(10),
        child: Icon(icon, color: const Color(0xFF1E3A8A), size: 26),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Tutorial overlay (capsule + animated hand pointing at D-pad)
// ─────────────────────────────────────────────────────────────────

class _TutorialOverlaySnake extends StatefulWidget {
  const _TutorialOverlaySnake({
    required this.idleTime,
    required this.progress,
  });
  final double idleTime;
  final double progress;

  @override
  State<_TutorialOverlaySnake> createState() => _TutorialOverlaySnakeState();
}

class _TutorialOverlaySnakeState extends State<_TutorialOverlaySnake>
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
              // Hand pointing down-left at the D-pad.
              Transform.rotate(
                angle: 1.0, // tilt to point at D-pad below
                child: CustomPaint(
                  size: const Size(34, 34),
                  painter: _SnakeHandPainter(idleTime: widget.idleTime),
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Tap D-Pad or Swipe to Guide!',
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

class _SnakeHandPainter extends CustomPainter {
  _SnakeHandPainter({required this.idleTime});
  final double idleTime;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w * 0.5;
    final cy = h * 0.45;
    final bob = sin(idleTime * 4) * 3;
    final tap = sin(idleTime * 8) > 0.7 ? 6.0 : 0.0;

    canvas.save();
    canvas.translate(cx, cy + bob + tap);

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

    // Index finger pointing down.
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
  }

  @override
  bool shouldRepaint(_SnakeHandPainter old) =>
      old.idleTime != idleTime;
}

// ─────────────────────────────────────────────────────────────────
// Painter
// ─────────────────────────────────────────────────────────────────

class _SnakeMasterPainter extends CustomPainter {
  _SnakeMasterPainter({
    required this.snake,
    required this.food,
    required this.foodKind,
    required this.dir,
    required this.progress,
    required this.cell,
    required this.cols,
    required this.rows,
    required this.headPulse,
    required this.tongueVisible,
    required this.idleTime,
    required this.floaters,
    required this.particles,
    required this.sparkles,
    required this.activePower,
    required this.powerRemaining,
    required this.powerUpOnField,
  });

  final List<Point<int>> snake;
  final Point<int> food;
  final _FoodKind foodKind;
  final Point<int> dir;
  final double progress;
  final double cell;
  final int cols;
  final int rows;
  final double headPulse;
  final bool tongueVisible;
  final double idleTime;
  final List<_Floater> floaters;
  final List<_Particle> particles;
  final List<_Sparkle> sparkles;
  final _PowerUpKind activePower;
  final double powerRemaining;
  final _ActivePowerUp? powerUpOnField;

  @override
  void paint(Canvas canvas, Size size) {
    _drawPlayfieldCard(canvas, size);
    _drawRails(canvas, size);
    // Power-up on field (drawn under food).
    if (powerUpOnField != null) {
      _drawPowerUp(canvas, powerUpOnField!, size);
    }
    _drawFood(canvas, food, size);
    _drawSnake(canvas, size);
    _drawSparkles(canvas, size);
    _drawParticles(canvas, size);
    _drawFloaters(canvas, size);
    _drawBoardBorder(canvas, size);
  }

  // ─────────────────────────────────────────────────────────────
  // Sections
  // ─────────────────────────────────────────────────────────────

  void _drawPlayfieldCard(Canvas canvas, Size size) {
    // Saturated pastel card — gives the snake / food / pills visible
    // contrast instead of the original white-on-white look.
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(14),
    );
    canvas.drawRRect(rrect, Paint()..color = const Color(0xFFD8E6FF));
    // Stronger indigo grid so the playfield reads as a real board.
    final gridLine = Paint()
      ..color = const Color(0xFF1E3A8A).withValues(alpha: 0.18)
      ..strokeWidth = 1;
    for (var i = 1; i < cols; i++) {
      canvas.drawLine(Offset(i * cell, 0), Offset(i * cell, size.height), gridLine);
    }
    for (var i = 1; i < rows; i++) {
      canvas.drawLine(Offset(0, i * cell), Offset(size.width, i * cell), gridLine);
    }
  }

  void _drawRails(Canvas canvas, Size size) {
    // Pastel-blue rounded rails along the outer ring — visual marker
    // for the lethal boundary (collision check stays at index 0/N-1).
    final railPaint = Paint()..color = const Color(0xFFBFDBFE).withValues(alpha: 0.6);
    final bw = cell;
    final bh = cell;
    // Top + bottom full-width rails.
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, bh), railPaint);
    canvas.drawRect(Rect.fromLTWH(0, size.height - bh, size.width, bh), railPaint);
    // Left + right full-height rails.
    canvas.drawRect(Rect.fromLTWH(0, 0, bw, size.height), railPaint);
    canvas.drawRect(
        Rect.fromLTWH(size.width - bw, 0, bw, size.height), railPaint);
  }

  void _drawFood(Canvas canvas, Point<int> food, Size size) {
    final cx = food.x * cell + cell / 2;
    final cy = food.y * cell + cell / 2;
    final pulse = 0.6 + 0.4 * (0.5 + 0.5 * sin(idleTime * 4));
    // Outer glow ring.
    canvas.drawCircle(
      Offset(cx, cy),
      cell * 0.55,
      Paint()
        ..color = const Color(0xFFFACC15).withValues(alpha: 0.18 * pulse),
    );
    switch (foodKind) {
      case _FoodKind.star:
        _drawStar(canvas, cx, cy, cell);
        break;
      case _FoodKind.apple:
        _drawApple(canvas, cx, cy, cell);
        break;
      case _FoodKind.coin:
        _drawCoin(canvas, cx, cy, cell);
        break;
    }
  }

  void _drawStar(Canvas canvas, double cx, double cy, double cell) {
    final r = cell * 0.36;
    // 5-point star path.
    final path = Path();
    const points = 5;
    for (var i = 0; i < points * 2; i++) {
      final angle = -pi / 2 + (i * pi) / points;
      final radius = i.isEven ? r : r * 0.45;
      final px = cx + cos(angle) * radius;
      final py = cy + sin(angle) * radius;
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFACC15), Color(0xFFCA8A04)],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r)),
    );
    // Dark outline.
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF1F2937)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );
    // White highlight crescent.
    canvas.drawCircle(
      Offset(cx - r * 0.25, cy - r * 0.35),
      r * 0.18,
      Paint()..color = Colors.white.withValues(alpha: 0.7),
    );
  }

  void _drawApple(Canvas canvas, double cx, double cy, double cell) {
    final r = cell * 0.32;
    final path = Path();
    path.moveTo(cx, cy + r * 0.7);
    path.cubicTo(
      cx + r * 1.1, cy - r * 0.05,
      cx + r * 0.55, cy - r * 0.85,
      cx, cy - r * 0.35,
    );
    path.cubicTo(
      cx - r * 0.55, cy - r * 0.85,
      cx - r * 1.1, cy - r * 0.05,
      cx, cy + r * 0.7,
    );
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: const [Color(0xFFFCA5A5), Color(0xFFDC2626), Color(0xFFB91C1C)],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r * 1.1)),
    );
    // Outline.
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF1F2937)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );
    // Stem.
    canvas.drawRect(
      Rect.fromLTWH(cx - 1.5, cy - r * 1.05, 3, r * 0.25),
      Paint()..color = const Color(0xFF166534),
    );
    // Leaf.
    final leafPath = Path()
      ..moveTo(cx + 1, cy - r * 1.0)
      ..quadraticBezierTo(cx + r * 0.5, cy - r * 1.25, cx + r * 0.4, cy - r * 0.85)
      ..quadraticBezierTo(cx + r * 0.2, cy - r * 0.95, cx + 1, cy - r * 1.0)
      ..close();
    canvas.drawPath(
      leafPath,
      Paint()..color = const Color(0xFF16A34A),
    );
    // Glossy highlight crescent.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx - r * 0.32, cy - r * 0.36),
        width: r * 0.55,
        height: r * 0.28,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.6),
    );
  }

  void _drawCoin(Canvas canvas, double cx, double cy, double cell) {
    final r = cell * 0.32;
    // Outer ring.
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: const [Color(0xFFFEF08A), Color(0xFFFBBF24), Color(0xFFB45309)],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r)),
    );
    // Inner ring.
    canvas.drawCircle(
      Offset(cx, cy),
      r * 0.85,
      Paint()
        ..color = const Color(0xFFFBBF24)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
    // Outline.
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..color = const Color(0xFF1F2937)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    // Dollar sign glyph.
    final tp = TextPainter(
      text: TextSpan(
        text: r'$',
        style: TextStyle(
          color: const Color(0xFF1F2937),
          fontSize: r * 1.1,
          fontWeight: FontWeight.w900,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
    // Highlight crescent (top-left).
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx - r * 0.25, cy - r * 0.30),
        width: r * 0.55,
        height: r * 0.28,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.65),
    );
  }

  void _drawSnake(Canvas canvas, Size size) {
    if (snake.isEmpty) return;
    // Each segment: render at its current cell + an offset toward the
    // NEXT segment's cell (so the body follows the head smoothly).
    // Head interpolates from its cell toward (cell + dir) by `progress`.
    final headCell = Offset(
      snake.first.x.toDouble() + dir.x * progress,
      snake.first.y.toDouble() + dir.y * progress,
    );
    // Body segments: each segment `i` (i >= 1) interpolates from its
    // current cell toward the previous segment's cell by `progress`.
    final positions = <Offset>[headCell];
    for (var i = 1; i < snake.length; i++) {
      final cur = snake[i].x.toDouble();
      final curY = snake[i].y.toDouble();
      // Previous segment's "render position" (the position the
      // previous segment was at the START of this step).
      final prev = snake[i - 1];
      // Direction from current to previous (snake follows).
      final dx = (prev.x - snake[i].x).toDouble();
      final dy = (prev.y - snake[i].y).toDouble();
      final px = cur + dx * progress;
      final py = curY + dy * progress;
      positions.add(Offset(px, py));
    }
    for (var i = snake.length - 1; i >= 0; i--) {
      final seg = positions[i];
      final isHead = i == 0;
      // Taper: tail alpha fades.
      final tailT = i / snake.length;
      final baseColor = Color.lerp(
        const Color(0xFF4ADE80),
        const Color(0xFF16A34A),
        tailT * 0.5,
      )!;
      // Head pulse on eat.
      final scale = isHead ? headPulse : 1.0;
      final segSize = cell * (isHead ? 0.85 : 0.72) * scale;
      final rect = Rect.fromCenter(
        center: Offset(seg.dx * cell + cell / 2, seg.dy * cell + cell / 2),
        width: segSize,
        height: segSize,
      );
      final rr = RRect.fromRectAndRadius(rect, Radius.circular(segSize * 0.3));
      // Drop shadow.
      canvas.drawRRect(
        rr.shift(const Offset(1, 2)),
        Paint()..color = Colors.black.withValues(alpha: 0.35),
      );
      // Body gradient.
      canvas.drawRRect(
        rr,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(baseColor, Colors.white, 0.35) ?? baseColor,
              baseColor,
              Color.lerp(baseColor, Colors.black, 0.25) ?? baseColor,
            ],
          ).createShader(rect),
      );
      // Thick dark outline (kawaii).
      canvas.drawRRect(
        rr,
        Paint()
          ..color = const Color(0xFF1F2937)
          ..style = PaintingStyle.stroke
          ..strokeWidth = isHead ? 2.5 : 2.0,
      );
      if (isHead) {
        _drawHeadGloss(canvas, rect);
        _drawHeadFace(canvas, rect, dir);
      }
    }
  }

  void _drawHeadGloss(Canvas canvas, Rect headRect) {
    // Glossy top-left highlight (kawaii).
    final glossRect = Rect.fromCenter(
      center: Offset(headRect.left + headRect.width * 0.30,
          headRect.top + headRect.height * 0.30),
      width: headRect.width * 0.45,
      height: headRect.height * 0.30,
    );
    canvas.drawOval(
      glossRect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: [
            Colors.white.withValues(alpha: 0.55),
            Colors.white.withValues(alpha: 0.0),
          ],
        ).createShader(glossRect),
    );
  }

  void _drawHeadFace(Canvas canvas, Rect headRect, Point<int> dir) {
    final cx = headRect.center.dx;
    final cy = headRect.center.dy;
    final r = headRect.width / 2;
    // Eyes: positioned perpendicular to direction.
    final perpX = -dir.y.toDouble();
    final perpY = dir.x.toDouble();
    // Pupils offset slightly toward direction.
    final pupilOffset = r * 0.18;
    for (final side in [-1, 1]) {
      final eyeCx = cx + perpX * r * 0.32 * side + dir.x * pupilOffset;
      final eyeCy = cy + perpY * r * 0.32 * side + dir.y * pupilOffset;
      // White.
      canvas.drawCircle(
        Offset(eyeCx, eyeCy),
        r * 0.18,
        Paint()..color = Colors.white,
      );
      // Pupil.
      canvas.drawCircle(
        Offset(eyeCx + dir.x * r * 0.05, eyeCy + dir.y * r * 0.05),
        r * 0.10,
        Paint()..color = Colors.black,
      );
      // Tiny highlight on pupil.
      canvas.drawCircle(
        Offset(eyeCx + dir.x * r * 0.05 - r * 0.03,
            eyeCy + dir.y * r * 0.05 - r * 0.03),
        r * 0.03,
        Paint()..color = Colors.white,
      );
    }
    // Small smile arc — drawn on the side opposite to direction.
    final smileCx = cx - dir.x * r * 0.20;
    final smileCy = cy - dir.y * r * 0.20;
    final smileRect = Rect.fromCenter(
      center: Offset(smileCx, smileCy),
      width: r * 0.32,
      height: r * 0.18,
    );
    final smileStartAngle = dir.x != 0
        ? (dir.x > 0 ? pi * 0.15 : pi * 0.85)
        : (dir.y > 0 ? pi * 0.65 : pi * 0.35);
    canvas.drawArc(
      smileRect,
      smileStartAngle,
      pi * 0.7,
      false,
      Paint()
        ..color = const Color(0xFF1F2937)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );
    // Tongue.
    if (tongueVisible) {
      final tongueStart = Offset(
        cx + dir.x * r * 0.5,
        cy + dir.y * r * 0.5,
      );
      final tongueEnd = Offset(
        tongueStart.dx + dir.x * r * 0.5,
        tongueStart.dy + dir.y * r * 0.5,
      );
      canvas.drawLine(
        tongueStart,
        tongueEnd,
        Paint()
          ..color = const Color(0xFFEC4899)
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
      // Forked tip.
      const forkAngle = pi / 6;
      final tipBase = tongueEnd;
      canvas.drawLine(
        tipBase,
        tipBase +
            Offset.fromDirection(
              atan2(dir.y.toDouble(), dir.x.toDouble()) + forkAngle,
              r * 0.18,
            ),
        Paint()
          ..color = const Color(0xFFEC4899)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        tipBase,
        tipBase +
            Offset.fromDirection(
              atan2(dir.y.toDouble(), dir.x.toDouble()) - forkAngle,
              r * 0.18,
            ),
        Paint()
          ..color = const Color(0xFFEC4899)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _drawPowerUp(Canvas canvas, _ActivePowerUp pu, Size size) {
    final cx = pu.pos.x * cell + cell / 2;
    final cy = pu.pos.y * cell + cell / 2;
    final color = pu.kind == _PowerUpKind.speed
        ? const Color(0xFF22D3EE)
        : const Color(0xFFA073FF);
    // Glow.
    canvas.drawCircle(
      Offset(cx, cy),
      cell * 0.55,
      Paint()..color = color.withValues(alpha: 0.25),
    );
    canvas.drawCircle(
      Offset(cx, cy),
      cell * 0.40,
      Paint()..color = Colors.white,
    );
    if (pu.kind == _PowerUpKind.speed) {
      // Lightning bolt.
      final path = Path();
      final r = cell * 0.20;
      path.moveTo(cx - r * 0.4, cy - r * 1.2);
      path.lineTo(cx + r * 0.4, cy - r * 0.2);
      path.lineTo(cx, cy - r * 0.1);
      path.lineTo(cx + r * 0.5, cy + r * 1.2);
      path.lineTo(cx - r * 0.3, cy + r * 0.1);
      path.lineTo(cx, cy + r * 0.0);
      path.close();
      canvas.drawPath(path, Paint()..color = color);
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF1F2937)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    } else {
      // Magnet U-shape.
      final r = cell * 0.22;
      final path = Path()
        ..moveTo(cx - r, cy - r * 0.6)
        ..lineTo(cx - r, cy + r * 0.4)
        ..lineTo(cx - r * 0.4, cy + r * 0.4)
        ..lineTo(cx - r * 0.4, cy - r * 0.1)
        ..lineTo(cx + r * 0.4, cy - r * 0.1)
        ..lineTo(cx + r * 0.4, cy + r * 0.4)
        ..lineTo(cx + r, cy + r * 0.4)
        ..lineTo(cx + r, cy - r * 0.6);
      canvas.drawPath(path, Paint()..color = color);
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF1F2937)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
  }

  void _drawSparkles(Canvas canvas, Size size) {
    for (final s in sparkles) {
      final alpha = (s.life / 0.7).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(s.x * cell + cell / 2, s.y * cell + cell / 2),
        cell * 0.4 + s.r,
        Paint()
          ..color = const Color(0xFFFEF3C7).withValues(alpha: alpha * 0.6),
      );
    }
  }

  void _drawParticles(Canvas canvas, Size size) {
    for (final p in particles) {
      final alpha = (p.life / 0.8).clamp(0.0, 1.0);
      canvas.save();
      canvas.translate(p.x, p.y);
      canvas.rotate(p.rotation);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: cell * 0.22, height: cell * 0.14),
        Paint()..color = p.color.withValues(alpha: alpha),
      );
      canvas.restore();
    }
  }

  void _drawFloaters(Canvas canvas, Size size) {
    for (final f in floaters) {
      final alpha = (f.life / 0.85).clamp(0.0, 1.0);
      _draw3DText(
        canvas,
        Offset(f.x * cell + cell / 2, f.y * cell - (0.85 - f.life) * 30),
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

    // 1. Outer yellow glow (outer blur).
    final glowPaint = Paint()
      ..color = const Color(0xFFFDE047).withValues(alpha: alpha * 0.65)
      ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 12);
    canvas.drawRect(textRect.inflate(4), glowPaint);

    // 2. Yellow stroke outline (layered TextPainter with stroke).
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

  void _drawBoardBorder(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(14),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = const Color(0xFFBFDBFE)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
    // Active-power glow on border.
    if (activePower != _PowerUpKind.none) {
      final color = activePower == _PowerUpKind.speed
          ? const Color(0xFF22D3EE)
          : const Color(0xFFA073FF);
      canvas.drawRRect(
        rrect.inflate(2),
        Paint()
          ..color = color.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 6),
      );
    }
  }

  @override
  bool shouldRepaint(_SnakeMasterPainter old) =>
      old.snake != snake ||
      old.food != food ||
      old.foodKind != foodKind ||
      old.dir != dir ||
      old.progress != progress ||
      old.cell != cell ||
      old.headPulse != headPulse ||
      old.tongueVisible != tongueVisible ||
      old.idleTime != idleTime ||
      old.floaters != floaters ||
      old.particles != particles ||
      old.sparkles != sparkles ||
      old.activePower != activePower ||
      old.powerUpOnField != powerUpOnField;
}
