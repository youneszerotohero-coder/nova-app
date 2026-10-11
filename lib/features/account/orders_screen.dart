import 'package:flutter/material.dart';

import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/utils/format_price.dart';
import '../../core/widgets/hero_style.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/nova_page_header.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../data/models.dart';
import '../cart/order_payment_sheet.dart';
import '../catalog/offers_catalog_screen.dart';
import 'dashboard_card.dart';

/// The website's `/account/orders` on a phone (`OrdersView`, `dashboard.css`):
/// one card per Order with its program, date, total and status chip
/// (paid / awaiting payment / CCP receipt under review = no access), and
/// "Retry payment" while it can still be paid.
class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState app = AppScope.of(context);
    final List<Order> orders = app.commerce.orders;
    return Scaffold(
      backgroundColor: NovaColors.paper,
      body: RefreshIndicator(
        onRefresh: app.commerce.load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(bottom: 40 + MediaQuery.paddingOf(context).bottom),
          children: [
            NovaPageHeader(kicker: context.tr('dash.orders_eyebrow'), title: context.tr('orders.title')),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Entrance(
                child: orders.isEmpty
                    ? HeroEmpty(
                        icon: Icons.credit_card_rounded,
                        title: context.tr('orders.emptyTitle'),
                        message: context.tr('orders.emptyMsg'),
                        action: NovaButton(
                          label: context.tr('dash.see_offers'),
                          chipIcon: Icons.arrow_forward_rounded,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(builder: (_) => const OffersCatalogScreen()),
                          ),
                        ),
                      )
                    // `.ordersHistory`: one card holding the Order cards.
                    : DashboardCard(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(context.tr('dash.billing_history'), style: heroLabel(15, color: NovaColors.accent)),
                            const SizedBox(height: 16),
                            for (final Order order in orders)
                              Padding(padding: const EdgeInsets.only(bottom: 12), child: _OrderCard(order: order)),
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

/// Tone, glyph and label of each Order state (`.orderStatus`): paid =
/// success, awaiting or under review = warning, the rest = danger.
({Color tone, Color background, IconData icon, String label}) _statusStyle(BuildContext context, OrderStatus status) {
  return switch (status) {
    OrderStatus.paid => (
        tone: NovaColors.onlineGreen,
        background: NovaColors.liveBg,
        icon: Icons.check_circle_outline_rounded,
        label: context.tr('orders.paid'),
      ),
    OrderStatus.awaiting => (
        tone: NovaColors.badgeOrange,
        background: NovaColors.quizBg,
        icon: Icons.schedule_rounded,
        label: context.tr('orders.awaiting'),
      ),
    OrderStatus.pendingReview => (
        tone: NovaColors.badgeOrange,
        background: NovaColors.quizBg,
        icon: Icons.hourglass_top_rounded,
        label: context.tr('orders.pendingReview'),
      ),
    OrderStatus.rejected => (
        tone: NovaColors.heartRed,
        background: NovaColors.dangerBg,
        icon: Icons.error_outline_rounded,
        label: context.tr('orders.rejected'),
      ),
    OrderStatus.cancelled || OrderStatus.expired => (
        tone: NovaColors.heartRed,
        background: NovaColors.dangerBg,
        icon: Icons.error_outline_rounded,
        label: context.tr(status == OrderStatus.cancelled ? 'orders.cancelled' : 'orders.expired'),
      ),
  };
}

/// `.tableRow` on a phone: line border, radius 20.
class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final ({Color tone, Color background, IconData icon, String label}) style = _statusStyle(context, order.status);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NovaColors.paperCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: NovaColors.borderOnLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: NovaColors.accentMist, borderRadius: BorderRadius.circular(13)),
                child: Icon(Icons.school_outlined, size: 20, color: NovaColors.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  order.program.isEmpty ? order.number : order.program,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: heroLabel(15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.calendar_today_outlined, size: 17, color: NovaColors.textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(order.date, textDirection: TextDirection.ltr, style: heroLabel(15)),
                ),
              ),
              Icon(Icons.payments_outlined, size: 17, color: NovaColors.textMuted),
              const SizedBox(width: 6),
              // Amounts read left to right in Arabic too.
              Text(formatDaPrice(order.total), textDirection: TextDirection.ltr, style: heroLabel(15)),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: style.background, borderRadius: BorderRadius.circular(10)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(style.icon, size: 16, color: style.tone),
                    const SizedBox(width: 6),
                    Text(style.label, style: heroLabel(14, color: style.tone)),
                  ],
                ),
              ),
              if (order.payable)
                PressableScale(
                  onTap: () => showOrderPayment(context, order),
                  pressedScale: 0.96,
                  semanticLabel: context.tr('orders.retry'),
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(color: NovaColors.accent, borderRadius: BorderRadius.circular(13)),
                    child: Center(
                      widthFactor: 1,
                      child: Text(context.tr('orders.retry'), style: heroLabel(15, color: Colors.white)),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
