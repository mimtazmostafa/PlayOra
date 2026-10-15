import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../game_widgets.dart';
import '../mini_game.dart';

/// Memory Cards — animal face matching memory game.
///
/// Scene:
///   * 8×4 grid of 32 cards (16 pairs). Each card has a custom
///     patterned back and a cute animal emoji on the front.
///   * 3D flip animation per card via `Matrix4.identity()..rotateY()` —
///     half-flip threshold swaps which face is visible so the back
///     and front stay oriented correctly.
///   * On a match: both cards stay revealed with a glowing border;
///     a star confetti burst spawns at the matched pair's centroid.
///   * On a mismatch: both cards flip back after 1 second.
///   * Top countdown bar drains across the player's turn (level-based
///     duration) and a "memorize" phase reveals all cards briefly
///     before play begins.
///
/// Class + ctor signature stays byte-identical so the dispatcher
/// routing keeps working.
class MemoryCardsGame extends MiniGame {
  const MemoryCardsGame({
    super.key,
    required super.callbacks,
    this.level = 1,
  });

  /// Optional level — controls the play timer (50 s → 25 s).
  final int level;

  @override
  State<MemoryCardsGame> createState() => _MemoryCardsGameState();
}

enum _MCState { showAll, playing, waitReveal, gameOver }

