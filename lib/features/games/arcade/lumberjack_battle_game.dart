import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../game_widgets.dart';
import '../mini_game.dart';

/// Lumberjack Battle — ported from
/// `downloaded_games/games/lumberjack_battle/game.py`.
///
/// Split-screen chop-timing game. Each side has its own tree with
/// branches. Tap left/right at the right moment to chop — chopping
/// into a branch kills you. Survival time drains each frame; chopping
/// a clear block adds score and time. First to die loses; or highest
/// score when both die.
///
/// Touch controls:
///   * Tap anywhere on the canvas during the WAITING screen to start.
///   * Tap left/right half of the panel during PLAY to chop that side.
///   * Tap to restart after GAME OVER.
///   * (Keyboard A/D works too — desktop fallback.)
///
/// Bot has 3 difficulties: easy (slow, random), medium (safe side),
/// hard (looks ahead one block).
class LumberjackBattleGame extends MiniGame {
  const LumberjackBattleGame({
    super.key,
    required super.callbacks,
    this.level = 1,
  });

  /// 1 = easy, 2 = medium, 3+ = hard bot (when AI mode on).
  final int level;

  @override
  State<LumberjackBattleGame> createState() => _LumberjackBattleState();
}

enum _LBDifficulty { easy, medium, hard }
enum _LBPhase { waiting, playing, gameOver }

