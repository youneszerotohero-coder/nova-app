import 'package:flutter/material.dart';

import '../theme/nova_colors.dart';

/// The weekly activity bars from the reference progress card: one
/// rounded column per day, the busiest day filled with the hue, each
/// column growing from zero the first time it is shown.
class WeeklyBars extends StatelessWidget {
  const WeeklyBars({
    super.key,
    required this.values,
    required this.labels,
    this.hue = NovaHue.peach,
    this.highlight,
    this.barHeight = 116,
    this.onColor = false,
  });

  /// One value per column; the tallest sets the scale.
  final List<int> values;
  final List<String> labels;
  final NovaHue hue;

  /// Column to fill with the hue. Defaults to the tallest.
  final int? highlight;
  final double barHeight;

  /// Rendering on a colour block rather than paper.
  final bool onColor;

  @override
  Widget build(BuildContext context) {
    final int max = values.isEmpty
        ? 1
        : values.reduce((int a, int b) => a > b ? a : b).clamp(1, 1 << 30);
    final int peak = highlight ?? values.indexOf(max);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: barHeight + 26,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (int i = 0; i < values.length; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _Bar(
                      value: values[i],
                      fraction: values[i] / max,
                      height: barHeight,
                      hue: hue,
                      active: i == peak,
                      onColor: onColor,
                      delay: Duration(milliseconds: 60 * i),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final String label in labels)
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    fontSize: 11.5,
                    color: onColor
                        ? Colors.white.withValues(alpha: 0.8)
                        : NovaColors.textMuted,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.value,
    required this.fraction,
    required this.height,
    required this.hue,
    required this.active,
    required this.onColor,
    required this.delay,
  });

  final int value;
  final double fraction;
  final double height;
  final NovaHue hue;
  final bool active;
  final bool onColor;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final Color track = onColor
        ? Colors.white.withValues(alpha: 0.22)
        : hue.surfaceStrong;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: fraction.clamp(0.08, 1)),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (BuildContext context, double grown, _) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              '$value',
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w800,
                fontSize: 12,
                height: 1.4,
                color: active
                    ? (onColor ? Colors.white : hue.onSurface)
                    : (onColor
                        ? Colors.white.withValues(alpha: 0.7)
                        : NovaColors.textMuted),
              ),
            ),
            const SizedBox(height: 5),
            Container(
              height: height * grown,
              decoration: BoxDecoration(
                color: active ? null : track,
                gradient: active ? hue.gradient : null,
                borderRadius: BorderRadius.circular(100),
              ),
            ),
          ],
        );
      },
    );
  }
}
