import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../i18n/nova_strings.dart';
import '../state/app_state.dart';
import '../theme/nova_colors.dart';
import '../theme/nova_dimens.dart';
import '../theme/nova_typography.dart';
import 'appearance_controls.dart';
import 'hue_card.dart';
import 'monogram_avatar.dart';
import 'nova_bottom_bar.dart';
import 'nova_decor.dart';
import 'nova_page_header.dart';
import 'pressable_scale.dart';

/// Opens the animated navigation menu over the whole app.
///
/// The panel slides in from the reading-start edge (left, or right
/// in Arabic) with a scrim fade while its
/// content staggers in item by item; the dialog transition reverses
/// on dismiss (scrim tap, close button or item selection).
Future<void> showNovaMenu(
  BuildContext context, {
  required List<NovaNavItem> items,
  required int currentIndex,
  required ValueChanged<int> onSelect,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close menu',
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 400),
    transitionBuilder:
        (
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondaryAnimation,
          Widget child,
        ) {
          final Animation<double> curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              // Flips the x offset in RTL, so the panel enters from the
              // right edge it is docked to.
              textDirection: Directionality.of(context),
              position: Tween<Offset>(
                begin: const Offset(-0.22, 0),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
    pageBuilder: (BuildContext context, _, _) => _MenuPanel(
      items: items,
      currentIndex: currentIndex,
      onSelect: onSelect,
    ),
  );
}

/// Each destination keeps one hue across the whole menu.
const List<NovaHue> _rowHues = [
  NovaHue.sky,
  NovaHue.mint,
  NovaHue.lilac,
  NovaHue.peach,
  NovaHue.rose,
];

class _MenuPanel extends StatefulWidget {
  const _MenuPanel({
    required this.items,
    required this.currentIndex,
    required this.onSelect,
  });

  final List<NovaNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  State<_MenuPanel> createState() => _MenuPanelState();
}

class _MenuPanelState extends State<_MenuPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 540),
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _select(int index) {
    Navigator.of(context).pop();
    widget.onSelect(index);
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          width: 316,
          height: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: NovaColors.paperCard,
            borderRadius: BorderRadius.circular(NovaDimens.radiusCardLarge),
            boxShadow: NovaDimens.shadowFloating,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MenuHeader(controller: _controller),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
                  children: [
                    for (int i = 0; i < widget.items.length; i++)
                      _Stagger(
                        controller: _controller,
                        start: 0.2 + i * 0.08,
                        child: _MenuRow(
                          item: widget.items[i],
                          hue: _rowHues[i % _rowHues.length],
                          active: i == widget.currentIndex,
                          onTap: () => _select(i),
                        ),
                      ),
                    // Points and lessons belong to an account (D-127: a visitor has none).
                    if (AppScope.of(context).session.signedIn) ...[
                      const SizedBox(height: 10),
                      _Stagger(
                        controller: _controller,
                        start: 0.68,
                        child: const _RewardCard(),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  6,
                  16,
                  14 + MediaQuery.paddingOf(context).bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(height: 1, color: NovaColors.borderOnLight),
                    const SizedBox(height: 14),
                    _Stagger(
                      controller: _controller,
                      start: 0.78,
                      child: const AppearanceControls(compact: true),
                    ),
                    const SizedBox(height: 12),
                    _Stagger(
                      controller: _controller,
                      start: 0.86,
                      child: Text(
                        'NOVA · ${context.tr('menu.studentApp')}',
                        style: NovaTypography.muted(
                          NovaTypography.textTheme.labelSmall!,
                        ),
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
  }
}

/// The gradient top of the drawer: brand, close and the portrait with
/// the Student's school identity.
class _MenuHeader extends StatelessWidget {
  const _MenuHeader({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    final StudentProfile? student = AppScope.of(context).profile;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        18,
        MediaQuery.paddingOf(context).top + 18,
        18,
        20,
      ),
      decoration: const BoxDecoration(gradient: NovaPageHeader.gradient),
      child: Stack(
        children: [
          const Positioned.fill(
            child: NovaDecor(color: Colors.white, opacity: 0.24, seed: 1),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Stagger(
                controller: controller,
                start: 0,
                child: Row(
                  children: [
                    Text(
                      'nova',
                      style: NovaTypography.textTheme.headlineMedium!
                          .copyWith(color: Colors.white),
                    ),
                    const SizedBox(width: 5),
                    const Padding(
                      padding: EdgeInsets.only(top: 5),
                      child: Sparkle(size: 10),
                    ),
                    const Spacer(),
                    FrostedIconButton(
                      icon: Icons.close_rounded,
                      semanticLabel: 'Close',
                      size: 40,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              _Stagger(
                controller: controller,
                start: 0.08,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2.5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.55),
                          width: 2,
                        ),
                      ),
                      child: MonogramAvatar(
                        label: student?.fullName ?? '',
                        photo: student?.photo,
                        size: 46,
                        showRing: false,
                        colors: const [Color(0xFF14498F), Color(0xFF0E3260)],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            student?.fullName ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: NovaTypography.textTheme.titleLarge!
                                .copyWith(color: Colors.white),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            <String>[
                              student?.level ?? '',
                              student?.track ?? '',
                            ].where((String s) => s.isNotEmpty).join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                NovaTypography.textTheme.bodySmall!.copyWith(
                              color: Colors.white.withValues(alpha: 0.82),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Points and lessons completed, so the drawer always shows progress.
class _RewardCard extends StatelessWidget {
  const _RewardCard();

  @override
  Widget build(BuildContext context) {
    final StudentProfile? student = AppScope.of(context).profile;
    return HueCard(
      hue: NovaHue.butter,
      decorSeed: 3,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const IconTile(
            icon: Icons.stars_rounded,
            hue: NovaHue.butter,
            filled: true,
            size: 40,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.trf('menu.points', {'n': '${student?.points ?? 0}'}),
                  style: NovaTypography.textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  context.trf(
                    'menu.lessonsDone',
                    {'n': '${student?.lessonsCompleted ?? 0}'},
                  ),
                  style: NovaTypography.textTheme.bodySmall!.copyWith(
                    color: NovaHue.butter.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.item,
    required this.hue,
    required this.active,
    required this.onTap,
  });

  final NovaNavItem item;
  final NovaHue hue;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.97,
      semanticLabel: item.label,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        height: 62,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: active ? NovaColors.ink950 : NovaColors.paperCard,
          borderRadius: BorderRadius.circular(NovaDimens.radiusTile),
          border: Border.all(
            color: active ? NovaColors.ink950 : NovaColors.borderOnLight,
          ),
          boxShadow: active ? NovaDimens.shadowSoft : null,
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                IconTile(
                  icon: item.icon,
                  hue: hue,
                  size: 42,
                  filled: active,
                ),
                if (item.badgeCount > 0)
                  PositionedDirectional(
                    end: -2,
                    top: -2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: NovaColors.badgeOrange,
                        borderRadius: BorderRadius.circular(100),
                        border: Border.all(
                          color: active
                              ? NovaColors.ink950
                              : NovaColors.paperCard,
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        item.badgeCount > 9 ? '9+' : '${item.badgeCount}',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w800,
                          fontSize: 9,
                          height: 1.3,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Text(
                item.label,
                style: NovaTypography.textTheme.titleMedium!.copyWith(
                  color:
                      active ? NovaColors.textOnDark : NovaColors.textStrong,
                ),
              ),
            ),
            AnimatedSlide(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              offset: active
                  ? Offset.zero
                  : Offset(
                      Directionality.of(context) == TextDirection.rtl
                          ? 0.4
                          : -0.4,
                      0,
                    ),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 240),
                opacity: active ? 1 : 0,
                child: const Icon(
                  Icons.arrow_forward_rounded,
                  size: 18,
                  color: NovaColors.textOnDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fades and slides a row in as the drawer opens.
class _Stagger extends StatelessWidget {
  const _Stagger({
    required this.controller,
    required this.start,
    required this.child,
  });

  final Animation<double> controller;
  final double start;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Animation<double> animation = CurvedAnimation(
      parent: controller,
      curve: Interval(
        start,
        (start + 0.45).clamp(0.0, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        textDirection: Directionality.of(context),
        position: Tween<Offset>(
          begin: const Offset(-0.25, 0),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }
}
