import 'package:flutter/material.dart';

import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_dimens.dart';
import '../../core/theme/nova_typography.dart';

/// The website's Student account cards (`dashboard.css`), shared by
/// Settings, Wallet, Orders and Notifications.

/// `.dashboardCard`: surface, 1 px line border, radius 24, `--hx-shadow`,
/// with the `.dashboardCardHeading` (blue kicker over the ink Baloo title).
class DashboardCard extends StatelessWidget {
  const DashboardCard({
    super.key,
    required this.child,
    this.kicker,
    this.title,
    this.padding = const EdgeInsets.fromLTRB(20, 22, 20, 22),
  });

  final String? kicker;
  final String? title;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: dashboardCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (kicker != null || title != null) ...[
            if (kicker != null) Text(kicker!, style: dashboardKickerStyle),
            if (kicker != null && title != null) const SizedBox(height: 4),
            if (title != null) Text(title!, style: dashboardTitleStyle),
            const SizedBox(height: 17),
          ],
          child,
        ],
      ),
    );
  }
}

BoxDecoration dashboardCardDecoration({Color? border}) => BoxDecoration(
      color: NovaColors.paperCard,
      borderRadius: BorderRadius.circular(NovaDimens.radiusTile),
      border: Border.all(color: border ?? NovaColors.borderOnLight),
      boxShadow: NovaDimens.shadowCard,
    );

/// `.dashboardCardHeading > div > span`: blue, 14 px Baloo 800.
TextStyle get dashboardKickerStyle => TextStyle(
      fontFamily: NovaTypography.display,
      fontFamilyFallback: NovaTypography.fallback,
      fontWeight: FontWeight.w800,
      fontSize: 14,
      height: 1.3,
      color: NovaColors.accent,
    );

/// `.dashboardCardHeading h2`: ink Baloo 800.
TextStyle get dashboardTitleStyle => TextStyle(
      fontFamily: NovaTypography.display,
      fontFamilyFallback: NovaTypography.fallback,
      fontWeight: FontWeight.w800,
      fontSize: 21,
      height: 1.3,
      color: NovaColors.textStrong,
    );

/// Baloo 800 at [size] in [color] (ink by default): the website's
/// `font-family: var(--hx-font); font-weight: 800` labels.
TextStyle heroLabel(double size, {Color? color, double height = 1.3}) => TextStyle(
      fontFamily: NovaTypography.display,
      fontFamilyFallback: NovaTypography.fallback,
      fontWeight: FontWeight.w800,
      fontSize: size,
      height: height,
      color: color ?? NovaColors.textStrong,
    );

/// Body text at [size] in [color] (`--hx-ink-2` by default).
TextStyle heroText(double size, {Color? color, FontWeight weight = FontWeight.w500, double height = 1.5}) => TextStyle(
      fontFamily: NovaTypography.body,
      fontFamilyFallback: NovaTypography.fallback,
      fontWeight: weight,
      fontSize: size,
      height: height,
      color: color ?? NovaColors.textBody,
    );

/// `.infoField`: line border, radius 14; label mute 13.5, value ink 16.
/// [ltr] keeps a phone number or a code reading left to right in Arabic.
class InfoField extends StatelessWidget {
  const InfoField({super.key, required this.label, required this.value, this.ltr = false});

  final String label;
  final String value;
  final bool ltr;

  @override
  Widget build(BuildContext context) {
    final String shown = value.trim().isEmpty ? '—' : value;
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: NovaColors.paperCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NovaColors.borderOnLight),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: heroText(13.5, color: NovaColors.textMuted, height: 1.35)),
          const SizedBox(height: 5),
          Text(
            shown,
            textDirection: ltr ? TextDirection.ltr : null,
            style: heroLabel(16, height: 1.35),
          ),
        ],
      ),
    );
  }
}

/// A full-width row button in the card style: the website's sign-out
/// button (`.securityCard > button`: 48 high, radius 17, surface, line
/// border, the label at the start and a chevron at the end).
class CardRowButton extends StatelessWidget {
  const CardRowButton({super.key, required this.label, required this.onTap, this.color});

  final String label;
  final VoidCallback? onTap;

  /// Label and chevron colour; ink by default.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final Color ink = color ?? NovaColors.textStrong;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: NovaColors.paperCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NovaDimens.radiusControl),
          side: BorderSide(color: NovaColors.borderOnLight),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: heroLabel(16, color: ink))),
                Icon(Icons.chevron_right_rounded, size: 20, color: ink),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
