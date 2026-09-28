import 'package:flutter/material.dart';

import '../theme/nova_colors.dart';
import '../theme/nova_dimens.dart';
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

/// Floating ink pill navigation. The gradient marker slides between
/// destinations rather than popping, so switching tabs reads as one
/// continuous move.
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

  static const double _marker = 50;
  static const double _inset = 9;

  /// A tap on the pill's padding ring goes to the tab it is closest to.
  void _tapRing(Offset position, double width, TextDirection direction) {
    final double slot = (width - 2 * _inset) / items.length;
    int index = ((position.dx - _inset) / slot).floor().clamp(
      0,
      items.length - 1,
    );
    if (direction == TextDirection.rtl) index = items.length - 1 - index;
    onChanged(index);
  }

  @override
  Widget build(BuildContext context) {
    final TextDirection direction = Directionality.of(context);

    return Positioned(
      left: 0,
      right: 0,
      // Above the system navigation bar when the app draws behind it
      // (edge-to-edge); 0 extra otherwise.
      bottom: 18 + MediaQuery.viewPaddingOf(context).bottom,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints bar) =>
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (TapUpDetails details) =>
                    _tapRing(details.localPosition, bar.maxWidth, direction),
                child: _pill(),
              ),
        ),
      ),
    );
  }

  Widget _pill() {
    return Container(
      height: NovaDimens.bottomBarHeight,
      padding: const EdgeInsets.all(_inset),
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
              // Directional so the marker follows the Row, which
              // lays out right-to-left in Arabic.
              AnimatedPositionedDirectional(
                duration: const Duration(milliseconds: 340),
                curve: Curves.easeOutCubic,
                start: slot * currentIndex + (slot - _marker) / 2,
                top: 0,
                child: Container(
                  width: _marker,
                  height: _marker,
                  decoration: const BoxDecoration(
                    gradient: NovaColors.accentGradient,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        offset: Offset(0, 6),
                        blurRadius: 16,
                        spreadRadius: -4,
                        color: Color(0x662B87F7),
                      ),
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
        pressedScale: 0.88,
        child: SizedBox(
          height: NovaBottomBar._marker,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              // A gentle lift on the active glyph, on top of the
              // marker that slid in underneath it.
              AnimatedScale(
                duration: const Duration(milliseconds: 340),
                curve: Curves.easeOutBack,
                scale: active ? 1.08 : 1,
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 340),
                  curve: Curves.easeOutCubic,
                  offset: active ? const Offset(0, -0.04) : Offset.zero,
                  child: TweenAnimationBuilder<Color?>(
                    duration: const Duration(milliseconds: 280),
                    tween: ColorTween(
                      end: active ? Colors.white : NovaColors.textMutedOnDark,
                    ),
                    builder: (BuildContext context, Color? color, _) => Icon(
                      item.icon,
                      size: 23,
                      color: color ?? NovaColors.textMutedOnDark,
                    ),
                  ),
                ),
              ),
              if (item.badgeCount > 0 && !active)
                PositionedDirectional(
                  top: 8,
                  end: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    constraints: const BoxConstraints(minWidth: 16),
                    decoration: const BoxDecoration(
                      color: NovaColors.accent,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      item.badgeCount > 9 ? '9+' : '${item.badgeCount}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w700,
                        fontSize: 9.5,
                        height: 1.3,
                        color: Colors.white,
                      ),
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
