import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/i18n/nova_strings.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/widgets/hero_style.dart';

/// D-133 launch animation, in the website's hero language: the blue band
/// with its formulas, the NOVA logo popping in, the yellow marker circling it,
/// then the hero's line "The BAC? We'll get it together." and three dots
/// while the session loads. It continues the native launch screen (blue).
class NovaSplash extends StatefulWidget {
  const NovaSplash({super.key});

  /// How long the animation needs to be seen once.
  static const Duration minimum = Duration(milliseconds: 1900);

  @override
  State<NovaSplash> createState() => _NovaSplashState();
}

class _NovaSplashState extends State<NovaSplash> with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1700))..forward();
  late final AnimationController _dots = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _intro.dispose();
    _dots.dispose();
    super.dispose();
  }

  Animation<double> _phase(double start, double end, [Curve curve = Curves.easeOutCubic]) =>
      CurvedAnimation(parent: _intro, curve: Interval(start, end, curve: curve));

  @override
  Widget build(BuildContext context) {
    final Animation<double> logo = _phase(0, 0.45, Curves.elasticOut);
    final Animation<double> ring = _phase(0.3, 0.75);
    final Animation<double> words = _phase(0.55, 0.9);
    return Scaffold(
      backgroundColor: NovaColors.accent,
      body: HeroBand(
        radius: BorderRadius.zero,
        padding: EdgeInsets.zero,
        child: SizedBox.expand(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: _intro,
                builder: (BuildContext context, Widget? child) => SizedBox(
                  width: 200,
                  height: 200,
                  child: CustomPaint(
                    foregroundPainter: _LogoRing(progress: ring.value),
                    child: Center(
                      child: Transform.scale(
                        scale: 0.4 + 0.6 * logo.value,
                        child: Opacity(opacity: logo.value.clamp(0, 1), child: child),
                      ),
                    ),
                  ),
                ),
                child: Container(
                  width: 132,
                  height: 132,
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(offset: Offset(0, 22), blurRadius: 40, spreadRadius: -16, color: Color(0x99071649))],
                  ),
                  child: Image.asset('assets/images/brand/nova_logo.png', semanticLabel: 'NOVA'),
                ),
              ),
              const SizedBox(height: 26),
              FadeTransition(
                opacity: words,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, 0.35), end: Offset.zero).animate(words),
                  child: Text(
                    context.tr('splash.tagline'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: NovaTypography.display,
                      fontFamilyFallback: NovaTypography.fallback,
                      fontWeight: FontWeight.w800,
                      fontSize: 24,
                      height: 1.3,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 34),
              FadeTransition(
                opacity: words,
                child: AnimatedBuilder(
                  animation: _dots,
                  builder: (BuildContext context, _) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (int i = 0; i < 3; i++)
                        Transform.translate(
                          offset: Offset(0, -7 * math.max(0, math.sin((_dots.value - i * 0.18) * 2 * math.pi))),
                          child: Container(
                            width: 10,
                            height: 10,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: const BoxDecoration(color: NovaColors.yellow, shape: BoxShape.circle),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The hand-drawn yellow loop around the logo (the hero's circled word).
class _LogoRing extends CustomPainter {
  _LogoRing({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final Paint paint = Paint()
      ..color = NovaColors.yellow
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    final Offset c = size.center(Offset.zero);
    final Path path = Path();
    const int steps = 80;
    for (int i = 0; i <= steps; i++) {
      final double t = i / steps;
      final double a = -math.pi * 0.7 + 2.15 * math.pi * t;
      final double r = size.width * (0.43 + 0.025 * math.sin(t * math.pi * 3));
      final Offset p = c + Offset(r * math.cos(a), r * 0.94 * math.sin(a));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    for (final metric in path.computeMetrics()) {
      canvas.drawPath(metric.extractPath(0, metric.length * progress), paint);
    }
  }

  @override
  bool shouldRepaint(_LogoRing old) => old.progress != progress;
}
