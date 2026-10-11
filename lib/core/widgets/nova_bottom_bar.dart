import 'package:flutter/material.dart';

import '../theme/nova_colors.dart';
import '../theme/nova_dimens.dart';
import '../theme/nova_typography.dart';
import 'pressable_scale.dart';

/// A destination in the floating pill navigation bar.
class NovaNavItem {
  const NovaNavItem({
    required this.icon,
    required this.label,
    this.badgeCount = 0,
  });

  final IconData icon;
  final String label;
  final int badgeCount;
}

/// The website's phone bottom bar (`.studentBottomNav`): a navy pill, each
/// destination an icon over its label, and a yellow marker that slides to
/// the active one.
class NovaBottomBar extends StatelessWidget {
  const NovaBottomBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onChanged,
  });

  final List<NovaNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onChanged;

  static const double _pad = 6;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 12,
      right: 12,
      // Above the system navigation bar when the app draws behind it
      // (edge-to-edge); 0 extra otherwise.
      bottom: 12 + MediaQuery.viewPaddingOf(context).bottom,
      child: Container(
        height: NovaDimens.bottomBarHeight,
        padding: const EdgeInsets.all(_pad),
        decoration: BoxDecoration(
          color: NovaColors.ink950,
          borderRadius: BorderRadius.circular(NovaDimens.radiusChip),
          boxShadow: NovaDimens.shadowFloating,
        ),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double slot = constraints.maxWidth / items.length;
            return Stack(
              children: [
                // Directional so the marker follows the Row, which lays
                // out right-to-left in Arabic.
                AnimatedPositionedDirectional(
                  duration: const Duration(milliseconds: 350),
                  curve: const Cubic(0.2, 0.8, 0.2, 1),
                  start: slot * currentIndex,
                  top: 0,
                  bottom: 0,
                  width: slot,
                  child: Container(
                    decoration: BoxDecoration(
                      color: NovaColors.yellow,
                      borderRadius: BorderRadius.circular(NovaDimens.radiusChip),
                      boxShadow: const [
                        BoxShadow(offset: Offset(0, 6), blurRadius: 16, spreadRadius: -4, color: Color(0x80FFD54A)),
                      ],
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (int i = 0; i < items.length; i++)
                      SizedBox(
                        width: slot,
                        child: _NavItemButton(
                          item: items[i],
                          active: i == currentIndex,
                          onTap: () => onChanged(i),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NavItemButton extends StatelessWidget {
  const _NavItemButton({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final NovaNavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: item.label,
      child: PressableScale(
        onTap: onTap,
        pressedScale: 0.9,
        child: TweenAnimationBuilder<Color?>(
          duration: const Duration(milliseconds: 250),
          tween: ColorTween(end: active ? NovaColors.yellowInk : Colors.white.withValues(alpha: 0.72)),
          builder: (BuildContext context, Color? color, _) => Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(item.icon, size: 22, color: color),
                  if (item.badgeCount > 0)
                    PositionedDirectional(
                      top: -6,
                      end: -10,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 17),
                        height: 17,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF5D5D),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(
                          item.badgeCount > 9 ? '9+' : '${item.badgeCount}',
                          style: const TextStyle(
                            fontFamily: NovaTypography.body,
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                            height: 1.2,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: NovaTypography.display,
                    fontFamilyFallback: NovaTypography.fallback,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    height: 1.2,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