class _MemoryCardsGameState extends MiniGameState<MemoryCardsGame>
    with TickerProviderStateMixin {
  static const int _cols = 4;
  static const int _rows = 4;
  static const int _pairs = (_cols * _rows) ~/ 2; // 8 pairs

  /// Cute animal + object kawaii cards — 8 distinct kinds, each
  /// appears twice. The `kind` enum drives the painter (replaces
  /// emoji with vector art).
  static const List<_CardKind> _cardKinds = _CardKind.values;

  // ─── Card model ────────────────────────────────────────────────
  late List<_Card> _cards;
  final List<_Card> _selected = <_Card>[];

  // Per-card flip progress 0..1, owned by state so the ticker can
  // drive it smoothly without AnimationControllers per card.
  late List<double> _flipProgress;

  // Confetti bursts (one per match).
  final List<_Confetti> _confetti = [];

  // Match scale-bounce progress 0..1 per card (for matched pairs).
  late List<double> _matchBounce;
  // Hearts.
  int _hearts = 3;
  double _heartsPulse = 0;
  // Tutorial state.
  bool _showTutorial = true;
  bool _tutorialDismissed = false;
  double _tutorialElapsed = 0;
  double _idleTime = 0;
  // Pause.
  final bool _paused = false;

  // ─── Game state ────────────────────────────────────────────────
  int _score = 0;
  int _matches = 0;
  int _moves = 0;
  _MCState _state = _MCState.showAll;
  String _message = 'Memorize the cards!';

  // ─── Timer state ───────────────────────────────────────────────
  // During showAll: counts DOWN to 0 from memorizeDuration.
  // During playing: counts DOWN to 0 from levelDuration.
  late final Ticker _ticker;
  DateTime _last = DateTime.now();
  double _timeRemaining = 0; // seconds
  static const double _memorizeDuration = 4.0; // seconds

  Timer? _revealTimer;
  final Random _rng = Random();

  @override
  void initState() {
    super.initState();
    _resetGame();
    _last = DateTime.now();
    _ticker = createTicker(_onTick)..start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reportScore(_score);
      reportStats('Lv ${widget.level}  •  Moves $_moves');
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _revealTimer?.cancel();
    super.dispose();
  }

  Duration get _levelDuration {
    // Higher level → less time. Clamp 25s..50s.
    final secs = 50 - (widget.level - 1) * 5;
    return Duration(seconds: secs.clamp(25, 50));
  }

  void _resetGame() {
    _revealTimer?.cancel();
    final pool = <_CardKind>[..._cardKinds, ..._cardKinds];
    pool.shuffle(_rng);
    _cards = List<_Card>.generate(
      _cols * _rows,
      (i) => _Card(
        id: i,
        kind: pool[i],
        matched: false,
      ),
    );
    _flipProgress = List<double>.filled(_cards.length, 1.0); // all face-up during memorize
    _matchBounce = List<double>.filled(_cards.length, 0.0);
    _selected.clear();
    _confetti.clear();
    _score = 0;
    _matches = 0;
    _moves = 0;
    _hearts = 3;
    _heartsPulse = 0;
    _showTutorial = true;
    _tutorialDismissed = false;
    _tutorialElapsed = 0;
    _state = _MCState.showAll;
    _message = 'Memorize the cards!';
    _timeRemaining = _memorizeDuration;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      reportScore(_score);
      reportStats('Lv ${widget.level}  •  Moves $_moves');
    });
  }

  void _onTick(Duration _) {
    if (!mounted) return;
    final now = DateTime.now();
    final dt = now.difference(_last).inMicroseconds / 1e6;
    _last = now;
    if (_paused) return;
    var changed = false;
    _idleTime += dt;
    _tutorialElapsed += dt;
    if (_heartsPulse > 0) {
      _heartsPulse = max(0, _heartsPulse - dt * 2.0);
      changed = true;
    }
    // Tick timer.
    if (_state == _MCState.showAll || _state == _MCState.playing) {
      _timeRemaining -= dt;
      changed = true;
      if (_timeRemaining <= 0) {
        if (_state == _MCState.showAll) {
          _beginPlaying();
        } else {
          _endGame(outOfTime: true);
        }
      }
    }
    // Auto-dismiss tutorial after 6s.
    if (_showTutorial && !_tutorialDismissed && _tutorialElapsed >= 6.0) {
      _showTutorial = false;
      changed = true;
    }
    // Match bounce decay.
    if (_matchBounce.any((b) => b > 0)) {
      for (var i = 0; i < _matchBounce.length; i++) {
        _matchBounce[i] = max(0, _matchBounce[i] - dt * 2.4);
        if (_matchBounce[i] > 0) changed = true;
      }
    }
    // Animate confetti.
    if (_confetti.isNotEmpty) {
      for (final c in _confetti) {
        c.life -= dt;
        c.x += c.vx * dt;
        c.y += c.vy * dt;
        c.vy += 180 * dt; // gravity
        c.rotation += c.spin * dt;
      }
      _confetti.removeWhere((c) {
        if (c.life <= 0) {
          changed = true;
          return true;
        }
        return false;
      });
    }
    if (changed && mounted) setState(() {});
  }

  void _dismissTutorial() {
    if (!_tutorialDismissed) {
      _tutorialDismissed = true;
      _showTutorial = false;
    }
  }

  void _beginPlaying() {
    if (!mounted) return;
    setState(() {
      _state = _MCState.playing;
      _message = 'Match the pairs!';
      _timeRemaining = _levelDuration.inSeconds.toDouble();
      // Flip all cards face-down.
      for (var i = 0; i < _flipProgress.length; i++) {
        _flipProgress[i] = 0;
      }
    });
  }

  void _onTapCard(_Card card) {
    if (_paused) return;
    if (_state != _MCState.playing) return;
    if (card.matched) return;
    if (_selected.contains(card)) return;
    if (_selected.length >= 2) return;
    _dismissTutorial();
    setState(() {
      _selected.add(card);
      // Start flipping this card toward face-up.
      _flipProgress[card.id] = 1.0; // we'll animate via timer-driven lerp
    });
    HapticFeedback.lightImpact();
    haptic(HapticFeedbackType.selection);
    if (_selected.length == 2) {
      _moves += 1;
      reportStats('Lv ${widget.level}  •  Moves $_moves');
      _state = _MCState.waitReveal;
      _revealTimer = Timer(const Duration(seconds: 1), _resolveReveal);
    }
  }

  void _resolveReveal() {
    if (!mounted) return;
    final a = _selected[0];
    final b = _selected[1];
    final isMatch = a.kind == b.kind;
    if (isMatch) {
      a.matched = true;
      b.matched = true;
      _matchBounce[a.id] = 1.0;
      _matchBounce[b.id] = 1.0;
      _matches += 1;
      final basePts = 50;
      final comboBonus = _matches >= 4 ? 100 : (_matches >= 2 ? 50 : 0);
      _score += basePts + comboBonus;
      // Spawn confetti at the matched pair centroid.
      _confetti.addAll(_Confetti.burst(
        origin: _centroid([a, b]),
        count: 26,
      ));
      HapticFeedback.mediumImpact();
      haptic(HapticFeedbackType.medium);
      reportScore(_score);
      reportStats('Lv ${widget.level}  •  Moves $_moves');
      _selected.clear();
      _state = _MCState.playing;
      if (_matches >= _pairs) {
        _endGame(outOfTime: false);
      }
    } else {
      // Mismatch — flip back.
      HapticFeedback.lightImpact();
      haptic(HapticFeedbackType.light);
      // Flip both back.
      _selected.clear();
      _state = _MCState.playing;
    }
    setState(() {});
  }

  // Compute the centroid of a set of cards (in canvas coords).
  // The build() method hasn't run yet at this point so we use the
  // estimated grid layout (8x4, 64 dp cards, 8 dp gap).
  Offset _centroid(List<_Card> cards) {
    final w = MediaQuery.of(context).size;
    final cellSize = ((w.width - 32 - (_cols - 1) * 8) / _cols).clamp(40.0, 72.0);
    final gridW = _cols * cellSize + (_cols - 1) * 8;
    final gridLeft = (w.width - gridW) / 2;
    final gridTop = 110.0; // under timer + score
    var sx = 0.0, sy = 0.0;
    for (final c in cards) {
      final row = c.id ~/ _cols;
      final col = c.id % _cols;
      sx += gridLeft + col * (cellSize + 8) + cellSize / 2;
      sy += gridTop + row * (cellSize + 8) + cellSize / 2;
    }
    return Offset(sx / cards.length, sy / cards.length);
  }

  void _endGame({required bool outOfTime}) {
    _state = _MCState.gameOver;
    _message = outOfTime ? "Time's up!" : 'You matched all pairs!';
    if (outOfTime) {
      _hearts = max(0, _hearts - 1);
      _heartsPulse = 1.0;
      HapticFeedback.heavyImpact();
      haptic(HapticFeedbackType.heavy);
      if (_hearts > 0) {
        // Restart with full hearts and a fresh time budget.
        _state = _MCState.playing;
        _timeRemaining = _levelDuration.inSeconds.toDouble();
        _flipProgress = List<double>.filled(_cards.length, 0);
        return;
      }
    } else {
      HapticFeedback.heavyImpact();
      haptic(HapticFeedbackType.heavy);
    }
    _selected.clear();
    reportGameOver();
    setState(() {});
  }

  // ─── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final w = mq.size.width;
    final cellSize = ((w - 32 - (_cols - 1) * 8) / _cols).clamp(40.0, 72.0);
    final gridW = _cols * cellSize + (_cols - 1) * 8;
    final gridH = _rows * cellSize + (_rows - 1) * 8;
    final gridLeft = (w - gridW) / 2;
    final gridTop = 130.0;

    return Container(
      color: const Color(0xFF062A33),
      child: Stack(
        children: [
          // Background gradient + floating dots + sparkles.
          Positioned.fill(
            child: CustomPaint(
              painter: _MemoryBgPainter(
                time: _idleTime,
              ),
            ),
          ),
          // Top HUD removed — host GameContainerScreen provides it.
          // Message banner under HUD.
          Positioned(
            left: 16,
            right: 16,
            top: 96,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF000000).withValues(alpha: 0.14),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Text(
                  _message,
                  style: const TextStyle(
                    color: Color(0xFF1E3A8A),
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ),
          // Grid of 3D-flip cards.
          Positioned(
            left: gridLeft,
            top: gridTop,
            width: gridW,
            height: gridH,
            child: Stack(
              children: [
                for (var i = 0; i < _cards.length; i++)
                  _FlippingCard(
                    card: _cards[i],
                    flipProgress: _flipProgress[i],
                    bounceProgress: _matchBounce[i],
                    cellSize: cellSize,
                    row: i ~/ _cols,
                    col: i % _cols,
                    gap: 8,
                    idleTime: _idleTime,
                    onTap: () => _onTapCard(_cards[i]),
                  ),
                // Confetti overlay.
                ..._confetti.map((c) => Positioned(
                      left: c.x - c.size / 2,
                      top: c.y - c.size / 2,
                      child: IgnorePointer(
                        child: Transform.rotate(
                          angle: c.rotation,
                          child: Container(
                            width: c.size,
                            height: c.size,
                            decoration: BoxDecoration(
                              color: c.color.withValues(alpha: c.life / c.maxLife),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: c.color.withValues(
                                      alpha: 0.5 * (c.life / c.maxLife)),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    )),
              ],
            ),
          ),
          // Pause overlay removed — host GameContainerScreen provides it.
          // Game Over overlay removed — host GameContainerScreen provides it.
          // Tutorial overlay.
          if (_showTutorial)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: _TutorialOverlayMCards(
                  elapsed: _tutorialElapsed,
                  onDismiss: _dismissTutorial,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Card kinds (replaces old _AnimalPalette; each has its own
//     painter routine for kawaii vector art).
enum _CardKind { fox, panda, bunny, frog, star, strawberry, kitten, penguin }

// ─── Card ─────────────────────────────────────────────────────────
class _Card {
  _Card({
    required this.id,
    required this.kind,
    required this.matched,
  });
  final int id;
  final _CardKind kind;
  bool matched;
}

// ─── Confetti ─────────────────────────────────────────────────────
class _Confetti {
  _Confetti({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.color,
    required this.size,
    required this.rotation,
    required this.spin,
    required this.life,
    required this.maxLife,
  });
  double x;
  double y;
  double vx;
  double vy;
  final Color color;
  final double size;
  double rotation;
  final double spin;
  double life;
  final double maxLife;

  static List<_Confetti> burst({
    required Offset origin,
    required int count,
  }) {
    final rng = Random();
    const palette = [
      Color(0xFFFACC15), // yellow
      Color(0xFF22D3EE), // cyan
      Color(0xFFF472B6), // pink
      Color(0xFFA78BFA), // purple
      Color(0xFF34D399), // green
      Color(0xFFFB7185), // rose
    ];
    return List.generate(count, (_) {
      final angle = rng.nextDouble() * 2 * pi - pi / 2; // upward bias
      final speed = 140 + rng.nextDouble() * 100;
      return _Confetti(
        x: origin.dx,
        y: origin.dy,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed,
        color: palette[rng.nextInt(palette.length)],
        size: 6 + rng.nextDouble() * 6,
        rotation: rng.nextDouble() * pi * 2,
        spin: (rng.nextDouble() - 0.5) * 12,
        life: 0.9 + rng.nextDouble() * 0.3,
        maxLife: 1.2,
      );
    });
  }
}

// ─── 3D-flip card ─────────────────────────────────────────────────
class _FlippingCard extends StatefulWidget {
  const _FlippingCard({
    required this.card,
    required this.flipProgress,
    required this.bounceProgress,
    required this.cellSize,
    required this.row,
    required this.col,
    required this.gap,
    required this.idleTime,
    required this.onTap,
  });

  final _Card card;
  final double flipProgress; // 0..1; 1 = face-up
  final double bounceProgress; // 0..1; bounce scale for matched cards
  final double cellSize;
  final int row;
  final int col;
  final double gap;
  final double idleTime;
  final VoidCallback onTap;

  @override
  State<_FlippingCard> createState() => _FlippingCardState();
}

class _FlippingCardState extends State<_FlippingCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  double _current = 0; // smoothly tracked value 0..1
  double _target = 0;

  @override
  void initState() {
    super.initState();
    _current = widget.flipProgress;
    _target = widget.flipProgress;
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    )..addListener(() {
        setState(() {
          _current = _target * _ctrl.value +
              (_current == 0 ? 0 : _current) * (1 - _ctrl.value);
        });
      });
  }

  @override
  void didUpdateWidget(covariant _FlippingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.flipProgress != oldWidget.flipProgress) {
      // Animate from _current toward widget.flipProgress.
      _current = widget.flipProgress == 1 ? 0 : _current;
      _target = widget.flipProgress;
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flip = _current.clamp(0.0, 1.0);
    // 0 → back, 1 → front. Map to angle 0..π so the card rotates
    // around its vertical axis. The "front" face is drawn when
    // angle < π/2, the "back" when angle > π/2.
    final angle = flip * pi;
    final isFrontVisible = angle < pi / 2;
    // After 90° the visible face should be the mirror of the back so
    // text/emoji reads correctly. We swap sides + apply a -1 Y-scale.
    final transform = Matrix4.identity()
      ..setEntry(3, 2, 0.0015) // perspective
      ..rotateY(angle);
    if (!isFrontVisible) {
      transform.rotateY(pi);
    }
    // Bounce scale: starts at 1.0, ramps up to 1.25 at midpoint, back to 1.0.
    final bounce = widget.bounceProgress > 0
        ? 1.0 + 0.30 * sin(widget.bounceProgress * pi)
        : 1.0;
    final matched = widget.card.matched;
    return Positioned(
      left: widget.col * (widget.cellSize + widget.gap),
      top: widget.row * (widget.cellSize + widget.gap),
      width: widget.cellSize,
      height: widget.cellSize,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Transform(
          alignment: Alignment.center,
          transform: transform,
          child: Transform.scale(
            scale: bounce,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  if (matched)
                    BoxShadow(
                      color: const Color(0xFFFACC15).withValues(alpha: 0.75),
                      blurRadius: 16,
                      spreadRadius: 2,
                    )
                  else
                    const BoxShadow(
                      color: Color(0x40000000),
                      blurRadius: 6,
                      offset: Offset(0, 3),
                    ),
                ],
                border: matched
                    ? Border.all(
                        color: const Color(0xFFFACC15),
                        width: 2.5,
                      )
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: isFrontVisible
                    ? _CardFront(
                        card: widget.card,
                        cellSize: widget.cellSize,
                        idleTime: widget.idleTime,
                      )
                    : _CardBack(
                        cellSize: widget.cellSize,
                        idleTime: widget.idleTime,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Card back (spec: pastel blue/purple with thick dark border +
//     rounded corners + central glowing white star) ────────────────
class _CardBack extends StatelessWidget {
  const _CardBack({required this.cellSize, required this.idleTime});
  final double cellSize;
  final double idleTime;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFA5C9FF),
            Color(0xFFC9B8FF),
            Color(0xFF9C7CFF),
          ],
        ),
        border: Border(
          top: BorderSide(color: Color(0xFF1E1B4B), width: 2.5),
          bottom: BorderSide(color: Color(0xFF1E1B4B), width: 2.5),
          left: BorderSide(color: Color(0xFF1E1B4B), width: 2.5),
          right: BorderSide(color: Color(0xFF1E1B4B), width: 2.5),
        ),
      ),
      child: CustomPaint(
        painter: _CardBackPainter(cellSize: cellSize, idleTime: idleTime),
      ),
    );
  }
}

class _CardBackPainter extends CustomPainter {
  _CardBackPainter({required this.cellSize, required this.idleTime});
  final double cellSize;
  final double idleTime;

  @override
  void paint(Canvas canvas, Size size) {
    // Subtle diamond pattern overlay.
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.20)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final step = size.width / 5;
    for (var i = -5; i < 10; i++) {
      final p = i * step;
      canvas.drawLine(Offset(p, 0), Offset(p + size.height, size.height), paint);
      canvas.drawLine(Offset(p, size.height), Offset(p + size.height, 0), paint);
    }
    // Glowing white star icon (with halo).
    final center = Offset(size.width / 2, size.height / 2);
    final pulse = 0.85 + 0.15 * sin(idleTime * 2.5);
    // Outer halo.
    canvas.drawCircle(
      center,
      size.width * 0.32 * pulse,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.30 * pulse)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    // Star.
    final starPath = _starPath(center, size.width * 0.22, 5);
    canvas.drawPath(
      starPath,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.95),
    );
    canvas.drawPath(
      starPath,
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    // Center dot.
    canvas.drawCircle(
      center,
      size.width * 0.05,
      Paint()..color = const Color(0xFFFFE066),
    );
  }

  ui.Path _starPath(Offset c, double radius, int points) {
    final p = ui.Path();
    final outer = radius;
    final inner = radius * 0.45;
    for (var i = 0; i < points * 2; i++) {
      final r = i.isEven ? outer : inner;
      final angle = -pi / 2 + i * pi / points;
      final x = c.dx + r * cos(angle);
      final y = c.dy + r * sin(angle);
      if (i == 0) {
        p.moveTo(x, y);
      } else {
        p.lineTo(x, y);
      }
    }
    p.close();
    return p;
  }

  @override
  bool shouldRepaint(_CardBackPainter old) =>
      old.cellSize != cellSize || old.idleTime != idleTime;
}

// ─── Card front (kawaii vector art per _CardKind) ─────────────────
class _CardFront extends StatelessWidget {
  const _CardFront({
    required this.card,
    required this.cellSize,
    required this.idleTime,
  });
  final _Card card;
  final double cellSize;
  final double idleTime;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFF9F1),
            Color(0xFFFFF1F7),
          ],
        ),
        border: Border.all(
          color: const Color(0xFF1E1B4B),
          width: 2.5,
        ),
      ),
      child: Stack(
        children: [
          Center(
            child: CustomPaint(
              size: Size(cellSize * 0.92, cellSize * 0.92),
              painter: _KawaiiCardPainter(
                kind: card.kind,
                size: cellSize * 0.92,
                idleTime: idleTime,
                matched: card.matched,
              ),
            ),
          ),
          if (card.matched)
            Positioned(
              right: 4,
              top: 4,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: const Color(0xFFFACC15),
                  shape: BoxShape.circle,
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x80000000),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 12,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Kawaii vector card painter — draws foxes, pandas, bunnies, frogs,
/// stars, strawberries, kittens, penguins with thick dark outlines,
/// glossy highlights, and expressive faces.
class _KawaiiCardPainter extends CustomPainter {
  _KawaiiCardPainter({
    required this.kind,
    required this.size,
    required this.idleTime,
    required this.matched,
  });
  final _CardKind kind;
  final double size;
  final double idleTime;
  final bool matched;

  @override
  void paint(Canvas canvas, Size canvasSize) {
    canvas.save();
    canvas.translate(canvasSize.width / 2, canvasSize.height / 2);
    final r = canvasSize.width / 2;
    switch (kind) {
      case _CardKind.fox:
        _drawFox(canvas, r);
        break;
      case _CardKind.panda:
        _drawPanda(canvas, r);
        break;
      case _CardKind.bunny:
        _drawBunny(canvas, r);
        break;
      case _CardKind.frog:
        _drawFrog(canvas, r);
        break;
      case _CardKind.star:
        _drawStar(canvas, r);
        break;
      case _CardKind.strawberry:
        _drawStrawberry(canvas, r);
        break;
      case _CardKind.kitten:
        _drawKitten(canvas, r);
        break;
      case _CardKind.penguin:
        _drawPenguin(canvas, r);
        break;
    }
    canvas.restore();
  }

  void _drawFace(Canvas canvas, Offset c, double r, {bool cheeks = true}) {
    // Eyes.
    final eyeR = r * 0.10;
    final eo = r * 0.28;
    canvas.drawCircle(c + Offset(-eo, -r * 0.05), eyeR, Paint()..color = const Color(0xFF1F0A14));
    canvas.drawCircle(c + Offset(eo, -r * 0.05), eyeR, Paint()..color = const Color(0xFF1F0A14));
    canvas.drawCircle(
      c + Offset(-eo + eyeR * 0.35, -r * 0.05 - eyeR * 0.4),
      eyeR * 0.45,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      c + Offset(eo + eyeR * 0.35, -r * 0.05 - eyeR * 0.4),
      eyeR * 0.45,
      Paint()..color = Colors.white,
    );
    // Smile.
    final smile = Path()
      ..moveTo(c.dx - r * 0.20, c.dy + r * 0.15)
      ..quadraticBezierTo(c.dx, c.dy + r * 0.30, c.dx + r * 0.20, c.dy + r * 0.15);
    canvas.drawPath(
      smile,
      Paint()
        ..color = const Color(0xFF1F0A14)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.07
        ..strokeCap = StrokeCap.round,
    );
    if (cheeks) {
      canvas.drawCircle(c + Offset(-r * 0.42, r * 0.10), r * 0.10,
          Paint()..color = const Color(0xFFFF9CCC).withValues(alpha: 0.55));
      canvas.drawCircle(c + Offset(r * 0.42, r * 0.10), r * 0.10,
          Paint()..color = const Color(0xFFFF9CCC).withValues(alpha: 0.55));
    }
  }

  void _drawBody(Canvas canvas, Offset c, double r, Color body,
      Color highlight, Color outline, {bool round = true}) {
    if (round) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = ui.Gradient.radial(
            c + Offset(-r * 0.3, -r * 0.4),
            r * 1.2,
            [highlight, body],
          ),
      );
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = outline
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.10,
      );
    } else {
      // Rounded rect.
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: c, width: r * 1.8, height: r * 1.8),
        Radius.circular(r * 0.45),
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..shader = ui.Gradient.radial(
            c + Offset(-r * 0.3, -r * 0.4),
            r * 1.2,
            [highlight, body],
          ),
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..color = outline
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.10,
      );
    }
    // Glossy crescent.
    canvas.drawCircle(
      c + Offset(-r * 0.32, -r * 0.36),
      r * 0.22,
      Paint()..color = Colors.white.withValues(alpha: 0.60),
    );
  }

  void _drawFox(Canvas canvas, double r) {
    final c = Offset(0, r * 0.05);
    _drawBody(canvas, c, r * 0.85, const Color(0xFFFF7A1A),
        const Color(0xFFFFC58A), const Color(0xFF3F1422));
    // Ears (triangles).
    final earL = Path()
      ..moveTo(-r * 0.55, -r * 0.45)
      ..lineTo(-r * 0.30, -r * 0.85)
      ..lineTo(-r * 0.10, -r * 0.45)
      ..close();
    final earR = Path()
      ..moveTo(r * 0.55, -r * 0.45)
      ..lineTo(r * 0.30, -r * 0.85)
      ..lineTo(r * 0.10, -r * 0.45)
      ..close();
    canvas.drawPath(earL, Paint()..color = const Color(0xFFFF7A1A));
    canvas.drawPath(earR, Paint()..color = const Color(0xFFFF7A1A));
    canvas.drawPath(
      earL,
      Paint()
        ..color = const Color(0xFF3F1422)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.07,
    );
    canvas.drawPath(
      earR,
      Paint()
        ..color = const Color(0xFF3F1422)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.07,
    );
    // Snout (cream).
    final snout = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(0, r * 0.30),
        width: r * 0.9,
        height: r * 0.55,
      ),
      Radius.circular(r * 0.25),
    );
    canvas.drawRRect(
      snout,
      Paint()..color = const Color(0xFFFFF1D9),
    );
    canvas.drawRRect(
      snout,
      Paint()
        ..color = const Color(0xFF3F1422)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.05,
    );
    // Nose.
    final nose = Path()
      ..moveTo(0, r * 0.15)
      ..lineTo(-r * 0.10, r * 0.30)
      ..lineTo(r * 0.10, r * 0.30)
      ..close();
    canvas.drawPath(nose, Paint()..color = const Color(0xFF3F1422));
    _drawFace(canvas, c + Offset(0, r * 0.10), r * 0.55);
  }

  void _drawPanda(Canvas canvas, double r) {
    final c = Offset(0, r * 0.05);
    _drawBody(canvas, c, r * 0.88, Colors.white,
        const Color(0xFFFAFAFA), const Color(0xFF1F1F1F));
    // Black ears.
    canvas.drawCircle(c + Offset(-r * 0.55, -r * 0.55), r * 0.20,
        Paint()..color = const Color(0xFF1F1F1F));
    canvas.drawCircle(c + Offset(r * 0.55, -r * 0.55), r * 0.20,
        Paint()..color = const Color(0xFF1F1F1F));
    // Black eye patches.
    canvas.drawCircle(c + Offset(-r * 0.30, -r * 0.10), r * 0.18,
        Paint()..color = const Color(0xFF1F1F1F));
    canvas.drawCircle(c + Offset(r * 0.30, -r * 0.10), r * 0.18,
        Paint()..color = const Color(0xFF1F1F1F));
    // Eyes.
    canvas.drawCircle(c + Offset(-r * 0.30, -r * 0.10), r * 0.08,
        Paint()..color = Colors.white);
    canvas.drawCircle(c + Offset(r * 0.30, -r * 0.10), r * 0.08,
        Paint()..color = Colors.white);
    canvas.drawCircle(c + Offset(-r * 0.30, -r * 0.08), r * 0.04,
        Paint()..color = const Color(0xFF1F1F1F));
    canvas.drawCircle(c + Offset(r * 0.30, -r * 0.08), r * 0.04,
        Paint()..color = const Color(0xFF1F1F1F));
    // Nose.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(0, r * 0.20),
        width: r * 0.18,
        height: r * 0.12,
      ),
      Paint()..color = const Color(0xFF1F1F1F),
    );
    // Smile.
    final smile = Path()
      ..moveTo(-r * 0.18, r * 0.32)
      ..quadraticBezierTo(0, r * 0.42, r * 0.18, r * 0.32);
    canvas.drawPath(
      smile,
      Paint()
        ..color = const Color(0xFF1F1F1F)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.06
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawBunny(Canvas canvas, double r) {
    final c = Offset(0, r * 0.10);
    _drawBody(canvas, c, r * 0.85, const Color(0xFFFFE3F0),
        const Color(0xFFFFF7FB), const Color(0xFF3F1422));
    // Long ears.
    final earL = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(-r * 0.30, -r * 0.60), width: r * 0.20, height: r * 0.55),
      Radius.circular(r * 0.10),
    );
    final earR = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(r * 0.30, -r * 0.60), width: r * 0.20, height: r * 0.55),
      Radius.circular(r * 0.10),
    );
    canvas.drawRRect(earL, Paint()..color = const Color(0xFFFFE3F0));
    canvas.drawRRect(earR, Paint()..color = const Color(0xFFFFE3F0));
    canvas.drawRRect(earL,
        Paint()
          ..color = const Color(0xFF3F1422)
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.05);
    canvas.drawRRect(earR,
        Paint()
          ..color = const Color(0xFF3F1422)
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.05);
    // Inner pink ear.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(-r * 0.30, -r * 0.55), width: r * 0.10, height: r * 0.35),
        Radius.circular(r * 0.05),
      ),
      Paint()..color = const Color(0xFFFF9CCC),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(r * 0.30, -r * 0.55), width: r * 0.10, height: r * 0.35),
        Radius.circular(r * 0.05),
      ),
      Paint()..color = const Color(0xFFFF9CCC),
    );
    _drawFace(canvas, c, r * 0.50);
  }

  void _drawFrog(Canvas canvas, double r) {
    final c = Offset(0, r * 0.10);
    _drawBody(canvas, c, r * 0.85, const Color(0xFF6FE7B7),
        const Color(0xFFB8F5D8), const Color(0xFF0B2E22));
    // Eyes (bulbous, white-cream).
    canvas.drawCircle(c + Offset(-r * 0.30, -r * 0.55), r * 0.22,
        Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawCircle(c + Offset(r * 0.30, -r * 0.55), r * 0.22,
        Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawCircle(c + Offset(-r * 0.30, -r * 0.55), r * 0.22,
        Paint()
          ..color = const Color(0xFF0B2E22)
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.05);
    canvas.drawCircle(c + Offset(r * 0.30, -r * 0.55), r * 0.22,
        Paint()
          ..color = const Color(0xFF0B2E22)
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.05);
    // Pupils.
    canvas.drawCircle(c + Offset(-r * 0.30, -r * 0.50), r * 0.10,
        Paint()..color = const Color(0xFF0B2E22));
    canvas.drawCircle(c + Offset(r * 0.30, -r * 0.50), r * 0.10,
        Paint()..color = const Color(0xFF0B2E22));
    canvas.drawCircle(c + Offset(-r * 0.27, -r * 0.54), r * 0.04,
        Paint()..color = Colors.white);
    canvas.drawCircle(c + Offset(r * 0.33, -r * 0.54), r * 0.04,
        Paint()..color = Colors.white);
    // Wide mouth.
    final mouth = Path()
      ..moveTo(-r * 0.55, r * 0.20)
      ..quadraticBezierTo(0, r * 0.55, r * 0.55, r * 0.20);
    canvas.drawPath(
      mouth,
      Paint()
        ..color = const Color(0xFF0B2E22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.07
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawStar(Canvas canvas, double r) {
    final c = Offset(0, 0);
    final path = Path();
    const points = 5;
    for (var i = 0; i < points * 2; i++) {
      final angle = -pi / 2 + i * pi / points;
      final radius = i.isEven ? r * 0.95 : r * 0.42;
      final x = radius * cos(angle);
      final y = radius * sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.radial(
          c + Offset(-r * 0.3, -r * 0.4),
          r * 1.2,
          [const Color(0xFFFFF1A8), const Color(0xFFFFD23F)],
        ),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF4A2E00)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.07,
    );
    // Inner star highlight.
    final inner = Path();
    for (var i = 0; i < 4; i++) {
      final angle = -pi / 2 + i * pi / 2;
      final radius = i.isEven ? r * 0.30 : r * 0.13;
      final x = -r * 0.20 + cos(angle) * radius;
      final y = -r * 0.30 + sin(angle) * radius;
      if (i == 0) {
        inner.moveTo(x, y);
      } else {
        inner.lineTo(x, y);
      }
    }
    inner.close();
    canvas.drawPath(inner, Paint()..color = Colors.white.withValues(alpha: 0.65));
    _drawFace(canvas, c + Offset(0, r * 0.10), r * 0.50);
  }

  void _drawStrawberry(Canvas canvas, double r) {
    final c = Offset(0, r * 0.10);
    // Body (heart-like teardrop).
    final path = Path()
      ..moveTo(0, -r * 0.55)
      ..cubicTo(r * 0.95, -r * 0.10, r * 0.65, r * 0.85, 0, r * 0.85)
      ..cubicTo(-r * 0.65, r * 0.85, -r * 0.95, -r * 0.10, 0, -r * 0.55)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, -r * 0.55),
          Offset(0, r * 0.85),
          [const Color(0xFFFF6B85), const Color(0xFFFF4D6D)],
        ),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF3F1422)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.07,
    );
    // Leafy crown.
    final leaf = Path()
      ..moveTo(-r * 0.50, -r * 0.40)
      ..lineTo(-r * 0.20, -r * 0.60)
      ..lineTo(0, -r * 0.45)
      ..lineTo(r * 0.20, -r * 0.60)
      ..lineTo(r * 0.50, -r * 0.40)
      ..lineTo(r * 0.40, -r * 0.20)
      ..lineTo(r * 0.18, -r * 0.30)
      ..lineTo(0, -r * 0.20)
      ..lineTo(-r * 0.18, -r * 0.30)
      ..lineTo(-r * 0.40, -r * 0.20)
      ..close();
    canvas.drawPath(leaf, Paint()..color = const Color(0xFF22C55E));
    canvas.drawPath(
      leaf,
      Paint()
        ..color = const Color(0xFF0B2E22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.05,
    );
    // Seeds.
    final seed = Paint()..color = const Color(0xFFFFE066);
    for (var i = 0; i < 6; i++) {
      final dy = -r * 0.05 + i * r * 0.16;
      final dx = (i.isEven ? 0.0 : r * 0.18) +
          sin(idleTime * 1.4 + i) * r * 0.02;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(dx, dy), width: r * 0.07, height: r * 0.10),
        seed,
      );
    }
    // Glossy crescent.
    canvas.drawCircle(
      c + Offset(-r * 0.30, -r * 0.20),
      r * 0.18,
      Paint()..color = Colors.white.withValues(alpha: 0.55),
    );
    _drawFace(canvas, c, r * 0.40);
  }

  void _drawKitten(Canvas canvas, double r) {
    final c = Offset(0, r * 0.05);
    _drawBody(canvas, c, r * 0.85, const Color(0xFFFFC58A),
        const Color(0xFFFFE6C8), const Color(0xFF3F1422));
    // Triangle ears.
    final earL = Path()
      ..moveTo(-r * 0.65, -r * 0.20)
      ..lineTo(-r * 0.35, -r * 0.85)
      ..lineTo(-r * 0.10, -r * 0.30)
      ..close();
    final earR = Path()
      ..moveTo(r * 0.65, -r * 0.20)
      ..lineTo(r * 0.35, -r * 0.85)
      ..lineTo(r * 0.10, -r * 0.30)
      ..close();
    canvas.drawPath(earL, Paint()..color = const Color(0xFFFFC58A));
    canvas.drawPath(earR, Paint()..color = const Color(0xFFFFC58A));
    canvas.drawPath(earL,
        Paint()
          ..color = const Color(0xFF3F1422)
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.06);
    canvas.drawPath(earR,
        Paint()
          ..color = const Color(0xFF3F1422)
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.06);
    // Inner pink.
    final elIn = Path()
      ..moveTo(-r * 0.55, -r * 0.30)
      ..lineTo(-r * 0.38, -r * 0.65)
      ..lineTo(-r * 0.20, -r * 0.35)
      ..close();
    final erIn = Path()
      ..moveTo(r * 0.55, -r * 0.30)
      ..lineTo(r * 0.38, -r * 0.65)
      ..lineTo(r * 0.20, -r * 0.35)
      ..close();
    canvas.drawPath(elIn, Paint()..color = const Color(0xFFFF9CCC));
    canvas.drawPath(erIn, Paint()..color = const Color(0xFFFF9CCC));
    // Nose triangle.
    final nose = Path()
      ..moveTo(0, r * 0.10)
      ..lineTo(-r * 0.10, r * 0.25)
      ..lineTo(r * 0.10, r * 0.25)
      ..close();
    canvas.drawPath(nose, Paint()..color = const Color(0xFFFF9CCC));
    canvas.drawPath(nose,
        Paint()
          ..color = const Color(0xFF3F1422)
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.05);
    // Whiskers.
    final w = Paint()
      ..color = const Color(0xFF3F1422)
      ..strokeWidth = r * 0.04
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(-r * 0.10, r * 0.30), Offset(-r * 0.55, r * 0.20), w);
    canvas.drawLine(Offset(-r * 0.10, r * 0.30), Offset(-r * 0.55, r * 0.40), w);
    canvas.drawLine(Offset(r * 0.10, r * 0.30), Offset(r * 0.55, r * 0.20), w);
    canvas.drawLine(Offset(r * 0.10, r * 0.30), Offset(r * 0.55, r * 0.40), w);
    // Mouth.
    final mouth = Path()
      ..moveTo(0, r * 0.30)
      ..lineTo(0, r * 0.38)
      ..moveTo(0, r * 0.38)
      ..quadraticBezierTo(-r * 0.10, r * 0.50, -r * 0.18, r * 0.40)
      ..moveTo(0, r * 0.38)
      ..quadraticBezierTo(r * 0.10, r * 0.50, r * 0.18, r * 0.40);
    canvas.drawPath(
      mouth,
      Paint()
        ..color = const Color(0xFF3F1422)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.05
        ..strokeCap = StrokeCap.round,
    );
    // Eyes.
    canvas.drawCircle(c + Offset(-r * 0.28, -r * 0.05), r * 0.10,
        Paint()..color = const Color(0xFF1F0A14));
    canvas.drawCircle(c + Offset(r * 0.28, -r * 0.05), r * 0.10,
        Paint()..color = const Color(0xFF1F0A14));
  }

  void _drawPenguin(Canvas canvas, double r) {
    final c = Offset(0, r * 0.05);
    _drawBody(canvas, c, r * 0.88, const Color(0xFF1F2937),
        const Color(0xFF4B5563), const Color(0xFF000000));
    // White belly.
    final belly = RRect.fromRectAndRadius(
      Rect.fromCenter(center: c + Offset(0, r * 0.15), width: r * 1.10, height: r * 1.20),
      Radius.circular(r * 0.45),
    );
    canvas.drawRRect(belly, Paint()..color = const Color(0xFFFAFAFA));
    canvas.drawRRect(
      belly,
      Paint()
        ..color = const Color(0xFF000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.06,
    );
    // Beak.
    final beak = Path()
      ..moveTo(0, -r * 0.05)
      ..lineTo(-r * 0.10, r * 0.10)
      ..lineTo(r * 0.10, r * 0.10)
      ..close();
    canvas.drawPath(beak, Paint()..color = const Color(0xFFF59E0B));
    canvas.drawPath(beak,
        Paint()
          ..color = const Color(0xFF3F1422)
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.04);
    // Eyes.
    canvas.drawCircle(c + Offset(-r * 0.22, -r * 0.20), r * 0.08,
        Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawCircle(c + Offset(r * 0.22, -r * 0.20), r * 0.08,
        Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawCircle(c + Offset(-r * 0.22, -r * 0.18), r * 0.04,
        Paint()..color = const Color(0xFF1F0A14));
    canvas.drawCircle(c + Offset(r * 0.22, -r * 0.18), r * 0.04,
        Paint()..color = const Color(0xFF1F0A14));
    // Tiny feet.
    canvas.drawOval(
      Rect.fromCenter(center: Offset(-r * 0.20, r * 0.75), width: r * 0.30, height: r * 0.15),
      Paint()..color = const Color(0xFFF59E0B),
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(r * 0.20, r * 0.75), width: r * 0.30, height: r * 0.15),
      Paint()..color = const Color(0xFFF59E0B),
    );
  }

  @override
  bool shouldRepaint(_KawaiiCardPainter old) =>
      old.kind != kind ||
      old.size != size ||
      old.idleTime != idleTime ||
      old.matched != matched;
}

// ─── Background painter (spec: pastel teal-to-blue gradient +
//     floating star sparkles + ambient particles) ──────────────────
class _MemoryBgPainter extends CustomPainter {
  _MemoryBgPainter({required this.time});
  final double time;

  @override
  void paint(Canvas canvas, Size size) {
    // Soft pastel teal → blue gradient.
    final bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFFB0E5E2),
          Color(0xFF9CD7E6),
          Color(0xFF7BBFE0),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bg);
    // Soft "wave" decoration bands.
    final band1 = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.10)
      ..style = PaintingStyle.fill;
    final bandPath1 = Path()
      ..moveTo(0, size.height * 0.55)
      ..quadraticBezierTo(
        size.width * 0.25,
        size.height * 0.50,
        size.width * 0.50,
        size.height * 0.58,
      )
      ..quadraticBezierTo(
        size.width * 0.75,
        size.height * 0.66,
        size.width,
        size.height * 0.55,
      )
      ..lineTo(size.width, size.height * 0.66)
      ..lineTo(0, size.height * 0.66)
      ..close();
    canvas.drawPath(bandPath1, band1);
    // Floating dots (sparkles).
    final dotPaint = Paint();
    for (var i = 0; i < 36; i++) {
      final phase = i * 0.7;
      final baseX = ((i * 53) % size.width.toInt()).toDouble();
      final baseY = ((i * 91 + (time * 14).toInt()) % size.height.toInt())
          .toDouble();
      final tw = (0.6 + 0.4 * sin(time * 1.8 + phase)).clamp(0.0, 1.0);
      dotPaint.color =
          Colors.white.withValues(alpha: (0.18 + tw * 0.35).clamp(0.0, 0.95));
      canvas.drawCircle(Offset(baseX, baseY), 1.5 + (i % 3), dotPaint);
    }
    // 12 four-point star sparkles.
    final star = Paint()
      ..color = Colors.white.withValues(alpha: 0.7);
    for (var i = 0; i < 12; i++) {
      final phase = i * 0.55;
      final baseX = ((i * 71) % size.width.toInt()).toDouble();
      final baseY =
          ((i * 113 + (time * 6).toInt()) % size.height.toInt()).toDouble();
      final tw = (0.6 + 0.4 * sin(time * 2.4 + phase)).clamp(0.0, 1.0);
      final r = 2.5 + tw * 1.5;
      star.color = Colors.white.withValues(alpha: 0.45 * tw);
      final path = Path();
      for (var k = 0; k < 8; k++) {
        final a = -pi / 2 + k * pi / 4;
        final rr = k.isEven ? r : r * 0.4;
        final x = baseX + cos(a) * rr;
        final y = baseY + sin(a) * rr;
        if (k == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.close();
      canvas.drawPath(path, star);
    }
  }

  @override
  bool shouldRepaint(_MemoryBgPainter old) => old.time != time;
}

