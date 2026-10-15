import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../game_widgets.dart';
import '../mini_game.dart';

/// Space Blast — retro vertical space shooter.
///
/// Visual upgrade (plan: cosmic-blasting-zephyr):
///   * Deep navy/purple space canvas with **animated multi-layered
///     scrolling vector starfields** (kept) and **distant glowing
///     nebula clouds** (new).
///   * Top HUD bar — white circular Pause button + STAGE badge pill on
///     left, rounded white `SCORE N,NNN` card centred, red heart-lives
///     pill on right (replacing the legacy dark `_Chip` pills).
///   * SHIELD/POWER-UP progress gauge above the player ship showing
///     wave progress.
///   * Kawaii starship with **thick dark outlines**, **bright cyan
///     wings**, **glossy cockpit glass**, and **animated flame
///     engine thruster**.
///   * Kawaii alien invaders (grunt/shooter/tank) with **thick dark
///     outlines** + cute faces + smiles.
///   * **Rotating space rocks / asteroids** falling straight down
///     between waves.
///   * Vector lasers — **glowing neon yellow** for normal weapon,
///     cyan 3-fan spread, bright **pink beam** for beam weapon.
///   * 3-D score floaters (`+20`, `BLAST! +50`, `BOOST!`) with
///     star-trail sparkles + 4-point star particles.
///   * Star coin collectibles (10 % drop chance) that home toward
///     the player.
///   * First-launch tutorial overlay — "Drag to move & shoot!"
///     capsule + animated cartoon hand performing a left-to-right
///     drag motion; auto-dismissed after 6 s or on first drag.
///   * Direct `HapticFeedback.selectionClick / mediumImpact /
///     heavyImpact` calls (per spec). Host-proxy calls kept as
///     fallback for audio cue compatibility.
///
/// Engine preserved from previous version: drag-to-position ship
/// (horizontal + slight vertical freedom, tilts toward drag
/// direction), continuous auto-firing lasers every 130 ms, weapon
/// upgrade drops (spread/beam/shield), 3-parallax starfield, alien
/// waves (V/Line/Diamond/Zigzag formations), wave-clear banner,
/// 0.6 s invincibility + screen shake on player hit, game over at
/// 0 lives.
///
/// Public surface kept byte-identical with the previous engine so
/// the dispatcher (`case 'space-blast'`) keeps resolving:
///   `class SpaceBlastGame extends MiniGame`
///   `const SpaceBlastGame({super.key, required super.callbacks})`
class SpaceBlastGame extends MiniGame {
  const SpaceBlastGame({super.key, required super.callbacks});

  @override
  State<SpaceBlastGame> createState() => _State();
}

enum _AlienKind { grunt, shooter, tank }

enum _Weapon { normal, spread, beam }

enum _PowerUpKind { spread, beam, shield, coin }

// ─────────────────────────────────────────────────────────────────
// Entities
// ─────────────────────────────────────────────────────────────────

class _Alien {
  _Alien({
    required this.x,
    required this.y,
    required this.kind,
    required this.color,
    required this.points,
    required this.hp,
    required this.wobblePhase,
  });
  double x;
  double y;
  _AlienKind kind;
  Color color;
  int points;
  int hp;
  double wobblePhase;
}

class _Asteroid {
  _Asteroid({
    required this.x,
    required this.y,
    required this.vy,
    required this.r,
    required this.spin,
    required this.rotation,
    required this.hp,
    required this.points,
  });
  double x;
  double y;
  double vy;
  double r;
  double spin;
  double rotation;
  int hp;
  int points;
}

class _AlienLaser {
  _AlienLaser({required this.x, required this.y, required this.vy});
  double x;
  double y;
  double vy;
}

class _Laser {
  _Laser({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.color,
    required this.width,
  });
  double x;
  double y;
  double vx;
  double vy;
  Color color;
  double width;
}

class _PowerUp {
  _PowerUp({required this.x, required this.y, required this.kind});
  double x;
  double y;
  double vy = 70;
  _PowerUpKind kind;
}

class _Coin {
  _Coin({required this.x, required this.y});
  double x;
  double y;
  // For homing: stores the target ship position when activated.
  bool homing = false;
  Offset? target;
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

class _StarSparkle {
  _StarSparkle({
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

class _Shockwave {
  _Shockwave({required this.x, required this.y, required this.color})
      : r = 0,
        life = 1.0;
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
    this.fontSize = 16,
    this.isBig = false,
  }) : life = 0.8;
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
    required this.r,
    required this.speed,
    required this.alpha,
    required this.phase,
  });
  double x;
  double y;
  double r;
  double speed; // dp/s
  double alpha;
  double phase; // for twinkle
}

class _Nebula {
  const _Nebula({
    required this.cx,
    required this.cy,
    required this.r,
    required this.color,
  });
  final double cx;
  final double cy;
  final double r;
  final Color color;
}

