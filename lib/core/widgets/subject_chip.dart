import 'package:flutter/material.dart';

import '../theme/nova_colors.dart';
import 'pressable_scale.dart';

/// The one subject pill, shared by the Explore rail and the filter
/// sheet: a rounded capsule in the brand blue with a glyph disc, that
/// fills with the accent gradient when selected.
class SubjectChip extends StatelessWidget {
  const SubjectChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.count,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Defaults to the subject's own glyph.
  final IconData? icon;

  /// Optional course count shown as a trailing badge.
  final int? count;

  static const double height = 44;

  /// Row height for a horizontal rail of chips, leaving room for the
  /// selected chip's glow.
  static const double railHeight = height + 12;

  static IconData iconFor(String subject) => switch (subject) {
        'Mathematics' => Icons.functions_rounded,
        'Physics' => Icons.bolt_rounded,
        'Science' => Icons.biotech_rounded,
        'English' => Icons.translate_rounded,
        'Philosophy' => Icons.psychology_alt_rounded,
        _ => Icons.menu_book_rounded,
      };

  @override
  Widget build(BuildContext context) {
    const NovaHue hue = NovaHue.sky;
    final Color foreground = selected ? Colors.white : hue.onSurface;

    return Semantics(
      selected: selected,
      child: PressableScale(
        onTap: onTap,
        pressedScale: 0.94,
        semanticLabel: label,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          height: height,
          padding: EdgeInsetsDirectional.fromSTEB(
            5,
            0,
            count == null ? 16 : 6,
            0,
          ),
          decoration: BoxDecoration(
            color: selected ? null : hue.surface,
            gradient: selected ? NovaColors.accentGradient : null,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: selected
                  ? Colors.transparent
                  : hue.solid.withValues(alpha: 0.16),
            ),
            boxShadow: [
              BoxShadow(
                offset: const Offset(0, 6),
                blurRadius: 14,
                spreadRadius: -6,
                color: hue.solid.withValues(alpha: selected ? 0.55 : 0),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected
                      ? Colors.white.withValues(alpha: 0.22)
                      : hue.surfaceStrong,
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (Widget child, Animation<double> a) =>
                      ScaleTransition(scale: a, child: child),
                  child: Icon(
                    selected ? Icons.check_rounded : icon ?? iconFor(label),
                    key: ValueKey<bool>(selected),
                    size: 17,
                    color: foreground,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: -0.1,
                  color: foreground,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 8),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  constraints: const BoxConstraints(minWidth: 26),
                  height: 26,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  decoration: BoxDecoration(
                    shape: BoxShape.rectangle,
                    borderRadius: BorderRadius.circular(100),
                    color: selected
                        ? Colors.white.withValues(alpha: 0.22)
                        : NovaColors.paperCard,
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      height: 1,
                      color: foreground,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
