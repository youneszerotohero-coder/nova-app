import 'package:flutter/material.dart';

import '../theme/nova_colors.dart';
import '../theme/nova_dimens.dart';
import 'pressable_scale.dart';

/// The primary gradient pill: brand gradient, soft accent glow and
/// the caller's glyph, which pops when [active] flips.
class GradientPillButton extends StatelessWidget {
  const GradientPillButton({
    super.key,
    required this.icon,
    this.label,
    this.onTap,
    this.height = 56,
    this.width,
    this.active = false,
    this.semanticLabel,
  });

  final IconData icon;
  final String? label;
  final VoidCallback? onTap;
  final double height;
  final double? width;

  /// Replays the glyph's pop-in — for toggles that keep the button in
  /// place while its meaning changes.
  final bool active;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.94,
      semanticLabel: semanticLabel,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        height: height,
        width: width,
        padding: EdgeInsets.symmetric(horizontal: label == null ? 0 : 22),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(NovaDimens.radiusChip),
          gradient: NovaColors.accentGradient,
          boxShadow: NovaDimens.shadowAccent,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (Widget child, Animation<double> animation) {
                return ScaleTransition(scale: animation, child: child);
              },
              child: Icon(
                icon,
                key: ValueKey<bool>(active),
                size: 24,
                color: Colors.white,
              ),
            ),
            if (label != null) ...[
              const SizedBox(width: 10),
              Text(
                label!,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  height: 1,
                  letterSpacing: -0.2,
                  color: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
