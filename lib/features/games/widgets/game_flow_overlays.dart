/// Shared overlay chrome for the "Pool / Backgammon / Maze Escape"
/// mini-game family. Each game imports these widgets so the three
/// games feel like one product family without duplicating ~150 lines
/// of overlay code per game.
///
/// All four overlays follow the same visual language:
///
///   * Dark navy scrim (`Colors.black.withValues(alpha: 0.55–0.7)`)
///   * Blue HUD pills (`#1E3A8A` background + white text)
///   * Yellow CTA pill (`AppColors.dailyGold` with dark text + drop
///     shadow)
///   * Outlined-blue secondary button
///   * Cartoony boy character (see [BoyCharacter]) in the
///     illustration area on start / win / trophy screens
///
/// Each overlay is a single StatelessWidget that drops into a
/// `Positioned.fill` inside the game's `Stack`. They take callbacks
/// for the buttons so the game owns the state transitions.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../game_player/widgets/confetti_shower.dart';

// ── Brand tokens (private to this file) ─────────────────────────────
// `dailyGold` is the canonical reward gold in AppColors (used by the
// daily-completion overlay) — the three games here share that gold
// for their yellow CTAs.
const _blueInk = Color(0xFF1E3A8A);
const _ink = Color(0xFF1F2937);
const _onDarkMuted = Color(0xCCFFFFFF);
const _panelLight = Color(0xFF1F2937);
const _yellowPillShadow = Color(0xFFCA8A04);
const _hudPillH = 36.0;
const _pillRadius = 999.0;

// Const shadow lists so HUD rebuilds don't allocate fresh lists.
const _hudShadow = BoxShadow(
  color: Color(0x40000000),
  blurRadius: 8,
  offset: Offset(0, 2),
);
const _hudShadows = <BoxShadow>[_hudShadow];

/// Pose for the [BoyCharacter] illustration. Each pose shares the
/// same head/torso/cap but varies the arm position and any prop.
enum BoyPose {
  /// Boy in left profile holding a pool cue angled forward.
  cueStick,

  /// Boy in 3/4 view, both hands cradling a dice cup.
  diceCup,

  /// Boy in 3/4 view from behind, mid-stride.
  walking,

  /// Boy in front-facing 3/4 view, right arm raised in celebration.
  waving,
}

// ────────────────────────────────────────────────────────────────────
// Start overlay
// ────────────────────────────────────────────────────────────────────

/// Start screen for a mini-game.
///
/// Shows the in-game chrome (back button + title), the "You X/X vs
/// Target N" red/blue card, instruction copy, and a yellow Play
/// pill. Caller renders the gameplay scene illustration (table,
/// board, maze) inside [illustration] — typically a SizedBox +
/// CustomPaint that fills the available space.
class GameStartOverlay extends StatelessWidget {
  const GameStartOverlay({
    super.key,
    required this.title,
    required this.subtitle,
    required this.youScore,
    required this.targetScore,
    required this.instruction,
    required this.illustration,
    required this.onPlay,
    this.onBack,
  });

