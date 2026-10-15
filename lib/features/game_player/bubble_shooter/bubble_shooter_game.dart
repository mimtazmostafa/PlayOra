import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../widgets/game_hud_bar.dart';
import 'bubble_shooter_controller.dart';
import 'bubble_shooter_game_module.dart';
import 'bubble_shooter_ai.dart';
import 'bubble_shooter_state.dart';

/// Top-level play view for the Bubble Shooter game.
///
/// Layout:
///   - [GameHudBar] pinned at the top (title + score).
///   - Below it, the board with the launcher at the bottom-center.
///   - An optional faint "ceiling warning" stripe when the highest
///     bubble row gets close to [BubbleShooterState.ceilingLine].
class BubbleShooterGame extends StatelessWidget {
  const BubbleShooterGame({
    super.key,
    required this.gameTitle,
    required this.controller,
  });

  final String gameTitle;
  final BubbleShooterController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final state = controller.state;
        return Column(
          children: [
            GameHudBar(
              title: gameTitle,
              onPause: () => _onPause(context),
              subtitle: state.isGameOver
                  ? (state.status == BubbleGameStatus.won
                      ? 'You won!'
                      : 'Game over')
                  : 'Goal: ${state.score} / ${state.scoreTarget}',
              score: state.score,
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return _Board(
                    controller: controller,
                    constraints: constraints,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  void _onPause(BuildContext context) {
    final moduleScope = context.findAncestorStateOfType<BubbleShooterGameModuleState>();
    if (moduleScope != null) {
      moduleScope.pause();
    }
  }
}

/// The interactive board. Renders bubbles in a hex-offset grid and
/// hosts the gesture detector that turns drag gestures into shots.
class _Board extends StatefulWidget {
  const _Board({
    required this.controller,
    required this.constraints,
  });

  final BubbleShooterController controller;
  final BoxConstraints constraints;

  @override
  State<_Board> createState() => _BoardState();
}

class _BoardState extends State<_Board> {
  Offset? _launcherPosition;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final size = Size(
      widget.constraints.maxWidth,
      widget.constraints.maxHeight,
    );
    final launcher = _launcherPosition ??
        Offset(size.width / 2, size.height - kBubbleRadius * 1.5);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface(Theme.of(context).brightness),
        borderRadius: BorderRadius.circular(AppSpacing.md),
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          _BoardBackground(
            controller: controller,
          ),
          // Ceiling warning stripe — visible only when bubbles are close.
          _CeilingWarning(controller: controller),
          // Flyer drawn above the static board.
          if (controller.flyer != null)
            Positioned(
              left: controller.flyer!.position.dx - kBubbleRadius,
              top: controller.flyer!.position.dy - kBubbleRadius,
              child: _Bubble(color: controller.flyer!.color, size: kBubbleDiameter),
            ),
          // Launcher at the bottom-center.
          Positioned(
            left: launcher.dx - kBubbleRadius,
            top: launcher.dy - kBubbleRadius,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Bubble(color: controller.currentShot, size: kBubbleDiameter),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Next',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary(
                          Theme.of(context).brightness,
                        ),
                      ),
                ),
                _Bubble(color: controller.nextShot, size: kBubbleDiameter * 0.6),
              ],
            ),
          ),
          // Gesture detector for aim & shoot.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: _onPanStart,
              onPanUpdate: _onPanUpdate,
              onPanEnd: _onPanEnd,
              child: CustomPaint(
                painter: _AimLinePainter(
                  origin: launcher,
                  target: _lastTarget ?? launcher,
                  color: Theme.of(context).colorScheme.primary,
                  suggestion: controller.suggestionForCurrentShot(),
                  boardWidth: size.width,
                  boardHeight: size.height,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Offset? _lastTarget;

  void _onPanStart(DragStartDetails details) {
    setState(() {
      _launcherPosition = details.localPosition;
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_launcherPosition != null) {
      _lastTarget = details.localPosition;
      setState(() {});
    }
  }

  void _onPanEnd(DragEndDetails details) {
    final origin = _launcherPosition;
    final target = _lastTarget;
    if (origin != null && target != null) {
      widget.controller.aimAndShoot(origin: origin, target: target);
    }
    setState(() {
      _launcherPosition = null;
      _lastTarget = null;
    });
  }
}

/// Static board paint: bubbles + the empty cells in their hex-offset
/// positions. Drawn as a single CustomPaint for performance.
class _BoardBackground extends StatelessWidget {
  const _BoardBackground({
    required this.controller,
  });

  final BubbleShooterController controller;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BoardPainter(
        state: controller.state,
        brightness: Theme.of(context).brightness,
      ),
      child: const SizedBox.expand(),
    );
  }
}

