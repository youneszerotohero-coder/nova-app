import 'package:flutter/material.dart';

import '../theme/nova_colors.dart';
import 'pressable_scale.dart';

/// One choice in a [NovaSegment].
class SegmentItem {
  const SegmentItem({required this.label, this.icon});

  final String label;
  final IconData? icon;
}

/// The pill tab row from the reference: the active choice is a solid
/// near-black pill, the others stay quiet. Works on paper and on top
/// of a colour block ([onColor]).
class NovaSegment extends StatelessWidget {
  const NovaSegment({
    super.key,
    required this.items,
    required this.selected,
    required this.onChanged,
    this.onColor = false,
    this.expand = true,
  });

  final List<SegmentItem> items;
  final int selected;
  final ValueChanged<int> onChanged;

  /// Renders for a saturated/dark backdrop instead of paper.
  final bool onColor;

  /// Fills the available width (tabs), or hugs its content (chips).
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final List<Widget> pills = [
      for (int i = 0; i < items.length; i++)
        _Pill(
          item: items[i],
          active: i == selected,
          onColor: onColor,
          onTap: () => onChanged(i),
        ),
    ];

    return Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      children: [
        for (int i = 0; i < pills.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          expand ? Expanded(child: pills[i]) : pills[i],
        ],
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.item,
    required this.active,
    required this.onColor,
    required this.onTap,
  });

  final SegmentItem item;
  final bool active;
  final bool onColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color background = active
        ? NovaColors.ink950
        : onColor
            ? Colors.white.withValues(alpha: 0.24)
            : NovaColors.subtleFill;
    final Color foreground = active
        ? NovaColors.textOnDark
        : onColor
            ? Colors.white
            : NovaColors.textStrong;

    return PressableScale(
      onTap: onTap,
      pressedScale: 0.95,
      semanticLabel: item.label,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(100),
          boxShadow: active
              ? const [
                  BoxShadow(
                    offset: Offset(0, 8),
                    blurRadius: 18,
                    spreadRadius: -8,
                    color: Color(0x4D0A1128),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (item.icon != null) ...[
              Icon(item.icon, size: 17, color: foreground),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                  letterSpacing: -0.2,
                  color: foreground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
