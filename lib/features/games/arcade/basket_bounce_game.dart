import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../mini_game.dart';
import '../widgets/tutorial_overlay.dart';

/// Basket Bounce — physics-based arcade basketball.
///
/// Visual upgrade (plan: gentle-dazzling-river):
///   * Warm hardwood court + bright blue wall + soft daylight + floating
///     confetti + free-throw key + 3-point arc.
///   * Top HUD bar — circular white Pause + Level badge pill on left, dual
///     rounded `SCORE` + `HIGH-TIME` cards centred, basketball-lives pill
///     on right (replacing the legacy dark ScoreChip / MissesChip).
///   * Kawaii vector basketball with thick dark outlines + glossy
///     highlight + eyes + blush + smile (face fades during flight).
///   * Smooth curved **dotted trajectory arc** preview.
///   * Floating star collectables along the arc that score `+20 x STAR`.
///   * Vibrant 3-D `SWISH! +N` glossy pop-up surrounded by star sparkles
///     + screen vibration.
///   * First-launch tutorial overlay — capsule + animated cartoon hand
///     pointing at the launcher.
///   * Direct `HapticFeedback.lightImpact / mediumImpact / heavyImpact /
///     selectionClick` calls (per spec). Host-proxy calls kept as a
///     fallback for audio cue compatibility.
///
/// Engine preserved from previous version: spring-loaded launcher pad,
/// drag-and-release launch, gravity + rim-circle bounce + backboard
/// bounce + net AABB settle, swish detection, score floaters, 5-star
/// burst, particle trail, release-flash particle ring, rim shake, net
/// sway, game-over at 3 misses.
///
/// Public surface kept byte-identical with the previous engine so the
/// dispatcher (`case 'basket-bounce'`) keeps resolving:
///   `class BasketBounceGame extends MiniGame`
///   `const BasketBounceGame({super.key, required super.callbacks})`
class BasketBounceGame extends MiniGame {
  const BasketBounceGame({super.key, required super.callbacks});

  @override
  State<BasketBounceGame> createState() => _BasketBounceState();
}