/// Visual stripe just below the ceiling line, drawn redder as bubbles
/// approach it. Disappears entirely once bubbles are safely away.
class _CeilingWarning extends StatelessWidget {
  const _CeilingWarning({required this.controller});

  final BubbleShooterController controller;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final highestRow = state.highestFilledRow;
    if (highestRow < 0) return const SizedBox.shrink();
    final distance = state.ceilingLine - highestRow;
    if (distance >= 3) return const SizedBox.shrink();
    final intensity = ((3 - distance) / 3).clamp(0.0, 1.0);
    final top =
        kBubbleDiameter * state.ceilingLine.toDouble() - kBubbleRadius;
    return Positioned(
      top: top,
      left: 0,
      right: 0,
      height: 4,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.4 + 0.4 * intensity),
        ),
      ),
    );
  }
}

/// Painter that draws the filled bubbles on the board.
class _BoardPainter extends CustomPainter {
  _BoardPainter({required this.state, required this.brightness});
  final BubbleShooterState state;
  final Brightness brightness;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (var row = 0; row < BubbleShooterState.boardHeight; row++) {
      final isEvenRow = row.isEven;
      final maxCol = isEvenRow
          ? BubbleShooterState.boardWidth
          : BubbleShooterState.boardWidth - 1;
      final colOffset = isEvenRow ? 0.0 : kBubbleRadius;
      for (var col = 0; col < maxCol; col++) {
        final cell = state.at(row, col);
        if (cell == null) continue;
        paint.color = _colorFor(cell, brightness);
        canvas.drawCircle(
          Offset(
            colOffset + col * kBubbleDiameter + kBubbleRadius,
            row * kBubbleDiameter + kBubbleRadius,
          ),
          kBubbleRadius - 1,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BoardPainter old) =>
      old.state != state || old.brightness != brightness;
}

/// Aim line drawn over the board. Shows the trajectory from the
/// launcher to the user's finger, plus a faint circle at the AI's
/// recommended snap target.
class _AimLinePainter extends CustomPainter {
  _AimLinePainter({
    required this.origin,
    required this.target,
    required this.color,
    required this.suggestion,
    required this.boardWidth,
    required this.boardHeight,
  });
  final Offset origin;
  final Offset target;
  final Color color;
  final AimSuggestion? suggestion;
  final double boardWidth;
  final double boardHeight;

  @override
  void paint(Canvas canvas, Size size) {
    if (origin == target) return;
    final stroke = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(origin, target, stroke);
    final arrow = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final direction = target - origin;
    final normalized = direction / direction.distance;
    final arrowTip = target;
    final perp = Offset(-normalized.dy, normalized.dx) * 8;
    final arrowBack = arrowTip - normalized * 12;
    final path = Path()
      ..moveTo(arrowTip.dx, arrowTip.dy)
      ..lineTo(arrowBack.dx + perp.dx, arrowBack.dy + perp.dy)
      ..lineTo(arrowBack.dx - perp.dx, arrowBack.dy - perp.dy)
      ..close();
    canvas.drawPath(path, arrow);
    if (suggestion != null) {
      final snap = Offset(
        suggestion!.col * kBubbleDiameter +
            (suggestion!.row.isEven ? 0.0 : kBubbleRadius) +
            kBubbleRadius,
        suggestion!.row * kBubbleDiameter + kBubbleRadius,
      );
      final hintPaint = Paint()
        ..color = color.withValues(alpha: 0.4)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(snap, kBubbleRadius, hintPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _AimLinePainter old) =>
      old.origin != origin ||
      old.target != target ||
      old.suggestion != suggestion;
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.color, required this.size});
  final BubbleColor color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _colorFor(
          color,
          Theme.of(context).brightness,
        ),
        shape: BoxShape.circle,
      ),
    );
  }
}

Color _colorFor(BubbleColor color, Brightness brightness) {
  switch (color) {
    case BubbleColor.red:
      return const Color(0xFFEF4444);
    case BubbleColor.blue:
      return const Color(0xFF3B82F6);
    case BubbleColor.green:
      return const Color(0xFF22C55E);
    case BubbleColor.yellow:
      return const Color(0xFFF59E0B);
    case BubbleColor.purple:
      return const Color(0xFF7C3AED);
  }
}
