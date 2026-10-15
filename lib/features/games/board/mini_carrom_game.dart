import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../game_widgets.dart';
import '../mini_game.dart';

/// Mini Carrom — 2D top-down carrom board. Slingshot the striker by
/// pulling back and releasing. Aim line shows direction + force.
/// Pocket detection on the four corners.
///
/// Visuals (Section 2):
///   * Warm wooden board frame (#D7CCC8) with rounded corners.
///   * 3D-shaded recessed corner pockets with drop shadow.
///   * Glossy spherical striker + coin pieces with specular highlights.
///   * Dynamic aim-guide projection line on drag.
///   * Full 2D physics: velocity, friction, elastic collisions, cushion.
///   * Slingshot: pull the striker back to charge, release to shoot.
///   * Striker grab-radius shown as a faint ring on hover.
class MiniCarromGame extends MiniGame {
  const MiniCarromGame({
    super.key,
    required this.twoPlayer,
    required super.callbacks,
  });
  final bool twoPlayer;

  @override
  State<MiniCarromGame> createState() => _MiniCarromState();
}

class _MiniCarromState extends MiniGameState<MiniCarromGame>
    with SingleTickerProviderStateMixin {
  // ── Board-space constants (logical units, before scale to widget) ──
  static const double _boardSize = 320;
  static const double _boardPadding = 12;
  static const double _pocketRadius = 16;
  static const double _strikerRadius = 13;
  static const double _coinRadius = 9;
  /// Widget pixel size of the play area. Set on layout.
  double _widgetSize = _boardSize;

  // All physical state lives in board-space (0..320). Painter converts
  // to widget-space via canvas.scale; gestures convert via the
  // `_toBoard` helper. This avoids the old bug where touch coords and
  // striker coords lived in different spaces when the board was scaled.
  Offset _striker = Offset(_boardSize / 2, _boardSize - 30);
  Offset _strikerVel = Offset.zero;
  List<_Coin> _coins = [];
  int _score = 0;
  int _player = 0; // 0 = white, 1 = black
  int _lastShooter = -1;
  bool _gameOver = false;
  bool _ballsMoving = false;
  Offset? _aimStart; // board-space anchor of the slingshot drag
  Offset? _aimEnd; // board-space current finger position
  double _grabFlash = 0; // 0..1 visual pulse when striker is grabbed

  // Visual tokens.
  static const Color _woodLight = Color(0xFFD7CCC8);
  static const Color _woodDark = Color(0xFF8D6E63);
  static const Color _woodFrame = Color(0xFF5D4037);
  static const Color _pocketShadow = Color(0xFF000000);

  late final Ticker _ticker;
  DateTime _last = DateTime.now();

  @override
  void initState() {
    super.initState();
    _spawnCoins();
    _ticker = createTicker(_tick)..start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reportScore(_score);
      // HUD subtitle: pieces left + turn indicator.
      reportStats('Pieces ${_coins.length}');
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// Convert widget-space touch coordinate to board-space.
  Offset _toBoard(Offset p) {
    final scale = _widgetSize / _boardSize;
    if (scale <= 0) return p;
    return Offset(p.dx / scale, p.dy / scale);
  }

  void _spawnCoins() {
    final rng = Random();
    final center = Offset(_boardSize / 2, _boardSize / 2);
    final positions = <Offset>[];
    var attempts = 0;
    while (positions.length < 9 && attempts < 200) {
      attempts++;
      final dx = (rng.nextDouble() - 0.5) * 60;
      final dy = (rng.nextDouble() - 0.5) * 60;
      final p = center + Offset(dx, dy);
      bool ok = true;
      for (final q in positions) {
        if ((p - q).distance < _coinRadius * 2.2) {
          ok = false;
          break;
        }
      }
      if (ok) positions.add(p);
    }
    _coins = [
      for (var i = 0; i < positions.length; i++)
        _Coin(
          position: positions[i],
          velocity: Offset.zero,
          color: i == 4
              ? const Color(0xFFEF4444)
              : (i.isEven
                  ? const Color(0xFFF5F5F5)
                  : const Color(0xFF1F2937)),
          points: i == 4 ? 50 : (i.isEven ? 10 : 20),
          isQueen: i == 4,
        ),
    ];
  }

  void _tick(Duration _) {
    if (!mounted) return;
    if (_gameOver) return;
    final now = DateTime.now();
    final dt = now.difference(_last).inMicroseconds / 1e6;
    _last = now;
    final clampedDt = dt.clamp(0.0, 0.05);
    bool anyMoving = _strikerVel != Offset.zero;
    var dirty = false;
    // Decay the grab-flash pulse so the ring fades out smoothly.
    if (_grabFlash > 0) {
      _grabFlash = max(0, _grabFlash - clampedDt * 2.5);
      dirty = true;
    }
    final wantsRepaint = dirty || anyMoving;
    if (!wantsRepaint) return;
    setState(() {
      // ─── Striker physics ───
      if (_strikerVel != Offset.zero) {
        _striker += _strikerVel * clampedDt;
        _strikerVel = _strikerVel * 0.98;
        if (_strikerVel.distance < 6) _strikerVel = Offset.zero;
        // Cushion bounces for the striker.
        if (_striker.dx < _boardPadding + _strikerRadius) {
          _striker = Offset(_boardPadding + _strikerRadius, _striker.dy);
          _strikerVel = Offset(-_strikerVel.dx * 0.7, _strikerVel.dy);
        }
        if (_striker.dx > _boardSize - _boardPadding - _strikerRadius) {
          _striker = Offset(
              _boardSize - _boardPadding - _strikerRadius, _striker.dy);
          _strikerVel = Offset(-_strikerVel.dx * 0.7, _strikerVel.dy);
        }
        if (_striker.dy < _boardPadding + _strikerRadius) {
          _striker = Offset(_striker.dx, _boardPadding + _strikerRadius);
          _strikerVel = Offset(_strikerVel.dx, -_strikerVel.dy * 0.7);
        }
        if (_striker.dy > _boardSize - _boardPadding - _strikerRadius) {
          _striker =
              Offset(_striker.dx, _boardSize - _boardPadding - _strikerRadius);
          _strikerVel = Offset(_strikerVel.dx, -_strikerVel.dy * 0.7);
        }
        anyMoving = true;
      }

      for (final c in _coins) {
        if (c.velocity == Offset.zero) continue;
        anyMoving = true;
        c.position += c.velocity * clampedDt;
        c.velocity = c.velocity * 0.98;
        if (c.velocity.distance < 6) c.velocity = Offset.zero;
        // Cushion.
        if (c.position.dx < _boardPadding + _coinRadius) {
          c.position = Offset(_boardPadding + _coinRadius, c.position.dy);
          c.velocity = Offset(-c.velocity.dx * 0.7, c.velocity.dy);
        }
        if (c.position.dx > _boardSize - _boardPadding - _coinRadius) {
          c.position = Offset(
              _boardSize - _boardPadding - _coinRadius, c.position.dy);
          c.velocity = Offset(-c.velocity.dx * 0.7, c.velocity.dy);
        }
        if (c.position.dy < _boardPadding + _coinRadius) {
          c.position = Offset(c.position.dx, _boardPadding + _coinRadius);
          c.velocity = Offset(c.velocity.dx, -c.velocity.dy * 0.7);
        }
        if (c.position.dy > _boardSize - _boardPadding - _coinRadius) {
          c.position = Offset(
              c.position.dx, _boardSize - _boardPadding - _coinRadius);
          c.velocity = Offset(c.velocity.dx, -c.velocity.dy * 0.7);
        }
        // Coin ↔ coin collisions.
        for (final other in _coins) {
          if (identical(other, c)) continue;
          final diff = c.position - other.position;
          final d = diff.distance;
          final minD = _coinRadius * 2;
          if (d < minD && d > 0.0001) {
            final n = diff / d;
            final sep = (minD - d) / 2;
            c.position += n * sep;
            other.position -= n * sep;
            final relV = c.velocity - other.velocity;
            final v = relV.dx * n.dx + relV.dy * n.dy;
            if (v < 0) {
              final imp = n * v;
              c.velocity -= imp;
              other.velocity += imp;
            }
          }
        }
        // Striker ↔ coin collisions.
        final strikerDiff = c.position - _striker;
        final strikerD = strikerDiff.distance;
        if (strikerD < _coinRadius + _strikerRadius && strikerD > 0.0001) {
          final n = strikerDiff / strikerD;
          final relV = c.velocity - _strikerVel;
          final v = relV.dx * n.dx + relV.dy * n.dy;
          if (v < 0) {
            final imp = n * v * 1.1;
            c.velocity -= imp;
            _strikerVel += imp;
          }
        }
        // Pocket detection.
        for (final pk in _pockets()) {
          if ((c.position - pk).distance < _pocketRadius) {
            c.pocketed = true;
            if (_lastShooter == 0 || _lastShooter == 1) {
              if (c.isQueen) {
                _score += 50;
              } else {
                _score += c.points;
              }
              haptic(HapticFeedbackType.light);
            }
            break;
          }
        }
      }
      _coins.removeWhere((c) => c.pocketed);
      _ballsMoving = anyMoving;
      // Mark state dirty if the grab-flash needs to repaint but no
      // piece is moving — otherwise the pulse would freeze.
      if (dirty && !anyMoving) {
        // Already inside setState; nothing to do.
      }
      reportScore(_score);
      reportStats('Pieces ${_coins.length}');
      if (!anyMoving) {
        // End of shot: pass the turn, replace striker.
        _player = 1 - _player;
        _striker = Offset(_boardSize / 2, _player == 0 ? _boardSize - 30 : 30);
        _strikerVel = Offset.zero;
        _lastShooter = -1;
        // End of game when only one color left.
        const white = Color(0xFFF5F5F5);
        const black = Color(0xFF1F2937);
        final hasWhite = _coins.any((c) => !c.isQueen && c.color == white);
        final hasBlack = _coins.any((c) => !c.isQueen && c.color == black);
        if (!hasWhite || !hasBlack) {
          _gameOver = true;
          haptic(HapticFeedbackType.medium);
          reportGameOver();
        }
      }
    });
  }

  List<Offset> _pockets() => [
        const Offset(_boardPadding, _boardPadding),
        Offset(_boardSize - _boardPadding, _boardPadding),
        Offset(_boardPadding, _boardSize - _boardPadding),
        Offset(_boardSize - _boardPadding, _boardSize - _boardPadding),
      ];

  // ────────────────────────────────────────────────────────────
  // Slingshot gesture
  //
  //   * onPanDown: if the touch lands near the striker in board
  //     space (within ~3.5× striker radius), start a slingshot. This
  //     radius is generous so the player can easily grab the striker.
  //   * onPanUpdate: track finger position. The aim vector is the
  //     delta from striker to finger; the striker is visually pulled
  //     back toward the finger direction so the player sees the
  //     "slingshot tension".
  //   * onPanEnd: striker velocity = striker→finger (opposite) × power.
  // ────────────────────────────────────────────────────────────
  void _onPanStart(DragStartDetails d) {
    if (_ballsMoving || _gameOver) return;
    final touch = _toBoard(d.localPosition);
    final dist = (touch - _striker).distance;
    if (dist <= _strikerRadius * 4.5) {
      _aimStart = touch;
      _aimEnd = touch;
      setState(() => _grabFlash = 1.0);
      haptic(HapticFeedbackType.selection);
    }
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_aimStart == null) return;
    _aimEnd = _toBoard(d.localPosition);
    // Visual pullback: striker shifts toward the finger (the
    // "slingshot" stretch) but is clamped so it never leaves the
    // board.
    final delta = _aimEnd! - _striker;
    final maxPull = 40.0;
    if (delta.distance > maxPull) {
      _aimEnd = _striker + delta / delta.distance * maxPull;
    }
    setState(() {});
  }

  void _onPanEnd(DragEndDetails d) {
    if (_aimStart == null) return;
    final anchor = _aimStart!;
    final pull = _aimEnd ?? anchor;
    // Striker shoots in the OPPOSITE direction of the finger pull.
    final v = (_striker - pull) * 4.0;
    if (v.distance >= 30) {
      _lastShooter = _player;
      final clamped = v.distance.clamp(60.0, 520.0);
      _strikerVel = v / v.distance * clamped;
      haptic(HapticFeedbackType.medium);
    }
    setState(() {
      _aimStart = null;
      _aimEnd = null;
      _grabFlash = 0;
    });
  }

  void _onPanCancel() {
    setState(() {
      _aimStart = null;
      _aimEnd = null;
      _grabFlash = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kGameBackground(Theme.of(context).brightness),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Top HUD removed — host GameContainerScreen provides it.
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: LayoutBuilder(
                  builder: (context, c) {
                    final sz = c.maxWidth.clamp(240.0, 480.0);
                    _widgetSize = sz;
                    return SizedBox(
                      width: sz,
                      height: sz,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: _onPanStart,
                        onPanUpdate: _onPanUpdate,
                        onPanEnd: _onPanEnd,
                        onPanCancel: _onPanCancel,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _CarromPainter(
                                  striker: _striker,
                                  coins: _coins,
                                  aimStart: _aimStart,
                                  aimEnd: _aimEnd,
                                  strikerIsGrabbed: _aimStart != null,
                                  grabFlash: _grabFlash,
                                  strikerRadius: _strikerRadius,
                                  score: _score,
                                  player: _player,
                                  twoPlayer: widget.twoPlayer,
                                  woodLight: _woodLight,
                                  woodDark: _woodDark,
                                  woodFrame: _woodFrame,
                                  pocketShadow: _pocketShadow,
                                ),
                              ),
                            ),
                            if (!_ballsMoving && _aimStart == null)
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 12,
                                child: Center(
                                  child: IgnorePointer(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 6),
                                      decoration: BoxDecoration(
                                        color:
                                            Colors.black.withValues(alpha: 0.55),
                                        borderRadius:
                                            BorderRadius.circular(20),
                                      ),
                                      child: const Text(
                                        'Hold & drag the striker back to shoot',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Coin {
  _Coin({
    required this.position,
    required this.velocity,
    required this.color,
    required this.points,
    required this.isQueen,
  });
  Offset position;
  Offset velocity;
  final Color color;
  final int points;
  final bool isQueen;
  bool pocketed = false;
}

class _CarromPainter extends CustomPainter {
  _CarromPainter({
    required this.striker,
    required this.coins,
    required this.aimStart,
    required this.aimEnd,
    required this.strikerIsGrabbed,
    required this.grabFlash,
    required this.strikerRadius,
    required this.score,
    required this.player,
    required this.twoPlayer,
    required this.woodLight,
    required this.woodDark,
    required this.woodFrame,
    required this.pocketShadow,
  });

  final Offset striker;
  final List<_Coin> coins;
  final Offset? aimStart;
  final Offset? aimEnd;
  final bool strikerIsGrabbed;
  final double grabFlash;
  final double strikerRadius;
  final int score;
  final int player;
  final bool twoPlayer;
  final Color woodLight;
  final Color woodDark;
  final Color woodFrame;
  final Color pocketShadow;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / _MiniCarromState._boardSize;
    canvas.save();
    canvas.scale(cell);

    // ─── Outer wooden frame with rounded corners and shadow ───
    final outerRect = Rect.fromLTWH(
      0,
      0,
      _MiniCarromState._boardSize,
      _MiniCarromState._boardSize,
    );
    final outerRRect = RRect.fromRectAndRadius(
      outerRect,
      const Radius.circular(28),
    );
    canvas.drawRRect(
      outerRRect.shift(const Offset(0, 4)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawRRect(
      outerRRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF8D6E63),
            Color(0xFF6D4C41),
            Color(0xFF4E342E),
          ],
        ).createShader(outerRect),
    );

    // ─── Inner playfield (warm wood) ───
    final innerRect = Rect.fromLTWH(
      _MiniCarromState._boardPadding,
      _MiniCarromState._boardPadding,
      _MiniCarromState._boardSize - _MiniCarromState._boardPadding * 2,
      _MiniCarromState._boardSize - _MiniCarromState._boardPadding * 2,
    );
    final innerRRect = RRect.fromRectAndRadius(
      innerRect,
      const Radius.circular(14),
    );
    canvas.drawRRect(
      innerRRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFD7CCC8), Color(0xFFBCAAA4), Color(0xFFA1887F)],
        ).createShader(innerRect),
    );

    // Wood grain — soft sweeping curves.
    final grainPaint = Paint()
      ..color = const Color(0xFF6D4C41).withValues(alpha: 0.10)
      ..strokeWidth = 0.6;
    for (var i = 0; i < 16; i++) {
      final y = 18 + i * (_MiniCarromState._boardSize - 36) / 15;
      canvas.drawLine(
        Offset(_MiniCarromState._boardPadding + 4, y),
        Offset(_MiniCarromState._boardSize - _MiniCarromState._boardPadding - 4,
            y + 0.5),
        grainPaint,
      );
    }

    // ─── Diagonal soft highlight ───
    canvas.save();
    canvas.clipRRect(innerRRect);
    canvas.drawRect(
      innerRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.18),
            Colors.transparent,
          ],
        ).createShader(innerRect),
    );
    canvas.restore();

    // ─── Recessed pockets with shadow ───
    for (final pk in _pockets()) {
      canvas.drawCircle(
        pk + const Offset(0, 2),
        _MiniCarromState._pocketRadius + 3,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.65)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawCircle(
        pk,
        _MiniCarromState._pocketRadius,
        Paint()
          ..shader = RadialGradient(
            colors: [Colors.black, const Color(0xFF111111)],
          ).createShader(Rect.fromCircle(
              center: pk, radius: _MiniCarromState._pocketRadius)),
      );
      canvas.drawCircle(
        pk,
        _MiniCarromState._pocketRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..shader = const SweepGradient(
            colors: [
              Color(0xFF000000),
              Color(0xFF555555),
              Color(0xFF000000),
            ],
          ).createShader(Rect.fromCircle(
              center: pk, radius: _MiniCarromState._pocketRadius)),
      );
    }

    // ─── Center decorations (faint crosshair) ───
    final center = Offset(_MiniCarromState._boardSize / 2,
        _MiniCarromState._boardSize / 2);
    final centerPaint = Paint()
      ..color = const Color(0xFF6D4C41).withValues(alpha: 0.4)
      ..strokeWidth = 1.2;
    canvas.drawLine(center - const Offset(20, 0), center + const Offset(20, 0),
        centerPaint);
    canvas.drawLine(center - const Offset(0, 20), center + const Offset(0, 20),
        centerPaint);
    canvas.drawCircle(center, 4, centerPaint);

    // ─── Coins with specular shading ───
    for (final c in coins) {
      // Drop shadow.
      canvas.drawCircle(
        c.position + const Offset(1, 2),
        _MiniCarromState._coinRadius,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
      );
      // Body sphere.
      canvas.drawCircle(
        c.position,
        _MiniCarromState._coinRadius,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.3, -0.35),
            radius: 0.95,
            colors: [
              Color.lerp(c.color, Colors.white, 0.55) ?? Colors.white,
              c.color,
              Color.lerp(c.color, Colors.black, 0.5) ?? Colors.black,
            ],
            stops: const [0.0, 0.55, 1.0],
          ).createShader(Rect.fromCircle(
              center: c.position, radius: _MiniCarromState._coinRadius)),
      );
      // Specular highlight.
      canvas.drawCircle(
        c.position + const Offset(-2.2, -2.5),
        _MiniCarromState._coinRadius * 0.32,
        Paint()..color = Colors.white.withValues(alpha: 0.85),
      );
      // Queen ring.
      if (c.isQueen) {
        canvas.drawCircle(
          c.position,
          _MiniCarromState._coinRadius * 0.5,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.85)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }

    // ─── Striker grab halo: shown whenever the striker is close to
    // being grabbed. Even before touch-down, the player can SEE that
    // the striker is interactive.
    if (grabFlash > 0 || strikerIsGrabbed) {
      canvas.drawCircle(
        striker,
        _MiniCarromState._strikerRadius + 8,
        Paint()
          ..color = Colors.white.withValues(
              alpha: 0.18 + 0.35 * grabFlash.clamp(0.0, 1.0))
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }

    // ─── Slingshot stretch line (between the original striker and
    // the pulled-back position). Only visible while grabbed.
    if (strikerIsGrabbed && aimStart != null && aimEnd != null) {
      final pull = aimEnd! - aimStart!;
      if (pull.distance > 1.0) {
        final rubber = Paint()
          ..color = Colors.white.withValues(alpha: 0.55)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(striker, striker + pull * 1.4, rubber);
        // Dot at the finger.
        canvas.drawCircle(
          striker + pull * 1.4,
          4,
          Paint()..color = Colors.white.withValues(alpha: 0.85),
        );
        // Power meter (small arc near striker).
        final power = (pull.distance / 40.0).clamp(0.0, 1.0);
        final arcRect = Rect.fromCircle(
          center: striker,
          radius: _MiniCarromState._strikerRadius + 14,
        );
        final arcPaint = Paint()
          ..color = Color.lerp(
            const Color(0xFFFFB300),
            const Color(0xFFFF3B5C),
            power,
          )!
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;
        canvas.drawArc(
          arcRect,
          -pi / 2,
          pi * 1.5 * power,
          false,
          arcPaint,
        );
      }
    }

    // ─── Striker (glossy) ───
    // While grabbed, draw the striker at the pulled-back position so
    // the slingshot effect is visible.
    final strikerDrawPos = strikerIsGrabbed && aimStart != null && aimEnd != null
        ? striker + (aimEnd! - aimStart!) * 1.0
        : striker;
    canvas.drawCircle(
      strikerDrawPos + const Offset(1, 2),
      _MiniCarromState._strikerRadius,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawCircle(
      strikerDrawPos,
      _MiniCarromState._strikerRadius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.35),
          radius: 0.95,
          colors: const [
            Color(0xFFFFE082),
            Color(0xFFFFB300),
            Color(0xFF6D4C41),
          ],
          stops: [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(
            center: strikerDrawPos, radius: _MiniCarromState._strikerRadius)),
    );
    canvas.drawCircle(
      strikerDrawPos + const Offset(-3, -3),
      _MiniCarromState._strikerRadius * 0.32,
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );

    // ─── Dynamic aim-guide projection line ───
    // Show where the striker will fly: from current (pulled) position
    // in the OPPOSITE direction of the finger pull.
    if (strikerIsGrabbed && aimStart != null && aimEnd != null) {
      final pull = aimEnd! - aimStart!;
      if (pull.distance > 4) {
        final shotDir = -pull / pull.distance;
        final power = (pull.distance / 40.0).clamp(0.0, 1.0);
        final maxLen = 60.0 + 100.0 * power;
        final projEnd = striker + shotDir * maxLen;
        final dashPaint = Paint()
          ..color = (twoPlayer
                  ? (player == 0
                      ? const Color(0xFFF5F5F5)
                      : const Color(0xFF1F2937))
                  : const Color(0xFF00E887))
              .withValues(alpha: 0.85)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round;
        _drawDashed(
          canvas,
          striker,
          projEnd,
          dashPaint,
          dashWidth: 6,
          gapWidth: 4,
        );
      }
    }
    canvas.restore();
  }

  void _drawDashed(
    Canvas canvas,
    Offset a,
    Offset b,
    Paint paint, {
    required double dashWidth,
    required double gapWidth,
  }) {
    final total = (b - a).distance;
    if (total <= 0) return;
    final dir = (b - a) / total;
    var t = 0.0;
    while (t < total) {
      final segStart = a + dir * t;
      final segEnd = a + dir * (t + dashWidth).clamp(0.0, total);
      canvas.drawLine(segStart, segEnd, paint);
      t += dashWidth + gapWidth;
    }
  }

  List<Offset> _pockets() => [
        const Offset(_MiniCarromState._boardPadding,
            _MiniCarromState._boardPadding),
        Offset(_MiniCarromState._boardSize - _MiniCarromState._boardPadding,
            _MiniCarromState._boardPadding),
        Offset(_MiniCarromState._boardPadding,
            _MiniCarromState._boardSize - _MiniCarromState._boardPadding),
        Offset(_MiniCarromState._boardSize - _MiniCarromState._boardPadding,
            _MiniCarromState._boardSize - _MiniCarromState._boardPadding),
      ];

  @override
  bool shouldRepaint(_CarromPainter old) =>
      old.coins != coins ||
      old.striker != striker ||
      old.aimStart != aimStart ||
      old.aimEnd != aimEnd ||
      old.strikerIsGrabbed != strikerIsGrabbed ||
      old.grabFlash != grabFlash ||
      old.score != score ||
      old.player != player;
}
