import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../game_widgets.dart';
import '../mini_game.dart';
import '../widgets/game_flow_overlays.dart';

/// Jelly Jump — single-screen tap-to-thrust platformer in the
/// "Pool / Backgammon / Maze Escape" mini-game family.
///
/// Match the reference: side-view cartoon sky with rising platforms
/// and a bouncing jelly character. Tap to thrust upward when the
/// jelly lands on a platform. Reach height 20 to win.
///
/// Phases: `start → play → win → trophy`.
class JellyJumpGame extends MiniGame {
  const JellyJumpGame({super.key, required super.callbacks});

  @override
  State<JellyJumpGame> createState() => _JellyJumpGameState();
}

enum _JellyPhase { start, play, win, trophy }

class _Platform {
  _Platform(this.y, this.x, this.width);
  double y;
  double x;
  double width;
}

class _JellyJumpGameState extends MiniGameState<JellyJumpGame>
    with SingleTickerProviderStateMixin {
  static const double _gravity = 1100;
  static const double _jumpStrength = -560;
  static const double _maxBestHeight = 20;

  late final Ticker _ticker;
  final Random _rng = Random();

  double _bestHeight = 0;
  int _score = 0;
  _JellyPhase _phase = _JellyPhase.start;

  double _vy = 0;
  bool _onGround = false;
  double _groundY = 0;
  double _squash = 1.0;

  final List<_Platform> _platforms = [];
  Duration _last = Duration.zero;

  double _boardW = 0;
  double _boardH = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reportScore(_score);
      reportStats('Best 0  •  Target $_maxBestHeight');
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
      'Best ${_bestHeight.toStringAsFixed(1)}  •  Target $_maxBestHeight',
    );
  }

  void _onPlay() {
    setState(() {
      _phase = _JellyPhase.play;
      _score = 0;
      _bestHeight = 0;
      _platforms.clear();
      // Defer platform build to LayoutBuilder so we have valid
      // board width / height. _groundY is also reset there.
      _onGround = true;
      _vy = 0;
      _squash = 1.0;
      _last = Duration.zero;
      _groundY = 0;
    });
    _refreshHud();
  }

  void _onPlayAgain() {
    setState(() {
      _phase = _JellyPhase.start;
      _score = 0;
      _bestHeight = 0;
      _platforms.clear();
      _groundY = 0;
    });
    _refreshHud();
  }

  void _buildPlatforms() {
    _platforms.clear();
    if (_boardW <= 0 || _boardH <= 0) return;
    // Ground platform.
    _platforms.add(_Platform(_groundY, -100, _boardW + 200));
    for (var i = 0; i < 24; i++) {
      final y = _groundY - (i + 1) * 90 - _rng.nextDouble() * 40;
      final x = _rng.nextDouble() * (_boardW - 80);
      _platforms.add(_Platform(y, x, 70 + _rng.nextDouble() * 50));
    }
  }

  void _tick(Duration elapsed) {
    if (_phase != _JellyPhase.play) return;
    if (_boardW == 0 || _boardH == 0 || _groundY == 0) return;
    final dt = _last == Duration.zero
        ? 0.0
        : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dt <= 0) return;
    // Clamp dt — guards against huge jumps after a long pause.
    final sdt = dt.clamp(0.0, 0.05);
    setState(() {
      _vy += _gravity * sdt;
      _groundY -= _vy * sdt;
      // Best height tracking — convert ground rise into height climbed.
      final rise = -_groundY;
      _bestHeight = max(_bestHeight, rise);
      _squash = (_onGround ? 1.2 : 1.0) - (_vy.abs() / 1000);
      _squash = _squash.clamp(0.7, 1.4);
      // Generate new platforms above as we climb. Keep adding until
      // the top platform is well above the screen.
      var topPlatformY =
          _platforms.map((p) => p.y).reduce((a, b) => a < b ? a : b);
      while (topPlatformY > _groundY - _boardH) {
        final y = topPlatformY - 90 - _rng.nextDouble() * 40;
        final x = _rng.nextDouble() * (_boardW - 80);
        _platforms.add(_Platform(y, x, 70 + _rng.nextDouble() * 50));
        topPlatformY = y;
      }
      // Drop platforms far below.
      _platforms.removeWhere(
        (p) => p.y > _groundY + _boardH * 0.6,
      );
      // Land check.
      if (_vy > 0) {
        for (final p in _platforms) {
          final jellyY = _groundY - 25;
          if (jellyY >= p.y - 12 && jellyY <= p.y + 8 &&
              p.x <= _boardW / 2 && p.x + p.width >= _boardW / 2) {
            _groundY = p.y - 25;
            _vy = 0;
            _onGround = true;
            _squash = 1.3;
            break;
          }
        }
      } else {
        _onGround = false;
      }
      // Fall limit — game over only if the jelly drops well below
      // the bottom of the screen (it has clearly fallen off-screen).
      if (_groundY > _boardH + 60) {
        _endGame();
      }
    });
    _score = _bestHeight.round();
    _refreshHud();
    if (_bestHeight >= _maxBestHeight) {
      _endGame();
    }
  }

  void _jump() {
    if (_phase != _JellyPhase.play) return;
    if (!_onGround) return;
    _vy = _jumpStrength;
    _onGround = false;
    _squash = 0.7;
    haptic(HapticFeedbackType.medium);
  }

  void _endGame() {
    if (_phase != _JellyPhase.play) return;
    haptic(_bestHeight >= _maxBestHeight
        ? HapticFeedbackType.heavy
        : HapticFeedbackType.selection);
    reportScore(_score);
    reportStats(
      'Best ${_bestHeight.toStringAsFixed(1)}  •  Target $_maxBestHeight',
    );
    reportGameOver();
    setState(() {
      _phase = _bestHeight >= _maxBestHeight
          ? _JellyPhase.win
          : _JellyPhase.trophy;
    });
  }

  void _onContinueAfterWin() {
    setState(() {
      _phase = _JellyPhase.trophy;
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
                _boardW = c.maxWidth;
                _boardH = c.maxHeight;
                // Lazy-init the ground & platforms once we know the
                // real board size — keeps Play from racing the layout
                // pass and ending the game on the first frame.
                if (_groundY == 0) {
                  _groundY = _boardH - 80;
                  if (_phase == _JellyPhase.play) _buildPlatforms();
                }
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _jump,
                  child: CustomPaint(
                    painter: _JellyPainter(
                      groundY: _groundY,
                      platforms: _platforms,
                      boardW: _boardW,
                      boardH: _boardH,
                      squash: _squash,
                      onGround: _onGround,
                    ),
                    size: Size(_boardW, _boardH),
                  ),
                );
              },
            ),
          ),
        ),
        if (_phase == _JellyPhase.start)
          GameStartOverlay(
            title: 'JELLY JUMP',
            subtitle: 'Bounce higher\nand reach the top!',
            youScore: _bestHeight.round(),
            targetScore: _maxBestHeight.round(),
            instruction:
                'Tap when the jelly lands on a platform to bounce higher. Reach height 20 to win.',
            illustration: const BoyCharacter(pose: BoyPose.walking),
            onPlay: _onPlay,
            onBack: () => Navigator.of(context).maybePop(),
          ),
        if (_phase == _JellyPhase.win)
          GameWinOverlay(
            title: 'YOU WIN!',
            subtitle: 'TOP REACHED!',
            scoreValue: _bestHeight.round(),
            scoreLabel: 'Best Height',
            statRows: [
              ('Score', '$_score'),
              ('Target', '${_maxBestHeight.round()}'),
            ],
            onContinue: _onContinueAfterWin,
          ),
        if (_phase == _JellyPhase.trophy)
          GameTrophyOverlay(
            iconData: Icons.emoji_events_rounded,
            iconGradient: const [Color(0xFFFCD34D), Color(0xFFF59E0B)],
            title: _bestHeight >= _maxBestHeight
                ? 'Great Job!'
                : 'Keep Going!',
            subtitle: _bestHeight >= _maxBestHeight
                ? 'You reached the target height.'
                : 'Try again — bounce higher!',
            score: _score,
            statRows: [
              ('Best', _bestHeight.toStringAsFixed(1)),
              ('Score', '$_score'),
              ('Target', '${_maxBestHeight.round()}'),
            ],
            onPlayAgain: _onPlayAgain,
            onBack: () => Navigator.of(context).maybePop(),
          ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// Painter
// ────────────────────────────────────────────────────────────────────

class _JellyPainter extends CustomPainter {
  _JellyPainter({
    required this.groundY,
    required this.platforms,
    required this.boardW,
    required this.boardH,
    required this.squash,
    required this.onGround,
  });

  final double groundY;
  final List<_Platform> platforms;
  final double boardW;
  final double boardH;
  final double squash;
  final bool onGround;

  static const _skyTop = Color(0xFFBFDBFE);
  static const _skyBottom = Color(0xFFE0F2FE);
  static const _platform = Color(0xFFEC4899);
  static const _platformShadow = Color(0xFF9D174D);
  static const _jelly = Color(0xFFA855F7);
  static const _jellyShadow = Color(0xFF6B21A8);

  @override
  void paint(Canvas canvas, Size size) {
    // Sky.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_skyTop, _skyBottom],
        ).createShader(Offset.zero & size),
    );

    // Clouds.
    final cloud = Paint()..color = Colors.white.withValues(alpha: 0.8);
    canvas.drawCircle(Offset(size.width * 0.2, size.height * 0.15), 30, cloud);
    canvas.drawCircle(Offset(size.width * 0.65, size.height * 0.08), 22, cloud);
    canvas.drawCircle(Offset(size.width * 0.85, size.height * 0.18), 26, cloud);

    // Camera offset — keep the jelly near the lower-middle of the
    // screen. The "ground" rises as the player climbs.
    final cameraY = size.height * 0.6;

    // Platforms (in world space).
    for (final p in platforms) {
      final screenY = cameraY - (p.y - groundY);
      if (screenY < -20 || screenY > size.height + 20) continue;
      final rect = Rect.fromLTWH(p.x, screenY - 6, p.width, 12);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        Paint()..color = _platform,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        Paint()
          ..color = _platformShadow
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    }

    // Jelly character.
    final cx = size.width / 2;
    final cy = cameraY;
    final baseR = 26.0;
    final rx = baseR * squash;
    final ry = baseR * (2 - squash);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy + 2), width: rx * 2, height: ry * 2),
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2),
      Paint()..color = _jelly,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2),
      Paint()
        ..color = _jellyShadow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    // Face.
    final eyeOffset = squash > 1 ? 1.0 : -1.0;
    canvas.drawCircle(
      Offset(cx - baseR * 0.35, cy - 2 + eyeOffset),
      3,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      Offset(cx + baseR * 0.35, cy - 2 + eyeOffset),
      3,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      Offset(cx - baseR * 0.35 + 1, cy - 2 + eyeOffset),
      1.6,
      Paint()..color = Colors.black,
    );
    canvas.drawCircle(
      Offset(cx + baseR * 0.35 + 1, cy - 2 + eyeOffset),
      1.6,
      Paint()..color = Colors.black,
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(cx, cy + 6),
        width: baseR * 0.8,
        height: baseR * 0.6,
      ),
      0.2,
      2.7,
      false,
      Paint()
        ..color = Colors.black87
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_JellyPainter old) =>
      old.groundY != groundY ||
      old.platforms != platforms ||
      old.squash != squash ||
      old.onGround != onGround;
}
