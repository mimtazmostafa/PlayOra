import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../game_player/widgets/confetti_shower.dart';
import '../game_widgets.dart';
import '../mini_game.dart';

/// Cricket Battle — 12-ball / 3-wicket innings on a 3D-perspective
/// stadium pitch. The bowler runs in from the top of the canvas and
/// releases a red ball that travels down the tan pitch strip toward
/// the batsman in the foreground. A cream "tap zone" sits on the
/// pitch — tap when the ball passes through it.
///
/// Scoring follows the reference: the closer the ball's progress to
/// the centre of the tap zone when the player taps, the bigger the
/// shot. Six windows of tolerance (six / four / two / one / dot /
/// wicket) keep the mechanic forgiving without removing timing.
///
/// Innings end after 12 balls or 3 wickets. If the player crosses the
/// 50-run target, the trophy screen plays ("Great Job!"); otherwise
/// the "Keep Going!" hint screen shows.
class CricketBattingGame extends MiniGame {
  const CricketBattingGame({super.key, required super.callbacks});

  @override
  State<CricketBattingGame> createState() => _State();
}

/// Phases the innings walks through. The painter only animates the
/// ball in [bowl]; [start] / [result] / [out] / [over] / [keepGoing]
/// each show a themed overlay that pauses gameplay.
enum _Phase {
  start,
  bowl,
  result,
  out,
  over,
  keepGoing,
}

/// Result of a single swing.
enum _ShotKind { dot, one, two, four, six, wicket }

class _State extends MiniGameState<CricketBattingGame> {
  static const int _maxBalls = 12;
  static const int _maxWickets = 3;
  static const int _target = 50;

  /// Position of the tap-zone centre along the pitch (0 = bowler's
  /// end, 1 = past the batsman's crease). 0.65 sits comfortably above
  /// the batsman so the ball visibly passes through it.
  static const double _zoneCentre = 0.65;

  int _ballsBowled = 0;
  int _runs = 0;
  int _wickets = 0;
  _Phase _phase = _Phase.start;

  /// 0..1 — how far the ball has travelled down the pitch.
  double _ballProgress = 0;
  double _ballSpeed = 0.55;
  Timer? _timer;
  final math.Random _rng = math.Random();

  _ShotKind _lastKind = _ShotKind.dot;

  /// Score reported to the host HUD — derived from runs so it can't
  /// drift out of sync.
  int get _score => _runs * 10;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reportScore(_score);
      reportStats('Runs 0  •  W 0  •  Ball 0/$_maxBalls');
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  int get _ballsLeft => _maxBalls - _ballsBowled;

