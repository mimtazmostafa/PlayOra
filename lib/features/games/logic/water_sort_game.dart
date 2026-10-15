import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/utils/random_utils.dart';
import '../game_widgets.dart';
import '../mini_game.dart';

/// **Water Sort** — Realistic glass-tube color sorting puzzle.
///
/// Faithful to the actual Water Sort game (watersortgame.com):
///   * Dark maroon background with subtle vignette.
///   * Realistic glass test tubes with rim highlight, body shadow,
///     and crisp white outline.
///   * Liquid layers with proper horizontal meniscus and a slight
///     vertical gradient to suggest depth and water shimmer.
///   * Tilt + pour animation: when a tube is selected, it tilts
///     toward the destination and the top color runs across as a
///     fluid stream into the destination tube.
///   * Standard controls: Back (top-left), Refresh (top-right),
///     Undo (bottom-left), Hint (bottom-right), Add Tube (center).
///
/// Rules (identical to the real game):
///   * Tap a tube to select it. Tap another to pour.
///   * You may only pour onto an empty tube or onto a tube whose
///     top color matches.
///   * An entire contiguous run of the same color pours together,
///     but only if the destination has room for the whole run.
///   * Otherwise the move is refused (tube shakes).
class WaterSortGame extends MiniGame {
  const WaterSortGame({
    super.key,
    required super.callbacks,
    this.level = 1,
    this.dailyChallenge = false,
  });

  final int level;
  final bool dailyChallenge;

  @override
  State<WaterSortGame> createState() => _WaterSortState();
}

