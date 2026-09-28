import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/widgets/hue_card.dart';
import '../../core/widgets/nova_toast.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../data/models.dart';

/// Lets the Student choose a CCP receipt: JPEG, PNG or PDF up to
/// 10 MB, the backend's own limits. Null when cancelled.
Future<File?> pickCcpReceipt(BuildContext context) async {
  final List<PlatformFile> files = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const <String>['jpg', 'jpeg', 'png', 'pdf'],
  );
  final String? path = files.isEmpty ? null : files.first.path;
  if (path == null) return null;
  final File file = File(path);
  if (await file.length() > 10 * 1024 * 1024) {
    if (context.mounted) {
      novaToast(context, context.tr('checkout.receiptTooBig'),
          icon: Icons.error_outline_rounded);
    }
    return null;
  }
  return file;
}

/// Opens Chargily's hosted checkout for [orderId] in the browser; the
/// order turns paid through Chargily's webhook, not through the app.
Future<void> openChargilyCheckout(BuildContext context, int orderId) async {
  final Uri url =
      await AppScope.of(context).commerce.chargilyCheckout(orderId);
  final bool opened =
      await launchUrl(url, mode: LaunchMode.externalApplication);
  if (!opened) {
    throw const ApiException(
      status: 0,
      code: 'CHECKOUT_UNAVAILABLE',
      message: 'Could not open the payment page.',
    );
  }
}

/// Pays an order that is still awaiting payment (from Orders): upload a
/// CCP receipt or go to the card checkout.
Future<void> showOrderPayment(BuildContext context, Order order) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (BuildContext context) => _OrderPaymentSheet(order: order),
  );
}

class _OrderPaymentSheet extends StatefulWidget {
  const _OrderPaymentSheet({required this.order});

  final Order order;

  @override
  State<_OrderPaymentSheet> createState() => _OrderPaymentSheetState();
}

class _OrderPaymentSheetState extends State<_OrderPaymentSheet> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String doneKey) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      Navigator.of(context).pop();
      novaToast(context, context.tr(doneKey), icon: Icons.check_circle_rounded);
    } on ApiException catch (error) {
      if (mounted) {
        novaToast(context, apiErrorText(context, error),
            icon: Icons.error_outline_rounded);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _ccp() async {
    final File? receipt = await pickCcpReceipt(context);
    if (receipt == null || !mounted) return;
    final AppState app = AppScope.of(context);
    await _run(
      () => app.commerce.uploadCcpReceipt(widget.order.id, receipt),
      'checkout.orderSent',
    );
  }

  Future<void> _card() => _run(
        () => openChargilyCheckout(context, widget.order.id),
        'checkout.cardOpened',
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(10),
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: NovaColors.paperCard,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.tr('checkout.method'),
              style: NovaTypography.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '${widget.order.number} · ${widget.order.program}',
            style: NovaTypography.muted(NovaTypography.textTheme.bodySmall!),
          ),
          const SizedBox(height: 16),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(18),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            _Option(
              icon: Icons.receipt_long_rounded,
              hue: NovaHue.butter,
              title: context.tr('checkout.ccp'),
              subtitle: context.tr('checkout.uploadReceipt'),
              onTap: _ccp,
            ),
            const SizedBox(height: 10),
            _Option(
              icon: Icons.credit_card_rounded,
              hue: NovaHue.sky,
              title: context.tr('checkout.card'),
              subtitle: context.tr('checkout.cardSub'),
              onTap: _card,
            ),
          ],
        ],
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.icon,
    required this.hue,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final NovaHue hue;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      semanticLabel: title,
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: NovaColors.borderOnLight),
        ),
        child: Row(
          children: [
            IconTile(icon: icon, hue: hue, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: NovaTypography.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: NovaTypography.muted(
                      NovaTypography.textTheme.bodySmall!,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: NovaColors.textMuted),
          ],
        ),
      ),
    );
  }
}
