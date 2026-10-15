import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../widgets/game_hud_bar.dart';
import 'block_puzzle_controller.dart';
import 'block_puzzle_state.dart';

/// Block Puzzle game widget. Pure presentation — reads everything from
/// the controller. Renders:
///   - HUD with score
///   - the 10x10 grid with drag-target cells
///   - the 3-piece tray at the bottom (Draggable sources)
class BlockPuzzleGame extends StatefulWidget {
  const BlockPuzzleGame({
    super.key,
    required this.gameTitle,
    required this.controller,
  });

  final String gameTitle;
  final BlockPuzzleController controller;

  @override
  State<BlockPuzzleGame> createState() => _BlockPuzzleGameState();
}

class _BlockPuzzleGameState extends State<BlockPuzzleGame> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: GameHudBar(
                title: widget.gameTitle,
                subtitle: 'Drag pieces onto the grid. Clear full lines.',
                score: widget.controller.score,
              ),
            ),
            AppSpacing.gapMd,
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: _Board(controller: widget.controller),
                ),
              ),
            ),
            AppSpacing.gapMd,
            _Tray(controller: widget.controller),
            AppSpacing.gapMd,
          ],
        ),
      ),
    );
  }
}

/// The grid. Each cell is a [DragTarget] accepting any piece; the
/// controller decides which piece and where to place it based on the
/// payload.
class _Board extends StatelessWidget {
  const _Board({required this.controller});
  final BlockPuzzleController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = controller.logic.boardSize;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface(theme.brightness),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.primary, width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: size,
          ),
          itemCount: size * size,
          itemBuilder: (context, index) {
            final r = index ~/ size;
            final c = index % size;
            final filled = controller.board.isFilled(r, c);
            final flashing = controller.isFlashing(r, c);
            return DragTarget<_PieceDrag>(
              onAcceptWithDetails: (details) {
                controller.dropAt(details.data.pieceIndex, r, c);
              },
              builder: (context, candidate, rejected) {
                final isHovering = candidate.isNotEmpty;
                final invalid = isHovering && _wouldOverlap(
                      controller,
                      candidate.first!.pieceIndex,
                      r,
                      c,
                    );
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: AppColors.textSecondary(theme.brightness)
                          .withValues(alpha: 0.3),
                      width: 0.5,
                    ),
                    color: filled
                        ? _colorFor(
                            controller.pieceIdAt(r, c) ?? '',
                            theme,
                          )
                        : invalid
                            ? Colors.red.withValues(alpha: 0.25)
                            : isHovering
                                ? Colors.green.withValues(alpha: 0.25)
                                : null,
                  ),
                  child: flashing
                      ? Container(color: Colors.white.withValues(alpha: 0.55))
                      : null,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

bool _wouldOverlap(
  BlockPuzzleController controller,
  int pieceIndex,
  int r,
  int c,
) {
  if (pieceIndex < 0 || pieceIndex >= controller.tray.length) return true;
  final piece = controller.tray[pieceIndex];
  for (final cell in piece.cells) {
    final rr = r + cell[0];
    final cc = c + cell[1];
    if (!controller.board.inBounds(rr, cc)) return true;
    if (controller.board.isFilled(rr, cc)) return true;
  }
  return false;
}

class _PieceDrag {
  const _PieceDrag(this.pieceIndex);
  final int pieceIndex;
}

/// The 3-piece tray at the bottom. Each piece is a [Draggable] source;
/// the [DragTarget] cells above it accept the drop.
class _Tray extends StatelessWidget {
  const _Tray({required this.controller});
  final BlockPuzzleController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface(theme.brightness),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.textSecondary(theme.brightness).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(controller.tray.length, (i) {
          final piece = controller.tray[i];
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Draggable<_PieceDrag>(
                data: _PieceDrag(i),
                feedback: _PiecePreview(
                  piece: piece,
                  accent: accent,
                  boardSize: controller.logic.boardSize,
                  ghost: true,
                ),
                childWhenDragging: const SizedBox.shrink(),
                child: _PiecePreview(
                  piece: piece,
                  accent: accent,
                  boardSize: controller.logic.boardSize,
                  ghost: false,
                  onTap: () => controller.beginDrag(i),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _PiecePreview extends StatelessWidget {
  const _PiecePreview({
    required this.piece,
    required this.accent,
    required this.boardSize,
    required this.ghost,
    this.onTap,
  });

  final BlockPiece piece;
  final Color accent;
  final int boardSize;
  final bool ghost;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = ghost ? accent.withValues(alpha: 0.55) : accent;
    return GestureDetector(
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: 1,
        child: Column(
          mainAxisSize: MainAxisSize.max,
          children: List.generate(piece.height, (r) {
            return Expanded(
              child: Row(
                children: List.generate(piece.width, (c) {
                  final occupied = piece.cells.any((cell) =>
                      cell[0] == r && cell[1] == c);
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Container(
                        decoration: BoxDecoration(
                          color: occupied ? color : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            );
          }),
        ),
      ),
    );
  }
}

/// Static color picker based on the piece id. We hash the id into a hue.
Color _colorFor(String pieceId, ThemeData theme) {
  if (pieceId.isEmpty) return theme.colorScheme.primary;
  final hash = pieceId.hashCode;
  final hue = (hash.abs() % 360).toDouble();
  return HSLColor.fromAHSL(1, hue, 0.55, 0.55).toColor();
}
