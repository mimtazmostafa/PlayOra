import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../game_widgets.dart';
import '../mini_game.dart';

/// Tap Reaction — screen changes colour, wait for GREEN, then tap.
/// False-start penalty: tapping before green ends the round immediately.
///
/// Tracks the average of 5 reaction times.
class TapReactionGame extends MiniGame {
  const TapReactionGame({super.key, required super.callbacks});

  @override
  State<TapReactionGame> createState() => _TapReactionState();
}

enum _Phase { idle, waiting, green, tooSoon, done }

class _TapReactionState extends MiniGameState<TapReactionGame> {
  static const int _totalRounds = 5;
  _Phase _phase = _Phase.idle;
  int _round = 0;
  final List<int> _reactions = [];
  int _score = 0;
  Timer? _delayTimer;
  DateTime? _greenAt;
  final Random _rng = Random();

  @override
  void dispose() {
    _delayTimer?.cancel();
    super.dispose();
  }

  void _startRound() {
    if (_round >= _totalRounds) return;
    setState(() => _phase = _Phase.waiting);
    final wait = 1200 + _rng.nextInt(2800);
    _delayTimer = Timer(Duration(milliseconds: wait), () {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.green;
        _greenAt = DateTime.now();
      });
      haptic(HapticFeedbackType.light);
    });
  }

  void _onTap() {
    switch (_phase) {
      case _Phase.idle:
        _round = 0;
        _reactions.clear();
        _score = 0;
        _startRound();
        break;
      case _Phase.waiting:
        // False start!
        _delayTimer?.cancel();
        setState(() => _phase = _Phase.tooSoon);
        haptic(HapticFeedbackType.heavy);
        _afterPenalty();
        break;
      case _Phase.green:
        final ms = DateTime.now().difference(_greenAt!).inMilliseconds;
        _reactions.add(ms);
        // Scoring: faster = more points. 1000ms = 0, 200ms = 800.
        final points = (1000 - ms).clamp(0, 1000);
        _score += points;
        _round++;
        reportScore(_score);
        reportStats(
          'Round $_round/$_totalRounds  •  Avg $_avgLabel',
        );
        haptic(HapticFeedbackType.selection);
        _afterPenalty();
        break;
      case _Phase.tooSoon:
      case _Phase.done:
        if (_phase == _Phase.done) {
          // Restart.
          _round = 0;
          _reactions.clear();
          _score = 0;
          _startRound();
        }
        break;
    }
  }

  void _afterPenalty() {
    if (_round >= _totalRounds) {
      setState(() => _phase = _Phase.done);
      haptic(HapticFeedbackType.medium);
      reportStats('Final avg $_avgLabel');
      reportGameOver();
    } else {
      Future.delayed(const Duration(milliseconds: 1100), () {
        if (!mounted) return;
        _startRound();
      });
    }
  }

  String get _avgLabel {
    if (_reactions.isEmpty) return '—';
    final avg =
        _reactions.reduce((a, b) => a + b) / _reactions.length;
    return '${avg.round()} ms';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        color: _bgForPhase(_phase),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Round ${(_round + 1).clamp(1, _totalRounds)}/$_totalRounds',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  _labelForPhase(_phase),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 24),
                if (_reactions.isNotEmpty)
                  Text(
                    'Avg: $_avgLabel',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _bgForPhase(_Phase p) {
    switch (p) {
      case _Phase.idle:
        return kGamePanel();
      case _Phase.waiting:
        return const Color(0xFFB91C1C);
      case _Phase.green:
        return const Color(0xFF15803D);
      case _Phase.tooSoon:
        return const Color(0xFF7F1D1D);
      case _Phase.done:
        return kGamePanel();
    }
  }

  String _labelForPhase(_Phase p) {
    switch (p) {
      case _Phase.idle:
        return 'TAP TO START';
      case _Phase.waiting:
        return 'Wait for GREEN...';
      case _Phase.green:
        return 'TAP!';
      case _Phase.tooSoon:
        return 'Too soon! ❌';
      case _Phase.done:
        return 'Avg $_avgLabel\nTAP to play again';
    }
  }
}
