import 'package:flutter/material.dart';

import '../theme/nova_colors.dart';
import '../theme/nova_dimens.dart';
import 'pressable_scale.dart';

/// The circular icon button: the surface with its hairline and the sticker
/// shadow, or the blue fill when [dark].
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

  /// The filled variant: the website's blue `.hxBtn` with a white glyph.
  final bool dark;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final Color fill = dark ? NovaColors.accent : NovaColors.paperCard;
    final Color iconColor = dark ? Colors.white : NovaColors.textStrong;

    return PressableScale(
      onTap: onTap,
      semanticLabel: semanticLabel,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: fill,
          shape: BoxShape.circle,
          border: dark ? null : Border.all(color: NovaColors.borderOnLight),
          boxShadow: dark ? null : NovaDimens.shadowSticker,
        ),
        child: Icon(icon, size: iconSize, color: iconColor),
      ),
    );
  }
}