class _State extends MiniGameState<SpaceBlastGame>
    with TickerProviderStateMixin {
  // ───────────────────────────────────────────────────────────────
  // Tuning constants
  // ───────────────────────────────────────────────────────────────

  static const double _tutorialDuration = 6.0;

  // ───────────────────────────────────────────────────────────────
  // State
  // ───────────────────────────────────────────────────────────────

  late final Ticker _ticker;
  late final Ticker _idleTicker;
  final Random _rng = Random();
  DateTime _last = DateTime.now();

  double _screenW = 0;
  double _screenH = 0;

  // Ship state.
  double _shipX = 0.5; // 0..1 normalized
  double _shipY = 0.0; // 0..1 from bottom
  double _shipTilt = 0; // radians
  Offset? _touchPos;
  bool _invincible = false;
  double _invincibleTime = 0;
  int _lives = 3;

  // Fire timing.
  double _fireTimer = 0;

  // Weapon state.
  _Weapon _weapon = _Weapon.normal;
  double _weaponTime = 0;

  // Shield bubble state.
  bool _hasShield = false;

  // Score / wave.
  int _score = 0;
  int _wave = 1;
  int _waveClearTimer = 0;
  bool _waitingForNextWave = false;

  // Pause.
  final bool _paused = false;

  // Hearts pulse (visual feedback when hit / power-up pickup).
  double _heartsPulse = 0;

  // Tutorial state.
  bool _showTutorial = true;
  // ignore: prefer_final_fields
  double _tutorialElapsed = 0;
  bool _tutorialDismissed = false;

  // Idle time (drives star twinkle + tutorial hand animation).
  double _idleTime = 0;

  // Entities.
  final List<_Alien> _aliens = [];
  final List<_Asteroid> _asteroids = [];
  final List<_AlienLaser> _alienLasers = [];
  final List<_Laser> _lasers = [];
  final List<_PowerUp> _powerUps = [];
  final List<_Coin> _coins = [];
  final List<_Particle> _particles = [];
  final List<_StarSparkle> _sparkles = [];
  final List<_Shockwave> _shocks = [];
  final List<_Floater> _floaters = [];

  // Stars (3 parallax layers).
  final List<_Star> _stars = [];

  // Asteroid spawn timer.
  double _asteroidSpawnTimer = 1.5;

  // Wave-progress gauge (SHIELD / POWER-UP): 0..1 based on
  // aliens remaining in the current wave.
  double get _waveProgress {
    if (_waveStartCount == 0) return 1.0;
    final killed = _waveStartCount - _aliens.length;
    return (killed / _waveStartCount).clamp(0.0, 1.0);
  }

  int _waveStartCount = 0;

  // Nebula clouds (fixed positions).
  static const _nebulae = [
    _Nebula(cx: 0.20, cy: 0.20, r: 0.55, color: Color(0xFFA855F7)),
    _Nebula(cx: 0.85, cy: 0.75, r: 0.60, color: Color(0xFF22D3EE)),
    _Nebula(cx: 0.55, cy: 0.50, r: 0.45, color: Color(0xFFFB7185)),
  ];

  // Engine flame + exhaust.
  double _flameTime = 0;

  // Shake.
  double _shakeTime = 0;
  double _shakeMag = 0;

  // Game over.
  bool _gameOver = false;

  // Spawn timer.
  double _alienFireTimer = 0;

  // ───────────────────────────────────────────────────────────────
  // Lifecycle
  // ───────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
    _idleTicker = createTicker(_onIdle)..start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reportScore(_score);
      _refreshStats();
      _spawnWave();
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _idleTicker.dispose();
    super.dispose();
  }

  void _refreshStats() {
    reportStats('Wave $_wave  •  Lives $_lives/3');
  }

  // ───────────────────────────────────────────────────────────────
  // Tick
  // ───────────────────────────────────────────────────────────────

  void _tick(Duration _) {
    if (!mounted || _screenW == 0) return;
    if (_paused) {
      _animateStars(0.016); // keep stars drifting slowly
      return;
    }
    final now = DateTime.now();
    final dt = (now.difference(_last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = now;

    if (!_starsReady) {
      _seedStars();
    }

    setState(() {
      _flameTime += dt;
      // Shake decay.
      if (_shakeTime > 0) {
        _shakeTime = (_shakeTime - dt).clamp(0.0, 99.0);
      }
      // Invincibility decay.
      if (_invincible) {
        _invincibleTime -= dt;
        if (_invincibleTime <= 0) {
          _invincible = false;
          _invincibleTime = 0;
        }
      }
      // Weapon decay.
      if (_weapon != _Weapon.normal) {
        _weaponTime -= dt;
        if (_weaponTime <= 0) {
          _weapon = _Weapon.normal;
          _weaponTime = 0;
        }
      }
      // Wave clear banner.
      if (_waveClearTimer > 0) {
        _waveClearTimer -= (dt * 1000).round();
        if (_waveClearTimer <= 0 && _waitingForNextWave) {
          _waitingForNextWave = false;
          _wave += 1;
          _spawnWave();
        }
      }
      _animateStars(dt);
      // Once the game has ended, drain any remaining VFX for one frame
      // so explosions don't pop, then stop the ticker — otherwise it
      // keeps repainting under the host's game-over overlay and starves
      // the UI ("freeze mid-gameplay").
      if (_gameOver) {
        _animateVfx(dt);
        if (_ticker.isActive) _ticker.stop();
        return;
      }
      _smoothShip(dt);
      _autoFire(dt);
      _moveEntities(dt);
      _alienFire(dt);
      _spawnAsteroids(dt);
      _collisions();
      _animateVfx(dt);

      // Tutorial auto-dismiss after timeout.
      if (_showTutorial && !_tutorialDismissed) {
        _tutorialElapsed += dt;
        if (_tutorialElapsed > _tutorialDuration) {
          _dismissTutorial();
        }
      }
    });
  }

  void _onIdle(Duration elapsed) {
    if (!mounted) return;
    setState(() {
      _idleTime += 0.016;
      if (_heartsPulse > 0) {
        _heartsPulse = (_heartsPulse - 0.064).clamp(0.0, 1.0);
      }
    });
  }

  void _animateVfx(double dt) {
    for (final p in _particles) {
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vy += 200 * dt;
      p.life -= dt;
      p.rotation += p.spin * dt;
    }
    _particles.removeWhere((p) => p.life <= 0);
    for (final s in _shocks) {
      s.r += 90 * dt;
      s.life -= dt * 1.6;
    }
    _shocks.removeWhere((s) => s.life <= 0);
    for (final f in _floaters) {
      f.y -= 30 * dt;
      f.life -= dt;
    }
    _floaters.removeWhere((f) => f.life <= 0);
    for (final s in _sparkles) {
      s.x += s.vx * dt;
      s.y += s.vy * dt;
      s.life -= dt;
      s.rot += s.spin * dt;
    }
    _sparkles.removeWhere((s) => s.life <= 0);
  }

  void _animateStars(double dt) {
    for (final s in _stars) {
      s.y += s.speed * dt;
      if (s.y > _screenH + 4) {
        s.y = -4;
        s.x = _rng.nextDouble() * _screenW;
      }
    }
  }

  bool get _starsReady => _stars.isNotEmpty;

  void _seedStars() {
    for (var i = 0; i < 30; i++) {
      _stars.add(_Star(
        x: _rng.nextDouble() * _screenW,
        y: _rng.nextDouble() * _screenH,
        r: 0.6 + _rng.nextDouble() * 0.8,
        speed: 60 + _rng.nextDouble() * 30,
        alpha: 0.3 + _rng.nextDouble() * 0.3,
        phase: _rng.nextDouble() * pi * 2,
      ));
    }
    for (var i = 0; i < 30; i++) {
      _stars.add(_Star(
        x: _rng.nextDouble() * _screenW,
        y: _rng.nextDouble() * _screenH,
        r: 1.0 + _rng.nextDouble() * 1.0,
        speed: 130 + _rng.nextDouble() * 40,
        alpha: 0.4 + _rng.nextDouble() * 0.4,
        phase: _rng.nextDouble() * pi * 2,
      ));
    }
    for (var i = 0; i < 20; i++) {
      _stars.add(_Star(
        x: _rng.nextDouble() * _screenW,
        y: _rng.nextDouble() * _screenH,
        r: 1.4 + _rng.nextDouble() * 1.0,
        speed: 240 + _rng.nextDouble() * 60,
        alpha: 0.6 + _rng.nextDouble() * 0.3,
        phase: _rng.nextDouble() * pi * 2,
      ));
    }
  }

  // ───────────────────────────────────────────────────────────────
  // Ship control
  // ───────────────────────────────────────────────────────────────

  void _smoothShip(double dt) {
    if (_touchPos != null) {
      final targetX = _touchPos!.dx / _screenW;
      final targetY = 1 - _touchPos!.dy / _screenH;
      _shipX += (targetX - _shipX) * (dt * 12).clamp(0.0, 1.0);
      _shipY += (targetY - _shipY) * (dt * 8).clamp(0.0, 1.0);
      _shipTilt = (targetX - _shipX).clamp(-0.3, 0.3) * 1.5;
    } else {
      _shipTilt *= (1 - dt * 4).clamp(0.0, 1.0);
    }
    _shipX = _shipX.clamp(0.06, 0.94);
    _shipY = _shipY.clamp(0.0, 0.45);
  }

  void _onPanStart(DragStartDetails d) {
    _touchPos = d.localPosition;
    _dismissTutorial();
  }

  void _onPanUpdate(DragUpdateDetails d) {
    _touchPos = d.localPosition;
  }

  void _onPanEnd(DragEndDetails _) {
    _touchPos = null;
  }

  void _dismissTutorial() {
    if (!_showTutorial || _tutorialDismissed) return;
    setState(() {
      _tutorialDismissed = true;
      _showTutorial = false;
    });
  }

  void _autoFire(double dt) {
    _fireTimer -= dt;
    final rate = _weapon == _Weapon.beam ? 0.06 : 0.13;
    if (_fireTimer > 0) return;
    _fireTimer = rate;
    final cx = _shipX * _screenW;
    final cy = (1 - _shipY) * _screenH - 30;
    switch (_weapon) {
      case _Weapon.normal:
        _lasers.add(_Laser(
          x: cx,
          y: cy,
          vx: 0,
          vy: -560,
          color: const Color(0xFFFACC15),
          width: 3,
        ));
        break;
      case _Weapon.spread:
        for (final a in [-0.26, 0, 0.26]) {
          final v = 540.0;
          _lasers.add(_Laser(
            x: cx,
            y: cy,
            vx: sin(a) * v,
            vy: -cos(a) * v,
            color: const Color(0xFF22D3EE),
            width: 3.5,
          ));
        }
        break;
      case _Weapon.beam:
        _lasers.add(_Laser(
          x: cx,
          y: cy,
          vx: 0,
          vy: -780,
          color: const Color(0xFFFB7185),
          width: 6,
        ));
        break;
    }
  }

  // ───────────────────────────────────────────────────────────────
  // Waves
  // ───────────────────────────────────────────────────────────────

  void _spawnWave() {
    final formation = (_wave - 1) % 4;
    final count = 14 + _wave * 4;
    final baseY = -40.0;
    switch (formation) {
      case 0:
        // V formation.
        for (var i = 0; i < count; i++) {
          final sign = i.isEven ? 1 : -1;
          final idx = (i / 2).floor();
          final x = 0.5 + sign * 0.07 * (idx + 1);
          _aliens.add(_makeAlien(x, baseY - i * 30.0));
        }
        break;
      case 1:
        // Line formation.
        for (var i = 0; i < count; i++) {
          final x = 0.15 + (i / (count - 1).clamp(1, 99)) * 0.7;
          _aliens.add(_makeAlien(x, baseY - i * 28.0));
        }
        break;
      case 2:
        // Diamond.
        final mid = (count / 2).floor();
        for (var i = 0; i < count; i++) {
          final offset = i <= mid ? i : (count - 1 - i);
          final x = 0.5 + (i - mid) * (0.7 / mid);
          _aliens.add(_makeAlien(x, baseY - offset * 32.0));
        }
        break;
      case 3:
        // Zigzag.
        for (var i = 0; i < count; i++) {
          final x = i.isEven ? 0.30 : 0.70;
          _aliens.add(_makeAlien(x, baseY - i * 30.0));
        }
        break;
    }
    _waveStartCount = _aliens.length;
    _refreshStats();
  }

  _Alien _makeAlien(double x, double y) {
    final roll = _rng.nextDouble();
    if (roll < 0.6) {
      return _Alien(
        x: x,
        y: y,
        kind: _AlienKind.grunt,
        color: const Color(0xFFFB7185),
        points: 20,
        hp: 1,
        wobblePhase: _rng.nextDouble() * pi * 2,
      );
    } else if (roll < 0.9) {
      return _Alien(
        x: x,
        y: y,
        kind: _AlienKind.shooter,
        color: const Color(0xFFFBBF24),
        points: 30,
        hp: 1,
        wobblePhase: _rng.nextDouble() * pi * 2,
      );
    } else {
      return _Alien(
        x: x,
        y: y,
        kind: _AlienKind.tank,
        color: const Color(0xFFA855F7),
        points: 50,
        hp: 2,
        wobblePhase: _rng.nextDouble() * pi * 2,
      );
    }
  }

  void _spawnAsteroids(double dt) {
    _asteroidSpawnTimer -= dt;
    if (_asteroidSpawnTimer > 0) return;
    _asteroidSpawnTimer = 1.2 + _rng.nextDouble() * 1.3;
    _asteroids.add(_Asteroid(
      x: 0.1 + _rng.nextDouble() * 0.8,
      y: -30.0,
      vy: 60 + _rng.nextDouble() * 40,
      r: 14 + _rng.nextDouble() * 8,
      spin: (_rng.nextDouble() - 0.5) * 4,
      rotation: _rng.nextDouble() * pi,
      hp: 1,
      points: 10,
    ));
  }

  // ───────────────────────────────────────────────────────────────
  // Entity movement
  // ───────────────────────────────────────────────────────────────

  void _moveEntities(double dt) {
    for (final a in _aliens) {
      a.y += 50 * dt;
      a.wobblePhase += dt * 2;
      a.x += sin(a.wobblePhase) * 0.0005;
    }
    _aliens.removeWhere((a) => a.y > _screenH + 30);

    for (final ast in _asteroids) {
      ast.y += ast.vy * dt;
      ast.rotation += ast.spin * dt;
    }
    _asteroids.removeWhere((a) => a.y > _screenH + 50);

    for (final l in _lasers) {
      l.x += l.vx * dt;
      l.y += l.vy * dt;
    }
    _lasers.removeWhere(
        (l) => l.y < -20 || l.x < -20 || l.x > _screenW + 20);

    for (final l in _alienLasers) {
      l.y += l.vy * dt;
    }
    _alienLasers.removeWhere((l) => l.y > _screenH + 20);

    for (final p in _powerUps) {
      p.y += p.vy * dt;
    }
    _powerUps.removeWhere((p) => p.y > _screenH + 20);

    // Coins fall + home toward player when within range.
    final ship = _shipScreenPos();
    for (final c in _coins) {
      if (!c.homing && c.y > _screenH * 0.55) {
        c.homing = true;
      }
      if (c.homing) {
        c.target = ship;
        final dx = ship.dx - c.x;
        final dy = ship.dy - c.y;
        final d = sqrt(dx * dx + dy * dy);
        if (d > 0) {
          final speed = 180.0;
          c.x += (dx / d) * speed * dt;
          c.y += (dy / d) * speed * dt;
        }
      } else {
        c.y += 80 * dt;
      }
    }
    _coins.removeWhere((c) => c.y > _screenH + 20);
  }

  void _alienFire(double dt) {
    _alienFireTimer -= dt;
    if (_alienFireTimer > 0) return;
    _alienFireTimer = 1.2 + _rng.nextDouble() * 0.8;
    if (_aliens.isEmpty) return;
    final shooter = _aliens[_rng.nextInt(_aliens.length)];
    if (shooter.kind == _AlienKind.grunt) return;
    _alienLasers.add(_AlienLaser(
      x: shooter.x * _screenW,
      y: shooter.y + 18,
      vy: 220,
    ));
  }

  // ───────────────────────────────────────────────────────────────
  // Collisions
  // ───────────────────────────────────────────────────────────────

  void _collisions() {
    final shipCx = _shipX * _screenW;
    final shipCy = (1 - _shipY) * _screenH;
    const shipR = 18.0;

    // Lasers vs aliens + asteroids.
    for (final l in _lasers.toList()) {
      // Aliens.
      for (final a in _aliens.toList()) {
        final ax = a.x * _screenW;
        final ay = a.y;
        final r = a.kind == _AlienKind.tank ? 20.0 : 16.0;
        final d = (Offset(ax, ay) - Offset(l.x, l.y)).distance;
        if (d < r + l.width) {
          a.hp -= _weapon == _Weapon.beam ? 2 : 1;
          _lasers.remove(l);
          if (a.hp <= 0) {
            _onAlienKilled(a);
            _aliens.remove(a);
          } else {
            _floaters.add(_Floater(
              x: ax,
              y: ay - 18,
              text: 'HIT!',
              color: const Color(0xFFFBBF24),
            ));
          }
          break;
        }
      }
      // Asteroids.
      for (final ast in _asteroids.toList()) {
        final d = (Offset(ast.x * _screenW, ast.y) - Offset(l.x, l.y))
            .distance;
        if (d < ast.r + l.width) {
          ast.hp -= 1;
          _lasers.remove(l);
          if (ast.hp <= 0) {
            _onAsteroidKilled(ast);
            _asteroids.remove(ast);
          }
          break;
        }
      }
    }
    // Alien lasers vs ship.
    if (!_invincible) {
      for (final l in _alienLasers.toList()) {
        final d = (Offset(l.x, l.y) - Offset(shipCx, shipCy)).distance;
        if (d < shipR + 4) {
          _alienLasers.remove(l);
          _onPlayerHit();
          return;
        }
      }
    }
    // Aliens contact ship.
    if (!_invincible) {
      for (final a in _aliens) {
        final ax = a.x * _screenW;
        final ay = a.y;
        final d = (Offset(ax, ay) - Offset(shipCx, shipCy)).distance;
        if (d < shipR + 14) {
          _onPlayerHit();
          return;
        }
      }
    }
    // Asteroids contact ship.
    if (!_invincible) {
      for (final ast in _asteroids) {
        final ax = ast.x * _screenW;
        final ay = ast.y;
        final d = (Offset(ax, ay) - Offset(shipCx, shipCy)).distance;
        if (d < shipR + ast.r) {
          _onPlayerHit();
          return;
        }
      }
    }
    // Power-ups.
    for (final p in _powerUps.toList()) {
      final d = (Offset(p.x, p.y) - Offset(shipCx, shipCy)).distance;
      if (d < shipR + 16) {
        _onPowerUp(p);
        _powerUps.remove(p);
      }
    }
    // Coins.
    for (final c in _coins.toList()) {
      final d = (Offset(c.x, c.y) - Offset(shipCx, shipCy)).distance;
      if (d < shipR + 12) {
        _onCoinCollected(c);
        _coins.remove(c);
      }
    }
  }

  void _onAlienKilled(_Alien a) {
    _score += a.points;
    _heartsPulse = 1.0;
    final ax = a.x * _screenW;
    final ay = a.y;
    final isBig = a.kind == _AlienKind.tank;
    _floaters.add(_Floater(
      x: ax,
      y: ay - 24,
      text: isBig ? 'BLAST! +${a.points}' : '+${a.points}',
      color: a.color,
      fontSize: isBig ? 22 : 18,
      isBig: isBig,
    ));
    // 16-particle radial burst.
    for (var i = 0; i < 16; i++) {
      final a2 = (i / 16) * 2 * pi + _rng.nextDouble() * 0.4;
      final sp = 60 + _rng.nextDouble() * 140;
      _particles.add(_Particle(
        x: ax,
        y: ay,
        vx: cos(a2) * sp,
        vy: sin(a2) * sp,
        life: 0.6,
        color: a.color,
        rotation: _rng.nextDouble() * pi,
        spin: (_rng.nextDouble() - 0.5) * 10,
      ));
    }
    // 8 star sparkles.
    for (var i = 0; i < 8; i++) {
      final a2 = (i / 8) * 2 * pi + _rng.nextDouble() * 0.4;
      final sp = 50 + _rng.nextDouble() * 60;
      _sparkles.add(_StarSparkle(
        x: ax,
        y: ay,
        vx: cos(a2) * sp,
        vy: sin(a2) * sp,
        life: 0.5,
        color: Colors.white,
        rot: 0,
        spin: (_rng.nextDouble() - 0.5) * 8,
      ));
    }
    // Shockwave.
    _shocks.add(_Shockwave(x: ax, y: ay, color: a.color));
    HapticFeedback.selectionClick();
    haptic(HapticFeedbackType.medium);
    reportScore(_score);

    // 25 % weapon/shield power-up + 10 % star coin.
    if (_rng.nextDouble() < 0.25) {
      final roll = _rng.nextDouble();
      final kind = roll < 0.4
          ? _PowerUpKind.spread
          : roll < 0.75
              ? _PowerUpKind.beam
              : _PowerUpKind.shield;
      _powerUps.add(_PowerUp(x: ax, y: ay, kind: kind));
    } else if (_rng.nextDouble() < 0.10) {
      _coins.add(_Coin(x: ax, y: ay));
    }
    // Wave clear check.
    if (_aliens.isEmpty && !_waitingForNextWave) {
      _waitingForNextWave = true;
      _waveClearTimer = 1800;
      _floaters.add(_Floater(
        x: _screenW / 2,
        y: _screenH * 0.4,
        text: 'WAVE $_wave CLEAR!',
        color: const Color(0xFFFB923C),
        fontSize: 32,
        isBig: true,
      ));
      HapticFeedback.heavyImpact();
      haptic(HapticFeedbackType.heavy);
    }
  }

  void _onAsteroidKilled(_Asteroid ast) {
    _score += ast.points;
    final ax = ast.x * _screenW;
    final ay = ast.y;
    _floaters.add(_Floater(
      x: ax,
      y: ay - 18,
      text: '+${ast.points}',
      color: const Color(0xFF94A3B8),
    ));
    for (var i = 0; i < 10; i++) {
      final a2 = (i / 10) * 2 * pi;
      final sp = 40 + _rng.nextDouble() * 60;
      _particles.add(_Particle(
        x: ax,
        y: ay,
        vx: cos(a2) * sp,
        vy: sin(a2) * sp,
        life: 0.5,
        color: const Color(0xFF94A3B8),
        rotation: _rng.nextDouble() * pi,
        spin: (_rng.nextDouble() - 0.5) * 10,
      ));
    }
    _shocks.add(_Shockwave(x: ax, y: ay, color: const Color(0xFF94A3B8)));
    haptic(HapticFeedbackType.light);
    reportScore(_score);
  }

  void _onCoinCollected(_Coin c) {
    _score += 25;
    _heartsPulse = 1.0;
    _floaters.add(_Floater(
      x: c.x,
      y: c.y - 16,
      text: '+25',
      color: const Color(0xFFFACC15),
    ));
    for (var i = 0; i < 8; i++) {
      final a2 = (i / 8) * 2 * pi;
      _sparkles.add(_StarSparkle(
        x: c.x,
        y: c.y,
        vx: cos(a2) * 50,
        vy: sin(a2) * 50,
        life: 0.4,
        color: const Color(0xFFFACC15),
        rot: 0,
        spin: (_rng.nextDouble() - 0.5) * 8,
      ));
    }
    HapticFeedback.selectionClick();
    haptic(HapticFeedbackType.light);
    reportScore(_score);
  }

  void _onPlayerHit() {
    if (_hasShield) {
      _hasShield = false;
      _floaters.add(_Floater(
        x: _shipX * _screenW,
        y: (1 - _shipY) * _screenH,
        text: 'SHIELD!',
        color: const Color(0xFFFACC15),
      ));
      HapticFeedback.mediumImpact();
      haptic(HapticFeedbackType.medium);
      _invincible = true;
      _invincibleTime = 0.6;
      _shocks.add(_Shockwave(
        x: _shipX * _screenW,
        y: (1 - _shipY) * _screenH,
        color: const Color(0xFFFACC15),
      ));
      return;
    }
    _lives -= 1;
    _heartsPulse = 1.0;
    _shake(0.4, 14);
    HapticFeedback.heavyImpact();
    haptic(HapticFeedbackType.heavy);
    _invincible = true;
    _invincibleTime = 0.6;
    for (var i = 0; i < 12; i++) {
      final a2 = (i / 12) * 2 * pi;
      _particles.add(_Particle(
        x: _shipX * _screenW,
        y: (1 - _shipY) * _screenH,
        vx: cos(a2) * 100,
        vy: sin(a2) * 100,
        life: 0.5,
        color: const Color(0xFFEF4444),
        rotation: 0,
        spin: 0,
      ));
    }
    if (_lives <= 0) {
      _gameOver = true;
      reportScore(_score);
      _refreshStats();
      reportGameOver();
    } else {
      _refreshStats();
    }
  }

  void _onPowerUp(_PowerUp p) {
    _heartsPulse = 1.0;
    switch (p.kind) {
      case _PowerUpKind.spread:
        _weapon = _Weapon.spread;
        _weaponTime = 6;
        _floaters.add(_Floater(
          x: p.x,
          y: p.y - 24,
          text: 'BOOST!',
          color: const Color(0xFF22D3EE),
          fontSize: 20,
          isBig: true,
        ));
        break;
      case _PowerUpKind.beam:
        _weapon = _Weapon.beam;
        _weaponTime = 4;
        _floaters.add(_Floater(
          x: p.x,
          y: p.y - 24,
          text: 'BEAM!',
          color: const Color(0xFFFB7185),
          fontSize: 20,
          isBig: true,
        ));
        break;
      case _PowerUpKind.shield:
        _hasShield = true;
        _floaters.add(_Floater(
          x: p.x,
          y: p.y - 24,
          text: 'SHIELD!',
          color: const Color(0xFFFACC15),
          fontSize: 20,
          isBig: true,
        ));
        break;
      case _PowerUpKind.coin:
        // unused (coins spawn from a different path)
        break;
    }
    // Sparkle ring.
    for (var i = 0; i < 10; i++) {
      final a2 = (i / 10) * 2 * pi;
      _particles.add(_Particle(
        x: p.x,
        y: p.y,
        vx: cos(a2) * 70,
        vy: sin(a2) * 70,
        life: 0.4,
        color: p.kind == _PowerUpKind.spread
            ? const Color(0xFF22D3EE)
            : p.kind == _PowerUpKind.beam
                ? const Color(0xFFFB7185)
                : const Color(0xFFFACC15),
        rotation: 0,
        spin: 0,
      ));
    }
    HapticFeedback.mediumImpact();
    haptic(HapticFeedbackType.medium);
  }

  void _shake(double duration, double magnitude) {
    _shakeTime = duration;
    _shakeMag = magnitude;
  }

  // ───────────────────────────────────────────────────────────────
  // Build
  // ───────────────────────────────────────────────────────────────

  Offset _shipScreenPos() => Offset(
        _shipX * _screenW,
        (1 - _shipY) * _screenH,
      );

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
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF0F172A),
                Color(0xFF1E1B4B),
                Color(0xFF2E1065),
              ],
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Transform.translate(
                  offset: shake,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: _onPanStart,
                    onPanUpdate: _onPanUpdate,
                    onPanEnd: _onPanEnd,
                    child: CustomPaint(
                      painter: _SpacePainter(
                        idleTime: _idleTime,
                        ship: _shipScreenPos(),
                        shipTilt: _shipTilt,
                        flameTime: _flameTime,
                        invincible: _invincible,
                        stars: _stars,
                        aliens: _aliens,
                        asteroids: _asteroids,
                        alienLasers: _alienLasers,
                        lasers: _lasers,
                        powerUps: _powerUps,
                        coins: _coins,
                        particles: _particles,
                        sparkles: _sparkles,
                        shocks: _shocks,
                        floaters: _floaters,
                        hasShield: _hasShield,
                        weapon: _weapon,
                        waveClearTimer: _waveClearTimer,
                        wave: _wave,
                        screenW: _screenW,
                        screenH: _screenH,
                      ),
                    ),
                  ),
                ),
              ),
              // Top HUD removed — host GameContainerScreen provides it.
              // SHIELD / POWER-UP gauge above the player ship.
              Positioned(
                left: 0,
                right: 0,
                bottom: 12,
                child: Center(
                  child: _ShieldGauge(
                    progress: _waveProgress,
                    wave: _wave,
                  ),
                ),
              ),
              // Tutorial overlay (auto-dismiss after 6 s or first drag).
              if (_showTutorial && !_tutorialDismissed)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 80,
                  child: _TutorialOverlaySpace(
                    idleTime: _idleTime,
                    progress: _tutorialElapsed / _tutorialDuration,
                  ),
                ),
              // Pause overlay removed — host GameContainerScreen provides it.
              // Game Over overlay removed — host GameContainerScreen provides it.
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// SHIELD/POWER-UP gauge (wave progress above the player ship)
// ─────────────────────────────────────────────────────────────────