  final String title;
  final String subtitle;
  final int youScore;
  final int targetScore;
  final String instruction;
  final Widget illustration;
  final VoidCallback onPlay;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0B1226), Color(0xFF1F2A4A)],
          ),
        ),
        child: Column(
          children: [
            _TopBar(title: title, onBack: onBack),
            Expanded(child: illustration),
            _ScoreVsTarget(you: youScore, target: targetScore),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Column(
                children: [
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    instruction,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _CtaPill(
                    label: 'Play',
                    icon: Icons.play_arrow_rounded,
                    onTap: onPlay,
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// Gameplay HUD
// ────────────────────────────────────────────────────────────────────

/// Three blue pills rendered above the gameplay surface: "You X/Y",
/// counter, and a pause button. Drop this as a `Positioned(top: 0,
/// left: 0, right: 0, child: GamePlayHud(...))` inside the game's
/// `Stack`.
class GamePlayHud extends StatelessWidget {
  const GamePlayHud({
    super.key,
    required this.youText,
    required this.counterText,
    this.onPause,
    this.avatar = true,
  });

  /// Left-pill label, e.g. "You 0/5" or "You 0/15".
  final String youText;

  /// Centre-pill label, e.g. "Balls Left 7" or "Moves Left 10".
  final String counterText;

  /// Pause-icon tap. Optional — the pause pill renders even when
  /// null, just without a tap handler.
  final VoidCallback? onPause;

  /// Whether to prepend the avatar circle to the "You" pill. The
  /// reference shows it on every screen.
  final bool avatar;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Row(
          children: [
            Expanded(
              child: _BluePillChrome(
                child: _YouPillContent(text: youText, showAvatar: avatar),
              ),
            ),
            const SizedBox(width: 8),
            _BluePillChrome(
              child: Center(
                child: Text(
                  counterText,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _BluePillChrome(
              width: _hudPillH,
              shape: BoxShape.circle,
              onTap: onPause,
              child: const Icon(
                Icons.pause_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// Win overlay
// ────────────────────────────────────────────────────────────────────

/// Win / level-complete overlay. Shows the win header pill, the
/// large yellow-bordered score badge with confetti behind, the
/// bottom stats row, and a yellow "Continue" pill.
class GameWinOverlay extends StatelessWidget {
  const GameWinOverlay({
    super.key,
    required this.title,
    required this.subtitle,
    required this.scoreValue,
    required this.scoreLabel,
    required this.statRows,
    required this.onContinue,
  });

  /// Header pill text, e.g. "YOU WIN!" or "LEVEL COMPLETE".
  final String title;

  /// Large celebratory subtitle, e.g. "YOU ESCAPED!".
  final String subtitle;

  /// Big yellow-bordered score number.
  final int scoreValue;

  /// Label under the score, e.g. "Balls Pocketed".
  final String scoreLabel;

  /// Secondary stat rows (label, value).
  final List<(String, String)> statRows;

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
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
          const Positioned.fill(
            child: IgnorePointer(child: ConfettiShower(count: 32)),
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 12),
                    const _LabelChip(text: 'Game Over', color: _blueInk),
                    const SizedBox(height: 20),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _ScoreBadge(value: scoreValue, label: title),
                    const SizedBox(height: 20),
                    if (statRows.isNotEmpty)
                      _StatsStrip(
                        rows: [
                          (scoreLabel, '$scoreValue'),
                          ...statRows,
                        ],
                      )
                    else
                      Text(
                        scoreLabel,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    const SizedBox(height: 24),
                    _CtaPill(
                      label: 'Continue',
                      icon: Icons.arrow_forward_rounded,
                      onTap: onContinue,
                    ),
                    const SizedBox(height: 24),
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

// ────────────────────────────────────────────────────────────────────
// Trophy / "Great Job!" overlay
// ────────────────────────────────────────────────────────────────────

/// Final-result overlay for after a win. Renders the gold trophy
/// gradient circle + "Great Job!" title + a centred "Your Score"
/// panel + a 3-column stat strip + a yellow "Play Again" pill + a
/// blue outlined "Back to Games" button.
class GameTrophyOverlay extends StatelessWidget {
  const GameTrophyOverlay({
    super.key,
    required this.iconData,
    required this.iconGradient,
    required this.title,
    required this.subtitle,
    required this.score,
    required this.statRows,
    required this.onPlayAgain,
    required this.onBack,
    this.glowColor,
  });

  /// Icon shown inside the trophy circle (trophy for win, dice for
  /// backgammon, etc.).
  final IconData iconData;

  /// Gradient for the trophy circle.
  final List<Color> iconGradient;

  /// Big title, e.g. "Great Job!".
  final String title;

  /// Sub-copy under the title.
  final String subtitle;

  /// Final score (large number under "Your Score").
  final int score;

  /// 3-column stat strip (typically three small label/value pairs).
  final List<(String, String)> statRows;

  final VoidCallback onPlayAgain;
  final VoidCallback onBack;

  /// Optional glow halo colour for the trophy circle. Defaults to
  /// the first colour of [iconGradient].
  final Color? glowColor;

  @override
  Widget build(BuildContext context) {
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
                  Container(
                    width: 112,
                    height: 112,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: iconGradient,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (glowColor ?? iconGradient.first)
                              .withValues(alpha: 0.5),
                          blurRadius: 24,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      iconData,
                      size: 64,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
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
                  _YourScorePanel(score: score),
                  if (statRows.length == 3) ...[
                    const SizedBox(height: 12),
                    _StatsStrip(rows: statRows),
                  ],
                  const SizedBox(height: 24),
                  _CtaPill(
                    label: 'Play Again',
                    icon: Icons.replay_rounded,
                    onTap: onPlayAgain,
                  ),
                  const SizedBox(height: 12),
                  _CtaPill.outline(
                    label: 'Back to Games',
                    icon: Icons.home_rounded,
                    onTap: onBack,
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// Boy character (shared painter)
// ────────────────────────────────────────────────────────────────────

/// Cartoony boy character used in all three games' illustration
/// areas. The same boy appears in four poses: holding a pool cue,
/// holding a dice cup, mid-stride (walking), and celebrating
/// (waving). Renders into a [SizedBox] of any size — internally
/// scales to fit.
class BoyCharacter extends StatelessWidget {
  const BoyCharacter({
    super.key,
    required this.pose,
    this.mood = BoyMood.happy,
  });

  final BoyPose pose;

  /// Slight facial-expression tweak — the [waving] pose uses
  /// excited, the in-game poses use happy.
  final BoyMood mood;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _BoyPainter(pose: pose, mood: mood),
        size: Size.infinite,
      ),
    );
  }
}

enum BoyMood { happy, excited }

class _BoyPainter extends CustomPainter {
  _BoyPainter({required this.pose, required this.mood});

  final BoyPose pose;
  final BoyMood mood;

  // Palette + cached Paints — all allocated once instead of per-frame.
  static const _skin = Color(0xFFF5C9A0);
  static const _capBlue = Color(0xFF2563EB);
  static const _capVisor = Color(0xFF1E3A8A);
  static const _shirt = Color(0xFF2563EB);
  static const _shirtShadow = Color(0xFF1E40AF);
  static const _eye = Color(0xFF1F2937);
  static const _cheek = Color(0xFFFCA5A5);
  static const _legColor = Color(0xFF1E3A8A);
  static const _prop1 = Color(0xFFEAB308); // pool-cue wood / dice pip
  static const _prop2 = Color(0xFF92400E); // pool-cue shaft / dice body
  static const _cupRim = Color(0xFFB45309);

  static final _legPaint = Paint()..color = _legColor;
  static final _shoePaint = Paint()..color = Colors.white;
  static final _shirtPaint = Paint()..color = _shirt;
  static final _shirtShadowPaint =
      Paint()..color = _shirtShadow.withValues(alpha: 0.7);
  static final _skinPaint = Paint()..color = _skin;
  static final _armStrokePaint = Paint()
    ..color = _shirt
    ..strokeCap = StrokeCap.round;
  static final _eyePaint = Paint()..color = _eye;
  static final _cheekPaint = Paint()
    ..color = _cheek.withValues(alpha: 0.7);
  static final _capPaint = Paint()..color = _capBlue;
  static final _capVisorPaint = Paint()..color = _capVisor;
  static final _smileStrokePaint = Paint()
    ..color = _eye
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  static final _smileFillPaint = Paint()
    ..color = _eye
    ..style = PaintingStyle.fill;
  static final _prop1Paint = Paint()..color = _prop1;
  static final _prop2Paint = Paint()..color = _prop2;
  static final _cupRimPaint = Paint()..color = _cupRim;
  static final _dicePaint = Paint()..color = Colors.white;
  static final _pipPaint = Paint()..color = _eye;

  @override
  void paint(Canvas canvas, Size size) {
    // Always render into a centred ~65% × 65% sub-region so the
    // caller can pad around the boy.
    final dim = size.shortestSide * 0.65;
    final ox = (size.width - dim) / 2;
    final oy = (size.height - dim) / 2;
    canvas.save();
    canvas.translate(ox, oy);
    final unit = dim / 60; // 60 logical units tall

    final cx = 30 * unit;
    final feetY = 60 * unit;
    final headY = 14 * unit;
    final headR = 9 * unit;
    final bodyTop = (headY + headR) + 2 * unit;
    final bodyH = 24 * unit;
    final bodyW = 18 * unit;
    final armW = 4 * unit;
    final legW = 6 * unit;
    final legH = 16 * unit;

    _drawLegs(canvas, cx, feetY, legW, legH, unit);
    _drawTorso(canvas, cx, bodyTop, bodyW, bodyH);
    _drawArmsAndProps(canvas, cx, bodyTop, bodyW, bodyH, armW, unit);
    _drawHead(
      canvas,
      Offset(cx, headY),
      headR,
      unit,
      wavingArm: pose == BoyPose.waving,
    );

    canvas.restore();
  }

  void _drawLegs(
    Canvas canvas,
    double cx,
    double feetY,
    double legW,
    double legH,
    double unit,
  ) {
    final stride = pose == BoyPose.walking ? unit * 1.2 : 0.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - legW - stride / 2, feetY - legH, legW, legH),
        Radius.circular(legW * 0.25),
      ),
      _legPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx + stride / 2, feetY - legH, legW, legH),
        Radius.circular(legW * 0.25),
      ),
      _legPaint,
    );
    // Sneaker toe-caps.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          cx - legW - stride / 2 - unit * 0.5,
          feetY - unit * 2,
          legW + unit,
          unit * 2,
        ),
        Radius.circular(unit * 0.6),
      ),
      _shoePaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          cx + stride / 2 - unit * 0.5,
          feetY - unit * 2,
          legW + unit,
          unit * 2,
        ),
        Radius.circular(unit * 0.6),
      ),
      _shoePaint,
    );
  }

  void _drawTorso(
    Canvas canvas,
    double cx,
    double bodyTop,
    double bodyW,
    double bodyH,
  ) {
    final rect = Rect.fromLTWH(cx - bodyW / 2, bodyTop, bodyW, bodyH);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(bodyW * 0.25)),
      _shirtPaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(rect.left, rect.top, rect.width * 0.35, rect.height),
      _shirtShadowPaint,
    );
  }

  void _drawArmsAndProps(
    Canvas canvas,
    double cx,
    double bodyTop,
    double bodyW,
    double bodyH,
    double armW,
    double unit,
  ) {
    _armStrokePaint.strokeWidth = armW;
    switch (pose) {
      case BoyPose.cueStick:
        canvas.drawLine(
          Offset(cx - bodyW / 2 + 2 * unit, bodyTop + 4 * unit),
          Offset(cx - bodyW / 2 + 1 * unit, bodyTop + bodyH - 4 * unit),
          _armStrokePaint,
        );
        canvas.drawCircle(
          Offset(cx - bodyW / 2 + 1 * unit, bodyTop + bodyH - 4 * unit),
          armW * 0.5,
          _skinPaint,
        );
        // Right arm forward holding the cue.
        final grip = Offset(cx + bodyW / 2 - 2 * unit, bodyTop + 4 * unit);
        final tip = Offset(
          cx + bodyW / 2 + 22 * unit,
          bodyTop + bodyH - 2 * unit,
        );
        canvas.drawLine(grip, tip, _armStrokePaint);
        canvas.drawCircle(tip, armW * 0.5, _skinPaint);
        _drawPoolCue(canvas, grip, tip, unit);
        break;

      case BoyPose.diceCup:
        final leftGrip = Offset(
          cx - bodyW / 2 + 2 * unit,
          bodyTop + bodyH * 0.6,
        );
        final rightGrip = Offset(
          cx + bodyW / 2 - 2 * unit,
          bodyTop + bodyH * 0.6,
        );
        final cupCenter = Offset(cx, bodyTop + bodyH * 0.7);
        canvas.drawLine(
          Offset(cx - bodyW / 4, bodyTop + bodyH * 0.4),
          leftGrip,
          _armStrokePaint,
        );
        canvas.drawLine(
          Offset(cx + bodyW / 4, bodyTop + bodyH * 0.4),
          rightGrip,
          _armStrokePaint,
        );
        canvas.drawCircle(leftGrip, armW * 0.5, _skinPaint);
        canvas.drawCircle(rightGrip, armW * 0.5, _skinPaint);
        _drawDiceCup(canvas, cupCenter, unit);
        break;

      case BoyPose.walking:
        // Arms swinging — left forward, right back.
        canvas.drawLine(
          Offset(cx - bodyW / 2 + 2 * unit, bodyTop + 4 * unit),
          Offset(cx - bodyW / 2 + 6 * unit, bodyTop + bodyH * 0.6),
          _armStrokePaint,
        );
        canvas.drawCircle(
          Offset(cx - bodyW / 2 + 6 * unit, bodyTop + bodyH * 0.6),
          armW * 0.5,
          _skinPaint,
        );
        canvas.drawLine(
          Offset(cx + bodyW / 2 - 2 * unit, bodyTop + 4 * unit),
          Offset(cx + bodyW / 2 - 6 * unit, bodyTop + bodyH * 0.4),
          _armStrokePaint,
        );
        canvas.drawCircle(
          Offset(cx + bodyW / 2 - 6 * unit, bodyTop + bodyH * 0.4),
          armW * 0.5,
          _skinPaint,
        );
        break;

      case BoyPose.waving:
        canvas.drawLine(
          Offset(cx - bodyW / 2 + 2 * unit, bodyTop + 4 * unit),
          Offset(cx - bodyW / 2 + 1 * unit, bodyTop + bodyH - 4 * unit),
          _armStrokePaint,
        );
        canvas.drawCircle(
          Offset(cx - bodyW / 2 + 1 * unit, bodyTop + bodyH - 4 * unit),
          armW * 0.5,
          _skinPaint,
        );
        final shoulder = Offset(cx + bodyW / 2 - 2 * unit, bodyTop + 4 * unit);
        final handUp = Offset(
          cx + bodyW / 2 + 4 * unit,
          bodyTop - 8 * unit,
        );
        canvas.drawLine(shoulder, handUp, _armStrokePaint);
        canvas.drawCircle(handUp, armW * 0.55, _skinPaint);
        break;
    }
  }

  void _drawHead(
    Canvas canvas,
    Offset center,
    double headR,
    double unit, {
    required bool wavingArm,
  }) {
    canvas.drawCircle(center, headR, _skinPaint);
    canvas.drawCircle(
      Offset(center.dx - headR * 0.95, center.dy),
      headR * 0.18,
      _skinPaint,
    );
    canvas.drawCircle(
      Offset(center.dx + headR * 0.95, center.dy),
      headR * 0.18,
      _skinPaint,
    );
    canvas.drawCircle(
      Offset(center.dx - headR * 0.32, center.dy - headR * 0.10),
      headR * 0.10,
      _eyePaint,
    );
    canvas.drawCircle(
      Offset(center.dx + headR * 0.32, center.dy - headR * 0.10),
      headR * 0.10,
      _eyePaint,
    );
    // Excited mood OR a waving pose → open mouth; otherwise smile arc.
    final mouthY = center.dy + headR * 0.30;
    final mouthRect = Rect.fromCircle(
      center: Offset(center.dx, mouthY),
      radius: headR * 0.30,
    );
    if (mood == BoyMood.excited || wavingArm) {
      canvas.drawArc(mouthRect, 0, 3.14, false, _smileFillPaint);
    } else {
      _smileStrokePaint.strokeWidth = headR * 0.10;
      canvas.drawArc(mouthRect, 0.1, 3.0, false, _smileStrokePaint);
    }
    canvas.drawCircle(
      Offset(center.dx - headR * 0.55, center.dy + headR * 0.18),
      headR * 0.10,
      _cheekPaint,
    );
    canvas.drawCircle(
      Offset(center.dx + headR * 0.55, center.dy + headR * 0.18),
      headR * 0.10,
      _cheekPaint,
    );
    // Blue cap — half-disc on top of the head with a visor.
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: headR * 1.05)
          .shift(const Offset(0, -2)),
      3.14,
      3.14,
      true,
      _capPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(center.dx, center.dy - headR * 0.55),
          width: headR * 1.6,
          height: headR * 0.35,
        ),
        Radius.circular(headR * 0.15),
      ),
      _capVisorPaint,
    );
  }

  void _drawPoolCue(Canvas canvas, Offset grip, Offset tip, double unit) {
    _prop1Paint.strokeWidth = unit * 1.1;
    _prop1Paint.strokeCap = StrokeCap.round;
    canvas.drawLine(grip, tip, _prop1Paint);
    final cueLength = (tip - grip).distance;
    final butt = Offset(
      grip.dx + (tip.dx - grip.dx) / cueLength * unit * 0.8,
      grip.dy + (tip.dy - grip.dy) / cueLength * unit * 0.8,
    );
    canvas.drawCircle(butt, unit * 0.6, _prop2Paint);
    final cueTip = Offset(
      grip.dx + (tip.dx - grip.dx) / cueLength * (cueLength - unit * 0.6),
      grip.dy + (tip.dy - grip.dy) / cueLength * (cueLength - unit * 0.6),
    );
    canvas.drawCircle(cueTip, unit * 0.45, _shoePaint);
  }

  void _drawDiceCup(Canvas canvas, Offset center, double unit) {
    final cupRect = Rect.fromCenter(
      center: center.translate(0, unit),
      width: unit * 14,
      height: unit * 10,
    );
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        cupRect,
        topLeft: Radius.circular(unit * 4),
        topRight: Radius.circular(unit * 4),
        bottomLeft: Radius.circular(unit * 0.5),
        bottomRight: Radius.circular(unit * 0.5),
      ),
      _prop2Paint,
    );
    canvas.drawRect(
      Rect.fromCenter(
        center: center.translate(0, unit - 4),
        width: unit * 14,
        height: unit * 1.2,
      ),
      _cupRimPaint,
    );
    // Two dice peeking out the top.
    canvas.drawRect(
      Rect.fromCenter(
        center: center.translate(-unit * 3, -unit * 3),
        width: unit * 4,
        height: unit * 4,
      ),
      _dicePaint,
    );
    canvas.drawRect(
      Rect.fromCenter(
        center: center.translate(unit * 3, -unit * 3),
        width: unit * 4,
        height: unit * 4,
      ),
      _dicePaint,
    );
    canvas.drawCircle(
      center.translate(unit * 3, -unit * 3),
      unit * 0.6,
      _pipPaint,
    );
    canvas.drawCircle(
      center.translate(unit * 3 - unit * 1.2, -unit * 3 - unit * 1.2),
      unit * 0.6,
      _pipPaint,
    );
    canvas.drawCircle(
      center.translate(unit * 3 + unit * 1.2, -unit * 3 + unit * 1.2),
      unit * 0.6,
      _pipPaint,
    );
  }

  @override
  bool shouldRepaint(_BoyPainter old) =>
      old.pose != pose || old.mood != mood;
}

