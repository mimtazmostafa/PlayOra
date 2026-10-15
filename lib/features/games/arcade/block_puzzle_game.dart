import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../game_widgets.dart';
import '../mini_game.dart';

/// 8x8 Block Puzzle — drag tetromino pieces onto the grid. Complete
/// rows or columns to clear them with combo bonuses.
///
/// Implementation notes:
///   * The grid is a flat `List<int?>` (null = empty, int = color id).
///   * A tray of 3 random pieces sits below the grid. The player
///     drags a piece into the grid using a long-press drag system.
///   * Clearing a row + column combo is rewarded with a multiplier.
class BlockPuzzleGame extends MiniGame {
  const BlockPuzzleGame({super.key, required super.callbacks});

  @override
  State<BlockPuzzleGame> createState() => _BlockPuzzleGameState();
}

class _BlockPuzzleGameState extends MiniGameState<BlockPuzzleGame>
    with TickerProviderStateMixin {
  static const int _size = 8;
  static const List<Color> _palette = [
    Color(0xFF22C55E),  // neon green (I)
    Color(0xFFFB923C),  // orange (L)
    Color(0xFFA855F7),  // purple (T)
    Color(0xFF38BDF8),  // cyan (J)
    Color(0xFFFACC15),  // bright yellow (S/O)
    Color(0xFFEC4899),  // magenta (Z)
  ];

  // Tracked as `mutable` arrays so we can update in-place without
  // rebuilding the entire list every frame.
  late List<int?> _grid;
  late List<_Piece> _tray;

  // Drag state.
  Offset? _dragPos;
  _Piece? _draggingPiece;
  Size _gridPixelSize = Size.zero;
  final GlobalKey _gridKey = GlobalKey();

  int _score = 0;
  int _combo = 0;
  int _filled = 0;
  int _level = 1;
  bool _flashing = false;
  // Where the dragging piece would land (origin row/col) — drives the
  // placement highlight glow.
  int? _hoverRow;
  int? _hoverCol;
  // Active line-clear floaters + particle bursts.
  final List<_ComboFloater> _floaters = [];
  final List<_LineParticle> _particles = [];
  // Hearts.
  int _hearts = 3;
  double _heartsPulse = 0;
  // Pause + tutorial.
  final bool _paused = false;
  bool _showTutorial = true;
  bool _tutorialDismissed = false;
  double _tutorialElapsed = 0;
  double _idleTime = 0;
  // BG sparkles.
  final List<_BgSparkle> _bck = [];
  final Random _rng = Random();

  late final AnimationController _flashCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  // Drives floater + particle integration at 60 FPS.
  late final Ticker _ticker;
  DateTime _last = DateTime.now();

  @override
  void initState() {
    super.initState();
    _grid = List<int?>.filled(_size * _size, null);
    _tray = _spawnTray();
    _flashCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    _spawnBgSparkles(28);
    _last = DateTime.now();
    _ticker = createTicker(_onTick)..start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reportScore(_score);
      reportStats('Lv $_level  •  $_filled/64');
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _flashCtrl.dispose();
    super.dispose();
  }

  void _spawnBgSparkles(int n) {
    for (var i = 0; i < n; i++) {
      _bck.add(_BgSparkle(
        x: _rng.nextDouble(),
        y: _rng.nextDouble(),
        r: 1.4 + _rng.nextDouble() * 2.6,
        life: 0.4 + _rng.nextDouble() * 1.0,
        phase: _rng.nextDouble() * 6.28,
      ));
    }
  }

  void _dismissTutorial() {
    if (!_tutorialDismissed) {
      _tutorialDismissed = true;
      _showTutorial = false;
    }
  }

  void _onTick(Duration _) {
    if (!mounted) return;
    final now = DateTime.now();
    var dt = now.difference(_last).inMicroseconds / 1e6;
    _last = now;
    if (dt > 0.05) dt = 0.05;
    if (_paused) return;
    _idleTime += dt;
    _tutorialElapsed += dt;
    if (_showTutorial && !_tutorialDismissed && _tutorialElapsed >= 6.0) {
      _showTutorial = false;
    }
    var changed = false;
    if (_heartsPulse > 0) {
      _heartsPulse = max(0, _heartsPulse - dt * 2.0);
      changed = true;
    }
    for (final b in _bck) {
      b.life -= dt * 0.5;
    }
    _bck.removeWhere((b) => b.life <= 0);
    if (_floaters.isNotEmpty) {
      for (final f in _floaters) {
        f.t += dt / 1.0;
      }
      _floaters.removeWhere((f) {
        if (f.t >= 1) {
          changed = true;
          return true;
        }
        return false;
      });
    }
    if (_particles.isNotEmpty) {
      for (final p in _particles) {
        p.life -= dt;
        p.x += p.vx * dt;
        p.y += p.vy * dt;
        p.vy += 220 * dt; // gravity
      }
      _particles.removeWhere((p) {
        if (p.life <= 0) {
          changed = true;
          return true;
        }
        return false;
      });
    }
    if (changed && mounted) setState(() {});
  }

  // ───────── Game logic ─────────

  List<_Piece> _spawnTray() {
    final rng = Random();
    return List.generate(3, (_) {
      return _Piece.shapes[rng.nextInt(_Piece.shapes.length)];
    });
  }

  bool _tryPlace(_Piece piece, int originRow, int originCol) {
    _dismissTutorial();
    // Bounds + collision check.
    for (final cell in piece.cells) {
      final r = originRow + cell.dr;
      final c = originCol + cell.dc;
      if (r < 0 || r >= _size || c < 0 || c >= _size) return false;
      if (_grid[r * _size + c] != null) return false;
    }
    for (final cell in piece.cells) {
      final r = originRow + cell.dr;
      final c = originCol + cell.dc;
      _grid[r * _size + c] = piece.colorId;
    }
    HapticFeedback.lightImpact();
    haptic(HapticFeedbackType.light);
    _score += piece.cells.length * 10;
    _filled += piece.cells.length;
    _clearLines();

    // Replace used piece; if the tray is empty, refill.
    final idx = _tray.indexOf(piece);
    if (idx >= 0) {
      final newTray = List.of(_tray)..[idx] = _Piece.empty;
      if (newTray.every((p) => p.isEmpty)) {
        _tray = _spawnTray();
      } else {
        _tray = newTray;
      }
    }
    reportScore(_score);
    reportStats('Lv $_level  •  $_filled/64');
    if (!_canPlaceAnyPiece()) {
      _score += _combo * 50;
      _hearts = max(0, _hearts - 1);
      _heartsPulse = 1.0;
      reportScore(_score);
      HapticFeedback.heavyImpact();
      haptic(HapticFeedbackType.medium);
      reportGameOver();
    }
    return true;
  }

  void _clearLines() {
    final fullRows = <int>[];
    for (var r = 0; r < _size; r++) {
      bool full = true;
      for (var c = 0; c < _size; c++) {
        if (_grid[r * _size + c] == null) {
          full = false;
          break;
        }
      }
      if (full) fullRows.add(r);
    }
    final fullCols = <int>[];
    for (var c = 0; c < _size; c++) {
      bool full = true;
      for (var r = 0; r < _size; r++) {
        if (_grid[r * _size + c] == null) {
          full = false;
          break;
        }
      }
      if (full) fullCols.add(c);
    }
    if (fullRows.isEmpty && fullCols.isEmpty) {
      _combo = 0;
      return;
    }
    _combo += 1;
    final cleared = fullRows.length + fullCols.length;
    _score += cleared * 100 * _combo;
    // Combo multiplier: 1x → 1x, 2x → 1.5x, 3x → 2x.
    final mult = _combo == 1 ? 1.0 : (_combo == 2 ? 1.5 : 2.0);
    final bonus = (cleared * 100 * mult).round();
    final earned = cleared * 100 * _combo;
    if (bonus != earned) {
      _score += (bonus - earned); // adjust for multiplier
    }
    // Snapshot cleared cells for particle spawning before wiping.
    final clearedCells = <_PCell>[];
    for (final r in fullRows) {
      for (var c = 0; c < _size; c++) {
        clearedCells.add(_PCell(r, c));
      }
    }
    for (final c in fullCols) {
      for (var r = 0; r < _size; r++) {
        clearedCells.add(_PCell(r, c));
      }
    }
    // Spawn particles (8 per cleared cell, color = that cell's palette).
    final rng = Random();
    for (final cc in clearedCells) {
      final id = _grid[cc.dr * _size + cc.dc];
      if (id == null || id < 0 || id >= _palette.length) continue;
      final color = _palette[id];
      final origin = Offset(
        cc.dc * _gridPixelSize.width / _size + _gridPixelSize.width / _size / 2,
        cc.dr * _gridPixelSize.height / _size + _gridPixelSize.height / _size / 2,
      );
      for (var i = 0; i < 8; i++) {
        final angle = rng.nextDouble() * 2 * pi;
        final speed = 60 + rng.nextDouble() * 80;
        _particles.add(_LineParticle(
          x: origin.dx,
          y: origin.dy,
          vx: cos(angle) * speed,
          vy: sin(angle) * speed - 40,
          color: color,
          life: 0.4 + rng.nextDouble() * 0.18,
          maxLife: 0.5,
          size: 2 + rng.nextDouble() * 2,
        ));
      }
    }
    for (final r in fullRows) {
      for (var c = 0; c < _size; c++) {
        _grid[r * _size + c] = null;
      }
    }
    for (final c in fullCols) {
      for (var r = 0; r < _size; r++) {
        _grid[r * _size + c] = null;
      }
    }
    // Spawn combo floater at the centroid of cleared cells.
    if (clearedCells.isNotEmpty) {
      var sumR = 0, sumC = 0;
      for (final cc in clearedCells) {
        sumR += cc.dr;
        sumC += cc.dc;
      }
      final cx = (sumC / clearedCells.length + 0.5) *
          _gridPixelSize.width /
          _size;
      final cy = (sumR / clearedCells.length + 0.5) *
          _gridPixelSize.height /
          _size;
      // Combo banner text per spec.
      final bannerText = _combo >= 3
          ? 'FANTASTIC! +$bonus'
          : _combo == 2
              ? 'COMBO x2! +$bonus'
              : 'BLOCK CLEAR! +$bonus';
      _floaters.add(_ComboFloater(
        text: bannerText,
        x: cx,
        y: cy,
        t: 0,
        color: _combo >= 3
            ? const Color(0xFFEC4899)
            : (_combo == 2 ? const Color(0xFFFACC15) : const Color(0xFF22D3EE)),
      ));
    }
    // Stage progression: every 5 placements, level up.
    final placements = _filled ~/ 8;
    if (placements > 0 && placements % 5 == 0) {
      _level += 1;
      _floaters.add(_ComboFloater(
        text: 'LEVEL $_level!',
        x: _gridPixelSize.width / 2,
        y: _gridPixelSize.height / 2 - 40,
        t: 0,
        color: const Color(0xFFA855F7),
      ));
      HapticFeedback.heavyImpact();
    }
    HapticFeedback.mediumImpact();
    haptic(HapticFeedbackType.medium);
    _flashing = true;
    _flashCtrl.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      setState(() => _flashing = false);
    });
  }

  bool _canPlaceAnyPiece() {
    for (final piece in _tray) {
      if (piece.isEmpty) continue;
      for (var r = 0; r < _size; r++) {
        for (var c = 0; c < _size; c++) {
          bool ok = true;
          for (final cell in piece.cells) {
            final rr = r + cell.dr;
            final cc = c + cell.dc;
            if (rr < 0 ||
                rr >= _size ||
                cc < 0 ||
                cc >= _size ||
                _grid[rr * _size + cc] != null) {
              ok = false;
              break;
            }
          }
          if (ok) return true;
        }
      }
    }
    return false;
  }

  // ───────── Build ─────────

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1B0F3A),
      child: Stack(
        children: [
          // Background.
          Positioned.fill(
            child: CustomPaint(
              painter: _BlockBgPainter(bck: _bck, idleTime: _idleTime),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Top HUD removed — host GameContainerScreen provides it.
                const SizedBox(height: 12),
                // Grid + drag overlay.
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final cell = (c.maxWidth / _size).clamp(20.0, 60.0);
                      final gridSize = cell * _size;
                      _gridPixelSize = Size(gridSize, gridSize);
                      return Center(
                        child: SizedBox(
                          key: _gridKey,
                          width: gridSize,
                          height: gridSize,
                          child: CustomPaint(
                            painter: _BlockGridPainter(
                              grid: _grid,
                              flash: _flashCtrl.value,
                              flashing: _flashing,
                              palette: _palette,
                              cell: cell,
                              hoverRow: _hoverRow,
                              hoverCol: _hoverCol,
                              hoverPiece: _draggingPiece,
                              particles: _particles,
                              floaters: _floaters,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                // Tray.
                Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF000000).withValues(alpha: 0.14),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (final piece in _tray)
                        Expanded(
                          child: piece.isEmpty
                              ? const SizedBox(height: 56)
                              : _PieceWidget(
                                  piece: piece,
                                  palette: _palette,
                                  onDragStart: () {
                                    setState(() {
                                      _draggingPiece = piece;
                                      _dragPos = null;
                                      _hoverRow = null;
                                      _hoverCol = null;
                                    });
                                  },
                                  onDragUpdate: (pos) {
                                    final hr = _hoverFromPos(pos);
                                    setState(() {
                                      _dragPos = pos;
                                      _hoverRow = hr?.$1;
                                      _hoverCol = hr?.$2;
                                    });
                                  },
                                  onDragEnd: () {
                                    if (_draggingPiece != null && _dragPos != null) {
                                      _resolveDrop(_draggingPiece!, _dragPos!);
                                    }
                                    setState(() {
                                      _draggingPiece = null;
                                      _dragPos = null;
                                      _hoverRow = null;
                                      _hoverCol = null;
                                    });
                                  },
                                ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Floating drag preview — overlays the entire screen so the
          // ghost follows the finger across tray + grid + chrome.
          if (_draggingPiece != null && _dragPos != null)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _DragGhostPainter(
                    piece: _draggingPiece!,
                    color: _palette[_draggingPiece!.colorId],
                    pos: _dragPos!,
                    cell: _gridPixelSize.width / _size,
                  ),
                ),
              ),
            ),
          // Pause overlay removed — host GameContainerScreen provides it.
          // Tutorial overlay.
          if (_showTutorial)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: _TutorialOverlayBlocks(
                  elapsed: _tutorialElapsed,
                  onDismiss: _dismissTutorial,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _resolveDrop(_Piece piece, Offset globalPos) {
    // Convert global pos to grid-relative local coords via the grid's
    // own render box — robust against padding / chrome changes.
    final gridBox =
        _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (gridBox == null) return;
    final local = gridBox.globalToLocal(globalPos);
    if (local.dx < 0 ||
        local.dy < 0 ||
        local.dx > _gridPixelSize.width ||
        local.dy > _gridPixelSize.height) {
      return; // dropped outside the grid
    }
    final cell = _gridPixelSize.width / _size;
    final col = (local.dx / cell).floor();
    final row = (local.dy / cell).floor();
    // Anchor the piece by its top-left cell (so the player's finger
    // positions the piece's top-left corner).
    _tryPlace(piece, row, col);
  }

  // Returns (row, col) of the cell under the given global drag position,
  // anchoring the piece by its top-left so the hovered row/col is the
  // piece's origin cell. Returns null if the drag is outside the grid
  // or the piece wouldn't fit there.
  (int, int)? _hoverFromPos(Offset globalPos) {
    final gridBox =
        _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (gridBox == null) return null;
    final local = gridBox.globalToLocal(globalPos);
    if (local.dx < 0 ||
        local.dy < 0 ||
        local.dx > _gridPixelSize.width ||
        local.dy > _gridPixelSize.height) {
      return null;
    }
    final cell = _gridPixelSize.width / _size;
    final col = (local.dx / cell).floor();
    final row = (local.dy / cell).floor();
    if (_draggingPiece == null) return null;
    if (!_canPlaceAt(_draggingPiece!, row, col)) return null;
    return (row, col);
  }

  bool _canPlaceAt(_Piece piece, int originRow, int originCol) {
    for (final cell in piece.cells) {
      final r = originRow + cell.dr;
      final c = originCol + cell.dc;
      if (r < 0 || r >= _size || c < 0 || c >= _size) return false;
      if (_grid[r * _size + c] != null) return false;
    }
    return true;
  }
}

class _Piece {
  const _Piece(this.cells, this.colorId);
  static const _Piece empty = _Piece._([], 0);
  const _Piece._(this.cells, this.colorId);

  final List<_PCell> cells;
  final int colorId;
  bool get isEmpty => cells.isEmpty;

  static const List<_Piece> shapes = [
    _Piece([_PCell(0, 0), _PCell(0, 1), _PCell(0, 2), _PCell(0, 3)], 0),
    _Piece([_PCell(0, 0), _PCell(1, 0), _PCell(2, 0), _PCell(3, 0)], 1),
    _Piece([_PCell(0, 0), _PCell(0, 1)], 2),
    _Piece(
        [_PCell(0, 1), _PCell(1, 0), _PCell(1, 1), _PCell(2, 0)], 3),
    _Piece(
        [_PCell(0, 0), _PCell(0, 1), _PCell(1, 1), _PCell(1, 2)], 4),
  ];
}

class _PCell {
  const _PCell(this.dr, this.dc);
  final int dr;
  final int dc;
}

class _PieceWidget extends StatelessWidget {
  const _PieceWidget({
    required this.piece,
    required this.palette,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final _Piece piece;
  final List<Color> palette;
  final VoidCallback onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final color = palette[piece.colorId];
    return LayoutBuilder(
      builder: (context, c) {
        final maxRows =
            piece.cells.map((e) => e.dr).reduce((a, b) => a > b ? a : b) + 1;
        final maxCols =
            piece.cells.map((e) => e.dc).reduce((a, b) => a > b ? a : b) + 1;
        final cell = ((c.maxWidth - 4) / maxCols).clamp(8.0, 16.0);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) {
            onDragStart();
            onDragUpdate(d.globalPosition);
          },
          onPanUpdate: (d) => onDragUpdate(d.globalPosition),
          onPanEnd: (_) => onDragEnd(),
          onPanCancel: onDragEnd,
          child: SizedBox(
            width: maxCols * cell,
            height: maxRows * cell,
            child: CustomPaint(
              painter: _PiecePainter(piece: piece, color: color, cell: cell),
            ),
          ),
        );
      },
    );
  }
}

class _PiecePainter extends CustomPainter {
  _PiecePainter({
    required this.piece,
    required this.color,
    required this.cell,
  });
  final _Piece piece;
  final Color color;
  final double cell;

  @override
  void paint(Canvas canvas, Size size) {
    for (final c in piece.cells) {
      final rect = Rect.fromLTWH(c.dc * cell, c.dr * cell, cell - 1, cell - 1);
      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(3));
      canvas.drawRRect(
        rr,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(color, Colors.white, 0.35) ?? color,
              color,
              Color.lerp(color, Colors.black, 0.30) ?? color,
            ],
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(_PiecePainter old) =>
      old.piece != piece || old.color != color || old.cell != cell;
}

class _BlockGridPainter extends CustomPainter {
  _BlockGridPainter({
    required this.grid,
    required this.flash,
    required this.flashing,
    required this.palette,
    required this.cell,
    required this.hoverRow,
    required this.hoverCol,
    required this.hoverPiece,
    required this.particles,
    required this.floaters,
  });

  final List<int?> grid;
  final double flash;
  final bool flashing;
  final List<Color> palette;
  final double cell;
  final int? hoverRow;
  final int? hoverCol;
  final _Piece? hoverPiece;
  final List<_LineParticle> particles;
  final List<_ComboFloater> floaters;

  @override
  void paint(Canvas canvas, Size size) {
    // Board background with rounded corners and shadow.
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(14),
    );
    canvas.drawRRect(
      rrect.shift(const Offset(0, 3)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF131822), Color(0xFF0B0E14)],
        ).createShader(Offset.zero & size),
    );

    // Subtle grid lines.
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    for (var i = 1; i < 8; i++) {
      final p = i * cell;
      canvas.drawLine(Offset(p, 0), Offset(p, size.height), line);
      canvas.drawLine(Offset(0, p), Offset(size.width, p), line);
    }

    // Filled cells with glossy 3D gradient.
    for (var r = 0; r < 8; r++) {
      for (var c = 0; c < 8; c++) {
        if (r * 8 + c >= grid.length) continue;
        final id = grid[r * 8 + c];
        if (id == null) continue;
        if (id < 0 || id >= palette.length) continue;
        final color = palette[id];
        final rect = Rect.fromLTWH(c * cell + 2, r * cell + 2, cell - 4, cell - 4);
        final rr = RRect.fromRectAndRadius(rect, const Radius.circular(5));
        // Drop shadow.
        canvas.drawRRect(
          rr.shift(const Offset(1, 2)),
          Paint()
            ..color = Colors.black.withValues(alpha: 0.55)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
        );
        // 4-stop bevel (highlight → base → shade → edge).
        canvas.drawRRect(
          rr,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.lerp(color, Colors.white, 0.40) ?? color,
                color,
                Color.lerp(color, Colors.black, 0.18) ?? color,
                Color.lerp(color, Colors.black, 0.40) ?? color,
              ],
              stops: const [0.0, 0.4, 0.7, 1.0],
            ).createShader(rect),
        );
        // Inner radial highlight (top-left).
        canvas.drawRRect(
          rr,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(-0.4, -0.5),
              radius: 0.7,
              colors: [
                Colors.white.withValues(alpha: 0.18),
                Colors.white.withValues(alpha: 0.0),
              ],
            ).createShader(rect),
        );
        // Outline.
        canvas.drawRRect(
          rr,
          Paint()
            ..color = Color.lerp(color, Colors.black, 0.55) ?? color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
        // Specular highlight dot.
        canvas.drawCircle(
          rect.topLeft + const Offset(4, 4),
          2.5,
          Paint()..color = Colors.white.withValues(alpha: 0.7),
        );
      }
    }

    // Border around board.
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = const Color(0xFF2A3245)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Placement highlight glow (when dragging a piece over a valid cell).
    if (hoverRow != null && hoverCol != null && hoverPiece != null) {
      canvas.save();
      canvas.clipRRect(rrect);
      final color = palette[hoverPiece!.colorId];
      for (final c in hoverPiece!.cells) {
        final r = hoverRow! + c.dr;
        final cc = hoverCol! + c.dc;
        if (r < 0 || r >= 8 || cc < 0 || cc >= 8) continue;
        final rect = Rect.fromLTWH(
          cc * cell + 2,
          r * cell + 2,
          cell - 4,
          cell - 4,
        );
        final rr = RRect.fromRectAndRadius(rect, const Radius.circular(5));
        // Outer glow ring.
        canvas.drawRRect(
          rr.inflate(2),
          Paint()
            ..color = const Color(0xFF22D3EE).withValues(alpha: 0.65)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
        // Tinted ghost fill.
        canvas.drawRRect(
          rr,
          Paint()
            ..color = Color.lerp(color, Colors.white, 0.12) ?? color
            ..style = PaintingStyle.fill,
        );
      }
      canvas.restore();
    }

    if (flashing) {
      // Multi-stage line-clear flash:
      //   0–0.13s: white burst (full alpha)
      //   0.13–0.47s: colored sweep, top→bottom, fading out
      // (particles handle the "burst" stage visually)
      if (flash < 0.13) {
        final t = flash / 0.13;
        final alpha = (1 - t).clamp(0.0, 1.0);
        final flashPaint = Paint()
          ..color = Colors.white.withValues(alpha: alpha);
        canvas.save();
        canvas.clipRRect(rrect);
        canvas.drawRect(Offset.zero & size, flashPaint);
        canvas.restore();
      } else if (flash < 0.47) {
        final t = ((flash - 0.13) / 0.34).clamp(0.0, 1.0);
        final sweepPaint = Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFFFACC15).withValues(alpha: 0.7 * (1 - t)),
              const Color(0xFFFACC15).withValues(alpha: 0),
            ],
          ).createShader(Offset.zero & size);
        canvas.save();
        canvas.clipRRect(rrect);
        canvas.drawRect(Offset.zero & size, sweepPaint);
        canvas.restore();
      }
    }

    // Particle bursts (always visible during their life).
    if (particles.isNotEmpty) {
      for (final p in particles) {
        final alpha = (p.life / p.maxLife).clamp(0.0, 1.0);
        canvas.drawCircle(
          Offset(p.x, p.y),
          p.size,
          Paint()..color = p.color.withValues(alpha: alpha),
        );
      }
    }

    // Combo floaters (always visible during their life).
    for (final f in floaters) {
      final yOff = -50 * f.t;
      final alpha = (1 - f.t).clamp(0.0, 1.0);
      final tp = TextPainter(
        text: TextSpan(
          text: f.text,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: f.color.withValues(alpha: alpha),
            shadows: const [
              Shadow(
                color: Color(0x80000000),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(f.x - tp.width / 2, f.y + yOff));
    }
  }

  @override
  bool shouldRepaint(_BlockGridPainter old) =>
      old.grid != grid ||
      old.flash != flash ||
      old.flashing != flashing ||
      old.cell != cell ||
      old.hoverRow != hoverRow ||
      old.hoverCol != hoverCol ||
      old.hoverPiece != hoverPiece ||
      old.particles.length != particles.length ||
      old.floaters.length != floaters.length;
}

class _DragGhostPainter extends CustomPainter {
  _DragGhostPainter({
    required this.piece,
    required this.color,
    required this.pos,
    required this.cell,
  });
  final _Piece piece;
  final Color color;
  final Offset pos;
  final double cell;

  @override
  void paint(Canvas canvas, Size size) {
    // Drop shadow under the ghost.
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    for (final c in piece.cells) {
      final rect = Rect.fromLTWH(
        pos.dx + c.dc * cell,
        pos.dy + c.dr * cell + 3,
        cell - 1,
        cell - 1,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        shadowPaint,
      );
    }
    // Beveled ghost body.
    for (final c in piece.cells) {
      final rect = Rect.fromLTWH(
        pos.dx + c.dc * cell,
        pos.dy + c.dr * cell,
        cell - 1,
        cell - 1,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(color, Colors.white, 0.4) ?? color,
              color,
              Color.lerp(color, Colors.black, 0.30) ?? color,
            ],
          ).createShader(rect),
      );
      // Subtle highlight dot.
      canvas.drawCircle(
        rect.topLeft + const Offset(3, 3),
        1.8,
        Paint()..color = Colors.white.withValues(alpha: 0.7),
      );
    }
  }

  @override
  bool shouldRepaint(_DragGhostPainter old) =>
      old.piece != piece || old.pos != pos || old.cell != cell;
}

