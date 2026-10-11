import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_dimens.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/utils/format_price.dart';
import '../../core/widgets/hero_style.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/nova_page_header.dart';
import '../../core/widgets/nova_scene_image.dart';
import '../../core/widgets/nova_toast.dart';
import '../../core/widgets/pressable_scale.dart';
import '../catalog/offers_catalog_screen.dart';
import '../catalog/units_catalog_screen.dart';
import '../shell/student_top_bar.dart';
import 'checkout_screen.dart';

/// The website's `/cart` (`cart.tsx`, `pages.css`): the programs held for
/// checkout, one of them selected — checkout completes one program at a
/// time, per the conception — then the dark checkout panel under the list
/// whose yellow button takes the selected program to payment.
class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  /// Server key of the selected program; the first one by default.
  String? _selected;

  static void _push(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final AppState state = AppScope.of(context);
    final List<CartItem> items = state.items;
    // As a tab the floating bottom bar covers the end of the page.
    final bool tab = ShellNav.maybeOf(context) != null;
    final CartItem? selected = items.isEmpty
        ? null
        : items.firstWhere((CartItem item) => item.id == _selected, orElse: () => items.first);

    return ColoredBox(
      color: NovaColors.paperPublic,
      child: ListView(
        padding: EdgeInsets.only(bottom: tab ? 130 : 40 + MediaQuery.paddingOf(context).bottom),
        children: [
          NovaPageHeader(
            kicker: context.tr('cart.checkoutEyebrow'),
            title: context.tr('cart.title'),
            lead: context.tr('cart.checkoutOne'),
          ),
          const SizedBox(height: 22),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: selected == null
                ? Entrance(child: _empty(context))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SectionHead(number: '01', label: context.tr('cart.orderDetails'), title: context.tr('cart.chooseProgram')),
                      ...stagger(<Widget>[
                        for (final CartItem item in items)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _CartRow(
                              item: item,
                              state: state,
                              selected: item.id == selected.id,
                              onSelect: () => setState(() => _selected = item.id),
                            ),
                          ),
                      ]),
                      if (items.length == 1) ...[
                        const SizedBox(height: 4),
                        const _CartTip(),
                      ],
                      const SizedBox(height: 24),
                      Entrance(
                        delay: const Duration(milliseconds: 120),
                        child: _CheckoutPanel(
                          item: selected,
                          onCheckout: () => _push(context, CheckoutScreen(item: selected)),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// `HxEmpty.nvCartEmpty`: the Offers first, the Units as the ghost.
  Widget _empty(BuildContext context) {
    return HeroEmpty(
      icon: Icons.shopping_bag_outlined,
      title: context.tr('cart.emptyTitle'),
      message: context.tr('cart.emptyMsg'),
      action: Wrap(
        alignment: WrapAlignment.center,
        spacing: 10,
        runSpacing: 10,
        children: [
          NovaButton(
            label: context.tr('cart.browseOffers'),
            chipIcon: Icons.arrow_forward_rounded,
            onTap: () => _push(context, const OffersCatalogScreen()),
          ),
          NovaButton(
            label: context.tr('cart.exploreUnits'),
            variant: NovaButtonVariant.ghost,
            onTap: () => _push(context, const UnitsCatalogScreen()),
          ),
        ],
      ),
    );
  }
}

/// `.nvSectionHead`: the yellow number tile, the blue label, the title.
class _SectionHead extends StatelessWidget {
  const _SectionHead({required this.number, required this.label, required this.title});

  final String number;
  final String label;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Eyebrow(number: number, label: label, color: NovaColors.accent),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              fontFamily: NovaTypography.display,
              fontFamilyFallback: NovaTypography.fallback,
              fontWeight: FontWeight.w600,
              fontSize: 26,
              height: 1.3,
              color: NovaColors.textStrong,
            ),
          ),
        ],
      ),
    );
  }
}

