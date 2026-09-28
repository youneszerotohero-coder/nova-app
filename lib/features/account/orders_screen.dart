import 'package:flutter/material.dart';

import '../../core/i18n/labels.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/utils/format_price.dart';
import '../../core/widgets/hue_card.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../data/models.dart';
import '../../core/state/app_state.dart';
import '../cart/order_payment_sheet.dart';

/// Billing history: every order with its program, total and status
/// chip (paid / awaiting payment / CCP pending review = no access).
class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState app = AppScope.of(context);
    final List<Order> orders = app.commerce.orders;
    return PageScaffold(
      title: context.tr('orders.title'),
      kicker: context.trf(
        'orders.kicker',
        {'n': orders.length.toString()},
      ),
      watermark: Icons.receipt_long_rounded,
      body: RefreshIndicator(
        onRefresh: app.commerce.load,
        child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        children: orders.isEmpty
            ? <Widget>[
                EmptyState(
                  icon: Icons.receipt_long_rounded,
                  title: context.tr('orders.emptyTitle'),
                  message: context.tr('orders.emptyMsg'),
                ),
              ]
            : stagger(
          orders
              .map(
                (Order order) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _OrderCard(order: order),
                ),
              )
              .toList(),
        ),
      ),
      ),
    );
  }
}

/// Hue, glyph and label for each order state — one source of truth so
/// the chip and the icon tile can never disagree.
({NovaHue hue, IconData icon, String label}) _statusStyle(
  BuildContext context,
  OrderStatus status,
) {
  return switch (status) {
    OrderStatus.paid => (
        hue: NovaHue.mint,
        icon: Icons.check_circle_rounded,
        label: context.tr('orders.paid'),
      ),
    OrderStatus.awaiting => (
        hue: NovaHue.peach,
        icon: Icons.schedule_rounded,
        label: context.tr('orders.awaiting'),
      ),
    OrderStatus.pendingReview => (
        hue: NovaHue.butter,
        icon: Icons.hourglass_top_rounded,
        label: context.tr('orders.pendingReview'),
      ),
    OrderStatus.rejected => (
        hue: NovaHue.rose,
        icon: Icons.receipt_long_rounded,
        label: context.tr('orders.rejected'),
      ),
    OrderStatus.cancelled || OrderStatus.expired => (
        hue: NovaHue.ink,
        icon: Icons.block_rounded,
        label: context.tr(
          status == OrderStatus.cancelled ? 'orders.cancelled' : 'orders.expired',
        ),
      ),
  };
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final ({NovaHue hue, IconData icon, String label}) style =
        _statusStyle(context, order.status);

    return NovaCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconTile(icon: style.icon, hue: style.hue, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.program,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: NovaTypography.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${modelLabelText(context, order.kind)} · ${modelLabelText(context, order.method)}',
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
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: NovaColors.subtleFill,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.number,
                        style: NovaTypography.textTheme.labelMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        order.date,
                        style: NovaTypography.muted(
                          NovaTypography.textTheme.bodySmall!,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  formatDaPrice(order.total),
                  style: NovaTypography.textTheme.titleMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatusChip(
                label: style.label,
                icon: style.icon,
                hue: style.hue,
              ),
              const Spacer(),
              if (order.payable)
                PressableScale(
                  onTap: () => showOrderPayment(context, order),
                  semanticLabel: context.tr('orders.retry'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: NovaColors.ink950,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      context.tr('orders.retry'),
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: NovaColors.textOnDark,
                      ),
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.icon,
    required this.hue,
  });

  final String label;
  final IconData icon;
  final NovaHue hue;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: hue.surfaceStrong,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: hue.onSurface),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w700,
              fontSize: 11,
              color: hue.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