class _LumberjackBattleState extends MiniGameState<LumberjackBattleGame>
    with SingleTickerProviderStateMixin {
  static const int _treeHeight = 10;
  static const double _maxTime = 100.0;

  late final Ticker _ticker;
  final Random _rng = Random();

  final bool _isAi = true; // single-player only — always vs Bot.
  late _LBDifficulty _botDiff;
  int _botDelayFrames = 0;
  int _botCooldown = 0;

  late _LBPlayer _p1;
  late _LBPlayer _p2;

  _LBPhase _phase = _LBPhase.waiting;
  int _score1 = 0;
  int _score2 = 0;
  double _time1 = _maxTime;
  double _time2 = _maxTime;
  String _lastEvent = 'Tap anywhere to start';
  String _lastReportedStats = '';

  static const Color _bg = Color(0xFF87CEEB);
  static const Color _ground = Color(0xFF228B22);
  static const Color _trunk = Color(0xFF784B28);
  static const Color _trunkLine = Color(0xFF503214);
  static const Color _p1Color = Color(0xFFFF4500);
  static const Color _p2Color = Color(0xFF1E90FF);
  static const Color _shirt1 = Color(0xFFC80000);
  static const Color _shirt2 = Color(0xFF0064C8);
  static const Color _timerFg = Color(0xFFFFD700);
  static const Color _crack = Color(0xFF000000);
  static const Color _skin = Color(0xFFFFE0BD);
  static const Color _timeBlock = Color(0xFF3296FF);

  @override
  void initState() {
    super.initState();
    _botDiff = widget.level >= 3
        ? _LBDifficulty.hard
        : (widget.level >= 2 ? _LBDifficulty.medium : _LBDifficulty.easy);
    _p1 = _LBPlayer(side: -1, color: _p1Color, shirt: _shirt1);
    _p2 = _LBPlayer(side: 1, color: _p2Color, shirt: _shirt2);
    // Synchronous state init only — defer host callbacks to next frame
    // to avoid `setState() called during build` crash.
    _initStateData();
    _ticker = createTicker(_onTick)..start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      reportScore(0);
      _updateStats();
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// Pure state reset — no host callbacks. Used by initState and by
  /// [_resetGame] which adds the host callback updates.
  void _initStateData() {
    _p1.reset();
    _p2.reset();
    _score1 = 0;
    _score2 = 0;
    _time1 = _maxTime;
    _time2 = _maxTime;
    _phase = _LBPhase.waiting;
    _lastEvent = 'Tap anywhere to start';
    _botDelayFrames = widget.level >= 3 ? 9 : (widget.level >= 2 ? 18 : 30);
    _botCooldown = 0;
  }

  void _resetGame() {
    _initStateData();
    reportScore(0);
    _updateStats();
  }

  _LBBlock _generateTreeBlock(int lastBranch) {
    int branch;
    if (lastBranch != 0 || _rng.nextDouble() < 0.3) {
      branch = lastBranch == 0
          ? (_rng.nextBool() ? 1 : -1)
          : lastBranch;
      if (_rng.nextDouble() < 0.5) branch = 0;
    } else {
      branch = _rng.nextInt(3) - 1;
    }
    var type = 'normal';
    if (branch == 0) {
      final r = _rng.nextDouble();
      if (r < 0.1) {
        type = '2x';
      } else if (r < 0.15) {
        type = 'time';
      }
    }
    final shape = _rng.nextInt(5);
    return _LBBlock(branch: branch, type: type, hits: 0, branchShape: shape);
  }

  /// Generates a tree block whose branch is GUARANTEED to be opposite
  /// the [lastSide] the player chopped. Prevents the unfair instant
  /// death where the new bottom block has a branch on the same side
  /// the player just committed to chopping.
  _LBBlock _generateSafeTreeBlock(int lastBranch, int lastSide) {
    // Roll a few times — if the candidate has a branch on `lastSide`,
    // reroll. Bounded so we never spin forever.
    for (var i = 0; i < 4; i++) {
      final candidate = _generateTreeBlock(lastBranch);
      if (candidate.branch != lastSide) return candidate;
    }
    // Last resort: force-clear.
    return _LBBlock(
      branch: -lastSide,
      type: 'normal',
      hits: 0,
      branchShape: _rng.nextInt(5),
    );
  }

  void _initTree(_LBPlayer p) {
    p.tree.clear();
    for (var i = 0; i < _treeHeight; i++) {
      if (i < 2) {
        p.tree.add(_LBBlock(branch: 0, type: 'normal', hits: 0, branchShape: 0));
      } else {
        p.tree.add(_generateTreeBlock(p.tree.last.branch));
      }
    }
  }

void _startGame() {
    if (_phase != _LBPhase.waiting) return;
    setState(() {
      _phase = _LBPhase.playing;
      _p1.elapsed = 0;
      _p2.elapsed = 0;
      _initTree(_p1);
      _initTree(_p2);
      _lastEvent = 'Chop!';
    });
    _updateStats();
  }

  void _onTick(Duration _) {
    if (_phase == _LBPhase.gameOver) {
      if (_ticker.isActive) _ticker.stop();
      return;
    }
    if (_phase != _LBPhase.playing) {
      return;
    }
    final elapsed = _p1.elapsed;
    final drain = 3.0 + elapsed * 0.1;
    bool bothDead = true;
    for (final p in [_p1, _p2]) {
      if (p.animTimer > 0) p.animTimer--;
      if (!p.dead) {
        p.time -= drain * (1 / 60);
        if (p.time <= 0) {
          p.time = 0;
          _killPlayer(p);
        }
      }
      for (final ft in List.of(p.floating)) {
        ft.y -= 3;
        ft.alpha -= 12;
        if (ft.alpha <= 0) p.floating.remove(ft);
      }
      if (p.dead) {
        p.deathProgress = min(1.0, p.deathProgress + 0.04);
        p.deathStarAngle += 3.0;
      } else {
        bothDead = false;
      }
    }
    if (_isAi && !_p2.dead) {
      _botCooldown--;
      if (_botCooldown <= 0) {
        _botChop();
        _botCooldown = _botDelayFrames;
        _botDelayFrames = max(4, _botDelayFrames - 1);
      }
    }
    if (bothDead) _finishGame();
    setState(() {});
    _updateStats();
  }

  void _botChop() {
    final bottom = _p2.tree.first;
    if (bottom.type == '2x' && bottom.hits == 0) {
      var safe = _p2.side;
      if (bottom.branch != 0) safe = -bottom.branch;
      _chopPlayer(_p2, safe);
    } else {
      final next = _p2.tree.length > 1 ? _p2.tree[1] : null;
      if (next != null && next.branch != 0) {
        _chopPlayer(_p2, -next.branch);
      } else {
        var safe = _p2.side;
        if (bottom.branch != 0) safe = -bottom.branch;
        _chopPlayer(_p2, safe);
      }
    }
  }

  void _chopPlayer(_LBPlayer p, int side) {
    if (p.dead) return;
    p.side = side;
    p.animTimer = 8;
    final bottom = p.tree.first;
    if (bottom.branch == side) {
      _killPlayer(p);
      return;
    }
    if (bottom.type == '2x' && bottom.hits == 0) {
      bottom.hits = 1;
      haptic(HapticFeedbackType.medium);
      return;
    }
    haptic(HapticFeedbackType.selection);
    if (p == _p1) {
      _score1++;
    } else {
      _score2++;
    }
    final score = p == _p1 ? _score1 : _score2;
    var addTime = 15.0 * exp(-score / 300.0);
    if (bottom.type == 'time') {
      p.floating.add(_FloatingText('+TIME!', side,
          color: const Color(0xFF32FF32)));
      addTime += 30.0;
    } else {
      p.floating.add(_FloatingText('+1', side, color: Colors.yellow));
    }
    p.time = min(_maxTime, p.time + addTime);
    p.tree.removeAt(0);
    final lastBranch = p.tree.isEmpty ? 0 : p.tree.last.branch;
    // Player just chopped `side` — never spawn a block whose branch
    // would instantly kill them on that same side.
    p.tree.add(_generateSafeTreeBlock(lastBranch, side));
    if (p.tree.first.branch == side) {
      _killPlayer(p);
    }
  }

  void _killPlayer(_LBPlayer p) {
    p.dead = true;
    haptic(HapticFeedbackType.heavy);
    _lastEvent =
        '${p == _p1 ? "P1" : (_isAi ? "Bot" : "P2")} crashed!';
  }

  void _finishGame() {
    if (_phase == _LBPhase.gameOver) return;
    setState(() => _phase = _LBPhase.gameOver);
    final winner = _score1 > _score2
        ? 1
        : (_score2 > _score1 ? 2 : 0);
    reportScore((_score1 + _score2) * 50 + (winner == 1 ? 200 : 0));
    haptic(HapticFeedbackType.heavy);
    reportGameOver();
  }

  void _updateStats() {
    final turn = _phase == _LBPhase.gameOver
        ? 'Game over — tap to retry'
        : (_phase == _LBPhase.waiting
            ? 'Tap anywhere to start'
            : 'P1 $_score1 · Bot $_score2');
    if (turn == _lastReportedStats) return;
    _lastReportedStats = turn;
    reportStats(turn);
  }

  // ─── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        // Desktop / web fallback only — touch is the primary control.
        if (event.logicalKey == LogicalKeyboardKey.space) {
          if (_phase == _LBPhase.waiting) {
            _startGame();
            return KeyEventResult.handled;
          }
          if (_phase == _LBPhase.gameOver) {
            _resetGame();
            return KeyEventResult.handled;
          }
        }
        if (_phase == _LBPhase.playing) {
          if (event.logicalKey == LogicalKeyboardKey.keyA ||
              event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _chopPlayer(_p1, -1);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.keyD ||
              event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _chopPlayer(_p1, 1);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        color: Colors.black,
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) {
                    final half = c.maxWidth / 2;
                    return Row(
                      children: [
                        SizedBox(
                          width: half,
                          height: c.maxHeight,
                          child: _buildPlayerPanel(_p1, half, c.maxHeight,
                              isLeft: true, score: _score1, time: _time1),
                        ),
                        SizedBox(
                          width: half,
                          height: c.maxHeight,
                          child: _buildPlayerPanel(_p2, half, c.maxHeight,
                              isLeft: false, score: _score2, time: _time2),
                        ),
                      ],
                    );
                  },
                ),
              ),
              _buildControls(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerPanel(
    _LBPlayer p,
    double w,
    double h, {
    required bool isLeft,
    required int score,
    required double time,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) {
        // Both panels feed input to P1 — the bot panel is just a
        // visual mirror, but it MUST also accept taps so the user
        // can chop by tapping either half of the screen.
        //
        // Translate the panel-local tap position to a screen-side:
        //   * left panel: left of panel = -1, right = +1 (1:1 mapping)
        //   * right panel: left of panel = right of screen = +1
        //                  (flip the sign)
        final localSide = d.localPosition.dx < w / 2 ? -1 : 1;
        final screenSide = isLeft ? localSide : -localSide;
        // Wait/retry/finish are global — any tap on either panel
        // works the same way.
        if (_phase == _LBPhase.waiting) {
          _startGame();
          return;
        }
        if (_phase == _LBPhase.gameOver) {
          _resetGame();
          return;
        }
        if (_phase == _LBPhase.playing) {
          _chopPlayer(_p1, screenSide);
        }
      },
      child: Container(
        color: _bg,
        child: CustomPaint(
          size: Size(w, h),
          painter: _LBPanelPainter(
            player: p,
            time: time,
            score: score,
            timeBlock: _timeBlock,
            ground: _ground,
            trunk: _trunk,
            trunkLine: _trunkLine,
            crack: _crack,
            timerFg: _timerFg,
            skin: _skin,
            isWaiting: _phase == _LBPhase.waiting,
            isGameOver: _phase == _LBPhase.gameOver,
            isPlayerSide: isLeft,
            panelWidth: w,
            panelHeight: h,
          ),
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
          // Difficulty picker — single-player only.
          ToggleButtons(
            isSelected: [
              _botDiff == _LBDifficulty.easy,
              _botDiff == _LBDifficulty.medium,
              _botDiff == _LBDifficulty.hard,
            ],
            onPressed: (i) {
              setState(() => _botDiff = _LBDifficulty.values[i]);
              _resetGame();
            },
            constraints: const BoxConstraints(minHeight: 32, minWidth: 50),
            borderRadius: BorderRadius.circular(8),
            color: Colors.white60,
            selectedColor: Colors.white,
            fillColor: _p2Color.withValues(alpha: 0.3),
            children: const [Text('Easy'), Text('Med'), Text('Hard')],
          ),
          const Spacer(),
          Text(
            _lastEvent,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _resetGame,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _LBPlayer {
  _LBPlayer({required this.side, required this.color, required this.shirt});
  int side;
  Color color;
  Color shirt;
  final List<_LBBlock> tree = [];
  double time = 100;
  int animTimer = 0;
  bool dead = false;
  double deathProgress = 0;
  double deathStarAngle = 0;
  double elapsed = 0;
  final List<_FloatingText> floating = [];

  void reset() {
    time = 100;
    animTimer = 0;
    dead = false;
    deathProgress = 0;
    deathStarAngle = 0;
    floating.clear();
    tree.clear();
  }
}

class _LBBlock {
  _LBBlock({
    required this.branch,
    required this.type,
    required this.hits,
    required this.branchShape,
  });
  int branch; // -1, 0, 1
  String type; // 'normal', '2x', 'time'
  int hits;
  int branchShape;
}

class _FloatingText {
  _FloatingText(this.text, this.side, {required this.color});
  String text;
  int side;
  Color color;
  double y = 0;
  int alpha = 255;
}

class _LBPanelPainter extends CustomPainter {
  _LBPanelPainter({
    required this.player,
    required this.time,
    required this.score,
    required this.timeBlock,
    required this.ground,
    required this.trunk,
    required this.trunkLine,
    required this.crack,
    required this.timerFg,
    required this.skin,
    required this.isWaiting,
    required this.isGameOver,
    required this.isPlayerSide,
    required this.panelWidth,
    required this.panelHeight,
  });

  final _LBPlayer player;
  final double time;
  final int score;
  final Color timeBlock;
  final Color ground;
  final Color trunk;
  final Color trunkLine;
  final Color crack;
  final Color timerFg;
  final Color skin;
  final bool isWaiting;
  final bool isGameOver;
  final bool isPlayerSide;
  final double panelWidth;
  final double panelHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final groundH = 100.0;
    canvas.drawRect(
      Rect.fromLTWH(0, size.height - groundH, size.width, groundH),
      Paint()..color = ground,
    );
    final blockW = 80.0;
    final blockH = 80.0;
    final centerX = size.width / 2;
    final baseY = size.height - groundH - blockH;
    for (var i = 0; i < player.tree.length; i++) {
      final block = player.tree[i];
      final y = baseY - (i * blockH);
      if (y < -blockH) break;
      final rect = Rect.fromLTWH(centerX - blockW / 2, y, blockW, blockH);
      var color = trunk;
      if (block.type == '2x') {
        color = const Color(0xFFC86432);
      } else if (block.type == 'time') {
        color = timeBlock;
      }
      canvas.drawRect(rect, Paint()..color = color);
      canvas.drawLine(
        Offset(rect.left + 15, rect.top),
        Offset(rect.left + 15, rect.bottom),
        Paint()
          ..color = trunkLine
          ..strokeWidth = 2,
      );
      canvas.drawLine(
        Offset(rect.right - 15, rect.top),
        Offset(rect.right - 15, rect.bottom),
        Paint()
          ..color = trunkLine
          ..strokeWidth = 2,
      );
      if (block.type == '2x' && block.hits == 1) {
        canvas.drawLine(
          Offset(centerX - 30, y + 20),
          Offset(centerX + 10, y + 40),
          Paint()
            ..color = crack
            ..strokeWidth = 3,
        );
        canvas.drawLine(
          Offset(centerX + 10, y + 40),
          Offset(centerX - 10, y + 70),
          Paint()
            ..color = crack
            ..strokeWidth = 3,
        );
      }
      if (block.type == 'time') {
        canvas.drawCircle(
          Offset(centerX, y + blockH / 2),
          15,
          Paint()..color = Colors.white,
        );
        canvas.drawLine(
          Offset(centerX, y + blockH / 2),
          Offset(centerX, y + blockH / 2 - 10),
          Paint()
            ..color = Colors.black
            ..strokeWidth = 2,
        );
        canvas.drawLine(
          Offset(centerX, y + blockH / 2),
          Offset(centerX + 8, y + blockH / 2),
          Paint()
            ..color = Colors.black
            ..strokeWidth = 2,
        );
      }
      if (block.branch != 0) {
        const bW = 120.0;
        Offset bStart;
        List<Offset> pts;
        if (block.branch == 1) {
          bStart = Offset(centerX + blockW / 2, y + 60);
          pts = switch (block.branchShape) {
            0 => [
                bStart,
                bStart + const Offset(bW, -20),
                bStart + const Offset(bW - 10, -50),
                bStart + const Offset(0, -40)
              ],
            1 => [
                bStart,
                bStart + const Offset(bW, 20),
                bStart + const Offset(bW - 30, -30),
                bStart + const Offset(0, -50)
              ],
            2 => [
                bStart,
                bStart + const Offset(bW, -40),
                bStart + const Offset(bW, -60),
                bStart + const Offset(0, -30)
              ],
            3 => [
                bStart,
                bStart + const Offset(bW - 40, 30),
                bStart + const Offset(bW, 0),
                bStart + const Offset(bW / 2, -50),
                bStart + const Offset(0, -40)
              ],
            _ => [
                bStart,
                bStart + const Offset(bW, -30),
                bStart + const Offset(bW - 20, -50),
                bStart + const Offset(0, -40)
              ],
          };
        } else {
          bStart = Offset(centerX - blockW / 2, y + 60);
          pts = switch (block.branchShape) {
            0 => [
                bStart,
                bStart - const Offset(bW, -20),
                bStart - const Offset(bW - 10, -50),
                bStart - const Offset(0, -40)
              ],
            1 => [
                bStart,
                bStart - const Offset(bW, 20),
                bStart - const Offset(bW - 30, -30),
                bStart - const Offset(0, -50)
              ],
            2 => [
                bStart,
                bStart - const Offset(bW, -40),
                bStart - const Offset(bW, -60),
                bStart - const Offset(0, -30)
              ],
            3 => [
                bStart,
                bStart - const Offset(bW - 40, 30),
                bStart - const Offset(bW, 0),
                bStart - const Offset(bW / 2, -50),
                bStart - const Offset(0, -40)
              ],
            _ => [
                bStart,
                bStart - const Offset(bW, -30),
                bStart - const Offset(bW - 20, -50),
                bStart - const Offset(0, -40)
              ],
          };
        }
        final path = Path()..moveTo(pts[0].dx, pts[0].dy);
        for (final p in pts.skip(1)) {
          path.lineTo(p.dx, p.dy);
        }
        path.close();
        canvas.drawPath(path, Paint()..color = trunk);
      }
    }
    final pX = player.side == 1
        ? centerX + (blockW / 2) + 35
        : centerX - (blockW / 2) - 35;
    final pY = size.height - groundH;
    if (!player.dead) {
      _drawLumberjack(canvas, pX, pY, player.side, player.animTimer > 0,
          player.shirt, skin);
    } else {
      _drawDeadLumberjack(canvas, pX, pY, player);
    }
    for (final ft in player.floating) {
      final tp = TextPainter(
        text: TextSpan(
          text: ft.text,
          style: TextStyle(
            color: ft.color.withValues(alpha: ft.alpha / 255),
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final fx = player.side == 1 ? centerX + 80 : centerX - 100;
      final fy = baseY + 40 + ft.y;
      tp.paint(canvas, Offset(fx, fy));
    }
    final scoreTp = TextPainter(
      text: TextSpan(
        text: '$score',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 36,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    scoreTp.paint(canvas, const Offset(20, 20));
    const timerW = 200.0;
    const timerH = 20.0;
    final timerX = size.width / 2 - timerW / 2;
    const timerY = 60.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(timerX, timerY, timerW, timerH),
        const Radius.circular(10),
      ),
      Paint()..color = const Color(0xFF323232),
    );
    final fillW = max(0.0, timerW * (time / 100.0));
    var tColor = timerFg;
    if (time < 25) {
      tColor = const Color(0xFFFF0000);
    } else if (time < 50) {
      tColor = const Color(0xFFFF8C00);
    }
    if (fillW > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(timerX, timerY, fillW, timerH),
          const Radius.circular(10),
        ),
        Paint()..color = tColor,
      );
    }

    // Overlay: WAITING — visible on BOTH panels so the player knows
    // to tap. Drives the start of the run from any panel tap.
    if (isWaiting) {
      _drawCenterOverlay(
        canvas,
        size,
        title: 'TAP TO START',
        subtitle: isPlayerSide
            ? 'Tap left / right half to chop'
            : 'Your opponent is the Bot',
        accent: const Color(0xFFFFD700),
      );
      _drawTapZones(canvas, size);
    }
    // Overlay: GAME OVER.
    if (isGameOver) {
      _drawCenterOverlay(
        canvas,
        size,
        title: player.dead ? 'GAME OVER' : 'YOU WIN!',
        subtitle: 'Tap to play again',
        accent: player.dead
            ? const Color(0xFFFF5252)
            : const Color(0xFF22C55E),
      );
    }
  }

  void _drawCenterOverlay(
    Canvas canvas,
    Size size, {
    required String title,
    required String subtitle,
    required Color accent,
  }) {
    // Dim background.
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xCC000000),
    );

    // Card.
    final cardW = min(size.width - 40, 320.0);
    final cardH = 150.0;
    final card = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: cardW,
      height: cardH,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(card, const Radius.circular(20)),
      Paint()..color = const Color(0xFF1E1E2E),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(card, const Radius.circular(20)),
      Paint()
        ..color = accent
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke,
    );

    // Title.
    final titlePainter = TextPainter(
      text: TextSpan(
        text: title,
        style: TextStyle(
          color: accent,
          fontSize: 26,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
          shadows: const [
            Shadow(blurRadius: 8, color: Color(0x88000000)),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    titlePainter.paint(
      canvas,
      Offset(
        card.center.dx - titlePainter.width / 2,
        card.top + 24,
      ),
    );

    // Subtitle.
    final subPainter = TextPainter(
      text: TextSpan(
        text: subtitle,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: cardW - 32);
    subPainter.paint(
      canvas,
      Offset(
        card.center.dx - subPainter.width / 2,
        card.top + 70,
      ),
    );

    // Tap hint icon.
    final iconY = card.bottom - 36;
    _drawTapIcon(
      canvas,
      card.center.dx - 30,
      iconY,
      size: 18,
      color: Colors.white,
    );
    final hintPainter = TextPainter(
      text: const TextSpan(
        text: 'TAP',
        style: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w900,
          letterSpacing: 2.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    hintPainter.paint(
      canvas,
      Offset(
        card.center.dx - hintPainter.width / 2 + 18,
        iconY - hintPainter.height / 2,
      ),
    );
  }

  void _drawTapIcon(
    Canvas canvas,
    double cx,
    double cy, {
    required double size,
    required Color color,
  }) {
    final hand = Path()
      ..moveTo(cx - size * 0.4, cy - size * 0.5)
      ..lineTo(cx - size * 0.4, cy + size * 0.4)
      ..lineTo(cx + size * 0.5, cy + size * 0.4)
      ..lineTo(cx + size * 0.5, cy - size * 0.1)
      ..lineTo(cx + size * 0.2, cy - size * 0.1)
      ..lineTo(cx + size * 0.2, cy - size * 0.5)
      ..close();
    canvas.drawPath(hand, Paint()..color = color);
  }

  void _drawTapZones(Canvas canvas, Size size) {
    // Subtle visual hints that the left and right halves are the
    // tap targets for chopping once the game starts.
    final w = size.width;
    final h = size.height;
    final zonePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, w / 2, h), zonePaint);
    canvas.drawRect(Rect.fromLTWH(w / 2, 0, w / 2, h), zonePaint);

    final leftPainter = TextPainter(
      text: const TextSpan(
        text: '← LEFT',
        style: TextStyle(
          color: Colors.white24,
          fontSize: 14,
          fontWeight: FontWeight.w900,
          letterSpacing: 2.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    leftPainter.paint(canvas, Offset(12, h - 32));

    final rightPainter = TextPainter(
      text: const TextSpan(
        text: 'RIGHT →',
        style: TextStyle(
          color: Colors.white24,
          fontSize: 14,
          fontWeight: FontWeight.w900,
          letterSpacing: 2.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    rightPainter.paint(
      canvas,
      Offset(w - rightPainter.width - 12, h - 32),
    );
  }

  void _drawLumberjack(Canvas canvas, double x, double y, int side,
      bool isAnimating, Color shirt, Color skin) {
    canvas.drawRect(
      Rect.fromLTWH(x - 8, y - 25, 6, 25),
      Paint()..color = const Color(0xFF323232),
    );
    canvas.drawRect(
      Rect.fromLTWH(x + 2, y - 25, 6, 25),
      Paint()..color = const Color(0xFF323232),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x - 15, y - 55, 30, 32),
        const Radius.circular(6),
      ),
      Paint()..color = shirt,
    );
    canvas.drawCircle(
      Offset(x, y - 65),
      14,
      Paint()..color = skin,
    );
    final beardPath = Path()
      ..moveTo(x - 14, y - 65)
      ..lineTo(x + 14, y - 65)
      ..lineTo(x + 5, y - 48)
      ..lineTo(x - 5, y - 48)
      ..close();
    canvas.drawPath(beardPath, Paint()..color = const Color(0xFF8B4513));
    canvas.drawCircle(Offset(x - 6, y - 70), 4, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(x + 6, y - 70), 4, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(x - 5, y - 70), 2,
        Paint()..color = const Color(0xFF1E1E1E));
    canvas.drawCircle(Offset(x + 7, y - 70), 2,
        Paint()..color = const Color(0xFF1E1E1E));
    final beaniePath = Path()
      ..moveTo(x - 12, y - 72)
      ..lineTo(x + 12, y - 72)
      ..lineTo(x, y - 85)
      ..close();
    canvas.drawPath(beaniePath, Paint()..color = const Color(0xFFC83232));
    canvas.drawCircle(Offset(x, y - 85), 4,
        Paint()..color = const Color(0xFFDCDCDC));
    Offset axeStart, axeEnd;
    if (isAnimating) {
      if (side == -1) {
        canvas.drawLine(Offset(x - 5, y - 45), Offset(x + 10, y - 35),
            Paint()..color = shirt..strokeWidth = 6);
        canvas.drawLine(Offset(x + 10, y - 35), Offset(x + 25, y - 25),
            Paint()..color = skin..strokeWidth = 5);
        axeStart = Offset(x, y - 40);
        axeEnd = Offset(x + 50, y - 15);
      } else {
        canvas.drawLine(Offset(x + 5, y - 45), Offset(x - 10, y - 35),
            Paint()..color = shirt..strokeWidth = 6);
        canvas.drawLine(Offset(x - 10, y - 35), Offset(x - 25, y - 25),
            Paint()..color = skin..strokeWidth = 5);
        axeStart = Offset(x, y - 40);
        axeEnd = Offset(x - 50, y - 15);
      }
    } else {
      if (side == -1) {
        canvas.drawLine(Offset(x - 5, y - 45), Offset(x - 20, y - 40),
            Paint()..color = shirt..strokeWidth = 6);
        canvas.drawLine(Offset(x - 20, y - 40), Offset(x - 25, y - 50),
            Paint()..color = skin..strokeWidth = 5);
        axeStart = Offset(x - 15, y - 30);
        axeEnd = Offset(x - 30, y - 75);
      } else {
        canvas.drawLine(Offset(x + 5, y - 45), Offset(x + 20, y - 40),
            Paint()..color = shirt..strokeWidth = 6);
        canvas.drawLine(Offset(x + 20, y - 40), Offset(x + 25, y - 50),
            Paint()..color = skin..strokeWidth = 5);
        axeStart = Offset(x + 15, y - 30);
        axeEnd = Offset(x + 30, y - 75);
      }
    }
    canvas.drawLine(axeStart, axeEnd,
        Paint()
          ..color = const Color(0xFF8B4513)
          ..strokeWidth = 5);
    final bladeX = axeEnd.dx;
    final bladeY = axeEnd.dy;
    final bladePath = Path();
    if (isAnimating) {
      if (side == -1) {
        bladePath
          ..moveTo(bladeX, bladeY - 15)
          ..lineTo(bladeX + 10, bladeY - 5)
          ..lineTo(bladeX + 5, bladeY + 15)
          ..lineTo(bladeX - 10, bladeY + 10)
          ..close();
      } else {
        bladePath
          ..moveTo(bladeX, bladeY - 15)
          ..lineTo(bladeX - 10, bladeY - 5)
          ..lineTo(bladeX - 5, bladeY + 15)
          ..lineTo(bladeX + 10, bladeY + 10)
          ..close();
      }
    } else {
      if (side == -1) {
        bladePath
          ..moveTo(bladeX, bladeY + 10)
          ..lineTo(bladeX - 15, bladeY + 15)
          ..lineTo(bladeX - 15, bladeY - 15)
          ..lineTo(bladeX, bladeY - 10)
          ..close();
      } else {
        bladePath
          ..moveTo(bladeX, bladeY + 10)
          ..lineTo(bladeX + 15, bladeY + 15)
          ..lineTo(bladeX + 15, bladeY - 15)
          ..lineTo(bladeX, bladeY - 10)
          ..close();
      }
    }
    canvas.drawPath(bladePath, Paint()..color = const Color(0xFFC0C0C0));
  }

  void _drawDeadLumberjack(Canvas canvas, double x, double y, _LBPlayer p) {
    canvas.save();
    canvas.translate(x, y);
    final progress = p.deathProgress;
    final fallAngle = sin(progress * pi / 2) * 90.0 * p.side;
    canvas.rotate(fallAngle);
    _drawLumberjack(canvas, 0, 0, p.side, false, p.shirt, skin);
    canvas.restore();
    if (progress > 0.5) {
      final starAlpha = ((progress - 0.5) * 2).clamp(0.0, 1.0);
      final headX = x;
      final headY = y - 65;
      for (var i = 0; i < 3; i++) {
        final angle = p.deathStarAngle + i * 120;
        final sx = headX + cos(angle * pi / 180) * 22;
        final sy = headY + sin(angle * pi / 180) * 12;
        _drawStar(canvas, sx, sy, 8, 3,
            Color.fromRGBO(255, 220, 0, starAlpha));
      }
    }
  }

  void _drawStar(
      Canvas canvas, double cx, double cy, double outerR, double innerR, Color color) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final angle = -pi / 2 + i * pi / 5;
      final r = i.isEven ? outerR : innerR;
      final px = cx + r * cos(angle);
      final py = cy + r * sin(angle);
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_LBPanelPainter old) =>
      old.time != time ||
      old.score != score ||
      old.timeBlock != timeBlock ||
      !identical(old.player.tree, player.tree) ||
      !identical(old.player.floating, player.floating) ||
      old.player.animTimer != player.animTimer ||
      old.player.side != player.side ||
      old.player.dead != player.dead ||
      old.isWaiting != isWaiting ||
      old.isGameOver != isGameOver ||
      old.isPlayerSide != isPlayerSide ||
      old.panelWidth != panelWidth ||
      old.panelHeight != panelHeight;
}
