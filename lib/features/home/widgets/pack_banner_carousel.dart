import 'package:flutter/material.dart';

import '../../../core/i18n/nova_strings.dart';
import '../../../core/theme/nova_colors.dart';
import '../../../core/theme/nova_dimens.dart';
import '../../../core/widgets/circle_icon_button.dart';
import '../../../core/widgets/nova_scene_image.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../../data/models.dart';

/// Promotional banner carousel for the featured packs: scene imagery
/// with the "LEARN TODAY" kicker and uppercase pack headline, advanced
/// by the next/previous round buttons or by swiping, with gradient
/// page dots underneath.
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
    // Tracking pulls Arabic letters apart, so it is Latin-only.
    final bool rtl = direction == TextDirection.rtl;

    return Column(
      children: [
        SizedBox(
          // +30 % (owner): the pack backgrounds show in full.
          height: 203,
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
                    child: PressableScale(
                      onTap: () => widget.onPackTap?.call(pack),
                      semanticLabel: 'Open pack ${pack.name}',
                    child: ClipRRect(
                      borderRadius:
                          BorderRadius.circular(NovaDimens.radiusCard),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          NovaSceneImage(
                            scene: pack.scene,
                            image: pack.image,
                            icon: pack.icon,
                            iconScale: 0.72,
                          ),
                          // Poster scrim: keeps the kicker and headline
                          // legible over any photo, darkest where they
                          // start reading.
                          if (pack.image != null)
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: AlignmentDirectional.centerStart,
                                  end: AlignmentDirectional.centerEnd,
                                  colors: [
                                    Color(0xB30A1128),
                                    Color(0x590A1128),
                                    Color(0x260A1128),
                                  ],
                                ),
                              ),
                            ),
                          Positioned.directional(
                            textDirection: direction,
                            start: 60,
                            end: 84,
                            top: 20,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.tr('home.learnToday'),
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w600,
                                    fontSize: rtl ? 12 : 10,
                                    height: 1.2,
                                    letterSpacing: rtl ? 0 : 3.5,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  pack.headline.toUpperCase(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 24,
                                    height: 1.1,
                                    letterSpacing: rtl ? 0 : -0.2,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
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
                bottom: 0,
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
                bottom: 0,
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
