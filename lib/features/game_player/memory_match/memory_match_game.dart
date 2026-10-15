import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../widgets/game_hud_bar.dart';
import 'memory_match_controller.dart';
import 'memory_match_state.dart';

/// Memory Match game widget. Pure presentation — reads everything from
/// the controller. Renders the HUD, the 4x4 card grid, and the score.
class MemoryMatchGame extends StatefulWidget {
  const MemoryMatchGame({
    super.key,
    required this.gameTitle,
    required this.controller,
  });

  final String gameTitle;
  final MemoryMatchController controller;

  @override
  State<MemoryMatchGame> createState() => _MemoryMatchGameState();
}

class _MemoryMatchGameState extends State<MemoryMatchGame> {
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

  /// Count of face-up cards — used to detect "second card just flipped"
  /// and schedule the auto-flip-back delay.
  int _lastFaceUpCount = 0;

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;

    final faceUpCount = state.cards.where((c) => c.isFaceUp && !c.isMatched).length;
    if (faceUpCount == 2 && _lastFaceUpCount < 2) {
      // Just flipped the second card of a pair — schedule the delay.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.controller.scheduleFlipBack();
      });
    }
    _lastFaceUpCount = faceUpCount;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GameHudBar(
              title: widget.gameTitle,
              subtitle: 'Moves: ${state.moves}  •  Time: ${state.secondsElapsed}s',
              score: widget.controller.score,
            ),
            AppSpacing.gapMd,
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: _CardGrid(
                    controller: widget.controller,
                    onTap: widget.controller.tap,
                  ),
                ),
              ),
            ),
            AppSpacing.gapMd,
          ],
        ),
      ),
    );
  }
}

class _CardGrid extends StatelessWidget {
  const _CardGrid({
    required this.controller,
    required this.onTap,
  });

  final MemoryMatchController controller;
  final void Function(int cardId) onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = controller.logic.rows;
    final cols = controller.logic.cols;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface(theme.brightness),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.primary, width: 1),
      ),
      padding: const EdgeInsets.all(10),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemCount: rows * cols,
        itemBuilder: (context, index) {
          final card = controller.cards[index];
          return _Card(
            card: card,
            onTap: () => onTap(card.id),
          );
        },
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.card, required this.onTap});

  final MemoryCard card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showFace = card.isFaceUp || card.isMatched;
    return GestureDetector(
      onTap: card.isMatched ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: showFace
              ? _symbolColor(card.symbol).withValues(alpha: 0.85)
              : theme.colorScheme.primary.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(10),
          border: card.isMatched
              ? Border.all(color: Colors.greenAccent.shade400, width: 2)
              : null,
        ),
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: showFace
                ? Icon(
                    _symbolIcon(card.symbol),
                    key: ValueKey('face-${card.id}'),
                    size: 30,
                    color: Colors.white,
                  )
                : Icon(
                    Icons.help_outline_rounded,
                    key: ValueKey('back-${card.id}'),
                    size: 28,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
          ),
        ),
      ),
    );
  }
}

IconData _symbolIcon(CardSymbol s) {
  switch (s) {
    case CardSymbol.star:
      return Icons.star_rounded;
    case CardSymbol.heart:
      return Icons.favorite_rounded;
    case CardSymbol.cloud:
      return Icons.cloud_rounded;
    case CardSymbol.moon:
      return Icons.nightlight_round;
    case CardSymbol.bolt:
      return Icons.flash_on_rounded;
    case CardSymbol.leaf:
      return Icons.eco_rounded;
    case CardSymbol.droplet:
      return Icons.water_drop_rounded;
    case CardSymbol.flame:
      return Icons.local_fire_department_rounded;
  }
}

Color _symbolColor(CardSymbol s) {
  switch (s) {
    case CardSymbol.star:
      return const Color(0xFFFBBF24);
    case CardSymbol.heart:
      return const Color(0xFFEF4444);
    case CardSymbol.cloud:
      return const Color(0xFF60A5FA);
    case CardSymbol.moon:
      return const Color(0xFF6366F1);
    case CardSymbol.bolt:
      return const Color(0xFFF59E0B);
    case CardSymbol.leaf:
      return const Color(0xFF22C55E);
    case CardSymbol.droplet:
      return const Color(0xFF06B6D4);
    case CardSymbol.flame:
      return const Color(0xFFF97316);
  }
}
