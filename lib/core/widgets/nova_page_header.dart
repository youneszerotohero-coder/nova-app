import 'package:flutter/material.dart';

import '../theme/nova_colors.dart';
import '../theme/nova_dimens.dart';
import '../theme/nova_typography.dart';
import 'nova_decor.dart';
import 'pressable_scale.dart';

/// The one header every top-level and pushed page opens on: the brand
/// gradient, sticker decor, an optional back button and actions, then
/// the kicker line and the page title — nothing else, so every page
/// starts at the same height and reads as the same product.
///
/// [bottom] is the single exception (Explore's search field), which
/// sits inside the block under the title.
class NovaPageHeader extends StatelessWidget {
  const NovaPageHeader({
    super.key,
    required this.title,
    this.kicker,
    this.showBack,
    this.actions,
    this.bottom,
    this.watermark,
  });

  final String title;

  /// The short context line above the title ("MY LEARNING · 7
  /// LESSONS"), always rendered in capitals beside a sparkle.
  final String? kicker;

  /// Null follows the route like [AppBar] does: no back button on a
  /// shell tab, one when the same screen is pushed (e.g. Cart opened
  /// from Profile).
  final bool? showBack;
  final List<Widget>? actions;

  /// Rendered full-width under the title, inside the block.
  final Widget? bottom;

  /// Oversized glyph bleeding off the right edge.
  final IconData? watermark;

  /// The brand gradient every header shares.
  static const LinearGradient gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF4D9EFF), NovaColors.accent, Color(0xFF1B5FD0)],
  );

  @override
  Widget build(BuildContext context) {
    final bool showBack = this.showBack ??
        (ModalRoute.of(context)?.impliesAppBarDismissal ?? false);

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.paddingOf(context).top + 14,
        20,
        bottom == null ? 22 : 18,
      ),
      decoration: const BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(NovaDimens.radiusCardLarge),
        ),
        boxShadow: [
          BoxShadow(
            offset: Offset(0, 16),
            blurRadius: 34,
            spreadRadius: -16,
            color: Color(0x662B87F7),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (watermark != null)
            Positioned(
              right: -26,
              bottom: -34,
              child: Icon(
                watermark,
                size: 124,
                color: Colors.white.withValues(alpha: 0.13),
              ),
            ),
          const Positioned.fill(
            child: NovaDecor(color: Colors.white, opacity: 0.22, seed: 3),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Tab pages have no back button or actions: no empty row
              // above the title (owner: less space at the top).
              if (showBack || (actions?.isNotEmpty ?? false)) ...[
                SizedBox(
                  height: 44,
                  child: Row(
                    children: [
                      if (showBack)
                        FrostedIconButton(
                          icon: Icons.arrow_back_rounded,
                          semanticLabel: 'Back',
                          onTap: () => Navigator.of(context).maybePop(),
                        ),
                      const Spacer(),
                      ...?actions,
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (kicker != null) ...[
                Row(
                  children: [
                    const Sparkle(size: 12),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        kicker!.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          fontSize: 10.5,
                          letterSpacing: 2.4,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NovaTypography.textTheme.displayMedium!.copyWith(
                  color: Colors.white,
                  height: 1.04,
                ),
              ),
              if (bottom != null) ...[
                const SizedBox(height: 16),
                bottom!,
              ],
            ],
          ),
        ],
      ),
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
                border: Border.all(color: NovaColors.ink950.withValues(alpha: 0.08)),
                boxShadow: const [
                  BoxShadow(color: Color(0x33091224), blurRadius: 12, offset: Offset(0, 3)),
                ],
              ),
              child: Icon(icon, size: size * 0.46, color: NovaColors.ink950),
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
                    color: NovaColors.badgeOrange,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Text(
                    badge > 9 ? '9+' : '$badge',
                    style: const TextStyle(
                      fontFamily: 'Inter',
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
                fontFamily: 'Inter',
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
