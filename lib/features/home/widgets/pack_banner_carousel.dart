import 'package:flutter/material.dart';

import '../../../core/theme/nova_colors.dart';
import '../../../core/widgets/circle_icon_button.dart';
import '../../../data/models.dart';
import '../../detail/pack_card.dart';

/// The home carousel of Offers: one [PackCard] per view (poster whole,
/// name and price under it), advanced by the next/previous round buttons
/// or by swiping, with gradient page dots underneath.
class PackBannerCarousel extends StatefulWidget {
  const PackBannerCarousel({super.key, required this.packs, this.onPackTap});

  final List<Pack> packs;
  final ValueChanged<Pack>? onPackTap;

  @override
  State<PackBannerCarousel> createState() => _PackBannerCarouselState();
}

class _PackBannerCarouselState extends State<PackBannerCarousel> {
  late final PageController _controller =
      PageController(viewportFraction: 0.94);
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _onFirst => _page == 0;
  bool get _onLast => _page == widget.packs.length - 1;

  void _go(int delta) {
    final int target = (_page + delta).clamp(0, widget.packs.length - 1);
    _controller.animateToPage(
      target,
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextDirection direction = Directionality.of(context);

    return Column(
      children: [
        SizedBox(
          // One Offer per view, its poster whole (D-122).
          height: PackCard.height,
          child: Stack(
            children: [
              PageView.builder(
                controller: _controller,
                itemCount: widget.packs.length,
                clipBehavior: Clip.none,
                onPageChanged: (int page) => setState(() => _page = page),
                itemBuilder: (BuildContext context, int index) {
                  final Pack pack = widget.packs[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: PackCard(
                      pack: pack,
                      onTap: () => widget.onPackTap?.call(pack),
                    ),
                  );
                },
              ),

              // Carousel controls. Directional so Arabic mirrors them:
              // the PageView runs right-to-left there, so "previous"
              // sits on the right and "next" on the left.
              Positioned.directional(
                textDirection: direction,
                start: 14,
                top: 0,
                bottom: PackCard.stripHeight,
                child: Center(
                  child: _CarouselArrow(
                    icon: Icons.chevron_left_rounded,
                    label: 'Previous pack',
                    enabled: !_onFirst,
                    onTap: () => _go(-1),
                  ),
                ),
              ),
              Positioned.directional(
                textDirection: direction,
                end: 14,
                top: 0,
                bottom: PackCard.stripHeight,
                child: Center(
                  child: _CarouselArrow(
                    icon: Icons.chevron_right_rounded,
                    label: 'Next pack',
                    enabled: !_onLast,
                    onTap: () => _go(1),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (int i = 0; i < widget.packs.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOut,
                width: i == _page ? 20 : 7,
                height: 7,
                decoration: BoxDecoration(
                  color: i == _page
                      ? null
                      : const Color(0xFFC5D3E7),
                  gradient: i == _page ? NovaColors.accentGradient : null,
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _CarouselArrow extends StatelessWidget {
  const _CarouselArrow({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: enabled ? 1 : 0.35,
      child: CircleIconButton(
        icon: icon,
        size: 42,
        iconSize: 24,
        onTap: enabled ? onTap : null,
        semanticLabel: label,
      ),
    );
  }
}