// ─── Combo floater ───────────────────────────────────────────────
class _ComboFloater {
  _ComboFloater({
    required this.text,
    required this.x,
    required this.y,
    required this.t,
    required this.color,
  });
  final String text;
  final double x;
  final double y;
  double t;
  final Color color;
}

// ─── Line-clear particle ─────────────────────────────────────────
class _LineParticle {
  _LineParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.color,
    required this.life,
    required this.maxLife,
    required this.size,
  });
  double x;
  double y;
  double vx;
  double vy;
  final Color color;
  double life;
  final double maxLife;
  final double size;
}

// ─── BG sparkle ──────────────────────────────────────────────────
class _BgSparkle {
  _BgSparkle({
    required this.x,
    required this.y,
    required this.r,
    required this.life,
    required this.phase,
  });
  double x;
  double y;
  double r;
  double life;
  double phase;
}

class _BlockBgPainter extends CustomPainter {
  _BlockBgPainter({required this.bck, required this.idleTime});
  final List<_BgSparkle> bck;
  final double idleTime;

  @override
  void paint(Canvas canvas, Size size) {
    // Pastel purple→indigo gradient.
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFF3E8FF),
            Color(0xFFE9D5FF),
            Color(0xFFDDD6FE),
          ],
        ).createShader(rect),
    );

    // Subtle grid texture overlay.
    final grid = Paint()
      ..color = const Color(0xFF6D28D9).withValues(alpha: 0.06)
      ..strokeWidth = 1;
    const step = 32.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    // Bg sparkles.
    for (final b in bck) {
      final alpha = b.life.clamp(0.0, 1.0);
      final twinkle = 0.5 +
          0.5 *
              sin(idleTime * 2.4 + b.phase);
      final r = b.r * (0.7 + 0.3 * twinkle);
      final cx = b.x * size.width;
      final cy = b.y * size.height;
      // Soft halo.
      canvas.drawCircle(
        Offset(cx, cy),
        r * 2.5,
        Paint()
          ..color = const Color(0xFFA855F7).withValues(alpha: 0.10 * alpha),
      );
      // Star core.
      final core = Paint()
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.7 * alpha);
      _drawStar(canvas, Offset(cx, cy), r, core);
    }
  }

  void _drawStar(Canvas canvas, Offset c, double r, Paint p) {
    final path = Path();
    for (var i = 0; i < 4; i++) {
      final a = (pi / 2) * i + pi / 4;
      path.moveTo(c.dx + cos(a) * r * 1.6, c.dy + sin(a) * r * 1.6);
      path.lineTo(c.dx, c.dy);
      path.close();
    }
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_BlockBgPainter old) =>
      old.idleTime != idleTime || old.bck.length != bck.length;
}

