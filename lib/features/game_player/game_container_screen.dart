import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/audio/audio_engine.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/round_minimal_button.dart';
import '../../data/models/game_difficulty.dart';
import '../../data/registry/game_registry.dart';
import '../games/game_widgets.dart';
import '../games/games_providers.dart';
import '../settings/settings_controller.dart';
import 'games_dispatcher.dart';
import 'widgets/animated_star.dart';
import 'widgets/confetti_shower.dart';
import 'widgets/floating_text_overlay.dart';
import 'widgets/game_hud_bar.dart';
import 'widgets/particle_system_widget.dart';

/// Universal full-screen launcher viewport for any mini-game.
///
/// Responsibilities:
///   1. Resolve the requested [RegistryGame] by id.
///   2. Paint a single redesigned top HUD bar — minimalist round
///      control buttons (back / pause / restart / sound / haptics) +
///      level + difficulty chips + score, no debug text overlays.
///   3. Mount the game-specific viewport via [GamesDispatcher].
///   4. Show the polished game-over screen with score / XP / new
///      high-score badge and "Play Again" / "Home" actions.
///   5. Pair every haptic with an audio cue through [AudioEngine]
///      so all 35 games get sound + tactile feedback for free.
///
/// Why a single screen for all games?
///
///   * One set of overlay widgets is easier to keep on-brand than 20.
///   * Sound / haptic / pause state stays scoped to a single route.
///   * Auto-hiding the bottom tab bar is already handled at the shell
///     level via `HideBottomNav` — the container sits above it.
class GameContainerScreen extends ConsumerStatefulWidget {
  const GameContainerScreen({
    super.key,
    required this.gameId,
    this.level = 1,
  });

  /// Registry id (slug) of the game to launch.
  final String gameId;

  /// 1-indexed level passed in via `?level=N`. Mini-games can ignore
  /// it (endless-score games) or use it to seed difficulty (level-based
  /// puzzles).
  final int level;

  @override
  ConsumerState<GameContainerScreen> createState() => _GameContainerScreenState();
}

