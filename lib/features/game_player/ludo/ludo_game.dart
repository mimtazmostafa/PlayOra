import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../widgets/game_hud_bar.dart';
import 'ludo_board.dart';
import 'ludo_controller.dart';
import 'ludo_model.dart';
import 'ludo_motion.dart';

/// Ludo game surface.
///
/// The widget is intentionally thin: it owns a [LudoController] for
/// its lifetime, exposes the controller's lifecycle through a
/// [LudoGameModule] shim (init/pause/resume), and renders the board
/// + HUD from the controller's current state. All rules + bot
/// decisions live in the controller + model + bot.
class LudoGame extends StatefulWidget {
  const LudoGame({
    super.key,
    required this.gameTitle,
    required this.controller,
    this.boardSize = 360,
  });

  final String gameTitle;
  final LudoController controller;
  final double boardSize;

  @override
  State<LudoGame> createState() => _LudoGameState();
}

class _LudoGameState extends State<LudoGame>
    with TickerProviderStateMixin {
  LudoController get _controller => widget.controller;

  late final LudoMotionController _motion;

  /// Snapshot of the state the controller had on the previous
  /// notifyListeners tick. Used to compute move trails.
  LudoState? _previousState;

  /// Path indices currently flashing white after a capture. Cleared
  /// after ~350 ms by [clearFlashTimer].
  Set<int> _captureFlash = const <int>{};

  Timer? _clearFlashTimer;

  @override
  void initState() {
    super.initState();
    _motion = LudoMotionController(vsync: this);
    _controller.addListener(_onControllerRebuild);
    _controller.init();
    _previousState = _controller.currentState;
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerRebuild);
    _motion.dispose();
    _clearFlashTimer?.cancel();
    super.dispose();
  }

  void _onControllerRebuild() {
    if (!mounted) return;
    final current = _controller.currentState;
    final prev = _previousState ?? current;
    // Drive the motion tween for any token that changed position
    // between the previous and current state.
    _motion.start(prev, current);
    _previousState = current;

    // Show a brief white flash on the captured cells.
    final caps = _controller.lastCapturePathIndices;
    if (caps.isNotEmpty) {
      setState(() => _captureFlash = caps);
      _controller.clearLastCaptures();
      _clearFlashTimer?.cancel();
      _clearFlashTimer = Timer(const Duration(milliseconds: 350), () {
        if (!mounted) return;
        setState(() => _captureFlash = const <int>{});
      });
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.md),
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final state = _controller.currentState;
                final subtitle = _controller.hasEnded
                    ? '${_seatName(state.winner!)} wins!'
                    : _controller.isHumanTurn
                        ? 'Your turn \u2014 ${_seatName(state.currentPlayer)}'
                        : '${_seatName(state.currentPlayer)} playing\u2026';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: GameHudBar.customTrailing(
                    title: widget.gameTitle,
                    subtitle: subtitle,
                    subtitleColor: _seatColor(state.currentPlayer),
                    customTrailing: _SeatChip(player: state.currentPlayer),
                  ),
                );
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_controller, _motion]),
                    builder: (context, _) {
                      final state = _controller.currentState;
                      final legal = _controller.legalMovesForActive
                          .map((m) => m.tokenIndex)
                          .toSet();
                      // Build a small lookup of tween overrides for
                      // any token currently mid-move.
                      final tweens = <(LudoPlayer, int), LudoTokenTween>{};
                      for (final p in LudoPlayer.values) {
                        for (var i = 0; i < 4; i++) {
                          final t = _motion.tweened(p, i);
                          if (t != null) tweens[(p, i)] = t;
                        }
                      }
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (details) =>
                            _handleTap(details.localPosition),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: CustomPaint(
                            painter: LudoBoardPainter(
                              theme: theme,
                              state: state,
                              legalTokenIndices:
                                  state.currentPlayer == _controller.humanPlayer
                                      ? legal
                                      : const <int>{},
                              flashCapturesAt: _captureFlash,
                              tweens: tweens.isEmpty ? null : tweens,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _DiceRollBar(controller: _controller),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }

  /// Converts a screen tap into a token index on the human seat.
  ///
  /// We test the tap against every legal-move target (path,
  /// stretch, finished, yard home) â€” whichever legal target cell
  /// the user tapped on, we move that token.
  void _handleTap(Offset localPosition) {
    if (!_controller.isHumanTurn) return;
    if (!_controller.currentState.rolled) return;
    final size = widget.boardSize;
    final cell = size / 15.0;
    final col = (localPosition.dx / cell).floor();
    final row = (localPosition.dy / cell).floor();

    final legal = _controller.legalMovesForActive;
    for (final m in legal) {
      // Find the screen pos of token m.tokenIndex's current + next.
      final player = _controller.currentState.currentPlayer;
      final currentTokens = _controller.currentState.players[player.seat].tokens;
      // Use the legal move's NEXT position (so a yard token that's
      // about to move counts as the start cell of the player's start).
      final next = m.next;
      final pos = _cellFor(player, next);
      if (pos == null) continue;
      final tCol = pos.$2;
      final tRow = pos.$1;
      if (tRow == row && tCol == col) {
        _controller.attemptMove(m.tokenIndex);
        return;
      }
      // Also accept a tap on the token's CURRENT pos for yard exits.
      final curr = currentTokens[m.tokenIndex];
      final c = _cellFor(player, curr);
      if (c == null) continue;
      if (c.$1 == row && c.$2 == col) {
        _controller.attemptMove(m.tokenIndex);
        return;
      }
    }
  }

  (int, int)? _cellFor(LudoPlayer player, LudoPosition pos) {
    if (pos is LudoPositionPath) {
      if (pos.pathIndex < 0 || pos.pathIndex >= LudoBoardPainter.mainPath.length) {
        return null;
      }
      return LudoBoardPainter.mainPath[pos.pathIndex];
    } else if (pos is LudoPositionStretch) {
      final layout = LudoBoardPainter.stretchLayout[player];
      if (layout == null || pos.stretchIndex >= layout.length) return null;
      return layout[pos.stretchIndex];
    } else if (pos is LudoPositionFinished) {
      // Finished tokens cluster around the center â€” accept any tap
      // within the 3Ã—3 home block.
      return (7, 7);
    } else if (pos is LudoPositionHome) {
      // Yard tokens: accept taps in the player's 6Ã—6 yard.
      final anchor = switch (player) {
        LudoPlayer.red => (1.5 + (pos.yardSlot % 2) * 2, 1.5 + (pos.yardSlot ~/ 2) * 2),
        LudoPlayer.green => (1.5 + (pos.yardSlot % 2) * 2, 9 + 1.5 + (pos.yardSlot ~/ 2) * 2),
        LudoPlayer.yellow => (9 + 1.5 + (pos.yardSlot % 2) * 2, 9 + 1.5 + (pos.yardSlot ~/ 2) * 2),
        LudoPlayer.blue => (9 + 1.5 + (pos.yardSlot % 2) * 2, 1.5 + (pos.yardSlot ~/ 2) * 2),
      };
      // Accept any tap inside the 6Ã—6 yard by returning anchor and
      // letting the bounding-box check below pass. We accept based on
      // the slot center for simplicity.
      return (anchor.$1 ~/ 1, anchor.$2 ~/ 1);
    }
    return null;
  }
}

// ---------------------------------------------------------------------
// HUD helpers + seat chip
// ---------------------------------------------------------------------

Color _seatColor(LudoPlayer p) => switch (p) {
      LudoPlayer.red => const Color(0xFFEF4444),
      LudoPlayer.green => const Color(0xFF22C55E),
      LudoPlayer.yellow => const Color(0xFFCA8A04),
      LudoPlayer.blue => const Color(0xFF1D4ED8),
    };

String _seatName(LudoPlayer p) => switch (p) {
      LudoPlayer.red => 'Red',
      LudoPlayer.green => 'Green',
      LudoPlayer.yellow => 'Yellow',
      LudoPlayer.blue => 'Blue',
    };

/// Small colored pill showing the current seat. Used as the trailing
/// widget of [GameHudBar.customTrailing] so the player can see at a
/// glance whose turn it is.
class _SeatChip extends StatelessWidget {
  const _SeatChip({required this.player});

  final LudoPlayer player;

  @override
  Widget build(BuildContext context) {
    final color = _seatColor(player);
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2),
      ),
      child: Text(
        player.label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 14,
        ),
      ),
    );
  }
}

