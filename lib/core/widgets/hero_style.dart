import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/nova_colors.dart';
import '../theme/nova_dimens.dart';
import '../theme/nova_typography.dart';
import 'pressable_scale.dart';

/// The website's hero language (D-125, `hero.css` / `hx.tsx`) for the app:
/// the royal-blue band with formula doodles, the yellow eyebrow, the
/// hand-drawn circled word and the button with its yellow chip.

/// `.hxBand`: royal blue lit by two soft radial glows, each fading out at
/// 70 % of its reach as on the website.
class HeroBandDecoration {
  static BoxDecoration of({BorderRadiusGeometry? radius}) {
    final bool dark = NovaColors.current.isDark;
    // `--hx-blue`, or `--hx-blue-deep` in dark mode.
    final Color base = dark ? const Color(0xFF0D1F57) : NovaColors.accent;
    final Color glow = dark ? const Color(0x4D4F82F0) : const Color(0x736CA0FF);
    return BoxDecoration(
      color: base,
      borderRadius: radius,
      gradient: RadialGradient(
        center: const Alignment(-0.64, -0.3),
        radius: 1.1,
        colors: <Color>[Color.alphaBlend(glow, base), base],
        stops: const <double>[0, 0.7],
      ),
    );
  }
}

/// A blue band with the website's glows and doodles behind [child].
class HeroBand extends StatelessWidget {
  const HeroBand({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
    this.radius = const BorderRadius.all(Radius.circular(NovaDimens.radiusHero)),
    this.doodles = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadiusGeometry radius;
  final bool doodles;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: HeroBandDecoration.of(radius: radius),
      child: Stack(
        children: [
          // The deep glow of the bottom corner (second radial of `.hxBand`).
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.9, 1),
                  radius: 0.9,
                  colors: <Color>[
                    NovaColors.current.isDark ? const Color(0x99061032) : const Color(0x8C102C8C),
                    Colors.transparent,
                  ],
                  stops: const <double>[0, 0.7],
                ),
              ),
            ),
          ),
          if (doodles) const Positioned.fill(child: HeroDoodles()),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

/// `.hxDoodles`: three formulas, white at 16 %, tilted at the far edge.
class HeroDoodles extends StatelessWidget {
  const HeroDoodles({super.key});

  static const List<String> _items = <String>['sin²x + cos²x = 1', '∫₀¹ 2x dx = 1', '2H₂ + O₂ → 2H₂O'];

  @override
  Widget build(BuildContext context) {
    const TextStyle style = TextStyle(
      fontFamily: NovaTypography.display,
      fontWeight: FontWeight.w600,
      fontSize: 15,
      height: 1,
      color: Color(0x29FFFFFF),
    );
    // The website places them at the inline end: the left in Arabic.
    final bool rtl = Directionality.of(context) == TextDirection.rtl;
    Widget doodle(int i, double angle) => Transform.rotate(
          angle: angle * math.pi / 180,
          child: Text(_items[i], textDirection: TextDirection.ltr, style: style),
        );
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) => Stack(
          children: [
            Positioned(top: box.maxHeight * 0.12, left: rtl ? box.maxWidth * 0.06 : null, right: rtl ? null : box.maxWidth * 0.06, child: doodle(0, 5)),
            Positioned(bottom: box.maxHeight * 0.1, left: rtl ? box.maxWidth * 0.3 : null, right: rtl ? null : box.maxWidth * 0.3, child: doodle(1, -4)),
            Positioned(top: box.maxHeight * 0.46, left: rtl ? box.maxWidth * 0.02 : null, right: rtl ? null : box.maxWidth * 0.02, child: doodle(2, -7)),
          ],
        ),
      ),
    );
  }
}

/// `.hxEyebrow`: a short dash and a yellow (or blue) line of context.
class HeroEyebrow extends StatelessWidget {
  const HeroEyebrow(this.text, {super.key, this.onBlue = true});

  final String text;
  final bool onBlue;

