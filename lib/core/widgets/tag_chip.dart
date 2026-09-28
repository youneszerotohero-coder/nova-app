import 'package:flutter/material.dart';

import '../theme/nova_colors.dart';
import '../theme/nova_dimens.dart';
import '../theme/nova_typography.dart';

/// Small rounded label chip. `translucent` renders the frosted pill
/// used on top of imagery; `tinted` renders solid fills for cards.
class TagChip extends StatelessWidget {
  const TagChip(
    this.label, {
    super.key,
    this.translucent = false,
    this.tint,
    this.textColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    this.fontSize = 12.5,
  });

  final String label;
  final bool translucent;
  final Color? tint;
  final Color? textColor;
  final EdgeInsetsGeometry padding;
  final double fontSize;

  const TagChip.translucent(this.label, {super.key})
      : translucent = true,
        tint = null,
        textColor = Colors.white,
        padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        fontSize = 12.5;

  @override
  Widget build(BuildContext context) {
    final Color background = translucent
        ? Colors.white.withValues(alpha: 0.22)
        : (tint ?? NovaColors.veilOnDark);

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(NovaDimens.radiusChip),
      ),
      child: Text(
        label,
        style: NovaTypography.onDark(
          TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            fontSize: fontSize,
            height: 1.2,
            letterSpacing: -0.1,
            color: textColor ?? Colors.white,
          ),
        ),
      ),
    );
  }
}
