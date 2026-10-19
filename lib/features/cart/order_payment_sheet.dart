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
import '../../core/widgets/nova_toast.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../data/models.dart';
import 'cart_screen.dart';

/// Lets the Student choose a photo of the CCP receipt from the phone's
/// photos (owner request, 2026-10-19): JPEG or PNG up to 10 MB, the
/// backend's own limits. iOS hands an iPhone photo (HEIC) over as JPEG.
/// Null when cancelled.
Future<File?> pickCcpReceipt(BuildContext context) async {
  final List<PlatformFile> files = await FilePicker.pickFiles(
    type: FileType.image,
    darwinOptions: const DarwinOptions(assetRepresentationMode: DarwinAssetRepresentationMode.compatible),
  );
  final String? path = files.isEmpty ? null : files.first.path;
  if (path == null) return null;
  if (!RegExp(r'\.(jpe?g|png)$', caseSensitive: false).hasMatch(path)) {
    if (context.mounted) {
      novaToast(context, context.tr('checkout.receiptFormat'), icon: Icons.error_outline_rounded);
    }
    return null;
  }
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
    // The website's dark checkout panel and its payment cards.
    return Container(
      margin: const EdgeInsets.all(10),
      padding: EdgeInsets.fromLTRB(
        16,
        20,
        16,
        16 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: CheckoutPanelColors.decoration(radius: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.tr('checkout.method'), style: _label(17, Colors.white)),
          const SizedBox(height: 4),
          Text(
            '${widget.order.number} · ${widget.order.program}',
            style: _text(14, CheckoutPanelColors.mute),
          ),
          const SizedBox(height: 16),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(18),
              child: Center(child: CircularProgressIndicator(color: NovaColors.yellow)),
            )
          else ...[
            _Option(
              icon: Icons.receipt_long_rounded,
              title: context.tr('checkout.ccp'),
              subtitle: context.tr('checkout.uploadReceipt'),
              onTap: _ccp,
            ),
            const SizedBox(height: 10),
            _Option(
              icon: Icons.credit_card_rounded,
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

TextStyle _label(double size, Color color) => TextStyle(
      fontFamily: NovaTypography.display,
      fontFamilyFallback: NovaTypography.fallback,
      fontWeight: FontWeight.w800,
      fontSize: size,
      height: 1.3,
      color: color,
    );

TextStyle _text(double size, Color color) => TextStyle(
      fontFamily: NovaTypography.body,
      fontFamilyFallback: NovaTypography.fallback,
      fontWeight: FontWeight.w500,
      fontSize: size,
      height: 1.45,
      color: color,
    );

/// `.nvPayCard`: the white art tile, the method and its help line.
class _Option extends StatelessWidget {
  const _Option({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.98,
      semanticLabel: title,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: CheckoutPanelColors.line),
        ),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 44,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 22, color: const Color(0xFF17191D)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: _label(16, Colors.white)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: _text(14, CheckoutPanelColors.mute)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: CheckoutPanelColors.mute),
          ],
        ),
      ),
    );
  }
}