class _DiceRollBar extends StatefulWidget {
  const _DiceRollBar({required this.controller});

  final LudoController controller;

  @override
  State<_DiceRollBar> createState() => _DiceRollBarState();
}

class _DiceRollBarState extends State<_DiceRollBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;
  int _spinningTo = 0;
  bool _wasRolled = false;
  final _rng = Random();

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    widget.controller.addListener(_onControllerTick);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerTick);
    _spin.dispose();
    super.dispose();
  }

  void _onControllerTick() {
    final rolled = widget.controller.currentState.rolled;
    if (rolled && !_wasRolled) {
      _spinningTo = widget.controller.currentState.dice;
      _spin
        ..reset()
        ..forward();
    }
    _wasRolled = rolled;
  }

  LudoController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final state = controller.currentState;
        final showRoll = controller.isHumanTurn && !state.rolled && !controller.hasEnded;
        final showDice = state.rolled && !controller.hasEnded;
        final showEnded = controller.hasEnded;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (showRoll)
                ElevatedButton.icon(
                  onPressed: () => controller.rollDice(),
                  icon: const Icon(Icons.casino),
                  label: const Text('Roll dice'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.md,
                    ),
                  ),
                )
              else if (showDice)
                AnimatedBuilder(
                  animation: _spin,
                  builder: (context, _) {
                    final t = _spin.value;
                    final pip = t < 0.85
                        ? (1 + _rng.nextInt(6))
                        : _spinningTo;
                    final pop = t < 0.85
                        ? 1.0
                        : 1.0 + 0.18 * (1 - (t - 0.85) / 0.15);
                    return Transform.scale(
                      scale: pop.clamp(0.85, 1.18),
                      child: _DiceChip(value: pip),
                    );
                  },
                )
              else if (showEnded)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Game over',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else
                // Bot turn: show a "thinkingâ€¦" indicator.
                _BotThinking(),
            ],
          ),
        );
      },
    );
  }
}

class _DiceChip extends StatelessWidget {
  const _DiceChip({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.accent, width: 2),
      ),
      child: Center(
        child: Text(
          '$value',
          style: theme.textTheme.headlineMedium?.copyWith(
            color: AppColors.accent,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _BotThinking extends StatefulWidget {
  @override
  State<_BotThinking> createState() => _BotThinkingState();
}

class _BotThinkingState extends State<_BotThinking>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return AnimatedBuilder(
          animation: _ac,
          builder: (context, _) {
            final t = (_ac.value - i * 0.18).clamp(0.0, 1.0);
            final scale = 0.7 + (t < 0.5 ? t * 0.6 : (1 - t) * 0.6);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: 10 * scale,
              height: 10 * scale,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
              ),
            );
          },
        );
      }),
    );
  }
}
