import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Reusable animated score popup overlay for game juice ("+100!",
/// "GREAT!", "SWISH!").
///
/// Call sites push a [_Floater] via the public [GlobalKey<_FloatingTextOverlayState>]
/// held by the host; the overlay floats upward, scales up briefly,
/// then fades out and self-removes. Multiple floaters can stack — each
/// one renders in its own [_FloaterEntry] widget inside an overlay
/// [Stack].
///
/// The overlay is non-interactive ([IgnorePointer]) so taps still
/// reach the canvas behind it. The widget is intended to be stacked
/// on top of the game's CustomPaint viewport.
class FloatingTextOverlay extends StatefulWidget {
  const FloatingTextOverlay({
    super.key,
    this.lifeSeconds = 0.9,
    this.riseDistance = 64,
    this.peakScale = 1.25,
    this.defaultColor,
    this.defaultFontSize = 26,
  });

  /// Total time a floater is visible (rise + hold + fade). The fade
  /// starts at ~60% of this window so the floater feels snappy.
  final double lifeSeconds;

  /// How many dp a floater rises before disappearing. Default tuned
  /// to "rises about a thumb's width" so the text reads without
  /// drifting off screen on small phones.
  final double riseDistance;

  /// Peak scale factor during the entrance bounce. 1.0 = no scale;
  /// 1.25 = visible pop without feeling cartoonish.
  final double peakScale;

  /// Default floater colour. Individual entries can override.
  final Color? defaultColor;

  /// Default floater font size. Individual entries can override.
  final double defaultFontSize;

  @override
  State<FloatingTextOverlay> createState() => FloatingTextOverlayState();
}

/// Public controller for [FloatingTextOverlay].
///
/// Usage:
/// ```dart
/// final _floatKey = GlobalKey<FloatingTextOverlayState>();
/// ...
/// _floatKey.currentState?.show(
///   '+50',
///   Offset(120, 80),
///   color: const Color(0xFFFFC529),
/// );
/// ```
class FloatingTextOverlayState extends State<FloatingTextOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  final List<_FloaterEntry> _entries = [];
  int _idSeq = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Emit a new floater with [text] anchored at [anchor] (widget-local
  /// coordinates). Optional [color] / [fontSize] override the overlay
  /// defaults; [icon] renders next to the text if provided.
  void show(
    String text,
    Offset anchor, {
    Color? color,
    double? fontSize,
    IconData? icon,
    double lifeSecondsOverride = 0,
  }) {
    final entry = _FloaterEntry(
      id: _idSeq++,
      text: text,
      anchor: anchor,
      color: color ?? widget.defaultColor ?? Colors.white,
      fontSize: fontSize ?? widget.defaultFontSize,
      lifeSeconds: lifeSecondsOverride > 0
          ? lifeSecondsOverride
          : widget.lifeSeconds,
      riseDistance: widget.riseDistance,
      peakScale: widget.peakScale,
      icon: icon,
      onComplete: _remove,
    );
    setState(() => _entries.add(entry));
  }

  /// Drop all in-flight floaters. Useful on game-over or when the
  /// host navigates away.
  void clear() {
    if (_entries.isEmpty) return;
    setState(_entries.clear);
  }

  void _remove(int id) {
    if (!mounted) return;
    setState(() => _entries.removeWhere((e) => e.id == id));
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final e in _entries) _FloaterWidget(entry: e),
        ],
      ),
    );
  }
}

class _FloaterEntry {
  _FloaterEntry({
    required this.id,
    required this.text,
    required this.anchor,
    required this.color,
    required this.fontSize,
    required this.lifeSeconds,
    required this.riseDistance,
    required this.peakScale,
    required this.onComplete,
    this.icon,
  });
  final int id;
  final String text;
  final Offset anchor;
  final Color color;
  final double fontSize;
  final double lifeSeconds;
  final double riseDistance;
  final double peakScale;
  final IconData? icon;
  final ValueChanged<int> onComplete;
}

class _FloaterWidget extends StatefulWidget {
  const _FloaterWidget({required this.entry});
  final _FloaterEntry entry;

  @override
  State<_FloaterWidget> createState() => _FloaterWidgetState();
}

class _FloaterWidgetState extends State<_FloaterWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (widget.entry.lifeSeconds * 1000).round()),
    );
    _ctrl.forward().whenComplete(() {
      if (mounted) widget.entry.onComplete(widget.entry.id);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) {
        final t = _ctrl.value;
        // Bounce: scale up fast then settle. Phase = 0→1 covers the
        // entire lifetime, but the scale curve uses the first 25%.
        final scalePhase = (t / 0.25).clamp(0.0, 1.0);
        final ease = Curves.easeOutBack.transform(scalePhase);
        final scale = 1.0 + (e.peakScale - 1.0) * ease;
        // Rise: starts at 0, ends at riseDistance. Cubic ease so the
        // motion settles softly.
        final rise = e.riseDistance * Curves.easeOutCubic.transform(t);
        // Fade: hold full opacity until 60%, then fade out.
        final alpha = t < 0.6
            ? 1.0
            : ((1.0 - t) / 0.4).clamp(0.0, 1.0);
        return Positioned(
          left: e.anchor.dx,
          top: e.anchor.dy - rise,
          child: IgnorePointer(
            child: Opacity(
              opacity: alpha,
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.center,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35 * alpha),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (e.icon != null) ...[
                        Icon(e.icon, color: e.color, size: e.fontSize),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        e.text,
                        style: TextStyle(
                          color: e.color,
                          fontSize: e.fontSize,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.4,
                          shadows: const [
                            Shadow(
                              color: Color.fromRGBO(0, 0, 0, 0.55),
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Lightweight variant that paints a single floater without the
/// controller lifecycle — useful for tests and previews that just
/// want a static "SWISH!" example on screen.
class StaticFloaterLabel extends StatelessWidget {
  const StaticFloaterLabel({
    super.key,
    required this.text,
    this.color = AppColors.hudAccentYellow,
    this.fontSize = 26,
    this.icon,
  });
  final String text;
  final Color color;
  final double fontSize;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: color, size: fontSize),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
              shadows: const [
                Shadow(
                  color: Color.fromRGBO(0, 0, 0, 0.55),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}