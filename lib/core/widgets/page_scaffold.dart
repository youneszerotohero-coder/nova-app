import 'package:flutter/material.dart';

import '../theme/nova_colors.dart';
import '../theme/nova_dimens.dart';
import '../theme/nova_typography.dart';
import 'hero_style.dart';
import 'nova_page_header.dart';
import 'pressable_scale.dart';

export 'nova_page_header.dart' show FrostedIconButton, FrostedPillButton;

/// Common pushed-page scaffold: the shared [NovaPageHeader] block with
/// a back button, the page body, and an optional bottom action bar.
class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.title,
    required this.body,
    this.kicker,
    this.actions,
    this.bottomBar,
    this.watermark,
  });

  final String title;
  final Widget body;

  /// Context line above the title (see [NovaPageHeader.kicker]).
  final String? kicker;
  final List<Widget>? actions;

  /// Optional bottom action bar (purchase CTA, checkout submit...).
  final Widget? bottomBar;

  /// Oversized glyph bleeding off the header's right edge.
  final IconData? watermark;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NovaPageHeader(
            title: title,
            kicker: kicker,
            showBack: true,
            actions: actions,
            watermark: watermark,
          ),
          Expanded(child: body),
          ?bottomBar,
        ],
      ),
    );
  }
}

/// Section card container used across screens.
class NovaCard extends StatelessWidget {
  const NovaCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      pressedScale: onTap == null ? 1 : 0.98,
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: color ?? NovaColors.paperCard,
          borderRadius: BorderRadius.circular(NovaDimens.radiusTile),
          border: Border.all(color: NovaColors.borderOnLight),
          boxShadow: NovaDimens.shadowSoft,
        ),
        child: child,
      ),
    );
  }
}

/// The website's `.dashboardCard` with its heading (`CardHeading`): an
/// optional blue kicker (14 px Baloo 800) over the ink title; no icon tile.
class NovaSectionCard extends StatelessWidget {
  const NovaSectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.hue = NovaHue.sky,
    this.subtitle,
    this.trailing,
    this.kicker,
  });

  /// Kept for callers; the website's card heading has no icon.
  final IconData icon;
  final String title;
  final Widget child;

  /// Kept for callers; the card is neutral whatever the hue.
  final NovaHue hue;
  final String? subtitle;
  final Widget? trailing;

  /// The blue line above the title (`.dashboardCardHeading span`).
  final String? kicker;

  @override
  Widget build(BuildContext context) {
    return NovaCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (kicker != null) ...[
                      Text(
                        kicker!,
                        style: TextStyle(
                          fontFamily: NovaTypography.display,
                          fontFamilyFallback: NovaTypography.fallback,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          height: 1.3,
                          color: NovaColors.accent,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: NovaTypography.display,
                        fontFamilyFallback: NovaTypography.fallback,
                        fontWeight: FontWeight.w800,
                        fontSize: 19,
                        height: 1.3,
                        color: NovaColors.textStrong,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: NovaTypography.textTheme.bodySmall!.copyWith(color: NovaColors.textBody),
                      ),
                    ],
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

/// Friendly empty state (cart, results, notifications...): the website's
/// `HxEmpty` with a blue `.hxBtn` as its action.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.hue = NovaHue.sky,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;

  /// The tile's tone: [NovaHue.rose] for an error, blue otherwise.
  final NovaHue hue;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: HeroEmpty(
          icon: icon,
          title: title,
          message: message,
          tone: hue,
          action: actionLabel == null
              ? null
              : NovaButton(label: actionLabel!, chipIcon: Icons.arrow_forward_rounded, onTap: onAction),
        ),
      ),
    );
  }
}
