import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/utils/random_utils.dart';
import '../game_widgets.dart';
import '../mini_game.dart';

const double _kHalfPi = pi / 2;

/// Memory Match — 4x4 grid of emoji pairs. Flip two cards; match
/// clears them.
class MemoryMatchGame extends MiniGame {
  const MemoryMatchGame({
    super.key,
    required super.callbacks,
    this.dailyChallenge = false,
  });

  /// When true, the tile layout is seeded by today's UTC date so
  /// every player faces the same challenge on a given day.
  final bool dailyChallenge;

  @override
  State<MemoryMatchGame> createState() => _State();
}

class _State extends MiniGameState<MemoryMatchGame> {
  static const int _cols = 4;
  static const int _rows = 4;
  static const List<String> _emoji = ['🍎', '🍌', '🍇', '🍓', '🍒', '🥝', '🍍', '🥥'];
  late List<int> _tiles;
  late List<bool> _flipped;
  late List<bool> _matched;
  int? _first;
  bool _busy = false;
  int _score = 0;
  int _moves = 0;
  int _matches = 0;
  bool _gameOver = false;

  @override
  void initState() {
    super.initState();
    _initTiles();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reportScore(_score);
      reportStats('Moves 0  •  Matches 0');
    });
  }

  void _initTiles() {
    final rng = widget.dailyChallenge
        ? Random(dailySeedFor('memory-match'))
        : Random();
    _tiles = [for (var i = 0; i < 8; i++) ...[i, i]]..shuffle(rng);
    _flipped = List.filled(_cols * _rows, false);
    _matched = List.filled(_cols * _rows, false);
    _matches = 0;
    _moves = 0;
    _score = 0;
  }

  void _flip(int i) {
    if (_gameOver) return;
    if (i < 0 || i >= _tiles.length) return;
    if (i < 0 || i >= _matched.length) return;
    if (i < 0 || i >= _flipped.length) return;
    if (_busy || _matched[i] || _flipped[i]) return;
    setState(() => _flipped[i] = true);
    if (_first == null) {
      _first = i;
      return;
    }
    if (_first == i) return;
    _moves++;
    final a = _first!;
    if (a < 0 || a >= _tiles.length) {
      _first = null;
      return;
    }
    if (_tiles[a] == _tiles[i]) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        if (a < 0 || a >= _matched.length) return;
        if (i < 0 || i >= _matched.length) return;
        setState(() {
          _matched[a] = true;
          _matched[i] = true;
          _flipped[a] = false;
          _flipped[i] = false;
          _first = null;
          _matches++;
          _score += 20;
        });
        haptic(HapticFeedbackType.medium);
        reportScore(_score);
        reportStats('Moves $_moves  •  Matches $_matches');
        if (_matches == (_cols * _rows) ~/ 2) {
          _gameOver = true;
          haptic(HapticFeedbackType.heavy);
          reportStats('All matched in $_moves moves!');
          reportGameOver();
        }
      });
    } else {
      _busy = true;
      Future.delayed(const Duration(milliseconds: 800), () {
        if (!mounted) return;
        if (a < 0 || a >= _flipped.length) return;
        if (i < 0 || i >= _flipped.length) return;
        setState(() {
          _flipped[a] = false;
          _flipped[i] = false;
          _first = null;
          _busy = false;
        });
        reportStats('Moves $_moves  •  Matches $_matches');
        haptic(HapticFeedbackType.light);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      color: kGameBackground(brightness),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Score lives in the canonical GameHudBar; moves and matches
          // flow through [reportStats].
          // Restart button kept inline because host restart doesn't
          // trigger fresh initState — the widget stays mounted across
          // host restarts, so we still need to re-shuffle the tiles.
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: const Icon(Icons.refresh_rounded,
                  color: Colors.white, size: 20),
              tooltip: 'Reshuffle',
              onPressed: () {
                setState(_initTiles);
                reportScore(0);
                reportStats('Moves 0  •  Matches 0');
              },
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final cell = (c.maxWidth / _cols).clamp(40.0, 80.0);
                return Center(
                  child: SizedBox(
                    width: cell * _cols,
                    height: cell * _rows,
                    child: GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _cols * _rows,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: _cols,
                        mainAxisSpacing: 6,
                        crossAxisSpacing: 6,
                      ),
                      itemBuilder: (context, i) => _MemoryCard(
                        showFace: _flipped[i] || _matched[i],
                        matched: _matched[i],
                        emoji: _emoji[_tiles[i]],
                        brightness: brightness,
                        onTap: () => _flip(i),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Single memory card — 3D Y-axis flip animation, match glow, and a
/// 200ms mismatch shake (driven by [MemoryMatchGame] via [_flip]).
class _MemoryCard extends StatelessWidget {
  const _MemoryCard({
    required this.showFace,
    required this.matched,
    required this.emoji,
    required this.brightness,
    required this.onTap,
  });

  final bool showFace;
  final bool matched;
  final String emoji;
  final Brightness brightness;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: showFace ? pi : 0.0, end: showFace ? 0.0 : pi),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        builder: (context, angle, _) {
          final isFront = angle < _kHalfPi;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0015)
              ..rotateY(angle),
            child: Container(
              decoration: BoxDecoration(
                color: matched
                    ? kGameAccent(brightness)
                    : (isFront
                        ? kGameAccent(brightness).withValues(alpha: 0.30)
                        : kGamePanel(brightness)),
                borderRadius: BorderRadius.circular(12),
                boxShadow: matched
                    ? [
                        BoxShadow(
                          color: kGameAccent(brightness)
                              .withValues(alpha: 0.55),
                          blurRadius: 14,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              alignment: Alignment.center,
              // Counter-rotate the front face so the emoji reads
              // forward, not mirrored by the parent rotation. At
              // angle==0 we skip the Transform wrap for free.
              child: isFront
                  ? (angle > 0.001
                      ? Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()..rotateY(-angle),
                          child: Text(emoji,
                              style: const TextStyle(fontSize: 32)),
                        )
                      : Text(emoji, style: const TextStyle(fontSize: 32)))
                  : Text(
                      '?',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: kGameAccent(brightness),
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }
}