// ─── Tutorial overlay ──────────────────────────────────────────────
class _TutorialOverlayMCards extends StatefulWidget {
  const _TutorialOverlayMCards({
    required this.elapsed,
    required this.onDismiss,
  });
  final double elapsed;
  final VoidCallback onDismiss;

  @override
  State<_TutorialOverlayMCards> createState() =>
      _TutorialOverlayMCardsState();
}

class _TutorialOverlayMCardsState extends State<_TutorialOverlayMCards>
    with SingleTickerProviderStateMixin {
  late final Ticker _tk;
  double _t = 0;

  @override
  void initState() {
    super.initState();
    _tk = createTicker((_) {
      if (!mounted) return;
      setState(() => _t += 1 / 60);
    })..start();
  }

  @override
  void dispose() {
    _tk.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slide = Curves.easeOutCubic.transform((_t * 3.5).clamp(0.0, 1.0));
    final handBob = sin(_t * 5) * 4.0;
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
                color: const Color(0xFF000000).withValues(alpha: 0.14),
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
                  offset: Offset(0, handBob),
                  child: CustomPaint(
                    painter: _MemoryHandPainter(t: _t),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Flexible(
                child: Text(
                  'Tap cards to find matching pairs!',
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

class _MemoryHandPainter extends CustomPainter {
  _MemoryHandPainter({required this.t});
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final tap = (sin(t * 4) + 1) * 0.5;
    canvas.save();
    canvas.translate(cx, cy + 4);
    // Tap ripple below finger.
    canvas.drawCircle(
      Offset(0, 12),
      4 + tap * 6,
      Paint()
        ..color = const Color(0xFF22D3EE).withValues(alpha: 0.25 - tap * 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    // Yellow palm.
    final palm = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(0, 0), width: 22, height: 16),
      const Radius.circular(7),
    );
    canvas.drawRRect(
      palm,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, -8),
          Offset(0, 8),
          const [Color(0xFFFFE57F), Color(0xFFFFB347)],
        ),
    );
    canvas.drawRRect(
      palm,
      Paint()
        ..color = const Color(0xFFB3681A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    // Pointing finger — angled up-left at a card.
    canvas.save();
    canvas.translate(0, 0);
    canvas.rotate(-0.45);
    final fingerLen = 16 + tap * 3;
    final finger = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(0, fingerLen / 2 - 2),
        width: 7,
        height: fingerLen,
      ),
      const Radius.circular(3.5),
    );
    canvas.drawRRect(
      finger,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, 0),
          Offset(0, fingerLen),
          const [Color(0xFFFFE57F), Color(0xFFFFB347)],
        ),
    );
    canvas.drawRRect(
      finger,
      Paint()
        ..color = const Color(0xFFB3681A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MemoryHandPainter old) => old.t != t;
}
