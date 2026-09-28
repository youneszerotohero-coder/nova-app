import 'dart:async';

import 'package:flutter/material.dart';

/// Shared motion vocabulary: staggered entrances for lists, count-up
/// numbers and a pulsing marker. Page transitions live in the theme
/// (NovaTheme) so every pushed route animates consistently.
///
/// Kept light for average Android phones: short, few at a time, no
/// widget rebuild per frame, and none at all when the phone's "remove
/// animations" accessibility setting is on.

/// Plays a short fade + slide-up entrance once, with an optional start
/// delay so siblings can stagger.
class Entrance extends StatefulWidget {
  const Entrance({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = 14,
  });

  final Widget child;
  final Duration delay;
  final double offset;

  /// No entrance waits longer than this, however long the list.
  static const Duration maxDelay = Duration(milliseconds: 240);

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );
  late final Animation<double> _animation = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  Timer? _start;

  @override
  void initState() {
    super.initState();
    final Duration delay = widget.delay > Entrance.maxDelay ? Entrance.maxDelay : widget.delay;
    if (delay == Duration.zero) {
      _controller.forward();
    } else {
      _start = Timer(delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _start?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return widget.child;
    // FadeTransition only changes a layer's alpha; the translated child
    // is built once and never rebuilt while it animates.
    return FadeTransition(
      opacity: _animation,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (BuildContext context, Widget? child) => Transform.translate(
          offset: Offset(0, (1 - _animation.value) * widget.offset),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}

/// Only the first rows of a list cascade in; the rest, usually below the
/// fold, appear directly.
const int maxStaggered = 6;

/// Wraps a list's children so the first rows cascade in.
/// Usage: `children: stagger(children)` inside a Column, or wrap each
/// item of a ListView with `Entrance(delay: ...)`.
List<Widget> stagger(
  List<Widget> children, {
  Duration step = const Duration(milliseconds: 40),
  Duration base = Duration.zero,
}) {
  return <Widget>[
    for (int i = 0; i < children.length; i++)
      if (i < maxStaggered) Entrance(delay: base + step * i, child: children[i]) else children[i],
  ];
}

/// Animates an integer from zero to [value] (progress counts, points).
class CountUpText extends StatelessWidget {
  const CountUpText(
    this.value, {
    super.key,
    this.style,
    this.suffix = '',
    this.duration = const Duration(milliseconds: 900),
  });

  final int value;
  final TextStyle? style;
  final String suffix;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (BuildContext context, double v, _) => Text(
        '${v.round()}$suffix',
        style: style,
      ),
    );
  }
}

/// Soft infinite pulse used by the LIVE badge.
class Pulse extends StatefulWidget {
  const Pulse({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  State<Pulse> createState() => _PulseState();
}

class _PulseState extends State<Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
    lowerBound: 0.86,
    upperBound: 1.0,
  );

  @override
  void initState() {
    super.initState();
    if (widget.enabled) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(Pulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.enabled) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Its own layer: the endless pulse never repaints the card around it.
  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: ScaleTransition(scale: _controller, child: widget.child),
      );
}

/// Smoothly animates between two colors (used by stateful chips).
class AnimatedColorChip extends ImplicitlyAnimatedWidget {
  const AnimatedColorChip({
    super.key,
    required this.color,
    required this.child,
    this.borderRadius = 100,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    super.duration = const Duration(milliseconds: 240),
    super.curve = Curves.easeOut,
  });

  final Color color;
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;

  @override
  ImplicitlyAnimatedWidgetState<AnimatedColorChip> createState() =>
      _AnimatedColorChipState();
}

class _AnimatedColorChipState extends ImplicitlyAnimatedWidgetState<AnimatedColorChip> {
  ColorTween _tween = ColorTween();

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _tween = visitor(
      _tween,
      widget.color,
      (dynamic value) => ColorTween(begin: value as Color),
    )! as ColorTween;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: widget.padding,
      decoration: BoxDecoration(
        color: _tween.evaluate(animation),
        borderRadius: BorderRadius.circular(widget.borderRadius),
      ),
      child: widget.child,
    );
  }
}