/// `.nhEyebrow`: a yellow number tile turned −4°, then the label.
class _Eyebrow extends StatelessWidget {
  const _Eyebrow({required this.number, required this.label, required this.color});

  final String number;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.rotate(
          angle: -4 * math.pi / 180,
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: NovaColors.yellow, borderRadius: BorderRadius.circular(9)),
            child: Text(number, style: _label(16, NovaColors.yellowInk)),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(child: Text(label, style: _label(16, color))),
      ],
    );
  }
}

TextStyle _label(double size, Color color, {double height = 1.25}) => TextStyle(
      fontFamily: NovaTypography.display,
      fontFamilyFallback: NovaTypography.fallback,
      fontWeight: FontWeight.w800,
      fontSize: size,
      height: height,
      color: color,
    );

/// One held program (`.nvCartItem`): the radio, the thumbnail, the yellow
/// kind chip, the title, the price and the remove button. The whole card
/// selects it; swiping still removes it.
class _CartRow extends StatelessWidget {
  const _CartRow({required this.item, required this.state, required this.selected, required this.onSelect});

  final CartItem item;
  final AppState state;
  final bool selected;
  final VoidCallback onSelect;

  /// Removes from the server cart; a failure restores the row and says
  /// why instead of silently diverging from the backend.
  Future<void> _remove(BuildContext context) async {
    try {
      await state.commerce.remove(item);
      if (context.mounted) {
        novaToast(context, context.tr('cart.removed'), icon: Icons.delete_outline_rounded);
      }
    } on ApiException catch (error) {
      if (context.mounted) {
        novaToast(context, apiErrorText(context, error), icon: Icons.error_outline_rounded);
      }
      await state.commerce.load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final String meta = item.meta.isNotEmpty ? item.meta : context.tr('cart.yearAccess');
    return Dismissible(
      key: ValueKey<String>(item.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => _remove(context),
      // endToStart swipes reveal the end side: the left in Arabic.
      background: Container(
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsetsDirectional.only(end: 24),
        decoration: BoxDecoration(color: NovaColors.dangerBg, borderRadius: BorderRadius.circular(NovaDimens.radiusTile)),
        child: Icon(Icons.delete_outline_rounded, color: NovaColors.heartRed),
      ),
      child: Semantics(
        selected: selected,
        inMutuallyExclusiveGroup: true,
        child: PressableScale(
          onTap: onSelect,
          pressedScale: 0.99,
          semanticLabel: context.trf('cart.selectItem', {'title': item.title}),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: NovaColors.paperCard,
              borderRadius: BorderRadius.circular(NovaDimens.radiusTile),
              border: Border.all(color: selected ? NovaColors.accent : NovaColors.borderOnLight),
              boxShadow: selected
                  ? <BoxShadow>[BoxShadow(spreadRadius: 3, color: NovaColors.accentMist), ...NovaDimens.shadowCard]
                  : null,
            ),
            child: Row(
              children: [
                _Radio(selected: selected),
                const SizedBox(width: 12),
                // `.nvCartThumb`: 25:23 on the warm grid paper.
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: 84,
                    height: 77,
                    color: const Color(0xFFF4F3EF),
                    child: NovaSceneImage(
                      scene: item.scene,
                      image: item.image,
                      icon: item.icon,
                      iconScale: 0.5,
                      alignment: Alignment.center,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 28,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(color: NovaColors.yellow, borderRadius: BorderRadius.circular(10)),
                        child: Center(
                          widthFactor: 1,
                          child: Text(_kindLabel(context, item), style: _label(14, NovaColors.yellowInk)),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: _label(18, NovaColors.textStrong, height: 1.3)),
                      const SizedBox(height: 4),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: NovaTypography.textTheme.bodyMedium!.copyWith(color: NovaColors.textMuted, fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                formatDaPrice(item.price),
                                // Amounts read left to right in Arabic too.
                                textDirection: TextDirection.ltr,
                                maxLines: 1,
                                style: _label(18.5, NovaColors.textStrong, height: 1.1),
                              ),
                            ),
                          ),
                          // `.nvCartRemove`: a 34 px circle on phones in a
                          // 44 px touch target.
                          Semantics(
                            button: true,
                            label: context.trf('cart.removeItem', {'title': item.title}),
                            excludeSemantics: true,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _remove(context),
                              child: SizedBox(
                                width: 44,
                                height: 44,
                                child: Center(
                                  child: Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: NovaColors.borderOnLight),
                                    ),
                                    child: Icon(Icons.delete_outline_rounded, size: 16, color: NovaColors.textMuted),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
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

String _kindLabel(BuildContext context, CartItem item) =>
    context.tr(item.productKind == 'offer' ? 'checkout.offer' : 'checkout.course');

/// `.nvCartRadio`: 22 px; selected = blue with a surface ring inside.
class _Radio extends StatelessWidget {
  const _Radio({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? NovaColors.accent : Colors.transparent,
        border: Border.all(color: selected ? NovaColors.accent : NovaColors.borderOnLight, width: 2),
      ),
      child: selected
          ? Container(
              margin: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: NovaColors.paperCard, width: 3),
              ),
            )
          : null,
    );
  }
}

/// `.nvCartTip`, under a single program: the Offers may account for the
/// Units already owned.
class _CartTip extends StatelessWidget {
  const _CartTip();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _DashedRRect(color: NovaColors.borderOnLight, radius: NovaDimens.radiusTile),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Transform.rotate(
                  angle: -6 * math.pi / 180,
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: const BoxDecoration(color: NovaColors.yellow, shape: BoxShape.circle),
                    child: const Icon(Icons.auto_awesome_outlined, size: 18, color: NovaColors.yellowInk),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.tr('cart.needAnotherSubject'), style: _label(17, NovaColors.textStrong, height: 1.3)),
                      const SizedBox(height: 2),
                      Text(
                        context.tr('cart.offersAccountOwned'),
                        style: NovaTypography.textTheme.bodyMedium!.copyWith(color: NovaColors.textMuted, fontSize: 15),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 56, top: 6),
              child: PressableScale(
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const OffersCatalogScreen())),
                semanticLabel: context.tr('cart.compareOffers'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(context.tr('cart.compareOffers'), style: _label(15, NovaColors.accent)),
                      const SizedBox(width: 4),
                      Icon(Icons.north_east_rounded, size: 16, color: NovaColors.accent),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The checkout panel's colours (`.nvCheckout`, pages.css): the same in
/// both themes except the panel itself (`#131C44` in dark mode).
abstract final class CheckoutPanelColors {
  static Color get background => NovaColors.current.isDark ? const Color(0xFF131C44) : const Color(0xFF121A3A);
  static const Color text = Color(0xFFEEF1F5);
  static const Color soft = Color(0xFFC8D0EA);
  static const Color mute = Color(0xFF98A3C6);
  static const Color line = Color(0x1FFFFFFF);
  static const Color field = Color(0xFF1C2654);
  static const Color discount = Color(0xFF5BE38F);

  static BoxDecoration decoration({double radius = 24}) => BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(radius),
        border: NovaColors.current.isDark ? Border.all(color: const Color(0x14FFFFFF)) : null,
        boxShadow: <BoxShadow>[
          BoxShadow(
            offset: const Offset(0, 40),
            blurRadius: 80,
            spreadRadius: -40,
            color: NovaColors.current.isDark ? const Color(0xB3000000) : const Color(0x990A0C12),
          ),
        ],
      );
}

/// The dark checkout panel under the list: the selected program, its
/// price, and the yellow "Continue securely" button with its blue chip.
class _CheckoutPanel extends StatelessWidget {
  const _CheckoutPanel({required this.item, required this.onCheckout});

  final CartItem item;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    final String meta = item.meta.isNotEmpty ? item.meta : context.tr('cart.yearAccess');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: CheckoutPanelColors.decoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: _Eyebrow(number: '02', label: context.tr('cart.checkoutEyebrow'), color: NovaColors.yellow),
          ),
          const SizedBox(height: 12),
          Text(context.tr('cart.orderSummary'), style: _label(27, Colors.white, height: 1.3)),
          const SizedBox(height: 18),
          // `.nvSummaryProduct`.
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0x0DFFFFFF), borderRadius: BorderRadius.circular(18)),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: NovaSceneImage(scene: item.scene, image: item.image, icon: item.icon, alignment: Alignment.center),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_kindLabel(context, item), style: _label(13.5, CheckoutPanelColors.mute, height: 1.3)),
                      const SizedBox(height: 3),
                      Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: _label(16, Colors.white, height: 1.3)),
                      const SizedBox(height: 3),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: NovaTypography.textTheme.bodyMedium!.copyWith(color: CheckoutPanelColors.mute, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          // `.nvTotal`: a dashed rule, the label, the amount.
          CustomPaint(
            painter: _DashedTop(color: CheckoutPanelColors.line),
            child: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.tr('cart.total'), style: _label(17, Colors.white, height: 1.3)),
                        const SizedBox(height: 2),
                        Text(
                          context.tr('cart.vatIncluded'),
                          style: NovaTypography.textTheme.bodySmall!.copyWith(color: CheckoutPanelColors.mute, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    formatDaPrice(item.price),
                    textDirection: TextDirection.ltr,
                    style: _label(29, Colors.white, height: 1),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          CheckoutButton(label: context.tr('cart.continueSecurely'), onTap: onCheckout),
        ],
      ),
    );
  }
}

