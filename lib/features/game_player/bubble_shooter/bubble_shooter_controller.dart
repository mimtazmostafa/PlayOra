/// Top-level controller for the Bubble Shooter game.
///
/// Owns:
///   - the [BubbleShooterState] (pure game engine)
///   - the projectile ([Flyer]) and the tween-target snap target
///   - the [Ticker] that animates the projectile along its arc
///   - the end-of-game callback (assigned by the host)
///
/// The controller is paused/resumed by the host. When paused, the
/// ticker is stopped so the projectile freezes mid-flight.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'bubble_shooter_ai.dart';
import 'bubble_shooter_state.dart';

/// Geometric constants shared by the controller and the view. The
/// controller uses these to route ray-casts; the view uses them to
/// position bubbles. Keeping them here avoids a "where is the truth"
/// mistake.
const double kBubbleDiameter = 32;
const double kBubbleRadius = kBubbleDiameter / 2;
const double kBoardWidthPx = 12 * kBubbleDiameter;
const double kBoardHeightPx = 16 * kBubbleDiameter;

/// Read-only snapshot of the flyer for the view.
class FlyerView {
  const FlyerView({
    required this.position,
    required this.color,
  });

  final Offset position;
  final BubbleColor color;
}

class BubbleShooterController extends ChangeNotifier {
  BubbleShooterController({
    required TickerProvider vsync,
    math.Random? rng,
  })  : _rng = rng ?? math.Random(),
        // ignore: prefer_initializing_formals
        _vsync = vsync {
    _state = BubbleShooterState.initial(rng: _rng);
    _currentShot = _rngBubble();
    _nextShot = _rngBubble();
    _ticker = _vsync.createTicker(_onTick);
  }

  // ignore: unused_field
  final TickerProvider _vsync;
  final math.Random _rng;
  late final Ticker _ticker;
  BubbleShooterState _state = BubbleShooterState.initial(rng: math.Random());
  late BubbleColor _currentShot;
  late BubbleColor _nextShot;

  /// The projectile currently in flight, if any. Null when the
  /// controller is idle between shots.
  _Flyer? _flyer;

  /// Whether the ticker is currently driving frames.
  bool _running = false;

  /// Callback invoked exactly once when the game ends.
  void Function(int score) _onGameEnd = _noopEnd;
  static void _noopEnd(int score) {}

  /// Current engine state. Read-only snapshot for the view.
  BubbleShooterState get state => _state;

  /// The color the player is about to shoot.
  BubbleColor get currentShot => _currentShot;

  /// The color that will load after the current shot.
  BubbleColor get nextShot => _nextShot;

  /// Whether the player currently has a flyer mid-flight.
  bool get hasFlyerInFlight => _flyer != null;

  /// Read-only snapshot of the flyer for the view to render.
  FlyerView? get flyer {
    final f = _flyer;
    if (f == null) return null;
    return FlyerView(position: f.position, color: f.color);
  }

  /// Lets the host redirect the end-of-game callback after construction.
  void attachEndCallback(void Function(int score) callback) {
    _onGameEnd = callback;
  }

  /// Stop the ticker. Safe to call multiple times.
  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// Starts the ticker if the game is still ongoing.
  void init() {
    if (_state.isGameOver) return;
    if (!_ticker.isActive) _ticker.start();
    _running = true;
  }

  /// Pause the ticker.
  void pause() {
    _running = false;
    _ticker.stop();
  }

  /// Resume the ticker.
  void resume() {
    if (_state.isGameOver) return;
    if (!_ticker.isActive) _ticker.start();
    _running = true;
  }

  /// Returns the next-to-shoot slot the AI recommends, or null when no
  /// good shot exists. The view uses this to draw a faint suggestion
  /// line.
  AimSuggestion? suggestionForCurrentShot() {
    return const BubbleShooterAi().aimSuggestion(
      state: _state,
      nextShot: _currentShot,
    );
  }

