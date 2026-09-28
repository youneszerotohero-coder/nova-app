import 'package:flutter/material.dart';

import '../theme/nova_colors.dart';
import 'circle_icon_button.dart';

/// Circular button with the small orange count badge seen on the
/// reference notification bell.
class BadgeIconButton extends StatelessWidget {
  const BadgeIconButton({
    super.key,
    required this.icon,
    this.count = 0,
    this.onTap,
    this.semanticLabel,
  });

  final IconData icon;
  final int count;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleIconButton(
            icon: icon,
            onTap: onTap,
            semanticLabel: semanticLabel,
          ),
          if (count > 0)
            Positioned(
              top: -2,
              right: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 2,
                ),
                decoration: const BoxDecoration(
                  color: NovaColors.accent,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  count > 9 ? '9+' : '$count',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700,
                    fontSize: 10.5,
                    height: 1.2,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
