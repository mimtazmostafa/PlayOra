import 'dart:math';

import 'package:flutter/material.dart';

import '../game_widgets.dart';
import '../mini_game.dart';

/// Battleship — ported from
/// `downloaded_games/games/battleship/game.py`.
///
/// 10×10 grids, classic 5-ship fleet (Carrier-5, Battleship-4,
/// Cruiser-3, Submarine-3, Destroyer-2). Place ships horizontally
/// or vertically, then take turns firing. Hits grant an extra turn.
/// First to sink all enemy ships wins.
///
/// Modes: 1P-vs-Bot or 2P Pass-and-Play (host-managed). AI bot uses
/// a "hunt then target" heuristic: random shots until a hit, then
/// line up along the hit direction.
class BattleshipGame extends MiniGame {
  const BattleshipGame({
    super.key,
    required super.callbacks,
    this.level = 1,
  });

  /// 1 = easy, 2 = medium, 3+ = hard (currently single AI mode).
  final int level;

  @override
  State<BattleshipGame> createState() => _BattleshipGameState();
}

enum _BSPhase { placeP1, placeP2, battle, transition }

class _BattleshipGameState extends MiniGameState<BattleshipGame> {
  static const int _gridW = 10;
  static const int _gridH = 10;

  static const List<List<String>> _shipDefs = [
    ['Carrier', '5'],
    ['Battleship', '4'],
    ['Cruiser', '3'],
    ['Submarine', '3'],
    ['Destroyer', '2'],
  ];

  // Boards: '~' = empty, 'S' = ship (hidden from opponent),
  // 'X' = hit, 'O' = miss
  late List<List<String>> _p1Board;
  late List<List<String>> _p2Board;
  late List<_BSShip> _p1Ships;
  late List<_BSShip> _p2Ships;
  // Shots: set of "r,c" strings
  final Set<String> _p1Shots = <String>{};
  final Set<String> _p2Shots = <String>{};

  _BSPhase _phase = _BSPhase.placeP1;
  int _plIdx = 0;
  bool _plHoriz = true;
  int _currentPlayer = 1; // 1 or 2
  bool _extraTurn = false;
  bool _gameOver = false;
  int _winner = 0;
  String _message = '';
  int _score1 = 0;
  int _score2 = 0;

  // Bot AI state
  final Random _rng = Random();
  final List<Point<int>> _botHits = [];
  final bool _isAi = true;

  static const Color _bg = Color(0xFF050E26);

