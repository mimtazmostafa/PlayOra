import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../core/widgets/scale_tap_button.dart';
import '../mini_game.dart';
import '../widgets/tutorial_overlay.dart';

/// Racing Rush — top-down 2.5D sinusoidal racer.
///
/// Visual upgrade (plan: gentle-dazzling-river):
///   * Bright pastel grass + dark asphalt + curved red/white rumble strips
///     that follow the curvature.
///   * Pastel balloons drifting over the grass borders.
///   * 2.5D **camera roll** (canvas rotates ±2° with the curve).
///   * Top HUD bar — circular white Pause + speedometer/boost pill on left,
///     rounded white `SCORE` card in centre, red heart-lives pill on right
///     (replacing the legacy dark cards).
///   * Bottom controls — translucent floating Left / Right pill, vibrant
///     blue 3D `NITRO!` button in the centre, round star power-up slot on
///     the right.
///   * First-launch tutorial overlay — bobby cartoon hand + capsule.
///   * Direct `HapticFeedback.selectionClick/mediumImpact` calls on
///     steering / Nitro / coin pickups.
///
/// Engine: 3-lane sinusoidal curve, 5 obstacle kinds, magnet power-up,
/// nitro w/ screen-shake & speed-lines, parallax trees, smoke bursts,
/// score floaters, game-over.
///
/// Public surface kept byte-identical so the dispatcher
/// (`case 'racing-rush'`) keeps resolving:
///   `class RacingRushGame extends MiniGame`
///   `const RacingRushGame({super.key, required super.callbacks})`
class RacingRushGame extends MiniGame {
  const RacingRushGame({super.key, required super.callbacks});

  @override
  State<RacingRushGame> createState() => _RacingRushState();
}