  @override
  Widget build(BuildContext context) {
    final Color color = onBlue ? NovaColors.yellow : NovaColors.accent;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 22, height: 3, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: NovaTypography.display,
              fontFamilyFallback: NovaTypography.fallback,
              fontWeight: FontWeight.w800,
              fontSize: 15,
              height: 1.4,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

/// `HxTitle` / `HxMarked`: a title where `*one word*` is circled by a
/// hand-drawn marker that draws itself, as on the website.
class HeroTitle extends StatelessWidget {
  const HeroTitle(
    this.text, {
    super.key,
    this.onBlue = true,
    this.size = 30,
    this.maxLines = 3,
    this.textAlign = TextAlign.start,
  });

  final String text;
  final bool onBlue;
  final double size;
  final int maxLines;
  final TextAlign textAlign;

  /// The text without its marker stars.
  static String plain(String text) => text.replaceAll('*', '');

  @override
  Widget build(BuildContext context) {
    final TextStyle style = TextStyle(
      fontFamily: NovaTypography.display,
      fontFamilyFallback: NovaTypography.fallback,
      fontWeight: FontWeight.w800,
      fontSize: size,
      height: 1.25,
      color: onBlue ? Colors.white : NovaColors.textStrong,
    );
    final RegExpMatch? match = RegExp(r'\*([^*]+)\*').firstMatch(text);
    if (match == null) {
      return Text(text, maxLines: maxLines, overflow: TextOverflow.ellipsis, textAlign: textAlign, style: style);
    }
    return Text.rich(
      TextSpan(
        style: style,
        children: <InlineSpan>[
          TextSpan(text: text.substring(0, match.start)),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: CircledWord(match.group(1)!, style: style, onBlue: onBlue),
          ),
          TextSpan(text: text.substring(match.end)),
        ],
      ),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: textAlign,
    );
  }
}

/// One word inside the yellow hand-drawn ellipse (`.hxCircle`).
class CircledWord extends StatelessWidget {
  const CircledWord(this.word, {super.key, required this.style, this.onBlue = true});

  final String word;
  final TextStyle style;
  final bool onBlue;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: const Interval(0.25, 1, curve: Curves.easeOutCubic),
      builder: (BuildContext context, double t, Widget? child) => CustomPaint(
        foregroundPainter: _MarkerEllipse(progress: t, color: onBlue ? NovaColors.yellow : const Color(0xFFFFC21A)),
        child: child,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        child: Text(word, style: style),
      ),
    );
  }
}

