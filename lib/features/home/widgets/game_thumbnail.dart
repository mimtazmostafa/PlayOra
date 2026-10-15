import 'package:flutter/material.dart';

import '../../../data/models/game_model.dart';
import '../../games/widgets/game_card.dart';

/// Tile shown in horizontal rows on the Home screen.
///
/// Thin wrapper over [GameCard] with a fixed `width` so each row of
/// tiles stays the same size regardless of the device. The overflow
/// safeguards (ellipsized titles + `Flexible` text rows + 4:3
/// thumbnail) all live in [GameCard]; this widget just decides how
/// wide each card is in the row.
class GameThumbnail extends StatelessWidget {
  const GameThumbnail({
    super.key,
    required this.game,
    required this.onTap,
    this.width = 140,
  });

  final Game game;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: GameCard(
        game: game,
        onTap: onTap,
      ),
    );
  }
}