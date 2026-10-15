import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../mini_game.dart';

/// Tile Match — Triple-Tile / Tile Stack layered match-3.
///
/// Scene (top → bottom):
///   * HUD provided by the host container (back / pause / restart /
///     sound / haptics + overlays). This game paints only the gameplay
///     surface and in-game effects.
///   * 4×5×3 layered isometric grid of kawaii pastel vector tiles
///     (cats, fish, leaves, stars, flowers, hearts) with thick dark
///     outlines, multi-layer bevels, and soft drop shadows.
///   * Tappable tiles pulse softly + bob in place; tapping a tile
///     lifts it (easeOutBack) and glides it into the next free tray
///     slot with a parabolic arc.
///   * 3-match triggers a glossy 3D `MATCH! +N` pop-up surrounded by
///     floating sparkle particles, a shockwave ring, and pop bursts.
///   * 7-slot rounded white tray.
///   * Idle tutorial hand pointing at a valid tappable tile on the
///     initial levels.
class TileMatchGame extends MiniGame {
  const TileMatchGame({super.key, required super.callbacks});

  @override
  State<TileMatchGame> createState() => _State();
}

class _State extends MiniGameState<TileMatchGame>
    with TickerProviderStateMixin {
  // ─── Constants ────────────────────────────────────────────────
  static const int _cols = 4;
  static const int _rows = 5;
  static const int _layers = 3;
  static const int _cellCount = _cols * _rows;
  static const int _traySlots = 7;
  static const double _tileGap = 8;
  static const double _layerDX = 6;
  static const double _layerDY = -10;
  static const int _maxLives = 3;
  static const double _idleHandDelay = 4.0;
  static const double _idleHandDuration = 3.0;
  static const int _comboCap = 10;

  // 6 distinct kawaii symbol kinds (cats / fish / leaf / star /
  // flower / heart).
  static const List<String> _symbolNames = [
    'cat', 'fish', 'leaf', 'star', 'flower', 'heart',
  ];

  /// Pastel fills per kind (kawaii palettes).
  static const List<_SymbolPalette> _palettes = [
    _SymbolPalette(
      body: 0xFFFECACA, shade: 0xFFF87171, edge: 0xFF991B1B, accent: 0xFFFFB199,
    ), // cat — peach
    _SymbolPalette(
      body: 0xFF60A5FA, shade: 0xFF2563EB, edge: 0xFF1E3A8A, accent: 0xFFBFDBFE,
    ), // fish — sky
    _SymbolPalette(
      body: 0xFF86EFAC, shade: 0xFF16A34A, edge: 0xFF14532D, accent: 0xFFD1FAE5,
    ), // leaf — lime
    _SymbolPalette(
      body: 0xFFFDE047, shade: 0xFFEAB308, edge: 0xFF854D0E, accent: 0xFFFFF7E6,
    ), // star — yellow
    _SymbolPalette(
      body: 0xFFF472B6, shade: 0xFFDB2777, edge: 0xFF831843, accent: 0xFFFCE7F3,
    ), // flower — pink
    _SymbolPalette(
      body: 0xFFA78BFA, shade: 0xFF7C3AED, edge: 0xFF4C1D95, accent: 0xFFEDE9FE,
    ), // heart — violet
  ];

  late final Ticker _ticker;
  late final Ticker _idleTicker;
  DateTime _last = DateTime.now();
  double _idleTime = 0;
  final Random _rng = Random();

  // ─── Geometry (set in LayoutBuilder) ──────────────────────────
  Size _canvas = Size.zero;
  double _playfieldX = 0;
  double _playfieldY = 0;
  double _tileSize = 56;
  // HUD geometry.
  double _hudH = 0;
  double _trayH = 0;
  double _pillH = 0;

  // ─── Board ────────────────────────────────────────────────────
  late List<_Cell?> _cells;

  // ─── Tray ─────────────────────────────────────────────────────
  late List<int?> _tray;
  final List<_PickRecord> _history = [];

  // ─── Effects ──────────────────────────────────────────────────
  final List<_Flyer> _flyers = [];
  final List<_PopBurst> _bursts = [];
  final List<_Shockwave> _shocks = [];
  final List<_FloatText> _floaters = [];
  final List<_Sparkle> _sparkles = [];
  final List<_MatchPop> _matchPops = [];

  // ─── Power-up cooldowns ───────────────────────────────────────
  double _undoCD = 0;
  double _shuffleCD = 0;
  double _hintCD = 0;
  int _hintHighlightIdx = -1;
  double _hintHighlightTime = 0;

  // ─── Lives / Combo / Tutorial hand ────────────────────────────
  int _lives = _maxLives;
  int _combo = 0;
  double _comboPulseT = 0;
  int _tutorialHandTarget = -1;
  double _tutorialHandIdleAcc = 0;
  double _tutorialHandShownAt = 0;
  final int _level = 1;

  // ─── Game state ───────────────────────────────────────────────
  int _score = 0;
  bool _gameOver = false;
  bool _won = false;

  @override
  void initState() {
    super.initState();
    _initBoard();
    _tray = List<int?>.filled(_traySlots, null);
    _last = DateTime.now();
    _ticker = createTicker(_onTick)..start();
    _idleTicker = createTicker(_onIdle)..start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reportScore(_score);
      reportStats('Lives $_lives  •  Combo $_combo');
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _idleTicker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final now = DateTime.now();
    final dt = now.difference(_last).inMicroseconds / 1e6;
    _last = now;
    if (_gameOver) return;
    _stepEffects(dt);
    _stepCooldowns(dt);
    _stepCombo(dt);
    _stepTutorialHand(dt);
    if (mounted) setState(() {});
    _checkWinOrLose();
  }

  void _onIdle(Duration elapsed) {
    _idleTime += 1 / 60;
  }

  void _stepEffects(double dt) {
    for (final f in _flyers) {
      f.t += dt / 0.32;
    }
    _flyers.removeWhere((f) {
      if (f.t >= 1) {
        _onFlyerLand(f);
        return true;
      }
      return false;
    });
    for (final b in _bursts) {
      b.life -= dt;
    }
    _bursts.removeWhere((b) => b.life <= 0);
    for (final s in _shocks) {
      s.t += dt / 0.32;
    }
    _shocks.removeWhere((s) => s.t >= 1);
    for (final fl in _floaters) {
      fl.t += dt / 1.0;
    }
    _floaters.removeWhere((fl) => fl.t >= 1);
    for (final sp in _sparkles) {
      sp.life -= dt;
      sp.x += sp.vx * dt;
      sp.y += sp.vy * dt;
      sp.vy += 220 * dt; // mild gravity
      sp.rot += sp.spin * dt;
    }
    _sparkles.removeWhere((sp) => sp.life <= 0);
    for (final mp in _matchPops) {
      mp.t += dt / 1.2;
    }
    _matchPops.removeWhere((mp) => mp.t >= 1);
  }

  void _stepCooldowns(double dt) {
    if (_undoCD > 0) _undoCD = (_undoCD - dt).clamp(0, 1);
    if (_shuffleCD > 0) _shuffleCD = (_shuffleCD - dt).clamp(0, 1);
    if (_hintCD > 0) _hintCD = (_hintCD - dt).clamp(0, 1);
    if (_hintHighlightTime > 0) {
      _hintHighlightTime -= dt;
      if (_hintHighlightTime <= 0) _hintHighlightIdx = -1;
    }
  }

  void _stepCombo(double dt) {
    if (_comboPulseT > 0) _comboPulseT = (_comboPulseT - dt).clamp(0, 1);
  }

  void _stepTutorialHand(double dt) {
    if (_gameOver) {
      _tutorialHandTarget = -1;
      _tutorialHandIdleAcc = 0;
      return;
    }
    _tutorialHandIdleAcc += dt;
    if (_tutorialHandTarget >= 0) {
      // Hide after auto-duration.
      if (_idleTime - _tutorialHandShownAt > _idleHandDuration) {
        _tutorialHandTarget = -1;
        _tutorialHandIdleAcc = 0;
      }
    } else if (_tutorialHandIdleAcc > _idleHandDelay && _level <= 3) {
      // Pick a fresh target.
      _tutorialHandTarget = _pickHintTarget();
      _tutorialHandShownAt = _idleTime;
    }
  }

  // ─── Board init ───────────────────────────────────────────────
  void _initBoard() {
    _cells = List<_Cell?>.filled(_cols * _rows * _layers, null);
    final symbolsPerLayer = _palettes.length;
    for (var layer = 0; layer < _layers; layer++) {
      for (var i = 0; i < _cellCount; i++) {
        final idx = layer * _cellCount + i;
        final kind = _rng.nextInt(symbolsPerLayer);
        _cells[idx] = _Cell(kind);
      }
    }
  }

  // ─── Hit testing ──────────────────────────────────────────────
  int _hitTestCell(Offset p) {
    if (_tileSize <= 0) return -1;
    for (var layer = _layers - 1; layer >= 0; layer--) {
      for (var row = 0; row < _rows; row++) {
        for (var col = 0; col < _cols; col++) {
          final idx = layer * _cellCount + row * _cols + col;
          final cell = _cells[idx];
          if (cell == null) continue;
          if (!_isTappable(layer, col, row)) continue;
          final rect = _cellRect(layer, col, row);
          if (rect.contains(p)) return idx;
        }
      }
    }
    return -1;
  }

  Rect _cellRect(int layer, int col, int row) {
    final baseX = _playfieldX + col * (_tileSize + _tileGap);
    final baseY = _playfieldY + row * (_tileSize + _tileGap);
    final x = baseX + layer * _layerDX;
    final y = baseY + layer * _layerDY;
    return Rect.fromLTWH(x, y, _tileSize, _tileSize);
  }

  bool _isTappable(int layer, int col, int row) {
    if (layer >= _layers - 1) return true;
    final aboveIdx = (layer + 1) * _cellCount + row * _cols + col;
    return _cells[aboveIdx] == null;
  }

  // ─── Tap handler ──────────────────────────────────────────────
  void _onTapDown(TapDownDetails d) {
    if (_gameOver) return;
    final idx = _hitTestCell(d.localPosition);
    if (idx < 0) return;
    _tutorialHandTarget = -1;
    _tutorialHandIdleAcc = 0;
    final cell = _cells[idx]!;
    // Find first empty tray slot.
    var slot = -1;
    for (var i = 0; i < _traySlots; i++) {
      if (_tray[i] == null) {
        slot = i;
        break;
      }
    }
    if (slot < 0) {
      _floaters.add(_FloatText(
        text: 'TRAY FULL',
        color: const Color(0xFFFCA5A5),
        x: _canvas.width / 2,
        y: _canvas.height * 0.74,
        t: 0,
      ));
      _decrementLife();
      HapticFeedback.lightImpact();
      return;
    }
    final layer = idx ~/ _cellCount;
    final row = (idx % _cellCount) ~/ _cols;
    final col = idx % _cols;
    final origin = _cellRect(layer, col, row).center;
    final target = _traySlotRect(slot).center;
    _flyers.add(_Flyer(
      symbol: cell.symbol,
      origin: origin,
      target: target,
      t: 0,
    ));
    _cells[idx] = null;
    _history.add(_PickRecord(slot: slot, symbol: cell.symbol, idx: idx));
    HapticFeedback.lightImpact();
    setState(() {});
  }

  Rect _traySlotRect(int slot) {
    final trayW = _canvas.width * 0.92;
    final slotW = (trayW - (_traySlots + 1) * 8) / _traySlots;
    final left = (_canvas.width - trayW) / 2 + 8 + slot * (slotW + 8);
    final top = _canvas.height - _pillH - _trayH - 8;
    return Rect.fromLTWH(left, top, slotW, _trayH - 16);
  }

  void _onFlyerLand(_Flyer f) {
    var slot = -1;
    for (var i = 0; i < _traySlots; i++) {
      if (_tray[i] == null) {
        slot = i;
        break;
      }
    }
    if (slot < 0) return;
    _tray[slot] = f.symbol;
    HapticFeedback.selectionClick();
    _checkTrayMatch();
  }

  void _checkTrayMatch() {
    final counts = <int, List<int>>{};
    for (var i = 0; i < _traySlots; i++) {
      final s = _tray[i];
      if (s == null) continue;
      counts.putIfAbsent(s, () => []).add(i);
    }
    var matched = false;
    counts.forEach((kind, slots) {
      if (slots.length >= 3) {
        matched = true;
        final extras = slots.length - 3;
        final baseScore = 30 * 3 + 10 * extras + 50 * _combo;
        _score += baseScore;
        _combo = (_combo + 1).clamp(0, _comboCap);
        _comboPulseT = 1.0;

        // Cluster center for VFX.
        Offset center = Offset.zero;
        for (final s in slots.take(3)) {
          center = center + _traySlotRect(s).center;
        }
        center = Offset(center.dx / 3, center.dy / 3);

        // Pop bursts at each matched slot.
        for (final s in slots.take(3)) {
          final rect = _traySlotRect(s);
          _bursts.addAll(_PopBurst.spawn(
            origin: rect.center,
            color: _palettes[kind].b,
            count: 12,
          ));
          _shocks.add(_Shockwave(rect.center, t: 0));
        }

        // 3D MATCH! +N pop-up.
        _matchPops.add(_MatchPop(
          center: center,
          text: 'MATCH! +$baseScore',
          t: 0,
        ));

        // 12 sparkle particles around the cluster.
        for (var i = 0; i < 14; i++) {
          final angle = _rng.nextDouble() * 2 * pi;
          final speed = 70 + _rng.nextDouble() * 60;
          _sparkles.add(_Sparkle(
            x: center.dx,
            y: center.dy,
            vx: cos(angle) * speed,
            vy: sin(angle) * speed - 60,
            life: 0.7,
            rot: _rng.nextDouble() * pi,
            spin: (_rng.nextDouble() - 0.5) * 12,
            color: const Color(0xFFFDE047),
          ));
        }

        // Clear those 3 slots.
        for (final s in slots.take(3)) {
          _tray[s] = null;
          _history.removeWhere((h) => h.slot == s);
        }
        // Remove that symbol kind from every cell on the board.
        for (var i = 0; i < _cells.length; i++) {
          if (_cells[i]?.symbol == kind) _cells[i] = null;
        }
        HapticFeedback.mediumImpact();
        reportStats('Lives $_lives  •  Combo $_combo');
      }
    });
    if (matched) {
      reportScore(_score);
      _checkTrayMatch();
    }
  }

  // ─── Win / lose ───────────────────────────────────────────────
  void _checkWinOrLose() {
    final remaining = _cells.where((c) => c != null).length;
    if (remaining == 0) {
      _won = true;
      _gameOver = true;
      _floaters.add(_FloatText(
        text: 'BOARD CLEARED!',
        color: const Color(0xFFFACC15),
        x: _canvas.width / 2,
        y: _canvas.height * 0.4,
        t: 0,
      ));
      HapticFeedback.heavyImpact();
      reportGameOver();
      return;
    }
    // No tappable tiles AND no tray match possible.
    var anyTappable = false;
    for (var layer = 0; layer < _layers; layer++) {
      for (var row = 0; row < _rows; row++) {
        for (var col = 0; col < _cols; col++) {
          final idx = layer * _cellCount + row * _cols + col;
          if (_cells[idx] == null) continue;
          if (_isTappable(layer, col, row)) {
            anyTappable = true;
            break;
          }
        }
        if (anyTappable) break;
      }
      if (anyTappable) break;
    }
    if (!anyTappable) {
      final trayCounts = <int, int>{};
      for (final s in _tray) {
        if (s == null) continue;
        trayCounts[s] = (trayCounts[s] ?? 0) + 1;
      }
      final trayMatchPossible = trayCounts.values.any((c) => c >= 2);
      if (!trayMatchPossible) {
        _won = false;
        _gameOver = true;
        _floaters.add(_FloatText(
          text: 'NO MOVES LEFT',
          color: const Color(0xFFF87171),
          x: _canvas.width / 2,
          y: _canvas.height * 0.4,
          t: 0,
        ));
        HapticFeedback.heavyImpact();
        reportGameOver();
      }
    }
  }

  // ─── Power-ups ────────────────────────────────────────────────
  int _pickHintTarget() {
    var bestIdx = -1;
    var bestGain = -1;
    for (var layer = 0; layer < _layers; layer++) {
      for (var row = 0; row < _rows; row++) {
        for (var col = 0; col < _cols; col++) {
          final idx = layer * _cellCount + row * _cols + col;
          if (_cells[idx] == null) continue;
          if (!_isTappable(layer, col, row)) continue;
          var gain = 0;
          if (layer > 0) {
            final belowIdx = (layer - 1) * _cellCount + row * _cols + col;
            if (_cells[belowIdx] != null) {
              final aboveIdx = (layer + 1) * _cellCount + row * _cols + col;
              if (_cells[aboveIdx] == null) gain += 1;
            }
          }
          if (gain > bestGain) {
            bestGain = gain;
            bestIdx = idx;
          }
        }
      }
    }
    return bestIdx;
  }

  // ─── Lives ────────────────────────────────────────────────────
  void _decrementLife() {
    if (_lives <= 0) return;
    _lives -= 1;
    _combo = 0;
    if (_lives <= 0) {
      _won = false;
      _gameOver = true;
      _floaters.add(_FloatText(
        text: 'OUT OF LIVES',
        color: const Color(0xFFF87171),
        x: _canvas.width / 2,
        y: _canvas.height * 0.4,
        t: 0,
      ));
      HapticFeedback.heavyImpact();
      reportGameOver();
    } else {
      _floaters.add(_FloatText(
        text: '-1 LIFE',
        color: const Color(0xFFFCA5A5),
        x: _canvas.width / 2,
        y: _canvas.height * 0.36,
        t: 0,
      ));
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _canvas = Size(constraints.maxWidth, constraints.maxHeight);
        // Layout zones (top → bottom):
        //   Playfield (flex)   Tray: 14%   Pills: 12%   Safe: 12%
        _hudH = 0;
        _pillH = _canvas.height * 0.10;
        _trayH = _canvas.height * 0.14;
        final playfieldTop = 8;
        final playfieldBottom = _canvas.height - _trayH - _pillH - 12;
        final playfieldH = playfieldBottom - playfieldTop;

        final maxTileByW = (_canvas.width - 32 - (_cols - 1) * _tileGap -
                (_layers - 1) * _layerDX) /
            _cols;
        final maxTileByH = (playfieldH - (_rows - 1) * _tileGap -
                (_layers - 1) * _layerDY.abs()) /
            _rows;
        _tileSize = maxTileByW.clamp(40.0, 76.0);
        if (_tileSize > maxTileByH) _tileSize = maxTileByH.clamp(40.0, 76.0);
        final playfieldW =
            _cols * _tileSize + (_cols - 1) * _tileGap + (_layers - 1) * _layerDX;
        final playfieldHActual =
            _rows * _tileSize + (_rows - 1) * _tileGap +
                (_layers - 1) * _layerDY.abs();
        _playfieldX = (_canvas.width - playfieldW) / 2;
        _playfieldY = playfieldTop + (playfieldH - playfieldHActual) / 2;

        return Stack(
          fit: StackFit.expand,
          children: [
            // Painter.
            CustomPaint(
              painter: _TileMatchPainter(
                cells: _cells,
                cellCount: _cellCount,
                cols: _cols,
                rows: _rows,
                layers: _layers,
                tileSize: _tileSize,
                tileGap: _tileGap,
                layerDX: _layerDX,
                layerDY: _layerDY,
                playfieldX: _playfieldX,
                playfieldY: _playfieldY,
                tray: _tray,
                traySlots: _traySlots,
                canvas: _canvas,
                hudH: _hudH,
                trayH: _trayH,
                pillH: _pillH,
                flyers: _flyers,
                bursts: _bursts,
                shocks: _shocks,
                floaters: _floaters,
                sparkles: _sparkles,
                matchPops: _matchPops,
                idleTime: _idleTime,
                hintHighlightIdx: _hintHighlightIdx,
                palettes: _palettes,
                symbolNames: _symbolNames,
                gameOver: _gameOver,
                won: _won,
                score: _score,
                level: _level,
                combo: _combo,
                comboCap: _comboCap,
                comboPulseT: _comboPulseT,
                lives: _lives,
                maxLives: _maxLives,
                tutorialHandTarget: _tutorialHandTarget,
              ),
            ),
            // Tap target covers the upper area only (playfield).
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: _canvas.height - _trayH - _pillH - 8,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: _onTapDown,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Palette
// ─────────────────────────────────────────────────────────────────
class _SymbolPalette {
  const _SymbolPalette({
    required this.body,
    required this.shade,
    required this.edge,
    required this.accent,
  });
  final int body;
  final int shade;
  final int edge;
  final int accent;
  Color get b => Color(body);
  Color get s => Color(shade);
  Color get e => Color(edge);
  Color get a => Color(accent);
}

class _Cell {
  _Cell(this.symbol);
  final int symbol;
}

class _Flyer {
  _Flyer({
    required this.symbol,
    required this.origin,
    required this.target,
    required this.t,
  });
  final int symbol;
  final Offset origin;
  final Offset target;
  double t;
}

class _PopBurst {
  _PopBurst({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.color,
    required this.life,
  });
  final double x;
  final double y;
  final double vx;
  final double vy;
  final Color color;
  double life;

  static List<_PopBurst> spawn({
    required Offset origin,
    required Color color,
    required int count,
  }) {
    final rng = Random();
    return List.generate(count, (_) {
      final angle = rng.nextDouble() * 2 * pi;
      final speed = 60 + rng.nextDouble() * 60;
      return _PopBurst(
        x: origin.dx,
        y: origin.dy,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed - 30,
        color: color,
        life: 0.48,
      );
    });
  }
}

class _Shockwave {
  _Shockwave(this.center, {required this.t});
  final Offset center;
  double t;
}

class _FloatText {
  _FloatText({
    required this.text,
    required this.color,
    required this.x,
    required this.y,
    required this.t,
  });
  final String text;
  final Color color;
  final double x;
  final double y;
  double t;
}

class _Sparkle {
  _Sparkle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.life,
    required this.rot,
    required this.spin,
    required this.color,
  });
  double x;
  double y;
  double vx;
  double vy;
  double life;
  double rot;
  double spin;
  Color color;
}

class _MatchPop {
  _MatchPop({required this.center, required this.text, required this.t});
  final Offset center;
  final String text;
  double t;
}

class _PickRecord {
  _PickRecord({required this.slot, required this.symbol, required this.idx});
  final int slot;
  final int symbol;
  final int idx;
}

// ─────────────────────────────────────────────────────────────────
// Main painter
// ─────────────────────────────────────────────────────────────────
class _TileMatchPainter extends CustomPainter {
  _TileMatchPainter({
    required this.cells,
    required this.cellCount,
    required this.cols,
    required this.rows,
    required this.layers,
    required this.tileSize,
    required this.tileGap,
    required this.layerDX,
    required this.layerDY,
    required this.playfieldX,
    required this.playfieldY,
    required this.tray,
    required this.traySlots,
    required this.canvas,
    required this.hudH,
    required this.trayH,
    required this.pillH,
    required this.flyers,
    required this.bursts,
    required this.shocks,
    required this.floaters,
    required this.sparkles,
    required this.matchPops,
    required this.idleTime,
    required this.hintHighlightIdx,
    required this.palettes,
    required this.symbolNames,
    required this.gameOver,
    required this.won,
    required this.score,
    required this.level,
    required this.combo,
    required this.comboCap,
    required this.comboPulseT,
    required this.lives,
    required this.maxLives,
    required this.tutorialHandTarget,
  });

  final List<_Cell?> cells;
  final int cellCount;
  final int cols;
  final int rows;
  final int layers;
  final double tileSize;
  final double tileGap;
  final double layerDX;
  final double layerDY;
  final double playfieldX;
  final double playfieldY;
  final List<int?> tray;
  final int traySlots;
  final Size canvas;
  final double hudH;
  final double trayH;
  final double pillH;
  final List<_Flyer> flyers;
  final List<_PopBurst> bursts;
  final List<_Shockwave> shocks;
  final List<_FloatText> floaters;
  final List<_Sparkle> sparkles;
  final List<_MatchPop> matchPops;
  final double idleTime;
  final int hintHighlightIdx;
  final List<_SymbolPalette> palettes;
  final List<String> symbolNames;
  final bool gameOver;
  final bool won;
  final int score;
  final int level;
  final int combo;
  final int comboCap;
  final double comboPulseT;
  final int lives;
  final int maxLives;
  final int tutorialHandTarget;

  static const Color _kOutline = Color(0xFF1F2937);
  static const Color _kCreamTop = Color(0xFFFFF7E6);
  static const Color _kCreamBot = Color(0xFFFAEBD7);

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Background — pastel blue → purple gradient + soft radial light.
    final bgRect = Offset.zero & size;
    canvas.drawRect(
      bgRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFEAF4FF), Color(0xFFDDE6FF), Color(0xFFE9D5FF)],
          stops: [0.0, 0.55, 1.0],
        ).createShader(bgRect),
    );
    // Soft white radial highlight top-center.
    canvas.drawCircle(
      Offset(size.width / 2, size.height * 0.15),
      size.width * 0.45,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.55),
            Colors.white.withValues(alpha: 0.0),
          ],
        ).createShader(
          Rect.fromCircle(
            center: Offset(size.width / 2, size.height * 0.15),
            radius: size.width * 0.45,
          ),
        ),
    );

    // 2. Cells (layer 0 → 2).
    for (var layer = 0; layer < layers; layer++) {
      for (var row = 0; row < rows; row++) {
        for (var col = 0; col < cols; col++) {
          final idx = layer * cellCount + row * cols + col;
          final cell = cells[idx];
          if (cell == null) continue;
          _paintTile(
            canvas,
            col: col,
            row: row,
            layer: layer,
            symbol: cell.symbol,
            tappable: !gameOver && _isTappable(layer, col, row),
            isHint: idx == hintHighlightIdx,
          );
        }
      }
    }

    // 4. Tray.
    _paintTray(canvas, size);

    // 5. Tutorial hand (if active).
    if (tutorialHandTarget >= 0) {
      _paintTutorialHand(canvas, size);
    }

    // 6. Flyers.
    for (final f in flyers) {
      final eased = Curves.easeOutCubic.transform(f.t.clamp(0, 1));
      final x = f.origin.dx + (f.target.dx - f.origin.dx) * eased;
      final y = f.origin.dy +
          (f.target.dy - f.origin.dy) * eased -
          24 * sin(eased * pi);
      final scale = 1 + 0.25 * sin(eased * pi);
      canvas.save();
      canvas.translate(x, y);
      canvas.scale(scale, scale);
      _paintTileBody(canvas, Offset.zero, palettes[f.symbol], f.symbol, 40);
      canvas.restore();
    }

    // 7. Pop bursts.
    for (final b in bursts) {
      final alpha = (b.life / 0.48).clamp(0.0, 1.0);
      final p = Paint()..color = b.color.withValues(alpha: alpha);
      canvas.drawCircle(Offset(b.x, b.y), 4, p);
    }

    // 8. Shockwaves.
    for (final s in shocks) {
      final eased = Curves.easeOutCubic.transform(s.t.clamp(0, 1));
      final r = 14 + 22 * eased;
      final alpha = (1 - s.t).clamp(0, 1) * 0.6;
      final p = Paint()
        ..color = Colors.white.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      canvas.drawCircle(s.center, r, p);
    }

    // 9. Sparkles.
    for (final sp in sparkles) {
      final alpha = (sp.life / 0.7).clamp(0.0, 1.0);
      canvas.save();
      canvas.translate(sp.x, sp.y);
      canvas.rotate(sp.rot);
      _paintSparkle(canvas, 6, sp.color, alpha);
      canvas.restore();
    }

    // 10. 3D MATCH! pop-ups.
    for (final mp in matchPops) {
      _paintMatchPop(canvas, mp);
    }

    // 11. Floaters (small "TRAY FULL" / "OUT OF LIVES" / etc).
    for (final fl in floaters) {
      final yOff = -60 * fl.t;
      final alpha = (1 - fl.t).clamp(0.0, 1.0);
      final tp = TextPainter(
        text: TextSpan(
          text: fl.text,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: fl.color.withValues(alpha: alpha),
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
      tp.paint(canvas, Offset(fl.x - tp.width / 2, fl.y + yOff));
    }
  }

  bool _isTappable(int layer, int col, int row) {
    if (layer >= layers - 1) return true;
    final aboveIdx = (layer + 1) * cellCount + row * cols + col;
    return cells[aboveIdx] == null;
  }

  // ─── Tile ─────────────────────────────────────────────────────
  void _paintTile(
    Canvas canvas, {
    required int col,
    required int row,
    required int layer,
    required int symbol,
    required bool tappable,
    required bool isHint,
  }) {
    final baseX = playfieldX + col * (tileSize + tileGap);
    final baseY = playfieldY + row * (tileSize + tileGap);
    final x = baseX + layer * layerDX;
    final y = baseY + layer * layerDY;
    final bob = tappable ? -1.5 * sin(idleTime * 2 + col + row) : 0.0;
    final scale = tappable ? 1.0 + 0.04 * sin(idleTime * 2 + col + row) : 1.0;
    final center = Offset(x + tileSize / 2, y + tileSize / 2 + bob);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale, scale);
    canvas.translate(-tileSize / 2, -tileSize / 2);

    _paintTileBody(canvas, Offset.zero, palettes[symbol], symbol, tileSize);

    if (isHint) {
      final hintPaint = Paint()
        ..color = const Color(0xFFFACC15).withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(-4, -4, tileSize + 8, tileSize + 8),
          const Radius.circular(12),
        ),
        hintPaint,
      );
    }
    if (!tappable) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, tileSize, tileSize),
          const Radius.circular(10),
        ),
        Paint()
          ..color = const Color(0xFF1E293B).withValues(alpha: 0.30),
      );
    }
    canvas.restore();
  }

  void _paintTileBody(
    Canvas canvas,
    Offset origin,
    _SymbolPalette palette,
    int symbol,
    double size,
  ) {
    final rect = Rect.fromLTWH(origin.dx, origin.dy, size, size);

    // Drop shadow.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.shift(const Offset(0, 4)),
        const Radius.circular(10),
      ),
      Paint()
        ..color = const Color(0x40000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // Warm cream bevel background.
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(10)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_kCreamTop, _kCreamBot],
        ).createShader(rect),
    );

    // Inner top-left highlight.
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(10)),
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.4, -0.5),
          radius: 0.7,
          colors: [
            Colors.white.withValues(alpha: 0.35),
            Colors.white.withValues(alpha: 0.0),
          ],
        ).createShader(rect),
    );

    // Outline (thick dark).
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(10)),
      Paint()
        ..color = _kOutline.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Kawaii icon body.
    _paintKawaiiIcon(canvas, symbol, rect, palette);
  }

  // ─── Kawaii icons (6 kinds) ────────────────────────────────────
  void _paintKawaiiIcon(
    Canvas canvas,
    int symbol,
    Rect rect,
    _SymbolPalette palette,
  ) {
    final cx = rect.center.dx;
    final cy = rect.center.dy;
    final w = rect.width;
    final h = rect.height;
    switch (symbol) {
      case 0: // cat
        _paintCat(canvas, cx, cy, w, h, palette);
        break;
      case 1: // fish
        _paintFish(canvas, cx, cy, w, h, palette);
        break;
      case 2: // leaf
        _paintLeaf(canvas, cx, cy, w, h, palette);
        break;
      case 3: // star
        _paintStar(canvas, cx, cy, w, h, palette);
        break;
      case 4: // flower
        _paintFlower(canvas, cx, cy, w, h, palette);
        break;
      case 5: // heart
        _paintHeart(canvas, cx, cy, w, h, palette);
        break;
    }
  }

  void _paintCat(Canvas canvas, double cx, double cy, double w, double h,
      _SymbolPalette p) {
    final headR = w * 0.32;
    final headCenter = Offset(cx, cy + h * 0.04);
    // Ears.
    final ear = Path()
      ..moveTo(cx - w * 0.30, cy - h * 0.16)
      ..lineTo(cx - w * 0.10, cy - h * 0.38)
      ..lineTo(cx - w * 0.18, cy - h * 0.06)
      ..close();
    canvas.drawPath(ear, Paint()..color = p.b);
    final ear2 = Path()
      ..moveTo(cx + w * 0.30, cy - h * 0.16)
      ..lineTo(cx + w * 0.10, cy - h * 0.38)
      ..lineTo(cx + w * 0.18, cy - h * 0.06)
      ..close();
    canvas.drawPath(ear2, Paint()..color = p.b);
    // Inner ear pink.
    final innerEar = Path()
      ..moveTo(cx - w * 0.26, cy - h * 0.18)
      ..lineTo(cx - w * 0.16, cy - h * 0.30)
      ..lineTo(cx - w * 0.18, cy - h * 0.12)
      ..close();
    canvas.drawPath(innerEar, Paint()..color = p.a);
    final innerEar2 = Path()
      ..moveTo(cx + w * 0.26, cy - h * 0.18)
      ..lineTo(cx + w * 0.16, cy - h * 0.30)
      ..lineTo(cx + w * 0.18, cy - h * 0.12)
      ..close();
    canvas.drawPath(innerEar2, Paint()..color = p.a);
    // Head.
    canvas.drawCircle(
      headCenter,
      headR,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: [p.b, p.s],
        ).createShader(Rect.fromCircle(center: headCenter, radius: headR)),
    );
    // Outline head + ears.
    canvas.drawCircle(
      headCenter,
      headR,
      Paint()
        ..color = _kOutline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    canvas.drawPath(
      ear,
      Paint()
        ..color = _kOutline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    canvas.drawPath(
      ear2,
      Paint()
        ..color = _kOutline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    // Cheek blush.
    canvas.drawCircle(
      Offset(cx - w * 0.18, cy + h * 0.12),
      w * 0.05,
      Paint()..color = const Color(0xFFFF6584).withValues(alpha: 0.6),
    );
    canvas.drawCircle(
      Offset(cx + w * 0.18, cy + h * 0.12),
      w * 0.05,
      Paint()..color = const Color(0xFFFF6584).withValues(alpha: 0.6),
    );
    // Eyes.
    final eyeY = cy - h * 0.02;
    final eyeOffsetX = w * 0.11;
    final eyeR = w * 0.06;
    final pupilR = w * 0.035;
    for (final sign in [-1, 1]) {
      final ex = cx + sign * eyeOffsetX;
      canvas.drawCircle(Offset(ex, eyeY), eyeR, Paint()..color = Colors.white);
      canvas.drawCircle(Offset(ex, eyeY), pupilR, Paint()..color = _kOutline);
      canvas.drawCircle(
        Offset(ex + eyeR * 0.35, eyeY - eyeR * 0.35),
        pupilR * 0.5,
        Paint()..color = Colors.white,
      );
    }
    // Smile.
    final smile = Path()
      ..moveTo(cx - w * 0.05, cy + h * 0.18)
      ..quadraticBezierTo(cx, cy + h * 0.24, cx + w * 0.05, cy + h * 0.18);
    canvas.drawPath(
      smile,
      Paint()
        ..color = _kOutline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round,
    );
  }

  void _paintFish(Canvas canvas, double cx, double cy, double w, double h,
      _SymbolPalette p) {
    final body = Rect.fromCenter(
      center: Offset(cx - w * 0.04, cy),
      width: w * 0.55,
      height: h * 0.45,
    );
    canvas.drawOval(
      body,
      Paint()
        ..shader = LinearGradient(
          colors: [p.b, p.s],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(body),
    );
    // Tail.
    final tail = Path()
      ..moveTo(body.right - 2, cy - h * 0.10)
      ..lineTo(cx + w * 0.30, cy - h * 0.22)
      ..lineTo(cx + w * 0.30, cy + h * 0.22)
      ..lineTo(body.right - 2, cy + h * 0.10)
      ..close();
    canvas.drawPath(tail, Paint()..color = p.s);
    // Outline.
    canvas.drawOval(
      body,
      Paint()
        ..color = _kOutline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    canvas.drawPath(
      tail,
      Paint()
        ..color = _kOutline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    // Eye.
    final eyeX = body.left + w * 0.12;
    final eyeY = cy - h * 0.04;
    canvas.drawCircle(Offset(eyeX, eyeY), w * 0.04, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(eyeX, eyeY), w * 0.02, Paint()..color = _kOutline);
    // Gill curve.
    final gill = Path()
      ..moveTo(body.left + w * 0.18, cy - h * 0.08)
      ..quadraticBezierTo(
        body.left + w * 0.22, cy, body.left + w * 0.18, cy + h * 0.08,
      );
    canvas.drawPath(
      gill,
      Paint()
        ..color = _kOutline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    // Scales hint.
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(body.center.dx + w * 0.04, cy),
        width: w * 0.18,
        height: h * 0.18,
      ),
      0.5,
      pi - 1.0,
      false,
      Paint()
        ..color = _kOutline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
  }

  void _paintLeaf(Canvas canvas, double cx, double cy, double w, double h,
      _SymbolPalette p) {
    final leaf = Path()
      ..moveTo(cx, cy - h * 0.32)
      ..quadraticBezierTo(cx + w * 0.36, cy - h * 0.18, cx + w * 0.30, cy + h * 0.04)
      ..quadraticBezierTo(cx + w * 0.20, cy + h * 0.30, cx, cy + h * 0.36)
      ..quadraticBezierTo(cx - w * 0.20, cy + h * 0.30, cx - w * 0.30, cy + h * 0.04)
      ..quadraticBezierTo(cx - w * 0.36, cy - h * 0.18, cx, cy - h * 0.32)
      ..close();
    canvas.drawPath(
      leaf,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [p.b, p.s],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: w * 0.4)),
    );
    canvas.drawPath(
      leaf,
      Paint()
        ..color = _kOutline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    // Vein.
    final vein = Path()
      ..moveTo(cx, cy - h * 0.30)
      ..lineTo(cx, cy + h * 0.32);
    canvas.drawPath(
      vein,
      Paint()
        ..color = _kOutline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    // Side veins.
    for (final s in [-1, 1]) {
      final v = Path()
        ..moveTo(cx, cy - h * 0.10)
        ..quadraticBezierTo(cx + s * w * 0.10, cy, cx + s * w * 0.20, cy - h * 0.04);
      canvas.drawPath(
        v,
        Paint()
          ..color = _kOutline.withValues(alpha: 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
    }
    // Highlight.
    canvas.drawCircle(
      Offset(cx - w * 0.10, cy - h * 0.10),
      w * 0.05,
      Paint()..color = Colors.white.withValues(alpha: 0.5),
    );
  }

  void _paintStar(Canvas canvas, double cx, double cy, double w, double h,
      _SymbolPalette p) {
    final star = _starPath(Offset(cx, cy), w * 0.36, w * 0.18, 5);
    canvas.drawPath(
      star,
      Paint()
        ..shader = LinearGradient(
          colors: [p.b, p.s],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: w * 0.36)),
    );
    canvas.drawPath(
      star,
      Paint()
        ..color = _kOutline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    // Inner highlight.
    canvas.drawCircle(
      Offset(cx - w * 0.06, cy - h * 0.08),
      w * 0.05,
      Paint()..color = Colors.white.withValues(alpha: 0.6),
    );
  }

  void _paintFlower(Canvas canvas, double cx, double cy, double w, double h,
      _SymbolPalette p) {
    final petalR = w * 0.16;
    for (var i = 0; i < 5; i++) {
      final angle = -pi / 2 + i * (2 * pi / 5);
      final px = cx + cos(angle) * w * 0.20;
      final py = cy + sin(angle) * w * 0.20;
      canvas.drawCircle(
        Offset(px, py),
        petalR,
        Paint()
          ..shader = RadialGradient(
            colors: [p.b, p.s],
            center: const Alignment(-0.3, -0.4),
          ).createShader(Rect.fromCircle(center: Offset(px, py), radius: petalR)),
      );
      canvas.drawCircle(
        Offset(px, py),
        petalR,
        Paint()
          ..color = _kOutline
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    }
    // Center.
    canvas.drawCircle(
      Offset(cx, cy),
      w * 0.10,
      Paint()..color = const Color(0xFFFACC15),
    );
    canvas.drawCircle(
      Offset(cx, cy),
      w * 0.10,
      Paint()
        ..color = _kOutline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    // Stamen dots.
    for (var i = 0; i < 4; i++) {
      final angle = i * (pi / 2);
      final px = cx + cos(angle) * w * 0.05;
      final py = cy + sin(angle) * w * 0.05;
      canvas.drawCircle(Offset(px, py), 1.2, Paint()..color = const Color(0xFF854D0E));
    }
  }

  void _paintHeart(Canvas canvas, double cx, double cy, double w, double h,
      _SymbolPalette p) {
    final heart = _heartPath(Offset(cx, cy), w * 0.32);
    canvas.drawPath(
      heart,
      Paint()
        ..shader = LinearGradient(
          colors: [p.b, p.s],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: w * 0.4)),
    );
    canvas.drawPath(
      heart,
      Paint()
        ..color = _kOutline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    canvas.drawCircle(
      Offset(cx - w * 0.10, cy - h * 0.04),
      w * 0.06,
      Paint()..color = Colors.white.withValues(alpha: 0.6),
    );
  }

  // ─── Tray ─────────────────────────────────────────────────────
  void _paintTray(Canvas canvas, Size size) {
    final trayW = size.width * 0.92;
    final slotW = (trayW - (traySlots + 1) * 8) / traySlots;
    final left0 = (size.width - trayW) / 2;
    final top = size.height - pillH - trayH - 12;
    // Tray backdrop — white rounded card.
    final trayBg = RRect.fromRectAndRadius(
      Rect.fromLTWH(left0, top, trayW, trayH - 16),
      const Radius.circular(24),
    );
    canvas.drawRRect(
      trayBg.shift(const Offset(0, 4)),
      Paint()
        ..color = const Color(0x30000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawRRect(trayBg, Paint()..color = Colors.white);
    for (var i = 0; i < traySlots; i++) {
      final slotRect = Rect.fromLTWH(
        left0 + 8 + i * (slotW + 8),
        top + 8,
        slotW,
        trayH - 32,
      );
      // Empty slot fill.
      canvas.drawRRect(
        RRect.fromRectAndRadius(slotRect, const Radius.circular(8)),
        Paint()..color = const Color(0xFFE2E8F0).withValues(alpha: 0.6),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(slotRect, const Radius.circular(8)),
        Paint()
          ..color = const Color(0xFFCBD5E1)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      final sym = tray[i];
      if (sym != null) {
        canvas.save();
        canvas.translate(slotRect.center.dx, slotRect.center.dy);
        canvas.scale(0.6, 0.6);
        canvas.translate(-tileSize / 2, -tileSize / 2);
        _paintTileBody(canvas, Offset.zero, palettes[sym], sym, tileSize);
        canvas.restore();
      }
    }
  }

  // ─── Tutorial hand ─────────────────────────────────────────────
  void _paintTutorialHand(Canvas canvas, Size size) {
    if (tutorialHandTarget < 0) return;
    // Compute target rect.
    final layer = tutorialHandTarget ~/ cellCount;
    final row = (tutorialHandTarget % cellCount) ~/ cols;
    final col = tutorialHandTarget % cols;
    final baseX = playfieldX + col * (tileSize + tileGap);
    final baseY = playfieldY + row * (tileSize + tileGap);
    final x = baseX + layer * layerDX;
    final y = baseY + layer * layerDY;
    final rect = Rect.fromLTWH(x, y, tileSize, tileSize);
    final cx = rect.center.dx;
    final cy = rect.top;
    final bob = sin(idleTime * 4) * 4;
    final tap = sin(idleTime * 8) > 0.7 ? 8.0 : 0.0;
    final baseY2 = cy - 22 + bob + tap;

    canvas.save();
    canvas.translate(cx, baseY2);
    // Cute cartoon hand emoji-style: rounded palm + 3 fingers + index
    // pointing down.
    final palmRect = Rect.fromCenter(
      center: const Offset(0, 0),
      width: 28,
      height: 28,
    );
    // Drop shadow.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        palmRect.shift(const Offset(0, 3)),
        const Radius.circular(10),
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.20)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    // Palm.
    canvas.drawRRect(
      RRect.fromRectAndRadius(palmRect, const Radius.circular(10)),
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFFFEF08A), Color(0xFFFCD34D)],
        ).createShader(palmRect),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(palmRect, const Radius.circular(10)),
      Paint()
        ..color = _kOutline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    // Index finger pointing down.
    final finger = Rect.fromCenter(
      center: const Offset(0, 18),
      width: 8,
      height: 18,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(finger, const Radius.circular(4)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFEF08A), Color(0xFFFCD34D)],
        ).createShader(finger),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(finger, const Radius.circular(4)),
      Paint()
        ..color = _kOutline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    // Knuckle lines.
    canvas.drawLine(
      const Offset(-7, -4),
      const Offset(7, -4),
      Paint()
        ..color = _kOutline.withValues(alpha: 0.5)
        ..strokeWidth = 1.0,
    );
    canvas.restore();
  }

  // ─── Sparkles ─────────────────────────────────────────────────
  void _paintSparkle(Canvas canvas, double r, Color color, double alpha) {
    final p = Paint()
      ..color = color.withValues(alpha: alpha)
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(0, -r)
      ..lineTo(r * 0.25, -r * 0.25)
      ..lineTo(r, 0)
      ..lineTo(r * 0.25, r * 0.25)
      ..lineTo(0, r)
      ..lineTo(-r * 0.25, r * 0.25)
      ..lineTo(-r, 0)
      ..lineTo(-r * 0.25, -r * 0.25)
      ..close();
    canvas.drawPath(path, p);
    canvas.drawCircle(
      Offset.zero,
      r * 0.3,
      Paint()..color = Colors.white.withValues(alpha: alpha),
    );
  }

  // ─── 3D MATCH! pop ────────────────────────────────────────────
  void _paintMatchPop(Canvas canvas, _MatchPop mp) {
    final t = mp.t.clamp(0.0, 1.0);
    // Scale curve: 0 → 1.2 → 1.0 over first 30 % of life, then 1.0.
    final scaleT = (t / 0.3).clamp(0.0, 1.0);
    final scale = scaleT < 1
        ? (1.2 * Curves.easeOutBack.transform(scaleT))
        : 1.0;
    final yOff = -40 * Curves.easeOutCubic.transform(t);
    final alpha =
        t < 0.15 ? t / 0.15 : (1 - (t - 0.15) / 0.85).clamp(0.0, 1.0);

    final cx = mp.center.dx;
    final cy = mp.center.dy + yOff;

    final tp = TextPainter(
      text: TextSpan(
        text: mp.text,
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w900,
          color: Colors.white,
          letterSpacing: 1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(cx, cy);
    canvas.scale(scale, scale);
    // Outer yellow glow.
    canvas.drawCircle(
      Offset.zero,
      tp.height * 1.2,
      Paint()
        ..color = const Color(0xFFFDE047).withValues(alpha: 0.45 * alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 14),
    );
    // Yellow outline (stroke).
    for (var stroke = 6; stroke >= 4; stroke--) {
      final outlineTp = TextPainter(
        text: TextSpan(
          text: mp.text,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = stroke.toDouble()
              ..color = const Color(0xFFFACC15).withValues(alpha: alpha),
            letterSpacing: 1.2,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      outlineTp.paint(canvas, Offset(-outlineTp.width / 2, -outlineTp.height / 2));
    }
    // Base white text on top.
    final baseTp = TextPainter(
      text: TextSpan(
        text: mp.text,
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w900,
          color: Colors.white.withValues(alpha: alpha),
          shadows: [
            Shadow(
              color: Colors.black.withValues(alpha: 0.4 * alpha),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
          letterSpacing: 1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    baseTp.paint(canvas, Offset(-baseTp.width / 2, -baseTp.height / 2));
    canvas.restore();
  }

  // ─── Helpers ──────────────────────────────────────────────────
  Path _starPath(Offset center, double outerR, double innerR, int points) {
    final path = Path();
    for (var i = 0; i < points * 2; i++) {
      final r = i.isEven ? outerR : innerR;
      final a = -pi / 2 + i * pi / points;
      final x = center.dx + cos(a) * r;
      final y = center.dy + sin(a) * r;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  Path _heartPath(Offset center, double r) {
    final path = Path();
    final top = Offset(center.dx, center.dy - r * 0.7);
    final left = Offset(center.dx - r, center.dy);
    final right = Offset(center.dx + r, center.dy);
    final bottom = Offset(center.dx, center.dy + r);
    path
      ..moveTo(top.dx, top.dy)
      ..cubicTo(
        left.dx, top.dy,
        left.dx, bottom.dy,
        bottom.dx, bottom.dy,
      )
      ..cubicTo(
        right.dx, bottom.dy,
        right.dx, top.dy,
        top.dx, top.dy,
      )
      ..close();
    return path;
  }

  @override
  bool shouldRepaint(_TileMatchPainter old) => true;
}