  @override
  void initState() {
    super.initState();
    _initStateData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      reportScore(0);
      _updateStats();
    });
  }

  /// Synchronous game-data init — separated from [_fullReset] so the
  /// `initState` build phase never reaches the `reportScore` /
  /// `_updateStats` calls (those trigger setState on the host
  /// GameContainerScreen, which is illegal mid-build).
  void _initStateData() {
    _p1Board = List.generate(_gridH, (_) => List.filled(_gridW, '~'));
    _p2Board = List.generate(_gridH, (_) => List.filled(_gridW, '~'));
    _p1Ships = [];
    _p2Ships = [];
    _p1Shots.clear();
    _p2Shots.clear();
    _phase = _BSPhase.placeP1;
    _plIdx = 0;
    _plHoriz = true;
    _currentPlayer = 1;
    _extraTurn = false;
    _gameOver = false;
    _winner = 0;
    _score1 = 0;
    _score2 = 0;
    _botHits.clear();
    if (_isAi) {
      _autoPlaceAll(_p2Board, _p2Ships);
      _message = 'Place your ships, Captain';
    } else {
      _message = 'P1 — place your ships';
    }
  }

  /// Full reset (mid-game restart): same state shape as initState but
  /// also pushes the host callback updates.
  void _fullReset() {
    _initStateData();
    reportScore(0);
    _updateStats();
  }

  List<Point<int>> _shipCells(int r, int c, int length, bool horiz) {
    if (horiz) {
      return [for (var i = 0; i < length; i++) Point(r, c + i)];
    }
    return [for (var i = 0; i < length; i++) Point(r + i, c)];
  }

  bool _validPlacement(List<Point<int>> cells, List<_BSShip> ships,
      {int? exclude}) {
    final occupied = <String>{};
    for (var i = 0; i < ships.length; i++) {
      if (i == exclude) continue;
      for (final cell in ships[i].cells) {
        occupied.add('${cell.x},${cell.y}');
      }
    }
    for (final p in cells) {
      if (p.x < 0 || p.x >= _gridH || p.y < 0 || p.y >= _gridW) return false;
      if (occupied.contains('${p.x},${p.y}')) return false;
    }
    return true;
  }

  void _autoPlaceAll(List<List<String>> board, List<_BSShip> ships) {
    for (final def in _shipDefs) {
      final name = def[0];
      final length = int.parse(def[1]);
      while (true) {
        final horiz = _rng.nextBool();
        final r = _rng.nextInt(_gridH);
        final c = _rng.nextInt(_gridW);
        final cells = _shipCells(r, c, length, horiz);
        if (_validPlacement(cells, ships)) {
          for (final p in cells) {
            board[p.x][p.y] = 'S';
          }
          ships.add(_BSShip(name: name, cells: cells, horiz: horiz));
          break;
        }
      }
    }
  }

  void _handleTap(Offset pos, Size size) {
    if (_phase == _BSPhase.transition) {
      _advanceFromTransition();
      return;
    }
    if (_gameOver) {
      _fullReset();
      return;
    }
    if (_phase == _BSPhase.placeP1 || _phase == _BSPhase.placeP2) {
      // Place ship on tap (or rotate via right-side button / long press)
      final origin = _boardOrigin(_phase == _BSPhase.placeP1 ? 1 : 2);
      final cellSize = _boardCellSize(size);
      final originOffset = _boardOffset(size);
      final bx = originOffset.dx + origin * (_gridW * cellSize + 80);
      final by = originOffset.dy;
      final local = pos - Offset(bx, by);
      final c = (local.dx / cellSize).floor();
      final r = (local.dy / cellSize).floor();
      if (r < 0 || r >= _gridH || c < 0 || c >= _gridW) return;
      if (_plIdx >= _shipDefs.length) {
        // Confirm placement
        if (_phase == _BSPhase.placeP1) {
          if (_isAi) {
            // In single-player AI mode, P2 ships are pre-placed by
            // _fullReset(); skip straight into battle so the player
            // isn't asked to lay down two fleets in a row.
            setState(() {
              _phase = _BSPhase.battle;
              _currentPlayer = 1;
            });
            _message = 'Battle! You shoot first';
          } else {
            setState(() {
              _phase = _BSPhase.placeP2;
              _plIdx = 0;
              _plHoriz = true;
            });
            _message = 'P2 — place your ships';
          }
        } else {
          setState(() => _phase = _BSPhase.battle);
          _message = 'Battle! P1 shoots first';
          _currentPlayer = 1;
        }
        return;
      }
      final length = int.parse(_shipDefs[_plIdx][1]);
      final cells = _shipCells(r, c, length, _plHoriz);
      final ships = _phase == _BSPhase.placeP1 ? _p1Ships : _p2Ships;
      final board = _phase == _BSPhase.placeP1 ? _p1Board : _p2Board;
      if (_validPlacement(cells, ships)) {
        setState(() {
          for (final p in cells) {
            board[p.x][p.y] = 'S';
          }
          ships.add(_BSShip(
              name: _shipDefs[_plIdx][0], cells: cells, horiz: _plHoriz));
          _plIdx++;
          _message = _plIdx < _shipDefs.length
              ? 'Place ${_shipDefs[_plIdx][0]} (${_shipDefs[_plIdx][1]})'
              : 'Tap to confirm layout';
        });
        haptic(HapticFeedbackType.selection);
      } else {
        haptic(HapticFeedbackType.heavy);
      }
    } else if (_phase == _BSPhase.battle) {
      final cellSize = _boardCellSize(size);
      final originOffset = _boardOffset(size);
      final boardIdx = _currentPlayer == 1 ? 2 : 1;
      final bx = originOffset.dx + (boardIdx == 1 ? 0 : _gridW * cellSize + 80);
      final by = originOffset.dy;
      final local = pos - Offset(bx, by);
      final c = (local.dx / cellSize).floor();
      final r = (local.dy / cellSize).floor();
      if (r < 0 || r >= _gridH || c < 0 || c >= _gridW) return;
      _shoot(r, c, _currentPlayer);
    }
  }

  void _advanceFromTransition() {
    setState(() {
      _phase = _BSPhase.battle;
    });
    if (_isAi && _currentPlayer == 2) {
      // Schedule bot shot.
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted || _gameOver) return;
        _botTakeShot();
      });
    }
  }

  void _shoot(int r, int c, int shooter) {
    final key = '$r,$c';
    if (shooter == 1) {
      if (_p1Shots.contains(key)) return;
      _p1Shots.add(key);
      if (_p2Board[r][c] == 'S') {
        _p2Board[r][c] = 'X';
        _extraTurn = true;
        final sunk = _isShipSunk(_p2Ships, _p2Board);
        if (sunk != null) {
          _message = '${sunk.name} sunk!';
        } else {
          _message = 'P1 — HIT!';
        }
        haptic(HapticFeedbackType.heavy);
        _score1 += 10;
        if (_allShipsSunk(_p2Board)) {
          _gameOver = true;
          _winner = 1;
          _message = 'P1 wins!';
        }
      } else {
        _p2Board[r][c] = 'O';
        _extraTurn = false;
        _message = 'P1 — Miss';
        haptic(HapticFeedbackType.medium);
      }
    } else {
      if (_p2Shots.contains(key)) return;
      _p2Shots.add(key);
      if (_p1Board[r][c] == 'S') {
        _p1Board[r][c] = 'X';
        _extraTurn = true;
        final sunk = _isShipSunk(_p1Ships, _p1Board);
        if (sunk != null) {
          _message = _isAi ? '${sunk.name} sunk!' : '${sunk.name} sunk!';
        } else {
          _message = _isAi ? 'Bot — HIT!' : 'P2 — HIT!';
        }
        haptic(HapticFeedbackType.heavy);
        _score2 += 10;
        if (_allShipsSunk(_p1Board)) {
          _gameOver = true;
          _winner = 2;
          _message = _isAi ? 'Bot wins!' : 'P2 wins!';
        }
      } else {
        _p1Board[r][c] = 'O';
        _extraTurn = false;
        _message = _isAi ? 'Bot — Miss' : 'P2 — Miss';
        haptic(HapticFeedbackType.medium);
      }
    }
    if (_gameOver) {
      reportScore((_score1 + _score2) * 10 + (_winner == 1 ? 200 : 0));
      haptic(HapticFeedbackType.heavy);
      reportGameOver();
    } else {
      reportScore((_score1 + _score2) * 10);
    }
    _updateStats();
    setState(() {});
    if (!_gameOver && !_extraTurn) {
      _currentPlayer = _currentPlayer == 1 ? 2 : 1;
      if (_isAi && _currentPlayer == 2) {
        Future.delayed(const Duration(milliseconds: 700), () {
          if (!mounted || _gameOver) return;
          _botTakeShot();
        });
      }
    }
  }

  _BSShip? _isShipSunk(List<_BSShip> ships, List<List<String>> board) {
    for (final ship in ships) {
      if (ship.cells.every((p) => board[p.x][p.y] == 'X')) {
        return ship;
      }
    }
    return null;
  }

  bool _allShipsSunk(List<List<String>> board) {
    for (var r = 0; r < _gridH; r++) {
      for (var c = 0; c < _gridW; c++) {
        if (board[r][c] == 'S') return false;
      }
    }
    return true;
  }

  void _botTakeShot() {
    if (_gameOver) return;
    Point<int>? target;
    if (_botHits.isNotEmpty) {
      // Try to extend a hit line.
      target = _botFindTargetingShot();
    }
    target ??= _botFindHuntShot();
    if (target == null) {
      _gameOver = true;
      _winner = 1;
      _message = 'P1 wins!';
      _updateStats();
      reportGameOver();
      return;
    }
    _shoot(target.x, target.y, 2);
  }

  Point<int>? _botFindTargetingShot() {
    if (_botHits.length == 1) {
      final h = _botHits.first;
      // Try each direction.
      final candidates = <Point<int>>[
        Point(h.x, h.y + 1),
        Point(h.x + 1, h.y),
        Point(h.x, h.y - 1),
        Point(h.x - 1, h.y),
      ];
      for (final c in candidates) {
        if (_validShot(c)) return c;
      }
    }
    if (_botHits.length >= 2) {
      // Try to extend along the line.
      final a = _botHits.first;
      final b = _botHits[1];
      int dr = 0, dc = 0;
      if (a.x == b.x) {
        dc = b.y > a.y ? 1 : -1;
      } else {
        dr = b.x > a.x ? 1 : -1;
      }
      // Try extending from both ends.
      final last = _botHits.last;
      final next = Point(last.x + dr, last.y + dc);
      if (_validShot(next)) return next;
      final first = _botHits.first;
      final prev = Point(first.x - dr, first.y - dc);
      if (_validShot(prev)) return prev;
    }
    return null;
  }

  Point<int>? _botFindHuntShot() {
    // Random unshot cell, with checkerboard bias.
    for (var tries = 0; tries < 200; tries++) {
      final r = _rng.nextInt(_gridH);
      final c = _rng.nextInt(_gridW);
      final p = Point(r, c);
      if ((r + c) % 2 != 0 && tries < 100) continue;
      if (_validShot(p)) return p;
    }
    return null;
  }

  bool _validShot(Point<int> p) {
    if (p.x < 0 || p.x >= _gridH || p.y < 0 || p.y >= _gridW) return false;
    final key = '${p.x},${p.y}';
    if (_p2Shots.contains(key)) return false;
    return true;
  }

  int _boardOrigin(int player) => player == 1 ? 0 : 1;

  double _boardCellSize(Size size) {
    final available = size.height - 100;
    return (available / _gridH).clamp(20.0, 40.0);
  }

  Offset _boardOffset(Size size) {
    return Offset(8, 60);
  }

  void _updateStats() {
    String turn;
    if (_phase == _BSPhase.placeP1 || _phase == _BSPhase.placeP2) {
      turn = 'Place ships';
    } else if (_gameOver) {
      turn = 'Game over';
    } else if (_phase == _BSPhase.battle) {
      turn = _currentPlayer == 1 ? 'P1 turn' : (_isAi ? 'Bot turn' : 'P2 turn');
    } else {
      turn = _message;
    }
    reportStats('$_score1 · $_score2 · $turn');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _bg,
      child: SafeArea(
        child: Column(
          children: [
            // Top HUD removed — host GameContainerScreen provides it.
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) {
                  final size = Size(c.maxWidth, c.maxHeight);
                  final cellSize = _boardCellSize(size);
                  final boardW = cellSize * _gridW;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) => _handleTap(d.localPosition, size),
                    onLongPress: () {
                      if (_phase == _BSPhase.placeP1 ||
                          _phase == _BSPhase.placeP2) {
                        setState(() => _plHoriz = !_plHoriz);
                      }
                    },
                    child: CustomPaint(
                      size: size,
                      painter: _BSBoardPainter(
                        phase: _phase,
                        cellSize: cellSize,
                        boardW: boardW,
                        p1Board: _p1Board,
                        p2Board: _p2Board,
                        p1Ships: _p1Ships,
                        p2Ships: _p2Ships,
                        p1Shots: _p1Shots,
                        p2Shots: _p2Shots,
                        plIdx: _plIdx,
                        plHoriz: _plHoriz,
                        shipDefs: _shipDefs,
                        currentPlayer: _currentPlayer,
                        showShips:
                            _phase == _BSPhase.placeP1 ? _p1Ships : _p2Ships,
                        message: _message,
                        gameOver: _gameOver,
                        winner: _winner,
                        isAi: _isAi,
                      ),
                    ),
                  );
                },
              ),
            ),
            _buildControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: const Color(0xFF06060F),
      child: Row(
        children: [
          if (_phase == _BSPhase.placeP1 || _phase == _BSPhase.placeP2)
            TextButton.icon(
              onPressed: () {
                // Auto-place for current player.
                setState(() {
                  final board = _phase == _BSPhase.placeP1 ? _p1Board : _p2Board;
                  final ships = _phase == _BSPhase.placeP1 ? _p1Ships : _p2Ships;
                  for (final s in ships) {
                    for (final c in s.cells) {
                      board[c.x][c.y] = '~';
                    }
                  }
                  ships.clear();
                  _autoPlaceAll(board, ships);
                  _plIdx = _shipDefs.length;
                  _message = 'Tap to confirm layout';
                });
              },
              icon: const Icon(Icons.auto_awesome, color: Colors.white70),
              label: const Text(
                'Auto',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          if (_phase == _BSPhase.placeP1 || _phase == _BSPhase.placeP2)
            TextButton.icon(
              onPressed: () => setState(() => _plHoriz = !_plHoriz),
              icon: Transform.rotate(
                angle: _plHoriz ? 0 : 1.5708,
                child: const Icon(Icons.swap_horiz, color: Colors.white70),
              ),
              label: Text(
                _plHoriz ? 'Horizontal' : 'Vertical',
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          const Spacer(),
          IconButton(
            onPressed: _fullReset,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _BSShip {
  _BSShip({required this.name, required this.cells, required this.horiz});
  String name;
  List<Point<int>> cells;
  bool horiz;
}

class _BSBoardPainter extends CustomPainter {
  _BSBoardPainter({
    required this.phase,
    required this.cellSize,
    required this.boardW,
    required this.p1Board,
    required this.p2Board,
    required this.p1Ships,
    required this.p2Ships,
    required this.p1Shots,
    required this.p2Shots,
    required this.plIdx,
    required this.plHoriz,
    required this.shipDefs,
    required this.currentPlayer,
    required this.showShips,
    required this.message,
    required this.gameOver,
    required this.winner,
    required this.isAi,
  });

  final _BSPhase phase;
  final double cellSize;
  final double boardW;
  final List<List<String>> p1Board;
  final List<List<String>> p2Board;
  final List<_BSShip> p1Ships;
  final List<_BSShip> p2Ships;
  final Set<String> p1Shots;
  final Set<String> p2Shots;
  final int plIdx;
  final bool plHoriz;
  final List<List<String>> shipDefs;
  final int currentPlayer;
  final List<_BSShip> showShips;
  final String message;
  final bool gameOver;
  final int winner;
  final bool isAi;

  void _drawGrid(Canvas canvas, double ox, double oy, List<List<String>> board,
      Set<String> shots, bool revealShips, List<_BSShip>? ships) {
    // Ocean background.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(ox - 4, oy - 4, boardW + 8, boardW + 8),
        const Radius.circular(8),
      ),
      Paint()..color = const Color(0xFF08265F),
    );
    for (var r = 0; r < 10; r++) {
      for (var c = 0; c < 10; c++) {
        final rx = ox + c * cellSize;
        final ry = oy + r * cellSize;
        final cell = Rect.fromLTWH(rx + 1, ry + 1, cellSize - 2, cellSize - 2);
        final val = board[r][c];
        if (val == 'X') {
          canvas.drawRect(
            cell,
            Paint()..color = const Color(0xFFFF4B19),
          );
          canvas.drawCircle(
            Offset(rx + cellSize / 2, ry + cellSize / 2),
            4,
            Paint()..color = const Color(0xFFFFA000),
          );
        } else if (val == 'O') {
          canvas.drawRect(
            cell,
            Paint()..color = const Color(0xFF0A326E),
          );
          canvas.drawCircle(
            Offset(rx + cellSize / 2, ry + cellSize / 2),
            cellSize * 0.16,
            Paint()..color = const Color(0xFF469BDC),
          );
        } else {
          canvas.drawRect(
            cell,
            Paint()..color = (r + c).isEven
                ? const Color(0xFF082858)
                : const Color(0xFF08265F),
          );
        }
        canvas.drawRect(
          cell,
          Paint()
            ..color = const Color(0xFF194696)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
    }
    // Draw ships if reveal.
    if (revealShips && ships != null) {
      for (final ship in ships) {
        _drawShip(canvas, ship, ox, oy);
      }
    }
    // Column / row labels.
    for (var c = 0; c < 10; c++) {
      final tp = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(65 + c),
          style: const TextStyle(
            color: Color(0xFF3C82C8),
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(ox + c * cellSize + cellSize / 2 - tp.width / 2, oy - 14));
    }
    for (var r = 0; r < 10; r++) {
      final tp = TextPainter(
        text: TextSpan(
          text: '${r + 1}',
          style: const TextStyle(
            color: Color(0xFF3C82C8),
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(ox - 14, oy + r * cellSize + cellSize / 2 - tp.height / 2));
    }
  }

  void _drawShip(Canvas canvas, _BSShip ship, double ox, double oy) {
    final cells = ship.cells;
    final minR = cells.map((p) => p.x).reduce(min);
    final maxR = cells.map((p) => p.x).reduce(max);
    final minC = cells.map((p) => p.y).reduce(min);
    final maxC = cells.map((p) => p.y).reduce(max);
    final x1 = ox + minC * cellSize + 2;
    final y1 = oy + minR * cellSize + 2;
    final x2 = ox + (maxC + 1) * cellSize - 2;
    final y2 = oy + (maxR + 1) * cellSize - 2;
    final sw = x2 - x1;
    final sh = y2 - y1;
    final rect = Rect.fromLTWH(x1, y1, sw, sh);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()..color = const Color(0xFF466069),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    // Deck
    final deckRect = ship.horiz
        ? Rect.fromLTWH(x1 + 4, y1 + sh / 4, sw - 8, sh / 2)
        : Rect.fromLTWH(x1 + sw / 4, y1 + 4, sw / 2, sh - 8);
    canvas.drawRRect(
      RRect.fromRectAndRadius(deckRect, const Radius.circular(2)),
      Paint()..color = const Color(0xFF374B5A),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final ox0 = 16.0;
    final oy = 50.0;
    final gap = 60.0;
    if (phase == _BSPhase.placeP1 || phase == _BSPhase.placeP2) {
      // Single board for placement.
      _drawGrid(canvas, ox0, oy, phase == _BSPhase.placeP1 ? p1Board : p2Board,
          <String>{}, true, showShips);
      // Ship list panel on right
      final panelX = ox0 + boardW + gap;
      for (var idx = 0; idx < shipDefs.length; idx++) {
        final done = idx < plIdx;
        final cur = idx == plIdx;
        Color col = const Color(0xFF505064);
        if (done) col = const Color(0xFF00FF64);
        if (cur) col = const Color(0xFF00DCFF);
        final tp = TextPainter(
          text: TextSpan(
            text: '${done ? "✓ " : (cur ? "► " : "  ")}${shipDefs[idx][0]} (${shipDefs[idx][1]})',
            style: TextStyle(
              color: col,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(panelX, oy + idx * 26));
      }
      // Hint
      final hint = TextPainter(
        text: TextSpan(
          text: plIdx >= shipDefs.length
              ? 'Tap board to confirm layout'
              : 'Tap to place  •  Long-press to rotate  •  Auto button for random',
          style: const TextStyle(
            color: Color(0xFF5A6E8C),
            fontSize: 11,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      hint.paint(canvas, Offset(ox0, oy + boardW + 12));
    } else {
      // Two boards side-by-side.
      _drawGrid(canvas, ox0, oy, p1Board, p2Shots, gameOver, gameOver ? p1Ships : null);
      _drawGrid(canvas, ox0 + boardW + gap, oy, p2Board, p1Shots, gameOver,
          gameOver ? p2Ships : null);
      // Player name labels.
      final p1Tp = TextPainter(
        text: TextSpan(
          text: 'P1',
          style: TextStyle(
            color: const Color(0xFF00DCFF),
            fontSize: 14,
            fontWeight: FontWeight.w900,
            backgroundColor:
                currentPlayer == 1 ? const Color(0xFF0A1F50) : null,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      p1Tp.paint(canvas, Offset(ox0 + boardW / 2 - p1Tp.width / 2, oy - 24));
      final p2Tp = TextPainter(
        text: TextSpan(
          text: isAi ? 'Bot' : 'P2',
          style: TextStyle(
            color: isAi ? Colors.white : const Color(0xFFFFC800),
            fontSize: 14,
            fontWeight: FontWeight.w900,
            backgroundColor:
                currentPlayer == 2 ? const Color(0xFF0A1F50) : null,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      p2Tp.paint(canvas,
          Offset(ox0 + boardW + gap + boardW / 2 - p2Tp.width / 2, oy - 24));

      if (gameOver) {
        canvas.drawRect(
          Offset.zero & size,
          Paint()..color = Colors.black.withValues(alpha: 0.55),
        );
        final winText = winner == 1
            ? 'P1 wins!'
            : (isAi ? 'Bot wins!' : 'P2 wins!');
        final color = winner == 1
            ? const Color(0xFF00DCFF)
            : (isAi ? Colors.white : const Color(0xFFFFC800));
        final tp = TextPainter(
          text: TextSpan(
            text: winText,
            style: TextStyle(
              color: color,
              fontSize: 32,
              fontWeight: FontWeight.w900,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas,
            Offset(size.width / 2 - tp.width / 2, size.height / 2 - 30));
      }
    }
  }

  @override
  bool shouldRepaint(_BSBoardPainter old) =>
      old.phase != phase ||
      old.cellSize != cellSize ||
      old.boardW != boardW ||
      old.plIdx != plIdx ||
      old.plHoriz != plHoriz ||
      old.currentPlayer != currentPlayer ||
      old.message != message ||
      old.gameOver != gameOver ||
      old.winner != winner ||
      old.isAi != isAi ||
      !identical(old.p1Board, p1Board) ||
      !identical(old.p2Board, p2Board) ||
      !identical(old.p1Shots, p1Shots) ||
      !identical(old.p2Shots, p2Shots) ||
      !identical(old.p1Ships, p1Ships) ||
      !identical(old.p2Ships, p2Ships) ||
      !identical(old.showShips, showShips);
}
