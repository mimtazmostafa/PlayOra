import 'package:flutter_test/flutter_test.dart';
import 'package:playnest/features/game_player/memory_match/memory_match_state.dart';

void main() {
  group('MemoryMatchLogic.newGame', () {
    test('produces 16 cards, 8 unique symbols each twice, all face-down', () {
      final logic = MemoryMatchLogic(seed: 1);
      final state = logic.newGame();
      expect(state.cards, hasLength(16));
      expect(state.moves, 0);
      expect(state.secondsElapsed, 0);
      expect(state.isPaused, isFalse);
      expect(state.isEnded, isFalse);
      // Each card starts face-down and unmatched.
      for (final c in state.cards) {
        expect(c.isFaceUp, isFalse);
        expect(c.isMatched, isFalse);
      }
      // Each symbol appears exactly twice.
      final counts = <CardSymbol, int>{};
      for (final c in state.cards) {
        counts[c.symbol] = (counts[c.symbol] ?? 0) + 1;
      }
      expect(counts.length, 8);
      for (final entry in counts.entries) {
        expect(entry.value, 2,
            reason: '${entry.key} should appear exactly twice');
      }
    });

    test('is deterministic with the same seed', () {
      final a = MemoryMatchLogic(seed: 42);
      final b = MemoryMatchLogic(seed: 42);
      final sa = a.newGame();
      final sb = b.newGame();
      expect(
        sa.cards.map((c) => c.symbol).toList(),
        sb.cards.map((c) => c.symbol).toList(),
      );
    });

    test('different seeds produce different orderings', () {
      final a = MemoryMatchLogic(seed: 1);
      final b = MemoryMatchLogic(seed: 999);
      final sa = a.newGame();
      final sb = b.newGame();
      expect(
        sa.cards.map((c) => c.symbol).toList(),
        isNot(sb.cards.map((c) => c.symbol).toList()),
      );
    });
  });

  group('MemoryMatchLogic.flipCard', () {
    test('flips a single face-down card face-up', () {
      final logic = MemoryMatchLogic(seed: 7);
      final state = logic.newGame();
      final flipped = logic.flipCard(state, 0);
      expect(flipped.cards[0].isFaceUp, isTrue);
      expect(flipped.cards[1].isFaceUp, isFalse);
    });

    test('is a no-op when card is already face-up', () {
      final logic = MemoryMatchLogic(seed: 7);
      final state = logic.newGame();
      final once = logic.flipCard(state, 0);
      final twice = logic.flipCard(once, 0);
      expect(identical(once, twice), isTrue);
    });

    test('is a no-op when card is already matched', () {
      final logic = MemoryMatchLogic(seed: 7);
      final state = logic.newGame();
      // Manually mark card 0 as matched + face-up.
      final matched = state.copyWith(
        cards: List.generate(
          state.cards.length,
          (i) => i == 0
              ? state.cards[i].copyWith(isFaceUp: true, isMatched: true)
              : state.cards[i],
        ),
      );
      final flipped = logic.flipCard(matched, 0);
      expect(identical(matched, flipped), isTrue);
    });

    test('is a no-op when game is paused', () {
      final logic = MemoryMatchLogic(seed: 7);
      final state = logic.newGame().copyWith(isPaused: true);
      final flipped = logic.flipCard(state, 0);
      expect(identical(state, flipped), isTrue);
    });

    test('is a no-op when game has ended', () {
      final logic = MemoryMatchLogic(seed: 7);
      final state = logic.newGame().copyWith(isEnded: true);
      final flipped = logic.flipCard(state, 0);
      expect(identical(state, flipped), isTrue);
    });

    test('is a no-op for out-of-range card id', () {
      final logic = MemoryMatchLogic(seed: 7);
      final state = logic.newGame();
      final flipped = logic.flipCard(state, 99);
      expect(identical(state, flipped), isTrue);
      final flippedNeg = logic.flipCard(state, -1);
      expect(identical(state, flippedNeg), isTrue);
    });
  });

  group('MemoryMatchLogic.evaluatePendingPair', () {
    test('locks matching pair and marks them matched', () {
      final logic = MemoryMatchLogic(seed: 7);
      final state = logic.newGame();
      // Force a known pair: pick first two cards, then synthetically
      // make them the same symbol and face-up.
      final s = state.copyWith(
        cards: List.generate(
          state.cards.length,
          (i) {
            if (i == 0 || i == 1) {
              return MemoryCard(
                id: state.cards[i].id,
                symbol: CardSymbol.star,
                isFaceUp: true,
                isMatched: false,
              );
            }
            return state.cards[i];
          },
        ),
      );
      final after = logic.evaluatePendingPair(s);
      expect(after.cards[0].isMatched, isTrue);
      expect(after.cards[1].isMatched, isTrue);
      // Both stay face-up after match.
      expect(after.cards[0].isFaceUp, isTrue);
      expect(after.cards[1].isFaceUp, isTrue);
      expect(after.isEnded, isFalse);
    });

    test('flips back a non-matching pair', () {
      final logic = MemoryMatchLogic(seed: 7);
      final state = logic.newGame();
      // Pick any two cards that are NOT the same symbol — for a shuffled
      // 16-card board with 8 symbols each appearing twice, almost any
      // two cards are non-matching. Use 0 and 2.
      final c0 = state.cards[0];
      final c2 = state.cards[2];
      if (c0.symbol == c2.symbol) {
        // Extremely unlikely with 8 distinct symbols; skip if true.
        return;
      }
      final s = state.copyWith(
        cards: List.generate(
          state.cards.length,
          (i) {
            if (i == 0 || i == 2) {
              return state.cards[i].copyWith(isFaceUp: true);
            }
            return state.cards[i];
          },
        ),
      );
      final after = logic.evaluatePendingPair(s);
      expect(after.cards[0].isFaceUp, isFalse);
      expect(after.cards[2].isFaceUp, isFalse);
      expect(after.cards[0].isMatched, isFalse);
    });

    test('is a no-op when fewer than 2 cards are face-up', () {
      final logic = MemoryMatchLogic(seed: 7);
      final state = logic.newGame();
      final s = state.copyWith(
        cards: List.generate(
          state.cards.length,
          (i) =>
              i == 0 ? state.cards[i].copyWith(isFaceUp: true) : state.cards[i],
        ),
      );
      final after = logic.evaluatePendingPair(s);
      expect(identical(s, after), isTrue);
    });

    test('sets isEnded when the matching pair completes the board', () {
      final logic = MemoryMatchLogic(seed: 7);
      final state = logic.newGame();
      // Mark all cards matched except cards 0 and 1, which we set up
      // as the same symbol + face-up. After evaluating the pair, the
      // board is fully matched → isEnded.
      final cards = List.generate(state.cards.length, (i) {
        if (i == 0 || i == 1) {
          return MemoryCard(
            id: state.cards[i].id,
            symbol: CardSymbol.star,
            isFaceUp: true,
            isMatched: false,
          );
        }
        return state.cards[i].copyWith(isMatched: true, isFaceUp: true);
      });
      final s = state.copyWith(cards: cards);
      final after = logic.evaluatePendingPair(s);
      expect(after.isComplete, isTrue);
      expect(after.isEnded, isTrue);
    });
  });

  group('MemoryMatchLogic.tick and recordMove', () {
    test('tick increments secondsElapsed by 1', () {
      final logic = MemoryMatchLogic(seed: 7);
      final state = logic.newGame();
      final after = logic.tick(state);
      expect(after.secondsElapsed, 1);
    });

    test('tick is a no-op when paused or ended', () {
      final logic = MemoryMatchLogic(seed: 7);
      final state = logic.newGame().copyWith(isPaused: true);
      expect(logic.tick(state).secondsElapsed, 0);
      final ended = state.copyWith(isEnded: true);
      expect(logic.tick(ended).secondsElapsed, 0);
    });

    test('recordMove increments moves by 1', () {
      final logic = MemoryMatchLogic(seed: 7);
      final state = logic.newGame();
      final after = logic.recordMove(state);
      expect(after.moves, 1);
    });

    test('recordMove is a no-op when paused or ended', () {
      final logic = MemoryMatchLogic(seed: 7);
      final paused = logic.newGame().copyWith(isPaused: true);
      expect(logic.recordMove(paused).moves, 0);
      final ended = paused.copyWith(isEnded: true);
      expect(logic.recordMove(ended).moves, 0);
    });
  });

  group('MemoryMatchLogic.scoreFor', () {
    test('perfect game (0 moves, 0s) scores 1000', () {
      final logic = MemoryMatchLogic(seed: 7);
      final state = logic.newGame();
      expect(logic.scoreFor(state), 1000);
    });

    test('formula: 1000 - 25*moves - 5*seconds', () {
      final logic = MemoryMatchLogic(seed: 7);
      final state = logic.newGame().copyWith(moves: 20, secondsElapsed: 10);
      // 1000 - 25*20 - 5*10 = 1000 - 500 - 50 = 450
      expect(logic.scoreFor(state), 450);
    });

    test('clamps at 0 for very long games', () {
      final logic = MemoryMatchLogic(seed: 7);
      final state = logic.newGame().copyWith(moves: 100, secondsElapsed: 500);
      // 1000 - 2500 - 2500 = -4000 → 0
      expect(logic.scoreFor(state), 0);
    });

    test('score is non-negative for any state', () {
      final logic = MemoryMatchLogic(seed: 7);
      final state = logic.newGame().copyWith(moves: 50, secondsElapsed: 200);
      // 1000 - 1250 - 1000 = -1250 → 0
      expect(logic.scoreFor(state), greaterThanOrEqualTo(0));
    });
  });

  group('MemoryMatchState', () {
    test('isComplete true when every card is matched', () {
      final logic = MemoryMatchLogic(seed: 7);
      final fresh = logic.newGame();
      final allMatched = fresh.copyWith(
        cards: List.generate(
          fresh.cards.length,
          (i) => fresh.cards[i].copyWith(isFaceUp: true, isMatched: true),
        ),
      );
      expect(allMatched.isComplete, isTrue);
    });
  });
}