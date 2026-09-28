import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../theme/nova_colors.dart';

/// The celebration played when an order lands: a disc springs in,
/// two rings pulse outward, a tick draws itself and confetti arcs away
/// under gravity.
///
/// Everything is driven by one controller and painted in a single
/// custom painter inside a repaint boundary, so the whole thing costs
/// one layer and stops animating the moment it finishes.
class SuccessBurst extends StatefulWidget {
  const SuccessBurst({
    super.key,
    this.size = 128,
    this.color = NovaColors.onlineGreen,
    this.confetti = true,
    this.onComplete,
  });

  final double size;
  final Color color;

  /// Disable for quieter confirmations (a queued receipt, say).
  final bool confetti;
  final VoidCallback? onComplete;

  @override
  State<SuccessBurst> createState() => _SuccessBurstState();
}

class _SuccessBurstState extends State<SuccessBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void initState() {
    super.initState();
    _controller.forward().then((_) {
      if (mounted) widget.onComplete?.call();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The confetti flies well outside the disc, so the canvas is
    // deliberately larger than the badge it draws.
    final double canvas = widget.size * 2.1;

    return RepaintBoundary(
      child: SizedBox(
        width: canvas,
        height: canvas,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (BuildContext context, _) => CustomPaint(
            painter: _BurstPainter(
              t: _controller.value,
              color: widget.color,
              badgeSize: widget.size,
              confetti: widget.confetti,
            ),
          ),
        ),
      ),
    );
  }
}

/// One confetti piece: launch angle, distance, spin and hue.
class _Fleck {
  const _Fleck(this.angle, this.distance, this.spin, this.color, this.square);

  final double angle;
  final double distance;
  final double spin;
  final Color color;
  final bool square;
}

final List<_Fleck> _flecks = List<_Fleck>.generate(16, (int i) {
  final math.Random random = math.Random(i * 7 + 3);
  const List<Color> palette = [
    NovaColors.accent,
    NovaColors.gold,
    NovaColors.badgeOrange,
    Color(0xFF6C5CE7),
    NovaColors.onlineGreen,
  ];
  return _Fleck(
    (i / 16) * math.pi * 2 + random.nextDouble() * 0.3,
    0.62 + random.nextDouble() * 0.38,
    (random.nextDouble() - 0.5) * 8,
    palette[i % palette.length],
    i.isEven,
  );
});

class _BurstPainter extends CustomPainter {
  _BurstPainter({
    required this.t,
    required this.color,
    required this.badgeSize,
    required this.confetti,
  });

  final double t;
  final Color color;
  final double badgeSize;
  final bool confetti;

  double _phase(double start, double end) =>
      ((t - start) / (end - start)).clamp(0, 1);

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = badgeSize / 2;

    // Rings: two expanding halos, staggered, fading as they grow.
    for (int i = 0; i < 2; i++) {
      final double p = Curves.easeOutCubic.transform(
        _phase(0.08 + i * 0.12, 0.72 + i * 0.12),
      );
      if (p <= 0 || p >= 1) continue;
      canvas.drawCircle(
        center,
        radius * (1 + p * 0.95),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * (1 - p)
          ..color = color.withValues(alpha: 0.4 * (1 - p)),
      );
    }

    if (confetti) _paintConfetti(canvas, center, radius);

    // Disc: springs in, then holds.
    final double pop = Curves.elasticOut.transform(_phase(0, 0.55));
    if (pop <= 0) return;
    final double discRadius = radius * pop.clamp(0, 1.12);
    canvas.drawCircle(
      center,
      discRadius,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(color, Colors.white, 0.28)!,
            color,
          ],
        ).createShader(
          Rect.fromCircle(center: center, radius: discRadius),
        ),
    );

    _paintTick(canvas, center, radius);
  }

  void _paintConfetti(Canvas canvas, Offset center, double radius) {
    final double p = Curves.easeOutCubic.transform(_phase(0.22, 1));
    if (p <= 0) return;
    final double fade = (1 - _phase(0.72, 1)).clamp(0, 1);

    for (final _Fleck fleck in _flecks) {
      final double travel = radius * 2.1 * fleck.distance * p;
      // A touch of gravity so the arc reads as thrown, not beamed.
      final Offset position = center +
          Offset(
            math.cos(fleck.angle) * travel,
            math.sin(fleck.angle) * travel + 26 * p * p,
          );

      canvas.save();
      canvas.translate(position.dx, position.dy);
      canvas.rotate(fleck.spin * p);
      final Paint paint = Paint()
        ..color = fleck.color.withValues(alpha: fade);
      if (fleck.square) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: 7, height: 7),
            const Radius.circular(2),
          ),
          paint,
        );
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: 4.5, height: 10),
            const Radius.circular(3),
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  void _paintTick(Canvas canvas, Offset center, double radius) {
    final double p = Curves.easeOutCubic.transform(_phase(0.3, 0.72));
    if (p <= 0) return;

    final Path tick = Path()
      ..moveTo(center.dx - radius * 0.34, center.dy + radius * 0.02)
      ..lineTo(center.dx - radius * 0.08, center.dy + radius * 0.28)
      ..lineTo(center.dx + radius * 0.36, center.dy - radius * 0.26);

    // Draw only the leading portion of the stroke, so it writes itself.
    final Path drawn = Path();
    for (final PathMetric metric in tick.computeMetrics()) {
      drawn.addPath(metric.extractPath(0, metric.length * p), Offset.zero);
    }

    canvas.drawPath(
      drawn,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.16
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t || old.color != color;
}