class _BasketBounceState extends MiniGameState<BasketBounceGame>
    with TickerProviderStateMixin {
  // ─────────────────────────────────────────────────────────────────
  // Tuning constants
  // ─────────────────────────────────────────────────────────────────

  // Launch and trajectory tuning lives at file scope so the painter can
  // reuse the exact same numbers and the preview arc lands where the
  // ball actually lands.
  static const double kBasketGravity = 400; // px/s²
  static const double kBasketBaseLaunchSpeed = 850; // px/s at power=1
  static const double kBasketHoopYFactor = 0.42; // y = screenH * factor

  static const double _gravity = kBasketGravity;
  static const double _hoopHitTolerance = 50; // wider than visual rim so edge shots count
  static const double _rimRestitution = 0.65;
  static const double _backboardRestitution = 0.4;
  static const int _comboThreshold = 3;
  static const int _maxMisses = 3;
  static const double _tutorialDuration = 6.0; // auto-dismiss seconds
  static const double _baseLaunchSpeed = kBasketBaseLaunchSpeed;
  // Hoop is mounted in the upper portion of the court but low enough
  // that a normal drag can clear it. y = 0.20 * screenH left shots
  // falling ~ 486 px short on every moderate drag; 0.42 keeps the
  // gap ~ 300 px, which the launch speed + reduced gravity can
  // actually reach.
  static const double _hoopYFactor = kBasketHoopYFactor;

  // ─────────────────────────────────────────────────────────────────
  // State
  // ─────────────────────────────────────────────────────────────────

  late final Ticker _ticker;
  late final Ticker _idleTicker;
  DateTime _last = DateTime.now();

  Offset _launcher = Offset.zero;
  Offset _hoopCenter = Offset.zero;
  double _hoopRadius = 30; // half the rim width

  // Drag state.
  Offset? _dragStart;
  Offset? _dragCurrent;
  bool _ballInFlight = false;
  bool _scoredThisShot = false;
  bool _swish = false;
  bool _rimContact = false;
  double _aimHapticAcc = 0;

  // Physics ball.
  Offset _ballPos = Offset.zero;
  Offset _ballVel = Offset.zero;

  // Rim shake.
  double _rimShakeLife = 0;
  double _rimShakeMag = 0;

  // Net sway — per-strand phase + amplitude (post-shot impulse).
  final List<double> _netPhase = List.generate(5, (_) => 0);
  final List<double> _netAmp = List.generate(5, (_) => 0.0);

  // Ball-in-net settling.
  bool _ballInNet = false;
  double _netSettleLife = 0;

  // Score.
  int _score = 0;
  int _shotsTaken = 0;
  int _shotsMade = 0;
  int _shotsMissed = 0;
  int _comboStreak = 0;
  bool _gameOver = false;

  final List<_Floater> _floaters = [];
  final List<_Star> _stars = [];
  final List<_Trail> _trail = [];
  final List<_Particle> _particles = [];
  final List<_Confetti> _confetti = [];
  final List<_StarTarget> _starTargets = [];
  final List<_SwishSparkle> _swishSparkles = [];

  double _screenW = 0;
  double _screenH = 0;

  // Per-frame elapsed (drives idle pulse on spring + tutorial hand).
  double _idleTime = 0;
  // Trail emission throttle.
  double _trailTimer = 0;

  // Confetti & star target spawn timers.
  int _confettiTimer = 0;
  int _starTimer = 0;

  // Tutorial state.
  bool _showTutorial = true;
  // ignore: prefer_final_fields
  double _tutorialElapsed = 0;
  bool _tutorialDismissed = false;

  // Streak / high-time tracking.
  double _currentStreakSeconds = 0;
  double _highTimeSeconds = 0;
  bool _lastShotScored = false;

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

  void _onIdle(Duration _) {
    _idleTime += 1 / 60;
  }

  // ─────────────────────────────────────────────────────────────────
  // Main tick
  // ─────────────────────────────────────────────────────────────────

  void _tick(Duration _) {
    if (!mounted || _screenW == 0) return;
    if (_gameOver) {
      if (_ticker.isActive) _ticker.stop();
      return;
    }
    final now = DateTime.now();
    final dt = now.difference(_last).inMicroseconds / 1e6;
    _last = now;
    _idleTime += dt;

    setState(() {
      // VFX always animate.
      _animateFloaters(dt);
      _animateStars(dt);
      _animateTrail(dt);
      _animateParticles(dt);
      _animateConfetti(dt);
      _animateStarTargets(dt);
      _animateSwishSparkles(dt);
      _animateNet(dt);
      if (_rimShakeLife > 0) {
        _rimShakeLife = (_rimShakeLife - dt).clamp(0.0, 99.0);
      }

      // Streak timer ticks up while the ball is at rest on the launcher
      // (i.e. between shots, a successful streak is "alive").
      if (_lastShotScored) {
        _currentStreakSeconds += dt;
        if (_currentStreakSeconds > _highTimeSeconds) {
          _highTimeSeconds = _currentStreakSeconds;
          _refreshStats();
        }
      }

      if (!_ballInFlight || _gameOver) return;

      // Ball-in-net settle (post-score): drop slowly and damp.
      if (_ballInNet) {
        _ballPos = _ballPos + Offset(0, 8) + _ballVel * 0.1 * dt;
        _ballVel = _ballVel * (1 - dt * 4);
        _netSettleLife -= dt;
        if (_netSettleLife <= 0) {
          _ballInFlight = false;
          _ballInNet = false;
          _resetBallToLauncher();
        }
        return;
      }

      // Integrate.
      _ballVel = _ballVel + Offset(0, _gravity * dt);
      _ballPos = _ballPos + _ballVel * dt;

      // Particle trail.
      _trailTimer -= dt;
      if (_trailTimer <= 0) {
        _trailTimer = 0.03;
        _trail.add(_Trail(
          x: _ballPos.dx,
          y: _ballPos.dy,
          life: 0.45,
        ));
        if (_trail.length > 32) _trail.removeAt(0);
      }

      // Star target collisions.
      for (final s in _starTargets.toList()) {
        if ((Offset(s.x, s.y) - _ballPos).distance < 22) {
          _onStarHit(s);
        }
      }
      _starTargets.removeWhere((s) => s.dead);

      // Rim collision (two rim circles, left + right end of ellipse).
      _resolveRimCollision();

      // Backboard collision (shooter-square + outer rect).
      _resolveBackboardCollision();

      // Net bounds (AABB) — when ball enters net region, lock in.
      _resolveNetBounds();

      // Hoop scoring (must pass through opening downward).
      if (!_scoredThisShot &&
          _ballPos.dy > _hoopCenter.dy - 8 &&
          _ballPos.dy < _hoopCenter.dy + 12 &&
          (_ballPos.dx - _hoopCenter.dx).abs() < _hoopHitTolerance &&
          _ballVel.dy > 0) {
        _onScore();
      }

      // Out of canvas.
      if (_ballPos.dy > _screenH + 60 ||
          _ballPos.dx < -60 ||
          _ballPos.dx > _screenW + 60) {
        _ballInFlight = false;
        if (!_scoredThisShot) {
          _shotsMissed += 1;
          _comboStreak = 0;
          _currentStreakSeconds = 0;
          _lastShotScored = false;
          HapticFeedback.lightImpact();
          reportStats(
              'Shots $_shotsMade/$_shotsTaken  •  Misses $_shotsMissed/$_maxMisses');
          if (_shotsMissed >= _maxMisses) {
            _gameOver = true;
            HapticFeedback.heavyImpact();
            reportScore(_score);
            reportStats('Final: $_shotsMade/$_shotsTaken made');
            reportGameOver();
          }
        }
        _resetBallToLauncher();
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────
  // Physics resolvers
  // ─────────────────────────────────────────────────────────────────

  void _resolveRimCollision() {
    const ballR = 18.0;
    final rimLeftCenter = Offset(_hoopCenter.dx - _hoopRadius, _hoopCenter.dy);
    final rimRightCenter = Offset(_hoopCenter.dx + _hoopRadius, _hoopCenter.dy);
    for (final rc in [rimLeftCenter, rimRightCenter]) {
      final diff = _ballPos - rc;
      final d = diff.distance;
      final minDist = ballR + 6; // rim thickness ~6
      if (d < minDist && d > 0.0001) {
        _rimContact = true;
        // Shake the rim.
        _rimShakeLife = 0.28;
        _rimShakeMag = 4.0;
        // Spark burst at contact.
        for (var i = 0; i < 6; i++) {
          final a = (i / 6) * 2 * pi;
          _particles.add(_Particle(
            x: rc.dx + cos(a) * 6,
            y: rc.dy + sin(a) * 6,
            vx: cos(a) * (60 + _rngStub() * 40),
            vy: sin(a) * (60 + _rngStub() * 40),
            life: 0.45,
            color: const Color(0xFFFB923C),
          ));
        }
        // Reflect velocity along the contact normal with restitution.
        final n = diff / d;
        final vDotN = _ballVel.dx * n.dx + _ballVel.dy * n.dy;
        if (vDotN < 0) {
          _ballVel = _ballVel - n * vDotN * (1 + _rimRestitution);
        }
        // Positional correction: push ball out of rim.
        _ballPos = rc + n * minDist;
        HapticFeedback.lightImpact();
      }
    }
  }

  void _resolveBackboardCollision() {
    final boardRect = Rect.fromCenter(
      center: Offset(_hoopCenter.dx, _hoopCenter.dy - 30),
      width: 80,
      height: 60,
    );
    if (_ballPos.dx > boardRect.left - 18 &&
        _ballPos.dx < boardRect.right + 18 &&
        _ballPos.dy > boardRect.top - 18 &&
        _ballPos.dy < boardRect.bottom + 18) {
      // Determine side of contact.
      final overlapLeft = (_ballPos.dx + 18) - boardRect.left;
      final overlapRight = boardRect.right - (_ballPos.dx - 18);
      final overlapTop = (_ballPos.dy + 18) - boardRect.top;
      final overlapBottom = boardRect.bottom - (_ballPos.dy - 18);
      final minOverlap = [overlapLeft, overlapRight, overlapTop, overlapBottom]
          .reduce(min);
      if (minOverlap == overlapLeft && _ballVel.dx > 0) {
        _ballVel = Offset(-_ballVel.dx * _backboardRestitution, _ballVel.dy);
        _ballPos = Offset(boardRect.left - 18, _ballPos.dy);
      } else if (minOverlap == overlapRight && _ballVel.dx < 0) {
        _ballVel = Offset(-_ballVel.dx * _backboardRestitution, _ballVel.dy);
        _ballPos = Offset(boardRect.right + 18, _ballPos.dy);
      } else if (minOverlap == overlapTop && _ballVel.dy > 0) {
        _ballVel = Offset(_ballVel.dx, -_ballVel.dy * _backboardRestitution);
        _ballPos = Offset(_ballPos.dx, boardRect.top - 18);
      } else if (minOverlap == overlapBottom && _ballVel.dy < 0) {
        _ballVel = Offset(_ballVel.dx, -_ballVel.dy * _backboardRestitution);
        _ballPos = Offset(_ballPos.dx, boardRect.bottom + 18);
      }
      _rimContact = true; // counts as "not swish"
      HapticFeedback.lightImpact();
    }
  }

  void _resolveNetBounds() {
    // Net AABB starts at hoop top, extends downward by netDepth.
    final netRect = Rect.fromLTRB(
      _hoopCenter.dx - _hoopRadius + 4,
      _hoopCenter.dy + 6,
      _hoopCenter.dx + _hoopRadius - 4,
      _hoopCenter.dy + 60,
    );
    if (_scoredThisShot &&
        _ballPos.dx > netRect.left &&
        _ballPos.dx < netRect.right &&
        _ballPos.dy > netRect.top &&
        _ballPos.dy < netRect.bottom &&
        _ballVel.dy > 0) {
      // Push the net strands.
      for (var i = 0; i < _netAmp.length; i++) {
        _netAmp[i] = (_netAmp[i] + 0.6).clamp(0.0, 4.0);
        _netPhase[i] = i * 0.4;
      }
      _ballInNet = true;
      _netSettleLife = 0.7;
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // Scoring + spawn lifecycle
  // ─────────────────────────────────────────────────────────────────

  void _onScore() {
    _scoredThisShot = true;
    _lastShotScored = true;
    _comboStreak += 1;
    _swish = !_rimContact;
    final comboMul = _comboStreak >= _comboThreshold ? 3 : 1;
    final swishMul = _swish ? 1.5 : 1.0;
    final base = 50;
    final points = (base * comboMul * swishMul).round();
    _score += points;
    _shotsMade += 1;

    if (_swish) {
      // Big sparkles for SWISH.
      for (var i = 0; i < 12; i++) {
        final a = (i / 12) * 2 * pi;
        _swishSparkles.add(_SwishSparkle(
          x: _hoopCenter.dx,
          y: _hoopCenter.dy,
          vx: cos(a) * (90 + _rngStub() * 50),
          vy: sin(a) * (90 + _rngStub() * 50),
          life: 1.2,
          size: 6 + _rngStub() * 4,
        ));
      }
      // Screen vibration (subtle).
      _rimShakeLife = 0.40;
      _rimShakeMag = 6.0;
      // Net sway impulse on swish.
      for (var i = 0; i < _netAmp.length; i++) {
        _netAmp[i] = (_netAmp[i] + 3.0).clamp(0.0, 5.0);
        _netPhase[i] = i * 0.45;
      }
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.mediumImpact();
    }

    final banner = _swish && comboMul > 1
        ? 'SWISH! +$points (${comboMul}x COMBO)'
        : _swish
            ? 'SWISH! +$points'
            : comboMul > 1
                ? '+$points (${comboMul}x)'
                : '+$points';

    _floaters.add(_Floater(
      x: _ballPos.dx,
      y: _ballPos.dy - 30,
      text: banner,
      color: _swish
          ? const Color(0xFFFDE047)
          : comboMul > 1
              ? const Color(0xFFFF5983)
              : Colors.white,
      fontSize: _swish ? 28 : 22,
    ));

    // 5-star burst around hoop.
    for (var i = 0; i < 5; i++) {
      final a = (i / 5) * 2 * pi;
      _stars.add(_Star(
        x: _hoopCenter.dx + cos(a) * 30 + (i.isEven ? 6 : -6),
        y: _hoopCenter.dy - 8 + sin(a) * 18,
        life: 0.7,
        rot: a,
      ));
    }
    // Big particle burst at the score spot.
    for (var i = 0; i < 12; i++) {
      final a = (i / 12) * 2 * pi;
      _particles.add(_Particle(
        x: _hoopCenter.dx,
        y: _hoopCenter.dy,
        vx: cos(a) * (80 + _rngStub() * 60),
        vy: sin(a) * (80 + _rngStub() * 60),
        life: 0.6,
        color: _swish ? const Color(0xFFFDE047) : const Color(0xFFFFC837),
      ));
    }
    reportScore(_score);
    _refreshStats();
  }

  void _onStarHit(_StarTarget s) {
    s.dead = true;
    final points = 20;
    _score += points;
    _floaters.add(_Floater(
      x: s.x,
      y: s.y - 16,
      text: '+$points x STAR',
      color: const Color(0xFFFACC15),
      fontSize: 18,
    ));
    for (var i = 0; i < 8; i++) {
      final a = (i / 8) * 2 * pi;
      _particles.add(_Particle(
        x: s.x,
        y: s.y,
        vx: cos(a) * (50 + _rngStub() * 30),
        vy: sin(a) * (50 + _rngStub() * 30),
        life: 0.4,
        color: const Color(0xFFFACC15),
      ));
    }
    HapticFeedback.mediumImpact();
    reportScore(_score);
    _refreshStats();
  }

  void _resetBallToLauncher() {
    _ballPos = _launcher;
    _ballVel = Offset.zero;
    _scoredThisShot = false;
    _swish = false;
    _rimContact = false;
  }

  // ─────────────────────────────────────────────────────────────────
  // Confetti + star target spawning
  // ─────────────────────────────────────────────────────────────────

  void _spawnConfetti() {
    _confetti.add(_Confetti(
      x: _rngStub() * _screenW,
      y: -20 - _rngStub() * 30,
      vx: (_rngStub() - 0.5) * 60,
      vy: 60 + _rngStub() * 60,
      rot: _rngStub() * 2 * pi,
      rotV: (_rngStub() - 0.5) * 6,
      color: _confettiPalette[(_rngStub() * _confettiPalette.length).floor() %
          _confettiPalette.length],
      life: 6.0 + _rngStub() * 2,
      size: 5 + _rngStub() * 4,
    ));
  }

  void _spawnStarTarget() {
    // Spawn at typical apex of arc between launcher and hoop.
    final apexX = _launcher.dx + (_hoopCenter.dx - _launcher.dx) * 0.55;
    final apexY = _launcher.dy - 220; // above launcher
    _starTargets.add(_StarTarget(
      x: apexX,
      y: apexY,
      bobSeed: _rngStub() * 6.28,
    ));
  }

  // ─────────────────────────────────────────────────────────────────
  // VFX animators
  // ─────────────────────────────────────────────────────────────────

  void _animateFloaters(double dt) {
    for (final f in _floaters) {
      f.y -= 50 * dt;
      f.life -= dt;
    }
    _floaters.removeWhere((f) => f.life <= 0);
  }

  void _animateStars(double dt) {
    for (final s in _stars) {
      s.life -= dt;
    }
    _stars.removeWhere((s) => s.life <= 0);
  }

  void _animateTrail(double dt) {
    for (final t in _trail) {
      t.life -= dt;
      t.r += 14 * dt;
    }
    _trail.removeWhere((t) => t.life <= 0);
  }

  void _animateParticles(double dt) {
    for (final p in _particles) {
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vy += 120 * dt; // gravity on particles
      p.life -= dt;
    }
    _particles.removeWhere((p) => p.life <= 0);
  }

  void _animateConfetti(double dt) {
    final ms = (dt * 1000).round();
    _confettiTimer += ms;
    if (_confettiTimer > 700 && _screenW > 0) {
      _confettiTimer = 0;
      _spawnConfetti();
    }
    for (final c in _confetti) {
      c.x += c.vx * dt;
      c.y += c.vy * dt;
      c.rot += c.rotV * dt;
      c.vy += 30 * dt; // light gravity (paper feel)
      c.life -= dt;
    }
    _confetti.removeWhere((c) =>
        c.life <= 0 || c.y > _screenH + 60);
  }

  void _animateStarTargets(double dt) {
    final ms = (dt * 1000).round();
    _starTimer += ms;
    if (_starTimer > 6000 && _screenW > 0) {
      _starTimer = 0;
      _spawnStarTarget();
    }
    // Gentle bob is computed in the painter via idleTime.
  }

  void _animateSwishSparkles(double dt) {
    for (final s in _swishSparkles) {
      s.x += s.vx * dt;
      s.y += s.vy * dt;
      s.vy += 90 * dt;
      s.life -= dt;
    }
    _swishSparkles.removeWhere((s) => s.life <= 0);
  }

  void _animateNet(double dt) {
    for (var i = 0; i < _netAmp.length; i++) {
      _netPhase[i] += dt * 4;
      _netAmp[i] = (_netAmp[i] - dt * 3).clamp(0.0, 5.0);
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // Input
  // ─────────────────────────────────────────────────────────────────

  void _onPanStart(DragStartDetails d) {
    if (_gameOver || _ballInFlight) return;
    if ((d.localPosition - _launcher).distance > 200) return;
    setState(() {
      _dragStart = d.localPosition;
      _dragCurrent = d.localPosition;
      _aimHapticAcc = 0;
    });
    _dismissTutorial();
    HapticFeedback.lightImpact();
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_gameOver || _ballInFlight) return;
    setState(() {
      _dragCurrent = d.localPosition;
      // Aim haptic every ~80 ms of drag distance.
      if (_dragStart != null && _dragCurrent != null) {
        final dDist =
            (_dragCurrent! - _dragStart!).distance;
        // No movement → nothing to buzz. As drag grows, fire at intervals.
        if (dDist > 20) {
          _aimHapticAcc += d.delta.dx.abs() + d.delta.dy.abs();
          if (_aimHapticAcc > 30) {
            _aimHapticAcc = 0;
            HapticFeedback.selectionClick();
          }
        }
      }
    });
  }

  void _onPanEnd(DragEndDetails _) {
    if (_gameOver || _ballInFlight || _dragStart == null || _dragCurrent == null) {
      return;
    }
    final drag = _dragCurrent! - _dragStart!;
    if (drag.distance < 20) return;
    final angle = atan2(-drag.dy, -drag.dx);
    // Match the trajectory-preview formula exactly (line 1827) so the
    // ball lands where the dotted arc promised.
    final power = (drag.distance / 200).clamp(0.4, 1.4);
    final speed =
        _baseLaunchSpeed * power * (drag.distance / 100).clamp(0.5, 1.4);
    setState(() {
      _ballInFlight = true;
      _scoredThisShot = false;
      _swish = false;
      _rimContact = false;
      _ballPos = _launcher;
      _ballVel = Offset(cos(angle) * speed, sin(angle) * speed);
      _shotsTaken += 1;
      _dragStart = null;
      _dragCurrent = null;
      // Release-flash particle ring around the launcher pad.
      for (var i = 0; i < 12; i++) {
        final a = (i / 12) * 2 * pi;
        _particles.add(_Particle(
          x: _launcher.dx,
          y: _launcher.dy,
          vx: cos(a) * 90,
          vy: sin(a) * 90,
          life: 0.4,
          color: const Color(0xFFFB923C),
        ));
      }
      _lastShotScored = false;
    });
    HapticFeedback.mediumImpact();
  }

  void _dismissTutorial() {
    if (_tutorialDismissed) return;
    _tutorialDismissed = true;
    _showTutorial = false;
  }

  // Cheap deterministic 0..1.
  double _rngStub() {
    // Reuse a private Random so confetti & star positions vary but
    // animation frame-to-frame is stable.
    return Random().nextDouble();
  }

  // ─────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────

  void _refreshStats() {
    final htSec = _highTimeSeconds.round();
    reportStats(
        'Shots $_shotsMade/$_shotsTaken  •  Misses $_shotsMissed/$_maxMisses  •  Best ${htSec}s');
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final firstFrame = _launcher == Offset.zero;
        _screenW = c.maxWidth;
        _screenH = c.maxHeight;
        _launcher = Offset(_screenW / 2, _screenH - 130);
        // Hoop mounted on the right side per spec.
        _hoopCenter = Offset(_screenW * 0.78, _screenH * _hoopYFactor);
        _hoopRadius = 30;
        if (firstFrame) {
          _ballPos = _launcher;
        }
        return Stack(
          children: [
            // Subtle pause-aware dim overlay so taps still register.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: _onPanStart,
                onPanUpdate: _onPanUpdate,
                onPanEnd: _onPanEnd,
                child: CustomPaint(
                  painter: _BasketPainter(
                    launcher: _launcher,
                    hoop: _hoopCenter,
                    hoopRadius: _hoopRadius,
                    rimShakeDx: _rimShakeLife > 0
                        ? (_rngStub() - 0.5) * _rimShakeMag
                        : 0,
                    rimShakeDy: _rimShakeLife > 0
                        ? (_rngStub() - 0.5) * _rimShakeMag
                        : 0,
                    dragStart: _dragStart,
                    dragCurrent: _dragCurrent,
                    ballPos: _ballPos,
                    ballInFlight: _ballInFlight,
                    idleTime: _idleTime,
                    floaters: _floaters,
                    stars: _stars,
                    trail: _trail,
                    particles: _particles,
                    confetti: _confetti,
                    starTargets: _starTargets,
                    swishSparkles: _swishSparkles,
                    netPhase: _netPhase,
                    netAmp: _netAmp,
                    score: _score,
                    highTimeSeconds: _highTimeSeconds.round(),
                  ),
                ),
              ),
            ),
            // Pause overlay removed — host GameContainerScreen provides it.
            // Top HUD removed — host GameContainerScreen provides it.
            // Tutorial overlay (above the canvas, near the launcher).
            if (_showTutorial && !_gameOver)
              Positioned(
                left: 0,
                right: 0,
                bottom: 130,
                child: TutorialOverlay(
                  idleTime: _idleTime,
                  progress: (_tutorialElapsed / _tutorialDuration).clamp(0.0, 1.0),
                  message: 'Drag & Release to Aim!',
                  handTilt: 0.4,
                  pointDown: true,
                ),
              ),
            // Game Over overlay removed — host GameContainerScreen provides it.
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// VFX records
// ─────────────────────────────────────────────────────────────────

class _Floater {
  _Floater({
    required this.x,
    required this.y,
    required this.text,
    required this.color,
    this.fontSize = 18,
  }) : life = 1.0;
  double x;
  double y;
  String text;
  Color color;
  double fontSize;
  double life;
}

class _Star {
  _Star({required this.x, required this.y, required this.life, this.rot = 0});
  double x;
  double y;
  double life;
  double rot;
}

class _Trail {
  _Trail({required this.x, required this.y, required this.life}) : r = 0;
  double x;
  double y;
  double r;
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
  });
  double x;
  double y;
  double vx;
  double vy;
  double life;
  Color color;
}

class _Confetti {
  _Confetti({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.rot,
    required this.rotV,
    required this.color,
    required this.life,
    required this.size,
  });
  double x;
  double y;
  double vx;
  double vy;
  double rot;
  double rotV;
  Color color;
  double life;
  double size;
}

class _StarTarget {
  _StarTarget({
    required this.x,
    required this.y,
    required this.bobSeed,
  });
  double x;
  double y;
  double bobSeed;
  bool dead = false;
}

class _SwishSparkle {
  _SwishSparkle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.life,
    required this.size,
  });
  double x;
  double y;
  double vx;
  double vy;
  double life;
  double size;
}

const List<Color> _confettiPalette = [
  Color(0xFFFCA5A5), // pink
  Color(0xFFBFDBFE), // sky
  Color(0xFFFDE68A), // yellow
  Color(0xFFDDD6FE), // lavender
  Color(0xFF86EFAC), // mint
];

// ─────────────────────────────────────────────────────────────────
// Tutorial overlay
// ─────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────
// Painter
// ─────────────────────────────────────────────────────────────────

class _BasketPainter extends CustomPainter {
  _BasketPainter({
    required this.launcher,
    required this.hoop,
    required this.hoopRadius,
    required this.rimShakeDx,
    required this.rimShakeDy,
    required this.dragStart,
    required this.dragCurrent,
    required this.ballPos,
    required this.ballInFlight,
    required this.idleTime,
    required this.floaters,
    required this.stars,
    required this.trail,
    required this.particles,
    required this.confetti,
    required this.starTargets,
    required this.swishSparkles,
    required this.netPhase,
    required this.netAmp,
    required this.score,
    required this.highTimeSeconds,
  });

  final Offset launcher;
  final Offset hoop;
  final double hoopRadius;
  final double rimShakeDx;
  final double rimShakeDy;
  final Offset? dragStart;
  final Offset? dragCurrent;
  final Offset ballPos;
  final bool ballInFlight;
  final double idleTime;
  final List<_Floater> floaters;
  final List<_Star> stars;
  final List<_Trail> trail;
  final List<_Particle> particles;
  final List<_Confetti> confetti;
  final List<_StarTarget> starTargets;
  final List<_SwishSparkle> swishSparkles;
  final List<double> netPhase;
  final List<double> netAmp;
  final int score;
  final int highTimeSeconds;

  @override
  void paint(Canvas canvas, Size size) {
    _drawCourt(canvas, size);
    _drawConfetti(canvas); // behind entities
    _drawStarTargets(canvas);
    _drawBackboard(canvas, hoop);
    _drawNet(canvas, hoop, hoopRadius);
    _drawRim(canvas, hoop, hoopRadius);
    _drawTrail(canvas);
    _drawParticles(canvas);
    _drawSwishSparkles(canvas);
    _drawSpringAndPad(canvas);
    _drawBall(canvas, ballPos);
    _drawStars(canvas);
    _drawFloaters(canvas);
  }

  // ─────────────────────────────────────────────────────────────
  // Court backdrop (warm hardwood + blue wall)
  // ─────────────────────────────────────────────────────────────

  void _drawCourt(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 1. Blue wall (top 50%).
    final wallH = h * 0.5;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, wallH),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFBAE6FD), Color(0xFF60A5FA), Color(0xFF3B82F6)],
          stops: [0.0, 0.55, 1.0],
        ).createShader(Rect.fromLTWH(0, 0, w, wallH)),
    );
    // Soft daylight highlight top-center.
    canvas.drawCircle(
      Offset(w / 2, h * 0.05),
      w * 0.55,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.45),
            Colors.white.withValues(alpha: 0.0),
          ],
        ).createShader(
          Rect.fromCircle(
            center: Offset(w / 2, h * 0.05),
            radius: w * 0.55,
          ),
        ),
    );

    // Stadium spotlight cones (flagship feel).
    for (final lx in [w * 0.18, w * 0.5, w * 0.82]) {
      final cone = Path()
        ..moveTo(lx, 0)
        ..lineTo(lx + w * 0.18, wallH * 0.65)
        ..lineTo(lx - w * 0.18, wallH * 0.65)
        ..close();
      canvas.drawPath(
        cone,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.10),
      );
      // Bright bulb.
      canvas.drawCircle(
        Offset(lx, 6),
        5,
        Paint()
          ..color = const Color(0xFFFEF3C7)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawCircle(
        Offset(lx, 6),
        2.5,
        Paint()..color = Colors.white,
      );
    }

    // Crowd silhouette band along the upper wall.
    final crowdTop = wallH * 0.18;
    final crowdPaint = Paint()..color = const Color(0xFF1E3A8A).withValues(alpha: 0.45);
    canvas.drawRect(
      Rect.fromLTWH(0, crowdTop, w, 18),
      crowdPaint,
    );
    // Head silhouettes — small bumps.
    final headPaint = Paint()..color = const Color(0xFF1E3A8A).withValues(alpha: 0.65);
    for (var x = 6.0; x < w; x += 18) {
      canvas.drawCircle(
        Offset(x, crowdTop + 6 + (sin(x * 0.3) * 3)),
        5,
        headPaint,
      );
    }

    // 2. Hardwood floor (bottom 50%).
    final floorTop = h * 0.5;
    final floorH = h - floorTop;
    canvas.drawRect(
      Rect.fromLTWH(0, floorTop, w, floorH),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFCD34D), Color(0xFFF59E0B), Color(0xFFB45309)],
          stops: [0.0, 0.55, 1.0],
        ).createShader(Rect.fromLTWH(0, floorTop, w, floorH)),
    );

    // Floor planks (vertical seams, 5 rows).
    final plankPaint = Paint()
      ..color = const Color(0xFF92400E)
      ..strokeWidth = 1.2;
    for (var i = 1; i < 5; i++) {
      final y = floorTop + (floorH / 5) * i;
      canvas.drawLine(Offset(0, y), Offset(w, y), plankPaint);
    }

    // Specular sheen across the floor centre.
    canvas.drawRect(
      Rect.fromLTWH(0, floorTop, w, floorH),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.18),
            Colors.white.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, floorTop, w, floorH)),
    );

    // 3. Free-throw key + 3-point arc + circle.
    final keyTop = floorTop + floorH * 0.18;
    final keyBottom = floorTop + floorH * 0.92;
    final keyTopHalfWidth = 70.0;
    final keyBottomHalfWidth = 110.0;
    final keyPath = Path()
      ..moveTo(w / 2 - keyTopHalfWidth, keyTop)
      ..lineTo(w / 2 - keyBottomHalfWidth, keyBottom)
      ..lineTo(w / 2 + keyBottomHalfWidth, keyBottom)
      ..lineTo(w / 2 + keyTopHalfWidth, keyTop)
      ..close();
    // Fill the key in red semi-transparent.
    canvas.drawPath(
      keyPath,
      Paint()..color = const Color(0xFFEF4444).withValues(alpha: 0.30),
    );
    final keyOutlinePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4;
    canvas.drawPath(keyPath, keyOutlinePaint);
    // Free-throw line.
    canvas.drawLine(
      Offset(w / 2 - keyTopHalfWidth, keyTop),
      Offset(w / 2 + keyTopHalfWidth, keyTop),
      keyOutlinePaint,
    );
    // Free-throw circle (above key, half-circle shown).
    canvas.drawArc(
      Rect.fromCircle(center: Offset(w / 2, keyTop), radius: 36),
      pi,
      pi,
      false,
      keyOutlinePaint,
    );
    // 3-point arc (sweeping curve at the bottom).
    final arcRect = Rect.fromCenter(
      center: Offset(w / 2, keyBottom),
      width: w * 0.7,
      height: h * 0.55,
    );
    canvas.drawArc(arcRect, pi - 1.05, 2.10, false,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.65)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4);
    // Centre-court logo dot.
    final centerY = (floorTop + h) / 2 - 10;
    canvas.drawCircle(
      Offset(w / 2, centerY),
      22,
      Paint()..color = const Color(0xFFFB923C).withValues(alpha: 0.85),
    );
    canvas.drawCircle(
      Offset(w / 2, centerY),
      22,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Confetti + star targets
  // ─────────────────────────────────────────────────────────────

  void _drawConfetti(Canvas canvas) {
    for (final c in confetti) {
      final alpha = (c.life / 4.0).clamp(0.0, 1.0);
      canvas.save();
      canvas.translate(c.x, c.y);
      canvas.rotate(c.rot);
      final rect = Rect.fromCenter(center: Offset.zero, width: c.size, height: c.size * 1.7);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(1.5)),
        Paint()..color = c.color.withValues(alpha: alpha),
      );
      canvas.restore();
    }
  }

  void _drawStarTargets(Canvas canvas) {
    for (final s in starTargets) {
      if (s.dead) continue;
      final bob = sin(idleTime * 3 + s.bobSeed) * 4;
      final cx = s.x;
      final cy = s.y + bob;
      _drawStarIcon(canvas, Offset(cx, cy), 14, const Color(0xFFFACC15));
      // Glow halo.
      canvas.drawCircle(
        Offset(cx, cy),
        22,
        Paint()
          ..color = const Color(0xFFFACC15).withValues(alpha: 0.15),
      );
    }
  }

  void _drawStarIcon(Canvas canvas, Offset c, double size, Color fill) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final angle = -pi / 2 + (i / 5) * pi;
      final r = i.isEven ? size : size * 0.45;
      final p = Offset(c.dx + cos(angle) * r, c.dy + sin(angle) * r);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF1F2937)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    canvas.drawCircle(
      Offset(c.dx, c.dy),
      size * 0.18,
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Hoop, rim, net
  // ─────────────────────────────────────────────────────────────

  void _drawBackboard(Canvas canvas, Offset hoop) {
    final boardRect = Rect.fromCenter(
      center: Offset(hoop.dx, hoop.dy - 36),
      width: 96,
      height: 64,
    );
    // Mounting arm behind the board.
    canvas.drawRect(
      Rect.fromLTWH(hoop.dx - 4, boardRect.top - 18, 8, 22),
      Paint()..color = const Color(0xFF374151),
    );
    canvas.drawRect(
      Rect.fromLTWH(hoop.dx - 4, boardRect.top - 18, 8, 22),
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    // Shadow.
    canvas.drawRect(
      boardRect.translate(2, 4),
      Paint()..color = Colors.black.withValues(alpha: 0.30),
    );
    // Board frame (dark border around translucent glass).
    canvas.drawRect(
      boardRect,
      Paint()..color = const Color(0xFF1F2937),
    );
    // Inner glass (translucent white).
    final glassRect = Rect.fromLTWH(
      boardRect.left + 4,
      boardRect.top + 4,
      boardRect.width - 8,
      boardRect.height - 8,
    );
    canvas.drawRect(
      glassRect,
      Paint()..color = Colors.white.withValues(alpha: 0.75),
    );
    // Glass highlight (top-left).
    final hl = Path()
      ..moveTo(glassRect.left, glassRect.top)
      ..lineTo(glassRect.left + glassRect.width * 0.5, glassRect.top)
      ..lineTo(glassRect.left, glassRect.top + glassRect.height * 0.4)
      ..close();
    canvas.drawPath(
      hl,
      Paint()..color = Colors.white.withValues(alpha: 0.55),
    );
    // Inner shooter square (red target).
    final inner = Rect.fromCenter(
      center: Offset(boardRect.center.dx, boardRect.bottom - 18),
      width: 36,
      height: 26,
    );
    canvas.drawRect(
      inner,
      Paint()
        ..color = const Color(0xFFEF4444).withValues(alpha: 0.95)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRect(
      inner,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  void _drawRim(Canvas canvas, Offset hoop, double r) {
    final rimCenter = hoop + Offset(rimShakeDx, rimShakeDy);
    // Rim shadow ellipse (front lip depth).
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(rimCenter.dx, rimCenter.dy + 4),
        width: r * 2,
        height: 14,
      ),
      Paint()..color = const Color(0xFFC2410C).withValues(alpha: 0.6),
    );
    // Main rim body (filled ellipse).
    canvas.drawOval(
      Rect.fromCenter(center: rimCenter, width: r * 2, height: 14),
      Paint()..color = const Color(0xFFFB923C),
    );
    // Rim outline.
    canvas.drawOval(
      Rect.fromCenter(center: rimCenter, width: r * 2, height: 14),
      Paint()
        ..color = const Color(0xFFC2410C)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    // Top highlight on the rim (gleaming metal).
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(rimCenter.dx, rimCenter.dy - 2),
        width: r * 1.9,
        height: 4,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.6),
    );
    // Rim connectors to backboard (V-shape mount).
    canvas.drawLine(
      Offset(rimCenter.dx - r, rimCenter.dy),
      Offset(hoop.dx, hoop.dy - 30),
      Paint()
        ..color = const Color(0xFFFB923C)
        ..strokeWidth = 3,
    );
    canvas.drawLine(
      Offset(rimCenter.dx + r, rimCenter.dy),
      Offset(hoop.dx, hoop.dy - 30),
      Paint()
        ..color = const Color(0xFFFB923C)
        ..strokeWidth = 3,
    );
  }

  void _drawNet(Canvas canvas, Offset hoop, double r) {
    final netPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 1.5;
    const rings = 3;
    final netDepth = 50.0;
    final rimLeft = hoop.dx - r + 2;
    final rimRight = hoop.dx + r - 2;
    final rimY = hoop.dy + 4;
    for (var s = 0; s < 5; s++) {
      final t = s / 4;
      final topX = rimLeft + (rimRight - rimLeft) * t;
      final botX = hoop.dx + (topX - hoop.dx) * 0.35;
      final phase = netPhase[s];
      final amp = netAmp[s];
      final sway = sin(phase) * amp;
      final path = Path();
      path.moveTo(topX, rimY);
      for (var i = 1; i <= rings; i++) {
        final ratio = i / rings;
        final y = rimY + netDepth * ratio;
        final x = topX + (botX - topX) * ratio + sway * ratio;
        path.lineTo(x, y);
      }
      canvas.drawPath(path, netPaint);
    }
    // Horizontal rings (connect strands).
    for (var i = 1; i < rings; i++) {
      final ratio = i / rings;
      final y = rimY + netDepth * ratio;
      for (var s = 0; s < 4; s++) {
        final tA = s / 4;
        final tB = (s + 1) / 4;
        final xA = rimLeft + (rimRight - rimLeft) * tA;
        final xB = rimLeft + (rimRight - rimLeft) * tB;
        final midX = (xA + xB) / 2;
        final sway = (sin(netPhase[s] + i) + sin(netPhase[s + 1] + i)) *
            0.5 *
            (netAmp[s] + netAmp[s + 1]) *
            0.25;
        canvas.drawLine(
          Offset(xA + (midX - xA) * ratio + sway * 0.5, y),
          Offset(xB + (midX - xB) * ratio - sway * 0.5, y),
          netPaint,
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Trajectory preview, spring, ball, VFX
  // ─────────────────────────────────────────────────────────────

  void _drawTrail(Canvas canvas) {
    for (final t in trail) {
      final alpha = (t.life / 0.45).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(t.x, t.y),
        6 + t.r,
        Paint()..color = const Color(0xFFFB923C).withValues(alpha: alpha * 0.45),
      );
    }
  }

  void _drawParticles(Canvas canvas) {
    for (final p in particles) {
      final alpha = (p.life / 0.6).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(p.x, p.y),
        3.5,
        Paint()..color = p.color.withValues(alpha: alpha),
      );
    }
  }

  void _drawSwishSparkles(Canvas canvas) {
    for (final s in swishSparkles) {
      final alpha = (s.life / 1.2).clamp(0.0, 1.0);
      final scale = (1 + (1 - s.life / 1.2) * 0.5).clamp(0.0, 2.0);
      canvas.save();
      canvas.translate(s.x, s.y);
      canvas.rotate(s.x + s.y);
      canvas.scale(scale);
      // 4-point star sparkle.
      final path = Path()
        ..moveTo(0, -s.size)
        ..lineTo(s.size * 0.25, -s.size * 0.25)
        ..lineTo(s.size, 0)
        ..lineTo(s.size * 0.25, s.size * 0.25)
        ..lineTo(0, s.size)
        ..lineTo(-s.size * 0.25, s.size * 0.25)
        ..lineTo(-s.size, 0)
        ..lineTo(-s.size * 0.25, -s.size * 0.25)
        ..close();
      canvas.drawPath(
        path,
        Paint()..color = const Color(0xFFFDE047).withValues(alpha: alpha),
      );
      canvas.drawCircle(
        Offset.zero,
        s.size * 0.25,
        Paint()..color = Colors.white.withValues(alpha: alpha * 0.95),
      );
      canvas.restore();
    }
  }

  void _drawSpringAndPad(Canvas canvas) {
    final compress = dragStart != null && dragCurrent != null
        ? ((dragCurrent! - dragStart!).distance / 200).clamp(0.0, 1.0)
        : 0.0;
    final idleBob = sin(idleTime * 2.5) * 2;
    final springTop = launcher.translate(
      0,
      -50 + 24 * compress + idleBob * (1 - compress),
    );
    _drawSpring(canvas, springTop, launcher);

    // Pad base — slim rounded rectangle with gradient + thick outline.
    final padRect = Rect.fromCenter(center: launcher, width: 64, height: 18);
    canvas.drawRRect(
      RRect.fromRectAndRadius(padRect, const Radius.circular(9)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFB74D), Color(0xFFFB923C)],
        ).createShader(padRect),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(padRect, const Radius.circular(9)),
      Paint()
        ..color = const Color(0xFF1F2937)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    // Pad highlight.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(launcher.dx - 26, launcher.dy - 7, 52, 4),
        const Radius.circular(2),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.45),
    );

    // Trajectory preview (only when dragging).
    if (dragStart != null && dragCurrent != null) {
      final drag = dragCurrent! - dragStart!;
      if (drag.distance > 20) {
        final power = (drag.distance / 200).clamp(0.4, 1.4);
        final angle = atan2(-drag.dy, -drag.dx);
        final speed = _BasketBounceState.kBasketBaseLaunchSpeed *
            power *
            (drag.distance / 100).clamp(0.5, 1.4);
        final vx = cos(angle) * speed;
        final vy = sin(angle) * speed;
        const g = _BasketBounceState.kBasketGravity;
        const stepSec = 0.06;
        const numPoints = 14;
        final dots = <Offset>[];
        for (var i = 0; i < numPoints; i++) {
          final t = i * stepSec;
          final px = launcher.dx + vx * t;
          final py = launcher.dy + vy * t + 0.5 * g * t * t;
          dots.add(Offset(px, py));
        }
        // Smooth curved dotted arc: alternating fill / outline.
        for (var i = 0; i < dots.length; i++) {
          final t = i / (dots.length - 1);
          // Taper: dots near launcher are larger.
          final radius = (5.0 * (1 - t) + 2.5 * t).clamp(2.0, 5.0);
          final paint = Paint()
            ..color = Colors.white.withValues(alpha: 0.7);
          if (i.isEven) {
            // Solid dot.
            canvas.drawCircle(dots[i], radius, paint);
          } else {
            // Outline dot.
            paint.style = PaintingStyle.stroke;
            paint.strokeWidth = 1.4;
            canvas.drawCircle(dots[i], radius, paint);
          }
        }
        // Aim guide line.
        canvas.drawLine(
          dragStart!,
          dragCurrent!,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.45)
            ..strokeWidth = 4
            ..strokeCap = StrokeCap.round,
        );
      }
    }
  }

  void _drawSpring(Canvas canvas, Offset top, Offset bottom) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final path = Path();
    path.moveTo(top.dx, top.dy);
    final segments = 5;
    final dy = (bottom.dy - top.dy) / segments;
    for (var i = 0; i < segments; i++) {
      final y = top.dy + dy * i;
      final left = Offset(top.dx - 12, y + dy * 0.25);
      final right = Offset(top.dx + 12, y + dy * 0.75);
      if (i.isEven) {
        path.lineTo(left.dx, left.dy);
        path.lineTo(right.dx, right.dy);
      } else {
        path.lineTo(right.dx, right.dy);
        path.lineTo(left.dx, left.dy);
      }
    }
    path.lineTo(bottom.dx, bottom.dy);
    canvas.drawPath(path, paint);
    // Spring top cap.
    canvas.drawCircle(
      top,
      6,
      Paint()..color = const Color(0xFFFB923C),
    );
    canvas.drawCircle(
      top,
      6,
      Paint()
        ..color = const Color(0xFF1F2937)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
  }

  void _drawBall(Canvas canvas, Offset c) {
    // Shadow.
    canvas.drawCircle(
      c.translate(2, 3),
      18,
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );
    // Body (gradient + thick dark outline).
    final bodyRect = Rect.fromCircle(center: c, radius: 18);
    canvas.drawCircle(
      c,
      18,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.3, -0.4),
          colors: [Color(0xFFFFB74D), Color(0xFFE65100)],
        ).createShader(bodyRect),
    );
    canvas.drawCircle(
      c,
      18,
      Paint()
        ..color = const Color(0xFF1F2937)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // Seams.
    final seamPaint = Paint()
      ..color = const Color(0xFF1F2937)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(c.dx - 18, c.dy),
      Offset(c.dx + 18, c.dy),
      seamPaint,
    );
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: 18),
      -2.5,
      1.8,
      false,
      seamPaint,
    );
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: 18),
      0.7,
      1.8,
      false,
      seamPaint,
    );

    // Glossy highlight.
    canvas.drawCircle(
      c.translate(-6, -7),
      5,
      Paint()..color = Colors.white.withValues(alpha: 0.45),
    );

    // Kawaii face — only when ball is at rest on launcher.
    if (!ballInFlight) {
      // Two white oval eyes.
      final eyePaint = Paint()..color = Colors.white;
      canvas.drawOval(
        Rect.fromCenter(center: c.translate(-5, -2), width: 4, height: 5),
        eyePaint,
      );
      canvas.drawOval(
        Rect.fromCenter(center: c.translate(5, -2), width: 4, height: 5),
        eyePaint,
      );
      // Pupils.
      final pupilPaint = Paint()..color = const Color(0xFF1F2937);
      canvas.drawCircle(c.translate(-5, -2), 1.8, pupilPaint);
      canvas.drawCircle(c.translate(5, -2), 1.8, pupilPaint);
      // Blush dots.
      final blush = Paint()..color = const Color(0xFFFCA5A5).withValues(alpha: 0.7);
      canvas.drawCircle(c.translate(-8, 4), 2.4, blush);
      canvas.drawCircle(c.translate(8, 4), 2.4, blush);
      // Smile arc.
      final smile = Paint()
        ..color = const Color(0xFF1F2937)
        ..strokeWidth = 1.4
        ..style = PaintingStyle.stroke;
      canvas.drawArc(
        Rect.fromCenter(center: c.translate(0, 4), width: 8, height: 5),
        0.4,
        pi - 0.8,
        false,
        smile,
      );
    }
  }

  void _drawStars(Canvas canvas) {
    for (final s in stars) {
      final alpha = (s.life / 0.7).clamp(0.0, 1.0);
      final scale = 0.6 + 0.6 * alpha;
      canvas.save();
      canvas.translate(s.x, s.y);
      canvas.rotate(s.rot);
      canvas.scale(scale);
      _drawStarIcon(
        canvas,
        Offset.zero,
        12,
        const Color(0xFFFFC837).withValues(alpha: alpha),
      );
      canvas.restore();
    }
  }

  void _drawFloaters(Canvas canvas) {
    for (final f in floaters) {
      final alpha = (f.life / 1.0).clamp(0.0, 1.0);
      // SWISH floaters get the 3-D layered treatment.
      if (f.text.startsWith('SWISH')) {
        _drawSwish3DText(canvas, Offset(f.x, f.y), f.text, f.color, f.fontSize, alpha);
        continue;
      }
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

  void _drawSwish3DText(
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
      ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 14);
    canvas.drawRect(textRect.inflate(4), glowPaint);

    // 2. Yellow stroke outline (rendered by re-painting with stroke style).
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

    // 3. Drop shadow under the white base.
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

    // 4. Base white text on top.
    tp.paint(canvas, origin);
  }

  @override
  bool shouldRepaint(_BasketPainter old) =>
      old.dragStart != dragStart ||
      old.dragCurrent != dragCurrent ||
      old.ballPos != ballPos ||
      old.ballInFlight != ballInFlight ||
      old.floaters != floaters ||
      old.stars != stars ||
      old.trail != trail ||
      old.particles != particles ||
      old.confetti != confetti ||
      old.starTargets != starTargets ||
      old.swishSparkles != swishSparkles ||
      old.netPhase != netPhase ||
      old.netAmp != netAmp ||
      old.rimShakeDx != rimShakeDx ||
      old.rimShakeDy != rimShakeDy ||
      old.idleTime != idleTime ||
      old.score != score ||
      old.highTimeSeconds != highTimeSeconds;
}
