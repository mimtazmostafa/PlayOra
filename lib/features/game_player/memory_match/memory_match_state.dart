import 'dart:math';

/// Memory Match — flip cards to find pairs. Keep the API simple:
/// pure functions that take a [MemoryMatchState] and return a new one.
/// The controller drives the timer and the 1s auto-flip-back delay.

/// The 8 symbols used on the 16-card (4x4) board. The renderer maps
/// each to a Material icon + color pair.
enum CardSymbol {
  star,
  heart,
  cloud,
  moon,
  bolt,
  leaf,
  droplet,
  flame;

  static CardSymbol random(Random rng) => values[rng.nextInt(values.length)];
}

/// State of a single card on the board.
class MemoryCard {
  const MemoryCard({
    required this.id,
    required this.symbol,
    required this.isFaceUp,
    required this.isMatched,
  });

  /// Stable index into the board grid (0..15).
  final int id;
  final CardSymbol symbol;
  final bool isFaceUp;
  final bool isMatched;

  MemoryCard copyWith({bool? isFaceUp, bool? isMatched}) {
    return MemoryCard(
      id: id,
      symbol: symbol,
      isFaceUp: isFaceUp ?? this.isFaceUp,
      isMatched: isMatched ?? this.isMatched,
    );
  }
}

/// Mutable board state. The controller rebuilds this on every flip.
class MemoryMatchState {
  MemoryMatchState({
    required this.cards,
    required this.moves,
    required this.secondsElapsed,
    required this.isPaused,
    required this.isEnded,
  });

  /// 16 cards in row-major order. Same indexing as the 4x4 grid.
  final List<MemoryCard> cards;

  /// Number of flip attempts the player has made (each turn = 1 move,
  /// even if it reveals two cards).
  final int moves;

  /// Total elapsed seconds since the game started (excluding paused).
  final int secondsElapsed;

  /// Whether the timer is currently frozen.
  final bool isPaused;

  /// True once all pairs are matched. The controller fires the
  /// end-of-game callback when this flips.
  final bool isEnded;

  bool get isComplete => cards.every((c) => c.isMatched);

  MemoryMatchState copyWith({
    List<MemoryCard>? cards,
    int? moves,
    int? secondsElapsed,
    bool? isPaused,
    bool? isEnded,
  }) {
    return MemoryMatchState(
      cards: cards ?? this.cards,
      moves: moves ?? this.moves,
      secondsElapsed: secondsElapsed ?? this.secondsElapsed,
      isPaused: isPaused ?? this.isPaused,
      isEnded: isEnded ?? this.isEnded,
    );
  }
}

/// Pure logic. No Ticker. The controller owns the timer.
class MemoryMatchLogic {
  MemoryMatchLogic({
    this.rows = 4,
    this.cols = 4,
    int? seed,
  })  : assert(rows * cols % 2 == 0, 'board must have an even number of cells'),
        _rng = Random(seed);

  final int rows;
  final int cols;
  final Random _rng;

  /// Build the initial 4x4 board: 8 pairs shuffled randomly, all
  /// face-down, all unmatched.
  MemoryMatchState newGame() {
    final total = rows * cols;
    final halfSymbols = <CardSymbol>[];
    for (int i = 0; i < total ~/ 2; i++) {
      halfSymbols.add(CardSymbol.values[i % CardSymbol.values.length]);
    }
    final symbols = <CardSymbol>[];
    for (final s in halfSymbols) {
      symbols.add(s);
      symbols.add(s);
    }
    symbols.shuffle(_rng);

    final cards = List<MemoryCard>.generate(
      total,
      (i) => MemoryCard(
        id: i,
        symbol: symbols[i],
        isFaceUp: false,
        isMatched: false,
      ),
    );

    return MemoryMatchState(
      cards: cards,
      moves: 0,
      secondsElapsed: 0,
      isPaused: false,
      isEnded: false,
    );
  }

  /// Flip a card face-up. Returns the new state. Caller is responsible
  /// for the subsequent [evaluatePendingPair] after a short delay.
  MemoryMatchState flipCard(MemoryMatchState state, int cardId) {
    if (state.isPaused || state.isEnded) return state;
    if (cardId < 0 || cardId >= state.cards.length) return state;
    final card = state.cards[cardId];
    if (card.isFaceUp || card.isMatched) return state;

    final newCards = List<MemoryCard>.generate(
      state.cards.length,
      (i) => i == cardId ? card.copyWith(isFaceUp: true) : state.cards[i],
    );
    return state.copyWith(cards: newCards);
  }

  /// Look for a pair of face-up but not-yet-matched cards. If found and
  /// they match, mark them as matched and possibly end the game. If they
  /// don't match, flip them back down. Returns the new state.
  MemoryMatchState evaluatePendingPair(MemoryMatchState state) {
    final pending = <MemoryCard>[];
    for (final c in state.cards) {
      if (c.isFaceUp && !c.isMatched) pending.add(c);
    }
    if (pending.length < 2) return state;

    final a = pending[0];
    final b = pending[1];

    if (a.symbol == b.symbol) {
      // Match — lock them in.
      final newCards = List<MemoryCard>.generate(
        state.cards.length,
        (i) {
          final c = state.cards[i];
          if (c.id == a.id || c.id == b.id) {
            return c.copyWith(isFaceUp: true, isMatched: true);
          }
          return c;
        },
      );
      final newState = state.copyWith(cards: newCards);
      if (newState.isComplete) {
        return newState.copyWith(isEnded: true);
      }
      return newState;
    } else {
      // Mismatch — flip them back down.
      final newCards = List<MemoryCard>.generate(
        state.cards.length,
        (i) {
          final c = state.cards[i];
          if (c.id == a.id || c.id == b.id) {
            return c.copyWith(isFaceUp: false);
          }
          return c;
        },
      );
      return state.copyWith(cards: newCards);
    }
  }

  /// Tick the elapsed-seconds counter. Caller should also call this on
  /// every second-tick to update the HUD.
  MemoryMatchState tick(MemoryMatchState state) {
    if (state.isPaused || state.isEnded) return state;
    return state.copyWith(secondsElapsed: state.secondsElapsed + 1);
  }

  /// Increment the move counter. Called once per "turn" (a pair of
  /// flips). The scoring formula subtracts 25 per move.
  MemoryMatchState recordMove(MemoryMatchState state) {
    if (state.isPaused || state.isEnded) return state;
    return state.copyWith(moves: state.moves + 1);
  }

  /// Score formula: 1000 - 25*moves - 5*seconds. Floors at 0. The
  /// shorter and faster the player plays, the higher the score.
  int scoreFor(MemoryMatchState state) {
    final raw = 1000 - 25 * state.moves - 5 * state.secondsElapsed;
    return raw.clamp(0, 1 << 30);
  }
}