class _ShieldGauge extends StatelessWidget {
  const _ShieldGauge({required this.progress, required this.wave});
  final double progress;
  final int wave;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.shield_rounded,
            size: 16,
            color: const Color(0xFF22D3EE),
          ),
          const SizedBox(width: 6),
          Text(
            'SHIELD',
            style: const TextStyle(
              color: Color(0xFF1E3A8A),
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 10),
          // Progress bar.
          Container(
            width: 120,
            height: 8,
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(999),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: const Color(0xFFE2E8F0),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFF22D3EE),
                ),
                minHeight: 8,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${(progress * 100).round()}%',
            style: const TextStyle(
              color: Color(0xFF1E3A8A),
              fontSize: 11,
              fontWeight: FontWeight.w900,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Tutorial overlay (capsule + animated hand performing left-right drag)
// ─────────────────────────────────────────────────────────────────

class _TutorialOverlaySpace extends StatefulWidget {
  const _TutorialOverlaySpace({
    required this.idleTime,
    required this.progress,
  });
  final double idleTime;
  final double progress;

  @override
  State<_TutorialOverlaySpace> createState() => _TutorialOverlaySpaceState();
}

class _TutorialOverlaySpaceState extends State<_TutorialOverlaySpace>
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
              // Hand performing a horizontal drag motion.
              Transform.rotate(
                angle: -0.3,
                child: CustomPaint(
                  size: const Size(34, 34),
                  painter: _SpaceHandPainter(idleTime: widget.idleTime),
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Drag to move & shoot!',
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

class _SpaceHandPainter extends CustomPainter {
  _SpaceHandPainter({required this.idleTime});
  final double idleTime;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w * 0.5;
    final cy = h * 0.45;
    // Horizontal drag motion — only x oscillates.
    final dragX = sin(idleTime * 4) * 8;

    canvas.save();
    canvas.translate(cx + dragX, cy);

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

    // Index finger pointing horizontally (right).
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

    // Horizontal drag trail beneath the hand.
    final trailPath = Path()
      ..moveTo(w * 0.05, h * 0.85)
      ..lineTo(w * 0.95, h * 0.85);
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
  bool shouldRepaint(_SpaceHandPainter old) =>
      old.idleTime != idleTime;
}

// ─────────────────────────────────────────────────────────────────
// Painter
// ─────────────────────────────────────────────────────────────────

class _SpacePainter extends CustomPainter {
  _SpacePainter({
    required this.idleTime,
    required this.ship,
    required this.shipTilt,
    required this.flameTime,
    required this.invincible,
    required this.stars,
    required this.aliens,
    required this.asteroids,
    required this.alienLasers,
    required this.lasers,
    required this.powerUps,
    required this.coins,
    required this.particles,
    required this.sparkles,
    required this.shocks,
    required this.floaters,
    required this.hasShield,
    required this.weapon,
    required this.waveClearTimer,
    required this.wave,
    required this.screenW,
    required this.screenH,
  });

  final double idleTime;
  final Offset ship;
  final double shipTilt;
  final double flameTime;
  final bool invincible;
  final List<_Star> stars;
  final List<_Alien> aliens;
  final List<_Asteroid> asteroids;
  final List<_AlienLaser> alienLasers;
  final List<_Laser> lasers;
  final List<_PowerUp> powerUps;
  final List<_Coin> coins;
  final List<_Particle> particles;
  final List<_StarSparkle> sparkles;
  final List<_Shockwave> shocks;
  final List<_Floater> floaters;
  final bool hasShield;
  final _Weapon weapon;
  final int waveClearTimer;
  final int wave;
  final double screenW;
  final double screenH;

  @override
  void paint(Canvas canvas, Size size) {
    _drawNebulae(canvas);
    _drawStars(canvas);
    _drawAliens(canvas);
    _drawAsteroids(canvas);
    _drawAlienLasers(canvas);
    _drawPowerUps(canvas);
    _drawCoins(canvas);
    _drawShocks(canvas);
    _drawParticles(canvas);
    _drawSparkles(canvas);
    _drawPlayer(canvas);
    _drawLasers(canvas);
    _drawFloaters(canvas);
    _drawWaveClear(canvas);
  }

  // ─────────────────────────────────────────────────────────────
  // Nebula clouds (large soft glows behind the starfield)
  // ─────────────────────────────────────────────────────────────
  void _drawNebulae(Canvas canvas) {
    for (final n in _State._nebulae) {
      final cx = n.cx * screenW;
      final cy = n.cy * screenH;
      final r = n.r * screenW;
      final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);
      canvas.drawOval(
        rect,
        Paint()
          ..shader = RadialGradient(
            center: Alignment.center,
            radius: 0.8,
            colors: [
              n.color.withValues(alpha: 0.18),
              n.color.withValues(alpha: 0.0),
            ],
          ).createShader(rect)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Starfield (3 parallax layers, with twinkling alpha)
  // ─────────────────────────────────────────────────────────────
  void _drawStars(Canvas canvas) {
    for (final s in stars) {
      final twinkle = 0.7 + 0.3 * sin(idleTime * 3 + s.phase);
      canvas.drawCircle(
        Offset(s.x, s.y),
        s.r,
        Paint()..color = Colors.white.withValues(alpha: s.alpha * twinkle),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Aliens — kawaii vector with thick dark outlines + smile.
  // ─────────────────────────────────────────────────────────────
  void _drawAliens(Canvas canvas) {
    for (final a in aliens) {
      final pos = Offset(a.x * screenW, a.y);
      final w = a.kind == _AlienKind.tank ? 38.0 : 30.0;
      final h = a.kind == _AlienKind.tank ? 28.0 : 22.0;
      // Drop shadow.
      canvas.drawOval(
        Rect.fromCenter(center: pos.translate(0, 4), width: w, height: h * 0.4),
        Paint()..color = Colors.black.withValues(alpha: 0.4),
      );
      final bodyRect = Rect.fromCenter(center: pos, width: w, height: h);

      // ── Distinct silhouettes per kind. ──────────────────────
      if (a.kind == _AlienKind.tank) {
        // Tank: armored hexagonal body.
        final hex = Path()
          ..moveTo(pos.dx - w * 0.5, pos.dy)
          ..lineTo(pos.dx - w * 0.25, pos.dy - h * 0.5)
          ..lineTo(pos.dx + w * 0.25, pos.dy - h * 0.5)
          ..lineTo(pos.dx + w * 0.5, pos.dy)
          ..lineTo(pos.dx + w * 0.25, pos.dy + h * 0.5)
          ..lineTo(pos.dx - w * 0.25, pos.dy + h * 0.5)
          ..close();
        canvas.drawPath(
          hex,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(-0.3, -0.4),
              colors: [Colors.white, a.color],
            ).createShader(hex.getBounds()),
        );
        canvas.drawPath(
          hex,
          Paint()
            ..color = const Color(0xFF1F2937)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0,
        );
        // Armor plates.
        canvas.drawLine(
          Offset(pos.dx - w * 0.25, pos.dy - h * 0.5),
          Offset(pos.dx - w * 0.25, pos.dy + h * 0.5),
          Paint()
            ..color = const Color(0xFF1F2937).withValues(alpha: 0.4)
            ..strokeWidth = 1.0,
        );
        canvas.drawLine(
          Offset(pos.dx + w * 0.25, pos.dy - h * 0.5),
          Offset(pos.dx + w * 0.25, pos.dy + h * 0.5),
          Paint()
            ..color = const Color(0xFF1F2937).withValues(alpha: 0.4)
            ..strokeWidth = 1.0,
        );
        // Twin cannons.
        for (final side in [-1, 1]) {
          canvas.drawRect(
            Rect.fromCenter(
              center: Offset(pos.dx + side * w * 0.4, pos.dy + h * 0.4),
              width: 3,
              height: 5,
            ),
            Paint()..color = const Color(0xFF1F2937),
          );
        }
      } else {
        // Grunt + Shooter: classic oval body.
        canvas.drawOval(
          bodyRect,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(-0.3, -0.4),
              colors: [Colors.white, a.color],
            ).createShader(bodyRect),
        );
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(pos.dx - w * 0.18, pos.dy - h * 0.20),
            width: w * 0.40,
            height: h * 0.22,
          ),
          Paint()..color = Colors.white.withValues(alpha: 0.45),
        );
        canvas.drawOval(
          bodyRect,
          Paint()
            ..color = const Color(0xFF1F2937)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0,
        );
      }

      // ── Eyes (kawaii, all kinds). ──────────────────────────
      final eyeOffset = a.kind == _AlienKind.tank ? 6.0 : 5.0;
      final eyeR = a.kind == _AlienKind.tank ? 3.0 : 2.5;
      for (final side in [-1, 1]) {
        final ec = Offset(pos.dx + side * eyeOffset, pos.dy - 2);
        canvas.drawCircle(ec, eyeR, Paint()..color = Colors.white);
        canvas.drawCircle(ec, eyeR * 0.55, Paint()..color = Colors.black);
        // Eye shine.
        canvas.drawCircle(
          ec.translate(-eyeR * 0.25, -eyeR * 0.25),
          eyeR * 0.25,
          Paint()..color = Colors.white.withValues(alpha: 0.9),
        );
      }

      // ── Mouth (varies by kind). ────────────────────────────
      if (a.kind == _AlienKind.shooter) {
        // Fanged grin.
        canvas.drawArc(
          Rect.fromCenter(center: Offset(pos.dx, pos.dy + 4), width: w * 0.45, height: h * 0.40),
          0.15 * pi, 0.7 * pi, false,
          Paint()
            ..color = const Color(0xFF1F2937)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..strokeCap = StrokeCap.round,
        );
        // Two fangs.
        for (final side in [-1, 1]) {
          final fx = pos.dx + side * 3;
          canvas.drawPath(
            Path()
              ..moveTo(fx - 1, pos.dy + 5)
              ..lineTo(fx, pos.dy + 8)
              ..lineTo(fx + 1, pos.dy + 5)
              ..close(),
            Paint()..color = Colors.white,
          );
        }
      } else {
        canvas.drawArc(
          Rect.fromCenter(center: Offset(pos.dx, pos.dy + 4), width: w * 0.45, height: h * 0.40),
          0.15 * pi, 0.7 * pi, false,
          Paint()
            ..color = const Color(0xFF1F2937)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..strokeCap = StrokeCap.round,
        );
      }

      // ── Antenna for shooters + tanks. ──────────────────────
      if (a.kind == _AlienKind.shooter) {
        canvas.drawLine(
          Offset(pos.dx, pos.dy - h / 2),
          Offset(pos.dx, pos.dy - h / 2 - 8),
          Paint()
            ..color = a.color
            ..strokeWidth = 1.8,
        );
        canvas.drawCircle(
          Offset(pos.dx, pos.dy - h / 2 - 9),
          3.0,
          Paint()..color = a.color,
        );
        canvas.drawCircle(
          Offset(pos.dx, pos.dy - h / 2 - 9),
          1.4,
          Paint()..color = Colors.white,
        );
      } else if (a.kind == _AlienKind.tank) {
        // Twin short antennae.
        for (final side in [-1, 1]) {
          canvas.drawLine(
            Offset(pos.dx + side * w * 0.12, pos.dy - h * 0.5),
            Offset(pos.dx + side * w * 0.22, pos.dy - h * 0.5 - 5),
            Paint()
              ..color = a.color
              ..strokeWidth = 1.4,
          );
          canvas.drawCircle(
            Offset(pos.dx + side * w * 0.22, pos.dy - h * 0.5 - 6),
            1.6,
            Paint()..color = const Color(0xFFFACC15),
          );
        }
      }

      // ── HP bar for tanks. ──────────────────────────────────
      if (a.kind == _AlienKind.tank && a.hp < 2) {
        canvas.drawRect(
          Rect.fromLTWH(pos.dx - 14, pos.dy - 22, 28, 3),
          Paint()..color = Colors.white24,
        );
        canvas.drawRect(
          Rect.fromLTWH(pos.dx - 14, pos.dy - 22, 28 * (a.hp / 2), 3),
          Paint()..color = a.color,
        );
        canvas.drawRect(
          Rect.fromLTWH(pos.dx - 14, pos.dy - 22, 28, 3),
          Paint()
            ..color = const Color(0xFF1F2937)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8,
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Asteroids — irregular polygon, rotating.
  // ─────────────────────────────────────────────────────────────
  void _drawAsteroids(Canvas canvas) {
    for (final ast in asteroids) {
      canvas.save();
      canvas.translate(ast.x * screenW, ast.y);
      canvas.rotate(ast.rotation);
      final path = _asteroidPath(ast.r);
      // Body.
      canvas.drawPath(
        path,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.3, -0.4),
            colors: const [Color(0xFFCBD5E1), Color(0xFF475569)],
          ).createShader(Rect.fromCircle(center: Offset.zero, radius: ast.r)),
      );
      // Highlight.
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(-ast.r * 0.30, -ast.r * 0.30),
          width: ast.r * 0.55,
          height: ast.r * 0.30,
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.4),
      );
      // Outline.
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF1F2937)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8,
      );
      // Crater dots.
      for (var i = 0; i < 3; i++) {
        final a = (i / 3) * 2 * pi + ast.rotation * 0.5;
        final d = ast.r * 0.4;
        canvas.drawCircle(
          Offset.fromDirection(a, d),
          1.5,
          Paint()..color = const Color(0xFF1F2937).withValues(alpha: 0.5),
        );
      }
      canvas.restore();
    }
  }

  Path _asteroidPath(double r) {
    // Irregular polygon: 6 vertices with alternating radii.
    final path = Path();
    const points = 6;
    for (var i = 0; i < points; i++) {
      final a = (i / points) * 2 * pi;
      final radius = (i.isEven ? 1.0 : 0.78) * r;
      final px = cos(a) * radius;
      final py = sin(a) * radius;
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }
    path.close();
    return path;
  }

  void _drawAlienLasers(Canvas canvas) {
    for (final l in alienLasers) {
      canvas.drawCircle(
        Offset(l.x, l.y),
        3,
        Paint()..color = const Color(0xFFFCA5A5),
      );
      canvas.drawCircle(
        Offset(l.x, l.y),
        6,
        Paint()..color = const Color(0xFFFCA5A5).withValues(alpha: 0.3),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Power-ups.
  // ─────────────────────────────────────────────────────────────
  void _drawPowerUps(Canvas canvas) {
    for (final p in powerUps) {
      _drawPowerUpIcon(canvas, p);
    }
  }

  void _drawPowerUpIcon(Canvas canvas, _PowerUp p) {
    final color = switch (p.kind) {
      _PowerUpKind.spread => const Color(0xFF22D3EE),
      _PowerUpKind.beam => const Color(0xFFFB7185),
      _PowerUpKind.shield => const Color(0xFFFACC15),
      _PowerUpKind.coin => const Color(0xFFFACC15),
    };
    canvas.drawCircle(
      Offset(p.x, p.y),
      22,
      Paint()..color = color.withValues(alpha: 0.3),
    );
    canvas.drawCircle(
      Offset(p.x, p.y),
      14,
      Paint()..color = const Color(0xFF111622),
    );
    canvas.drawCircle(
      Offset(p.x, p.y),
      14,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );
    switch (p.kind) {
      case _PowerUpKind.spread:
        for (var i = -1; i <= 1; i++) {
          canvas.drawCircle(
            Offset(p.x + i * 4, p.y),
            1.6,
            Paint()..color = color,
          );
        }
        break;
      case _PowerUpKind.beam:
        canvas.drawRect(
          Rect.fromCenter(center: Offset(p.x, p.y), width: 4, height: 14),
          Paint()..color = color,
        );
        break;
      case _PowerUpKind.shield:
        canvas.drawArc(
          Rect.fromCenter(center: Offset(p.x, p.y + 2), width: 14, height: 14),
          pi,
          pi,
          false,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
        break;
      case _PowerUpKind.coin:
        break;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Star coins.
  // ─────────────────────────────────────────────────────────────
  void _drawCoins(Canvas canvas) {
    for (final c in coins) {
      final cx = c.x;
      final cy = c.y;
      // Glow.
      canvas.drawCircle(
        Offset(cx, cy),
        14,
        Paint()..color = const Color(0xFFFACC15).withValues(alpha: 0.4),
      );
      // Body.
      canvas.drawCircle(
        Offset(cx, cy),
        10,
        Paint()
          ..shader = const RadialGradient(
            colors: [Color(0xFFFEF08A), Color(0xFFFACC15)],
          ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: 10)),
      );
      canvas.drawCircle(
        Offset(cx, cy),
        10,
        Paint()
          ..color = const Color(0xFF1F2937)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
      // Star glyph.
      _drawStarShape(canvas, Offset(cx, cy), 6, const Color(0xFF1F2937));
    }
  }

  void _drawStarShape(Canvas canvas, Offset center, double r, Color color) {
    final path = Path();
    const points = 5;
    for (var i = 0; i < points * 2; i++) {
      final angle = -pi / 2 + (i * pi) / points;
      final radius = i.isEven ? r : r * 0.45;
      final px = center.dx + cos(angle) * radius;
      final py = center.dy + sin(angle) * radius;
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  // ─────────────────────────────────────────────────────────────
  // Shocks / Particles / Star sparkles.
  // ─────────────────────────────────────────────────────────────
  void _drawShocks(Canvas canvas) {
    for (final s in shocks) {
      final alpha = s.life.clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(s.x, s.y),
        s.r,
        Paint()
          ..color = s.color.withValues(alpha: alpha * 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4,
      );
    }
  }

  void _drawParticles(Canvas canvas) {
    for (final p in particles) {
      final alpha = (p.life / 0.6).clamp(0.0, 1.0);
      canvas.save();
      canvas.translate(p.x, p.y);
      canvas.rotate(p.rotation);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: 7, height: 4),
        Paint()..color = p.color.withValues(alpha: alpha),
      );
      canvas.restore();
    }
  }

  void _drawSparkles(Canvas canvas) {
    for (final s in sparkles) {
      final alpha = (s.life / 0.5).clamp(0.0, 1.0);
      canvas.save();
      canvas.translate(s.x, s.y);
      canvas.rotate(s.rot);
      final path = Path();
      const points = 4;
      for (var i = 0; i < points * 2; i++) {
        final angle = (i * pi) / points;
        final radius = i.isEven ? 5.0 : 1.8;
        final px = cos(angle) * radius;
        final py = sin(angle) * radius;
        if (i == 0) {
          path.moveTo(px, py);
        } else {
          path.lineTo(px, py);
        }
      }
      path.close();
      canvas.drawPath(path, Paint()..color = s.color.withValues(alpha: alpha));
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.6 * alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6,
      );
      canvas.restore();
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Player ship — flagship starship: angular hull, cyan swept wings,
  // bright canopy dome with kawaii pilot, twin flame thrusters.
  // ─────────────────────────────────────────────────────────────
  void _drawPlayer(Canvas canvas) {
    canvas.save();
    canvas.translate(ship.dx, ship.dy);
    canvas.rotate(shipTilt);

    // ── Twin flame thrusters (animated). ──────────────────────
    for (final side in [-1, 1]) {
      final flicker = 0.7 + 0.3 * sin(flameTime * 32 + side);
      final flameH = 28 * flicker;
      final flamePath = Path()
        ..moveTo(side * 8 - 4, 16)
        ..quadraticBezierTo(side * 8, 16 + flameH, side * 8 + 4, 16)
        ..close();
      // Outer glow.
      canvas.drawPath(
        flamePath,
        Paint()
          ..color = const Color(0xFFFB923C).withValues(alpha: 0.45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      // Inner flame.
      canvas.drawPath(
        flamePath,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [
              Color(0xFFFEF08A),
              Color(0xFFFB923C),
              Color(0xFFEF4444),
            ],
          ).createShader(Rect.fromLTWH(side * 8 - 4, 16, 8, flameH)),
      );
      // Blue hot core.
      canvas.drawCircle(
        Offset(side * 8, 18),
        2.4,
        Paint()..color = Colors.white,
      );
    }

    // ── Hull silhouette (arrowhead). ──────────────────────────
    final hullPath = Path()
      ..moveTo(0, -22)
      ..lineTo(14, 8)
      ..lineTo(20, 16)
      ..lineTo(8, 18)
      ..lineTo(0, 22)
      ..lineTo(-8, 18)
      ..lineTo(-20, 16)
      ..lineTo(-14, 8)
      ..close();
    // Drop shadow.
    canvas.drawPath(
      hullPath.shift(const Offset(0, 3)),
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );
    // Hull fill — silver/white gradient.
    canvas.drawPath(
      hullPath,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFFFF), Color(0xFFE5E7EB), Color(0xFF9CA3AF)],
          stops: [0.0, 0.55, 1.0],
        ).createShader(hullPath.getBounds()),
    );
    // Hull outline.
    canvas.drawPath(
      hullPath,
      Paint()
        ..color = const Color(0xFF1F2937)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
    // Hull panel detail — center spine.
    canvas.drawLine(
      const Offset(0, -16),
      const Offset(0, 18),
      Paint()
        ..color = const Color(0xFF1F2937).withValues(alpha: 0.45)
        ..strokeWidth = 1.0,
    );

    // ── Cyan swept wings (back layer behind hull). ────────────
    final wingL = Path()
      ..moveTo(-10, 6)
      ..lineTo(-28, 18)
      ..lineTo(-22, 22)
      ..lineTo(-6, 14)
      ..close();
    final wingR = Path()
      ..moveTo(10, 6)
      ..lineTo(28, 18)
      ..lineTo(22, 22)
      ..lineTo(6, 14)
      ..close();
    for (final wing in [wingL, wingR]) {
      canvas.drawPath(
        wing,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF67E8F9), Color(0xFF22D3EE), Color(0xFF0891B2)],
            stops: [0.0, 0.5, 1.0],
          ).createShader(wing.getBounds()),
      );
      canvas.drawPath(
        wing,
        Paint()
          ..color = const Color(0xFF1F2937)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
    }
    // Wing tip lights.
    for (final tip in [const Offset(-25, 20), const Offset(25, 20)]) {
      canvas.drawCircle(
        tip,
        2.2,
        Paint()..color = const Color(0xFFFACC15),
      );
      canvas.drawCircle(
        tip,
        1.0,
        Paint()..color = Colors.white,
      );
    }

    // ── Glossy canopy / cockpit dome. ──────────────────────────
    final canopyRect = Rect.fromCenter(
      center: const Offset(0, -6),
      width: 14,
      height: 18,
    );
    canvas.drawOval(
      canopyRect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.3, -0.5),
          colors: [Color(0xFFBFDBFE), Color(0xFF1E40AF), Color(0xFF1E3A8A)],
          stops: [0.0, 0.55, 1.0],
        ).createShader(canopyRect),
    );
    // Glass highlight.
    canvas.drawOval(
      Rect.fromCenter(
        center: const Offset(-2.5, -10),
        width: 4,
        height: 6,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.75),
    );
    canvas.drawOval(
      canopyRect,
      Paint()
        ..color = const Color(0xFF1F2937)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );

    // ── Hull nose cone marker (red triangle). ─────────────────
    final nosePath = Path()
      ..moveTo(-3, -22)
      ..lineTo(3, -22)
      ..lineTo(0, -16)
      ..close();
    canvas.drawPath(
      nosePath,
      Paint()..color = const Color(0xFFEF4444),
    );
    canvas.drawPath(
      nosePath,
      Paint()
        ..color = const Color(0xFF1F2937)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );

    // ── Side engine vents (yellow glow). ───────────────────────
    for (final side in [-1, 1]) {
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(side * 10, 10),
          width: 4,
          height: 6,
        ),
        Paint()..color = const Color(0xFFFACC15),
      );
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(side * 10, 10),
          width: 4,
          height: 6,
        ),
        Paint()
          ..color = const Color(0xFF1F2937)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );
    }

    canvas.restore();

    // ── Status FX (drawn untransformed). ──────────────────────
    // Invincibility flicker ring.
    if (invincible && (flameTime * 12).floor().isEven) {
      canvas.drawCircle(
        ship,
        28,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    // Shield bubble.
    if (hasShield) {
      final r = 32 + 2 * sin(flameTime * 6);
      // Outer faint halo.
      canvas.drawCircle(
        ship,
        r + 4,
        Paint()
          ..color = const Color(0xFFFACC15).withValues(alpha: 0.10),
      );
      canvas.drawCircle(
        ship,
        r,
        Paint()
          ..color = const Color(0xFFFACC15).withValues(alpha: 0.18),
      );
      canvas.drawCircle(
        ship,
        r,
        Paint()
          ..color = const Color(0xFFFACC15).withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      // Hex grid hint on shield.
      for (var i = 0; i < 6; i++) {
        final a = i * pi / 3 + flameTime * 0.5;
        canvas.drawCircle(
          Offset(ship.dx + cos(a) * r, ship.dy + sin(a) * r),
          1.6,
          Paint()..color = Colors.white.withValues(alpha: 0.7),
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Lasers — neon yellow / cyan / pink with layered glow.
  // Beam weapon renders as a wide, screen-shaking pillar of light.
  // ─────────────────────────────────────────────────────────────
  void _drawLasers(Canvas canvas) {
    for (final l in lasers) {
      final isBeam = l.width >= 12;
      if (isBeam) {
        // ── Beam: thick pillar with multi-layer halo + bolt core.
        // Outer halo (huge + blurred).
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset(l.x, l.y),
            width: l.width * 3.2,
            height: screenH,
          ),
          Paint()
            ..color = l.color.withValues(alpha: 0.18)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
        );
        // Mid glow.
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset(l.x, l.y),
            width: l.width * 1.8,
            height: screenH,
          ),
          Paint()..color = l.color.withValues(alpha: 0.55),
        );
        // Inner beam.
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset(l.x, l.y),
            width: l.width,
            height: screenH,
          ),
          Paint()..color = l.color,
        );
        // White-hot core.
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset(l.x, l.y),
            width: l.width * 0.4,
            height: screenH,
          ),
          Paint()..color = Colors.white,
        );
      } else {
        // ── Bolt: stacked glow + body + white core.
        canvas.drawCircle(
          Offset(l.x, l.y),
          l.width * 1.8,
          Paint()..color = l.color.withValues(alpha: 0.45),
        );
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset(l.x, l.y),
            width: l.width,
            height: 14,
          ),
          Paint()..color = l.color,
        );
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset(l.x, l.y),
            width: l.width * 0.45,
            height: 14,
          ),
          Paint()..color = Colors.white,
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────────
  // 3-D floaters (layered TextPainter passes).
  // ─────────────────────────────────────────────────────────────
  void _drawFloaters(Canvas canvas) {
    for (final f in floaters) {
      final alpha = (f.life / 0.8).clamp(0.0, 1.0);
      if (f.isBig) {
        _draw3DText(
          canvas,
          Offset(f.x, f.y - (0.8 - f.life) * 24),
          f.text,
          f.color,
          f.fontSize,
          alpha,
        );
      } else {
        final tp = TextPainter(
          text: TextSpan(
            text: f.text,
            style: TextStyle(
              color: f.color.withValues(alpha: alpha),
              fontSize: f.fontSize,
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

  // ─────────────────────────────────────────────────────────────
  // Wave-clear banner (kept).
  // ─────────────────────────────────────────────────────────────
  void _drawWaveClear(Canvas canvas) {
    if (waveClearTimer <= 0) return;
    final totalMs = 1800.0;
    final t = (waveClearTimer / totalMs).clamp(0.0, 1.0);
    final alpha = t > 0.15 ? 1.0 : (t / 0.15);
    final scale = t > 0.15
        ? (1.0 + 0.4 * (1 - (t - 0.15) / 0.85))
        : (0.5 + 1.0 * (t / 0.15));
    canvas.save();
    canvas.translate(screenW / 2, screenH * 0.4);
    canvas.scale(scale);
    final tp = TextPainter(
      text: TextSpan(
        text: 'WAVE $wave CLEAR!',
        style: TextStyle(
          color: const Color(0xFFFB923C).withValues(alpha: alpha),
          fontSize: 36,
          fontWeight: FontWeight.w900,
          letterSpacing: 2,
          shadows: const [
            Shadow(blurRadius: 16, color: Color(0xAAFB923C)),
            Shadow(blurRadius: 4, color: Colors.black87),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SpacePainter old) =>
      old.ship != ship ||
      old.shipTilt != shipTilt ||
      old.flameTime != flameTime ||
      old.idleTime != idleTime ||
      old.invincible != invincible ||
      old.stars != stars ||
      old.aliens != aliens ||
      old.asteroids != asteroids ||
      old.alienLasers != alienLasers ||
      old.lasers != lasers ||
      old.powerUps != powerUps ||
      old.coins != coins ||
      old.particles != particles ||
      old.sparkles != sparkles ||
      old.shocks != shocks ||
      old.floaters != floaters ||
      old.hasShield != hasShield ||
      old.weapon != weapon ||
      old.waveClearTimer != waveClearTimer;
}