class _WaterSortState extends MiniGameState<WaterSortGame>
    with TickerProviderStateMixin {
  // ─────────────────────────────────────────────────────────────
  // Constants
  // ─────────────────────────────────────────────────────────────
  static const int _layers = 4;

  /// Tube layout — single horizontal row plus one locked / extra-tube
  /// slot at the end. Column count is dynamic so the row always fills
  /// the screen. The locked slot occupies the last column.
  // (Locked-slot is the slot after the playable row, see
  //  [_WaterSortState._isLockedSlot].)

  /// Six vivid colors tuned to pop against the maroon background.
  static const List<Color> _palette = [
    Color(0xFFEF4444), // cherry red
    Color(0xFFFFD93D), // bright yellow
    Color(0xFF4ADE80), // leaf green
    Color(0xFF38BDF8), // sky blue
    Color(0xFFA78BFA), // violet
    Color(0xFFFB7185), // pink
  ];

  // ─────────────────────────────────────────────────────────────
  // State
  // ─────────────────────────────────────────────────────────────
  late List<List<int>> _tubes;
  int? _selected;
  int _score = 0;
  int _level = 1;
  bool _gameOver = false;
  int _moves = 0;
  int _perfectPourStreak = 0;
  int _hintsLeft = 9;

  late int _tubeCount;
  late int _colourCount;

  final Set<int> _completedTubes = <int>{};

  // Animation controllers.
  late final AnimationController _liftCtrl; // tube lifts when selected
  late final AnimationController _shakeCtrl; // invalid move shake
  late final AnimationController _pourCtrl; // tilted-pour animation
  late final AnimationController _idleCtrl; // ambient liquid bob

  int _liftIdx = -1;
  int _invalidIdx = -1;

  int? _pourFrom;
  int? _pourTo;
  int _pourCount = 0;
  int _pourColour = 0;

  // Hint highlight — when set, both source and destination tubes pulse
  // with a colored ring so the player can spot the suggested move.
  int? _hintSrc;
  int? _hintDst;
  DateTime? _hintUntil;

  final List<_Floater> _floaters = [];
  static const int _historyCap = 100;
  final List<_Move> _history = [];

  // Layout cache.
  final List<Rect> _tubeRects = [];

  // Ticker for floater life.
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  @override
  void initState() {
    super.initState();
    _tubeCount = _tubesForLevel(widget.level);
    _level = widget.level;
    _colourCount = _coloursForLevel(_level);

    _liftCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _pourCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _idleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();

    _ticker = createTicker(_onTick)..start();

    _initLevel();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      reportScore(_score);
      reportStats('Level $_level  •  Moves $_moves');
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _liftCtrl.dispose();
    _shakeCtrl.dispose();
    _pourCtrl.dispose();
    _idleCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────
  // Level setup
  // ─────────────────────────────────────────────────────────────

  static int _coloursForLevel(int level) {
    if (level >= 7) return 6;
    if (level >= 4) return 5;
    return 4;
  }

  static int _tubesForLevel(int level) {
    if (level >= 7) return 7;
    if (level >= 4) return 6;
    return 5;
  }

  void _initLevel() {
    final rng = widget.dailyChallenge
        ? Random(dailySeedFor('water-sort'))
        : Random();

    // Classic Water Sort: leave one playable tube empty, fill the rest
    // with a random mixture so the puzzle isn't already solved. We
    // pick `distinctColours` distinct colours and distribute `layers`
    // copies of each across `distinctColours` tubes. The final
    // (distinctColours)-th tube gets left empty. The locked /
    // extra-tube slot is purely decorative (see [_isLockedSlot]).
    final distinctColours =
        (_tubeCount - 1).clamp(1, _colourCount);
    final chosen = <int>{};
    var guard = 0;
    while (chosen.length < distinctColours && guard++ < 200) {
      chosen.add(rng.nextInt(_colourCount));
    }
    while (chosen.length < distinctColours) {
      // Fallback: cycle colours if RNG degenerate (shouldn't happen).
      chosen.add(chosen.length % _colourCount);
    }
    final colourList = chosen.toList()..shuffle(rng);

    // Build the colour pool: each chosen colour contributes `_layers`
    // copies, then shuffle so the distribution across tubes is mixed.
    final pool = <int>[
      for (final c in colourList) ...List.filled(_layers, c),
    ]..shuffle(rng);

    _tubes = List<List<int>>.generate(_tubeCount + 1, (_) => []);

    // Fill `distinctColours` tubes with the shuffled pool. The remaining
    // playable tube (index = distinctColours) starts empty.
    for (var i = 0; i < distinctColours; i++) {
      _tubes[i] = <int>[];
      for (var k = 0; k < _layers; k++) {
        // Pool has exactly distinctColours * _layers elements; pulling
        // by index is safe because we cap to that count.
        final idx = i * _layers + k;
        if (idx < pool.length) {
          _tubes[i].add(pool[idx]);
        } else {
          _tubes[i].add(colourList[i % colourList.length]);
        }
      }
    }

    // Safety: a degenerate shuffle could land all 4 of a colour in one
    // tube, accidentally completing it. Re-shuffle the pool a couple of
    // times if any filled tube is already uniform.
    for (var attempt = 0; attempt < 6; attempt++) {
      var anyUniform = false;
      for (var i = 0; i < distinctColours; i++) {
        if (_tubes[i].length == _layers &&
            _tubes[i].every((c) => c == _tubes[i].first)) {
          anyUniform = true;
          break;
        }
      }
      if (!anyUniform) break;
      pool.shuffle(rng);
      for (var i = 0; i < distinctColours; i++) {
        _tubes[i].clear();
        for (var k = 0; k < _layers; k++) {
          _tubes[i].add(pool[i * _layers + k]);
        }
      }
    }

    _moves = 0;
    _perfectPourStreak = 0;
    _completedTubes.clear();
    _floaters.clear();
    _history.clear();
    _selected = null;
    _liftIdx = -1;
    _liftCtrl.value = 0;
    _invalidIdx = -1;
    _shakeCtrl.value = 0;
    _pourFrom = null;
    _pourTo = null;
    _pourCount = 0;
    _pourColour = 0;
  }

  bool _isLockedSlot(int idx) => idx == _tubeCount;

  // ─────────────────────────────────────────────────────────────
  // Tick — animate floaters
  // ─────────────────────────────────────────────────────────────
  void _onTick(Duration elapsed) {
    if (_floaters.isEmpty) return;
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (dt <= 0 || dt > 0.1) return;

    var dirty = false;
    for (final f in _floaters) {
      f.life -= dt;
      f.y -= dt * 28;
      dirty = true;
    }
    _floaters.removeWhere((f) => f.life <= 0);
    if (dirty) setState(() {});
  }

  // ─────────────────────────────────────────────────────────────
  // Input + pour
  // ─────────────────────────────────────────────────────────────

  void _onTapTube(int idx) {
    if (_gameOver) return;
    if (_pourCtrl.isAnimating) return;
    if (_shakeCtrl.isAnimating) return;
    if (_isLockedSlot(idx)) return;

    if (_selected == null) {
      if (_tubes[idx].isNotEmpty) {
        setState(() {
          _selected = idx;
          _liftIdx = idx;
          _liftCtrl.forward(from: 0);
        });
        haptic(HapticFeedbackType.light);
      }
      return;
    }

    if (_selected == idx) {
      setState(() {
        _selected = null;
        _liftIdx = -1;
        _liftCtrl.reverse();
      });
      return;
    }

    final from = _selected!;
    final to = idx;
    if (!_canPour(from, to)) {
      setState(() {
        _invalidIdx = idx;
        _selected = null;
        _liftIdx = -1;
        _liftCtrl.reverse();
      });
      _shakeCtrl.forward(from: 0).then((_) {
        if (mounted) {
          setState(() => _invalidIdx = -1);
          _shakeCtrl.value = 0;
        }
      });
      haptic(HapticFeedbackType.light);
      return;
    }

    _tryPour(from, to);
  }

  bool _canPour(int from, int to) {
    final src = _tubes[from];
    final dst = _tubes[to];
    if (src.isEmpty) return false;
    if (dst.length >= _layers) return false;
    if (dst.isNotEmpty && dst.last != src.last) return false;

    // Source's top run length.
    final top = src.last;
    var runLen = 0;
    for (var i = src.length - 1; i >= 0; i--) {
      if (src[i] != top) break;
      runLen++;
    }
    final free = _layers - dst.length;
    return runLen <= free;
  }

  void _tryPour(int from, int to) {
    final src = _tubes[from];
    final dst = _tubes[to];
    final colour = src.last;
    var count = 0;
    while (src.isNotEmpty &&
        src.last == colour &&
        dst.length + count < _layers) {
      src.removeLast();
      dst.add(colour);
      count++;
    }
    final completedBefore = _completedTubes.contains(to);

    setState(() {
      _selected = null;
      _liftIdx = -1;
      _moves++;
      _score = max(0, 1000 + _level * 50 - _moves * 25);
      if (count >= 2) {
        _perfectPourStreak++;
        _score += _perfectPourStreak * 25;
      } else {
        _perfectPourStreak = 0;
      }
      _pourFrom = from;
      _pourTo = to;
      _pourCount = count;
      _pourColour = colour;
      _history.add(_Move(from: from, to: to, count: count));
      if (_history.length > _historyCap) {
        _history.removeRange(0, _history.length - _historyCap);
      }
      _pourCtrl.forward(from: 0).then((_) {
        if (mounted) {
          setState(() {
            _pourFrom = null;
            _pourTo = null;
            _pourCount = 0;
          });
          _checkCompletionAfterPour(from, to, completedBefore);
        }
      });
    });
    haptic(HapticFeedbackType.medium);
    reportScore(_score);
    reportStats('Level $_level  •  Moves $_moves');
  }

  void _undo() {
    if (_history.isEmpty || _gameOver) return;
    if (_pourCtrl.isAnimating || _liftCtrl.isAnimating) return;
    final move = _history.removeLast();
    final src = _tubes[move.to];
    final dst = _tubes[move.from];
    final colour = src.last;
    for (var i = 0; i < move.count; i++) {
      src.removeLast();
      dst.add(colour);
    }
    setState(() {
      _moves = max(0, _moves - 1);
      _score = max(0, 1000 + _level * 50 - _moves * 25);
      _invalidIdx = -1;
      _liftIdx = -1;
      _selected = null;
      _pourFrom = null;
      _pourTo = null;
      _completedTubes.clear();
    });
    haptic(HapticFeedbackType.light);
    reportScore(_score);
    reportStats('Level $_level  •  Moves $_moves');
  }

  void _hint() {
    if (_hintsLeft <= 0) return;
    // Try to find a productive move: pour into a tube that would
    // complete it (uniform-full) or pour into the empty tube with a
    // matching top colour. If we find one, highlight both source and
    // destination as a flashing ring for a moment.
    final emptyIdx = <int>[];
    for (var i = 0; i < _tubeCount; i++) {
      if (_tubes[i].isEmpty) emptyIdx.add(i);
    }

    int? src;
    int? dst;
    for (var i = 0; i < _tubeCount; i++) {
      if (_tubes[i].isEmpty) continue;
      // Prefer moves that would complete the destination tube.
      for (var j = 0; j < _tubeCount; j++) {
        if (i == j) continue;
        if (_tubes[j].length == _layers) continue;
        if (!_canPour(i, j)) continue;
        // Pick destination that has the most matching top already.
        final srcTop = _tubes[i].last;
        if (_tubes[j].isNotEmpty && _tubes[j].last != srcTop) continue;
        // Prefer completing a tube.
        if (_tubes[j].length == _layers - 1 && _tubes[j].last == srcTop) {
          src = i;
          dst = j;
          break;
        }
        // Otherwise, prefer empty tubes (always useful) over partials.
        if (src == null ||
            (_tubes[j].isEmpty &&
                dst != null &&
                _tubes[dst].isNotEmpty)) {
          src = i;
          dst = j;
        }
      }
      if (src != null && _tubes[dst!].length == _layers - 1) break;
    }

    setState(() {
      _hintsLeft--;
      _hintSrc = src;
      _hintDst = dst;
      _hintUntil = DateTime.now().add(const Duration(milliseconds: 1400));
    });
    haptic(HapticFeedbackType.selection);
    // Auto-clear hint highlight after the duration.
    Future<void>.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      final deadline = _hintUntil;
      if (deadline != null && DateTime.now().isAfter(deadline)) {
        setState(() {
          _hintSrc = null;
          _hintDst = null;
          _hintUntil = null;
        });
      }
    });
  }

  // ─────────────────────────────────────────────────────────────
  // Completion + win
  // ─────────────────────────────────────────────────────────────

  void _checkCompletionAfterPour(
      int from, int to, bool destWasCompletedBefore) {
    final dst = _tubes[to];
    if (_isUniformFull(dst) && !destWasCompletedBefore) {
      _completedTubes.add(to);
      _spawnPerfectFloater(to);
      haptic(HapticFeedbackType.heavy);
    }
    if (_checkWin()) {
      _gameOver = true;
      haptic(HapticFeedbackType.heavy);
      reportScore(_score);
      reportStats('Puzzle solved in $_moves moves!');
      reportGameOver();
    }
  }

  bool _isUniformFull(List<int> tube) {
    if (tube.length != _layers) return false;
    final c = tube.first;
    for (final v in tube) {
      if (v != c) return false;
    }
    return true;
  }

  bool _checkWin() {
    for (var i = 0; i < _tubes.length; i++) {
      if (_isLockedSlot(i)) continue;
      final t = _tubes[i];
      if (t.isEmpty) continue;
      if (!_isUniformFull(t)) return false;
    }
    return true;
  }

  void _spawnPerfectFloater(int tubeIdx) {
    if (_tubeRects.isEmpty || tubeIdx >= _tubeRects.length) return;
    final r = _tubeRects[tubeIdx];
    _floaters.add(_Floater(
      x: r.center.dx,
      y: r.top - 6,
      text: 'PERFECT!',
      color: const Color(0xFFFFD83D),
      life: 1.4,
    ));
  }

  // ─────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // RepaintBoundary isolates all tube repaints from the host. The
    // scene-level RebuildBoundary below ensures state changes don't
    // tear down the tube painters (each tube has its own boundary).
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          _WaterSortScene(
            idleCtrl: _idleCtrl,
            tubes: _tubes,
            tubeCount: _tubeCount,
            palette: _palette,
            layers: _layers,
            selected: _selected,
            liftIdx: _liftIdx,
            liftCtrl: _liftCtrl,
            invalidIdx: _invalidIdx,
            shakeCtrl: _shakeCtrl,
            pourFrom: _pourFrom,
            pourTo: _pourTo,
            pourCount: _pourCount,
            pourColour: _pourColour,
            pourCtrl: _pourCtrl,
            hintSrc: _hintSrc,
            hintDst: _hintDst,
            hintUntil: _hintUntil,
            tubeRects: _tubeRects,
            floaters: _floaters,
            onTap: _onTapTube,
            isLockedSlot: _isLockedSlot,
          ),
          // Bottom-left: Undo button.
          Positioned(
            left: 16,
            bottom: 18,
            child: _CornerActionButton(
              icon: Icons.undo_rounded,
              label: 'Undo',
              accent: const Color(0xFFFBBF24),
              enabled: _history.isNotEmpty && !_gameOver,
              onTap: _undo,
            ),
          ),
          // Bottom-right: Hint button with counter badge.
          Positioned(
            right: 16,
            bottom: 18,
            child: _CornerActionButton(
              icon: Icons.lightbulb_rounded,
              label: 'Hint',
              accent: const Color(0xFFFBBF24),
              badge: _hintsLeft,
              enabled: _hintsLeft > 0 && !_gameOver,
              onTap: _hint,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Scene — the heavy painter lives here.
// ─────────────────────────────────────────────────────────────

class _WaterSortScene extends StatelessWidget {
  const _WaterSortScene({
    required this.idleCtrl,
    required this.tubes,
    required this.tubeCount,
    required this.palette,
    required this.layers,
    required this.selected,
    required this.liftIdx,
    required this.liftCtrl,
    required this.invalidIdx,
    required this.shakeCtrl,
    required this.pourFrom,
    required this.pourTo,
    required this.pourCount,
    required this.pourColour,
    required this.pourCtrl,
    required this.hintSrc,
    required this.hintDst,
    required this.hintUntil,
    required this.tubeRects,
    required this.floaters,
    required this.onTap,
    required this.isLockedSlot,
  });

  final AnimationController idleCtrl;
  final List<List<int>> tubes;
  final int tubeCount;
  final List<Color> palette;
  final int layers;
  final int? selected;
  final int liftIdx;
  final Animation<double> liftCtrl;
  final int invalidIdx;
  final Animation<double> shakeCtrl;
  final int? pourFrom;
  final int? pourTo;
  final int pourCount;
  final int pourColour;
  final Animation<double> pourCtrl;
  final int? hintSrc;
  final int? hintDst;
  final DateTime? hintUntil;
  final List<Rect> tubeRects;
  final List<_Floater> floaters;
  final ValueChanged<int> onTap;
  final bool Function(int) isLockedSlot;

  @override
  Widget build(BuildContext context) {
    // The water-sort scene lays out as a single horizontal row of
    // tubes (playable + one locked slot). Using Row + Expanded instead
    // of a Stack + Positioned + LayoutBuilder means Flutter itself
    // distributes the available width across tubes — so there's no
    // chance of a mis-computed cellW collapsing every tube onto x=0.
    return Container(
      color: const Color(0xFF4A1E1E),
      child: LayoutBuilder(
        builder: (context, c) {
          // Cache tube rectangles for floater spawn / hint targets.
          // We use each tube's actual rendered width once the Row lays
          // out — but to keep the painter self-contained we'll compute
          // rects from the same column-width math the Row uses.
          final playableCount = tubes.length - 1; // last entry is locked
          final cellW = c.maxWidth / (playableCount + 1);
          final cellH = c.maxHeight;

          tubeRects.clear();
          for (var i = 0; i < tubes.length; i++) {
            if (isLockedSlot(i)) {
              tubeRects.add(Rect.zero);
              continue;
            }
            final tubeW = cellW * 0.78;
            final tubeH = cellH * 0.78;
            tubeRects.add(Rect.fromCenter(
              center: Offset(
                i * cellW + cellW / 2,
                cellH * 0.55,
              ),
              width: tubeW,
              height: tubeH,
            ));
          }

          return Stack(
            fit: StackFit.expand,
            children: [
              // Vignette backdrop.
              const IgnorePointer(
                child: CustomPaint(painter: _BackdropPainter()),
              ),
              // Tubes laid out as a Row so each tube gets a real,
              // bounded width — no manual math that could collapse.
              Padding(
                padding: EdgeInsets.symmetric(horizontal: cellW * 0.11),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    for (var i = 0; i < tubes.length; i++)
                      if (!isLockedSlot(i))
                        Expanded(child: _buildTube(i)),
                    // Locked / extra slot, same width as a playable tube.
                    SizedBox(
                      width: cellW * 0.78,
                      child: const _LockedSlot(),
                    ),
                  ],
                ),
              ),
              // Pour stream overlay (renders above tubes).
              if (pourFrom != null && pourTo != null && pourCount > 0)
                IgnorePointer(
                  child: AnimatedBuilder(
                    animation: pourCtrl,
                    builder: (context, _) => CustomPaint(
                      painter: _PourStreamPainter(
                        sourceRect: tubeRects[pourFrom!],
                        destRect: tubeRects[pourTo!],
                        progress: pourCtrl.value,
                        colour: palette[pourColour % palette.length],
                      ),
                    ),
                  ),
                ),
              // Floaters.
              IgnorePointer(
                child: AnimatedBuilder(
                  animation: idleCtrl,
                  builder: (context, _) => CustomPaint(
                    painter: _FloatersPainter(floaters: floaters),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTube(int idx) {
    final isLift = liftIdx == idx;
    final isInv = invalidIdx == idx;
    final isPourSrc = pourFrom == idx;
    final isPourDst = pourTo == idx;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([
          if (isLift) liftCtrl,
          if (isInv) shakeCtrl,
          if (isPourSrc) pourCtrl,
          idleCtrl,
        ]),
        builder: (context, _) {
          final lift = isLift ? -10.0 * liftCtrl.value : 0.0;
          final shake = isInv
              ? 6.0 *
                  sin(shakeCtrl.value * pi * 6) *
                  (1 - shakeCtrl.value)
              : 0.0;
          final pourProgress = isPourSrc ? pourCtrl.value : 0.0;
          double tiltDeg = 0;
          double translateUp = 0;
          if (isPourSrc && pourProgress > 0 && pourProgress < 1) {
            final srcCx = tubeRects[idx].center.dx;
            final dstIdx = pourTo ?? -1;
            final dstCx = (dstIdx >= 0 && dstIdx < tubeRects.length)
                ? tubeRects[dstIdx].center.dx
                : srcCx;
            final horizSign = (dstCx - srcCx) >= 0 ? 1.0 : -1.0;
            final mid = pourProgress < 0.5
                ? pourProgress * 2
                : (1 - pourProgress) * 2;
            tiltDeg = -45.0 * horizSign * mid.clamp(0.0, 1.0);
            translateUp = -8.0 * mid.clamp(0.0, 1.0);
          }
          return Transform.translate(
            offset: Offset(shake, lift + translateUp),
            child: Transform.rotate(
              angle: tiltDeg * pi / 180,
              alignment: Alignment.bottomCenter,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onTap(idx),
                child: AspectRatio(
                  aspectRatio: 0.55,
                  child: CustomPaint(
                    painter: _TubePainter(
                      tube: tubes[idx],
                      layers: layers,
                      palette: palette,
                      selected: isLift,
                      invalid: isInv,
                      pourSource: isPourSrc,
                      pourDest: isPourDst,
                      pourProgress: pourProgress,
                      pourCount: pourCount,
                      pourColour: pourColour,
                      idleT: idleCtrl.value,
                      isTilted: tiltDeg.abs() > 0.1,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Backdrop painter — vignette + soft gradient for depth.
// ─────────────────────────────────────────────────────────────

class _BackdropPainter extends CustomPainter {
  const _BackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // Subtle radial vignette darkening corners.
    final gradient = RadialGradient(
      center: Alignment.center,
      radius: 1.0,
      colors: const [
        Color(0xFF5A2828),
        Color(0xFF4A1E1E),
        Color(0xFF2E1414),
      ],
      stops: const [0.0, 0.55, 1.0],
    );
    final paint = Paint()..shader = gradient.createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter old) => false;
}

// ─────────────────────────────────────────────────────────────
// Locked / extra slot (dashed outline + padlock).
// ─────────────────────────────────────────────────────────────

class _LockedSlot extends StatelessWidget {
  const _LockedSlot();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _LockedSlotPainter());
  }
}

class _LockedSlotPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Rect.fromLTWH(8, 0, w - 16, h);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(20));
    final paint = Paint()
      ..color = const Color(0xFF6B7280).withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path()..addRRect(rrect);
    final dashed = _dashedPath(path, dashWidth: 6, gapWidth: 4);
    canvas.drawPath(dashed, paint);
    // Padlock icon centered.
    final iconSize = h * 0.30;
    final cx = w / 2;
    final cy = h / 2;
    final bodyRect = Rect.fromCenter(
      center: Offset(cx, cy + iconSize * 0.15),
      width: iconSize * 0.9,
      height: iconSize * 0.7,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, const Radius.circular(4)),
      Paint()..color = const Color(0xFF9CA3AF),
    );
    final shackle = Path()
      ..addArc(
        Rect.fromCenter(
          center: Offset(cx, cy - iconSize * 0.1),
          width: iconSize * 0.55,
          height: iconSize * 0.55,
        ),
        pi,
        pi,
      );
    final shacklePaint = Paint()
      ..color = const Color(0xFF9CA3AF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawPath(shackle, shacklePaint);
  }

  Path _dashedPath(Path source,
      {required double dashWidth, required double gapWidth}) {
    final result = Path();
    for (final metric in source.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final next = distance + dashWidth;
        result.addPath(
          metric.extractPath(distance, next.clamp(0.0, metric.length)),
          Offset.zero,
        );
        distance = next + gapWidth;
      }
    }
    return result;
  }

  @override
  bool shouldRepaint(covariant _LockedSlotPainter old) => false;
}

// ─────────────────────────────────────────────────────────────
// Tube painter — realistic glass + liquid layers with meniscus.
// ─────────────────────────────────────────────────────────────

class _TubePainter extends CustomPainter {
  _TubePainter({
    required this.tube,
    required this.layers,
    required this.palette,
    required this.selected,
    required this.invalid,
    required this.pourSource,
    required this.pourDest,
    required this.pourProgress,
    required this.pourCount,
    required this.pourColour,
    required this.idleT,
    required this.isTilted,
  });

  final List<int> tube;
  final int layers;
  final List<Color> palette;
  final bool selected;
  final bool invalid;
  final bool pourSource;
  final bool pourDest;
  final double pourProgress;
  final int pourCount;
  final int pourColour;
  final double idleT;
  final bool isTilted;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rimRadius = w * 0.22;
    final neckInset = w * 0.04;
    final bodyLeft = neckInset;
    final bodyRight = w - neckInset;
    final rimY = 0.0;
    final neckH = h * 0.10;
    final bodyTop = neckH;
    final bodyBottom = h - rimRadius * 0.4;

    // ─── 1. Outer shadow (subtle drop) ───────────────────────
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(1, 2, w - 2, h),
        topLeft: Radius.circular(rimRadius),
        topRight: Radius.circular(rimRadius),
        bottomLeft: Radius.elliptical(rimRadius, rimRadius * 0.6),
        bottomRight: Radius.elliptical(rimRadius, rimRadius * 0.6),
      ),
      Paint()
        ..color = const Color(0x44000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // ─── 2. Glass body fill (very dark transparent, like glass) ─
    final glassBody = Path()
      ..moveTo(bodyLeft, bodyTop)
      ..lineTo(bodyRight, bodyTop)
      ..lineTo(bodyRight, bodyBottom)
      ..arcToPoint(
        Offset(bodyLeft, bodyBottom),
        radius: Radius.elliptical(w / 2, h * 0.18),
        clockwise: false,
      )
      ..close();
    canvas.drawPath(
      glassBody,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: const [
            Color(0x33FFFFFF),
            Color(0x11000000),
            Color(0x22FFFFFF),
          ],
        ).createShader(Offset.zero & size),
    );

    // ─── 3. Liquid layers ─────────────────────────────────────
    if (tube.isNotEmpty) {
      final innerLeft = bodyLeft + 2;
      final innerRight = bodyRight - 2;
      final layerH = (bodyBottom - bodyTop - 6) / layers;
      // Animated gentle bob (sin wave) per layer for shimmer.
      final bob = sin(idleT * 2 * pi) * 1.2;
      for (var i = 0; i < tube.length; i++) {
        final idx = tube[i];
        final baseColor = palette[idx % palette.length];
        final layerRect = Rect.fromLTRB(
          innerLeft,
          bodyBottom - 4 - (i + 1) * layerH + bob,
          innerRight,
          bodyBottom - 4 - i * layerH + bob,
        );
        // Main liquid body gradient: bright at top, deeper at bottom.
        final liquidPaint = Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(baseColor, Colors.white, 0.18)!,
              baseColor,
              Color.lerp(baseColor, Colors.black, 0.22)!,
            ],
            stops: const [0.0, 0.45, 1.0],
          ).createShader(layerRect);
        // Use a rounded path that follows the tube shape.
        final path = Path()
          ..addRRect(RRect.fromRectAndRadius(
            layerRect,
            const Radius.circular(2),
          ));
        canvas.drawPath(path, liquidPaint);

        // ─── Meniscus on top of the topmost layer ──────────────
        if (i == tube.length - 1) {
          final meniscus = Rect.fromLTRB(
            innerLeft,
            layerRect.top - 3,
            innerRight,
            layerRect.top + 1,
          );
          canvas.drawOval(
            meniscus,
            Paint()..color = baseColor,
          );
          // Highlight crescent on meniscus.
          canvas.drawArc(
            Rect.fromLTRB(
              innerLeft + 1,
              layerRect.top - 2.5,
              innerRight - 1,
              layerRect.top + 1,
            ),
            pi,
            pi,
            false,
            Paint()
              ..color = Colors.white.withValues(alpha: 0.55)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2,
          );
        }
      }
    }

    // ─── 4. Selection / invalid glow ring ─────────────────────
    if (selected) {
      final rrect = RRect.fromRectAndCorners(
        Rect.fromLTWH(0, 0, w, h),
        topLeft: Radius.circular(rimRadius),
        topRight: Radius.circular(rimRadius),
        bottomLeft: Radius.elliptical(rimRadius, rimRadius * 0.6),
        bottomRight: Radius.elliptical(rimRadius, rimRadius * 0.6),
      );
      canvas.drawRRect(
        rrect.inflate(3),
        Paint()
          ..color = const Color(0xFFFCD34D).withValues(alpha: 0.75)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      );
    }
    if (invalid) {
      final rrect = RRect.fromRectAndCorners(
        Rect.fromLTWH(0, 0, w, h),
        topLeft: Radius.circular(rimRadius),
        topRight: Radius.circular(rimRadius),
        bottomLeft: Radius.elliptical(rimRadius, rimRadius * 0.6),
        bottomRight: Radius.elliptical(rimRadius, rimRadius * 0.6),
      );
      canvas.drawRRect(
        rrect.inflate(2),
        Paint()
          ..color = const Color(0xFFEF4444)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      );
    }

    // ─── 5. Pour stream + tilted source tube ─────────────────
    if (pourSource && pourProgress > 0 && pourCount > 0) {
      _paintPourSource(canvas, size, bodyLeft, bodyRight, bodyTop, bodyBottom);
    }

    // ─── 6. Highlight strip on left edge (glass shine) ─────────
    final highlightPath = Path()
      ..moveTo(bodyLeft + 2, bodyTop + 4)
      ..lineTo(bodyLeft + 4, bodyBottom - 8)
      ..lineTo(bodyLeft + 6, bodyBottom - 8)
      ..lineTo(bodyLeft + 4, bodyTop + 4)
      ..close();
    canvas.drawPath(
      highlightPath,
      Paint()..color = Colors.white.withValues(alpha: 0.35),
    );

    // ─── 7. Rim (top lip) ─────────────────────────────────────
    final rimRect = Rect.fromLTRB(0, rimY, w, neckH + 4);
    final rimRRect =
        RRect.fromRectAndRadius(rimRect, Radius.circular(rimRadius));
    canvas.drawRRect(
      rimRRect,
      Paint()..color = const Color(0x33FFFFFF),
    );

    // ─── 8. Crisp white outline ────────────────────────────────
    final outlinePath = Path()
      ..moveTo(bodyLeft, bodyTop)
      ..lineTo(bodyLeft, bodyBottom - rimRadius * 0.6)
      ..arcToPoint(
        Offset(bodyLeft + rimRadius, bodyBottom),
        radius: Radius.elliptical(rimRadius, rimRadius * 0.6),
        clockwise: true,
      )
      ..lineTo(bodyRight - rimRadius, bodyBottom)
      ..arcToPoint(
        Offset(bodyRight, bodyBottom - rimRadius * 0.6),
        radius: Radius.elliptical(rimRadius, rimRadius * 0.6),
        clockwise: true,
      )
      ..lineTo(bodyRight, bodyTop);
    final outlinePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(outlinePath, outlinePaint);

    // Rim outline (top ellipse).
    canvas.drawArc(
      Rect.fromLTWH(0, 0, w, neckH * 1.6),
      pi,
      pi,
      false,
      outlinePaint,
    );
  }

  void _paintPourSource(Canvas canvas, Size size, double bodyLeft,
      double bodyRight, double bodyTop, double bodyBottom) {
    // Pour stream and destination draw handled by the overlay painter.
    // Here we just draw a subtle pour-tilt visual on the source.
  }

  @override
  bool shouldRepaint(covariant _TubePainter old) {
    return old.tube != tube ||
        old.selected != selected ||
        old.invalid != invalid ||
        old.pourSource != pourSource ||
        old.pourDest != pourDest ||
        old.pourProgress != pourProgress ||
        old.pourCount != pourCount ||
        old.pourColour != pourColour ||
        old.idleT != idleT ||
        old.isTilted != isTilted;
  }
}

// ─────────────────────────────────────────────────────────────
// Floaters overlay (PERFECT! etc.)
// ─────────────────────────────────────────────────────────────

class _PourStreamPainter extends CustomPainter {
  _PourStreamPainter({
    required this.sourceRect,
    required this.destRect,
    required this.progress,
    required this.colour,
  });

  final Rect sourceRect;
  final Rect destRect;
  final double progress;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;

    // Source end: tilted source emits from its upper side.
    final srcCentreX = sourceRect.center.dx;
    final srcTop = sourceRect.top + sourceRect.height * 0.20;
    // Pick side based on x-sign of destination.
    final sideX = destRect.center.dx >= srcCentreX
        ? sourceRect.right
        : sourceRect.left;
    final start = Offset(sideX, srcTop);

    // Destination entry point at the top opening of the dest tube.
    final endCentreX = destRect.center.dx;
    final endTop = destRect.top + destRect.height * 0.05;
    final end = Offset(endCentreX, endTop);

    // Stream width tapers.
    final streamWidth = 9.0 * (1 - progress * 0.5);

    // Stream grows in opacity as pour starts, fades at the end.
    final opacity = progress < 0.5
        ? (progress * 2).clamp(0.0, 1.0)
        : ((1 - progress) * 2).clamp(0.0, 1.0);

    final paint = Paint()
      ..color = colour.withValues(alpha: opacity * 0.85)
      ..strokeWidth = streamWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Curved bezier for a natural arc.
    final ctrl1 = Offset(
      start.dx + (end.dx - start.dx) * 0.4,
      start.dy - 30,
    );
    final ctrl2 = Offset(
      end.dx - (end.dx - start.dx) * 0.2,
      end.dy - 25,
    );
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(
        ctrl1.dx,
        ctrl1.dy,
        ctrl2.dx,
        ctrl2.dy,
        end.dx,
        end.dy,
      );

    // Glow underlay.
    canvas.drawPath(
      path,
      Paint()
        ..color = colour.withValues(alpha: opacity * 0.35)
        ..strokeWidth = streamWidth * 2.4
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawPath(path, paint);

    // A small "drop" accent near destination.
    final dropProgress = (progress * 1.6).clamp(0.0, 1.0);
    final dropPos = Offset.lerp(start, end, dropProgress)!;
    canvas.drawCircle(
      dropPos,
      4.0,
      Paint()..color = colour.withValues(alpha: opacity),
    );
  }

  @override
  bool shouldRepaint(covariant _PourStreamPainter old) =>
      old.progress != progress ||
      old.sourceRect != sourceRect ||
      old.destRect != destRect ||
      old.colour != colour;
}

class _FloatersPainter extends CustomPainter {
  _FloatersPainter({required this.floaters});
  final List<_Floater> floaters;

  @override
  void paint(Canvas canvas, Size size) {
    for (final f in floaters) {
      final alpha = (f.life / 1.4).clamp(0.0, 1.0);
      final tp = TextPainter(
        text: TextSpan(
          text: f.text,
          style: TextStyle(
            color: f.color.withValues(alpha: alpha),
            fontSize: 18,
            fontWeight: FontWeight.w900,
            shadows: const [
              Shadow(blurRadius: 4, color: Colors.black87),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(f.x - tp.width / 2, f.y));
    }
  }

  @override
  bool shouldRepaint(covariant _FloatersPainter old) =>
      old.floaters != floaters;
}

// ─────────────────────────────────────────────────────────────
// Records
// ─────────────────────────────────────────────────────────────

class _Floater {
  _Floater({
    required this.x,
    required this.y,
    required this.text,
    required this.color,
    required this.life,
  });
  double x;
  double y;
  String text;
  Color color;
  double life;
}

class _Move {
  _Move({required this.from, required this.to, required this.count});
  final int from;
  final int to;
  final int count;
}

/// Bottom-corner action button used by Water Sort. Matches the
/// reference image's yellow circular Undo / Hint chips with a small
/// label below and an optional counter badge.
class _CornerActionButton extends StatelessWidget {
  const _CornerActionButton({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
    this.enabled = true,
    this.badge,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;
  final bool enabled;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? accent : accent.withValues(alpha: 0.35);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? onTap : null,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.45),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    icon,
                    color: const Color(0xFF1F2937),
                    size: 28,
                  ),
                ),
                if (badge != null && badge! > 0)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1F2937),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white,
                          width: 1.5,
                        ),
                      ),
                      constraints: const BoxConstraints(minWidth: 22),
                      alignment: Alignment.center,
                      child: Text(
                        '$badge',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: enabled
                ? const Color(0xFFFDE68A)
                : const Color(0xFFFDE68A).withValues(alpha: 0.35),
            fontSize: 12,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }
}
