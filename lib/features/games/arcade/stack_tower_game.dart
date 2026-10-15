import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../game_widgets.dart';
import '../mini_game.dart';
import '../widgets/game_flow_overlays.dart';

/// Stack Tower — single-screen tap-to-drop stacking game in the
/// "Pool / Backgammon / Maze Escape" mini-game family.
///
/// Match the reference: side-on cartoon tower with a moving block
/// sliding horizontally above a stacked tower. Tap to drop the
/// moving block onto the stack; the overlap becomes the new top,
/// any overhang is trimmed. Stack as many blocks as you can before
/// missing entirely.
///
/// Phases: `start → play → win → trophy`.
class StackTowerGame extends MiniGame {
  const StackTowerGame({super.key, required super.callbacks});

  @override
  State<StackTowerGame> createState() => _StackTowerGameState();
}

enum _StackPhase { start, play, win, trophy }

class _StackTowerGameState extends MiniGameState<StackTowerGame>
    with SingleTickerProviderStateMixin {
  /// Visual height of each stacked block.
  static const double _blockH = 22;

  /// Target height — winning score.
  static const int _target = 50;

  final List<_Block> _blocks = [];
  late _Block _moving;
  bool _goingRight = true;
  double _screenW = 0;
  double _screenH = 0;
  int _score = 0;
  int _bestScore = 0;
  int _combo = 0;
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  _StackPhase _phase = _StackPhase.start;

  @override
  void initState() {
    super.initState();
    _blocks.add(_Block(0, 0, _blockH, 200, _BlockColor.blue));
    _moving = _Block(-200, 0, _blockH, 200, _BlockColor.red);
    _ticker = createTicker(_tick)..start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reportScore(_score);
      reportStats('Best $_bestScore');
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _refreshHud() {
    reportScore(_score);
    reportStats(
      'Combo ×$_combo  •  Best $_bestScore',
    );
  }

  void _onPlay() {
    setState(() {
      _phase = _StackPhase.play;
      _score = 0;
      _combo = 0;
      _blocks.clear();
      _blocks.add(_Block(0, _blockH, _blockH, _screenW, _BlockColor.blue));
      _spawnMoving();
    });
    _refreshHud();
  }

  void _onPlayAgain() {
    setState(() {
      _phase = _StackPhase.start;
      _score = 0;
      _combo = 0;
      _blocks.clear();
      _blocks.add(_Block(0, 0, _blockH, 200, _BlockColor.blue));
      _spawnMoving();
    });
    _refreshHud();
  }

  void _spawnMoving() {
    final top = _blocks.last;
    final w = top.width;
    _moving = _Block(
      _goingRight ? -w : _screenW,
      top.y,
      _blockH,
      w,
      _goingRight ? _BlockColor.red : _BlockColor.yellow,
    );
  }

  void _tick(Duration elapsed) {
    if (_phase == _StackPhase.win || _phase == _StackPhase.trophy) {
      if (_ticker.isActive) _ticker.stop();
      return;
    }
    if (_phase != _StackPhase.play) return;
    if (_screenW == 0) return;
    final dt = _last == Duration.zero
        ? 0.016
        : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    final speed = 130.0 + _score * 5;
    setState(() {
      if (_goingRight) {
        _moving = _moving.copyWith(x: _moving.x + speed * dt);
        if (_moving.x + _moving.width >= _screenW) {
          _goingRight = false;
          _moving = _moving.copyWith(x: _screenW - _moving.width);
        }
      } else {
        _moving = _moving.copyWith(x: _moving.x - speed * dt);
        if (_moving.x <= 0) {
          _goingRight = true;
          _moving = _moving.copyWith(x: 0);
        }
      }
    });
  }

  void _drop() {
    if (_phase != _StackPhase.play) return;
    final top = _blocks.last;
    final overlapStart = max(_moving.x, top.x);
    final overlapEnd = min(_moving.x + _moving.width, top.x + top.width);
    final overlap = overlapEnd - overlapStart;
    if (overlap <= 1) {
      // Miss entirely → game over.
      _bestScore = max(_bestScore, _score);
      haptic(HapticFeedbackType.heavy);
      reportScore(_score);
      reportStats('Best $_bestScore');
      reportGameOver();
      setState(() {
        _phase = _StackPhase.trophy;
      });
      return;
    }
    final perfect = (overlap - top.width).abs() < 1;
    final newW = perfect ? top.width : overlap;
    final newX = perfect ? _moving.x : overlapStart;
    final newY = top.y + _blockH;
    final color = _comboColor(_combo);
    setState(() {
      _blocks.add(_Block(newX, newY, _blockH, newW, color));
      if (perfect) {
        _combo++;
        _score += 10 * _combo;
      } else {
        _combo = 0;
        _score += 5;
      }
      _spawnMoving();
    });
    haptic(perfect ? HapticFeedbackType.medium : HapticFeedbackType.light);
    if (_score >= _target) {
      _bestScore = max(_bestScore, _score);
      haptic(HapticFeedbackType.heavy);
      reportGameOver();
      setState(() {
        _phase = _StackPhase.win;
      });
      return;
    }
    _refreshHud();
  }

  void _onContinueAfterWin() {
    setState(() {
      _phase = _StackPhase.trophy;
    });
  }

  // ── Build ────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: LayoutBuilder(
              builder: (context, c) {
                _screenW = c.maxWidth;
                _screenH = c.maxHeight;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _phase == _StackPhase.play ? _drop : null,
                  child: CustomPaint(
                    painter: _StackPainter(
                      blocks: _blocks,
                      moving: _phase == _StackPhase.play ? _moving : null,
                      blockH: _blockH,
                      combo: _combo,
                      screenH: _screenH,
                    ),
                    size: Size(_screenW, _screenH),
                  ),
                );
              },
            ),
          ),
        ),
        if (_phase == _StackPhase.start)
          GameStartOverlay(
            title: 'STACK TOWER',
            subtitle: 'Stack the blocks\nas high as you can!',
            youScore: _score,
            targetScore: _target,
            instruction:
                'Tap to drop the moving block onto the tower. Overhang is trimmed. Perfect drops chain combos!',
            illustration: const BoyCharacter(pose: BoyPose.cueStick),
            onPlay: _onPlay,
            onBack: () => Navigator.of(context).maybePop(),
          ),
        if (_phase == _StackPhase.win)
          GameWinOverlay(
            title: 'YOU WIN!',
            subtitle: 'TOWER BUILT!',
            scoreValue: _score,
            scoreLabel: 'Blocks Stacked',
            statRows: [
              ('Best', '$_bestScore'),
              ('Target', '$_target'),
            ],
            onContinue: _onContinueAfterWin,
          ),
        if (_phase == _StackPhase.trophy)
          GameTrophyOverlay(
            iconData: Icons.emoji_events_rounded,
            iconGradient: const [Color(0xFFFCD34D), Color(0xFFF59E0B)],
            title: _score >= _target ? 'Great Job!' : 'Keep Going!',
            subtitle: _score >= _target
                ? 'You reached the target height.'
                : 'Try again — beat your best!',
            score: _score,
            statRows: [
              ('Score', '$_score'),
              ('Best', '$_bestScore'),
              ('Target', '$_target'),
            ],
            onPlayAgain: _onPlayAgain,
            onBack: () => Navigator.of(context).maybePop(),
          ),
        // Top HUD removed — host GameContainerScreen provides it.
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// Models & painter
// ────────────────────────────────────────────────────────────────────