  /// Player dragged their finger across the board. Compute the
  /// trajectory and start a new flyer. The flyer is animated by the
  /// ticker.
  void aimAndShoot({required Offset origin, required Offset target}) {
    if (_state.isGameOver) return;
    if (_flyer != null) return; // Already in flight.
    final direction = target - origin;
    if (direction.distanceSquared < 1) return;
    final normalized = direction / direction.distance;
    _flyer = _Flyer(
      position: origin,
      velocity: normalized * 1200, // 1200 px / second.
      color: _currentShot,
      lastTickUs: 0,
    );
    if (!_ticker.isActive) _ticker.start();
    _running = true;
    notifyListeners();
  }

  /// Called by the ticker every frame. Advances the flyer, handles
  /// wall bounces, and snaps when the flyer hits a filled cell.
  void _onTick(Duration elapsed) {
    if (!_running) return;
    final flyer = _flyer;
    if (flyer == null) return;

    final dt = (elapsed.inMicroseconds - flyer.lastTickUs) / 1e6;
    if (dt <= 0) {
      flyer.lastTickUs = elapsed.inMicroseconds;
      return;
    }
    if (dt > 0.05) {
      // First tick of a new frame after a long pause — clamp dt so we
      // don't teleport the flyer across the board.
      flyer.lastTickUs = elapsed.inMicroseconds - 50000;
    } else {
      flyer.lastTickUs = elapsed.inMicroseconds;
    }

    final newPos = flyer.position + flyer.velocity * dt;

    // Wall bounces.
    if (newPos.dx < 0) {
      flyer.position = Offset(-newPos.dx, newPos.dy);
      flyer.velocity = Offset(-flyer.velocity.dx, flyer.velocity.dy);
    } else if (newPos.dx > kBoardWidthPx) {
      final overshoot = newPos.dx - kBoardWidthPx;
      flyer.position = Offset(kBoardWidthPx - overshoot, newPos.dy);
      flyer.velocity = Offset(-flyer.velocity.dx, flyer.velocity.dy);
    } else {
      flyer.position = newPos;
    }
    if (newPos.dy < 0) {
      flyer.position = Offset(flyer.position.dx, -newPos.dy);
      flyer.velocity = Offset(flyer.velocity.dx, -flyer.velocity.dy);
    }

    // Check collision against the board.
    final row = (flyer.position.dy / kBubbleDiameter).floor();
    final colOffset = row.isEven ? 0.0 : kBubbleRadius;
    final col = ((flyer.position.dx - colOffset) / kBubbleDiameter).floor();

    final ceilingRow = _state.highestFilledRow;
    if (ceilingRow >= 0 && row <= ceilingRow) {
      _snapAndApply(row, col);
      return;
    }
    if (row >= 0 && row < BubbleShooterState.boardHeight) {
      final clampedCol = col.clamp(0, BubbleShooterState.boardWidth - 1);
      if (_state.at(row, clampedCol) != null) {
        _snapAndApply(row, clampedCol);
        return;
      }
    }

    // Hit the bottom of the visible area before reaching the ceiling.
    if (flyer.position.dy > kBoardHeightPx - kBubbleRadius) {
      final snapRow = BubbleShooterState.boardHeight - 1;
      final safeCol = col.clamp(0, BubbleShooterState.boardWidth - 1);
      _snapAndApply(snapRow, safeCol);
      return;
    }

    notifyListeners();
  }

  void _snapAndApply(int row, int col) {
    _flyer = null;
    final newState = _state.shoot(
      row: row,
      col: col,
      shot: _currentShot,
      rng: _rng,
    );
    _state = newState;
    _currentShot = _nextShot;
    _nextShot = _rngBubble();
    notifyListeners();
    if (newState.isGameOver) {
      _running = false;
      _ticker.stop();
      _onGameEnd(newState.score);
    }
  }

  BubbleColor _rngBubble() {
    return BubbleColor.values[_rng.nextInt(BubbleColor.values.length)];
  }
}

class _Flyer {
  _Flyer({
    required this.position,
    required this.velocity,
    required this.color,
    required this.lastTickUs,
  });

  Offset position;
  Offset velocity;
  BubbleColor color;
  int lastTickUs;
}