// ────────────────────────────────────────────────────────────────────
// Shared widgets
// ────────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, this.onBack});
  final String title;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: onBack ?? () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.left,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.settings_rounded, color: Colors.white),
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreVsTarget extends StatelessWidget {
  const _ScoreVsTarget({required this.you, required this.target});
  final int you;
  final int target;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Row(
          children: [
            Expanded(
              child: _Pill(
                icon: Icons.person_rounded,
                label: 'You',
                value: '$you',
                color: _blueInk,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                'VS',
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Expanded(
              child: _Pill(
                icon: Icons.flag_rounded,
                label: 'Target',
                value: '$target',
                color: AppColors.coral,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(_pillRadius),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared blue-pill chrome used by all three HUD pills. Optionally
/// tap-able (pause button) and optionally a fixed-width circle.
class _BluePillChrome extends StatelessWidget {
  const _BluePillChrome({
    required this.child,
    this.width,
    this.shape = BoxShape.rectangle,
    this.onTap,
  });

  final Widget child;
  final double? width;
  final BoxShape shape;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final container = Container(
      width: width,
      height: _hudPillH,
      decoration: BoxDecoration(
        color: _blueInk,
        shape: shape,
        borderRadius:
            shape == BoxShape.rectangle ? BorderRadius.circular(_pillRadius) : null,
        boxShadow: _hudShadows,
      ),
      child: child,
    );
    if (onTap == null) return container;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: shape == BoxShape.circle
            ? null
            : BorderRadius.circular(_pillRadius),
        child: container,
      ),
    );
  }
}

/// Inner row of the "You" pill — just the avatar + label.
class _YouPillContent extends StatelessWidget {
  const _YouPillContent({required this.text, required this.showAvatar});
  final String text;
  final bool showAvatar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showAvatar) ...[
            Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.dailyGold,
              ),
              child: const Icon(
                Icons.person_rounded,
                color: Colors.white,
                size: 14,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LabelChip extends StatelessWidget {
  const _LabelChip({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(_pillRadius),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 14,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({required this.value, required this.label});
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.dailyGold,
        border: Border.all(color: Colors.white, width: 6),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$value',
              style: const TextStyle(
                color: _ink,
                fontSize: 56,
                fontWeight: FontWeight.w900,
                height: 1.0,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _ink,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _YourScorePanel extends StatelessWidget {
  const _YourScorePanel({required this.score});
  final int score;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: _panelLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          const Text(
            'Your Score',
            style: TextStyle(
              color: _onDarkMuted,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$score',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 40,
              fontWeight: FontWeight.w900,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsStrip extends StatelessWidget {
  const _StatsStrip({required this.rows});
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _onDarkMuted,
                    fontSize: 11,
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

/// Pill-shaped primary CTA. `.outline` flips it to the blue secondary
/// variant used for "Back to Games".
class _CtaPill extends StatelessWidget {
  const _CtaPill({
    required this.label,
    required this.icon,
    required this.onTap,
  }) : outline = false;

  const _CtaPill.outline({
    required this.label,
    required this.icon,
    required this.onTap,
  }) : outline = true;

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool outline;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_pillRadius),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          decoration: BoxDecoration(
            color: outline ? _blueInk : AppColors.dailyGold,
            borderRadius: BorderRadius.circular(_pillRadius),
            boxShadow: outline
                ? const [
                    BoxShadow(
                      color: Color(0x40000000),
                      blurRadius: 10,
                      offset: Offset(0, 3),
                    ),
                  ]
                : const [
                    BoxShadow(
                      color: _yellowPillShadow,
                      offset: Offset(0, 4),
                    ),
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 10,
                      offset: Offset(0, 2),
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