  void _bowl() {
    _ballsBowled++;
    _phase = _Phase.bowl;
    _ballProgress = 0;
    // Randomise speed so consecutive balls feel different — 0.45
    // progress/s (slow) up to 0.75 progress/s (fast).
    _ballSpeed = 0.45 + _rng.nextDouble() * 0.30;
    _refreshHud();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 16), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _ballProgress += _ballSpeed * 0.016;
      });
      if (_ballProgress >= 1.05) {
        t.cancel();
        // Ball passed the batsman without a swing — dot ball, no
        // wicket penalty (the wicket only triggers from a mistimed
        // swing).
        _onBallPassed();
      }
    });
  }

  /// Called when the ball reaches the batsman's end without a swing.
  void _onBallPassed() {
    _lastKind = _ShotKind.dot;
    haptic(HapticFeedbackType.light);
    _advanceAfterShot();
  }

  void _swing() {
    if (_phase != _Phase.bowl) return;
    _timer?.cancel();

    final delta = (_ballProgress - _zoneCentre).abs();
    final kind = _resolveShot(delta);
    final runs = _runsFor(kind);
    _lastKind = kind;

    switch (kind) {
      case _ShotKind.six:
      case _ShotKind.four:
        haptic(HapticFeedbackType.medium);
        break;
      case _ShotKind.two:
      case _ShotKind.one:
        haptic(HapticFeedbackType.light);
        break;
      case _ShotKind.dot:
        haptic(HapticFeedbackType.light);
        break;
      case _ShotKind.wicket:
        haptic(HapticFeedbackType.heavy);
        break;
    }

    _runs += runs;
    if (kind == _ShotKind.wicket) _wickets++;
    _advanceAfterShot();
  }

  _ShotKind _resolveShot(double delta) {
    if (delta <= 0.04) return _ShotKind.six;
    if (delta <= 0.10) return _ShotKind.four;
    if (delta <= 0.18) return _ShotKind.two;
    if (delta <= 0.26) return _ShotKind.one;
    if (delta <= 0.34) return _ShotKind.dot;
    return _ShotKind.wicket;
  }

  int _runsFor(_ShotKind kind) {
    switch (kind) {
      case _ShotKind.six:
        return 6;
      case _ShotKind.four:
        return 4;
      case _ShotKind.two:
        return 2;
      case _ShotKind.one:
        return 1;
      case _ShotKind.dot:
      case _ShotKind.wicket:
        return 0;
    }
  }

  /// Walks from the live swing into the post-shot overlay, or straight
  /// into an end-of-innings overlay if the innings is over.
  void _advanceAfterShot() {
    _phase = _Phase.result;
    _refreshHud();
    if (mounted) setState(() {});
  }

  void _onContinueAfterResult() {
    if (_wickets >= _maxWickets) {
      _setPhase(_Phase.out);
      return;
    }
    if (_ballsBowled >= _maxBalls) {
      _setPhase(_runs >= _target ? _Phase.over : _Phase.keepGoing);
      // Host GameContainerScreen owns the game-over overlay; report
      // here so it fires once the innings is decided.
      reportGameOver();
      return;
    }
    _bowl();
  }

  void _setPhase(_Phase p) {
    setState(() => _phase = p);
  }

  void _refreshHud() {
    reportScore(_score);
    reportStats(
      'Runs $_runs  •  W $_wickets  •  Ball $_ballsBowled/$_maxBalls',
    );
  }

  void _restart() {
    _timer?.cancel();
    setState(() {
      _ballsBowled = 0;
      _runs = 0;
      _wickets = 0;
      _phase = _Phase.start;
      _ballProgress = 0;
      _ballSpeed = 0.55;
    });
    reportScore(0);
    reportStats('Runs 0  •  W 0  •  Ball 0/$_maxBalls');
  }

  /// True when the gameplay surface (not an overlay) should consume
  /// taps. The result/out/over overlays handle their own buttons.
  bool get _isLiveTap => _phase == _Phase.bowl;

  void _onSurfaceTap() {
    if (_phase == _Phase.bowl) _swing();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _isLiveTap ? _onSurfaceTap : null,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _CricketScenePainter(
                  ballProgress: _ballProgress,
                  phase: _phase,
                  ballsLeft: _ballsLeft,
                  runs: _runs,
                  wickets: _wickets,
                  zoneCentre: _zoneCentre,
                ),
                size: Size.infinite,
              ),
            ),
          ),
        ),
        if (_phase == _Phase.start) _StartOverlay(onPlay: _bowl),
        if (_phase == _Phase.result)
          _ShotResultOverlay(
            kind: _lastKind,
            runsTotal: _runs,
            wickets: _wickets,
            ballsLeft: _ballsLeft,
            onContinue: _onContinueAfterResult,
          ),
        if (_phase == _Phase.out)
          _WicketOverlay(
            runs: _runs,
            wickets: _wickets,
            onContinue: () {
              // After the wicket screen we drop straight to the
              // trophy/keep-going judgment — the user has already
              // seen the "You're out!" reveal.
              _setPhase(
                _runs >= _target ? _Phase.over : _Phase.keepGoing,
              );
              reportGameOver();
            },
          ),
        if (_phase == _Phase.over)
          _GameOverOverlay(
            kind: _GameOverKind.trophy,
            runs: _runs,
            wickets: _wickets,
            ballsBowled: _ballsBowled,
            target: _target,
            onPlayAgain: _restart,
            onBack: () => Navigator.of(context).maybePop(),
          ),
        if (_phase == _Phase.keepGoing)
          _GameOverOverlay(
            kind: _GameOverKind.keepGoing,
            runs: _runs,
            wickets: _wickets,
            ballsBowled: _ballsBowled,
            target: _target,
            onPlayAgain: _restart,
            onBack: () => Navigator.of(context).maybePop(),
          ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// Scene painter
// ────────────────────────────────────────────────────────────────────

class _CricketScenePainter extends CustomPainter {
  _CricketScenePainter({
    required this.ballProgress,
    required this.phase,
    required this.ballsLeft,
    required this.runs,
    required this.wickets,
    required this.zoneCentre,
  });

  final double ballProgress;
  final _Phase phase;
  final int ballsLeft;
  final int runs;
  final int wickets;
  final double zoneCentre;

  // ── Palette ────────────────────────────────────────────────────────
  static const _skyTop = Color(0xFF7DD3FC);
  static const _skyMid = Color(0xFFBAE6FD);
  static const _skyHorizon = Color(0xFFE0F2FE);
  static const _crowdBand = Color(0xCC1E3A5F);
  static const _crowdHead1 = Color(0xFFFFC837);
  static const _crowdHead2 = Color(0xFFFF6584);
  static const _crowdHead3 = Color(0xFF4ADE80);
  static const _floodlightWhite = Color(0xFFFAFAFA);
  static const _floodlightGlow = Color(0xFFFFD54F);
  static const _outfieldLight = Color(0xFF86EFAC);
  static const _outfieldDark = Color(0xFF22C55E);
  static const _pitchTan = Color(0xFFD4A574);
  static const _pitchTanDark = Color(0xFFB98A5A);
  static const _crease = Colors.white;
  static const _zoneFill = Color(0xFFFEF3C7);
  static const _zoneBorder = Color(0xFFFCD34D);
  static const _zoneBorderDim = Color(0xFFFACC15);

  // Batsman palette (warm blue uniform + cream pads).
  static const _jersey = Color(0xFF1E3A8A);
  static const _jerseyShadow = Color(0xFF0F1E5C);
  static const _pad = Color(0xFFF1E2C0);
  static const _helmet = Color(0xFFE2E8F0);
  static const _skin = Color(0xFFF5C9A0);
  static const _bat = Color(0xFFE8C58A);
  static const _batStripe = Color(0xFF6F4F1F);

  // Bowler palette (red uniform).
  static const _bowlerShirt = Color(0xFFDC2626);
  static const _bowlerPants = Color(0xFF1F2937);
  static const _bowlerCap = Color(0xFF7F1D1D);

  // Ball.
  static const _ballRed = Color(0xFFEF4444);

  // ── Reusable paints (allocated once, used per frame) ───────────────
  // Ball.
  static final Paint _ballBodyPaint = Paint()..color = _ballRed;
  static final Paint _ballSeamPaint = Paint()
    ..color = Colors.white.withValues(alpha: 0.7)
    ..strokeWidth = 1.5;
  static final Paint _ballShadowPaint = Paint()
    ..shader = const RadialGradient(
      colors: <Color>[
        Color(0x59000000),
        Color(0x00000000),
      ],
      radius: 0.6,
    ).createShader(const Rect.fromLTWH(-14, -10, 28, 20));

  // Sky / outfield / pitch.
  static final Paint _crowdBandPaint = Paint()..color = _crowdBand;
  static final Paint _crowdDotPaint = Paint();
  static final Paint _floodlightTowerPaint = Paint()
    ..color = _floodlightWhite;
  static final Paint _floodlightCorePaint = Paint()
    ..color = _floodlightGlow.withValues(alpha: 0.95);
  static final Paint _floodlightHaloPaint = Paint()
    ..color = _floodlightGlow.withValues(alpha: 0.35);
  static final Paint _pitchPaint = Paint()..color = _pitchTan;
  static final Paint _pitchSeamPaint = Paint()
    ..color = _pitchTanDark.withValues(alpha: 0.45)
    ..strokeWidth = 1.4;
  static final Paint _creasePaint = Paint()
    ..color = _crease
    ..strokeWidth = 2.0;
  static final Paint _popPaint = Paint()
    ..color = _crease
    ..strokeWidth = 2.0;
  static final Paint _stumpPaint = Paint()
    ..color = _crease
    ..strokeWidth = 2.2;
  static final Paint _bailPaint = Paint()
    ..color = _crease
    ..strokeWidth = 1.6;
  static final Paint _zoneFillPaint = Paint()..color = _zoneFill;
  static final Paint _zoneLiveBorderPaint = Paint()
    ..color = _zoneBorder
    ..strokeWidth = 2.5
    ..style = PaintingStyle.stroke;
  static final Paint _zoneDimBorderPaint = Paint()
    ..color = _zoneBorderDim
    ..strokeWidth = 2.5
    ..style = PaintingStyle.stroke;
  static final Paint _zoneBallMarkerPaint = Paint()
    ..color = Colors.white.withValues(alpha: 0.85)
    ..strokeWidth = 1.6;
  static final Paint _zoneCenterMarkerPaint = Paint()
    ..color = _zoneBorder
    ..strokeWidth = 1.4;

  // Bowler.
  static final Paint _bowlerPantsPaint = Paint()..color = _bowlerPants;
  static final Paint _bowlerShirtPaint = Paint()..color = _bowlerShirt;
  static final Paint _bowlerHeadPaint = Paint()..color = _skin;
  static final Paint _bowlerCapPaint = Paint()..color = _bowlerCap;
  static final Paint _bowlerArmPaint = Paint()
    ..color = _bowlerShirt
    ..strokeWidth = 1
    ..strokeCap = StrokeCap.round;

  // Batsman.
  static final Paint _padPaint = Paint()..color = _pad;
  static final Paint _padOutlinePaint = Paint()
    ..color = _jerseyShadow
    ..strokeWidth = 1.5
    ..style = PaintingStyle.stroke;
  static final Paint _jerseyPaint = Paint()..color = _jersey;
  static final Paint _jerseyShadowPaint = Paint()
    ..color = _jerseyShadow.withValues(alpha: 0.7);
  static final Paint _armPaint = Paint()
    ..color = _jersey
    ..strokeCap = StrokeCap.round;
  static final Paint _handPaint = Paint()..color = _skin;
  static final Paint _batHandlePaint = Paint()..color = _batStripe;
  static final Paint _batBladePaint = Paint()..color = _bat;
  static final Paint _batEdgePaint = Paint()
    ..color = Colors.white.withValues(alpha: 0.5)
    ..strokeWidth = 1.2;
  static final Paint _helmetPaint = Paint()..color = _helmet;
  static final Paint _facePaint = Paint()..color = _skin;
  static final Paint _grillePaint = Paint()
    ..color = _jerseyShadow
    ..strokeWidth = 1.0;
  static final Paint _helmetRimPaint = Paint()
    ..color = _jerseyShadow
    ..strokeWidth = 1.5
    ..style = PaintingStyle.stroke;

  // HUD chips removed — host GameContainerScreen paints the score and
  // stats chips on its own HUD bar.

  /// Deterministic RNG for the crowd-head pattern — re-using one
  /// instance avoids per-frame GC churn.
  static final math.Random _crowdRng = math.Random(7);
  static const _crowdHeads = <Color>[_crowdHead1, _crowdHead2, _crowdHead3];
  static const _crowdHeadCount = 64;
  static const _crowdHeadRadius = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    _drawSky(canvas, size);
    _drawCrowd(canvas, size);
    _drawFloodlights(canvas, size);
    _drawOutfield(canvas, size);
    _drawPitch(canvas, size);
    _drawStumpsAndCreases(canvas, size);
    _drawTapZone(canvas, size);
    _drawBowler(canvas, size);
    _drawBatsman(canvas, size);
    _drawBall(canvas, size);
    // Host GameContainerScreen paints the score / stats chips on its
    // own HUD bar, so the in-painter HUD pills are removed.
  }

  // ── Sky ────────────────────────────────────────────────────────────
  void _drawSky(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height * 0.55);
    final shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [_skyTop, _skyMid, _skyHorizon],
      stops: [0.0, 0.55, 1.0],
    ).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = shader);
  }

  // ── Crowd silhouette along the horizon ─────────────────────────────
  void _drawCrowd(Canvas canvas, Size size) {
    final bandTop = size.height * 0.40;
    final bandHeight = size.height * 0.12;
    canvas.drawRect(
      Rect.fromLTWH(0, bandTop, size.width, bandHeight),
      _crowdBandPaint,
    );
    // Sprinkle of head-shaped circles in three jersey colours so the
    // band reads as "people", not a flat strip. Positions are
    // deterministic via [_crowdRng] so layout doesn't shift.
    for (var i = 0; i < _crowdHeadCount; i++) {
      final x = _crowdRng.nextDouble() * size.width;
      final y = bandTop + 2 + _crowdRng.nextDouble() * (bandHeight - 6);
      _crowdDotPaint.color =
          _crowdHeads[_crowdRng.nextInt(_crowdHeads.length)];
      canvas.drawCircle(
        Offset(x, y),
        _crowdHeadRadius,
        _crowdDotPaint,
      );
    }
  }

  // ── Two floodlight towers, mirrored left/right ─────────────────────
  void _drawFloodlights(Canvas canvas, Size size) {
    final baseY = size.height * 0.38;
    final towerH = size.height * 0.18;
    final towerW = size.width * 0.022;
    _floodlightTowerPaint.strokeWidth = towerW;
    final leftX = size.width * 0.10;
    final rightX = size.width * 0.90;
    for (final x in [leftX, rightX]) {
      canvas.drawLine(
        Offset(x, baseY),
        Offset(x, baseY - towerH),
        _floodlightTowerPaint,
      );
      canvas.drawCircle(
        Offset(x, baseY - towerH),
        towerW * 1.6,
        _floodlightCorePaint,
      );
      canvas.drawCircle(
        Offset(x, baseY - towerH),
        towerW * 2.6,
        _floodlightHaloPaint,
      );
    }
  }

  // ── Outfield ellipse ──────────────────────────────────────────────
  void _drawOutfield(Canvas canvas, Size size) {
    final fieldTop = size.height * 0.45;
    final fieldRect = Rect.fromLTWH(
      -size.width * 0.1,
      fieldTop,
      size.width * 1.2,
      size.height * 0.6,
    );
    final shader = const RadialGradient(
      center: Alignment(0, 0.2),
      radius: 0.95,
      colors: [_outfieldLight, _outfieldDark],
    ).createShader(fieldRect);
    canvas.drawOval(fieldRect, Paint()..shader = shader);
  }

  // ── Pitch strip (slightly tapered for perspective) ────────────────
  void _drawPitch(Canvas canvas, Size size) {
    final topY = size.height * 0.55;
    final bottomY = size.height * 0.97;
    final topW = size.width * 0.46;
    final bottomW = size.width * 0.62;
    final cx = size.width * 0.5;
    final path = Path()
      ..moveTo(cx - topW / 2, topY)
      ..lineTo(cx + topW / 2, topY)
      ..lineTo(cx + bottomW / 2, bottomY)
      ..lineTo(cx - bottomW / 2, bottomY)
      ..close();
    canvas.drawPath(path, _pitchPaint);
    canvas.drawLine(
      Offset(cx, topY + 4),
      Offset(cx, bottomY - 4),
      _pitchSeamPaint,
    );
  }

  // ── Crease lines + stumps at both ends ─────────────────────────────
  void _drawStumpsAndCreases(Canvas canvas, Size size) {
    final cx = size.width * 0.5;
    canvas.drawLine(
      Offset(size.width * 0.22, size.height * 0.92),
      Offset(size.width * 0.78, size.height * 0.92),
      _creasePaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.30, size.height * 0.60),
      Offset(size.width * 0.70, size.height * 0.60),
      _creasePaint,
    );

    void drawPop(double x, double y) {
      canvas.drawLine(Offset(x, y - 4), Offset(x, y + 4), _popPaint);
    }

    for (final x in [size.width * 0.27, size.width * 0.73]) {
      drawPop(x, size.height * 0.90);
    }
    for (final x in [size.width * 0.33, size.width * 0.67]) {
      drawPop(x, size.height * 0.62);
    }

    void drawStumps(double baseY, double scale) {
      final stumpH = size.height * 0.04 * scale;
      for (final xOff in [-8.0, 0.0, 8.0]) {
        canvas.drawLine(
          Offset(cx + xOff, baseY - stumpH),
          Offset(cx + xOff, baseY),
          _stumpPaint,
        );
      }
      canvas.drawLine(
        Offset(cx - 8, baseY - stumpH),
        Offset(cx + 8, baseY - stumpH),
        _bailPaint,
      );
    }

    drawStumps(size.height * 0.60, 0.8);
    drawStumps(size.height * 0.92, 1.0);
  }

  // ── Tap zone (cream/yellow rectangle on the pitch) ─────────────────
  void _drawTapZone(Canvas canvas, Size size) {
    final pitchTopY = size.height * 0.55;
    final pitchBottomY = size.height * 0.97;
    final pitchHeight = pitchBottomY - pitchTopY;
    final zoneCenterY = pitchTopY + pitchHeight * zoneCentre;
    final zoneH = pitchHeight * 0.18;
    final zoneW = size.width * 0.30;
    final rect = Rect.fromLTWH(
      size.width * 0.5 - zoneW / 2,
      zoneCenterY - zoneH / 2,
      zoneW,
      zoneH,
    );
    canvas.drawRect(rect, _zoneFillPaint);
    final live = phase == _Phase.bowl;
    canvas.drawRect(
      rect.inflate(2),
      live ? _zoneLiveBorderPaint : _zoneDimBorderPaint,
    );
    if (!live) return;
    // Ball-progress and centre markers — only painted during the live
    // bowl phase so the rest of the screen stays quiet.
    final ballY = _ballScreenY(size);
    canvas.drawLine(
      Offset(rect.left, ballY),
      Offset(rect.right, ballY),
      _zoneBallMarkerPaint,
    );
    canvas.drawLine(
      Offset(rect.left, zoneCenterY),
      Offset(rect.right, zoneCenterY),
      _zoneCenterMarkerPaint,
    );
  }

  // ── Bowler (red uniform) at the bowling crease ─────────────────────
  void _drawBowler(Canvas canvas, Size size) {
    final cx = size.width * 0.5;
    final feetY = size.height * 0.60;
    final unit = size.width * 0.018;

    canvas.drawRect(
      Rect.fromLTWH(cx - unit * 0.6, feetY - unit * 1.6, unit * 0.5, unit * 1.6),
      _bowlerPantsPaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(cx + unit * 0.1, feetY - unit * 1.4, unit * 0.5, unit * 1.4),
      _bowlerPantsPaint,
    );
    final torso = Rect.fromLTWH(
      cx - unit * 0.7,
      feetY - unit * 3.0,
      unit * 1.4,
      unit * 1.6,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(torso, Radius.circular(unit * 0.25)),
      _bowlerShirtPaint,
    );
    final head = Offset(cx, feetY - unit * 3.5);
    canvas.drawCircle(head, unit * 0.55, _bowlerHeadPaint);
    canvas.drawArc(
      Rect.fromCircle(center: head, radius: unit * 0.6),
      math.pi,
      math.pi,
      true,
      _bowlerCapPaint,
    );
    _bowlerArmPaint.strokeWidth = unit * 0.35;
    canvas.drawLine(
      Offset(cx - unit * 0.4, feetY - unit * 2.8),
      Offset(cx - unit * 0.9, feetY - unit * 3.6),
      _bowlerArmPaint,
    );
  }

  // ── Batsman (blue uniform, foreground) ─────────────────────────────
  void _drawBatsman(Canvas canvas, Size size) {
    final cx = size.width * 0.5;
    final feetY = size.height * 0.95;
    final unit = size.width * 0.032;
    final padRadius = Radius.circular(unit * 0.18);

    final frontLegRect = Rect.fromLTWH(
      cx - unit * 0.9,
      feetY - unit * 1.7,
      unit * 0.55,
      unit * 1.7,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(frontLegRect, padRadius),
      _padPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(frontLegRect, padRadius),
      _padOutlinePaint,
    );
    final backLegRect = Rect.fromLTWH(
      cx + unit * 0.15,
      feetY - unit * 1.45,
      unit * 0.5,
      unit * 1.45,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(backLegRect, padRadius),
      _padPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(backLegRect, padRadius),
      _padOutlinePaint,
    );

    final bodyTop = feetY - unit * 3.4;
    final bodyRect = Rect.fromLTWH(
      cx - unit * 0.55,
      bodyTop,
      unit * 1.1,
      unit * 1.4,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, Radius.circular(unit * 0.25)),
      _jerseyPaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        bodyRect.left,
        bodyRect.top,
        bodyRect.width * 0.35,
        bodyRect.height,
      ),
      _jerseyShadowPaint,
    );

    _armPaint.strokeWidth = unit * 0.35;
    canvas.drawLine(
      Offset(cx - unit * 0.15, bodyTop + unit * 0.36),
      Offset(cx - unit * 1.1, bodyTop + unit * 0.84),
      _armPaint,
    );
    canvas.drawCircle(
      Offset(cx - unit * 1.1, bodyTop + unit * 0.84),
      unit * 0.22,
      _handPaint,
    );
    canvas.drawLine(
      Offset(cx + unit * 0.15, bodyTop + unit * 0.36),
      Offset(cx + unit * 0.55, bodyTop - unit * 0.10),
      _armPaint,
    );
    canvas.drawCircle(
      Offset(cx + unit * 0.55, bodyTop - unit * 0.10),
      unit * 0.22,
      _handPaint,
    );

    final batGrip = Offset(cx + unit * 0.55, bodyTop - unit * 0.10);
    final bladeTip = Offset(cx - unit * 1.55, bodyTop + unit * 1.40);
    canvas.save();
    canvas.translate(batGrip.dx, batGrip.dy);
    final batDx = bladeTip.dx - batGrip.dx;
    final batDy = bladeTip.dy - batGrip.dy;
    canvas.rotate(math.atan2(batDy, batDx));
    final batLength = math.sqrt(batDx * batDx + batDy * batDy);
    final batWidth = unit * 0.42;
    final handleLen = batLength * 0.4;
    final bladeLen = batLength * 0.6;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, -batWidth * 0.22, handleLen, batWidth * 0.44),
        Radius.circular(batWidth * 0.15),
      ),
      _batHandlePaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(handleLen, -batWidth * 0.6, bladeLen, batWidth * 1.2),
        Radius.circular(batWidth * 0.2),
      ),
      _batBladePaint,
    );
    canvas.drawLine(
      Offset(handleLen + 2, -batWidth * 0.55),
      Offset(handleLen + bladeLen - 2, -batWidth * 0.55),
      _batEdgePaint,
    );
    canvas.restore();

    final headCenter = Offset(cx + unit * 0.05, bodyTop - unit * 0.55);
    canvas.drawCircle(headCenter, unit * 0.5, _helmetPaint);
    canvas.drawCircle(
      Offset(headCenter.dx - unit * 0.10, headCenter.dy),
      unit * 0.42,
      _facePaint,
    );
    for (final xOff in [-unit * 0.22, 0.0, unit * 0.22]) {
      canvas.drawLine(
        Offset(headCenter.dx - unit * 0.27 + xOff, headCenter.dy - unit * 0.14),
        Offset(headCenter.dx - unit * 0.27 + xOff, headCenter.dy + unit * 0.20),
        _grillePaint,
      );
    }
    canvas.drawCircle(headCenter, unit * 0.5, _helmetRimPaint);
  }

  // ── Ball ───────────────────────────────────────────────────────────
  void _drawBall(Canvas canvas, Size size) {
    if (phase == _Phase.bowl) {
      _renderBall(canvas, size.width * 0.5, _ballScreenY(size));
    } else if (phase == _Phase.start) {
      // Park the ball at the bowler's hand on the start screen so the
      // scene doesn't feel empty behind the "Play" overlay.
      _renderBall(canvas, size.width * 0.5, size.height * 0.56);
    }
  }

  double _ballScreenY(Size size) {
    final pitchTopY = size.height * 0.55;
    final pitchHeight = size.height * 0.42;
    return pitchTopY + pitchHeight * ballProgress;
  }

  void _renderBall(Canvas canvas, double cx, double cy) {
    // Drop-shadow (radial-gradient shader, not MaskFilter.blur).
    canvas.save();
    canvas.translate(cx + 1, cy + 2);
    canvas.drawCircle(Offset.zero, 12, _ballShadowPaint);
    canvas.restore();
    canvas.drawCircle(Offset(cx, cy), 12, _ballBodyPaint);
    canvas.drawLine(
      Offset(cx - 10, cy),
      Offset(cx + 10, cy),
      _ballSeamPaint,
    );
  }

  // ── HUD chips removed — host GameContainerScreen paints the score
  // and stats chips on its own HUD bar.

  @override
  bool shouldRepaint(_CricketScenePainter old) =>
      old.ballProgress != ballProgress ||
      old.phase != phase ||
      old.ballsLeft != ballsLeft ||
      old.runs != runs ||
      old.wickets != wickets;
}