class _MarkerEllipse extends CustomPainter {
  _MarkerEllipse({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      // `stroke-width: 5` with `vector-effect: non-scaling-stroke`.
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    // A slightly tilted loop that overshoots its start, like a pen stroke.
    final Rect box = Rect.fromLTWH(-2, size.height * 0.02, size.width + 4, size.height * 0.98);
    final Path path = Path();
    const int steps = 60;
    const double turn = 2.12 * math.pi;
    for (int i = 0; i <= steps; i++) {
      final double a = -math.pi * 0.62 + turn * i / steps;
      final double wobble = 1 + 0.035 * math.sin(i / steps * math.pi * 3);
      final Offset p = Offset(
        box.center.dx + box.width / 2 * wobble * math.cos(a),
        box.center.dy + box.height / 2 * wobble * math.sin(a) - 1.5 * math.cos(a),
      );
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    for (final metric in path.computeMetrics()) {
      canvas.drawPath(metric.extractPath(0, metric.length * progress), paint);
    }
  }

  @override
  bool shouldRepaint(_MarkerEllipse old) => old.progress != progress || old.color != color;
}

enum NovaButtonVariant { primary, yellow, ink, ghost, soft, onBlueGhost, danger }

/// `.hxBtn`: a 17 px rounded button (min height 52, `--sm` 44 / 14 px), the
/// label in Baloo 800, and an optional chip (yellow on blue, blue on yellow)
/// at the reading end. Every variant takes the website's tokens, so `ink`
/// flips to `#EEF2FF` / `#131B36` in dark mode as `.hxBtn--ink` does.
class NovaButton extends StatelessWidget {
  const NovaButton({
    super.key,
    required this.label,
    this.onTap,
    this.variant = NovaButtonVariant.primary,
    this.icon,
    this.chipIcon,
    this.trailingIcon,
    this.small = false,
    this.expand = false,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onTap;
  final NovaButtonVariant variant;

  /// Leading glyph (before the label).
  final IconData? icon;

  /// Chip glyph at the end; null for no chip.
  final IconData? chipIcon;

  /// A bare glyph after the label (the website's "Buy now ←" arrow).
  final IconData? trailingIcon;
  final bool small;
  final bool expand;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null && !loading;
    // (background, text, chip, chip text, border) per `.hxBtn--*`.
    final (Color bg, Color ink, Color chip, Color chipInk, Color line) = switch (variant) {
      NovaButtonVariant.primary => (NovaColors.accent, Colors.white, NovaColors.yellow, NovaColors.yellowInk, Colors.transparent),
      NovaButtonVariant.yellow => (NovaColors.yellow, NovaColors.yellowInk, NovaColors.accent, Colors.white, Colors.transparent),
      NovaButtonVariant.ink => (NovaColors.textStrong, NovaColors.paperCard, NovaColors.skyStrong, const Color(0xFF0B1A2A), Colors.transparent),
      NovaButtonVariant.ghost => (Colors.transparent, NovaColors.textStrong, NovaColors.accentMist, NovaColors.accent, NovaColors.lineStrong),
      NovaButtonVariant.soft => (NovaColors.accentMist, NovaColors.accent, NovaColors.accent, Colors.white, Colors.transparent),
      NovaButtonVariant.onBlueGhost => (const Color(0x1AFFFFFF), Colors.white, Colors.white, NovaColors.accent, const Color(0x57FFFFFF)),
      NovaButtonVariant.danger => (NovaColors.dangerBg, NovaColors.heartRed, NovaColors.yellow, NovaColors.yellowInk, Colors.transparent),
    };
    final double chipSize = small ? 34 : 40;
    final double gap = small ? 8 : 12;
    final Widget content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: ink))
        else if (icon != null)
          Icon(icon, size: 19, color: ink),
        if (loading || icon != null) SizedBox(width: gap),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: NovaTypography.display,
              fontFamilyFallback: NovaTypography.fallback,
              fontWeight: FontWeight.w800,
              fontSize: small ? 15 : 16,
              height: 1.2,
              color: ink,
            ),
          ),
        ),
        if (trailingIcon != null && !loading) ...[
          SizedBox(width: small ? 8 : 10),
          Icon(trailingIcon, size: 18, color: ink),
        ],
        if (chipIcon != null) ...[
          SizedBox(width: gap),
          Container(
            width: chipSize,
            height: chipSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: chip, borderRadius: BorderRadius.circular(small ? 10 : 12)),
            child: Icon(chipIcon, size: 18, color: chipInk),
          ),
        ],
      ],
    );
    return Opacity(
      opacity: enabled || loading ? 1 : 0.5,
      child: PressableScale(
        onTap: enabled ? onTap : null,
        pressedScale: 0.97,
        semanticLabel: label,
        child: Container(
          constraints: BoxConstraints(minHeight: small ? 44 : 52),
          padding: EdgeInsetsDirectional.only(
            start: small ? 16 : 20,
            end: chipIcon != null ? (small ? 4 : 6) : (small ? 16 : 20),
            top: small ? 4 : 6,
            bottom: small ? 4 : 6,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(small ? 14 : NovaDimens.radiusControl),
            border: Border.all(color: line, width: 1.5),
          ),
          child: content,
        ),
      ),
    );
  }
}