enum _BlockColor { red, yellow, green, blue, purple }

const Map<_BlockColor, Color> _kBlockColor = {
  _BlockColor.red: Color(0xFFEF4444),
  _BlockColor.yellow: Color(0xFFFACC15),
  _BlockColor.green: Color(0xFF22C55E),
  _BlockColor.blue: Color(0xFF3B82F6),
  _BlockColor.purple: Color(0xFFA855F7),
};

const Map<_BlockColor, Color> _kBlockColorDark = {
  _BlockColor.red: Color(0xFF991B1B),
  _BlockColor.yellow: Color(0xFFCA8A04),
  _BlockColor.green: Color(0xFF166534),
  _BlockColor.blue: Color(0xFF1E40AF),
  _BlockColor.purple: Color(0xFF6B21A8),
};

_BlockColor _comboColor(int combo) {
  if (combo >= 7) return _BlockColor.purple;
  if (combo >= 4) return _BlockColor.green;
  if (combo >= 1) return _BlockColor.blue;
  return _BlockColor.red;
}

class _Block {
  const _Block(this.x, this.y, this.height, this.width, this.color);
  final double x;
  final double y;
  final double height;
  final double width;
  final _BlockColor color;
  _Block copyWith({double? x, double? y, double? width}) =>
      _Block(x ?? this.x, y ?? this.y, height, width ?? this.width, color);
}

class _StackPainter extends CustomPainter {
  _StackPainter({
    required this.blocks,
    required this.moving,
    required this.blockH,
    required this.combo,
    required this.screenH,
  });

  final List<_Block> blocks;
  final _Block? moving;
  final double blockH;
  final int combo;
  final double screenH;

  @override
  void paint(Canvas canvas, Size size) {
    // Sky background gradient.
    final sky = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFBFDBFE), Color(0xFF60A5FA)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, sky);

    // Ground line.
    final groundY = size.height - blockH * 1.5;
    canvas.drawRect(
      Rect.fromLTWH(0, groundY + blockH, size.width, 2),
      Paint()..color = Colors.black26,
    );

    // Placed blocks (bottom-up).
    for (final b in blocks) {
      final rect = Rect.fromLTWH(
        b.x,
        groundY - b.y,
        b.width,
        b.height - 1,
      );
      final color = _kBlockColor[b.color]!;
      final dark = _kBlockColorDark[b.color]!;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()..color = color,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()
          ..color = dark
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    // Moving block.
    if (moving != null) {
      final m = moving!;
      final rect = Rect.fromLTWH(
        m.x,
        groundY - m.y,
        m.width,
        m.height - 1,
      );
      final color = _kBlockColor[m.color]!;
      final dark = _kBlockColorDark[m.color]!;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()..color = color.withValues(alpha: 0.92),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()
          ..color = dark
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
      // Combo chip.
      if (combo > 0) {
        final tp = TextPainter(
          text: TextSpan(
            text: '×$combo',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 14,
              shadows: [
                Shadow(blurRadius: 4, color: Colors.black54),
              ],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(rect.center.dx - tp.width / 2, rect.top - tp.height - 2),
        );
      }
    }

    // Drop hint.
    if (moving != null) {
      final tp = TextPainter(
        text: const TextSpan(
          text: 'TAP TO DROP',
          style: TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(size.width / 2 - tp.width / 2, size.height * 0.18),
      );
    }
  }

  @override
  bool shouldRepaint(_StackPainter old) =>
      old.blocks != blocks ||
      old.moving != moving ||
      old.combo != combo;
}
