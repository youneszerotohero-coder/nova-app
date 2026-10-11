import 'package:flutter/material.dart';

import '../theme/nova_colors.dart';
import '../../features/shell/student_top_bar.dart';
import '../theme/nova_typography.dart';
import 'hero_style.dart';
import 'motion.dart';
import 'pressable_scale.dart';

/// The one header every top-level and pushed page opens on, as on the
/// website (D-125): the blue band, an optional back button and actions,
/// then the eyebrow line and the page title — nothing else, so every page
/// starts at the same height and reads as the same product.
///
/// [bottom] is the single exception (Explore's search field), which
/// sits inside the block under the title.
class NovaPageHeader extends StatelessWidget {
  const NovaPageHeader({
    super.key,
    required this.title,
    this.kicker,
    this.lead,
    this.showBack,
    this.actions,
    this.bottom,
    this.watermark,
  });

  /// The title; `*one word*` is circled by the yellow marker.
  final String title;

  /// The short yellow context line above the title (the website's eyebrow).
  final String? kicker;

  /// One line under the title (the website's lead).
  final String? lead;

  /// Null follows the route like [AppBar] does: no back button on a
  /// shell tab, one when the same screen is pushed (e.g. Cart opened
  /// from Profile).
  final bool? showBack;

  /// Shown in the top bar, in place of the logo.
  final List<Widget>? actions;

  /// Rendered full-width under the title, inside the band.
  final Widget? bottom;

  /// Faint glyph in the band's corner.
  final IconData? watermark;

  @override
  Widget build(BuildContext context) {
    final bool showBack = this.showBack ??
        (ModalRoute.of(context)?.impliesAppBarDismissal ?? false);

    // As in the website's Student space: the top bar, then (25 px under it,
    // `.studentMain`) the blue band as a rounded card (`.hxHead.hxBand`:
    // 26 / 20 px padding) with its eyebrow, title, lead and actions, 14 px
    // apart (`.hxHeadCopy`; the actions 6 px more).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StudentTopBar(
          showBack: showBack,
          trailing: actions == null || actions!.isEmpty
              ? null
              : Row(mainAxisSize: MainAxisSize.min, children: actions!),
        ),
        if (!showBack) const SizedBox(height: 25),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Entrance(
            child: HeroBand(
              padding: const EdgeInsets.fromLTRB(20, 26, 20, 26),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (watermark != null)
                    PositionedDirectional(
                      end: -20,
                      bottom: -34,
                      child: Icon(watermark, size: 104, color: Colors.white.withValues(alpha: 0.07)),
                    ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (kicker != null) ...[
                        HeroEyebrow(kicker!),
                        const SizedBox(height: 14),
                      ],
                      HeroTitle(title, size: 32, maxLines: 2),
                      if (lead != null) ...[
                        const SizedBox(height: 14),
                        // `.hxLead` on the band: 16 px, line-height 1.7,
                        // `--hx-on-blue-2`.
                        Text(
                          lead!,
                          style: const TextStyle(
                            fontFamily: NovaTypography.body,
                            fontFamilyFallback: NovaTypography.fallback,
                            fontSize: 16,
                            height: 1.7,
                            color: Color(0xD6FFFFFF),
                          ),
                        ),
                      ],
                      if (bottom != null) ...[
                        const SizedBox(height: 20),
                        bottom!,
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Round button over a header or a poster (back, close, notifications):
/// solid white with a dark icon and a soft shadow, so it stays visible on a
/// light poster as well as on the blue header (it was translucent white).
class FrostedIconButton extends StatelessWidget {
  const FrostedIconButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    this.onTap,
    this.size = 44,
    this.badge = 0,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onTap;
  final double size;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.9,
      semanticLabel: semanticLabel,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.96),
                shape: BoxShape.circle,
                border: Border.all(color: NovaColors.ink.withValues(alpha: 0.08)),
                boxShadow: const [
                  BoxShadow(color: Color(0x33091224), blurRadius: 12, offset: Offset(0, 3)),
                ],
              ),
              child: Icon(icon, size: size * 0.46, color: NovaColors.ink),
            ),
            if (badge > 0)
              Positioned(
                right: -1,
                top: -1,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF5D5D),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Text(
                    badge > 9 ? '9+' : '$badge',
                    style: const TextStyle(
                      fontFamily: 'Geist',
                      fontWeight: FontWeight.w800,
                      fontSize: 9,
                      height: 1.2,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Frosted pill action for the header block.
class FrostedPillButton extends StatelessWidget {
  const FrostedPillButton({
    super.key,
    required this.label,
    required this.icon,
    this.onTap,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final Color foreground =
        Colors.white.withValues(alpha: enabled ? 1 : 0.55);

    return PressableScale(
      onTap: enabled ? onTap : null,
      pressedScale: 0.95,
      semanticLabel: label,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: enabled ? 0.24 : 0.12),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: foreground),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Geist',
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
