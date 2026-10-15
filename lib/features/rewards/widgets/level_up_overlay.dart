import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../rewards_controller.dart';

/// Listens on [levelUpStreamProvider] and shows a celebratory burst
/// every time the player crosses a level threshold. Mounted once at
/// the app root via `MaterialApp.builder`.
class LevelUpOverlay extends ConsumerStatefulWidget {
  const LevelUpOverlay({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<LevelUpOverlay> createState() => _LevelUpOverlayState();
}

class _LevelUpOverlayState extends ConsumerState<LevelUpOverlay>
    with SingleTickerProviderStateMixin {
  OverlayEntry? _entry;
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _controller.addStatusListener(_onStatus);
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_onStatus);
    _controller.dispose();
    _entry?.remove();
    super.dispose();
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _entry != null) {
      _entry!.remove();
      _entry = null;
    }
  }

  void _show(int level) {
    // If a previous burst is still on screen, replace it.
    _entry?.remove();
    final entry = OverlayEntry(builder: (_) => _Burst(level: level));
    _entry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
    _controller
      ..stop()
      ..forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<int>>(levelUpStreamProvider, (previous, next) {
      next.whenData((level) {
        _show(level);
      });
    });
    return widget.child;
  }
}

class _Burst extends StatelessWidget {
  const _Burst({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IgnorePointer(
      child: SafeArea(
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 900),
            curve: Curves.elasticOut,
            builder: (context, t, _) {
              return Opacity(
                opacity: (1 - (1 - t).abs()).clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: 0.6 + (t * 0.6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xl,
                      vertical: AppSpacing.lg,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.accent.withValues(alpha: 0.5),
                          blurRadius: 32,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.auto_awesome_rounded,
                          color: Colors.white,
                          size: 56,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'Level Up!',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Level $level',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}