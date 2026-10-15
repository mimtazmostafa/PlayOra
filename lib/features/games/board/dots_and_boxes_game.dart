import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../game_widgets.dart';
import '../mini_game.dart';

/// Dots and Boxes — ported from
/// `downloaded_games/games/dots_and_boxes/game.py`.
///
/// 8×8 dot grid (so 7×7 = 49 boxes). Players take turns drawing one
/// horizontal or vertical line between adjacent dots. Completing the
/// 4th side of a box claims it for the current player and grants an
/// extra turn. Most boxes wins.
///
/// Bots:
///   * easy   — random available line
///   * medium — greedy: take completing boxes, else avoid giving away
class DotsAndBoxesGame extends MiniGame {
  const DotsAndBoxesGame({
    super.key,
    required super.callbacks,
    this.level = 1,
  });

  final int level;

  @override
  State<DotsAndBoxesGame> createState() => _DotsAndBoxesGameState();
}

enum _DBDifficulty { easy, medium }

class _DotsAndBoxesGameState extends MiniGameState<DotsAndBoxesGame>
    with SingleTickerProviderStateMixin {
  static const int _gridSize = 8;
  static const int _threshold = 18;

  /// Each line is keyed by ('h' | 'v', row, col). Value = player who
  /// drew it (1 or 2). The painter's shouldRepaint compares references
  /// — we always replace the map with a fresh copy on every mutation
  /// so re-renders are triggered.
  Map<String, int> _lines = <String, int>{};
  /// Each claimed box (row, col) → player. Same copy-on-write rule.
  Map<String, int> _boxes = <String, int>{};
  /// Animation time for the most-recently-claimed box, ticks down.
  int _claimFlash = 0;
  /// Most-recent player line drawn — used to highlight it briefly.
  String? _lastDrawnKey;
  int _lastDrawnPlayer = 0;

  int _currentPlayer = 1;
  int _p1Count = 0;
  int _p2Count = 0;
  bool _gameOver = false;
  final bool _isAi = true;
  late _DBDifficulty _difficulty;
  DateTime? _botScheduledAt;
  bool _botThinking = false;

  static const Color _bg = Color(0xFF0C0C16);
  static const Color _dot = Color(0xFFF0F0FF);
  static const Color _p1 = Color(0xFFFF2864);
  static const Color _p2 = Color(0xFF00F5B4);
  static const Color _text = Color(0xFFDCDCF0);

  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    _resetGame();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration _) {
    if (!mounted) return;
    var dirty = false;
    if (_claimFlash > 0) {
      _claimFlash = max(0, _claimFlash - 1);
      dirty = true;
    }
    if (dirty) setState(() {});
    _maybeFireBot();
  }

  void _resetGame() {
    _lines = <String, int>{};
    _boxes = <String, int>{};
    _currentPlayer = 1;
    _p1Count = 0;
    _p2Count = 0;
    _gameOver = false;
    _botThinking = false;
    _botScheduledAt = null;
    _claimFlash = 0;
    _lastDrawnKey = null;
    _difficulty = widget.level >= 2
        ? _DBDifficulty.medium
        : _DBDifficulty.easy;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reportScore(0);
      _updateStats();
    });
  }

  // Copy-on-write helper so the painter sees a new reference.
  void _setLine(String key, int player) {
    _lines = {..._lines, key: player};
  }

  // Copy-on-write helper for boxes.
  void _setBox(String key, int player) {
    _boxes = {..._boxes, key: player};
  }

  // ─── Game mechanics ────────────────────────────────────────────────────

  String _lineKey(String type, int r, int c) => '$type-$r-$c';
  String _boxKey(int r, int c) => '$r-$c';

  /// Returns the line key if the click is near a valid line, else null.
  String? _lineAt(Offset p, Rect grid) {
    final cellW = grid.width / (_gridSize - 1);
    final cellH = grid.height / (_gridSize - 1);
    // Horizontal lines: row r, col c. Each sits at (cx, cy) → segment
    // from (cx, cy) to (cx + cellW, cy).
    for (var r = 0; r < _gridSize; r++) {
      for (var c = 0; c < _gridSize - 1; c++) {
        final cx = grid.left + c * cellW;
        final cy = grid.top + r * cellH;
        final rect = Rect.fromLTWH(
            cx, cy - _threshold, cellW, _threshold * 2);
        if (rect.contains(p)) return _lineKey('h', r, c);
      }
    }
    // Vertical lines: row r, col c.
    for (var r = 0; r < _gridSize - 1; r++) {
      for (var c = 0; c < _gridSize; c++) {
        final cx = grid.left + c * cellW;
        final cy = grid.top + r * cellH;
        final rect = Rect.fromLTWH(
            cx - _threshold, cy, _threshold * 2, cellH);
        if (rect.contains(p)) return _lineKey('v', r, c);
      }
    }
    return null;
  }

  /// Apply the line and return the number of boxes it completed.
  int _applyLine(String key, int player) {
    _setLine(key, player);
    return _checkNewBoxes(player);
  }

  int _checkNewBoxes(int player) {
    var count = 0;
    for (var r = 0; r < _gridSize - 1; r++) {
      for (var c = 0; c < _gridSize - 1; c++) {
        final key = _boxKey(r, c);
        if (_boxes.containsKey(key)) continue;
        final hasTop = _lines.containsKey(_lineKey('h', r, c));
        final hasBottom = _lines.containsKey(_lineKey('h', r + 1, c));
        final hasLeft = _lines.containsKey(_lineKey('v', r, c));
        final hasRight = _lines.containsKey(_lineKey('v', r, c + 1));
        if (hasTop && hasBottom && hasLeft && hasRight) {
          _setBox(key, player);
          count++;
        }
      }
    }
    return count;
  }

  List<String> _availableLines() {
    final out = <String>[];
    for (var r = 0; r < _gridSize; r++) {
      for (var c = 0; c < _gridSize - 1; c++) {
        final k = _lineKey('h', r, c);
        if (!_lines.containsKey(k)) out.add(k);
      }
    }
    for (var r = 0; r < _gridSize - 1; r++) {
      for (var c = 0; c < _gridSize; c++) {
        final k = _lineKey('v', r, c);
        if (!_lines.containsKey(k)) out.add(k);
      }
    }
    return out;
  }

  int _boxesCompletedBy(String lineKey) {
    _lines[lineKey] = 99;
    final before = _boxes.length;
    _checkNewBoxes(99);
    final after = _boxes.length;
    _lines.remove(lineKey);
    _boxes.removeWhere((k, v) => v == 99);
    return after - before;
  }

  bool _givesOpponentBox(String lineKey) {
    // Simulate drawing this line for self, then see if any single
    // opponent line completes a box.
    _lines[lineKey] = 1;
    final saved = Map<String, int>.from(_boxes);
    for (final l in _availableLines()) {
      _lines[l] = 2;
      final added = _checkNewBoxes(2);
      // Undo boxes & line
      _lines.remove(l);
      _boxes.clear();
      _boxes.addAll(saved);
      if (added > 0) {
        // undo self line
        _lines.remove(lineKey);
        _boxes.clear();
        _boxes.addAll(saved);
        return true;
      }
    }
    _lines.remove(lineKey);
    _boxes.clear();
    _boxes.addAll(saved);
    return false;
  }

  int _sacrificeChainSize(String lineKey) {
    // Draw the line, then have opponent greedily capture boxes until
    // they can't anymore — return total boxes they capture.
    _lines[lineKey] = 1;
    final savedLines = Map<String, int>.from(_lines);
    final savedBoxes = Map<String, int>.from(_boxes);
    var captured = 0;
    // Bot takes completing lines repeatedly.
    while (true) {
      String? nextLine;
      for (final l in _availableLines()) {
        _lines[l] = 2;
        final c = _checkNewBoxes(2);
        if (c > 0) {
          captured += c;
          nextLine = l;
          break;
        }
        _lines.remove(l);
      }
      if (nextLine == null) break;
    }
    // Restore.
    _lines.clear();
    _lines.addAll(savedLines);
    _boxes.clear();
    _boxes.addAll(savedBoxes);
    return captured;
  }

  String? _botPick() {
    final available = _availableLines();
    if (available.isEmpty) return null;
    if (_difficulty == _DBDifficulty.easy) {
      return available[Random().nextInt(available.length)];
    }
    // medium / hard share same first two stages; hard adds minimize-sacrifice
    // 1. Take completing boxes.
    for (final l in available) {
      if (_boxesCompletedBy(l) > 0) return l;
    }
    // 2. Avoid giving opponent boxes.
    final safe = <String>[];
    final unsafe = <String>[];
    for (final l in available) {
      if (_givesOpponentBox(l)) {
        unsafe.add(l);
      } else {
        safe.add(l);
      }
    }
    if (safe.isNotEmpty) return safe[Random().nextInt(safe.length)];
    if (_difficulty == _DBDifficulty.medium || unsafe.isEmpty) {
      return unsafe[Random().nextInt(unsafe.length)];
    }
    // hard: pick line with minimum sacrifice chain.
    String? best;
    var minGiven = 1 << 30;
    for (final l in unsafe) {
      final given = _sacrificeChainSize(l);
      if (given < minGiven) {
        minGiven = given;
        best = l;
      }
    }
    return best ?? unsafe[Random().nextInt(unsafe.length)];
  }

  void _onTap(Offset p, Rect grid) {
    if (_gameOver) return;
    if (_isAi && _currentPlayer == 2) return;
    final key = _lineAt(p, grid);
    if (key == null || _lines.containsKey(key)) return;
    _playLine(key, _currentPlayer);
  }

  void _playLine(String key, int player) {
    final boxes = _applyLine(key, player);
    if (player == 1) {
      _p1Count += boxes;
    } else {
      _p2Count += boxes;
    }
    haptic(boxes > 0 ? HapticFeedbackType.medium : HapticFeedbackType.light);
    final total = (_gridSize - 1) * (_gridSize - 1);
    if (_boxes.length >= total) {
      setState(() {
        _gameOver = true;
        _claimFlash = 24;
        _lastDrawnKey = key;
        _lastDrawnPlayer = player;
      });
      haptic(HapticFeedbackType.heavy);
      reportScore((_p1Count - _p2Count) * 50 + 200);
      _updateStats();
      reportGameOver();
      return;
    }
    setState(() {
      _claimFlash = boxes > 0 ? 18 : 0;
      _lastDrawnKey = key;
      _lastDrawnPlayer = player;
    });
    reportScore((_p1Count - _p2Count) * 50 + 200);
    _updateStats();
    if (boxes == 0) {
      _currentPlayer = _currentPlayer == 1 ? 2 : 1;
      if (_isAi && _currentPlayer == 2) {
        _scheduleBot();
      }
    } else {
      // Same player goes again.
      if (_isAi && _currentPlayer == 2) {
        _scheduleBot();
      }
    }
  }

  void _scheduleBot() {
    _botThinking = true;
    _botScheduledAt = DateTime.now().add(const Duration(milliseconds: 350));
  }

  void _maybeFireBot() {
    if (!_botThinking) return;
    if (_botScheduledAt == null) return;
    if (DateTime.now().isBefore(_botScheduledAt!)) return;
    _botThinking = false;
    _botScheduledAt = null;
    final pick = _botPick();
    if (pick != null) _playLine(pick, 2);
  }

  void _updateStats() {
    final total = (_gridSize - 1) * (_gridSize - 1);
    final claimed = _boxes.length;
    final turn = _gameOver
        ? 'Game over'
        : (_isAi && _currentPlayer == 2 ? 'Bot thinking…' : 'P$_currentPlayer');
    reportStats(
      'P1 $_p1Count · P2 $_p2Count · $claimed/$total · $turn',
    );
  }

  // ─── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _bg,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Top HUD removed — host GameContainerScreen provides it.
          const SizedBox(height: 12),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final size = c.biggest.shortestSide * 0.95;
                return Center(
                  child: SizedBox(
                    width: size,
                    height: size,
                    child: LayoutBuilder(
                      builder: (context, c2) {
                        final grid = Rect.fromLTWH(
                          0,
                          0,
                          c2.maxWidth,
                          c2.maxHeight,
                        );
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapDown: (d) => _onTap(d.localPosition, grid),
                          child: CustomPaint(
                            painter: _DBPainter(
                              gridSize: _gridSize,
                              lines: _lines,
                              boxes: _boxes,
                              dot: _dot,
                              p1: _p1,
                              p2: _p2,
                              text: _text,
                              threshold: _threshold.toDouble(),
                              currentPlayer: _currentPlayer,
                              claimFlash: _claimFlash,
                              lastDrawnKey: _lastDrawnKey,
                              lastDrawnPlayer: _lastDrawnPlayer,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          // Score row removed — host GameContainerScreen provides it.
        ],
      ),
    );
  }
}

class _DBPainter extends CustomPainter {
  _DBPainter({
    required this.gridSize,
    required this.lines,
    required this.boxes,
    required this.dot,
    required this.p1,
    required this.p2,
    required this.text,
    required this.threshold,
    required this.currentPlayer,
    required this.claimFlash,
    required this.lastDrawnKey,
    required this.lastDrawnPlayer,
  });

  final int gridSize;
  final Map<String, int> lines;
  final Map<String, int> boxes;
  final Color dot;
  final Color p1;
  final Color p2;
  final Color text;
  final double threshold;
  final int currentPlayer;
  final int claimFlash;
  final String? lastDrawnKey;
  final int lastDrawnPlayer;

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / (gridSize - 1);
    final cellH = size.height / (gridSize - 1);

    // Fill claimed boxes — brighter alpha so the player can see who
    // owns each box at a glance.
    final flashBoost = (claimFlash / 24.0).clamp(0.0, 1.0);
    for (var r = 0; r < gridSize - 1; r++) {
      for (var c = 0; c < gridSize - 1; c++) {
        final owner = boxes['$r-$c'];
        if (owner == null) continue;
        final color = owner == 1 ? p1 : p2;
        final rect = Rect.fromLTRB(
          c * cellW + 4,
          r * cellH + 4,
          (c + 1) * cellW - 4,
          (r + 1) * cellH - 4,
        );
        // Pulse the most-recent claim.
        final isFreshClaim = claimFlash > 0 && flashBoost > 0.4 &&
            _boxTouchesLine(r, c, lastDrawnKey);
        final baseAlpha = isFreshClaim ? 0.55 + 0.30 * flashBoost : 0.32;
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(4)),
          Paint()..color = color.withValues(alpha: baseAlpha),
        );
        if (isFreshClaim) {
          // Glow border on freshly-claimed box.
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(4)),
            Paint()
              ..color = color
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5,
          );
        }
        final tp = TextPainter(
          text: TextSpan(
            text: owner == 1 ? 'P1' : 'P2',
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(rect.center.dx - tp.width / 2, rect.center.dy - tp.height / 2),
        );
      }
    }

    // Draw lines.
    final baseStroke = (size.shortestSide / (gridSize * 6)).clamp(2.5, 5.5);
    for (final entry in lines.entries) {
      final key = entry.key;
      final owner = entry.value;
      if (owner == 99) continue;
      final parts = key.split('-');
      final type = parts[0];
      final r = int.parse(parts[1]);
      final c = int.parse(parts[2]);
      final color = owner == 1 ? p1 : p2;
      Offset a;
      Offset b;
      if (type == 'h') {
        a = Offset(c * cellW, r * cellH);
        b = Offset((c + 1) * cellW, r * cellH);
      } else {
        a = Offset(c * cellW, r * cellH);
        b = Offset(c * cellW, (r + 1) * cellH);
      }
      final isLastDrawn = key == lastDrawnKey;
      final paint = Paint()
        ..color = color
        ..strokeWidth =
            isLastDrawn ? baseStroke + 1.5 : baseStroke
        ..strokeCap = StrokeCap.round;
      if (isLastDrawn) {
        // Glow halo on the last-drawn line so the player sees their tap.
        canvas.drawLine(
          a,
          b,
          Paint()
            ..color = color.withValues(alpha: 0.55)
            ..strokeWidth = baseStroke + 6
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
      }
      canvas.drawLine(a, b, paint);
    }

    // Draw dots.
    final dotPaint = Paint()..color = dot;
    final dotRadius = baseStroke * 1.2;
    for (var r = 0; r < gridSize; r++) {
      for (var c = 0; c < gridSize; c++) {
        canvas.drawCircle(
          Offset(c * cellW, r * cellH),
          dotRadius,
          dotPaint,
        );
      }
    }
  }

  /// True if box (r, c) is touched by the most-recent line. Used to
  /// highlight a freshly-claimed box.
  bool _boxTouchesLine(int r, int c, String? key) {
    if (key == null) return false;
    final parts = key.split('-');
    final type = parts[0];
    final lr = int.parse(parts[1]);
    final lc = int.parse(parts[2]);
    if (type == 'h') {
      // Top or bottom edge of box (r, c).
      if (lr == r && lc == c) return true; // top
      if (lr == r + 1 && lc == c) return true; // bottom
    } else {
      if (lr == r && lc == c) return true; // left
      if (lr == r && lc == c + 1) return true; // right
    }
    return false;
  }

  @override
  bool shouldRepaint(_DBPainter old) =>
      old.lines != lines ||
      old.boxes != boxes ||
      old.currentPlayer != currentPlayer ||
      old.claimFlash != claimFlash ||
      old.lastDrawnKey != lastDrawnKey;
}