class _RacingRushState extends MiniGameState<RacingRushGame>
    with TickerProviderStateMixin {
  // ─────────────────────────────────────────────────────────────────
  // Tuning constants
  // ─────────────────────────────────────────────────────────────────

  static const int _laneCount = 3;
  static const double _carWidth = 56;
  static const double _carHeight = 90;
  static const double _baseSpeed = 280; // px/s
  static const double _speedRamp = 6; // px/s² — continuous acceleration
  static const double _maxSpeed = 900; // px/s
  static const double _nitroMultiplier = 1.8;
  static const double _nitroDuration = 1.5; // seconds
  static const int _maxLives = 3;
  static const double _laneSwitchEase = 8.0; // higher = snappier
  static const double _tutorialDuration = 6.0; // auto-dismiss seconds

  // Curvature lane-cross-coupling.
  static const double _curveAmpPx = 22;

  // ─────────────────────────────────────────────────────────────────
  // State
  // ─────────────────────────────────────────────────────────────────

  late final Ticker _ticker;
  late final Ticker _idleTicker;
  final Random _rng = Random();

  DateTime _last = DateTime.now();

  // Idle/anim ticker.
  double _idleTime = 0;

  // Track layout.
  double _screenW = 0;
  double _screenH = 0;
  double _trackScroll = 0; // for stripe animation
  double _curvaturePhase = 0; // accumulates over time for sinusoidal curve

  // Player state.
  int _targetLane = 1; // 0..2
  double _laneX = 0; // smoothed visual x of car center
  double _speed = _baseSpeed;
  double _nitroRemaining = 0;
  int _lives = _maxLives;
  bool _gameOver = false;
  int _steerDirection = 0; // -1 / 0 / +1 — used by painter for tire turn hint

  // Crash polish — when the final hit lands, briefly slow the world
  // (~0.4 s) and run a zoom-punch on the car so the impact feels
  // weighty. After the punch we hand the game-over overlay to the host.
  double _crashPunchT = 0;
  static const double _crashPunchDuration = 0.55;
  static const double _crashSlowMoFactor = 0.30; // 30% real-time for 0.55s

  // Score + stats.
  int _score = 0;
  int _coinsCollected = 0;
  double _distanceMeters = 0;
  bool _scoreReported = false;

  /// Coin-pickup combo. Resets to 0 if no coin is collected within
  /// [_comboWindow] seconds. Drives the multiplier floater + score
  /// multiplier on each pickup.
  int _combo = 0;
  double _comboTimer = 0;
  int _lastComboShown = 0;
  static const double _comboWindow = 1.6;

  /// Cached stats string — only re-emitted to the host when it actually
  /// changes, so the host's `setState` doesn't fire 60×/sec.
  String _lastReportedStats = '';

  // Drag-input state. We accumulate horizontal drag distance and commit
  // one lane shift per [_dragLaneThreshold] pixels (after a 5% screen
  // dead-zone). On release, a velocity-based fling commits any leftover.
  double _dragAccumDx = 0;
  bool _dragActive = false;
  static const double _dragLaneThreshold = 70; // px per lane shift

  // Entities.
  final List<_Sprite> _coins = [];
  final List<_Sprite> _obstacles = [];
  final List<_Opponent> _opponents = [];
  final List<_Magnet> _magnets = [];
  final List<_Tree> _trees = []; // parallax foliage
  final List<_Balloon> _balloons = []; // pastel balloons on grass border

  // VFX.
  final List<_Spark> _sparks = [];
  final List<_Smoke> _smoke = [];
  final List<_Burst> _bursts = [];
  final List<_Floater> _floaters = [];
  final List<_SpeedLine> _speedLines = [];

  // Spawn timers (ms).
  int _coinTimer = 0;
  int _coneTimer = 0;
  int _barrierTimer = 0;
  int _opponentTimer = 0;
  int _magnetTimer = 0;
  int _treeTimer = 0;
  int _balloonTimer = 0;

  // Magnet power-up.
  double _magnetTime = 0;

  // Screen shake (decays over time).
  double _shakeTime = 0;
  double _shakeMagnitude = 0;

  // Nitro button visual scale.
  double _nitroButtonScale = 1.0;

  // Tutorial state.
  bool _showTutorial = true;
  double _tutorialElapsed = 0;
  bool _tutorialDismissed = false;

  // Score milestone pulse (0..1, decays).
  double _milestonePulse = 0;
  int _lastMilestone = 0;

  // ─────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
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

  // ─────────────────────────────────────────────────────────────────
  // Main tick
  // ─────────────────────────────────────────────────────────────────

  void _onIdle(Duration _) {
    _idleTime += 1 / 60;
  }

  void _tick(Duration _) {
    if (!mounted || _screenW == 0) return;
    final now = DateTime.now();
    final dt = (now.difference(_last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = now;
    if (_gameOver) {
      // Even when game is over, allow VFX (smoke + shake) to play out
      // for one frame, then stop the ticker so we don't keep repainting
      // under the host's game-over overlay — that's the "freeze
      // mid-gameplay" feel.
      _animateVfx(dt);
      if (_ticker.isActive) _ticker.stop();
      return;
    }

    // Crash slow-mo — only the world/scroll slows; UI (shake, sparks)
    // keep their real-time cadence so the impact still feels snappy.
    double gameDt = dt;
    if (_crashPunchT > 0) {
      gameDt = dt * _crashSlowMoFactor;
      _crashPunchT = (_crashPunchT - dt).clamp(0.0, _crashPunchDuration);
    }

    setState(() {
      _curvaturePhase += gameDt * 0.6;
      // Nitro decays first so its boost duration is exact.
      if (_nitroRemaining > 0) {
        _nitroRemaining = (_nitroRemaining - dt).clamp(0.0, 99.0);
      }
      final nitroActive = _nitroRemaining > 0;
      // Speed ramps up over time (capped). Nitro multiplies.
      _speed = (_baseSpeed + _distanceMeters * _speedRamp * 0.05)
          .clamp(_baseSpeed, _maxSpeed);
      if (nitroActive) _speed *= _nitroMultiplier;
      _nitroButtonScale = nitroActive ? 1.05 : 1.0;

      _trackScroll += _speed * gameDt;

      // Distance increments with speed.
      _distanceMeters += _speed * gameDt * 0.1;
      if (nitroActive) _score += (10 * gameDt).round();

      // Lane interpolation.
      _smoothLane(gameDt);

      // Spawn cadence (ms accumulators).
      _spawnTickers(gameDt);

      // Magnet power-up effect (pulls coins toward car).
      if (_magnetTime > 0) {
        _magnetTime = (_magnetTime - gameDt).clamp(0.0, 99.0);
        final carCx = _carCenterX();
        final carCy = _carCenterY();
        for (final c in _coins) {
          final dx = carCx - c.x;
          final dy = carCy - c.y;
          final d = sqrt(dx * dx + dy * dy);
          if (d > 0 && d < 220) {
            c.x += dx / d * 240 * gameDt;
            c.y += dy / d * 240 * gameDt;
          }
        }
      }

      // Move entities down the screen (with parallax for trees & balloons).
      _moveEntities(gameDt);

      // Tutorial timing.
      if (_showTutorial) {
        _tutorialElapsed += dt;
        if (_tutorialElapsed >= _tutorialDuration) {
          _showTutorial = false;
        }
      }

      // Milestone pulse decay.
      if (_milestonePulse > 0) {
        _milestonePulse = (_milestonePulse - dt * 4).clamp(0.0, 1.0);
      }
      // Trigger on every 1000 score step.
      final ms = _score ~/ 1000;
      if (ms > _lastMilestone) {
        _lastMilestone = ms;
        _milestonePulse = 1.0;
      }

      // Coin-pickup combo decay — window is in real time so the combo
      // doesn't extend through the slow-mo on a crash.
      if (_comboTimer > 0) {
        _comboTimer = (_comboTimer - dt).clamp(0.0, _comboWindow);
        if (_comboTimer <= 0) {
          _combo = 0;
          _lastComboShown = 0;
        }
      }

      // Collisions.
      _processCollisions();

      // Nitro spark stream.
      if (nitroActive) _emitNitroSparks();

      // Screen shake decay.
      if (_shakeTime > 0) {
        _shakeTime = (_shakeTime - dt).clamp(0.0, 99.0);
      }

      _animateVfx(dt);

      _refreshHud();
    });
  }

  void _animateVfx(double dt) {
    for (final s in _sparks) {
      s.x += s.vx * dt;
      s.y += s.vy * dt;
      s.life -= dt;
    }
    _sparks.removeWhere((s) => s.life <= 0);

    for (final sm in _smoke) {
      sm.r += 28 * dt;
      sm.y -= 14 * dt;
      sm.life -= dt * 0.9;
    }
    _smoke.removeWhere((sm) => sm.life <= 0);

    for (final b in _bursts) {
      b.life -= dt * 2;
      b.r += 70 * dt;
    }
    _bursts.removeWhere((b) => b.life <= 0);

    for (final f in _floaters) {
      f.y -= 38 * dt;
      f.age += dt;
      f.life -= dt;
    }
    _floaters.removeWhere((f) => f.life <= 0);

    for (final sl in _speedLines) {
      sl.y += _speed * 1.4 * dt;
      sl.life -= dt * 0.9;
    }
    _speedLines.removeWhere((sl) => sl.life <= 0);
  }

  // ─────────────────────────────────────────────────────────────────
  // Lane math
  // ─────────────────────────────────────────────────────────────────

  double _laneCenterX(int lane) {
    // 3 lanes: 0.25, 0.5, 0.75 of the track width, plus a sinusoidal
    // curvature offset that swings the whole road ±22 px.
    final roadLeft = _screenW * 0.125;
    final roadRight = _screenW * 0.875;
    final roadWidth = roadRight - roadLeft;
    final laneWidth = roadWidth / _laneCount;
    final curveOffset = sin(_curvaturePhase) * _curveAmpPx;
    return roadLeft +
        laneWidth * (lane + 0.5) +
        curveOffset * (lane - 1) * 0.4;
  }

  double _carCenterX() => _laneX;

  // Car sits clearly above the bottom controls (steering pill + nitro
  // button at bottom: 18, ~70 px tall). 130 px gap keeps the car fully
  // on the road with no overlap.
  double _carCenterY() => _screenH - _carHeight - 130 + _carHeight / 2;

  void _smoothLane(double dt) {
    final targetX = _laneCenterX(_targetLane);
    final ease = (dt * _laneSwitchEase).clamp(0.0, 1.0);
    _laneX += (targetX - _laneX) * ease;
    // Snap when close enough.
    if ((targetX - _laneX).abs() < 0.5) _laneX = targetX;
  }

  void _steer(int delta) {
    if (_gameOver) return;
    final next = (_targetLane + delta).clamp(0, _laneCount - 1);
    if (next != _targetLane) {
      HapticFeedback.selectionClick();
      _steerDirection = delta;
      setState(() => _targetLane = next);
      _dismissTutorial();
      Future.delayed(const Duration(milliseconds: 220), () {
        if (!mounted) return;
        _steerDirection = 0;
      });
    }
  }

  /// Drag-pan handler — accumulates horizontal pixels and commits one
  /// lane shift per [_dragLaneThreshold]. Replacing the old `dx > 30`
  /// per-frame handler which fired on any micro-movement and felt
  /// twitchy / unreliable.
  void _onPanStart(DragStartDetails d) {
    if (_gameOver) return;
    _dragActive = true;
    _dragAccumDx = 0;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_gameOver || !_dragActive) return;
    _dragAccumDx += d.delta.dx;
    // 5% screen dead-zone prevents accidental lane shifts at the start
    // of a gesture when the thumb lands slightly off-center.
    final deadZone = _screenW * 0.05;
    final effective = _dragAccumDx.abs() > deadZone ? _dragAccumDx : 0;
    if (effective >= _dragLaneThreshold) {
      _steer(1);
      _dragAccumDx -= _dragLaneThreshold * effective.sign;
    } else if (effective <= -_dragLaneThreshold) {
      _steer(-1);
      _dragAccumDx -= _dragLaneThreshold * effective.sign;
    }
  }

  void _onPanEnd(DragEndDetails d) {
    _dragActive = false;
    if (_gameOver) return;
    // Velocity-based fling fallback — if the user flicks sideways at
    // release, commit any remaining drag distance (capped to one lane
    // shift so a wild flick can't blow past the road edge).
    final vx = d.velocity.pixelsPerSecond.dx;
    if (vx.abs() > 600) {
      if (vx > 0) {
        _steer(1);
      } else {
        _steer(-1);
      }
    }
    _dragAccumDx = 0;
  }

  /// Tap-zone lane switch. Tap the left half of the screen → left
  /// lane; right half → right lane; middle → no-op. Matches the
  /// Subway Surfers / Crossy Road pattern (whole screen is the
  /// controller). Coexists with the existing drag handler and the
  /// on-screen steering pill.
  void _steerByTap(Offset localPos) {
    if (_gameOver) return;
    final midX = _screenW / 2;
    if (localPos.dx < midX) {
      _steer(-1);
    } else if (localPos.dx > midX) {
      _steer(1);
    }
  }

  void _dismissTutorial() {
    if (_tutorialDismissed) return;
    _tutorialDismissed = true;
    _showTutorial = false;
  }

  // ─────────────────────────────────────────────────────────────────
  // Spawning
  // ─────────────────────────────────────────────────────────────────

  void _spawnTickers(double dt) {
    final ms = (dt * 1000).round();

    _coinTimer += ms;
    if (_coinTimer > 900) {
      _coinTimer = 0;
      _spawnCoinArc();
    }

    _coneTimer += ms;
    if (_coneTimer > 1500) {
      _coneTimer = 0;
      _obstacles.add(_Sprite(
        x: 0,
        y: -30,
        radius: 22,
        kind: _SpriteKind.cone,
      ).._snapToLane(_rng.nextInt(_laneCount)));
    }

    _barrierTimer += ms;
    if (_barrierTimer > 2500) {
      _barrierTimer = 0;
      _obstacles.add(_Sprite(
        x: 0,
        y: -40,
        radius: 30,
        kind: _SpriteKind.barrier,
      ).._snapToLane(_rng.nextInt(_laneCount)));
    }

    _opponentTimer += ms;
    if (_opponentTimer > 4000) {
      _opponentTimer = 0;
      final lane = _rng.nextInt(_laneCount);
      _opponents.add(_Opponent(
        lane: lane,
        y: -50,
        speedFactor: 0.45 + _rng.nextDouble() * 0.25,
        color: _opponentColors[_rng.nextInt(_opponentColors.length)],
      ));
    }

    _magnetTimer += ms;
    if (_magnetTimer > 7000) {
      _magnetTimer = 0;
      _magnets.add(_Magnet(x: 0, y: -40).._snapToLane(_rng.nextInt(_laneCount)));
    }

    _treeTimer += ms;
    if (_treeTimer > 380) {
      _treeTimer = 0;
      _spawnTree();
    }

    _balloonTimer += ms;
    if (_balloonTimer > 1900) {
      _balloonTimer = 0;
      _spawnBalloon();
    }
  }

  void _spawnCoinArc() {
    final lane = _rng.nextInt(_laneCount);
    final count = 3 + _rng.nextInt(3);
    for (var i = 0; i < count; i++) {
      _coins.add(_Sprite(
        x: 0,
        y: -60.0 - i * 56,
        radius: 12,
        kind: _SpriteKind.coin,
      ).._snapToLane(lane));
    }
  }

  void _spawnTree() {
    // Two-layer parallax: closer trees (right side, larger) scroll
    // faster than distant ones (left side, smaller).
    final side = _rng.nextBool();
    final depth = _rng.nextDouble();
    final baseY = -40.0;
    final parallax = 0.35 + depth * 0.55;
    final size = 28 + depth * 38;
    _trees.add(_Tree(
      side: side ? _TreeSide.right : _TreeSide.left,
      y: baseY,
      parallax: parallax,
      size: size,
      hue: 90 + _rng.nextInt(50),
    ));
  }

  void _spawnBalloon() {
    // Balloons only ever spawn on grass borders (not the road).
    final isLeft = _rng.nextBool();
    final side = isLeft ? _BalloonSide.left : _BalloonSide.right;
    final depth = _rng.nextDouble();
    final parallax = 0.30 + depth * 0.40;
    final size = 22 + depth * 12;
    final x = isLeft
        ? (_screenW * 0.02) + _rng.nextDouble() * (_screenW * 0.08)
        : (_screenW * 0.90) + _rng.nextDouble() * (_screenW * 0.08);
    _balloons.add(_Balloon(
      x: x,
      baseY: -40.0,
      parallax: parallax,
      size: size,
      bobSeed: _rng.nextDouble() * 6.28,
      color: _balloonPalette[_rng.nextInt(_balloonPalette.length)],
      side: side,
    ));
  }

  void _moveEntities(double dt) {
    // Coins / obstacles / magnets move at full speed.
    _coins.removeWhere((c) {
      c.y += _speed * dt;
      return c.y > _screenH + 60;
    });
    _obstacles.removeWhere((o) {
      o.y += _speed * dt;
      return o.y > _screenH + 80;
    });
    _magnets.removeWhere((m) {
      m.y += _speed * dt;
      return m.y > _screenH + 60;
    });
    // Opponents: slower than the player (gives the "ahead but slower"
    // racing feel).
    _opponents.removeWhere((o) {
      o.y += _speed * o.speedFactor * dt;
      return o.y > _screenH + 80;
    });
    // Trees: parallax scrolling.
    _trees.removeWhere((t) {
      t.y += _speed * t.parallax * dt;
      return t.y > _screenH + 60;
    });
    // Balloons: parallax scrolling (gentler than trees).
    _balloons.removeWhere((b) {
      b.baseY += _speed * b.parallax * dt;
      return b.baseY > _screenH + 80;
    });
  }

  // ─────────────────────────────────────────────────────────────────
  // Collisions
  // ─────────────────────────────────────────────────────────────────

  Rect get _carRect => Rect.fromCenter(
        center: Offset(_carCenterX(), _carCenterY()),
        width: _carWidth,
        height: _carHeight,
      );

  void _processCollisions() {
    final carRect = _carRect;

    // Coins (circular distance check) — single-pass: iterate by index
    // in reverse so removals don't shift active indices.
    for (int i = _coins.length - 1; i >= 0; i--) {
      final c = _coins[i];
      if ((Offset(c.x, c.y) - carRect.center).distance < c.radius + 30) {
        _onCoinPickup(c);
        _coins.removeAt(i);
      } else if (c.y > _screenH + 500) {
        _coins.removeAt(i);
      }
    }

    // Magnets.
    for (int i = _magnets.length - 1; i >= 0; i--) {
      final m = _magnets[i];
      if ((Offset(m.x, m.y) - carRect.center).distance < 30) {
        _onMagnetPickup(m);
        _magnets.removeAt(i);
      } else if (m.y > _screenH + 500) {
        _magnets.removeAt(i);
      }
    }

    // Obstacles (cones + barriers): AABB.
    for (int i = _obstacles.length - 1; i >= 0; i--) {
      final o = _obstacles[i];
      final oRect = Rect.fromCenter(
        center: Offset(o.x, o.y),
        width: o.radius * 1.6,
        height: o.radius * 1.6,
      );
      if (carRect.overlaps(oRect)) {
        _obstacles.removeAt(i);
        _onObstacleHit(o);
      }
    }

    // Opponent vehicles: AABB.
    for (int i = _opponents.length - 1; i >= 0; i--) {
      final op = _opponents[i];
      final opRect = Rect.fromCenter(
        center: Offset(_laneCenterX(op.lane), op.y),
        width: _carWidth * 0.9,
        height: _carHeight * 0.85,
      );
      if (carRect.overlaps(opRect)) {
        _opponents.removeAt(i);
        _onObstacleHit(_Sprite(
          x: opRect.center.dx,
          y: opRect.center.dy,
          radius: 32,
          kind: _SpriteKind.barrier,
        ));
      }
    }
  }

  void _onCoinPickup(_Sprite c) {
    // Combo decay — pickups must land within the window to chain.
    // Anything past the window resets the combo and the floater.
    if (_comboTimer > 0) {
      _combo += 1;
    } else {
      _combo = 1;
    }
    _comboTimer = _comboWindow;
    final mult = _comboMultiplier(_combo);
    _score += 10 * mult;
    _coinsCollected += 1;
    _bursts.add(_Burst(x: c.x, y: c.y, color: const Color(0xFFFFC529)));
    // Small "+N" floater always.
    _floaters.add(_Floater(
      x: c.x,
      y: c.y,
      text: '+${10 * mult}',
      color: const Color(0xFFFFC529),
    ));
    // Big combo banner at thresholds (3, 5, 8, 12, 16, ...).
    if (_combo >= 3 && _combo != _lastComboShown) {
      _lastComboShown = _combo;
      _floaters.add(_Floater(
        x: _screenW / 2,
        y: _screenH * 0.28,
        text: 'x$_combo COMBO!',
        color: const Color(0xFFFB923C),
      ));
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.mediumImpact();
    }
    c.y = _screenH + 1000; // remove
  }

  /// Score multiplier curve for combo chain length. Caps at 5x so the
  /// game stays balanced — anything past that is mostly visual.
  int _comboMultiplier(int combo) {
    if (combo >= 12) return 5;
    if (combo >= 8) return 4;
    if (combo >= 5) return 3;
    if (combo >= 3) return 2;
    return 1;
  }

  void _onMagnetPickup(_Magnet m) {
    _magnetTime = 4.0;
    _floaters.add(_Floater(
      x: m.x,
      y: m.y,
      text: 'MAGNET!',
      color: const Color(0xFFA073FF),
    ));
    _bursts.add(_Burst(x: m.x, y: m.y, color: const Color(0xFFA073FF)));
    HapticFeedback.mediumImpact();
    m.y = _screenH + 1000;
  }

  void _onObstacleHit(_Sprite o) {
    _lives -= 1;
    // Reset combo — a hit always breaks the chain.
    _combo = 0;
    _comboTimer = 0;
    _lastComboShown = 0;
    _floaters.add(_Floater(
      x: o.x,
      y: o.y,
      text: _lives > 0 ? 'HIT!' : 'WRECK!',
      color: const Color(0xFFEF4444),
    ));
    _bursts.add(_Burst(x: o.x, y: o.y, color: const Color(0xFFEF4444)));
    _spawnSmokeBurst(o.x, o.y);
    _spawnCrashSparks(o.x, o.y);
    _shake(0.55, 22);
    HapticFeedback.heavyImpact();
    o.y = _screenH + 1000;
    if (_lives <= 0) {
      _gameOver = true;
      // Brief slow-mo + zoom-punch so the impact lands with weight
      // before the host's game-over overlay takes over.
      _crashPunchT = _crashPunchDuration;
      reportGameOver();
    }
  }

  /// Spawns a denser spark shower + brief secondary burst at the impact
  /// point. Distinct from [_spawnSmokeBurst] which is darker/grey —
  /// sparks are bright orange/yellow and pop visually on impact.
  void _spawnCrashSparks(double x, double y) {
    const colors = <Color>[
      Color(0xFFFACC15),
      Color(0xFFFB923C),
      Color(0xFFEF4444),
      Color(0xFFFFFFFF),
    ];
    for (var i = 0; i < 22; i++) {
      final angle = _rng.nextDouble() * 2 * pi;
      final speed = 120 + _rng.nextDouble() * 200;
      _sparks.add(_Spark(
        x: x,
        y: y,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed,
        life: 0.6 + _rng.nextDouble() * 0.4,
        color: colors[_rng.nextInt(colors.length)],
      ));
    }
  }

  void _spawnSmokeBurst(double x, double y) {
    for (var i = 0; i < 14; i++) {
      final angle = (i / 14) * 2 * pi + _rng.nextDouble() * 0.4;
      final speed = 40 + _rng.nextDouble() * 80;
      _smoke.add(_Smoke(
        x: x + cos(angle) * 10,
        y: y + sin(angle) * 10,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed * 0.4,
        r: 6 + _rng.nextDouble() * 8,
        life: 1.0,
      ));
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // Nitro
  // ─────────────────────────────────────────────────────────────────

  void _toggleNitro(bool pressed) {
    if (_gameOver) return;
    setState(() {
      if (pressed) {
        _nitroRemaining = _nitroDuration;
        _floaters.add(_Floater(
          x: _screenW / 2,
          y: _screenH * 0.32,
          text: 'BOOST!',
          color: const Color(0xFF4E6CF5),
          fontSize: 32,
        ));
        HapticFeedback.mediumImpact();
      } else {
        _nitroRemaining = 0;
      }
    });
    _dismissTutorial();
  }

  void _emitNitroSparks() {
    for (var i = 0; i < 3; i++) {
      _sparks.add(_Spark(
        x: _carCenterX() + (_rng.nextDouble() - 0.5) * _carWidth * 0.6,
        y: _carCenterY() + _carHeight * 0.4,
        vx: (_rng.nextDouble() - 0.5) * 60,
        vy: 220 + _rng.nextDouble() * 90,
        life: 0.5,
      ));
    }
    // Speed lines on screen edges.
    if (_rng.nextDouble() < 0.55) {
      _speedLines.add(_SpeedLine(
        x: _rng.nextBool() ? _screenW * 0.08 : _screenW * 0.92,
        y: -20,
        length: 40 + _rng.nextDouble() * 50,
        life: 0.7,
      ));
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // Shake + HUD refresh
  // ─────────────────────────────────────────────────────────────────

  void _shake(double duration, double magnitude) {
    _shakeTime = duration;
    _shakeMagnitude = magnitude;
  }

  void _refreshHud() {
    if (_scoreReported && _score % 50 != 0) return;
    reportScore(_score);
    _scoreReported = _score % 50 == 0;
    final stats =
        '${_distanceMeters.round()} m  •  Coins $_coinsCollected  •  Lives $_lives/$_maxLives';
    if (stats != _lastReportedStats) {
      _lastReportedStats = stats;
      reportStats(stats);
    }
  }

  void _refreshStats() => _refreshHud();

  // ─────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        _screenW = c.maxWidth;
        _screenH = c.maxHeight;
        if (_laneX == 0) _laneX = _laneCenterX(_targetLane);
        return Stack(
          children: [
            // Track + entities painter (screen-shake via Transform).
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _steerByTap(d.localPosition),
                onHorizontalDragStart: _onPanStart,
                onHorizontalDragUpdate: _onPanUpdate,
                onHorizontalDragEnd: _onPanEnd,
                child: Transform.translate(
                  offset: _shakeTime > 0
                      ? Offset(
                          (_rng.nextDouble() - 0.5) * _shakeMagnitude,
                          (_rng.nextDouble() - 0.5) * _shakeMagnitude,
                        )
                      : Offset.zero,
                  child: Transform.scale(
                    // Crash zoom-punch — peaks at ~6% scale-up then
                    // springs back. Layered inside the shake so the
                    // world jolts outward as well as shakes.
                    scale: _crashPunchT > 0
                        ? 1.0 +
                            0.06 *
                                (1.0 -
                                    _crashPunchT / _crashPunchDuration)
                        : 1.0,
                    child: CustomPaint(
                    painter: _TrackPainter(
                      scroll: _trackScroll,
                      curvaturePhase: _curvaturePhase,
                      idleTime: _idleTime,
                      carX: _laneX,
                      carY: _carCenterY() - _carHeight / 2,
                      carW: _carWidth,
                      carH: _carHeight,
                      coins: _coins,
                      obstacles: _obstacles,
                      opponents: _opponents,
                      magnets: _magnets,
                      trees: _trees,
                      balloons: _balloons,
                      sparks: _sparks,
                      smoke: _smoke,
                      bursts: _bursts,
                      floaters: _floaters,
                      speedLines: _speedLines,
                      nitro: _nitroRemaining > 0,
                      steerDirection: _steerDirection,
                    ),
                  ),
                ),
              ),
              ),
            ),
            // Bottom controls.
            if (!_gameOver)
              Positioned(
                left: 0,
                right: 0,
                bottom: 18,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Steering pill (left).
                      _SteeringPill(
                        onLeft: () => _steer(-1),
                        onRight: () => _steer(1),
                      ),
                      // Nitro button (centre).
                      _NitroButton(
                        active: _nitroRemaining > 0,
                        scale: _nitroButtonScale,
                        onTapDown: () => _toggleNitro(true),
                        onTapUp: () => _toggleNitro(false),
                      ),
                      // Power-up slot (right).
                      const _PowerSlot(active: false),
                    ],
                  ),
                ),
              ),
            // Tutorial overlay (bottom-centre).
            if (_showTutorial && !_gameOver)
              Positioned(
                left: 0,
                right: 0,
                bottom: 100,
                child: TutorialOverlay(
                  idleTime: _idleTime,
                  progress: (_tutorialElapsed / _tutorialDuration).clamp(0.0, 1.0),
                  message: 'Steer & Boost to Race!',
                ),
              ),
            // Pause + game-over overlays are rendered by the host.
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Sprite + entity records
// ─────────────────────────────────────────────────────────────────

enum _SpriteKind { coin, cone, barrier }

class _Sprite {
  _Sprite({
    required this.x,
    required this.y,
    required this.radius,
    required this.kind,
  });
  double x;
  double y;
  double radius;
  _SpriteKind kind;

  /// Convenience: snap x to the lane center for a given lane index.
  void _snapToLane(int lane) {
    // The painter reads `x` as a lane index when `x == 0`. We use a
    // negative lane signal to mark "snap pending" so the painter
    // resolves it during paint using the same curvature phase.
    _pendingLane = lane;
  }

  /// Internal — resolved each paint frame so curvature is honored.
  int _pendingLane = -1;
}

class _Opponent {
  _Opponent({
    required this.lane,
    required this.y,
    required this.speedFactor,
    required this.color,
  });
  int lane;
  double y;
  double speedFactor;
  Color color;
}

class _Magnet {
  _Magnet({required this.x, required this.y});
  double x;
  double y;
  int _pendingLane = -1;
  void _snapToLane(int lane) {
    _pendingLane = lane;
  }
}

enum _TreeSide { left, right }

class _Tree {
  _Tree({
    required this.side,
    required this.y,
    required this.parallax,
    required this.size,
    required this.hue,
  });
  _TreeSide side;
  double y;
  double parallax;
  double size;
  int hue;
}

enum _BalloonSide { left, right }

class _Balloon {
  _Balloon({
    required this.x,
    required this.baseY,
    required this.parallax,
    required this.size,
    required this.bobSeed,
    required this.color,
    required this.side,
  });
  double x;
  double baseY;
  double parallax;
  double size;
  double bobSeed;
  Color color;
  _BalloonSide side;
}

class _Spark {
  _Spark({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.life,
    this.color = const Color(0xFFFFC529),
  });
  double x;
  double y;
  double vx;
  double vy;
  double life;
  Color color;
}

class _Smoke {
  _Smoke({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.r,
    required this.life,
  });
  double x;
  double y;
  double vx;
  double vy;
  double r;
  double life;
}

class _Burst {
  _Burst({required this.x, required this.y, required this.color})
      : life = 1.0,
        r = 0;
  double x;
  double y;
  double r;
  double life;
  Color color;
}

class _Floater {
  _Floater({
    required this.x,
    required this.y,
    required this.text,
    required this.color,
    this.fontSize = 18,
  })  : life = 0.7,
        age = 0;
  double x;
  double y;
  String text;
  Color color;
  double fontSize;
  double life;
  double age;
}

class _SpeedLine {
  _SpeedLine({
    required this.x,
    required this.y,
    required this.length,
    required this.life,
  });
  double x;
  double y;
  double length;
  double life;
}

const List<Color> _opponentColors = [
  Color(0xFF22D3EE),
  Color(0xFF34D399),
  Color(0xFFFBBF24),
  Color(0xFFF472B6),
];

/// Pastel balloon palette.
const List<Color> _balloonPalette = [
  Color(0xFFFCA5A5), // pink
  Color(0xFFBFDBFE), // sky
  Color(0xFFFDE68A), // yellow
  Color(0xFFDDD6FE), // lavender
];

// ─────────────────────────────────────────────────────────────────
// Bottom controls (steering pill + nitro + power-up slot).
// Top HUD is provided by the host `GameContainerScreen`.
// ─────────────────────────────────────────────────────────────────

class _SteeringPill extends StatelessWidget {
  const _SteeringPill({required this.onLeft, required this.onRight});
  final VoidCallback onLeft;
  final VoidCallback onRight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaleTapButton(
            onTap: onLeft,
            borderRadius: BorderRadius.circular(999),
            padding: const EdgeInsets.all(10),
            color: Colors.white.withValues(alpha: 0.20),
            semanticsLabel: 'Steer left',
            child: const Icon(
              Icons.chevron_left_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 4),
          const Text(
            'L\nR',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
              height: 1.05,
            ),
          ),
          const SizedBox(width: 4),
          ScaleTapButton(
            onTap: onRight,
            borderRadius: BorderRadius.circular(999),
            padding: const EdgeInsets.all(10),
            color: Colors.white.withValues(alpha: 0.20),
            semanticsLabel: 'Steer right',
            child: const Icon(
              Icons.chevron_right_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
        ],
      ),
    );
  }
}

class _NitroButton extends StatelessWidget {
  const _NitroButton({
    required this.active,
    required this.scale,
    required this.onTapDown,
    required this.onTapUp,
  });
  final bool active;
  final double scale;
  final VoidCallback onTapDown;
  final VoidCallback onTapUp;

  @override
  Widget build(BuildContext context) {
    final body = Container(
      width: 144,
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF60A5FA), Color(0xFF1E40AF)],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: active
                ? const Color(0x605E8DFF)
                : const Color(0x502563EB),
            blurRadius: active ? 30 : 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Bottom darkening strip (3D bottom shadow).
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  height: 22,
                  color: const Color(0x14000000),
                ),
              ),
            ),
          ),
          // Top highlight.
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  height: 24,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x55FFFFFF), Color(0x00FFFFFF)],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Label.
          Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.bolt_rounded,
                    color: Colors.white, size: 22),
                SizedBox(width: 6),
                Text(
                  'NITRO!',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                    fontSize: 15,
                    shadows: [
                      Shadow(blurRadius: 6, color: Color(0x66000000)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return GestureDetector(
      onTapDown: (_) => onTapDown(),
      onTapUp: (_) => onTapUp(),
      onTapCancel: onTapUp,
      child: AnimatedScale(
        scale: scale,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: body,
      ),
    );
  }
}

class _PowerSlot extends StatelessWidget {
  const _PowerSlot({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.star_rounded,
            size: 30,
            color: active ? const Color(0xFFFACC15) : const Color(0xFFFDE68A),
          ),
          if (active)
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0x66FACC15),
                  width: 3,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Tutorial overlay
// ─────────────────────────────────────────────────────────────────
// Painter
// ─────────────────────────────────────────────────────────────────

class _TrackPainter extends CustomPainter {
  _TrackPainter({
    required this.scroll,
    required this.curvaturePhase,
    required this.idleTime,
    required this.carX,
    required this.carY,
    required this.carW,
    required this.carH,
    required this.coins,
    required this.obstacles,
    required this.opponents,
    required this.magnets,
    required this.trees,
    required this.balloons,
    required this.sparks,
    required this.smoke,
    required this.bursts,
    required this.floaters,
    required this.speedLines,
    required this.nitro,
    required this.steerDirection,
  });

  final double scroll;
  final double curvaturePhase;
  final double idleTime;
  final double carX;
  final double carY;
  final double carW;
  final double carH;
  final List<_Sprite> coins;
  final List<_Sprite> obstacles;
  final List<_Opponent> opponents;
  final List<_Magnet> magnets;
  final List<_Tree> trees;
  final List<_Balloon> balloons;
  final List<_Spark> sparks;
  final List<_Smoke> smoke;
  final List<_Burst> bursts;
  final List<_Floater> floaters;
  final List<_SpeedLine> speedLines;
  final bool nitro;
  final int steerDirection;

  /// Resolves a sprite's lane index into a paint-time x (centered in
  /// the road with curvature offset).
  double _resolveLaneX(int lane, double screenW) {
    final roadLeft = screenW * 0.125;
    final roadRight = screenW * 0.875;
    final roadWidth = roadRight - roadLeft;
    final laneWidth = roadWidth / 3;
    final curveOffset = sin(curvaturePhase) * 22;
    return roadLeft +
        laneWidth * (lane + 0.5) +
        curveOffset * (lane - 1) * 0.4;
  }

  void _resolveSpriteLane(_Sprite s, double screenW) {
    if (s._pendingLane >= 0) {
      s.x = _resolveLaneX(s._pendingLane, screenW);
      s._pendingLane = -1;
    }
  }

  void _resolveMagnetLane(_Magnet m, double screenW) {
    if (m._pendingLane >= 0) {
      m.x = _resolveLaneX(m._pendingLane, screenW);
      m._pendingLane = -1;
    }
  }

  double _curveOffsetMid() => sin(curvaturePhase) * 22 * 0.4; // for centerline-based elements

  double _curveOffsetEdge() => sin(curvaturePhase) * 22; // full amplitude (for outer strips)

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Resolve lanes for sprites that haven't been positioned yet.
    for (final s in coins) {
      _resolveSpriteLane(s, w);
    }
    for (final s in obstacles) {
      _resolveSpriteLane(s, w);
    }
    for (final m in magnets) {
      _resolveMagnetLane(m, w);
    }

    // ── 1. Bright pastel grass + radial daylight highlight. ──────
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF86EFAC), Color(0xFF4ADE80)],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );
    // Soft daylight highlight top-center.
    canvas.drawCircle(
      Offset(w / 2, h * 0.10),
      w * 0.55,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.35),
            Colors.white.withValues(alpha: 0.0),
          ],
        ).createShader(
          Rect.fromCircle(
            center: Offset(w / 2, h * 0.10),
            radius: w * 0.55,
          ),
        ),
    );

    // Side grass mown stripes (subtle texture).
    for (var side = 0; side < 2; side++) {
      final baseX = side == 0 ? 0.0 : w * 0.885;
      final stripW = w * 0.115;
      for (var i = 0; i < 4; i++) {
        canvas.drawRect(
          Rect.fromLTWH(baseX, i * (h / 4), stripW, h / 8),
          Paint()
            ..color = (i.isEven
                ? const Color(0xFF4ADE80)
                : const Color(0xFF22C55E))
                .withValues(alpha: 0.4),
        );
      }
    }

    // ── Camera roll on curves (canvas rotates ±2°). ──────────────
    final rollDeg = _curveOffsetEdge() / 11; // map [-22,22] → [-2°,2°]
    final rollRad = rollDeg * pi / 180;
    canvas.save();
    canvas.translate(w / 2, h / 2);
    canvas.rotate(rollRad);
    canvas.translate(-w / 2, -h / 2);

    // ── 2. Curved red/white rumble strips. ──────────────────────
    final leftCurve = _curveOffsetMid();
    _drawRumbleStrip(canvas, 0, w * 0.115, true, h, leftCurve, true);
    _drawRumbleStrip(canvas, w * 0.885, w * 0.115, false, h, leftCurve, false);

    // ── 3. Asphalt. ─────────────────────────────────────────────
    final asphalt = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF3F4754), Color(0xFF2C2F36)],
      ).createShader(Rect.fromLTWH(w * 0.115, 0, w * 0.77, h));
    canvas.drawRect(Rect.fromLTWH(w * 0.115, 0, w * 0.77, h), asphalt);

    // Subtle road highlight gradient (lighter in the middle).
    canvas.drawRect(
      Rect.fromLTWH(w * 0.115, 0, w * 0.77, h),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0x33000000)],
        ).createShader(Rect.fromLTWH(w * 0.115, 0, w * 0.77, h)),
    );

    // ── 4. Lane separators (white dashed stripes, 2 of them). ──
    final dashPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final dashH = 28.0;
    final dashGap = 22.0;
    final period = dashH + dashGap;
    final roadLeft = w * 0.115;
    final roadRight = w * 0.885;
    for (final t in [roadLeft + (roadRight - roadLeft) / 3,
                     roadLeft + (roadRight - roadLeft) * 2 / 3]) {
      // Apply curvature offset to lane separator x.
      final co = _curveOffsetMid();
      var y = -((scroll) % period);
      while (y < h) {
        canvas.drawLine(
            Offset(t - 2 + co, y),
            Offset(t - 2 + co, y + dashH),
            dashPaint);
        y += period;
      }
    }

    // ── 5. Parallax trees. ─────────────────────────────────────
    for (final tree in trees) {
      _drawTree(canvas, tree, w, h);
    }

    // ── 5b. Pastel balloons on the grass borders. ──────────────
    for (final b in balloons) {
      _drawBalloon(canvas, b, h);
    }

    // ── 6. Entities (coins, obstacles, opponents, magnets). ────
    for (final c in coins) {
      _drawCoin(canvas, c.x, c.y, c.radius);
    }
    for (final o in obstacles) {
      if (o.kind == _SpriteKind.cone) {
        _drawCone(canvas, o.x, o.y, o.radius);
      } else {
        _drawBarrier(canvas, o.x, o.y, o.radius);
      }
    }
    for (final op in opponents) {
      _drawOpponent(canvas, _resolveLaneX(op.lane, w), op.y, op.color);
    }
    for (final m in magnets) {
      _drawMagnet(canvas, m.x, m.y);
    }

    // ── 7. Car (player). ───────────────────────────────────────
    _drawCar(canvas, carX, carY, carW, carH);

    // ── 8. Nitro overlays (sparks + speed lines). ──────────────
    for (final s in sparks) {
      final alpha = (s.life / 0.5).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(s.x, s.y),
        3 * alpha,
        Paint()..color = s.color.withValues(alpha: alpha),
      );
    }
    for (final sl in speedLines) {
      final alpha = (sl.life / 0.7).clamp(0.0, 1.0);
      canvas.drawLine(
        Offset(sl.x, sl.y),
        Offset(sl.x, sl.y + sl.length),
        Paint()
          ..color = Colors.white.withValues(alpha: alpha * 0.6)
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round,
      );
    }

    // ── 9. Pickup bursts. ──────────────────────────────────────
    for (final b in bursts) {
      final alpha = b.life.clamp(0.0, 1.0);
      for (var i = 0; i < 8; i++) {
        final angle = i * (pi / 4);
        canvas.drawLine(
          Offset(b.x, b.y),
          Offset(
            b.x + cos(angle) * (10 + b.r),
            b.y + sin(angle) * (10 + b.r),
          ),
          Paint()
            ..color = b.color.withValues(alpha: alpha)
            ..strokeWidth = 3,
        );
      }
      canvas.drawCircle(
        Offset(b.x, b.y),
        6 + b.r,
        Paint()..color = b.color.withValues(alpha: alpha * 0.5),
      );
    }

    // ── 10. Smoke (post-crash). ────────────────────────────────
    for (final sm in smoke) {
      final alpha = sm.life.clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(sm.x, sm.y),
        sm.r,
        Paint()..color = Color(0xFF6B7280).withValues(alpha: alpha * 0.7),
      );
    }

    // End camera roll.
    canvas.restore();

    // ── 11. Floating text (kept above roll so it stays readable). ──
    for (final f in floaters) {
      final alpha = (f.life / 0.7).clamp(0.0, 1.0);
      // Scale-up bounce on first 200 ms then settle.
      final scale = f.age < 0.2
          ? 0.5 + 1.2 * (f.age / 0.2) // 0.5 → 1.7
          : (f.age < 0.35
              ? 1.7 - 0.7 * ((f.age - 0.2) / 0.15) // 1.7 → 1.0
              : 1.0);
      final tp = TextPainter(
        text: TextSpan(
          text: f.text,
          style: TextStyle(
            color: f.color.withValues(alpha: alpha),
            fontSize: f.fontSize,
            fontWeight: FontWeight.w900,
            shadows: const [
              Shadow(blurRadius: 6, color: Colors.black87),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate(f.x, f.y);
      canvas.scale(scale);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────

  void _drawRumbleStrip(
    Canvas canvas,
    double x,
    double width,
    bool leftSide,
    double h,
    double xOffset,
    bool isLeftStrip,
  ) {
    final segH = 14.0;
    final totalStripH = h + segH; // overflow to avoid gap at bottom
    final offsetY = -((scroll * 1.05) % segH);
    // Apply horizontal curvature: shift each segment by an offset that
    // tapers (full amplitude at the outer edge, half at the inner).
    final segOffset = (isLeftStrip ? -1 : 1) * xOffset;
    for (var y = offsetY; y < totalStripH; y += segH) {
      final isRed = ((y ~/ segH) % 2) == 0;
      canvas.drawRect(
        Rect.fromLTWH(x + segOffset, y, width, segH),
        Paint()..color = isRed ? const Color(0xFFEF4444) : Colors.white,
      );
    }
  }

  void _drawTree(Canvas canvas, _Tree t, double w, double h) {
    final cx = t.side == _TreeSide.left
        ? w * 0.06 + (_rngStub(t.size.round()) * w * 0.04)
        : w * 0.94 + (_rngStub(t.size.round() + 7) * w * 0.04) -
            w * 0.04;
    final baseY = t.y + t.size;
    final trunk = Paint()..color = const Color(0xFF92400E);
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(cx, baseY + t.size * 0.12),
        width: t.size * 0.18,
        height: t.size * 0.25,
      ),
      trunk,
    );
    final canopy = Paint()
      ..color = HSLColor.fromAHSL(
        1, t.hue.toDouble(), 0.55, 0.45,
      ).toColor();
    canvas.drawCircle(Offset(cx, baseY - t.size * 0.2), t.size * 0.5, canopy);
    canvas.drawCircle(
      Offset(cx - t.size * 0.25, baseY + t.size * 0.05),
      t.size * 0.4,
      canopy,
    );
    canvas.drawCircle(
      Offset(cx + t.size * 0.25, baseY + t.size * 0.05),
      t.size * 0.4,
      canopy,
    );
    // Highlight.
    final highlight = Paint()..color = Colors.white.withValues(alpha: 0.20);
    canvas.drawCircle(
      Offset(cx - t.size * 0.18, baseY - t.size * 0.3),
      t.size * 0.16,
      highlight,
    );
  }

  void _drawBalloon(Canvas canvas, _Balloon b, double h) {
    final bob = sin(idleTime * 1.5 + b.bobSeed) * 3;
    final cy = b.baseY + b.size + bob;
    final radius = b.size * 0.55;

    // String.
    canvas.drawLine(
      Offset(b.x, cy),
      Offset(b.x, cy + b.size * 1.6),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..strokeWidth = 1.2,
    );

    // Knot (small triangle).
    final knotPath = Path()
      ..moveTo(b.x - 4, cy + radius * 1.05)
      ..lineTo(b.x + 4, cy + radius * 1.05)
      ..lineTo(b.x, cy + radius * 1.4)
      ..close();
    canvas.drawPath(knotPath, Paint()..color = b.color);

    // Balloon body with radial gradient + outline.
    final bodyRect = Rect.fromCircle(center: Offset(b.x, cy), radius: radius);
    canvas.drawCircle(
      Offset(b.x, cy),
      radius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          radius: 0.95,
          colors: [Colors.white, b.color],
        ).createShader(bodyRect),
    );
    canvas.drawCircle(
      Offset(b.x, cy),
      radius,
      Paint()
        ..color = const Color(0xFF1F2937)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    // Highlight shine.
    canvas.drawCircle(
      Offset(b.x - radius * 0.30, cy - radius * 0.40),
      radius * 0.18,
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );
  }

  /// Cheap deterministic 0..1 from a seed (avoid pulling Random into
  /// the painter so the tree positions stay stable per-frame).
  double _rngStub(int seed) =>
      ((seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff;

  void _drawCoin(Canvas canvas, double x, double y, double r) {
    canvas.drawCircle(Offset(x, y), r, Paint()..color = const Color(0xFFB45309));
    canvas.drawCircle(
        Offset(x, y), r * 0.92, Paint()..color = const Color(0xFFFFC529));
    canvas.drawCircle(
        Offset(x, y), r * 0.65, Paint()..color = const Color(0xFFFFE066));
    final dollar = TextPainter(
      text: const TextSpan(
        text: '\$',
        style: TextStyle(
          color: Color(0xFFB45309),
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    dollar.paint(canvas, Offset(x - 4, y - 6));
  }

  void _drawCone(Canvas canvas, double x, double y, double r) {
    final conePath = Path()
      ..moveTo(x, y - r)
      ..lineTo(x + r * 0.8, y + r)
      ..lineTo(x - r * 0.8, y + r)
      ..close();
    canvas.drawPath(conePath, Paint()..color = const Color(0xFFFF6B35));
    final stripe = Paint()
      ..color = Colors.white
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(x - r * 0.5, y),
      Offset(x + r * 0.5, y),
      stripe,
    );
    canvas.drawPath(
      conePath,
      Paint()
        ..color = Colors.black87
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  void _drawBarrier(Canvas canvas, double x, double y, double r) {
    final rect = Rect.fromCenter(
      center: Offset(x, y),
      width: r * 2,
      height: r * 1.2,
    );
    canvas.drawRect(rect, Paint()..color = const Color(0xFFEF4444));
    final stripe = Paint()..color = Colors.white;
    for (var i = -2; i < 4; i++) {
      canvas.drawLine(
        Offset(rect.left + i * 14.0, rect.top),
        Offset(rect.left + i * 14.0 + 14, rect.bottom),
        stripe,
      );
    }
    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.black87
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  void _drawOpponent(Canvas canvas, double x, double y, Color color) {
    final rect = Rect.fromCenter(
      center: Offset(x, y),
      width: carW * 0.9,
      height: carH * 0.85,
    );
    // Shadow.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.translate(2, 4),
        const Radius.circular(12),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );
    // Body — bright livery with darker underbelly.
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(12)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color, Color.lerp(color, Colors.black, 0.55)!],
        ).createShader(rect),
    );
    // Glossy highlight strip across the bonnet.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          rect.left + 4,
          rect.top + 6,
          rect.width - 8,
          rect.height * 0.10,
        ),
        const Radius.circular(8),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.35),
    );
    // Race number badge on the roof.
    final roofRect = Rect.fromCenter(
      center: rect.center.translate(0, -carH * 0.05),
      width: rect.width * 0.7,
      height: rect.height * 0.45,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(roofRect, const Radius.circular(8)),
      Paint()..color = Colors.white.withValues(alpha: 0.92),
    );
    // Roof number band.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          roofRect.left,
          roofRect.top + roofRect.height * 0.5,
          roofRect.width,
          roofRect.height * 0.18,
        ),
        const Radius.circular(4),
      ),
      Paint()..color = color,
    );
    // Windshield (front = bottom of rect since car points down).
    final windRect = Rect.fromCenter(
      center: Offset(roofRect.center.dx, rect.top + rect.height * 0.55),
      width: rect.width * 0.65,
      height: rect.height * 0.20,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(windRect, const Radius.circular(5)),
      Paint()..color = const Color(0xFF1A1A2E),
    );
    // Rear window (top of rect).
    final rearRect = Rect.fromCenter(
      center: Offset(roofRect.center.dx, rect.top + rect.height * 0.20),
      width: rect.width * 0.55,
      height: rect.height * 0.14,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rearRect, const Radius.circular(4)),
      Paint()..color = const Color(0xFF263238),
    );
    // Taillights (top = back of opponent).
    final taillight = Paint()..color = const Color(0xFFEF4444);
    for (final dx in [-rect.width * 0.30, rect.width * 0.30]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(rect.center.dx + dx, rect.top + 4),
            width: rect.width * 0.16,
            height: 6,
          ),
          const Radius.circular(2),
        ),
        taillight,
      );
    }
    // Headlights (bottom = front).
    final headlight = Paint()..color = const Color(0xFFFFF59D);
    for (final dx in [-rect.width * 0.22, rect.width * 0.22]) {
      canvas.drawCircle(
        Offset(rect.center.dx + dx, rect.bottom - 4),
        3,
        headlight,
      );
    }
  }

  void _drawMagnet(Canvas canvas, double x, double y) {
    canvas.drawCircle(
      Offset(x, y),
      18,
      Paint()..color = const Color(0xFFA073FF).withValues(alpha: 0.4),
    );
    final path = Path()
      ..moveTo(x - 12, y - 8)
      ..lineTo(x - 12, y + 4)
      ..lineTo(x - 6, y + 4)
      ..lineTo(x - 6, y - 2)
      ..lineTo(x + 6, y - 2)
      ..lineTo(x + 6, y + 4)
      ..lineTo(x + 12, y + 4)
      ..lineTo(x + 12, y - 8)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFA073FF));
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  void _drawCar(Canvas canvas, double x, double y, double w, double h) {
    final carRect = Rect.fromLTWH(x - w / 2, y, w, h);

    // Shadow.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        carRect.translate(2, 4),
        const Radius.circular(14),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );

    // Nitro flame trail (behind the car) — bigger, more dramatic.
    if (nitro) {
      for (var i = 0; i < 8; i++) {
        final flameY = carRect.bottom + i * 7;
        final flameW = carRect.width * (0.85 - i * 0.09);
        final t = i / 8;
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(carRect.center.dx, flameY + 4),
            width: flameW,
            height: 18 - i * 1.5,
          ),
          Paint()
            ..color = Color.lerp(
              const Color(0xFFFB923C),
              Colors.transparent,
              t,
            )!,
        );
      }
      // Inner blue core for hotter nitro.
      for (var i = 0; i < 4; i++) {
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(carRect.center.dx, carRect.bottom + i * 6),
            width: carRect.width * (0.55 - i * 0.10),
            height: 10 - i * 1.5,
          ),
          Paint()
            ..color = const Color(0xFF38BDF8).withValues(alpha: (1 - i / 4) * 0.85),
        );
      }
    }

    // Body (glossy red gradient).
    canvas.drawRRect(
      RRect.fromRectAndRadius(carRect, const Radius.circular(14)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFF3B30), Color(0xFF8B0000)],
        ).createShader(carRect),
    );
    // Hood scoop (sporty detail in the front).
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(carRect.center.dx, carRect.top + carRect.height * 0.20),
          width: carRect.width * 0.30,
          height: carRect.height * 0.12,
        ),
        const Radius.circular(4),
      ),
      Paint()..color = const Color(0xFF7F1D1D),
    );
    // Hood vent (small slit).
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(carRect.center.dx, carRect.top + carRect.height * 0.20),
        width: carRect.width * 0.18,
        height: 2,
      ),
      Paint()..color = Colors.black,
    );
    // Glossy highlight strip.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          carRect.left + 4,
          carRect.top + 6,
          carRect.width - 8,
          carRect.height * 0.18,
        ),
        const Radius.circular(10),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.35),
    );
    // White roof.
    final roofRect = Rect.fromCenter(
      center: carRect.center.translate(0, -carH * 0.05),
      width: carW * 0.7,
      height: carH * 0.45,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(roofRect, const Radius.circular(8)),
      Paint()..color = Colors.white,
    );
    // Windshield (front-facing — at the bottom of the rect since car points
    // downward = away from camera).
    final windRect = Rect.fromCenter(
      center: Offset(roofRect.center.dx, roofRect.bottom - roofRect.height * 0.30),
      width: roofRect.width * 0.85,
      height: roofRect.height * 0.5,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(windRect, const Radius.circular(5)),
      Paint()..color = const Color(0xFF1A1A2E),
    );
    // Windshield highlight.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          windRect.left + 4,
          windRect.top + 2,
          windRect.width * 0.4,
          windRect.height * 0.4,
        ),
        const Radius.circular(3),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.4),
    );
    // Rear window (towards the back of the car).
    final rearRect = Rect.fromCenter(
      center: Offset(roofRect.center.dx, roofRect.top + roofRect.height * 0.25),
      width: roofRect.width * 0.78,
      height: roofRect.height * 0.35,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rearRect, const Radius.circular(4)),
      Paint()..color = const Color(0xFF263238),
    );
    // Headlights (front = bottom of rect since car drives "down" the screen).
    final lightPaint = Paint()..color = const Color(0xFFFFE66D);
    final glowPaint = Paint()
      ..color = const Color(0xFFFFE66D).withValues(alpha: 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    for (final dx in [-carW * 0.26, carW * 0.26]) {
      canvas.drawCircle(
        Offset(carRect.center.dx + dx, carRect.bottom - 5),
        4,
        glowPaint,
      );
      canvas.drawCircle(
        Offset(carRect.center.dx + dx, carRect.bottom - 5),
        3.2,
        lightPaint,
      );
    }
    // Taillights (top of rect = back of car).
    final taillight = Paint()..color = const Color(0xFFEF4444);
    for (final dx in [-carW * 0.30, carW * 0.30]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(carRect.center.dx + dx, carRect.top + 4),
            width: carRect.width * 0.18,
            height: 6,
          ),
          const Radius.circular(2),
        ),
        taillight,
      );
    }
    // Exhaust pipes (bottom of car).
    for (final dx in [-carW * 0.20, carW * 0.20]) {
      canvas.drawCircle(
        Offset(carRect.center.dx + dx, carRect.bottom + 1),
        2.5,
        Paint()..color = const Color(0xFF374151),
      );
    }
    // Tires — slight rotation hint on lane-switch.
    final tirePaint = Paint()..color = const Color(0xFF1A1A1A);
    final rimPaint = Paint()..color = const Color(0xFF9CA3AF);
    final tireAngle = steerDirection * 0.35;
    canvas.save();
    canvas.translate(carRect.center.dx, carRect.center.dy);
    for (final dx in [-carW * 0.32, carW * 0.32]) {
      for (final dy in [-carH * 0.05, carH * 0.42]) {
        canvas.save();
        canvas.translate(dx, dy);
        canvas.rotate(tireAngle);
        canvas.drawCircle(Offset.zero, carW * 0.075, tirePaint);
        canvas.drawCircle(Offset.zero, carW * 0.045, rimPaint);
        canvas.restore();
      }
    }
    canvas.restore();
    // Race number "1" decal on the hood.
    final tp = TextPainter(
      text: TextSpan(
        text: '1',
        style: TextStyle(
          color: Colors.white,
          fontSize: carH * 0.18,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(carRect.center.dx - tp.width / 2, carRect.top + carRect.height * 0.06),
    );
  }

  @override
  bool shouldRepaint(_TrackPainter old) =>
      old.scroll != scroll ||
      old.curvaturePhase != curvaturePhase ||
      old.idleTime != idleTime ||
      old.carX != carX ||
      old.steerDirection != steerDirection ||
      old.coins != coins ||
      old.obstacles != obstacles ||
      old.opponents != opponents ||
      old.magnets != magnets ||
      old.trees != trees ||
      old.balloons != balloons ||
      old.sparks != sparks ||
      old.smoke != smoke ||
      old.bursts != bursts ||
      old.floaters != floaters ||
      old.speedLines != speedLines ||
      old.nitro != nitro;
}