// ────────────────────────────────────────────────────────────────────
// Overlays
// ────────────────────────────────────────────────────────────────────

const _yellowPill = Color(0xFFFACC15);
const _yellowPillShadow = Color(0xFFCA8A04);
const _panelLight = Color(0xFF1F2937);
const _onDarkMuted = Color(0xCCFFFFFF);

class _StartOverlay extends StatelessWidget {
  const _StartOverlay({required this.onPlay});
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.35),
              Colors.black.withValues(alpha: 0.65),
            ],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Text(
                      'CRICKET BATTLE',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.4,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Hit the ball and score\nas many runs as you can!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Tap when the ball reaches the yellow zone.\nGet 50+ runs across 12 balls to win.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 28),
                  _PillButton(
                    label: 'Play',
                    icon: Icons.play_arrow_rounded,
                    onTap: onPlay,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Copy + colour + confetti-flag for each [_ShotKind], looked up
/// once instead of three parallel switch statements.
class _ShotCopy {
  const _ShotCopy({
    required this.headline,
    required this.subhead,
    required this.color,
    required this.confetti,
  });
  final String headline;
  final String? subhead;
  final Color color;
  final bool confetti;

  static const _byKind = <_ShotKind, _ShotCopy>{
    _ShotKind.six: _ShotCopy(
      headline: 'SIX RUNS!',
      subhead: 'Out of the park!',
      color: Color(0xFFFFD700),
      confetti: true,
    ),
    _ShotKind.four: _ShotCopy(
      headline: 'FOUR RUNS!',
      subhead: 'Raced to the boundary!',
      color: Color(0xFFFFD700),
      confetti: true,
    ),
    _ShotKind.two: _ShotCopy(
      headline: 'TWO RUNS',
      subhead: 'Quick single… make that two.',
      color: Color(0xFF4ADE80),
      confetti: false,
    ),
    _ShotKind.one: _ShotCopy(
      headline: 'ONE RUN',
      subhead: 'Quick single.',
      color: Color(0xFF4ADE80),
      confetti: false,
    ),
    _ShotKind.dot: _ShotCopy(
      headline: 'DOT BALL',
      subhead: 'No run that time — try again.',
      color: Colors.white,
      confetti: false,
    ),
    _ShotKind.wicket: _ShotCopy(
      headline: 'WICKET!',
      subhead: 'Mistimed — stumps rattled!',
      color: Color(0xFFEF4444),
      confetti: false,
    ),
  };

  static _ShotCopy of(_ShotKind kind) => _byKind[kind]!;
}

class _ShotResultOverlay extends StatelessWidget {
  const _ShotResultOverlay({
    required this.kind,
    required this.runsTotal,
    required this.wickets,
    required this.ballsLeft,
    required this.onContinue,
  });

  final _ShotKind kind;
  final int runsTotal;
  final int wickets;
  final int ballsLeft;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final copy = _ShotCopy.of(kind);
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
              ),
            ),
          ),
          if (copy.confetti)
            const Positioned.fill(
              child: IgnorePointer(child: ConfettiShower(count: 28)),
            ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _LabelChip(text: copy.headline, color: copy.color),
                    const SizedBox(height: 16),
                    Text(
                      copy.subhead!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _StatsPanel(
                      rows: [
                        ('Runs', '$runsTotal'),
                        ('Wickets', '$wickets'),
                        ('Balls Left', '$ballsLeft'),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _PillButton(
                      label: 'Continue',
                      icon: Icons.arrow_forward_rounded,
                      onTap: onContinue,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WicketOverlay extends StatelessWidget {
  const _WicketOverlay({
    required this.runs,
    required this.wickets,
    required this.onContinue,
  });
  final int runs;
  final int wickets;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _LabelChip(
                    text: 'WICKET!',
                    color: Color(0xFFEF4444),
                  ),
                  const SizedBox(height: 16),
                  const Icon(
                    Icons.sports_cricket_rounded,
                    color: Colors.white,
                    size: 56,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "You're out!",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Runs $runs  •  Wickets $wickets',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 28),
                  _PillButton(
                    label: 'Continue',
                    icon: Icons.arrow_forward_rounded,
                    onTap: onContinue,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// End-of-innings screen — the trophy variant celebrates a target met
/// (gold circle, "Great Job!"); the keep-going variant teases the
/// next attempt (subtle ring, "Keep Going!"). They share chrome and
/// actions; the [kind] drives which one renders.
class _GameOverOverlay extends StatelessWidget {
  const _GameOverOverlay({
    required this.kind,
    required this.runs,
    required this.wickets,
    required this.ballsBowled,
    required this.target,
    required this.onPlayAgain,
    required this.onBack,
  });

  final _GameOverKind kind;
  final int runs;
  final int wickets;
  final int ballsBowled;
  final int target;
  final VoidCallback onPlayAgain;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final isTrophy = kind == _GameOverKind.trophy;
    final title = isTrophy ? 'Great Job!' : 'Keep Going!';
    final subtitle = isTrophy
        ? 'You crossed the $target-run target.'
        : _missingRunsMessage();
    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isTrophy) const _TrophyBadge() else const _RetryBadge(),
                  const SizedBox(height: 20),
                  Text(
                    title,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isTrophy ? 32 : 30,
                      fontWeight: FontWeight.w900,
                      letterSpacing: isTrophy ? -0.5 : 0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _StatsPanel(
                    rows: [
                      ('Runs', '$runs'),
                      ('Wickets', '$wickets'),
                      ('Balls', '$ballsBowled'),
                    ],
                  ),
                  const SizedBox(height: 28),
                  _PillButton(
                    label: 'Play Again',
                    icon: Icons.replay_rounded,
                    onTap: onPlayAgain,
                  ),
                  const SizedBox(height: 12),
                  _PillButton.outline(
                    label: 'Back to Games',
                    icon: Icons.arrow_back_rounded,
                    onTap: onBack,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _missingRunsMessage() {
    final required = (target - runs).clamp(0, target);
    final plural = required == 1 ? '' : 's';
    return 'You needed $required more run$plural to reach $target.';
  }
}

enum _GameOverKind { trophy, keepGoing }

// ────────────────────────────────────────────────────────────────────
// Shared overlay building blocks
// ────────────────────────────────────────────────────────────────────

/// Small rounded "label chip" used at the top of overlay panels.
class _LabelChip extends StatelessWidget {
  const _LabelChip({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.7)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 14,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

/// Pill-shaped primary CTA. [outline] flips it to a transparent variant
/// for secondary actions like "Back to Games".
class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.icon,
    required this.onTap,
  }) : outline = false;

  const _PillButton.outline({
    required this.label,
    required this.icon,
    required this.onTap,
  }) : outline = true;

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool outline;

  static const _ink = Color(0xFF1F2937);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 28,
            vertical: 14,
          ),
          decoration: BoxDecoration(
            color: outline ? Colors.transparent : _yellowPill,
            borderRadius: BorderRadius.circular(999),
            border: outline
                ? Border.all(color: Colors.white.withValues(alpha: 0.7))
                : null,
            boxShadow: outline
                ? null
                : [
                    const BoxShadow(
                      color: _yellowPillShadow,
                      offset: Offset(0, 4),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: outline ? Colors.white : _ink,
                size: outline ? 20 : 22,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: outline ? Colors.white : _ink,
                  fontWeight: outline ? FontWeight.w700 : FontWeight.w900,
                  fontSize: outline ? 15 : 16,
                  letterSpacing: outline ? 0 : 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Trophy disc above "Great Job!" — gradient circle + glowing shadow.
class _TrophyBadge extends StatelessWidget {
  const _TrophyBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 112,
      height: 112,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFCD34D), Color(0xFFF59E0B)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFCD34D).withValues(alpha: 0.5),
            blurRadius: 24,
            spreadRadius: 2,
          ),
        ],
      ),
      child: const Icon(
        Icons.emoji_events_rounded,
        size: 64,
        color: Colors.white,
      ),
    );
  }
}

/// Subtle ringed circle above "Keep Going!".
class _RetryBadge extends StatelessWidget {
  const _RetryBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: const Icon(
        Icons.refresh_rounded,
        size: 56,
        color: Colors.white,
      ),
    );
  }
}

/// Stats panel used by both [_ShotResultOverlay] and [_GameOverOverlay].
class _StatsPanel extends StatelessWidget {
  const _StatsPanel({required this.rows});
  final List<(String label, String value)> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
      decoration: BoxDecoration(
        color: _panelLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (final (label, value) in rows)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: const TextStyle(
                    color: _onDarkMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
