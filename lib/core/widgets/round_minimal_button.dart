import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/audio_engine.dart';

/// Minimalist round icon button used by the in-game HUD and the
/// home/category top bars. Renders as a 40×40 circle with a centered
/// icon; tapping fires a click haptic + tap audio cue.
class RoundMinimalButton extends ConsumerWidget {
  const RoundMinimalButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.color,
    this.size = 40,
    this.iconSize = 20,
    this.semanticLabel,
  });

  /// Material icon glyph (rounded variants read best).
  final IconData icon;

  /// Tap handler. Fires haptic + audio before invoking.
  final VoidCallback onTap;

  /// Long-press / accessibility tooltip.
  final String? tooltip;

  /// Background tint. Defaults to translucent black so it works on
  /// any game viewport. Set to `Colors.white` for use on light/dark
  /// themed chrome.
  final Color? color;

  /// Diameter in logical pixels.
  final double size;

  /// Glyph size in logical pixels.
  final double iconSize;

  /// Accessibility label — defaults to [tooltip] when unset.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bg = color ?? Colors.black.withValues(alpha: 0.40);
    final iconColor = color == Colors.white ? Colors.black : Colors.white;
    return Tooltip(
      message: tooltip ?? '',
      child: Semantics(
        label: semanticLabel ?? tooltip,
        button: true,
        child: Material(
          color: bg,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () {
              HapticFeedback.lightImpact();
              unawaited(
                ref.read(audioEngineProvider).playTap(
                      ref.watch(soundOnProvider),
                    ),
              );
              onTap();
            },
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, color: iconColor, size: iconSize),
            ),
          ),
        ),
      ),
    );
  }
}
