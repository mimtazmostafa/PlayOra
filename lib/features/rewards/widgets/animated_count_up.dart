import 'package:flutter/material.dart';

/// Animates an integer from its previous value to [target] using a
/// tween + easing. Re-uses the existing [AnimationController] when
/// possible so consecutive rewards stack into a single animation.
class AnimatedCountUp extends StatelessWidget {
  const AnimatedCountUp({
    super.key,
    required this.target,
    required this.textStyle,
    this.duration = const Duration(milliseconds: 900),
    this.prefix = '',
    this.suffix = '',
  });

  final int target;
  final TextStyle? textStyle;
  final Duration duration;
  final String prefix;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    return _AnimatedCountUpStateful(
      target: target,
      textStyle: textStyle,
      duration: duration,
      prefix: prefix,
      suffix: suffix,
    );
  }
}

class _AnimatedCountUpStateful extends StatefulWidget {
  const _AnimatedCountUpStateful({
    required this.target,
    required this.textStyle,
    required this.duration,
    required this.prefix,
    required this.suffix,
  });

  final int target;
  final TextStyle? textStyle;
  final Duration duration;
  final String prefix;
  final String suffix;

  @override
  State<_AnimatedCountUpStateful> createState() =>
      _AnimatedCountUpStatefulState();
}

class _AnimatedCountUpStatefulState extends State<_AnimatedCountUpStateful>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  Animation<int>? _animation;
  int _previous = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _animation = IntTween(begin: 0, end: widget.target).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant _AnimatedCountUpStateful oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.target != oldWidget.target) {
      // Pick up where we left off — animated integers can stack
      // (e.g. multiple awards in flight) and we want the visual to
      // continue smoothly.
      final current = _animation?.value ?? _previous;
      _previous = current;
      _animation = IntTween(begin: current, end: widget.target).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
      );
      _controller
        ..stop()
        ..forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation ?? const AlwaysStoppedAnimation(0),
      builder: (context, _) {
        final value = _animation?.value ?? widget.target;
        return Text(
          '${widget.prefix}$value${widget.suffix}',
          style: widget.textStyle,
        );
      },
    );
  }
}