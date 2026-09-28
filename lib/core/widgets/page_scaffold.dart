import 'package:flutter/material.dart';

import '../theme/nova_colors.dart';
import '../theme/nova_dimens.dart';
import '../theme/nova_typography.dart';
import 'hue_card.dart';
import 'nova_decor.dart';
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

/// A card that leads with a hue-tinted icon tile and a title row.
class NovaSectionCard extends StatelessWidget {
  const NovaSectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.hue = NovaHue.sky,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final NovaHue hue;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return NovaCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconTile(icon: icon, hue: hue, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: NovaTypography.textTheme.titleMedium),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: NovaTypography.muted(
                          NovaTypography.textTheme.bodySmall!,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

/// Friendly empty state (cart, results, notifications...).
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
  final NovaHue hue;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 96,
              height: 96,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  NovaDecor(color: hue.solid, opacity: 0.35, seed: 2),
                  Container(
                    width: 72,
                    height: 72,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: hue.surfaceStrong,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 30, color: hue.onSurface),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text(title, style: NovaTypography.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: NovaTypography.muted(NovaTypography.textTheme.bodyMedium!),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 18),
              PressableScale(
                onTap: onAction,
                semanticLabel: actionLabel,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: NovaColors.ink950,
                    borderRadius: BorderRadius.circular(100),
                    boxShadow: NovaDimens.shadowSoft,
                  ),
                  child: Text(
                    actionLabel!,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
