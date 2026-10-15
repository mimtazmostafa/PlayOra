import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A press-anywhere button that responds to taps with:
///   * AnimatedScale (1.0 ↔ 0.96) during press for tactile feedback.
///   * HapticFeedback.lightImpact() on tap (optional).
///   * Optional rounded "card" surface (color + borderRadius + padding)
///     so callers can build inkwell-style buttons without bringing in
///     Material/InkWell.
///   * Full GestureDetector wiring (onTap, onTapDown, onTapUp,
///     onTapCancel) so press animation cleanly tracks fingers.
///
/// Works in any context (no host coupling). Existing [RoundMinimalButton]
/// can be re-implemented on top of this once we want a wholesale
/// migration; for now it's an opt-in widget used by the new
/// [GameScaffold].
class ScaleTapButton extends StatefulWidget {
  const ScaleTapButton({
    super.key,
    required this.onTap,
    required this.child,
    this.pressedScale = 0.96,
    this.duration = const Duration(milliseconds: 120),
    this.curve = Curves.easeOut,
    this.haptic = true,
    this.borderRadius,
    this.padding,
    this.color,
    this.alignment,
    this.semanticsLabel,
  });

  final VoidCallback onTap;
  final Widget child;
  final double pressedScale;
  final Duration duration;
  final Curve curve;

  /// Fire [HapticFeedback.lightImpact] when the gesture completes.
  final bool haptic;

  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final AlignmentGeometry? alignment;
  final String? semanticsLabel;

  @override
  State<ScaleTapButton> createState() => _ScaleTapButtonState();
}

class _ScaleTapButtonState extends State<ScaleTapButton> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (!mounted) return;
    if (_pressed == v) return;
    setState(() => _pressed = v);
  }

  void _onTap() {
    if (widget.haptic) HapticFeedback.lightImpact();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius;
    final content = Container(
      alignment: widget.alignment,
      padding: widget.padding,
      decoration: radius == null && widget.color == null
          ? null
          : BoxDecoration(
              color: widget.color,
              borderRadius: radius,
            ),
      child: widget.child,
    );

    final button = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: _onTap,
      child: content,
    );

    return Semantics(
      button: true,
      label: widget.semanticsLabel,
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: widget.duration,
        curve: widget.curve,
        child: button,
      ),
    );
  }
}