class _GameContainerScreenState extends ConsumerState<GameContainerScreen>
    with TickerProviderStateMixin {
  bool _paused = false;
  bool _gameOver = false;
  bool _newHighScore = false;
  int _score = 0;
  int _highScore = 0;
  String _statsLabel = '';

  // ─── Universal juice layer (particle + floaters) ──────────────
  /// Keys for the host's reusable particle + floater overlays.
  /// Mini-games can request them via the [MiniGameCallbacks] for
  /// universal score popups; for now they're hosted locally and
  /// exercised by the host's own game-over / pause triggers.
  final GlobalKey<ParticleSystemWidgetState> _particleKey =
      GlobalKey<ParticleSystemWidgetState>();
  final GlobalKey<FloatingTextOverlayState> _floaterKey =
      GlobalKey<FloatingTextOverlayState>();

  // ─── Entry animations ──────────────────────────────────────────
  late final AnimationController _entryCtrl;
  late final Animation<double> _entryFade;

  // ─── Pause / game-over entry animations ────────────────────────
  late final AnimationController _overlayCtrl;
  late final Animation<double> _overlayScale;
  late final Animation<double> _overlayFade;

  /// Per-game secondary stats surfaced through the host's HUD subtitle
  /// (e.g. "Moves 4", "Balls 3", "Shots 5"). Each mini-game reports a
  /// label + value via [GamesDispatcher] → `onStatsChanged`.
  @override
  void initState() {
    super.initState();
    // Lock to portrait so touch controls stay natural.
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..forward();
    _entryFade = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);

    _overlayCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _overlayScale = Tween<double>(begin: 0.92, end: 1).animate(
      CurvedAnimation(parent: _overlayCtrl, curve: Curves.easeOutBack),
    );
    _overlayFade = CurvedAnimation(parent: _overlayCtrl, curve: Curves.easeOut);

    // Tiny welcome haptic + tap sound so the launch feels tactile.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      HapticFeedback.lightImpact();
      unawaited(
        ref.read(audioEngineProvider).playTap(ref.watch(soundOnProvider)),
      );
    });
  }

  @override
  void dispose() {
    // Restore the global orientation preference — leaving portrait
    // locked forever would surprise users returning to the launcher.
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _entryCtrl.dispose();
    _overlayCtrl.dispose();
    super.dispose();
  }

  // ─── Haptic + audio helpers ───────────────────────────────────

  void _haptic(HapticFeedbackType t) {
    final settings = ref.read(settingsControllerProvider);
    if (!settings.hapticsOn) return;
    switch (t) {
      case HapticFeedbackType.light:
        HapticFeedback.lightImpact();
        break;
      case HapticFeedbackType.medium:
        HapticFeedback.mediumImpact();
        break;
      case HapticFeedbackType.heavy:
        HapticFeedback.heavyImpact();
        break;
      case HapticFeedbackType.selection:
        HapticFeedback.selectionClick();
        break;
    }
    // Pair every haptic with an audio cue.
    final engine = ref.read(audioEngineProvider);
    final soundOn = ref.read(soundOnProvider);
    switch (t) {
      case HapticFeedbackType.light:
      case HapticFeedbackType.selection:
        unawaited(engine.playTap(soundOn));
        break;
      case HapticFeedbackType.medium:
        unawaited(engine.playWin(soundOn));
        break;
      case HapticFeedbackType.heavy:
        unawaited(engine.playError(soundOn));
        break;
    }
  }

  // ─── Mini-game callback forwarding ─────────────────────────────

  void _onScoreChanged(int newScore) {
    if (newScore == _score) return;
    setState(() => _score = newScore);
  }

  void _onStatsChanged(String stats) {
    if (stats == _statsLabel) return;
    setState(() => _statsLabel = stats);
  }

  void _onGameOver() {
    final wasHigh = _score > _highScore;
    if (wasHigh) _haptic(HapticFeedbackType.medium);
    // Mark the level as completed so the next one unlocks. Endless
    // games (Snake, 2048…) have total == 0 in the catalog; skip them.
    final repo = ref.read(levelProgressRepositoryProvider);
    if (repo.totalFor(widget.gameId) > 0) {
      ref
          .read(levelProgressControllerProvider)
          .markCompleted(widget.gameId, widget.level);
    }
    setState(() {
      _gameOver = true;
      if (wasHigh) {
        _highScore = _score;
        _newHighScore = true;
      }
    });
    // Juice: celebratory burst + "LEVEL COMPLETE!" floater on game over.
    final size = MediaQuery.of(context).size;
    final center = Offset(size.width / 2, size.height / 2);
    _particleKey.currentState?.emit(
      center,
      count: 24,
      speed: 280,
      colors: const [
        Color(0xFF4C73FF),
        Color(0xFFFF6584),
        Color(0xFFFFC837),
        Color(0xFF30D158),
        Color(0xFFA073FF),
      ],
    );
    _floaterKey.currentState?.show(
      'LEVEL COMPLETE!',
      center,
      color: AppColors.hudAccentYellow,
      fontSize: 22,
      icon: Icons.emoji_events_rounded,
      lifeSecondsOverride: 1.4,
    );
    _overlayCtrl.forward(from: 0);
  }

  void _restart() {
    setState(() {
      _score = 0;
      _gameOver = false;
      _newHighScore = false;
      _paused = false;
      _statsLabel = '';
    });
    _overlayCtrl.reverse();
    _haptic(HapticFeedbackType.selection);
  }

  void _exitToHome() {
    context.go(AppRoutes.home);
  }

  void _showPauseOverlay() {
    setState(() => _paused = true);
    _overlayCtrl.forward(from: 0);
  }

  void _resumeFromPause() {
    setState(() => _paused = false);
    _overlayCtrl.reverse();
  }

  Future<void> _confirmRestart() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restart game?'),
        content: const Text('Your current progress will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Restart'),
          ),
        ],
      ),
    );
    if (ok == true) _restart();
  }

  // ─── Settings flips ───────────────────────────────────────────

  void _toggleSound() {
    final settings = ref.read(settingsControllerProvider);
    _setSoundOn(!settings.soundOn);
  }

  void _setSoundOn(bool value) {
    ref.read(settingsControllerProvider.notifier).setSoundOn(value);
    _haptic(HapticFeedbackType.selection);
  }

  void _toggleHaptics() {
    final settings = ref.read(settingsControllerProvider);
    _setHapticsOn(!settings.hapticsOn);
  }

  void _setHapticsOn(bool value) {
    ref.read(settingsControllerProvider.notifier).setHapticsOn(value);
    _haptic(HapticFeedbackType.selection);
  }

  @override
  Widget build(BuildContext context) {
    final game = GameRegistry.byId(widget.gameId);
    if (game == null) {
      return _UnknownGameView(gameId: widget.gameId);
    }
    final settings = ref.watch(settingsControllerProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF080B12),
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            // ─── Game viewport (gradient + dynamic bounds) ───
            Positioned.fill(
              child: FadeTransition(
                opacity: _entryFade,
                child: _CanvasSurface(
                  accent: game.accent,
                  child: LayoutBuilder(
                    builder: (ctx, constraints) => Stack(
                      fit: StackFit.expand,
                      children: [
                        _GameViewport(
                          game: game,
                          level: widget.level,
                          paused: _paused || _gameOver,
                          soundOn: settings.soundOn,
                          hapticsOn: settings.hapticsOn,
                          onScoreChanged: _onScoreChanged,
                          onStatsChanged: _onStatsChanged,
                          onGameOver: _onGameOver,
                          onHaptic: _haptic,
                        ),
                        // Universal juice layer — sits above the canvas
                        // and below the HUD bar so taps still pass through
                        // to the game.
                        IgnorePointer(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ParticleSystemWidget(key: _particleKey),
                              FloatingTextOverlay(key: _floaterKey),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // ─── Top HUD bar ───
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _TopHudBar(
                title: game.title,
                statsLabel: _statsLabel,
                score: _score,
                paused: _paused,
                soundOn: settings.soundOn,
                hapticsOn: settings.hapticsOn,
                accent: game.accent,
                level: widget.level,
                difficulty: _difficultyLabel(game.difficulty),
                onBack: _exitToHome,
                onPauseToggle: () {
                  if (_paused) {
                    _resumeFromPause();
                  } else {
                    _showPauseOverlay();
                  }
                },
                onRestart: _confirmRestart,
                onSoundToggle: _toggleSound,
                onHapticsToggle: _toggleHaptics,
              ),
            ),
            // ─── Pause overlay ───
            if (_paused && !_gameOver)
              Positioned.fill(
                child: _PauseOverlay(
                  scale: _overlayScale,
                  fade: _overlayFade,
                  settings: settings,
                  onSetSoundOn: _setSoundOn,
                  onSetHapticsOn: _setHapticsOn,
                  onResume: _resumeFromPause,
                  onHome: _exitToHome,
                  onRestart: _confirmRestart,
                ),
              ),
            // ─── Game-over screen ───
            if (_gameOver)
              Positioned.fill(
                child: _GameOverOverlay(
                  scale: _overlayScale,
                  fade: _overlayFade,
                  score: _score,
                  highScore: _highScore,
                  isNewHigh: _newHighScore,
                  onPlayAgain: _restart,
                  onHome: _exitToHome,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Maps [GameDifficulty] to a human label. "EXTRA HARD" is reserved
  /// for the trickiest brain games (Chess, Sudoku) so the chip always
  /// reads as either of: EASY / MEDIUM / HARD / EXTRA HARD.
  static String _difficultyLabel(GameDifficulty d) {
    return switch (d) {
      GameDifficulty.easy => 'EASY',
      GameDifficulty.medium => 'MEDIUM',
      GameDifficulty.hard => 'HARD',
    };
  }
}

// ─────────────────────────────────────────────────────────────────
// Top HUD bar — minimalist round control buttons + level / difficulty
// chips + the canonical GameHudBar score row. Single source of truth
// for SCORE / LEVEL.
// ─────────────────────────────────────────────────────────────────

class _TopHudBar extends StatelessWidget {
  const _TopHudBar({
    required this.title,
    required this.statsLabel,
    required this.score,
    required this.paused,
    required this.soundOn,
    required this.hapticsOn,
    required this.accent,
    required this.level,
    required this.difficulty,
    required this.onBack,
    required this.onPauseToggle,
    required this.onRestart,
    required this.onSoundToggle,
    required this.onHapticsToggle,
  });

  final String title;
  final String statsLabel;
  final int score;
  final bool paused;
  final bool soundOn;
  final bool hapticsOn;
  final Color accent;
  final int level;
  final String difficulty;
  final VoidCallback onBack;
  final VoidCallback onPauseToggle;
  final VoidCallback onRestart;
  final VoidCallback onSoundToggle;
  final VoidCallback onHapticsToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(
        top: AppSpacing.xs,
        bottom: AppSpacing.sm,
        left: AppSpacing.md,
        right: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.65),
            Colors.black.withValues(alpha: 0.0),
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: minimalist round control buttons.
          Row(
            children: [
              RoundMinimalButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Back to home',
                onTap: onBack,
              ),
              const SizedBox(width: 8),
              RoundMinimalButton(
                icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                tooltip: paused ? 'Resume' : 'Pause',
                onTap: onPauseToggle,
              ),
              const SizedBox(width: 8),
              RoundMinimalButton(
                icon: Icons.refresh_rounded,
                tooltip: 'Restart',
                onTap: onRestart,
              ),
              const Spacer(),
              RoundMinimalButton(
                icon: soundOn
                    ? Icons.volume_up_rounded
                    : Icons.volume_off_rounded,
                tooltip: soundOn ? 'Sound on' : 'Sound off',
                onTap: onSoundToggle,
              ),
              const SizedBox(width: 8),
              RoundMinimalButton(
                icon: hapticsOn
                    ? Icons.vibration_rounded
                    : Icons.smartphone_rounded,
                tooltip: hapticsOn ? 'Haptics on' : 'Haptics off',
                onTap: onHapticsToggle,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // Row 2: level + difficulty chips, then score / title.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              LevelChip(level: level),
              const SizedBox(width: 6),
              DifficultyChip(difficulty: difficulty),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: GameHudBar(
                  title: title,
                  subtitle: statsLabel,
                  subtitleColor: Colors.white70,
                  score: score,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Canvas surface — applies the night-arcade / outdoor-sky gradient
// behind the game viewport. Lives at the host layer so every game
// gets the same backdrop without having to paint its own.
// ─────────────────────────────────────────────────────────────────

class _CanvasSurface extends StatelessWidget {
  const _CanvasSurface({required this.accent, required this.child});
  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isOutdoor = _isOutdoorAccent(accent);
    final colors = isOutdoor
        ? const [
            AppColors.outdoorSkyGradientStart,
            AppColors.outdoorSkyGradientEnd,
          ]
        : const [
            AppColors.nightArcadeGradientStart,
            AppColors.nightArcadeGradientEnd,
          ];
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
        ),
      ),
      child: child,
    );
  }

  /// Heuristic: outdoor-sports games (green, yellow, orange accents)
  /// get the sky-blue gradient. Everything else (puzzle / arcade /
  /// match games) gets the night-arcade gradient.
  bool _isOutdoorAccent(Color c) {
    final hsl = HSLColor.fromColor(c);
    // Outdoor palette tends to sit in the green / yellow / orange range
    // with mid-high lightness. Night games lean blue / purple / pink
    // with lower lightness.
    return hsl.lightness > 0.45 &&
        (hsl.hue >= 60 && hsl.hue <= 170);
  }
}

// ─────────────────────────────────────────────────────────────────
// Game viewport — dispatches to the right mini-game. Sits inside the
// host's [LayoutBuilder] so all engines see dynamic canvas bounds
// without each game having to wrap itself in one.
// ─────────────────────────────────────────────────────────────────

class _GameViewport extends StatelessWidget {
  const _GameViewport({
    required this.game,
    required this.level,
    required this.paused,
    required this.soundOn,
    required this.hapticsOn,
    required this.onScoreChanged,
    required this.onStatsChanged,
    required this.onGameOver,
    required this.onHaptic,
  });

  final RegistryGame game;
  final int level;
  final bool paused;
  final bool soundOn;
  final bool hapticsOn;
  final ValueChanged<int> onScoreChanged;
  final ValueChanged<String> onStatsChanged;
  final VoidCallback onGameOver;
  final ValueChanged<HapticFeedbackType> onHaptic;

  @override
  Widget build(BuildContext context) {
    return GamesDispatcher(
      game: game,
      level: level,
      paused: paused,
      soundOn: soundOn,
      hapticsOn: hapticsOn,
      onScoreChanged: onScoreChanged,
      onStatsChanged: onStatsChanged,
      onGameOver: onGameOver,
      onHaptic: onHaptic,
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Pause overlay — scale+fade entrance, single CTA primary, secondary
// "Restart" + "Quit to Home".
// ─────────────────────────────────────────────────────────────────

class _PauseOverlay extends StatelessWidget {
  const _PauseOverlay({
    required this.scale,
    required this.fade,
    required this.settings,
    required this.onSetSoundOn,
    required this.onSetHapticsOn,
    required this.onResume,
    required this.onHome,
    required this.onRestart,
  });
  final Animation<double> scale;
  final Animation<double> fade;
  final AppSettingsState settings;
  final ValueChanged<bool> onSetSoundOn;
  final ValueChanged<bool> onSetHapticsOn;
  final VoidCallback onResume;
  final VoidCallback onHome;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.65),
      alignment: Alignment.center,
      child: FadeTransition(
        opacity: fade,
        child: ScaleTransition(
          scale: scale,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg, vertical: AppSpacing.lg),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Mascot crown header.
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.reward.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.emoji_events_rounded,
                    size: 38,
                    color: AppColors.reward,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                const Text(
                  'PAUSED',
                  style: TextStyle(
                    color: AppColors.primaryInk,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _SettingsRow(
                  icon: Icons.volume_up_rounded,
                  label: 'Music',
                  value: settings.soundOn,
                  onChanged: onSetSoundOn,
                ),
                const SizedBox(height: AppSpacing.xs),
                _SettingsRow(
                  icon: Icons.graphic_eq_rounded,
                  label: 'SFX',
                  value: settings.soundOn,
                  onChanged: onSetSoundOn,
                ),
                const SizedBox(height: AppSpacing.xs),
                _SettingsRow(
                  icon: Icons.vibration_rounded,
                  label: 'Vibrate',
                  value: settings.hapticsOn,
                  onChanged: onSetHapticsOn,
                ),
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onResume,
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: const Text(
                      'RESUME GAME',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.play,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: const StadiumBorder(),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onHome,
                    icon: const Icon(Icons.close_rounded),
                    label: const Text(
                      'QUIT',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.playInk,
                      side: BorderSide(
                        color: AppColors.playInk.withValues(alpha: 0.5),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: const StadiumBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.backgroundLight,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.playInk, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.playInk,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeTrackColor: AppColors.play,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Game-over screen — scale+fade entrance, sparkle-burst behind trophy,
// XP / score / high-score summary, "Play Again" + "Home".
// ─────────────────────────────────────────────────────────────────

class _GameOverOverlay extends StatefulWidget {
  const _GameOverOverlay({
    required this.scale,
    required this.fade,
    required this.score,
    required this.highScore,
    required this.isNewHigh,
    required this.onPlayAgain,
    required this.onHome,
  });

  final Animation<double> scale;
  final Animation<double> fade;
  final int score;
  final int highScore;
  final bool isNewHigh;
  final VoidCallback onPlayAgain;
  final VoidCallback onHome;

  @override
  State<_GameOverOverlay> createState() => _GameOverOverlayState();
}

class _GameOverOverlayState extends State<_GameOverOverlay> {
  int _xpGained() {
    final base = widget.score * 10;
    return base + (widget.isNewHigh ? 50 : 0);
  }

  int _starsEarned() {
    if (widget.score <= 0) return 1;
    if (widget.score < 80) return 1;
    if (widget.score < 250) return 2;
    return 3;
  }

  int _coinsEarned() {
    return (widget.score * 0.4).round().clamp(50, 500) + 100;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Dimmed backdrop + confetti shower behind the dialog.
        Container(color: Colors.black.withValues(alpha: 0.7)),
        const Positioned.fill(child: ConfettiShower()),
        Center(
          child: FadeTransition(
            opacity: widget.fade,
            child: ScaleTransition(
              scale: widget.scale,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg, vertical: AppSpacing.lg),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 28,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header with gradient "LEVEL COMPLETED!" text.
                    Text(
                      'LEVEL COMPLETED!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                        foreground: Paint()
                          ..shader = const LinearGradient(
                            colors: [
                              Color(0xFFFFC837),
                              Color(0xFFFF6584),
                            ],
                          ).createShader(
                            const Rect.fromLTWH(0, 0, 240, 30),
                          ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    // 3 animated stars.
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(3, (i) {
                        final earned = i < _starsEarned();
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: AnimatedStar(
                            size: 48,
                            filled: earned,
                            delay: Duration(milliseconds: 220 * i),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    // Reward card.
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundLight,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          _RewardRow(
                            label: 'Final Score',
                            value: _formatScore(widget.score),
                            valueStyle: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: AppColors.playInk,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          const SizedBox(height: 8),
                          _RewardRow(
                            label: 'XP Gained',
                            value: '+${_xpGained()}',
                            valueStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.rewardInk,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFFFFC837),
                                        Color(0xFFB45309),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.lock_open_rounded,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'COINS',
                                  style: TextStyle(
                                    color: AppColors.textSecondaryLight,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '+${_coinsEarned()}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.playInk,
                                    fontFeatures: [
                                      FontFeature.tabularFigures()
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: widget.onPlayAgain,
                        icon: const Icon(Icons.arrow_forward_rounded),
                        label: const Text(
                          'NEXT LEVEL',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.play,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: const StadiumBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: widget.onHome,
                        icon: const Icon(Icons.home_rounded),
                        label: const Text(
                          'HOME',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.playInk,
                          side: BorderSide(
                            color: AppColors.playInk.withValues(alpha: 0.5),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: const StadiumBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _formatScore(int score) {
    final s = score.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

class _RewardRow extends StatelessWidget {
  const _RewardRow({
    required this.label,
    required this.value,
    required this.valueStyle,
  });
  final String label;
  final String value;
  final TextStyle valueStyle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondaryLight,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
        Text(value, style: valueStyle),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Unknown game fallback
// ─────────────────────────────────────────────────────────────────

class _UnknownGameView extends StatelessWidget {
  const _UnknownGameView({required this.gameId});

  final String gameId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: const Text('Game not found'),
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.help_outline_rounded,
                  size: 56, color: scheme.onSurfaceVariant),
              const SizedBox(height: AppSpacing.md),
              Text(
                'No game found for id "$gameId".',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                onPressed: () => context.go(AppRoutes.home),
                icon: const Icon(Icons.home_rounded),
                label: const Text('Back to Home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
