import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../game_widgets.dart';
import '../mini_game.dart';

/// Subway Run — flagship Subway Surfers-style endless runner.
///
/// **Visual recipe (matches the reference)**
///
///   * Bright daylight sky — soft blue gradient with fluffy clouds
///     drifting overhead and a glowing sun.
///   * Colorful daytime city skyline — two parallax layers with
///     buildings, antennas and warm/cool window palettes.
///   * Three converging tracks with **real steel rails** and
///     wooden railroad ties that scale with depth.
///   * **Subway train cars** with bright livery, window strips,
///     passenger doors, headlights, hazard chevrons and the
///     iconic yellow/orange front.
///   * **Runner character** — red hoodie + sneakers + cap + backpack,
///     banking on lane switch, with dust puffs at the feet.
///   * **Coin pickup animation** — gold coin pops, sparkles, and
///     snaps to the HUD counter.
///   * Three power-ups: Magnet (purple), Sneakers (yellow),
///     Hoverboard Shield (cyan) — all with glowing halos.
///   * Speed lines, screen shake on crash, "BUSTED!" overlay, then
///     "Game Over" summary.
///
/// **Mechanics**
///
///   * 3 lanes, swipe ← / → to switch, swipe ↑ to jump, swipe ↓
///     to slide / ground-pound.
///   * Forward speed ramps every 15 s (220 → 620 px/s).
///   * Double-tap to activate Hoverboard (absorbs one crash).
///   * Lane +25, Coin +10, Sneaker pickup → double-jump.
class SubwayRunGame extends MiniGame {
  const SubwayRunGame({super.key, required super.callbacks});

  @override
  State<SubwayRunGame> createState() => _SubwayRunState();
}

