import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The sticker vocabulary behind the playful direction: sparkles,
/// rings, dotted arcs and squiggles painted softly into a card so
/// large colour blocks never read as flat rectangles.
enum NovaDoodle { sparkle, ring, dottedArc, squiggle, dotGrid, blob }

/// Paints a deterministic arrangement of [NovaDoodle]s across its box.
///
/// It is decoration only — never wrap content that must stay legible
/// without it, and keep [opacity] low enough that text on top wins.
class NovaDecor extends StatelessWidget {
  const NovaDecor({
    super.key,
    this.color = Colors.white,
    this.opacity = 0.2,
    this.seed = 0,
    this.child,
  });

  final Color color;
  final double opacity;

  /// Same seed ⇒ same arrangement, so a card keeps its personality
  /// across rebuilds and between screens.
  final int seed;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DoodlePainter(color: color, opacity: opacity, seed: seed),
      child: child ?? const SizedBox.expand(),
    );
  }
}

/// A single four-point sparkle, for inline accents beside headlines.
class Sparkle extends StatelessWidget {
  const Sparkle({super.key, this.size = 14, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _SparklePainter(color ?? Colors.white),
      ),
    );
  }
}

class _SparklePainter extends CustomPainter {
  _SparklePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      _sparklePath(Offset(size.width / 2, size.height / 2), size.width / 2),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_SparklePainter old) => old.color != color;
}

Path _sparklePath(Offset c, double r) {
  final double w = r * 0.2;
  return Path()
    ..moveTo(c.dx, c.dy - r)
    ..quadraticBezierTo(c.dx + w, c.dy - w, c.dx + r, c.dy)
    ..quadraticBezierTo(c.dx + w, c.dy + w, c.dx, c.dy + r)
    ..quadraticBezierTo(c.dx - w, c.dy + w, c.dx - r, c.dy)
    ..quadraticBezierTo(c.dx - w, c.dy - w, c.dx, c.dy - r)
    ..close();
}

/// Where each doodle sits, in fractions of the box.
class _Anchor {
  const _Anchor(this.x, this.y, this.scale);

  final double x;
  final double y;

  /// Radius as a fraction of the box's shortest side.
  final double scale;
}

const List<_Anchor> _anchors = [
  _Anchor(0.87, 0.18, 0.13),
  _Anchor(0.14, 0.74, 0.17),
  _Anchor(0.70, 0.88, 0.11),
  _Anchor(0.33, 0.12, 0.10),
  _Anchor(0.96, 0.62, 0.08),
  _Anchor(0.52, 0.30, 0.07),
];

class _DoodlePainter extends CustomPainter {
  _DoodlePainter({
    required this.color,
    required this.opacity,
    required this.seed,
  });

  final Color color;
  final double opacity;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final double unit = size.shortestSide;
    const List<NovaDoodle> wheel = NovaDoodle.values;

    for (int i = 0; i < _anchors.length; i++) {
      final _Anchor anchor = _anchors[i];
      final NovaDoodle doodle = wheel[(seed + i * 2 + 1) % wheel.length];
      final Offset center = Offset(size.width * anchor.x, size.height * anchor.y);
      final double radius = unit * anchor.scale;

      // Shapes further down the list fade out, keeping the top-of-card
      // area — where headlines live — the quietest.
      final double alpha = opacity * (1 - i * 0.08);
      _draw(canvas, doodle, center, radius, color.withValues(alpha: alpha), i);
    }
  }

  void _draw(
    Canvas canvas,
    NovaDoodle doodle,
    Offset center,
    double radius,
    Color paintColor,
    int index,
  ) {
    final Paint fill = Paint()..color = paintColor;
    final Paint stroke = Paint()
      ..color = paintColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.5, radius * 0.11);

    switch (doodle) {
      case NovaDoodle.sparkle:
        canvas.drawPath(_sparklePath(center, radius), fill);
      case NovaDoodle.ring:
        canvas.drawCircle(center, radius, stroke);
      case NovaDoodle.dottedArc:
        for (int i = 0; i < 7; i++) {
          final double t = -0.4 + i * 0.32;
          canvas.drawCircle(
            center + Offset(math.cos(t) * radius, math.sin(t) * radius),
            math.max(1.3, radius * 0.11),
            fill,
          );
        }
      case NovaDoodle.squiggle:
        final Path path = Path()..moveTo(center.dx - radius, center.dy);
        for (int i = 0; i < 3; i++) {
          final double x0 = center.dx - radius + (radius * 2 / 3) * i;
          final double x1 = x0 + (radius * 2 / 3);
          path.quadraticBezierTo(
            (x0 + x1) / 2,
            center.dy + (i.isEven ? -radius * 0.55 : radius * 0.55),
            x1,
            center.dy,
          );
        }
        canvas.drawPath(path, stroke);
      case NovaDoodle.dotGrid:
        for (int row = 0; row < 3; row++) {
          for (int col = 0; col < 3; col++) {
            canvas.drawCircle(
              center + Offset((col - 1) * radius * 0.6, (row - 1) * radius * 0.6),
              math.max(1.1, radius * 0.09),
              fill,
            );
          }
        }
      case NovaDoodle.blob:
        canvas.drawCircle(
          center,
          radius * 1.5,
          Paint()
            ..color = paintColor.withValues(alpha: paintColor.a * 0.6)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.9),
        );
    }
    // Index is part of the arrangement, not the drawing — referenced
    // so the choreography stays explicit at the call site.
    assert(index >= 0);
  }

  @override
  bool shouldRepaint(_DoodlePainter old) =>
      old.color != color || old.opacity != opacity || old.seed != seed;
}