// ─── Tutorial overlay ─────────────────────────────────────────────
class _TutorialOverlayBlocks extends StatelessWidget {
  const _TutorialOverlayBlocks({
    required this.elapsed,
    required this.onDismiss,
  });

  final double elapsed;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final slide = (elapsed / 0.28).clamp(0.0, 1.0);
    final eased = Curves.easeOutCubic.transform(slide);
    final opacity = (elapsed / 0.28).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
      child: Opacity(
        opacity: opacity,
        child: Transform.translate(
          offset: Offset(0, (1 - eased) * 40),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
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
                      child: AnimatedBuilder(
                        animation: AlwaysStoppedAnimation(elapsed),
                        builder: (_, c2) => CustomPaint(
                          painter: _BlockHandPainter(t: elapsed),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Drag a piece from the dock onto the grid!',
                        style: TextStyle(
                          color: Color(0xFF1E3A8A),
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          height: 1.25,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: onDismiss,
                      child: const Icon(
                        Icons.close_rounded,
                        color: Color(0xFF6B7280),
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Tutorial hand painter (bottom-dock → grid drag motion) ────────
class _BlockHandPainter extends CustomPainter {
  _BlockHandPainter({required this.t});
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    // Bobbing animation: up-and-down plus a periodic forward tap.
    final bob = sin(t * 4.0) * 3.0;
    final tap = (sin(t * 2.0) * 0.5 + 0.5); // 0→1 cycle
    final dy = -bob - 1.5 * tap;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2 + dy);
    canvas.rotate(-0.45); // pointing up-left toward the grid

    final body = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFCD34D), Color(0xFFF59E0B)],
      ).createShader(Rect.fromCenter(
        center: const Offset(0, 0),
        width: 32,
        height: 32,
      ));
    final outline = Paint()
      ..color = const Color(0xFF1F2937)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Palm.
    final palm = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-10, -2, 18, 16),
      const Radius.circular(7),
    );
    canvas.drawRRect(palm, body);
    canvas.drawRRect(palm, outline);

    // Index finger pointing up-left.
    final finger = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-13, -16, 5, 16),
      const Radius.circular(2.5),
    );
    canvas.drawRRect(finger, body);
    canvas.drawRRect(finger, outline);

    // Folded fingers (small bumps on right side of palm).
    for (var i = 0; i < 3; i++) {
      final bump = RRect.fromRectAndRadius(
        Rect.fromLTWH(-1, 4 + i * 3, 10, 3),
        const Radius.circular(1.5),
      );
      canvas.drawRRect(bump, body);
      canvas.drawRRect(bump, outline);
    }
    // Thumb.
    final thumb = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-15, 8, 5, 9),
      const Radius.circular(2.5),
    );
    canvas.drawRRect(thumb, body);
    canvas.drawRRect(thumb, outline);

    canvas.restore();

    // Tap dot/ring indicator in the foreground.
    final cx = size.width / 2 - 18.0;
    final cy = size.height / 2 + 14.0 + dy;
    final ringAlpha = (1 - tap).clamp(0.0, 1.0);
    canvas.drawCircle(
      Offset(cx, cy),
      6.0 + tap * 6.0,
      Paint()
        ..color = const Color(0xFFA855F7).withValues(alpha: 0.45 * ringAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_BlockHandPainter old) => old.t != t;
}
