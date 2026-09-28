import 'package:flutter/material.dart';

import '../../core/i18n/labels.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_dimens.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/utils/format_price.dart';
import '../../core/widgets/hue_card.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/nova_page_header.dart';
import '../../core/widgets/nova_scene_image.dart';
import '../../core/widgets/nova_toast.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/pressable_scale.dart';
import 'checkout_screen.dart';

/// Cart tab: programs held for checkout. Per the conception, checkout
/// completes one program at a time, so the floating bar always names
/// the program it will take to payment.
class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState state = AppScope.of(context);

    if (state.items.isEmpty) {
      return Column(
        children: [
          NovaPageHeader(
            title: context.tr('cart.title'),
            kicker: _kicker(context, state.items.length),
            watermark: Icons.shopping_bag_rounded,
          ),
          Expanded(
            child: EmptyState(
              icon: Icons.shopping_bag_outlined,
              hue: NovaHue.sky,
              title: context.tr('cart.emptyTitle'),
              message: context.tr('cart.emptyMsg'),
            ),
          ),
        ],
      );
    }

    final CartItem first = state.items.first;
    final int total = state.items.fold(
      0,
      (int sum, CartItem item) => sum + item.price,
    );

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.only(bottom: 208),
          children: [
            NovaPageHeader(
              title: context.tr('cart.title'),
              kicker: _kicker(context, state.items.length),
              watermark: Icons.shopping_bag_rounded,
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 15,
                    color: NovaColors.accentDeep,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      context.tr('cart.oneAtATime'),
                      style: NovaTypography.textTheme.bodySmall!.copyWith(
                        color: NovaColors.accentDeep,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ...stagger(
              state.items
                  .map(
                    (CartItem item) => Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: _CartRow(item: item, state: state),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: HueCard(
                hue: NovaHue.butter,
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const IconTile(
                      icon: Icons.lightbulb_rounded,
                      hue: NovaHue.butter,
                      size: 38,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        context.tr('cart.tip'),
                        style: NovaTypography.textTheme.bodySmall!.copyWith(
                          color: NovaHue.butter.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _CheckoutBar(
            total: total,
            count: state.items.length,
            onCheckout: () => _checkout(context, first),
          ),
        ),
      ],
    );
  }

  /// "1 program waiting" / "3 programs waiting".
  static String _kicker(BuildContext context, int count) => count == 1
      ? context.tr('profile.cartSubOne')
      : context.trf('profile.cartSub', {'n': count.toString()});

  static void _checkout(BuildContext context, CartItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CheckoutScreen(item: item),
      ),
    );
  }
}

/// Floating summary + CTA, sitting just above the tab bar with a fade
/// so rows scroll away underneath it rather than colliding.
class _CheckoutBar extends StatelessWidget {
  const _CheckoutBar({
    required this.total,
    required this.count,
    required this.onCheckout,
  });

  final int total;
  final int count;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 26, 20, 104),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              NovaColors.paper.withValues(alpha: 0),
              NovaColors.paper.withValues(alpha: 0.92),
              NovaColors.paper,
            ],
            stops: const [0, 0.35, 1],
          ),
        ),
        child: PressableScale(
          onTap: onCheckout,
          pressedScale: 0.97,
          semanticLabel: context.tr('cart.checkout'),
          child: Container(
            height: 62,
            padding: const EdgeInsetsDirectional.fromSTEB(22, 0, 8, 0),
            decoration: BoxDecoration(
              color: NovaColors.ink950,
              borderRadius: BorderRadius.circular(100),
              boxShadow: NovaDimens.shadowFloating,
            ),
            child: Row(
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('cart.total').toUpperCase(),
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w700,
                        fontSize: 9.5,
                        letterSpacing: 1.6,
                        color: NovaColors.textMutedOnDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatDaPrice(total),
                      style: const TextStyle(
                        fontFamily: 'InterDisplay',
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                        height: 1.1,
                        letterSpacing: -0.4,
                        color: NovaColors.textOnDark,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: NovaColors.accentGradient,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        context.tr('cart.checkout'),
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        size: 17,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One held program: cover, kind, title, price and a remove action.
/// Swiping still removes it; the button makes that discoverable.
class _CartRow extends StatelessWidget {
  const _CartRow({required this.item, required this.state});

  final CartItem item;
  final AppState state;

  /// Removes from the server cart; a failure restores the row and says
  /// why instead of silently diverging from the backend.
  Future<void> _remove(BuildContext context) async {
    try {
      await state.commerce.remove(item);
      if (context.mounted) {
        novaToast(
          context,
          context.tr('cart.removed'),
          icon: Icons.delete_outline_rounded,
        );
      }
    } on ApiException catch (error) {
      if (context.mounted) {
        novaToast(context, apiErrorText(context, error),
            icon: Icons.error_outline_rounded);
      }
      await state.commerce.load();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Titles read "Subject — Course", so seeding on the subject keeps
    // a program the same colour here as in the catalog.
    final NovaHue hue = NovaHue.of(item.title.split('—').first.trim());

    return Dismissible(
      key: ValueKey<String>(item.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => _remove(context),
      // endToStart swipes reveal the end side: the left in Arabic.
      background: Container(
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsetsDirectional.only(end: 24),
        decoration: BoxDecoration(
          color: NovaColors.heartRed.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(NovaDimens.radiusTile),
        ),
        child: const Icon(
          Icons.delete_outline_rounded,
          color: NovaColors.heartRed,
        ),
      ),
      child: PressableScale(
        onTap: () => CartScreen._checkout(context, item),
        pressedScale: 0.98,
        semanticLabel: 'Checkout ${item.title}',
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: NovaColors.paperCard,
            borderRadius: BorderRadius.circular(NovaDimens.radiusTile),
            border: Border.all(color: NovaColors.borderOnLight),
            boxShadow: NovaDimens.shadowSoft,
          ),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: SizedBox(
                      width: 78,
                      height: 78,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          NovaSceneImage(
                            scene: item.scene,
                            image: item.image,
                            icon: item.icon,
                            iconScale: 0.5,
                            alignment: Alignment.center,
                          ),
                          if (item.discountPercent > 0)
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 3,
                                ),
                                color: NovaColors.heartRed,
                                child: Text(
                                  formatDiscount(item.discountPercent),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w800,
                                    fontSize: 10,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: hue.surfaceStrong,
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Text(
                            modelLabelText(context, item.kind),
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w700,
                              fontSize: 10,
                              color: hue.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: NovaTypography.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          context.tr('cart.yearAccess'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: NovaTypography.muted(
                            NovaTypography.textTheme.bodySmall!,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                height: 1,
                color: NovaColors.borderOnLight,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    formatDaPrice(item.price),
                    style: NovaTypography.textTheme.titleMedium,
                  ),
                  if (item.compareAtPrice > item.price) ...[
                    const SizedBox(width: 8),
                    Text(
                      formatDaPrice(item.compareAtPrice),
                      style: NovaTypography.textTheme.bodySmall!.copyWith(
                        decoration: TextDecoration.lineThrough,
                        decorationColor: NovaColors.textMuted,
                      ),
                    ),
                  ],
                  const Spacer(),
                  PressableScale(
                    onTap: () => _remove(context),
                    pressedScale: 0.9,
                    semanticLabel: context.tr('cart.remove'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: NovaColors.heartRed.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.delete_outline_rounded,
                            size: 15,
                            color: NovaColors.heartRed,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            context.tr('cart.remove'),
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w700,
                              fontSize: 11.5,
                              color: NovaColors.heartRed,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
