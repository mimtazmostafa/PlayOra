import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../games_providers.dart';
import '../game_widgets.dart';

/// A grid of level tiles for a single game. Level 1 is always unlocked;
/// subsequent levels unlock as the player wins. Tapping an unlocked
/// level triggers [onSelectLevel] (typically used to launch the game).
///
/// The grid adapts to the available width — cells are square and there
/// are at most [maxColumnsPerRow] per row.
class LevelSelectGrid extends ConsumerWidget {
  const LevelSelectGrid({
    super.key,
    required this.gameId,
    this.maxColumnsPerRow = 5,
    this.onSelectLevel,
  });

  final String gameId;
  final int maxColumnsPerRow;
  final ValueChanged<int>? onSelectLevel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncSnapshot = ref.watch(levelProgressProvider(gameId));
    final snapshot = asyncSnapshot.value;
    if (snapshot == null) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        const spacing = 10.0;
        final cols = (snapshot.total <= maxColumnsPerRow)
            ? snapshot.total
            : maxColumnsPerRow;
        if (cols == 0) {
          return _EmptyState(gameId: gameId);
        }
        final cell = ((c.maxWidth - spacing * (cols - 1)) / cols).clamp(48.0, 84.0);
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          alignment: WrapAlignment.start,
          children: [
            for (var i = 1; i <= snapshot.total; i++)
              _LevelTile(
                level: i,
                size: cell,
                unlocked: snapshot.isUnlocked(i),
                accent: i == snapshot.unlocked
                    ? kGameAccent(Theme.of(context).brightness)
                    : (i < snapshot.unlocked ? kGameReward() : Colors.white24),
                isCurrent: i == snapshot.unlocked,
                onTap: snapshot.isUnlocked(i)
                    ? () => onSelectLevel?.call(i)
                    : null,
              ),
          ],
        );
      },
    );
  }
}

class _LevelTile extends StatelessWidget {
  const _LevelTile({
    required this.level,
    required this.size,
    required this.unlocked,
    required this.accent,
    required this.isCurrent,
    required this.onTap,
  });

  final int level;
  final double size;
  final bool unlocked;
  final Color accent;
  final bool isCurrent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final inner = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: unlocked ? kGamePanel(Theme.of(context).brightness) : kGamePanel(Theme.of(context).brightness).withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: accent.withValues(alpha: isCurrent ? 0.9 : 0.45),
          width: isCurrent ? 2 : 1,
        ),
        boxShadow: isCurrent
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.45),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (unlocked)
            Text(
              '$level',
              style: TextStyle(
                color: isCurrent ? accent : Colors.white,
                fontSize: size * 0.34,
                fontWeight: FontWeight.w900,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            )
          else
            Icon(
              Icons.lock_rounded,
              size: size * 0.36,
              color: Colors.white24,
            ),
          if (isCurrent) ...[
            const SizedBox(height: 2),
            Container(
              width: 18,
              height: 3,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ],
      ),
    );

    if (!unlocked || onTap == null) return inner;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: inner,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.gameId});
  final String gameId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$gameId has no level progression yet.',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 4),
          const Text(
            'Endless mode — your high score is the goal.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
