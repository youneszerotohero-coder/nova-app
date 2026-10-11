import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/widgets/motion.dart';

/// D-132 "how it works" strip (`.unitHowTo`): three dashed steps with a
/// numbered yellow bead, for Students who need the path spelled out.
class HowToStrip extends StatelessWidget {
  const HowToStrip({super.key, required this.steps});

  final List<({IconData icon, String text})> steps;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: [
          for (int i = 0; i < steps.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == steps.length - 1 ? 0 : 8),
              child: Entrance(
                delay: Duration(milliseconds: 80 + 90 * i),
                child: CustomPaint(
                  painter: _DashedFrame(color: NovaColors.accent.withValues(alpha: 0.28), radius: 17),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 52),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(color: NovaColors.paperCard, borderRadius: BorderRadius.circular(17)),
                    child: Row(
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(color: NovaColors.accentMist, borderRadius: BorderRadius.circular(11)),
                              child: Icon(steps[i].icon, size: 18, color: NovaColors.accent),
                            ),
                            PositionedDirectional(
                              top: -7,
                              end: -7,
                              child: Container(
                                width: 19,
                                height: 19,
                                alignment: Alignment.center,
                                decoration: const BoxDecoration(color: NovaColors.yellow, shape: BoxShape.circle),
                                child: Text(
                                  '${i + 1}',
                                  style: const TextStyle(fontFamily: NovaTypography.body, fontWeight: FontWeight.w800, fontSize: 11, color: NovaColors.yellowInk),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text(steps[i].text, style: NovaTypography.textTheme.labelLarge)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DashedFrame extends CustomPainter {
  _DashedFrame({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final Path path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)));
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 9) {
        canvas.drawPath(metric.extractPath(d, math.min(d + 5, metric.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedFrame old) => old.color != color;
}

/// A rounded progress track filled in the website's green.
class GreenProgress extends StatelessWidget {
  const GreenProgress({super.key, required this.percent, this.height = 9});

  final int percent;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(100),
      child: Container(
        height: height,
        color: NovaColors.accentMist,
        alignment: AlignmentDirectional.centerStart,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: percent.clamp(0, 100) / 100),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (BuildContext context, double value, _) => FractionallySizedBox(
            widthFactor: value,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFF1F9A58), Color(0xFF4FD1A5)]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A ring with the percentage inside (`.unitRing` / `.unitLessonRing`).
class PercentRing extends StatelessWidget {
  const PercentRing({
    super.key,
    required this.percent,
    this.size = 44,
    this.color,
    this.track,
    this.textColor,
    this.stroke,
  });

  final int percent;
  final double size;
  /// Defaults to the theme's blue.
  final Color? color;
  final Color? track;
  final Color? textColor;
  final double? stroke;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: percent.clamp(0, 100) / 100),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (BuildContext context, double value, _) => CustomPaint(
        size: Size.square(size),
        painter: _RingPainter(value: value, color: color ?? NovaColors.accent, track: track ?? NovaColors.borderOnLight, stroke: stroke ?? size * 0.1),
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: Text(
              '‎$percent%',
              style: TextStyle(
                fontFamily: NovaTypography.body,
                fontWeight: FontWeight.w800,
                fontSize: size * 0.24,
                color: textColor ?? NovaColors.textStrong,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.value, required this.color, required this.track, required this.stroke});

  final double value;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = (Offset.zero & size).deflate(stroke / 2);
    canvas.drawArc(rect, 0, 2 * math.pi, false, Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke);
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * value, false, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value || old.color != color;
}