class _SubwayRunState extends MiniGameState<SubwayRunGame>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final Random _rng = Random();
  DateTime _last = DateTime.now();

  static const int _lanes = 3;
  static const double _gravity = 1900;
  // Jump apex ≈ v²/(2g) = 760²/(2·1900) ≈ 152 px — about 2.4× the
  // character's standing height. Real Subway Surfers uses ~1.5-2× with
  // visible hang-time and a leg-tuck animation at the apex.
  static const double _jumpVelocity = 760;
  static const double _sneakerJumpVelocity = 980;
  static const int _coinValue = 10;
  static const double _magnetDuration = 10.0;
  static const double _sneakerDuration = 8.0;
  static const double _hoverboardDuration = 12.0;
  static const double _speedWaveInterval = 15.0;

  // Player state.
  int _targetLane = 1;
  int _lane = 1;
  double _laneAnimT = 1.0;
  double _yOffset = 0;
  double _yVel = 0;
  bool _sliding = false;
  double _slideTime = 0;
  double _bankTilt = 0;
  int _laneSwitchesThisJump = 0;
  // Elapsed seconds since the current jump launched — drives the
  // leg-tuck animation in _drawPlayer. Reset to 0 when a new jump
  // starts, increments every tick while airborne, undefined on ground.
  double _jumpElapsed = 0;

  // Score / progression.
  int _score = 0;
  int _distance = 0;
  int _coins = 0;
  double _speed = 220;
  int _speedWaveIndex = 0;
  double _speedWaveTimer = 0;
  bool _gameOver = false;
  static const double _crashDuration = 1.4;
  double _crashTimer = 0;
  double _ragdollAngle = 0;
  double _ragdollT = 0;

  /// Last milestone (every 500 m) we've celebrated — reset to 0 each
  /// run so the banner fires repeatedly.
  int _lastMilestone = 0;
  /// Red vignette overlay opacity (0..1). Bumped briefly on near-miss.
  double _nearMissOpacity = 0;

  // Camera shake.
  double _shakeTime = 0;
  double _shakeMag = 0;

  // Power-ups.
  bool _magnetActive = false;
  double _magnetTime = 0;
  bool _sneakerActive = false;
  double _sneakerTime = 0;
  bool _hoverboardActive = false;
  double _hoverboardTime = 0;
  int _hoverboardAbsorptions = 0;
  int _lastTapTimeMs = 0;

  // Entity pools.
  final List<_Obstacle> _obstacles = [];
  final List<_CoinSprite> _coinSprites = [];
  final List<_PowerUp> _powerUps = [];
  final List<_FloatText> _floaters = [];
  final List<_Sparkle> _sparkles = [];
  final List<_SpeedLine> _speedLines = [];
  final List<_DustPuff> _dustPuffs = [];
  final List<_SnapCoin> _snapCoins = [];

  // World scroll phases.
  double _envScroll = 0;
  double _cloudScroll = 0;
  double _skylineScroll = 0;
  double _poleScroll = 0;
  double _tieScroll = 0;

  // Side props are spawned at the vanishing point and each tracks its
  // own z so they don't share a single scroll phase with the rest of
  // the world.
  double _propSpawnTimer = 0;
  final List<_SideProp> _sideProps = [];

  double _screenW = 0;
  double _screenH = 0;
  int _spawnTimer = 0;
  int _powerUpTimer = 0;

  Offset? _swipeStart;
  double _swipeAccumDx = 0;
  double _swipeAccumDy = 0;
  bool _swipeConsumed = false;
  double _idleTime = 0;
  double _footstepTimer = 0;

  /// Hint-chip visibility — 1.0 at start, fades to 0 over the first
  /// ~2.5 s of play so the bottom swipe/jump/slide/hover chips don't
  /// permanently cover the player's feet.
  double _hintOpacity = 1.0;
  static const double _hintFadeStart = 1.0;
  static const double _hintFadeEnd = 2.5;

  // Cached deterministic per-tie params so the painter doesn't reseed
  // every frame.
  static final List<_RailSpec> _railSpecs = List.unmodifiable(
    List.generate(28, (i) {
      final r = Random(1000 + i);
      return _RailSpec(
        heightOffset: (r.nextDouble() - 0.5) * 6,
        shineAlpha: 0.18 + r.nextDouble() * 0.18,
      );
    }),
  );

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
    _prepopulateSideProps();
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

  void _refreshStats() {
    final magnet = _magnetActive ? '  •  MAGNET' : '';
    final sneaker = _sneakerActive ? '  •  SNEAKERS' : '';
    final board = _hoverboardActive ? '  •  HOVERBOARD' : '';
    reportStats(
        '${_distance}m  •  Coins $_coins$magnet$sneaker$board');
  }

  // ─────────────────────────────────────────────────────────────
  // Tick
  // ─────────────────────────────────────────────────────────────

  void _tick(Duration _) {
    if (!mounted || _screenW == 0) return;
    // After the crash animation has finished AND the game is over,
    // stop the ticker so we don't keep repainting under the host's
    // game-over overlay — that's the "freeze mid-gameplay" feel.
    if (_gameOver && _crashTimer <= 0) {
      if (_ticker.isActive) _ticker.stop();
      return;
    }
    final now = DateTime.now();
    final dt = now.difference(_last).inMicroseconds / 1e6;
    _last = now;
    _idleTime += dt;
    // Hint chip fade — full opacity for the first 2 s of play, then
    // ease out to zero by the 6 s mark so the player's feet are
    // visible during normal gameplay.
    if (_hintOpacity > 0 && !_gameOver) {
      if (_idleTime > _hintFadeStart) {
        _hintOpacity =
            (1.0 - (_idleTime - _hintFadeStart) / (_hintFadeEnd - _hintFadeStart))
                .clamp(0.0, 1.0);
      }
    }
    if (dt > 0.1) return; // skip huge frames (backgrounded)

    setState(() {
      // Distance + speed ramp.
      _distance += (_speed * dt / 6).round();
      // Milestone banner every 500 m — visible "you're doing great"
      // feedback at every half-kilometer mark.
      final milestone = _distance ~/ 500;
      if (milestone > _lastMilestone) {
        _lastMilestone = milestone;
        for (var i = 0; i < 12; i++) {
          final a = (i / 12) * 2 * pi;
          _sparkles.add(_Sparkle(
            x: _screenW / 2,
            y: _screenH * 0.32,
            life: 0.9,
            phase: a,
            r: 0,
            color: const Color(0xFFFACC15),
          ));
        }
        _floaters.add(_FloatText(
          x: _screenW / 2,
          y: _screenH * 0.30,
          text: '$milestone × 500 m!',
          color: const Color(0xFFFACC15),
        ));
        haptic(HapticFeedbackType.medium);
      }
      _speedWaveTimer += dt;
      if (_speedWaveTimer >= _speedWaveInterval) {
        _speedWaveTimer = 0;
        _speedWaveIndex += 1;
        _speed = (220 + _speedWaveIndex * 34).toDouble().clamp(220.0, 620.0);
        _floaters.add(_FloatText(
          x: _screenW / 2,
          y: _screenH * 0.32,
          text: 'SPEED UP!',
          color: const Color(0xFFFB923C),
        ));
      }

      // Power-up countdowns.
      if (_magnetActive) {
        _magnetTime = (_magnetTime - dt).clamp(0.0, _magnetDuration);
        if (_magnetTime <= 0) _magnetActive = false;
      }
      if (_sneakerActive) {
        _sneakerTime = (_sneakerTime - dt).clamp(0.0, _sneakerDuration);
        if (_sneakerTime <= 0) _sneakerActive = false;
      }
      if (_hoverboardActive) {
        _hoverboardTime = (_hoverboardTime - dt).clamp(0.0, _hoverboardDuration);
        if (_hoverboardTime <= 0) _hoverboardActive = false;
      }

      // Crash sequence: pause world, animate ragdoll + BUSTED banner.
      // Slow-mo: timeScale ramps from 0.25 → 1.0 across the crash timer
      // so the impact lands with weight and the world eases back in.
      if (_crashTimer > 0) {
        final slowMo = 0.25 + 0.75 * (1.0 - _crashTimer / _crashDuration);
        final sdt = dt * slowMo;
        _crashTimer = (_crashTimer - sdt).clamp(0.0, _crashDuration);
        _ragdollT = (_ragdollT + sdt * 2.4).clamp(0.0, 1.0);
        _ragdollAngle = sin(_ragdollT * pi) * 0.9;
        for (final s in _sparkles) {
          s.life -= sdt;
        }
        _sparkles.removeWhere((s) => s.life <= 0);
        for (final d in _dustPuffs) {
          d.life -= sdt;
          d.r += 30 * sdt;
        }
        _dustPuffs.removeWhere((d) => d.life <= 0);
        for (final f in _floaters) {
          f.y -= 30 * sdt;
          f.life -= sdt;
        }
        _floaters.removeWhere((f) => f.life <= 0);
        for (final sc in _snapCoins) {
          sc.t = (sc.t + sdt * 3).clamp(0.0, 1.0);
        }
        if (_crashTimer <= 0.05 && !_gameOver) {
          _endGame();
        }
        return;
      }

      // Spawn cadence.
      _spawnTimer += (dt * 1000).round();
      if (_spawnTimer > 700) {
        _spawnTimer = 0;
        _spawnRandom();
      }
      _powerUpTimer += (dt * 1000).round();
      if (_powerUpTimer > 12000) {
        _powerUpTimer = 0;
        _spawnPowerUp();
      }

      // Lane animation. Real Subway Surfers uses a subtle 5-10° lean
      // (~0.15 rad) with a ~200 ms easeOutCubic — not the cartoonish
      // 23° lean this code used to do. Slower easing (dt*5 ≈ 200 ms)
      // gives the foot-shuffle room to read.
      if (_lane != _targetLane) {
        _laneAnimT = (_laneAnimT + dt * 5).clamp(0.0, 1.0);
        final u = Curves.easeOutCubic.transform(_laneAnimT);
        if (_laneAnimT >= 1.0) {
          _lane = _targetLane;
          _bankTilt = 0;
        } else {
          _bankTilt = (_targetLane - _lane).sign.toDouble() * (1 - u) * 0.15;
        }
      } else {
        _bankTilt = 0;
      }

      // Integrate entities.
      final dz = dt * _speed / 720.0;
      for (final o in _obstacles) {
        o.z += dz;
        if (o.kind == _ObstacleKind.oncomingTrain) {
          o.laneOffset += o.drift * dt;
          if (o.laneOffset > 1.3) o.drift = -o.drift.abs();
          if (o.laneOffset < -1.3) o.drift = o.drift.abs();
        }
      }
      _obstacles.removeWhere((o) => o.z > 1.1);

      for (final c in _coinSprites) {
        c.z += dz;
        c.phase += dt * 5;
        c.bob += dt * 2;
      }
      _coinSprites.removeWhere((c) => c.z > 1.1);

      for (final p in _powerUps) {
        p.z += dz;
        p.phase += dt * 2;
      }
      _powerUps.removeWhere((p) => p.z > 1.1);

      // Magnet pull.
      if (_magnetActive) {
        final playerScreen = _projectToScreen(0, _yOffset, 1.0);
        for (final c in _coinSprites) {
          final cs = _projectToScreen(c.laneOffset, 0, c.z);
          final d = (cs - playerScreen).distance;
          if (d < 150) {
            final dir = playerScreen - cs;
            final len = dir.distance;
            if (len > 0) {
              c.x += dir.dx / len * 360 * dt;
              c.y += dir.dy / len * 360 * dt;
            }
          }
        }
      }

      // Jump physics.
      if (_yOffset < 0 || _yVel > 0) {
        _jumpElapsed += dt;
        _yVel -= _gravity * dt;
        _yOffset += _yVel * dt;
        if (_yOffset > 0) {
          _yOffset = 0;
          _yVel = 0;
          _jumpElapsed = 0;
          for (var i = 0; i < 6; i++) {
            _dustPuffs.add(_DustPuff(
              x: _screenW / 2 + (_rng.nextDouble() - 0.5) * 22,
              y: _projectToScreen(0, 0, 1.0).dy + 30,
              life: 0.5,
            ));
          }
          haptic(HapticFeedbackType.selection);
        }
      }
      if (_sliding) {
        _slideTime -= dt;
        if (_slideTime <= 0) {
          _sliding = false;
        }
      }

      // Footstep dust.
      if (_yOffset >= -1 && !_sliding) {
        _footstepTimer += dt;
        if (_footstepTimer > 0.16) {
          _footstepTimer = 0;
          _dustPuffs.add(_DustPuff(
            x: _screenW / 2 + (_rng.nextDouble() - 0.5) * 18,
            y: _projectToScreen(0, 0, 1.0).dy + 28,
            life: 0.35,
          ));
        }
      }

      // VFX ticks.
      for (final f in _floaters) {
        f.y -= 30 * dt;
        f.life -= dt;
      }
      _floaters.removeWhere((f) => f.life <= 0);
      for (final s in _sparkles) {
        s.life -= dt;
        s.phase += dt * 6;
        s.r += 30 * dt;
      }
      _sparkles.removeWhere((s) => s.life <= 0);
      for (final sl in _speedLines) {
        sl.y += _speed * 2 * dt;
        sl.life -= dt;
      }
      _speedLines.removeWhere((sl) => sl.life <= 0);
      for (final d in _dustPuffs) {
        d.life -= dt;
        d.r += 35 * dt;
      }
      _dustPuffs.removeWhere((d) => d.life <= 0);
      for (final sc in _snapCoins) {
        sc.t = (sc.t + dt * 2.5).clamp(0.0, 1.0);
      }
      _snapCoins.removeWhere((sc) => sc.t >= 1.0);

      if (_shakeTime > 0) {
        _shakeTime = (_shakeTime - dt).clamp(0.0, 99.0);
      }

      // Speed-line emission when dashing.
      if (_speed > 380 && _rng.nextDouble() < 0.55) {
        _speedLines.add(_SpeedLine(
          x: _rng.nextBool() ? _screenW * 0.04 : _screenW * 0.96,
          y: -20,
          length: 40 + _rng.nextDouble() * 50,
          life: 0.6,
        ));
      }

      // Near-miss vignette decay (~0.4 s total fade).
      if (_nearMissOpacity > 0) {
        _nearMissOpacity = (_nearMissOpacity - dt * 2.5).clamp(0.0, 1.0);
      }

      // World scroll phases.
      _envScroll += dt * _speed;
      _cloudScroll += dt * _speed * 0.05;
      _skylineScroll += dt * _speed * 0.15;
      _poleScroll += dt * _speed * 0.5;
      _tieScroll += dt * _speed * 0.6;
      // Side props spawn at the vanishing point and scroll toward the
      // camera, matching the obstacle motion convention (z=0 horizon,
      // z=1 player). Spawn rate is tied to player speed so faster runs
      // feel denser.
      _propSpawnTimer -= dt * _speed * 0.05;
      if (_propSpawnTimer <= 0) {
        _propSpawnTimer = 0.08 + _rng.nextDouble() * 0.05;
        _spawnSideProp();
      }
      // Advance every prop toward the camera and despawn ones that
      // have scrolled past z=1.05 (they're behind the camera now).
      for (final p in _sideProps) {
        p.z += dt * 0.9;
      }
      _sideProps.removeWhere((p) => p.z > 1.05);

      _resolveCollisions();
    });
  }

  void _spawnSideProp() {
    // Decide side and kind. Cacti + lamps lean slightly outside the
    // track; crates + barrels sit just at the edge. Spawn at the
    // vanishing point (z=0); the tick loop will advance the prop toward
    // the camera (z=1).
    final side = _rng.nextBool() ? -1 : 1;
    final kinds = _PropKind.values;
    final kind = kinds[_rng.nextInt(kinds.length)];
    _sideProps.add(_SideProp(
      kind: kind,
      z: 0.0,
      side: side,
      variant: _rng.nextInt(4),
    ));
  }

  /// Seed the world with props at every depth so the player never sees
  /// an empty horizon while the spawn timer warms up.
  void _prepopulateSideProps() {
    const seedZs = [0.95, 0.82, 0.7, 0.58, 0.45, 0.32, 0.2, 0.1];
    var side = -1;
    for (final z in seedZs) {
      final kinds = _PropKind.values;
      _sideProps.add(_SideProp(
        kind: kinds[_rng.nextInt(kinds.length)],
        z: z,
        side: side,
        variant: _rng.nextInt(4),
      ));
      side = -side;
    }
  }

  void _spawnRandom() {
    final roll = _rng.nextDouble();
    // 55% obstacles (with multi-lane patterns), 45% coin streaks.
    if (roll < 0.55) {
      _spawnObstaclePattern();
    } else {
      _spawnCoinStreak();
    }
  }

  /// Spawn 1-3 obstacles in a recognisable pattern that forces the
  /// player to choose a lane — much closer to Subway Surfer's actual
  /// feel than single-lane random spawns.
  void _spawnObstaclePattern() {
    final pattern = _rng.nextInt(4);
    switch (pattern) {
      case 0:
        // Single obstacle in a random lane.
        _addObstacle(_rng.nextInt(_lanes));
      case 1:
        // Two-row train: fill two adjacent lanes, leaving exactly one
        // safe lane.
        final safe = _rng.nextInt(_lanes);
        for (var i = 0; i < _lanes; i++) {
          if (i == safe) continue;
          _addObstacle(i, kind: _ObstacleKind.train);
        }
      case 2:
        // Hurdle-bar across all three lanes — player must jump.
        for (var i = 0; i < _lanes; i++) {
          _addObstacle(i, kind: _ObstacleKind.hurdle);
        }
      case 3:
        // Signal barrier + train in different lanes — split-second
        // decision-making.
        _addObstacle(_rng.nextInt(_lanes),
            kind: _ObstacleKind.signalBarrier);
        final blockedLanes = <int>{(_rng.nextInt(_lanes) + 1) % _lanes};
        for (var i = 0; i < _lanes; i++) {
          if (blockedLanes.contains(i)) continue;
          _addObstacle(i, kind: _ObstacleKind.train);
        }
        break;
    }
  }

  void _addObstacle(int lane, {_ObstacleKind? kind}) {
    final laneOffset = (lane - 1).toDouble();
    final k = kind ??
        _pickObstacleKind();
    _obstacles.add(_Obstacle(
      laneOffset: laneOffset,
      z: -0.05,
      kind: k,
    ));
  }

  _ObstacleKind _pickObstacleKind() {
    final r = _rng.nextDouble();
    if (r < 0.30) return _ObstacleKind.hurdle;
    if (r < 0.55) return _ObstacleKind.signalBarrier;
    if (r < 0.78) return _ObstacleKind.train;
    if (r < 0.92) return _ObstacleKind.trackBuffer;
    return _ObstacleKind.oncomingTrain;
  }

  /// Spawn a streak of coins that arcs across multiple lanes so the
  /// player has to actually switch lanes to collect them.
  void _spawnCoinStreak() {
    final shape = _rng.nextInt(3);
    final count = 5 + _rng.nextInt(4);
    final zStart = -0.1 - _rng.nextDouble() * 0.2;
    switch (shape) {
      case 0:
        // Straight line in one lane.
        final lane = _rng.nextInt(_lanes);
        for (var i = 0; i < count; i++) {
          _addCoin(lane, zStart - i * 0.05);
        }
      case 1:
        // Three-lane zigzag — forces lane-switching.
        for (var i = 0; i < count; i++) {
          _addCoin(i % _lanes, zStart - i * 0.06);
        }
      case 2:
        // Cross-lane arc: collect by switching lanes quickly.
        final sequence = <int>[0, 1, 2, 1, 0, 1, 2];
        for (var i = 0; i < count; i++) {
          _addCoin(sequence[i % sequence.length], zStart - i * 0.05);
        }
    }
  }

  void _addCoin(int lane, double z) {
    _coinSprites.add(_CoinSprite(
      laneOffset: (lane - 1).toDouble(),
      z: z,
      phase: _rng.nextDouble() * pi * 2,
      bob: _rng.nextDouble() * pi * 2,
      x: 0,
      y: 0,
    ));
  }

  void _spawnPowerUp() {
    final lane = _rng.nextInt(_lanes);
    final kinds = _PowerUpKind.values;
    final kind = kinds[_rng.nextInt(kinds.length)];
    _powerUps.add(_PowerUp(
      laneOffset: (lane - 1).toDouble(),
      z: -0.05,
      kind: kind,
      phase: 0,
    ));
  }

  // ─────────────────────────────────────────────────────────────
  // Perspective
  // ─────────────────────────────────────────────────────────────

  Offset _projectToScreen(double laneOffset, double yOffset, double z) {
    final vanishingY = _screenH * 0.22;
    final vanishingX = _screenW / 2;
    final trackBottomY = _screenH - 40;
    final trackTopWidth = _screenW * 0.12;
    final trackBottomWidth = _screenW * 0.95;
    final safeZ = z.clamp(0.0, 1.05);
    final t = safeZ;
    final trackY = vanishingY + (trackBottomY - vanishingY) * t;
    final trackHalfWidth = (trackTopWidth +
            (trackBottomWidth - trackTopWidth) * t) /
        2;
    final laneWorldX = laneOffset * (trackHalfWidth * 0.7);
    final sx = vanishingX + laneWorldX;
    final sy = trackY + yOffset * t;
    return Offset(sx, sy);
  }

  Offset _playerScreen() {
    final u = Curves.easeOutCubic.transform(_laneAnimT);
    final renderedLane = _lane + (_targetLane - _lane) * u;
    return _projectToScreen(renderedLane - 1.0, _yOffset, 1.0);
  }

  // ─────────────────────────────────────────────────────────────
  // Collisions
  // ─────────────────────────────────────────────────────────────

  void _resolveCollisions() {
    final runnerScreen = _playerScreen();
    final u = Curves.easeOutCubic.transform(_laneAnimT);
    final renderedLane = _lane + (_targetLane - _lane) * u;
    final intLane = renderedLane.round().clamp(0, 2);

    // Near-miss tracking: track the minimum distance from the runner
    // to any obstacle in the same lane during the collision window.
    // When that minimum is below the "tight miss" threshold we fire
    // a brief red vignette + speed-line burst — the "premium feel"
    // cue every Subway Surfers has.
    bool nearMissThisFrame = false;

    for (final o in _obstacles.toList()) {
      if (o.z < 0.82 || o.z > 1.06) continue;
      if ((o.laneOffset - (intLane - 1)).abs() > 0.6) continue;
      // Near-miss: obstacle is in our lane, in the danger window,
      // and we're about to clip it (z > 0.96). Mark for a vignette
      // bump below — handled *after* the dodge-or-crash check so the
      // crash path still wins.
      if (o.z > 0.96 && (o.laneOffset - (intLane - 1)).abs() < 0.3) {
        nearMissThisFrame = true;
      }
      if (o.kind == _ObstacleKind.signalBarrier) {
        if (_sliding) continue;
      } else if (o.kind == _ObstacleKind.hurdle) {
        if (_yOffset < -55) continue;
      } else if (o.kind == _ObstacleKind.train ||
          o.kind == _ObstacleKind.oncomingTrain) {
        if (_yOffset < -55) continue;
        if (_sliding) continue;
      } else if (o.kind == _ObstacleKind.trackBuffer) {
        if (_yOffset < -55 || _sliding) continue;
      }
      // Hoverboard shield absorbs one crash.
      if (_hoverboardActive && _hoverboardAbsorptions < 1) {
        _hoverboardAbsorptions = 1;
        _hoverboardActive = false;
        _hoverboardTime = 0;
        for (var i = 0; i < 14; i++) {
          _sparkles.add(_Sparkle(
            x: runnerScreen.dx,
            y: runnerScreen.dy,
            life: 0.7,
            phase: (i / 14) * 2 * pi,
            r: 0,
            color: const Color(0xFF22D3EE),
          ));
        }
        _obstacles.remove(o);
        _floaters.add(_FloatText(
          x: runnerScreen.dx,
          y: runnerScreen.dy - 40,
          text: 'SHIELD!',
          color: const Color(0xFF22D3EE),
        ));
        haptic(HapticFeedbackType.heavy);
        return;
      }
      _triggerShake();
      _crash(o);
      return;
    }

    // Near-miss feedback: bump the red vignette overlay + emit a
    // burst of speed lines for ~0.4 s. We only fire if the player
    // actually dodged (no crash above) and only once per "close
    // shave" — the timer prevents flicker.
    if (nearMissThisFrame && _nearMissOpacity < 0.1) {
      _nearMissOpacity = 1.0;
      for (var i = 0; i < 4; i++) {
        _speedLines.add(_SpeedLine(
          x: _rng.nextBool() ? _screenW * 0.04 : _screenW * 0.96,
          y: -20,
          length: 50 + _rng.nextDouble() * 60,
          life: 0.4,
        ));
      }
      haptic(HapticFeedbackType.selection);
    }

    for (final c in _coinSprites.toList()) {
      if ((c.laneOffset - (intLane - 1)).abs() > 0.6) continue;
      if (c.z < 0.82 || c.z > 1.1) continue;
      final cs = _projectToScreen(c.laneOffset, 0, c.z) + Offset(c.x, c.y);
      final d = (cs - runnerScreen).distance;
      if (d < 60) {
        _score += _coinValue;
        _coins += 1;
        _snapCoins.add(_SnapCoin(
          fromX: cs.dx,
          fromY: cs.dy,
          t: 0,
        ));
        for (var i = 0; i < 10; i++) {
          final a = (i / 10) * 2 * pi;
          _sparkles.add(_Sparkle(
            x: cs.dx,
            y: cs.dy,
            life: 0.6,
            phase: a,
            r: 0,
            color: const Color(0xFFFFE066),
          ));
        }
        _coinSprites.remove(c);
        haptic(HapticFeedbackType.selection);
        reportScore(_score);
        _refreshStats();
      }
    }

    for (final p in _powerUps.toList()) {
      if ((p.laneOffset - (intLane - 1)).abs() > 0.6) continue;
      if (p.z < 0.82 || p.z > 1.1) continue;
      final ps = _projectToScreen(p.laneOffset, 0, p.z);
      final d = (ps - runnerScreen).distance;
      if (d < 60) {
        _activatePowerUp(p.kind);
        for (var i = 0; i < 12; i++) {
          _sparkles.add(_Sparkle(
            x: ps.dx,
            y: ps.dy,
            life: 0.7,
            phase: (i / 12) * 2 * pi,
            r: 0,
            color: _powerUpColor(p.kind),
          ));
        }
        _floaters.add(_FloatText(
          x: ps.dx,
          y: ps.dy - 30,
          text: _powerUpLabel(p.kind),
          color: _powerUpColor(p.kind),
        ));
        _powerUps.remove(p);
        haptic(HapticFeedbackType.medium);
      }
    }
  }

  void _activatePowerUp(_PowerUpKind kind) {
    switch (kind) {
      case _PowerUpKind.coinMagnet:
        _magnetActive = true;
        _magnetTime = _magnetDuration;
        break;
      case _PowerUpKind.superSneakers:
        _sneakerActive = true;
        _sneakerTime = _sneakerDuration;
        break;
      case _PowerUpKind.hoverboard:
        _hoverboardActive = true;
        _hoverboardAbsorptions = 0;
        _hoverboardTime = _hoverboardDuration;
        break;
    }
    _refreshStats();
  }

  String _powerUpLabel(_PowerUpKind kind) {
    switch (kind) {
      case _PowerUpKind.coinMagnet:
        return 'MAGNET!';
      case _PowerUpKind.superSneakers:
        return 'SNEAKERS!';
      case _PowerUpKind.hoverboard:
        return 'HOVERBOARD!';
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Input
  // ─────────────────────────────────────────────────────────────

  void _triggerShake() {
    _shakeTime = 0.45;
    _shakeMag = 16;
  }

  void _switchLane(int lane) {
    if (_gameOver || _crashTimer > 0) return;
    lane = lane.clamp(0, _lanes - 1);
    if (lane == _targetLane) return;
    setState(() {
      if (_yOffset < -10) {
        _laneSwitchesThisJump += 1;
        if (_laneSwitchesThisJump > 1) return;
      }
      _lane = _targetLane;
      _targetLane = lane;
      _laneAnimT = 0;
      _score += 25;
      final tx = _screenW / _lanes * (lane + 0.5);
      _floaters.add(_FloatText(
        x: tx,
        y: _screenH / 2,
        text: '+25 LANE!',
        color: const Color(0xFF22D3EE),
      ));
      haptic(HapticFeedbackType.selection);
      reportScore(_score);
      _refreshStats();
    });
  }

  void _jump() {
    if (_gameOver || _crashTimer > 0 || _sliding) return;
    if (_yOffset >= -1) {
      setState(() {
        _yVel = _sneakerActive ? _sneakerJumpVelocity : _jumpVelocity;
        _jumpElapsed = 0;
        _laneSwitchesThisJump = 0;
        _floaters.add(_FloatText(
          x: _screenW / 2,
          y: _screenH * 0.4,
          text: 'JUMP!',
          color: const Color(0xFF4E6CF5),
        ));
        haptic(HapticFeedbackType.selection);
      });
    }
  }

  void _slide() {
    if (_gameOver || _crashTimer > 0) return;
    // Swipe-down only triggers a forward roll while on the ground.
    // Mid-air swipe-down is intentionally a no-op so the jump reads
    // cleanly (no ground-pound).
    if (_yOffset < -10) return;
    setState(() {
      _sliding = true;
      _slideTime = 0.6;
      haptic(HapticFeedbackType.selection);
    });
  }

  void _onPanStart(DragStartDetails d) {
    _swipeStart = d.localPosition;
    _swipeAccumDx = 0;
    _swipeAccumDy = 0;
    _swipeConsumed = false;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    // Accumulate the running delta and commit the first action whose
    // threshold trips. This is more forgiving than measuring total
    // displacement at pan-end: the user gets instant feedback the
    // moment a swipe "decides" its direction.
    if (_swipeConsumed || _gameOver || _crashTimer > 0) return;
    final start = _swipeStart;
    if (start == null) return;
    _swipeAccumDx += d.delta.dx;
    _swipeAccumDy += d.delta.dy;
    // 16 px threshold — short swipes still register.
    if (_swipeAccumDx.abs() < 16 && _swipeAccumDy.abs() < 16) return;
    _commitSwipe();
  }

  /// Velocity-based fallback for swipes that are short but fast. Fires
  /// once the gesture ends so we don't double-commit against the
  /// accumulated-delta path above.
  void _onPanEnd(DragEndDetails d) {
    final start = _swipeStart;
    _swipeStart = null;
    if (start == null || _gameOver || _crashTimer > 0) return;
    if (!_swipeConsumed) {
      // Fallback: if the user flicked fast even on a short distance,
      // honour their intent. Real Subway Surfers uses ~600 px/s as the
      // commit threshold for horizontal lane switches.
      final v = d.velocity.pixelsPerSecond;
      if (v.dx.abs() > 600 || v.dy.abs() > 600) {
        _swipeAccumDx += v.dx.sign * 60;
        _swipeAccumDy += v.dy.sign * 60;
        _commitSwipe();
      } else {
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - _lastTapTimeMs < 300) {
          _activateHoverboardFromTap();
          _lastTapTimeMs = 0;
        } else {
          _lastTapTimeMs = now;
        }
      }
    }
    _swipeConsumed = false;
  }

  void _commitSwipe() {
    if (_swipeAccumDx.abs() > _swipeAccumDy.abs()) {
      _switchLane(_targetLane + (_swipeAccumDx > 0 ? 1 : -1));
    } else if (_swipeAccumDy < 0) {
      _jump();
    } else if (_yOffset >= -10) {
      _slide();
    }
    _swipeConsumed = true;
  }

  void _activateHoverboardFromTap() {
    if (_hoverboardActive) return;
    _hoverboardActive = true;
    _hoverboardAbsorptions = 0;
    _hoverboardTime = _hoverboardDuration;
    for (var i = 0; i < 18; i++) {
      _sparkles.add(_Sparkle(
        x: _screenW / 2,
        y: _projectToScreen(0, 0, 1.0).dy,
        life: 0.7,
        phase: (i / 18) * 2 * pi,
        r: 0,
        color: const Color(0xFF22D3EE),
      ));
    }
    _floaters.add(_FloatText(
      x: _screenW / 2,
      y: _screenH * 0.32,
      text: 'HOVERBOARD!',
      color: const Color(0xFF22D3EE),
    ));
    haptic(HapticFeedbackType.heavy);
    _refreshStats();
  }

  void _crash(_Obstacle o) {
    if (_crashTimer > 0) return;
    _crashTimer = 1.4;
    _ragdollT = 0;
    _ragdollAngle = 0;
    for (var i = 0; i < 16; i++) {
      final a = (i / 16) * 2 * pi;
      _sparkles.add(_Sparkle(
        x: _playerScreen().dx,
        y: _playerScreen().dy,
        life: 0.9,
        phase: a,
        r: 0,
        color: const Color(0xFFEF4444),
      ));
    }
    haptic(HapticFeedbackType.heavy);
  }

  void _endGame() {
    if (_gameOver) return;
    _gameOver = true;
    reportScore(_score);
    reportStats('Final: ${_distance}m  •  Coins $_coins');
    reportGameOver();
  }

  // ─────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        _screenW = c.maxWidth;
        _screenH = c.maxHeight;
        final shake = _shakeTime > 0
            ? Offset(
                (_rng.nextDouble() - 0.5) * _shakeMag,
                (_rng.nextDouble() - 0.5) * _shakeMag,
              )
            : Offset.zero;
        return Transform.translate(
          offset: shake,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF7DD3FC), // sky blue top
                    Color(0xFFBFE6FB), // mid sky
                    Color(0xFFE0F2FE), // horizon haze
                  ],
                ),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _TrackPainter(
                        lane: _lane,
                        targetLane: _targetLane,
                        laneAnimT: _laneAnimT,
                        bankTilt: _bankTilt,
                        yOffset: _yOffset,
                        sliding: _sliding,
                        speed: _speed,
                        distance: _distance,
                        obstacles: _obstacles,
                        coins: _coinSprites,
                        powerUps: _powerUps,
                        floaters: _floaters,
                        sparkles: _sparkles,
                        speedLines: _speedLines,
                        magnetActive: _magnetActive,
                        magnetTime: _magnetTime,
                        sneakerActive: _sneakerActive,
                        sneakerTime: _sneakerTime,
                        hoverboardActive: _hoverboardActive,
                        hoverboardTime: _hoverboardTime,
                        idleTime: _idleTime,
                        envScroll: _envScroll,
                        cloudScroll: _cloudScroll,
                        skylineScroll: _skylineScroll,
                        poleScroll: _poleScroll,
                        tieScroll: _tieScroll,
                        dustPuffs: _dustPuffs,
                        snapCoins: _snapCoins,
                        projectToScreen: _projectToScreen,
                        crashTimer: _crashTimer,
                        ragdollAngle: _ragdollAngle,
                        ragdollT: _ragdollT,
                        railSpecs: _railSpecs,
                        sideProps: _sideProps,
                        slideTime: _slideTime,
                        jumpElapsed: _jumpElapsed,
                      ),
                    ),
                  ),
                  // Power-up badges — sit just under the host HUD
                  // (~124 px below the top of the screen, after the
                  // host's padding + controls row + chips row).
                  if (_magnetActive || _sneakerActive || _hoverboardActive)
                    Positioned(
                      top: 124,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Wrap(
                          spacing: 6,
                          alignment: WrapAlignment.center,
                          children: [
                            if (_magnetActive)
                              _PowerBadge(
                                color: const Color(0xFFA073FF),
                                label: 'MAG ${_magnetTime.toStringAsFixed(1)}s',
                              ),
                            if (_sneakerActive)
                              _PowerBadge(
                                color: const Color(0xFFFACC15),
                                label: 'BOUNCE ${_sneakerTime.toStringAsFixed(1)}s',
                              ),
                            if (_hoverboardActive)
                              _PowerBadge(
                                color: const Color(0xFF22D3EE),
                                label: 'BOARD ${_hoverboardTime.toStringAsFixed(1)}s',
                              ),
                          ],
                        ),
                      ),
                    ),
                  // Near-miss red vignette — fades from 1 → 0 over ~0.4 s.
                  // Rendered above the canvas so it tints the world edges
                  // when the player threads an obstacle with no room.
                  if (_nearMissOpacity > 0)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: _NearMissVignette(opacity: _nearMissOpacity),
                      ),
                    ),
                  if (_crashTimer > 0 && !_gameOver)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: _BustedOverlay(
                          t: (1.4 - _crashTimer) / 1.4,
                        ),
                      ),
                    ),
                  Positioned(
                    bottom: 24,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: _hintOpacity,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: const [
                              _HintChip(
                                  icon: Icons.swap_horiz_rounded,
                                  label: 'SWIPE'),
                              _HintChip(
                                  icon: Icons.keyboard_arrow_up_rounded,
                                  label: 'JUMP'),
                              _HintChip(
                                  icon: Icons.keyboard_arrow_down_rounded,
                                  label: 'SLIDE'),
                              _HintChip(
                                  icon: Icons.touch_app_rounded,
                                  label: '2x HOVER'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Pause + game-over overlays are rendered by the host
                  // `GameContainerScreen` (`_GameOverOverlay` mounts when
                  // `reportGameOver()` fires from `_endGame`).
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Records
// ─────────────────────────────────────────────────────────────────

Color _powerUpColor(_PowerUpKind kind) {
  switch (kind) {
    case _PowerUpKind.coinMagnet:
      return const Color(0xFFA073FF);
    case _PowerUpKind.superSneakers:
      return const Color(0xFFFACC15);
    case _PowerUpKind.hoverboard:
      return const Color(0xFF22D3EE);
  }
}

enum _ObstacleKind { hurdle, signalBarrier, train, oncomingTrain, trackBuffer }

class _Obstacle {
  _Obstacle({
    required this.laneOffset,
    required this.z,
    required this.kind,
  });
  double laneOffset;
  double z;
  _ObstacleKind kind;
  double drift = 0;
}

class _CoinSprite {
  _CoinSprite({
    required this.laneOffset,
    required this.z,
    required this.phase,
    required this.bob,
    required this.x,
    required this.y,
  });
  double laneOffset;
  double z;
  double phase;
  double bob;
  double x;
  double y;
}

enum _PowerUpKind { coinMagnet, superSneakers, hoverboard }

class _PowerUp {
  _PowerUp({
    required this.laneOffset,
    required this.z,
    required this.kind,
    required this.phase,
  });
  double laneOffset;
  double z;
  _PowerUpKind kind;
  double phase;
}

class _FloatText {
  _FloatText({required this.x, required this.y, required this.text, required this.color})
      : life = 1.0;
  double x;
  double y;
  String text;
  Color color;
  double life;
}

class _Sparkle {
  _Sparkle({
    required this.x,
    required this.y,
    required this.life,
    required this.phase,
    required this.r,
    required this.color,
  });
  double x;
  double y;
  double life;
  double phase;
  double r;
  Color color;
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

class _DustPuff {
  _DustPuff({required this.x, required this.y, required this.life});
  double x;
  double y;
  double life;
  double r = 4;
}

class _SnapCoin {
  _SnapCoin({required this.fromX, required this.fromY, required this.t});
  double fromX;
  double fromY;
  double t;
}

class _RailSpec {
  const _RailSpec({required this.heightOffset, required this.shineAlpha});
  final double heightOffset;
  final double shineAlpha;
}

/// One parallaxing side prop. Procedurally generated so the world
/// never repeats exactly.
class _SideProp {
  _SideProp({
    required this.kind,
    required this.z,
    required this.side,
    required this.variant,
  });

  /// -1 = left of track, +1 = right of track.
  final int side;
  /// Mutates each frame as the prop scrolls toward the camera. z=0
  /// is at the vanishing point (horizon), z=1 is at the camera — same
  /// convention as obstacles/coins so perspective math is consistent.
  double z;
  final _PropKind kind;
  final int variant;
}

enum _PropKind { crate, barrel, cactus, lamp }

// ─────────────────────────────────────────────────────────────────
// HUD widgets
// ─────────────────────────────────────────────────────────────────

class _PowerBadge extends StatelessWidget {
  const _PowerBadge({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.45),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          fontFeatures: [FontFeature.tabularFigures()],
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _HintChip extends StatelessWidget {
  const _HintChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
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

class _BustedOverlay extends StatelessWidget {
  const _BustedOverlay({required this.t});
  final double t;
  @override
  Widget build(BuildContext context) {
    final scale = t < 0.2
        ? 0.4 + (t / 0.2) * 0.6
        : (1 + sin((t - 0.2).clamp(0.0, 0.8) * pi * 1.5) * 0.06);
    final alpha = (t * 1.6).clamp(0.0, 1.0);
    return Container(
      color: Colors.black.withValues(alpha: 0.4 * alpha),
      alignment: Alignment.center,
      child: Transform.scale(
        scale: scale,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'BUSTED!',
              style: TextStyle(
                color: Color(0xFFEF4444),
                fontSize: 64,
                fontWeight: FontWeight.w900,
                letterSpacing: 4,
                shadows: [
                  Shadow(blurRadius: 16, color: Colors.black87),
                ],
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'CRASH!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Red radial vignette that fades over ~0.4 s after a near-miss.
/// Transparent in the centre, hot at the edges.
class _NearMissVignette extends StatelessWidget {
  const _NearMissVignette({required this.opacity});
  final double opacity;
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _NearMissVignettePainter(opacity: opacity),
    );
  }
}

class _NearMissVignettePainter extends CustomPainter {
  _NearMissVignettePainter({required this.opacity});
  final double opacity;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = const RadialGradient(
        center: Alignment(0, 0.15),
        radius: 1.1,
        colors: [
          Color(0x00000000),
          Color(0x00000000),
          Color(0x66EF4444),
          Color(0xCCEF4444),
        ],
        stops: [0.0, 0.45, 0.8, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant _NearMissVignettePainter old) =>
      old.opacity != opacity;
}

// ─────────────────────────────────────────────────────────────────
// Painter
// ─────────────────────────────────────────────────────────────────

typedef _ProjectFn = Offset Function(double laneOffset, double yOffset, double z);

class _TrackPainter extends CustomPainter {
  _TrackPainter({
    required this.lane,
    required this.targetLane,
    required this.laneAnimT,
    required this.bankTilt,
    required this.yOffset,
    required this.sliding,
    required this.speed,
    required this.distance,
    required this.obstacles,
    required this.coins,
    required this.powerUps,
    required this.floaters,
    required this.sparkles,
    required this.speedLines,
    required this.magnetActive,
    required this.magnetTime,
    required this.sneakerActive,
    required this.sneakerTime,
    required this.hoverboardActive,
    required this.hoverboardTime,
    required this.idleTime,
    required this.envScroll,
    required this.cloudScroll,
    required this.skylineScroll,
    required this.poleScroll,
    required this.tieScroll,
    required this.dustPuffs,
    required this.snapCoins,
    required this.sideProps,
    required this.projectToScreen,
    required this.crashTimer,
    required this.ragdollAngle,
    required this.ragdollT,
    required this.railSpecs,
    required this.slideTime,
    required this.jumpElapsed,
  });

  final int lane;
  final int targetLane;
  final double laneAnimT;
  final double bankTilt;
  final double yOffset;
  final bool sliding;
  final double speed;
  final int distance;
  final List<_Obstacle> obstacles;
  final List<_CoinSprite> coins;
  final List<_PowerUp> powerUps;
  final List<_FloatText> floaters;
  final List<_Sparkle> sparkles;
  final List<_SpeedLine> speedLines;
  final bool magnetActive;
  final double magnetTime;
  final bool sneakerActive;
  final double sneakerTime;
  final bool hoverboardActive;
  final double hoverboardTime;
  final double idleTime;
  final double envScroll;
  final double cloudScroll;
  final double skylineScroll;
  final double poleScroll;
  final double tieScroll;
  final List<_DustPuff> dustPuffs;
  final List<_SnapCoin> snapCoins;
  final _ProjectFn projectToScreen;
  final double crashTimer;
  final double ragdollAngle;
  final double ragdollT;
  final List<_RailSpec> railSpecs;
  final List<_SideProp> sideProps;
  final double slideTime;
  final double jumpElapsed;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final vanishingY = h * 0.22;
    final vanishingX = w / 2;
    final trackBottomY = h - 40;
    final trackTopHalf = w * 0.06;
    final trackBottomHalf = w * 0.475;

    // ── Sky decorations: sun + clouds. ────────────────────────
    _drawSun(canvas, size);
    _drawClouds(canvas, size);

    // ── Skyline (two parallax layers). ────────────────────────
    // Buildings are clipped to the region *below* the top HUD so the
    // silhouettes don't poke into the score/coin chips and create a
    // busy, fragmented top edge. The HUD chip strip occupies roughly
    // the top ~96dp of the screen.
    canvas.save();
    canvas.clipRect(
      Rect.fromLTRB(0, 96, w, h),
    );
    _drawSkylineLayer(
      canvas,
      size,
      baseY: h * 0.20,
      scroll: skylineScroll,
      seed: 7,
      buildingColor: const Color(0xFFB0BEC5),
      accent: const Color(0xFF7DD3FC),
      windowColor: const Color(0xFFFACC15),
      buildingWidth: 38.0,
      maxHeight: 56.0,
    );
    _drawSkylineLayer(
      canvas,
      size,
      baseY: h * 0.22,
      scroll: skylineScroll * 0.55,
      seed: 21,
      buildingColor: const Color(0xFF90A4AE),
      accent: const Color(0xFF38BDF8),
      windowColor: const Color(0xFF22D3EE),
      buildingWidth: 50.0,
      maxHeight: 72.0,
    );
    canvas.restore();

    // ── Track trapezoid silhouette. ───────────────────────────
    final trackPath = Path()
      ..moveTo(vanishingX - trackTopHalf, vanishingY)
      ..lineTo(vanishingX + trackTopHalf, vanishingY)
      ..lineTo(vanishingX + trackBottomHalf, trackBottomY)
      ..lineTo(vanishingX - trackBottomHalf, trackBottomY)
      ..close();
    // Concrete platform base.
    canvas.drawPath(
      trackPath,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF8B8E94), Color(0xFF4A4D52)],
        ).createShader(trackPath.getBounds()),
    );

    // ── Real railroad ties (depth-banded, scaled). ────────────
    _drawTies(canvas, w, h, vanishingX, vanishingY, trackTopHalf,
        trackBottomHalf, trackBottomY);

    // ── Steel rails (two parallel strips). ────────────────────
    _drawRails(canvas, vanishingY, vanishingX, trackBottomY, trackTopHalf,
        trackBottomHalf);

    // ── Yellow center stripe per lane (perspective dashes). ──
    _drawLaneStripes(canvas);

    // ── Side walls (low platform kerbs). ──────────────────────
    _drawPlatformKerbs(canvas, size, vanishingY, trackBottomY);

    // ── Station lamp poles / signs. ───────────────────────────
    _drawStationPoles(canvas, w, vanishingY, trackBottomY);

    // ── Side props (crates, barrels, cacti, lamps). ────────────
    _drawSideProps(canvas, size);

    // ── Entities (sorted by z, far first). ────────────────────
    final all = <_DrawnEntity>[];
    for (final o in obstacles) {
      all.add(_DrawnEntity(z: o.z, draw: (c) => _drawObstacle(c, o)));
    }
    for (final c in coins) {
      all.add(_DrawnEntity(z: c.z, draw: (c2) => _drawCoin(c2, c)));
    }
    for (final p in powerUps) {
      all.add(_DrawnEntity(z: p.z, draw: (c2) => _drawPowerUp(c2, p)));
    }
    all.sort((a, b) => a.z.compareTo(b.z));
    for (final e in all) {
      e.draw(canvas);
    }

    // ── Player. ──────────────────────────────────────────────
    _drawPlayer(canvas);

    // ── Dust puffs. ──────────────────────────────────────────
    for (final d in dustPuffs) {
      final alpha = (d.life / 0.5).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(d.x, d.y),
        d.r,
        Paint()..color = const Color(0xFFE0E0E0).withValues(alpha: alpha * 0.6),
      );
    }

    // ── Sparkles. ────────────────────────────────────────────
    for (final s in sparkles) {
      final alpha = (s.life / 0.7).clamp(0.0, 1.0);
      for (var i = 0; i < 4; i++) {
        final a = s.phase + (i / 4) * 2 * pi;
        final px = s.x + cos(a) * (8 + s.r);
        final py = s.y + sin(a) * (8 + s.r);
        canvas.drawCircle(
          Offset(px, py),
          2.2,
          Paint()..color = s.color.withValues(alpha: alpha),
        );
      }
    }

    // ── Snap-to-counter coins. ───────────────────────────────
    final hudTarget = Offset(w - 60, 32);
    for (final sc in snapCoins) {
      final easedT = Curves.easeInCubic.transform(sc.t);
      final x = sc.fromX + (hudTarget.dx - sc.fromX) * easedT;
      final y =
          sc.fromY + (hudTarget.dy - sc.fromY) * easedT - 60 * sin(sc.t * pi);
      canvas.drawCircle(
        Offset(x, y),
        5,
        Paint()..color = const Color(0xFFFFC529).withValues(alpha: 1 - sc.t * 0.5),
      );
    }

    // ── Speed lines. ─────────────────────────────────────────
    if (speed > 380) {
      for (final sl in speedLines) {
        final alpha = (sl.life / 0.6).clamp(0.0, 1.0);
        canvas.drawLine(
          Offset(sl.x, sl.y),
          Offset(sl.x + (sl.x < w / 2 ? 6 : -6), sl.y + sl.length),
          Paint()
            ..color = Colors.white.withValues(alpha: alpha * 0.6)
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    // ── Floaters. ────────────────────────────────────────────
    for (final f in floaters) {
      final alpha = (f.life / 1.0).clamp(0.0, 1.0);
      final tp = TextPainter(
        text: TextSpan(
          text: f.text,
          style: TextStyle(
            color: f.color.withValues(alpha: alpha),
            fontSize: 16,
            fontWeight: FontWeight.w900,
            shadows: const [
              Shadow(blurRadius: 4, color: Colors.black87),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(f.x - tp.width / 2, f.y - tp.height / 2));
    }
  }

  // ─────────────────────────────────────────────────────────
  // Sky + skyline
  // ─────────────────────────────────────────────────────────

  void _drawSun(Canvas canvas, Size size) {
    final c = Offset(size.width * 0.82, size.height * 0.10);
    // Outer halo.
    canvas.drawCircle(
      c,
      42,
      Paint()
        ..color = const Color(0xFFFEF3C7).withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawCircle(
      c,
      30,
      Paint()
        ..color = const Color(0xFFFEF3C7).withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(
      c,
      22,
      Paint()..color = const Color(0xFFFACC15),
    );
    canvas.drawCircle(
      c,
      14,
      Paint()..color = const Color(0xFFFFFBEB),
    );
  }

  void _drawClouds(Canvas canvas, Size size) {
    final cloudPaint = Paint()..color = Colors.white.withValues(alpha: 0.85);
    final cloudShadow = Paint()..color = const Color(0xFFCBD5E1).withValues(alpha: 0.45);
    final period = size.width * 0.6;
    final scroll = cloudScroll % period;
    for (var i = 0; i < 5; i++) {
      final r = Random(11 + i);
      final baseX = -period + scroll + i * period * 0.55;
      final baseY = size.height * (0.04 + r.nextDouble() * 0.10);
      final w = size.width * (0.18 + r.nextDouble() * 0.06);
      _paintCloud(canvas, Offset(baseX, baseY), w, 22, cloudPaint, cloudShadow);
    }
  }

  void _paintCloud(
    Canvas canvas,
    Offset c,
    double w,
    double h,
    Paint paint,
    Paint shadow,
  ) {
    final r = h * 0.45;
    final circles = [
      (c.translate(r, -r * 0.3), r),
      (c.translate(w * 0.4, -r * 0.7), r * 1.05),
      (c.translate(w * 0.75, -r * 0.4), r * 0.9),
      (c.translate(w * 0.95, r * 0.05), r * 0.7),
    ];
    for (final p in circles) {
      canvas.drawCircle(p.$1, p.$2, shadow);
    }
    for (final p in circles) {
      canvas.drawCircle(p.$1, p.$2, paint);
    }
  }

  void _drawSkylineLayer(
    Canvas canvas,
    Size size, {
    required double baseY,
    required double scroll,
    required int seed,
    required Color buildingColor,
    required Color accent,
    required Color windowColor,
    required double buildingWidth,
    required double maxHeight,
  }) {
    final rng = Random(seed);
    final paint = Paint()..color = buildingColor;
    final accentPaint = Paint()..color = accent.withValues(alpha: 0.7);
    final winPaint = Paint()..color = windowColor.withValues(alpha: 0.85);
    final period = buildingWidth * 1.4;
    final scrollOffset = scroll % period;
    for (var x = -period + scrollOffset;
        x < size.width + period;
        x += period) {
      final h = maxHeight * (0.5 + rng.nextDouble() * 0.5);
      final w = buildingWidth * (0.8 + rng.nextDouble() * 0.4);
      final rect = Rect.fromLTWH(x, baseY - h, w, h);
      canvas.drawRect(rect, paint);
      // Antenna on taller buildings.
      if (h > maxHeight * 0.7) {
        canvas.drawRect(
          Rect.fromLTWH(x + w * 0.5 - 1, baseY - h - 8, 2, 8),
          accentPaint,
        );
      }
      // Window grid.
      final cols = (w / 7).floor();
      final rows = (h / 9).floor();
      for (var c = 0; c < cols; c++) {
        for (var r = 0; r < rows; r++) {
          if (rng.nextDouble() < 0.5) {
            canvas.drawRect(
              Rect.fromLTWH(
                rect.left + 2 + c * 7,
                rect.top + 2 + r * 9,
                4,
                5,
              ),
              winPaint,
            );
          }
        }
      }
    }
  }

  // ─────────────────────────────────────────────────────────
  // Track geometry
  // ─────────────────────────────────────────────────────────

  void _drawTies(
    Canvas canvas,
    double w,
    double h,
    double vanishingX,
    double vanishingY,
    double trackTopHalf,
    double trackBottomHalf,
    double trackBottomY,
  ) {
    // Wooden railroad ties.
    final tiePaint = Paint()..color = const Color(0xFF6B4423);
    final tieShine = Paint()..color = const Color(0xFF8B5A2B);
    final tieSpacing = 22.0;
    final scroll = tieScroll % tieSpacing;
    for (var y = -tieSpacing + scroll;
        y < h + tieSpacing;
        y += tieSpacing) {
      // Compute pseudo z from y.
      final z = ((y - vanishingY) / (trackBottomY - vanishingY)).clamp(0.0, 1.0);
      final half = trackTopHalf + (trackBottomHalf - trackTopHalf) * z;
      final specIdx = (y ~/ tieSpacing) % railSpecs.length;
      final spec = railSpecs[specIdx < 0 ? specIdx + railSpecs.length : specIdx];
      final width = (half * 2) - 6;
      final ty = y + spec.heightOffset;
      if (ty < vanishingY - 4) continue;
      final rect = Rect.fromLTWH(
        vanishingX - half + 3,
        ty - 1.6,
        width,
        3.2,
      );
      canvas.drawRect(rect, tiePaint);
      canvas.drawRect(
        Rect.fromLTWH(rect.left, rect.top, rect.width, 0.8),
        Paint()..color = tieShine.color.withValues(alpha: spec.shineAlpha),
      );
    }
  }

  void _drawRails(
    Canvas canvas,
    double vanishingY,
    double vanishingX,
    double trackBottomY,
    double trackTopHalf,
    double trackBottomHalf,
  ) {
    final railSteel = Paint()..color = const Color(0xFFB0BEC5);
    final railShine = Paint()..color = const Color(0xFFECEFF1);
    for (final offset in [-0.4, 0.4]) {
      // Top rail — a thin gleaming bar at +offset / -offset * trackHalfWidth.
      for (var i = 0; i < 28; i++) {
        final z = (i + 1) / 28.0;
        final y = vanishingY + (trackBottomY - vanishingY) * z;
        final half = trackTopHalf + (trackBottomHalf - trackTopHalf) * z;
        final x = vanishingX + offset * half;
        if (y > trackBottomY + 4) continue;
        // Rail cross-section: thin rectangle aligned along z.
        final railRect = Rect.fromLTWH(x - 1.5, y - 1.5, 3, 3);
        canvas.drawRect(railRect, railSteel);
        canvas.drawRect(
          Rect.fromLTWH(x - 0.5, y - 1.5, 1, 3),
          railShine,
        );
      }
    }
    // Rail tie plates (metal straps on each tie).
    final platePaint = Paint()..color = const Color(0xFF455A64);
    final tieSpacing = 22.0;
    final scroll = tieScroll % tieSpacing;
    for (var y = -tieSpacing + scroll;
        y < trackBottomY + tieSpacing;
        y += tieSpacing) {
      final z = ((y - vanishingY) / (trackBottomY - vanishingY)).clamp(0.0, 1.0);
      final half = trackTopHalf + (trackBottomHalf - trackTopHalf) * z;
      for (final offset in [-0.4, 0.4]) {
        final x = vanishingX + offset * half;
        canvas.drawRect(
          Rect.fromLTWH(x - 3, y - 2, 6, 4),
          platePaint,
        );
      }
    }
  }

  void _drawLaneStripes(Canvas canvas) {
    final dashPaint = Paint()
      ..color = const Color(0xFFFACC15)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    const dashLen = 18.0;
    const dashGap = 14.0;
    for (final laneEdge in [-0.5, 0.5]) {
      final startTop = projectToScreen(laneEdge * 2, 0, 0);
      final endBottom = projectToScreen(laneEdge * 2, 0, 1);
      final totalLen = (endBottom - startTop).distance;
      final segments = (totalLen / (dashLen + dashGap)).floor();
      final scrollPx = (envScroll * 0.5) % (dashLen + dashGap);
      for (var i = 0; i < segments; i++) {
        final t0 = (i * (dashLen + dashGap) + scrollPx) / totalLen;
        final t1 = (i * (dashLen + dashGap) + scrollPx + dashLen) / totalLen;
        if (t1 > 1) continue;
        final p0 = Offset.lerp(startTop, endBottom, t0.clamp(0.0, 1.0))!;
        final p1 = Offset.lerp(startTop, endBottom, t1.clamp(0.0, 1.0))!;
        canvas.drawLine(p0, p1, dashPaint);
      }
    }
  }

  void _drawPlatformKerbs(
    Canvas canvas,
    Size size,
    double vanishingY,
    double trackBottomY,
  ) {
    // Yellow safety strip along both platform edges.
    final stripPaint = Paint()..color = const Color(0xFFFACC15);
    final kerbPaint = Paint()..color = const Color(0xFF37474F);
    // Left kerb trapezoid.
    final leftPath = Path()
      ..moveTo(0, vanishingY)
      ..lineTo(size.width * 0.06, vanishingY)
      ..lineTo(size.width * 0.075, trackBottomY)
      ..lineTo(0, trackBottomY)
      ..close();
    canvas.drawPath(leftPath, kerbPaint);
    // Right kerb.
    final rightPath = Path()
      ..moveTo(size.width, vanishingY)
      ..lineTo(size.width * 0.94, vanishingY)
      ..lineTo(size.width * 0.925, trackBottomY)
      ..lineTo(size.width, trackBottomY)
      ..close();
    canvas.drawPath(rightPath, kerbPaint);
    // Yellow warning strip at the inner edge of each kerb.
    canvas.drawRect(
      Rect.fromLTWH(
          size.width * 0.06, vanishingY, size.width * 0.018, trackBottomY - vanishingY),
      stripPaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(
          size.width * 0.922, vanishingY, size.width * 0.018, trackBottomY - vanishingY),
      stripPaint,
    );
  }

  void _drawStationPoles(
    Canvas canvas,
    double w,
    double vanishingY,
    double trackBottomY,
  ) {
    final polePaint = Paint()..color = const Color(0xFF263238);
    final signPaint = Paint()..color = const Color(0xFFEF4444);
    final poleSpacing = 130.0;
    final scroll = poleScroll % poleSpacing;
    for (var x = -poleSpacing + scroll;
        x < w + poleSpacing;
        x += poleSpacing) {
      // Pole.
      canvas.drawRect(
        Rect.fromLTWH(x - 1.5, vanishingY + 4, 3, trackBottomY - vanishingY - 8),
        polePaint,
      );
      // Sign at top.
      canvas.drawRect(
        Rect.fromLTWH(x - 18, vanishingY - 6, 36, 14),
        signPaint,
      );
      // Sign text "STATION".
      final tp = TextPainter(
        text: const TextSpan(
          text: 'STATION',
          style: TextStyle(
            color: Colors.white,
            fontSize: 8,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, vanishingY - 6));
    }
  }

  // ─────────────────────────────────────────────────────────
  // Side props — crates, barrels, cacti, lamps that parallax
  // along the track edges so the world feels populated.
  // ─────────────────────────────────────────────────────────

  void _drawSideProps(Canvas canvas, Size canvasSize) {
    if (sideProps.isEmpty) return;
    // Hoist per-frame geometry — identical for every prop on this
    // canvas — so each _drawSideProp call reuses them.
    final vanishingY = canvasSize.height * 0.22;
    final trackBottomY = canvasSize.height - 40;
    final trackTopHalf = canvasSize.width * 0.06;
    final trackBottomHalf = canvasSize.width * 0.475;
    // Iterate in insertion order: new props spawn at the vanishing
    // point (z=0) and z only grows, so this list is already roughly
    // back-to-front. Cloning + sorting every frame was hot-path
    // churn for no visible win.
    for (final p in sideProps) {
      _drawSideProp(
        canvas,
        p,
        canvasSize,
        vanishingY: vanishingY,
        trackBottomY: trackBottomY,
        trackTopHalf: trackTopHalf,
        trackBottomHalf: trackBottomHalf,
      );
    }
  }

  void _drawSideProp(
    Canvas canvas,
    _SideProp p,
    Size canvasSize, {
    required double vanishingY,
    required double trackBottomY,
    required double trackTopHalf,
    required double trackBottomHalf,
  }) {
    if (p.z <= 0.02 || p.z > 1.05) return;
    // Sample the half-width at this z so the prop sits just outside
    // the rail.
    final t = p.z.clamp(0.0, 1.0);
    final half = trackTopHalf + (trackBottomHalf - trackTopHalf) * t;
    final ty = vanishingY + (trackBottomY - vanishingY) * t;
    // x position — outside the rail by `propGap` pixels, scaled with z.
    final propGap = (1.0 - t) * 60 + 28;
    final cx = canvasSize.width / 2 + p.side * (half + propGap);
    // Size grows with z.
    final baseSize = 18 + t * 38;
    // Shadow.
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, ty + 4), width: baseSize * 1.3, height: 4),
      Paint()..color = Colors.black.withValues(alpha: 0.30 * t),
    );
    switch (p.kind) {
      case _PropKind.crate:
        _drawCrate(canvas, Offset(cx, ty), baseSize, p.variant);
      case _PropKind.barrel:
        _drawBarrel(canvas, Offset(cx, ty), baseSize, p.variant);
      case _PropKind.cactus:
        _drawCactus(canvas, Offset(cx, ty), baseSize, p.variant);
      case _PropKind.lamp:
        _drawLamp(canvas, Offset(cx, ty), baseSize, p.variant);
    }
  }

  void _drawCrate(Canvas canvas, Offset pos, double s, int variant) {
    final rect = Rect.fromCenter(center: pos.translate(0, -s * 0.4), width: s, height: s);
    // Body.
    canvas.drawRect(
      rect,
      Paint()..color = const Color(0xFFB45309),
    );
    // Plank lines.
    final plank = Paint()
      ..color = const Color(0xFF7C2D12)
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(rect.left, rect.top + s * 0.33),
        Offset(rect.right, rect.top + s * 0.33), plank);
    canvas.drawLine(Offset(rect.left, rect.top + s * 0.66),
        Offset(rect.right, rect.top + s * 0.66), plank);
    canvas.drawLine(Offset(rect.center.dx, rect.top),
        Offset(rect.center.dx, rect.bottom), plank);
    // Highlight on the top edge.
    canvas.drawRect(
      Rect.fromLTWH(rect.left, rect.top, rect.width, 2),
      Paint()..color = const Color(0xFFFCD34D),
    );
    // Stamp on the front (rotates by variant).
    if (variant.isEven) {
      canvas.drawCircle(pos.translate(0, -s * 0.4), s * 0.18,
          Paint()..color = const Color(0xFFFCD34D));
    } else {
      final tri = Path()
        ..moveTo(pos.dx - s * 0.18, pos.dy - s * 0.2)
        ..lineTo(pos.dx + s * 0.18, pos.dy - s * 0.2)
        ..lineTo(pos.dx, pos.dy - s * 0.6)
        ..close();
      canvas.drawPath(tri, Paint()..color = const Color(0xFFFCD34D));
    }
  }

  void _drawBarrel(Canvas canvas, Offset pos, double s, int variant) {
    final r = s * 0.4;
    final rect = Rect.fromCenter(center: pos.translate(0, -s * 0.45), width: s * 0.9, height: s);
    // Body — rounded.
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(r)),
      Paint()..color = const Color(0xFF92400E),
    );
    // Metal bands.
    final band = Paint()
      ..color = const Color(0xFF1F2937)
      ..strokeWidth = 2;
    canvas.drawLine(Offset(rect.left, rect.top + s * 0.25),
        Offset(rect.right, rect.top + s * 0.25), band);
    canvas.drawLine(Offset(rect.left, rect.top + s * 0.75),
        Offset(rect.right, rect.top + s * 0.75), band);
    // Top rim.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(rect.center.dx, rect.top),
        width: rect.width,
        height: 4,
      ),
      Paint()..color = const Color(0xFFFBBF24),
    );
  }

  void _drawCactus(Canvas canvas, Offset pos, double s, int variant) {
    // Trunk.
    final trunk = Rect.fromCenter(
      center: pos.translate(0, -s * 0.5),
      width: s * 0.35,
      height: s,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(trunk, Radius.circular(s * 0.15)),
      Paint()..color = const Color(0xFF15803D),
    );
    // Two arms — one each side at different heights based on variant.
    final armW = s * 0.18;
    final armH = s * 0.45;
    if (variant.isEven) {
      // Right arm high.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(trunk.right, trunk.top + s * 0.10, armW + s * 0.15, armH),
          Radius.circular(s * 0.08),
        ),
        Paint()..color = const Color(0xFF15803D),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(trunk.right + s * 0.15, trunk.top + s * 0.10 + armH * 0.5,
              armW, armH * 0.5),
          Radius.circular(s * 0.08),
        ),
        Paint()..color = const Color(0xFF15803D),
      );
    } else {
      // Left arm low.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(trunk.left - s * 0.33, trunk.top + s * 0.30, armW + s * 0.15, armH),
          Radius.circular(s * 0.08),
        ),
        Paint()..color = const Color(0xFF15803D),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(trunk.left - armW, trunk.top + s * 0.30 + armH * 0.5,
              armW, armH * 0.5),
          Radius.circular(s * 0.08),
        ),
        Paint()..color = const Color(0xFF15803D),
      );
    }
    // Top highlight.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(trunk.left + 1, trunk.top, trunk.width - 2, s * 0.4),
        Radius.circular(s * 0.15),
      ),
      Paint()..color = const Color(0xFF22C55E).withValues(alpha: 0.5),
    );
  }

  void _drawLamp(Canvas canvas, Offset pos, double s, int variant) {
    // Post.
    canvas.drawRect(
      Rect.fromCenter(center: pos.translate(0, -s * 0.5), width: 2, height: s),
      Paint()..color = const Color(0xFF1F2937),
    );
    // Cross-arm.
    canvas.drawRect(
      Rect.fromCenter(center: pos.translate(0, -s * 0.9), width: s * 0.5, height: 1.5),
      Paint()..color = const Color(0xFF1F2937),
    );
    // Lantern.
    final lantern = Rect.fromCenter(
      center: pos.translate(s * 0.22, -s * 0.9),
      width: s * 0.20,
      height: s * 0.25,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(lantern, Radius.circular(2)),
      Paint()..color = const Color(0xFFFCD34D),
    );
    // Glow.
    canvas.drawCircle(
      lantern.center,
      s * 0.18,
      Paint()..color = const Color(0xFFFEF3C7).withValues(alpha: 0.4),
    );
  }

  // ─────────────────────────────────────────────────────────
  // Player
  // ─────────────────────────────────────────────────────────

  void _drawPlayer(Canvas canvas) {
    final u = Curves.easeOutCubic.transform(laneAnimT);
    final renderedLane = lane + (targetLane - lane) * u;
    // Visual z — drawn at z=0.65 (mid-foreground) so the character
    // sits roughly center-vertical rather than pressed against the
    // bottom edge. Collision math still uses z=1 (collision window is
    // 0.82-1.06), so this is a render-only adjustment.
    final pos = projectToScreen(renderedLane - 1.0, yOffset, 0.65);
    // Roll/somersault shrinks the height modestly so the rotation
    // reads cleanly without the body becoming a flat pancake.
    final baseH = sliding ? 48.0 : 64.0;
    final baseW = 32.0;
    final shadowScale = 1 + (yOffset / 200).abs() * 0.3;

    canvas.save();
    final tilt = (crashTimer > 0) ? ragdollAngle : bankTilt;
    canvas.translate(pos.dx, pos.dy);
    if (crashTimer > 0) {
      canvas.translate(
        sin(ragdollT * pi) * 40,
        (ragdollT * 80),
      );
    }
    canvas.rotate(tilt);

    // Shadow stays on the ground — drawn before any body transform so
    // it doesn't rotate or tuck with the rest of the character.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(0, baseH / 2 + 18),
        width: 30 * shadowScale,
        height: 8 * shadowScale,
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.4),
    );

    // Body transform — applied to everything from the hoverboard down
    // through the face. Slide = forward somersault (1+ revolution),
    // mid-jump = leg-tuck (vertical compression at apex) so the
    // character reads as "knees bent" at the top of the arc.
    canvas.save();
    if (sliding && crashTimer <= 0) {
      // Forward roll: rotate around the body's center mass (≈ y=0,
      // which sits between the legs and the chest). slideTime counts
      // down from 0.6 → 0, so the rotation goes 0 → 2π over 0.6s.
      canvas.rotate((0.6 - slideTime) * 2 * pi / 0.6);
    } else if (yOffset < -10 && crashTimer <= 0) {
      // Leg-tuck: peak compression at apex (jumpElapsed ≈ 0.4s with
      // current gravity). Triangle wave over the jump duration so the
      // character fully extends at launch and landing, knees bent at
      // apex. Max compression = 0.7 (legs tucked to 70% of standing).
      final apexT = (jumpElapsed / 0.4).clamp(0.0, 1.0);
      final compression = 0.15 * (1 - (apexT - 0.5).abs() * 2).clamp(0.0, 1.0);
      canvas.translate(0, baseH * 0.5);
      canvas.scale(1.0, 1.0 - compression);
      canvas.translate(0, -baseH * 0.5);
    }

    // Hoverboard plank.
    if (hoverboardActive) {
      final pulse = sin(idleTime * 8) * 0.5 + 0.5;
      final boardRect = Rect.fromCenter(
          center: Offset(0, baseH / 2 + 12), width: 56, height: 8);
      canvas.drawRRect(
        RRect.fromRectAndRadius(boardRect, const Radius.circular(4)),
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xFF22D3EE), Color(0xFF0EA5E9)],
          ).createShader(boardRect),
      );
      for (var i = 0; i < 3; i++) {
        canvas.drawCircle(
          Offset(0, baseH / 2 + 18 + i * 6 + sin(idleTime * 12 + i) * 2),
          2.5 - i * 0.6,
          Paint()
            ..color = const Color(0xFF22D3EE).withValues(alpha: (1 - i / 3) * (0.5 + pulse * 0.5)),
        );
      }
    }

    // ── Sneakers (red trainers with white sole). ─────────────
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(-8, baseH / 2 + 4), width: 14, height: 10),
        const Radius.circular(3),
      ),
      Paint()..color = const Color(0xFFEF4444),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(8, baseH / 2 + 4), width: 14, height: 10),
        const Radius.circular(3),
      ),
      Paint()..color = const Color(0xFFEF4444),
    );
    // White soles.
    canvas.drawRect(
      Rect.fromCenter(center: Offset(-8, baseH / 2 + 9), width: 14, height: 2),
      Paint()..color = Colors.white,
    );
    canvas.drawRect(
      Rect.fromCenter(center: Offset(8, baseH / 2 + 9), width: 14, height: 2),
      Paint()..color = Colors.white,
    );

    if (!sliding) {
      // ── Legs (blue jeans). ─────────────────────────────────
      canvas.drawRect(
        Rect.fromCenter(center: const Offset(-7, 14), width: 10, height: 20),
        Paint()..color = const Color(0xFF1E3A8A),
      );
      canvas.drawRect(
        Rect.fromCenter(center: const Offset(7, 14), width: 10, height: 20),
        Paint()..color = const Color(0xFF1E3A8A),
      );

      // ── Hoodie body (red, with cream logo dot). ────────────
      final bodyRect = Rect.fromCenter(
          center: const Offset(0, -2), width: baseW, height: 32);
      canvas.drawRRect(
        RRect.fromRectAndRadius(bodyRect, const Radius.circular(8)),
        Paint()..color = const Color(0xFFDC2626),
      );
      // Cream logo dot.
      canvas.drawCircle(
        const Offset(0, -2),
        4,
        Paint()..color = const Color(0xFFFEF3C7),
      );

      // ── Arms. ──────────────────────────────────────────────
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: const Offset(-18, 0), width: 8, height: 24),
          const Radius.circular(4),
        ),
        Paint()..color = const Color(0xFFB91C1C),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: const Offset(18, 0), width: 8, height: 24),
          const Radius.circular(4),
        ),
        Paint()..color = const Color(0xFFB91C1C),
      );
      // Hands.
      canvas.drawCircle(
        const Offset(-18, 12),
        4,
        Paint()..color = const Color(0xFFFCD34D),
      );
      canvas.drawCircle(
        const Offset(18, 12),
        4,
        Paint()..color = const Color(0xFFFCD34D),
      );

      // ── Backpack strap (over one shoulder). ────────────────
      canvas.drawRect(
        Rect.fromLTWH(-10, -16, 4, 26),
        Paint()..color = const Color(0xFF1F2937),
      );
      canvas.drawRect(
        Rect.fromLTWH(10, -16, 4, 26),
        Paint()..color = const Color(0xFF1F2937),
      );

      // ── Head (skin). ───────────────────────────────────────
      canvas.drawCircle(
        const Offset(0, -22),
        11,
        Paint()..color = const Color(0xFFFCD34D),
      );
      // Hair tuft.
      canvas.drawArc(
        Rect.fromCenter(center: const Offset(0, -28), width: 18, height: 8),
        pi,
        pi,
        true,
        Paint()..color = const Color(0xFF1F2937),
      );
      // ── Cap (red brim). ────────────────────────────────────
      final capRect = Rect.fromCenter(
          center: const Offset(0, -32), width: 24, height: 6);
      canvas.drawRRect(
        RRect.fromRectAndRadius(capRect, const Radius.circular(2)),
        Paint()..color = const Color(0xFFDC2626),
      );
      // Cap peak (forward).
      canvas.drawRect(
        Rect.fromLTWH(8, -32, 8, 3),
        Paint()..color = const Color(0xFFB91C1C),
      );
      // ── Face: eyes + smile. ────────────────────────────────
      if (crashTimer <= 0) {
        canvas.drawCircle(
          const Offset(-4, -22),
          1.6,
          Paint()..color = const Color(0xFF1F2937),
        );
        canvas.drawCircle(
          const Offset(4, -22),
          1.6,
          Paint()..color = const Color(0xFF1F2937),
        );
        canvas.drawArc(
          Rect.fromCenter(center: const Offset(0, -18), width: 6, height: 4),
          0,
          pi,
          false,
          Paint()
            ..color = const Color(0xFF1F2937)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4,
        );
      } else {
        // X-eyes on crash.
        _drawXEye(canvas, const Offset(-4, -22), 2);
        _drawXEye(canvas, const Offset(4, -22), 2);
      }
    }
    canvas.restore(); // body transform — speed-trail / auras draw in
                      // world space, not rotated with the body.

    // Speed-trail streak when jumping.
    if (yOffset < -20) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(0, baseH), width: baseW * 0.8, height: 30),
          const Radius.circular(4),
        ),
        Paint()
          ..color = const Color(0xFFEF4444).withValues(alpha: 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
    // Sneaker aura.
    if (sneakerActive) {
      canvas.drawCircle(
        const Offset(0, 0),
        34 + 4 * sin(idleTime * 8),
        Paint()
          ..color = const Color(0xFFFACC15).withValues(alpha: 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
    // Magnet aura.
    if (magnetActive) {
      canvas.drawCircle(
        const Offset(0, 4),
        64 + 6 * sin(magnetTime * 8),
        Paint()
          ..color = const Color(0xFFA073FF).withValues(alpha: 0.30)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
    canvas.restore();
  }

  void _drawXEye(Canvas canvas, Offset center, double r) {
    final paint = Paint()
      ..color = const Color(0xFF1F2937)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    canvas.drawLine(center.translate(-r, -r), center.translate(r, r), paint);
    canvas.drawLine(center.translate(-r, r), center.translate(r, -r), paint);
  }

  // ─────────────────────────────────────────────────────────
  // Entity drawers
  // ─────────────────────────────────────────────────────────

  void _drawObstacle(Canvas canvas, _Obstacle o) {
    if (o.z < 0) return;
    final pos = projectToScreen(o.laneOffset, 0, o.z);
    final scale = (0.25 + 0.75 * o.z).clamp(0.0, 1.5);
    // Shadow.
    canvas.drawCircle(
      Offset(pos.dx, pos.dy + 28 * scale),
      30 * scale,
      Paint()..color = Colors.black.withValues(alpha: 0.4),
    );
    switch (o.kind) {
      case _ObstacleKind.hurdle:
        _drawHurdle(canvas, pos, scale);
        break;
      case _ObstacleKind.signalBarrier:
        _drawSignalBarrier(canvas, pos, scale);
        break;
      case _ObstacleKind.train:
        _drawTrain(canvas, pos, scale, oncoming: false);
        break;
      case _ObstacleKind.oncomingTrain:
        _drawTrain(canvas, pos, scale, oncoming: true);
        break;
      case _ObstacleKind.trackBuffer:
        _drawTrackBuffer(canvas, pos, scale);
        break;
    }
  }

  void _drawHurdle(Canvas canvas, Offset pos, double scale) {
    final w = 72 * scale;
    final h = 18 * scale;
    final rect = Rect.fromCenter(center: pos, width: w, height: h);
    // Wooden beam.
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()..color = const Color(0xFFB45309),
    );
    // Wood grain stripes.
    final grain = Paint()
      ..color = const Color(0xFF78350F).withValues(alpha: 0.6)
      ..strokeWidth = 1 * scale;
    for (var i = 0; i < 4; i++) {
      canvas.drawLine(
        Offset(rect.left + 4 + i * (w - 8) / 4, rect.top + 2),
        Offset(rect.left + 4 + i * (w - 8) / 4, rect.bottom - 2),
        grain,
      );
    }
    // Posts.
    canvas.drawRect(
      Rect.fromCenter(center: Offset(rect.left + 4, pos.dy), width: 4, height: h + 14),
      Paint()..color = const Color(0xFF78350F),
    );
    canvas.drawRect(
      Rect.fromCenter(center: Offset(rect.right - 4, pos.dy), width: 4, height: h + 14),
      Paint()..color = const Color(0xFF78350F),
    );
    // Yellow chevron stripes (warning tape).
    final chev = Paint()
      ..color = const Color(0xFFFACC15)
      ..strokeWidth = 2 * scale;
    for (var i = 0; i < 4; i++) {
      canvas.drawLine(
        Offset(rect.left + 4 + i * (w - 8) / 4, rect.top + 2),
        Offset(rect.left + 8 + i * (w - 8) / 4, rect.bottom - 2),
        chev,
      );
    }
  }

  void _drawSignalBarrier(Canvas canvas, Offset pos, double scale) {
    final w = 50 * scale;
    final h = 100 * scale;
    final topY = pos.dy - h / 2;
    // Posts.
    canvas.drawRect(
      Rect.fromLTWH(pos.dx - w / 2, topY, 5, h),
      Paint()..color = const Color(0xFF263238),
    );
    canvas.drawRect(
      Rect.fromLTWH(pos.dx + w / 2 - 5, topY, 5, h),
      Paint()..color = const Color(0xFF263238),
    );
    // Top sign with chevrons.
    final signRect = Rect.fromLTWH(pos.dx - w / 2, topY, w, 24 * scale);
    canvas.drawRect(signRect, Paint()..color = const Color(0xFFEF4444));
    final chev = Paint()
      ..color = Colors.white
      ..strokeWidth = 2 * scale
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < 3; i++) {
      canvas.drawLine(
        Offset(signRect.left + 4 + i * w / 4, signRect.top + 2),
        Offset(signRect.left + 8 + i * w / 4, signRect.bottom - 2),
        chev,
      );
    }
    // Mid clearance bar — yellow/black striped.
    final midRect = Rect.fromCenter(
      center: Offset(pos.dx, topY + h * 0.6),
      width: w * 1.15,
      height: 7 * scale,
    );
    canvas.drawRect(midRect, Paint()..color = const Color(0xFFFACC15));
    final stripe = Paint()..color = const Color(0xFF1F2937);
    final stripeW = w * 1.15 / 6;
    for (var i = 0; i < 6; i += 2) {
      canvas.drawRect(
        Rect.fromLTWH(midRect.left + i * stripeW, midRect.top, stripeW, midRect.height),
        stripe,
      );
    }
  }

  void _drawTrackBuffer(Canvas canvas, Offset pos, double scale) {
    final w = 72 * scale;
    final h = 50 * scale;
    final rect = Rect.fromCenter(center: pos, width: w, height: h);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      Paint()..color = const Color(0xFFFACC15),
    );
    final stripe = Paint()..color = const Color(0xFF1F2937);
    final stripeW = w / 6;
    for (var i = 0; i < 6; i += 2) {
      canvas.drawRect(
        Rect.fromLTWH(rect.left + i * stripeW, rect.top, stripeW, h),
        stripe,
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      Paint()
        ..color = Colors.black87
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * scale,
    );
  }

  void _drawTrain(Canvas canvas, Offset pos, double scale,
      {required bool oncoming}) {
    final rect = Rect.fromCenter(
      center: pos,
      width: 96 * scale,
      height: 110 * scale,
    );
    // Drop shadow.
    canvas.drawRect(
      rect.translate(0, 4 * scale),
      Paint()..color = Colors.black.withValues(alpha: 0.4),
    );
    // Body — bright orange + cream livery.
    canvas.drawRect(rect, Paint()..color = const Color(0xFFFB923C));
    // Yellow front band.
    if (oncoming) {
      canvas.drawRect(
        Rect.fromLTWH(rect.left, rect.bottom - 20 * scale,
            rect.width, 20 * scale),
        Paint()..color = const Color(0xFFFACC15),
      );
      // Big windshield.
      canvas.drawRect(
        Rect.fromLTWH(rect.left + 16 * scale, rect.top + 18 * scale,
            rect.width - 32 * scale, 22 * scale),
        Paint()..color = const Color(0xFF1E40AF),
      );
      // Window frame.
      canvas.drawRect(
        Rect.fromLTWH(rect.left + 16 * scale, rect.top + 18 * scale,
            rect.width - 32 * scale, 22 * scale),
        Paint()
          ..color = const Color(0xFF1F2937)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2 * scale,
      );
    } else {
      // Side view: roof stripe.
      canvas.drawRect(
        Rect.fromLTWH(rect.left, rect.top, rect.width, 6 * scale),
        Paint()..color = const Color(0xFFFACC15),
      );
      // Window strip (passenger windows).
      canvas.drawRect(
        Rect.fromLTWH(rect.left + 4 * scale, rect.top + 14 * scale,
            rect.width - 8 * scale, 16 * scale),
        Paint()..color = const Color(0xFF1E40AF),
      );
      // Door.
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(rect.center.dx, rect.top + rect.height * 0.55),
          width: 18 * scale,
          height: 36 * scale,
        ),
        Paint()..color = const Color(0xFFEA580C),
      );
      // Door window.
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(rect.center.dx, rect.top + rect.height * 0.42),
          width: 12 * scale,
          height: 8 * scale,
        ),
        Paint()..color = const Color(0xFF93C5FD),
      );
      // Lower windows.
      for (var i = 0; i < 3; i++) {
        canvas.drawRect(
          Rect.fromLTWH(
            rect.left + 8 * scale + i * 26 * scale,
            rect.top + 36 * scale,
            18 * scale,
            14 * scale,
          ),
          Paint()..color = const Color(0xFF1E40AF),
        );
      }
    }
    // Headlights.
    for (final dx in [-rect.width * 0.25, rect.width * 0.25]) {
      canvas.drawCircle(
        Offset(pos.dx + dx, rect.bottom - 6 * scale),
        4 * scale,
        Paint()..color = const Color(0xFFFEF3C7),
      );
      if (oncoming) {
        final cone = Path()
          ..moveTo(pos.dx + dx, rect.bottom - 6 * scale)
          ..lineTo(pos.dx + dx - 10 * scale, rect.bottom + 26 * scale)
          ..lineTo(pos.dx + dx + 10 * scale, rect.bottom + 26 * scale)
          ..close();
        canvas.drawPath(
          cone,
          Paint()
            ..color = const Color(0xFFFEF3C7).withValues(alpha: 0.28)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
      }
    }
    // Border.
    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.black87
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * scale,
    );
    // "LINE 1" text on side.
    if (!oncoming) {
      final tp = TextPainter(
        text: TextSpan(
          text: 'LINE 1',
          style: TextStyle(
            color: Colors.white,
            fontSize: 10 * scale,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(rect.left + 8, rect.top + 26 * scale));
    }
  }

  void _drawCoin(Canvas canvas, _CoinSprite c) {
    if (c.z < 0) return;
    final pos = projectToScreen(c.laneOffset, 0, c.z) + Offset(c.x, c.y);
    final scale = (0.25 + 0.75 * c.z).clamp(0.0, 1.5);
    final bob = sin(c.bob) * 3 * scale;
    final r = 12 * scale;
    final xs = cos(c.phase).abs();
    // Shadow.
    canvas.drawCircle(
      Offset(pos.dx, pos.dy + r * 0.5),
      r * 0.8,
      Paint()..color = Colors.black.withValues(alpha: 0.3),
    );
    // Outer ring.
    canvas.drawCircle(
      Offset(pos.dx, pos.dy + bob),
      r,
      Paint()..color = const Color(0xFFB45309),
    );
    // Inner disc.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(pos.dx, pos.dy + bob),
        width: r * 1.6 * xs,
        height: r * 1.6,
      ),
      Paint()..color = const Color(0xFFFFC529),
    );
    // Specular highlight.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(pos.dx - r * 0.25 * xs, pos.dy + bob - r * 0.35),
        width: r * 0.5 * xs,
        height: r * 0.4,
      ),
      Paint()..color = const Color(0xFFFEF3C7).withValues(alpha: 0.85),
    );
    // $ mark.
    if (xs > 0.4) {
      final tp = TextPainter(
        text: const TextSpan(
          text: r'$',
          style: TextStyle(
            color: Color(0xFF7C2D12),
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(pos.dx - tp.width / 2, pos.dy + bob - tp.height / 2),
      );
    }
    // Orbital sparkle ring.
    final orbitR = r * 1.4;
    for (var i = 0; i < 4; i++) {
      final a = c.phase + i * (pi / 2);
      final px = pos.dx + cos(a) * orbitR;
      final py = pos.dy + bob + sin(a) * orbitR;
      canvas.drawCircle(
        Offset(px, py),
        1.5,
        Paint()..color = const Color(0xFFFFE066).withValues(alpha: 0.8),
      );
    }
  }

  void _drawPowerUp(Canvas canvas, _PowerUp p) {
    if (p.z < 0) return;
    final pos = projectToScreen(p.laneOffset, 0, p.z);
    final scale = (0.25 + 0.75 * p.z).clamp(0.0, 1.5);
    final color = _powerUpColor(p.kind);
    // Halo.
    canvas.drawCircle(
      Offset(pos.dx, pos.dy),
      24 * scale + sin(p.phase) * 2 * scale,
      Paint()..color = color.withValues(alpha: 0.30),
    );
    // Backing.
    canvas.drawCircle(
      Offset(pos.dx, pos.dy),
      18 * scale,
      Paint()..color = const Color(0xFF111622),
    );
    switch (p.kind) {
      case _PowerUpKind.coinMagnet:
        _drawMagnetIcon(canvas, pos, scale, color);
        break;
      case _PowerUpKind.superSneakers:
        _drawSneakerIcon(canvas, pos, scale, color);
        break;
      case _PowerUpKind.hoverboard:
        _drawHoverboardIcon(canvas, pos, scale, color);
        break;
    }
  }

  void _drawMagnetIcon(Canvas canvas, Offset pos, double scale, Color color) {
    final r = 11 * scale;
    final path = Path()
      ..moveTo(pos.dx - r, pos.dy - r * 0.6)
      ..lineTo(pos.dx - r, pos.dy + r * 0.4)
      ..lineTo(pos.dx - r * 0.4, pos.dy + r * 0.4)
      ..lineTo(pos.dx - r * 0.4, pos.dy - r * 0.1)
      ..lineTo(pos.dx + r * 0.4, pos.dy - r * 0.1)
      ..lineTo(pos.dx + r * 0.4, pos.dy + r * 0.4)
      ..lineTo(pos.dx + r, pos.dy + r * 0.4)
      ..lineTo(pos.dx + r, pos.dy - r * 0.6);
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4 * scale,
    );
  }

  void _drawSneakerIcon(Canvas canvas, Offset pos, double scale, Color color) {
    final r = 10 * scale;
    final body = Path()
      ..moveTo(pos.dx - r, pos.dy + r * 0.4)
      ..quadraticBezierTo(pos.dx, pos.dy - r * 0.8, pos.dx + r, pos.dy + r * 0.4)
      ..lineTo(pos.dx + r * 0.6, pos.dy + r * 0.7)
      ..lineTo(pos.dx - r * 0.6, pos.dy + r * 0.7)
      ..close();
    canvas.drawPath(body, Paint()..color = color);
    final lace = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.2 * scale
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(pos.dx - r * 0.3, pos.dy),
      Offset(pos.dx - r * 0.1, pos.dy - r * 0.4),
      lace,
    );
    canvas.drawLine(
      Offset(pos.dx + r * 0.1, pos.dy),
      Offset(pos.dx + r * 0.3, pos.dy - r * 0.4),
      lace,
    );
  }

  void _drawHoverboardIcon(Canvas canvas, Offset pos, double scale, Color color) {
    final w = 20 * scale;
    final h = 6 * scale;
    final rect = Rect.fromCenter(center: Offset(pos.dx, pos.dy), width: w, height: h);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2)),
      Paint()..color = color,
    );
    final flame = Path()
      ..moveTo(pos.dx - w * 0.3, pos.dy + h / 2)
      ..lineTo(pos.dx, pos.dy + h + 6 * scale)
      ..lineTo(pos.dx + w * 0.3, pos.dy + h / 2)
      ..close();
    canvas.drawPath(flame, Paint()..color = const Color(0xFFFB923C));
    canvas.drawCircle(
      Offset(pos.dx, pos.dy + h + 2),
      4 * scale,
      Paint()
        ..color = const Color(0xFF22D3EE).withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
  }

  @override
  bool shouldRepaint(_TrackPainter old) =>
      old.lane != lane ||
      old.targetLane != targetLane ||
      old.laneAnimT != laneAnimT ||
      old.bankTilt != bankTilt ||
      old.yOffset != yOffset ||
      old.sliding != sliding ||
      old.speed != speed ||
      old.distance != distance ||
      old.obstacles != obstacles ||
      old.coins != coins ||
      old.powerUps != powerUps ||
      old.floaters != floaters ||
      old.sparkles != sparkles ||
      old.speedLines != speedLines ||
      old.magnetActive != magnetActive ||
      old.magnetTime != magnetTime ||
      old.sneakerActive != sneakerActive ||
      old.sneakerTime != sneakerTime ||
      old.hoverboardActive != hoverboardActive ||
      old.hoverboardTime != hoverboardTime ||
      old.idleTime != idleTime ||
      old.envScroll != envScroll ||
      old.cloudScroll != cloudScroll ||
      old.skylineScroll != skylineScroll ||
      old.poleScroll != poleScroll ||
      old.tieScroll != tieScroll ||
      old.dustPuffs != dustPuffs ||
      old.snapCoins != snapCoins ||
      old.crashTimer != crashTimer ||
      old.ragdollAngle != ragdollAngle ||
      old.ragdollT != ragdollT ||
      old.slideTime != slideTime ||
      old.jumpElapsed != jumpElapsed ||
      old.sideProps != sideProps;
}

class _DrawnEntity {
  _DrawnEntity({required this.z, required this.draw});
  final double z;
  final void Function(Canvas) draw;
}
