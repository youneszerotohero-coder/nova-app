import 'package:flutter/material.dart';

import '../theme/nova_colors.dart';
import '../theme/nova_dimens.dart';
import 'pressable_scale.dart';

/// The circular, hairline-bordered icon button used across the
/// reference screens (menu, back, bell, camera, ...).
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = NovaDimens.circleButtonSize,
    this.iconSize = 21,
    this.dark = false,
    this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;

  /// Renders the charcoal variant used on light screens' dark strips
  /// and inside dark screens.
  final bool dark;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final Color fill = dark ? NovaColors.ink900 : NovaColors.paperCard;
    final Color border =
        dark ? NovaColors.borderOnDark : NovaColors.borderOnLight;
    final Color iconColor =
        dark ? NovaColors.textOnDark : NovaColors.textStrong;

    return PressableScale(
      onTap: onTap,
      semanticLabel: semanticLabel,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: fill,
          shape: BoxShape.circle,
          border: Border.all(color: border),
          boxShadow: dark
              ? null
              : const [
                  BoxShadow(
                    offset: Offset(0, 8),
                    blurRadius: 20,
                    spreadRadius: -8,
                    color: Color(0x240A1128),
                  ),
                ],
        ),
        child: Icon(icon, size: iconSize, color: iconColor),
      ),
    );
  }
}