/// `.nvCheckoutButton`: yellow, 62 high, radius 17, 18 px, with the blue
/// 46 px chip (radius 13) at the reading end.
class CheckoutButton extends StatelessWidget {
  const CheckoutButton({super.key, required this.label, this.onTap, this.loading = false, this.icon});

  final String label;
  final VoidCallback? onTap;
  final bool loading;

  /// The chip's glyph; the reading-direction arrow by default.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null && !loading;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: enabled || loading ? 1 : 0.5,
      child: PressableScale(
        onTap: enabled ? onTap : null,
        pressedScale: 0.97,
        semanticLabel: label,
        child: Container(
          constraints: const BoxConstraints(minHeight: 62),
          padding: const EdgeInsetsDirectional.fromSTEB(22, 8, 8, 8),
          decoration: BoxDecoration(color: NovaColors.yellow, borderRadius: BorderRadius.circular(NovaDimens.radiusControl)),
          child: Row(
            children: [
              Expanded(child: Text(label, style: _label(18, NovaColors.yellowInk, height: 1.3))),
              const SizedBox(width: 14),
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: NovaColors.blue, borderRadius: BorderRadius.circular(13)),
                child: loading
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                      )
                    : Icon(icon ?? Icons.arrow_forward_rounded, size: 18, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A 1 px dashed rounded border (`border: 1px dashed`).
class _DashedRRect extends CustomPainter {
  _DashedRRect({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final Path outline = Path()..addRRect(RRect.fromRectAndRadius((Offset.zero & size).deflate(0.5), Radius.circular(radius)));
    for (final metric in outline.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 7) {
        canvas.drawPath(metric.extractPath(d, math.min(d + 4, metric.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRect old) => old.color != color || old.radius != radius;
}

/// The dashed top rule of `.nvTotal`.
class _DashedTop extends CustomPainter {
  _DashedTop({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 7) {
      canvas.drawLine(Offset(x, 0.5), Offset(math.min(x + 4, size.width), 0.5), paint);
    }
  }

  @override
  bool shouldRepaint(_DashedTop old) => old.color != color;
}
