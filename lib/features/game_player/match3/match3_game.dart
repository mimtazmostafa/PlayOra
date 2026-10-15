import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../widgets/game_hud_bar.dart';
import 'match3_controller.dart';
import 'match3_state.dart';

/// Match-3 game surface.
///
/// The widget is intentionally thin: it owns a [Match3Controller] for
/// its lifetime, exposes the controller's lifecycle through a [GameModule]
/// shim (init/pause/resume), and renders the grid from the controller's
/// visible-cell snapshot. All scoring, swap resolution, cascade logic,
/// and timer handling live in the controller + pure [Match3Logic].
class Match3Game extends StatefulWidget {
  const Match3Game({
    super.key,
    required this.gameTitle,
    required this.controller,
    this.pixelSize = 44,
  });

  final String gameTitle;

  /// Owning controller. Provided by [Match3GameModule] so the widget
  /// does not own its own lifecycle.
  final Match3Controller controller;
  final double pixelSize;

  @override
  State<Match3Game> createState() => _Match3GameState();
}

class _Match3GameState extends State<Match3Game> {
  Match3Controller get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.init();
  }

  /// External pause/resume hook — the GamePlayerScreen calls these
  /// External pause/resume hook — the GamePlayerScreen calls these
  /// from its pause overlay. The controller is owned by
  /// [Match3GameModule], so this widget just exposes it.
  Match3Controller get controller => _controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.md),
            // AnimatedBuilder rebuilds the bar so the live countdown
            // updates every tick. GameHudBar's pause button is omitted
            // — the host screen already exposes one in the corner.
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final state = _controller.state;
                return GameHudBar(
                  title: widget.gameTitle,
                  subtitle: 'Score ${state.score}',
                  timerSeconds: state.secondsRemaining,
                );
              },
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final size = widget.pixelSize * _controller.gridSize;
                  return Center(
                    child: SizedBox(
                      width: size,
                      height: size,
                      child: Stack(
                        children: [
                          _BoardBackground(controller: _controller),
                          ..._buildCells(theme),
                          ..._buildParticles(),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildCells(ThemeData theme) {
    return _controller.visibleCells.map((cell) {
      final center = _cellCenter(cell.targetRow, cell.targetCol) + cell.offset;
      return Positioned(
        left: center.dx - widget.pixelSize / 2,
        top: center.dy - widget.pixelSize / 2,
        width: widget.pixelSize,
        height: widget.pixelSize,
        child: GestureDetector(
          onTap: () => _controller.onTap(
            GridPos(cell.targetRow, cell.targetCol),
          ),
          child: _GemView(
            type: cell.type,
            selected: cell.selected,
            highlighted: cell.highlighted,
            scale: cell.scale,
            alpha: cell.alpha,
            pixelSize: widget.pixelSize,
          ),
        ),
      );
    }).toList(growable: false);
  }

  List<Widget> _buildParticles() {
    return _controller.particles.map((p) {
      final fade = 1 - p.progress;
      return Positioned(
        left: p.position.dx - p.size / 2,
        top: p.position.dy - p.size / 2,
        width: p.size,
        height: p.size,
        child: Opacity(
          opacity: fade,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: p.color,
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
    }).toList(growable: false);
  }

  Offset _cellCenter(int row, int col) {
    final size = widget.pixelSize;
    return Offset(col * size + size / 2, row * size + size / 2);
  }
}

// ---------------------------------------------------------------------
// HUD
// ---------------------------------------------------------------------

class _BoardBackground extends StatelessWidget {
  const _BoardBackground({required this.controller});

  final Match3Controller controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withValues(alpha: 0.95),
            AppColors.primary.withValues(alpha: 0.7),
          ],
        ),
      ),
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _GridPainter(
              size: controller.gridSize,
              cellSize: controller.cellSize,
              color: Colors.white.withValues(alpha: 0.10),
            ),
          );
        },
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({required this.size, required this.cellSize, required this.color});

  final int size;
  final double cellSize;
  final Color color;

  @override
  void paint(Canvas canvas, Size paintSize) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    final totalSize = size * cellSize;
    for (int i = 1; i < size; i++) {
      final x = i * cellSize;
      canvas.drawLine(Offset(x, 0), Offset(x, totalSize), paint);
      final y = i * cellSize;
      canvas.drawLine(Offset(0, y), Offset(totalSize, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) =>
      old.size != size || old.cellSize != cellSize || old.color != color;
}

// ---------------------------------------------------------------------
// Gem rendering
// ---------------------------------------------------------------------

class _GemView extends StatelessWidget {
  const _GemView({
    required this.type,
    required this.selected,
    required this.highlighted,
    required this.scale,
    required this.alpha,
    required this.pixelSize,
  });

  final GemType type;
  final bool selected;
  final bool highlighted;
  final double scale;
  final double alpha;
  final double pixelSize;

  @override
  Widget build(BuildContext context) {
    final colors = _colorsFor(type);
    final padding = (pixelSize * 0.10).clamp(2.0, 6.0);
    return Opacity(
      opacity: alpha,
      child: Container(
        margin: EdgeInsets.all(padding),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: const Alignment(-0.3, -0.3),
            radius: 0.95,
            colors: colors,
          ),
          border: Border.all(
            color: selected
                ? Colors.white
                : Colors.white.withValues(alpha: 0.30),
            width: selected ? 3 : 1.5,
          ),
          boxShadow: [
            if (selected)
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.6),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: highlighted
            ? Center(
                child: Container(
                  width: pixelSize * 0.4,
                  height: pixelSize * 0.4,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              )
            : null,
      ),
    );
  }

  static List<Color> _colorsFor(GemType t) {
    switch (t) {
      case GemType.ruby:
        return const [Color(0xFFFCA5A5), Color(0xFFEF4444)];
      case GemType.amethyst:
        return const [Color(0xFFD8B4FE), Color(0xFF9333EA)];
      case GemType.topaz:
        return const [Color(0xFFFDE68A), Color(0xFFF59E0B)];
      case GemType.emerald:
        return const [Color(0xFFA7F3D0), Color(0xFF22C55E)];
      case GemType.sapphire:
        return const [Color(0xFFBFDBFE), Color(0xFF3B82F6)];
      case GemType.diamond:
        return const [Color(0xFFF8FAFC), Color(0xFF94A3B8)];
    }
  }
}