/// `HxEmpty`: the icon tile inside a dashed orbit with its yellow bead,
/// one short line, one action; boxed in a dashed `--hx-line-strong` frame.
class HeroEmpty extends StatelessWidget {
  const HeroEmpty({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.boxed = true,
    this.tone = NovaHue.sky,
    this.orbit = true,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final bool boxed;

  /// The tile's tone: blue, or `.hxState--error` ([NovaHue.rose]) and
  /// `--success` ([NovaHue.mint]).
  final NovaHue tone;

  /// The dashed orbit around the tile; without it, the catalogue's
  /// `.nvEmpty` (an empty [title] shows the text alone).
  final bool orbit;

  @override
  Widget build(BuildContext context) {
    final Widget body = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: orbit ? 108 : 64,
          height: orbit ? 108 : 64,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (orbit) const _Orbit(),
              Transform.rotate(
                angle: -6 * math.pi / 180,
                child: Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tone.surfaceStrong,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: NovaDimens.shadowSticker,
                  ),
                  child: Icon(icon, size: 30, color: tone.solid),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: orbit ? 18 : 14),
        if (title.isNotEmpty) HeroTitle(title, onBlue: false, size: 20, textAlign: TextAlign.center),
        if (message != null) ...[
          SizedBox(height: title.isEmpty ? 0 : (orbit ? 12 : 10)),
          Text(
            message!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: NovaTypography.body,
              fontFamilyFallback: NovaTypography.fallback,
              fontSize: 16,
              height: 1.6,
              color: NovaColors.textBody,
            ),
          ),
        ],
        if (action != null) ...[const SizedBox(height: 18), action!],
      ],
    );
    if (!boxed) return Padding(padding: const EdgeInsets.fromLTRB(20, 28, 20, 28), child: body);
    return CustomPaint(
      painter: _DashedFrame(color: NovaColors.lineStrong, radius: NovaDimens.radiusTile),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
        decoration: BoxDecoration(
          color: NovaColors.paperCard,
          borderRadius: BorderRadius.circular(NovaDimens.radiusTile),
        ),
        child: body,
      ),
    );
  }
}

/// A 1.5 px dashed rounded frame (`border: 1.5px dashed`), drawn over the box.
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
    final Path frame = Path()
      ..addRRect(RRect.fromRectAndRadius((Offset.zero & size).deflate(0.75), Radius.circular(radius - 0.75)));
    for (final metric in frame.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 9) {
        canvas.drawPath(metric.extractPath(d, math.min(d + 5, metric.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedFrame old) => old.color != color || old.radius != radius;
}

class _Orbit extends StatefulWidget {
  const _Orbit();

  @override
  State<_Orbit> createState() => _OrbitState();
}

class _OrbitState extends State<_Orbit> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(seconds: 40));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // `prefers-reduced-motion` stops the website's orbit too.
    if (MediaQuery.disableAnimationsOf(context)) {
      _spin.stop();
    } else if (!_spin.isAnimating) {
      _spin.repeat();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _spin,
      child: CustomPaint(size: const Size.square(108), painter: _OrbitPainter(line: NovaColors.blueLine)),
    );
  }
}

/// `.hxOrbit`: a 2 px dashed `--hx-blue-line` circle with the 12 px yellow
/// bead and its `rgba(255,213,74,.25)` ring, at 12 % / 12 % of the box.
class _OrbitPainter extends CustomPainter {
  _OrbitPainter({required this.line});

  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double r = size.width / 2 - 1;
    final Paint dash = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    const int dashes = 40;
    for (int i = 0; i < dashes; i++) {
      final double a = i * 2 * math.pi / dashes;
      canvas.drawArc(Rect.fromCircle(center: center, radius: r), a, math.pi / dashes, false, dash);
    }
    final Offset bead = Offset(size.width * 0.12, size.height * 0.12);
    canvas.drawCircle(bead, 11, Paint()..color = const Color(0x40FFD54A));
    canvas.drawCircle(bead, 6, Paint()..color = NovaColors.yellow);
  }

  @override
  bool shouldRepaint(_OrbitPainter old) => old.line != line;
}

/// A small rounded chip (`.unitChip` / `.hxSticker--plain`).
class HeroChip extends StatelessWidget {
  const HeroChip({super.key, required this.label, this.icon, this.color, this.background});

  final String label;
  final IconData? icon;
  final Color? color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final Color ink = color ?? NovaColors.textStrong.withValues(alpha: 0.78);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: background ?? NovaColors.paperRaised,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: ink), const SizedBox(width: 5)],
          Text(
            label,
            style: TextStyle(
              fontFamily: NovaTypography.body,
              fontFamilyFallback: NovaTypography.fallback,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
              height: 1.35,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }
}
