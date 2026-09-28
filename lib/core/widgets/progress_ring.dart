import 'package:flutter/material.dart';

import '../theme/nova_colors.dart';

/// Animated circular progress ring (course progress, goals).
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.percent,
    required this.size,
    this.strokeWidth = 8,
    this.trackColor,
    this.color,
    this.child,
  });

  final int percent;
  final double size;
  final double strokeWidth;
  final Color? trackColor;

  /// Defaults to the brand accent; override on coloured cards.
  final Color? color;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: percent.clamp(0, 100) / 100),
      duration: const Duration(milliseconds: 1100),
      curve: Curves.easeOutCubic,
      builder: (BuildContext context, double value, Widget? child) {
        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: size,
                height: size,
                child: CircularProgressIndicator(
                  value: value,
                  strokeWidth: strokeWidth,
                  strokeCap: StrokeCap.round,
                  backgroundColor:
                      trackColor ?? NovaColors.borderOnLight,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    color ?? NovaColors.accent,
                  ),
                ),
              ),
              ?child,
            ],
          ),
        );
      },
      child: child,
    );
  }
}

/// Animated horizontal progress bar with rounded caps.
class ProgressBar extends StatelessWidget {
  const ProgressBar({
    super.key,
    required this.percent,
    this.height = 7,
    this.trackColor,
    this.color = NovaColors.accent,
  });

  final int percent;
  final double height;
  final Color? trackColor;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: percent.clamp(0, 100) / 100),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (BuildContext context, double value, _) => ClipRRect(
        borderRadius: BorderRadius.circular(100),
        child: LinearProgressIndicator(
          value: value,
          minHeight: height,
          backgroundColor: trackColor ?? NovaColors.borderOnLight,
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      ),
    );
  }
}
