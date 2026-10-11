import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/utils/format_price.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/widgets/hero_style.dart';
import '../../core/widgets/nova_page_header.dart';
import '../../core/widgets/nova_scene_image.dart';
import '../../core/widgets/success_burst.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../data/commerce_store.dart';
import '../account/orders_screen.dart';
import 'cart_screen.dart';
import 'order_payment_sheet.dart';

/// Checkout for one program, driven by the backend: every amount comes
/// from `POST /checkout/quote` (overlap credit, referral/promo code,
/// points applied automatically), the order from `POST /orders`, then
/// Chargily card checkout, a CCP receipt upload, or an order already
/// paid at zero. As on the website there is no points control, and the
/// discount code is a text link under the pay button.
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key, required this.item});

  final CartItem item;

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

enum _PayMethod { card, ccp }

enum _Phase { form, processing, paid, queued, cardOpened }

class _CheckoutScreenState extends State<CheckoutScreen> {
  final TextEditingController _code = TextEditingController();

  _PayMethod _method = _PayMethod.card;
  _Phase _phase = _Phase.form;
  Quote? _quote;

  /// Why the quote could not be computed; nothing can be paid then.
  String? _quoteError;
  String? _submitError;

  /// A quote request is in flight; the pay button waits for it.
  bool _quoting = false;
  bool _checkingCode = false;

  /// Only the latest quote request may update the screen.
  int _quoteSeq = 0;

  bool _codeOpen = false;
  String? _appliedCode;
  String? _codeError;
  File? _receipt;
  String _orderNumber = '—';

  CommerceStore get _commerce => AppScope.of(context).commerce;

  /// A zero total: the backend pays the order when it is created.
  bool get _free => _quote?.finalAmount == 0;
  bool get _codeVisible => _codeOpen || _appliedCode != null;
  bool get _canSubmit =>
      _quote != null &&
      !_quoting &&
      (_free || _method == _PayMethod.card || _receipt != null);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadQuote());
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  /// Same requests as the website: a quote with `points_to_use: 0`,
  /// then — when redemption is on and points are usable — the same
  /// quote with the maximum the backend allows. Points are never picked
  /// by hand; the summary only shows what the server applied.
  Future<Quote> _fetchQuote(String? code) async {
    final Quote first = await _commerce.quote(widget.item, discountCode: code);
    if (!first.pointsEnabled || first.maxPointsUsable <= 0) return first;
    return _commerce.quote(
      widget.item,
      discountCode: code,
      points: first.maxPointsUsable,
    );
  }

  /// Quotes with the applied code (if any): on open, on retry and after
  /// the code is removed. A failure leaves no quote to pay on.
  Future<void> _loadQuote() async {
    final int seq = ++_quoteSeq;
    setState(() {
      _quoting = true;
      _quoteError = null;
    });
    try {
      final Quote quote = await _fetchQuote(_appliedCode);
      if (!mounted || seq != _quoteSeq) return;
      setState(() => _quote = quote);
    } on ApiException catch (error) {
      if (!mounted || seq != _quoteSeq) return;
      setState(() {
        _quote = null;
        _quoteError = apiErrorText(context, error);
      });
    } finally {
      if (mounted && seq == _quoteSeq) setState(() => _quoting = false);
    }
  }

  /// The backend recognizes the code as a referral or a promo code. A
  /// refused code keeps the current quote and says why under the field.
  Future<void> _applyCode() async {
    final String code = _code.text.trim();
    if (code.isEmpty) return;
    FocusScope.of(context).unfocus();
    final int seq = ++_quoteSeq;
    setState(() {
      _quoting = true;
      _checkingCode = true;
      _codeError = null;
    });
    try {
      final Quote quote = await _fetchQuote(code);
      if (!mounted || seq != _quoteSeq) return;
      setState(() {
        _quote = quote;
        _quoteError = null;
        if (quote.commercialDiscount != 'none') _appliedCode = code;
      });
    } on ApiException catch (error) {
      if (!mounted || seq != _quoteSeq) return;
      setState(() => _codeError = apiErrorText(context, error));
    } finally {
      if (mounted && seq == _quoteSeq) {
        setState(() {
          _quoting = false;
          _checkingCode = false;
        });
      }
    }
  }

  Future<void> _removeCode() {
    setState(() {
      _appliedCode = null;
      _codeError = null;
      _code.clear();
    });
    return _loadQuote();
  }

  Future<void> _pickReceipt() async {
    final File? file = await pickCcpReceipt(context);
    if (file != null && mounted) setState(() => _receipt = file);
  }

  Future<void> _submit() async {
    final Quote? quote = _quote;
    if (quote == null || !_canSubmit) return;
    final AppState app = AppScope.of(context);
    setState(() {
      _phase = _Phase.processing;
      _submitError = null;
    });
    try {
      final Map<String, dynamic> order = await _commerce.placeOrder(
        widget.item,
        discountCode: _appliedCode,
        commercialDiscount: quote.commercialDiscount,
        points: quote.pointsUsed,
      );
      final int orderId = order['id'] is int ? order['id'] as int : 0;
      _orderNumber = '${order['order_number'] ?? '—'}';

      if (order['status'] == 'paid') {
        await app.refreshAccount();
        if (mounted) setState(() => _phase = _Phase.paid);
        return;
      }
      if (!mounted) return;
      final File? receipt = _receipt;
      if (_method == _PayMethod.ccp && receipt != null) {
        await _commerce.uploadCcpReceipt(orderId, receipt);
        if (mounted) setState(() => _phase = _Phase.queued);
      } else {
        await openChargilyCheckout(context, orderId);
        if (mounted) setState(() => _phase = _Phase.cardOpened);
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.form;
        _submitError = apiErrorText(context, error);
      });
    }
  }

  String _kindLabel(BuildContext context) => widget.item.productKind == 'offer'
      ? context.tr('checkout.offer')
      : context.tr('checkout.course');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NovaColors.paperPublic,
      body: Stack(
        children: [
          if (_phase == _Phase.processing)
            const _ProcessingView()
          else
            ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.only(
                bottom: 28 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                NovaPageHeader(
                  title: context.tr('checkout.title'),
                  kicker: _kindLabel(context),
                  showBack: true,
                ),
                const SizedBox(height: 20),
                // The website's dark checkout panel (`.nvCheckout`).
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Entrance(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: CheckoutPanelColors.decoration(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(context.tr('cart.orderSummary'), style: _panelLabel(27, Colors.white)),
                          const SizedBox(height: 18),
                          _programCard(),
                          const SizedBox(height: 18),
                          _summary(),
                          const SizedBox(height: 18),
                          AnimatedSize(
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOutCubic,
                            alignment: Alignment.topCenter,
                            child: _free ? _coveredNotice() : _paymentSection(),
                          ),
                          const SizedBox(height: 18),
                          _actions(),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          if (_phase == _Phase.paid)
            _ResultSheet.paid(orderNumber: _orderNumber),
          if (_phase == _Phase.queued) const _ResultSheet.queued(),
          if (_phase == _Phase.cardOpened) const _ResultSheet.cardOpened(),
        ],
      ),
    );
  }

  /// `.nvSummaryProduct`: what is being bought, its kind and access year.
  Widget _programCard() {
    final Object? year = _quote?.json['academic_year'];
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: const Color(0x0DFFFFFF), borderRadius: BorderRadius.circular(18)),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 64,
              height: 64,
              child: NovaSceneImage(
                scene: widget.item.scene,
                image: widget.item.image,
                icon: widget.item.icon,
                alignment: Alignment.center,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_kindLabel(context), style: _panelLabel(13.5, CheckoutPanelColors.mute)),
                const SizedBox(height: 3),
                Text(
                  widget.item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _panelLabel(16, Colors.white),
                ),
                const SizedBox(height: 3),
                Text(
                  year is String
                      ? context.trf('checkout.accessYear', {'y': year})
                      : context.tr('checkout.accessActiveYear'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _panelText(14, CheckoutPanelColors.mute),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The server quote line by line, then the total due.
  Widget _summary() {
    final Quote? quote = _quote;
    if (quote == null) {
      return _quoteError != null ? _quoteFailure(_quoteError!) : const _SummarySkeleton();
    }
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: _quoting ? 0.55 : 1,
      child: _breakdown(quote),
    );
  }

  Widget _breakdown(Quote quote) {
    String minus(int amount) => '− ${formatDaPrice(amount)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SummaryRow(
          label: context.tr('checkout.subtotal'),
          value: formatDaPrice(quote.base),
        ),
        if (quote.overlapCredit > 0)
          _SummaryRow(
            label: context.tr('checkout.ownedCredit'),
            value: minus(quote.overlapCredit),
            discount: true,
          ),
        if (quote.referralDiscount > 0)
          _SummaryRow(
            label: context.tr('checkout.referralDiscount'),
            value: minus(quote.referralDiscount),
            discount: true,
          ),
        if (quote.promoDiscount > 0)
          _SummaryRow(
            label: context.tr('checkout.promoDiscount'),
            value: minus(quote.promoDiscount),
            discount: true,
          ),
        if (quote.pointsDiscount > 0)
          _SummaryRow(
            label: context.trf(
              'checkout.pointsApplied',
              {'n': quote.pointsUsed.toString()},
            ),
            value: minus(quote.pointsDiscount),
            discount: true,
          ),
        const SizedBox(height: 6),
        // `.nvTotal`: a dashed rule, "Total due", the amount.
        CustomPaint(
          painter: _DashedRule(),
          child: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.tr('checkout.totalDue'), style: _panelLabel(17, Colors.white)),
                      const SizedBox(height: 2),
                      Text(context.tr('checkout.vatNote'), style: _panelText(13, CheckoutPanelColors.mute)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (_quoting)
                  const Padding(
                    padding: EdgeInsetsDirectional.only(end: 10, bottom: 6),
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: CheckoutPanelColors.mute),
                    ),
                  ),
                _AnimatedPrice(quote.finalAmount, style: _panelLabel(29, Colors.white, height: 1)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _quoteFailure(String message) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Notice(message: message),
        const SizedBox(height: 6),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: _TextLink(
            icon: Icons.refresh_rounded,
            label: context.tr('common.retry'),
            onTap: _quoting ? null : _loadQuote,
          ),
        ),
      ],
    );
  }

  /// `.nvPayMethods`: the legend with the secure hint, then the two cards.
  Widget _paymentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(context.tr('checkout.method'), style: _panelLabel(17, Colors.white))),
            const Icon(Icons.lock_outline_rounded, size: 14, color: CheckoutPanelColors.mute),
            const SizedBox(width: 6),
            Text(context.tr('checkout.securePayment'), style: _panelText(13.5, CheckoutPanelColors.mute)),
          ],
        ),
        const SizedBox(height: 10),
        _MethodTile(
          selected: _method == _PayMethod.card,
          icon: Icons.credit_card_rounded,
          title: context.tr('checkout.card'),
          subtitle: context.tr('checkout.cardSub'),
          onTap: () => setState(() => _method = _PayMethod.card),
        ),
        const SizedBox(height: 10),
        _MethodTile(
          selected: _method == _PayMethod.ccp,
          icon: Icons.receipt_long_rounded,
          title: context.tr('checkout.ccp'),
          subtitle: context.tr('checkout.ccpSub'),
          onTap: () => setState(() => _method = _PayMethod.ccp),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _method == _PayMethod.ccp
              ? Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _ReceiptPicker(file: _receipt, onTap: _pickReceipt),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  /// Shown instead of the payment methods when nothing is left to pay.
  Widget _coveredNotice() => _Notice(message: context.tr('checkout.covered'), success: true);

  /// The one primary action, with the discount code beneath it.
  Widget _actions() {
    final String label = _free
        ? context.tr('checkout.confirmOrder')
        : _method == _PayMethod.ccp
            ? context.tr('checkout.sendOrder')
            : context.tr('checkout.continue');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_submitError != null) ...[
          _Notice(message: _submitError!),
          const SizedBox(height: 12),
        ],
        CheckoutButton(label: label, onTap: _canSubmit ? _submit : null),
        const SizedBox(height: 18),
        _codeSection(),
      ],
    );
  }

  /// `.nvCode`: a "Have a discount code?" row under the pay button that
  /// reveals one field for a referral or a promo code.
  Widget _codeSection() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CheckoutPanelColors.line),
      ),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TextLink(
              icon: Icons.local_offer_outlined,
              label: context.tr(_codeVisible ? 'checkout.codeLabel' : 'checkout.haveCode'),
              color: _codeVisible ? Colors.white : CheckoutPanelColors.soft,
              onTap: _appliedCode != null
                  ? null
                  : () => setState(() {
                        _codeOpen = !_codeOpen;
                        _codeError = null;
                      }),
            ),
            if (_codeVisible)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 2, 10, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(context.tr('checkout.codeHelp'), style: _panelText(14, CheckoutPanelColors.mute)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: _codeField()),
                        const SizedBox(width: 8),
                        _codeButton(),
                      ],
                    ),
                    _codeStatus(),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _codeField() {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: color, width: width),
        );
    final bool applied = _appliedCode != null;

    return TextField(
      controller: _code,
      autofocus: !applied,
      enabled: !applied,
      autocorrect: false,
      enableSuggestions: false,
      textCapitalization: TextCapitalization.characters,
      textInputAction: TextInputAction.done,
      cursorColor: Colors.white,
      onChanged: (_) => setState(() => _codeError = null),
      onSubmitted: (_) => _applyCode(),
      style: _panelText(16, applied ? CheckoutPanelColors.discount : Colors.white, weight: FontWeight.w600),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: CheckoutPanelColors.field,
        hintText: context.tr('checkout.codeHint'),
        hintStyle: _panelText(16, CheckoutPanelColors.mute),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        enabledBorder: border(_codeError != null ? const Color(0xFFFF6B6B) : CheckoutPanelColors.line),
        disabledBorder: border(CheckoutPanelColors.line),
        focusedBorder: border(NovaColors.skyStrong, 1.4),
      ),
    );
  }

  Widget _codeButton() {
    if (_appliedCode != null) {
      final String label = context.tr('checkout.removeCode');
      return PressableScale(
        onTap: _quoting ? null : _removeCode,
        semanticLabel: label,
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: CheckoutPanelColors.line),
          ),
          child: Text(label, style: _panelLabel(15, CheckoutPanelColors.soft)),
        ),
      );
    }
    final String label = context.tr('checkout.apply');
    final bool enabled = _code.text.trim().isNotEmpty && !_quoting;
    return PressableScale(
      onTap: enabled ? _applyCode : null,
      semanticLabel: label,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: enabled || _checkingCode ? 1 : 0.4,
        child: Container(
          height: 46,
          constraints: const BoxConstraints(minWidth: 84),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: _checkingCode
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF17191D)),
                )
              : Text(label, style: _panelText(14, const Color(0xFF17191D), weight: FontWeight.w600)),
        ),
      ),
    );
  }

  /// Applied code, refusal reason, or the linked referral the backend
  /// applied without a code (website wording for each).
  Widget _codeStatus() {
    final String? applied = _appliedCode;
    final Quote? quote = _quote;
    const Color ok = CheckoutPanelColors.discount;
    final Widget? line = applied != null && quote != null
        ? _StatusLine(
            icon: Icons.check_circle_outline_rounded,
            color: ok,
            text: quote.commercialDiscount == 'referral'
                ? context.tr('checkout.referralApplied')
                : context.trf(
                    'checkout.promoApplied',
                    {'code': applied.toUpperCase()},
                  ),
          )
        : _codeError != null
            ? _StatusLine(
                icon: Icons.error_outline_rounded,
                color: const Color(0xFFFF8A80),
                text: _codeError!,
              )
            : applied == null && quote?.commercialDiscount == 'referral'
                ? _StatusLine(
                    icon: Icons.check_circle_outline_rounded,
                    color: ok,
                    text: context.tr('checkout.referralAuto'),
                  )
                : null;
    if (line == null) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(top: 10), child: line);
  }
}

TextStyle _panelLabel(double size, Color color, {double height = 1.3}) => TextStyle(
      fontFamily: NovaTypography.display,
      fontFamilyFallback: NovaTypography.fallback,
      fontWeight: FontWeight.w800,
      fontSize: size,
      height: height,
      color: color,
    );

TextStyle _panelText(double size, Color color, {FontWeight weight = FontWeight.w500}) => TextStyle(
      fontFamily: NovaTypography.body,
      fontFamilyFallback: NovaTypography.fallback,
      fontWeight: weight,
      fontSize: size,
      height: 1.45,
      color: color,
    );

/// `.nvSummaryRow`: soft label, white amount; a discount in green.
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.discount = false,
  });

  final String label;
  final String value;
  final bool discount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: _panelText(15, CheckoutPanelColors.soft))),
          const SizedBox(width: 16),
          Text(
            value,
            // Amounts read left to right in Arabic too.
            textDirection: TextDirection.ltr,
            style: _panelLabel(16.5, discount ? CheckoutPanelColors.discount : Colors.white, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// Still placeholder rows while the first quote loads, so the panel
/// keeps its shape instead of jumping.
class _SummarySkeleton extends StatelessWidget {
  const _SummarySkeleton();

  @override
  Widget build(BuildContext context) {
    Widget bar(double width, double height) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: const Color(0x14FFFFFF),
            borderRadius: BorderRadius.circular(8),
          ),
        );
    Widget row() => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [bar(110, 12), const Spacer(), bar(64, 12)],
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [row(), row(), bar(double.infinity, 48)],
    );
  }
}

/// The total, easing to its new value when a code changes it.
class _AnimatedPrice extends StatelessWidget {
  const _AnimatedPrice(this.amount, {required this.style});

  final int amount;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: amount.toDouble(), end: amount.toDouble()),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      builder: (BuildContext context, double value, _) =>
          Text(
            formatDaPrice(value.round()),
            textDirection: TextDirection.ltr,
            style: style,
          ),
    );
  }
}

/// `.nvPayCard`: line border, radius 16; the selected one has the yellow
/// border on a faint yellow wash and the yellow radio.
class _MethodTile extends StatelessWidget {
  const _MethodTile({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: PressableScale(
        onTap: onTap,
        pressedScale: 0.98,
        semanticLabel: title,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? const Color(0x14FFD54A) : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? NovaColors.yellow : CheckoutPanelColors.line),
          ),
          child: Row(
            children: [
              // `.nvPayArt`: a white tile.
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
                    Text(title, style: _panelLabel(16, Colors.white)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: _panelText(14, CheckoutPanelColors.mute)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? NovaColors.yellow : Colors.transparent,
                  border: Border.all(color: selected ? NovaColors.yellow : CheckoutPanelColors.line, width: 2),
                ),
                child: selected
                    ? Container(
                        margin: const EdgeInsets.all(1),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF17191D), width: 3),
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.nvReceipt`: the CCP receipt drop zone under the payment methods —
/// what to attach until a file is chosen, then its name.
class _ReceiptPicker extends StatelessWidget {
  const _ReceiptPicker({required this.file, required this.onTap});

  final File? file;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final File? file = this.file;
    final bool attached = file != null;
    final String action = attached
        ? context.tr('checkout.receiptChange')
        : context.tr('checkout.receiptUpload');

    return PressableScale(
      onTap: onTap,
      pressedScale: 0.98,
      semanticLabel: '${context.tr('checkout.receipt')} · $action',
      child: CustomPaint(
        foregroundPainter: _DashedRRect(color: CheckoutPanelColors.line, radius: 16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(color: CheckoutPanelColors.field, shape: BoxShape.circle),
                child: Icon(
                  attached ? Icons.check_rounded : Icons.upload_file_rounded,
                  size: 18,
                  color: attached ? CheckoutPanelColors.discount : Colors.white,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr('checkout.receipt'), style: _panelLabel(16, Colors.white)),
                    const SizedBox(height: 2),
                    Text(
                      attached ? file.uri.pathSegments.last : context.tr('checkout.receiptTypes'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _panelText(14, CheckoutPanelColors.mute),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(color: NovaColors.yellow, borderRadius: BorderRadius.circular(100)),
                child: Text(action, style: _panelLabel(14, NovaColors.yellowInk, height: 1.2)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tappable line in the panel: the discount-code row (`.nvCodeReveal`)
/// and the quote retry.
class _TextLink extends StatelessWidget {
  const _TextLink({
    required this.label,
    this.icon,
    this.color = CheckoutPanelColors.soft,
    this.onTap,
  });

  final String label;
  final IconData? icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: AlignmentDirectional.centerStart,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                label,
                style: _panelLabel(15.5, color).copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: _panelText(14, color))),
      ],
    );
  }
}

/// `.nvNotice` in the dark panel: a readable failure (from
/// `apiErrorText`), or the success variant.
class _Notice extends StatelessWidget {
  const _Notice({required this.message, this.success = false});

  final String message;
  final bool success;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: success ? const Color(0xFF11261A) : const Color(0xFF2A1718),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: success ? const Color(0xFF1F5A37) : const Color(0xFF5A2B2B)),
        ),
        child: Text(
          message,
          style: _panelText(14, success ? const Color(0xFF9BE3B8) : const Color(0xFFF3B9B9)),
        ),
      ),
    );
  }
}

/// The dashed top rule of `.nvTotal`.
class _DashedRule extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = CheckoutPanelColors.line
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 7) {
      canvas.drawLine(Offset(x, 0.5), Offset(math.min(x + 4, size.width), 0.5), paint);
    }
  }

  @override
  bool shouldRepaint(_DashedRule old) => false;
}

/// A 1 px dashed rounded border (`.nvReceipt { border-style: dashed }`).
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

class _ProcessingView extends StatelessWidget {
  const _ProcessingView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _OrbitSpinner(),
          const SizedBox(height: 22),
          Text(
            context.tr('checkout.creating'),
            style: NovaTypography.textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            context.tr('checkout.creatingSub'),
            style: NovaTypography.muted(NovaTypography.textTheme.bodySmall!),
          ),
        ],
      ),
    );
  }
}

/// The order result: a scrim, a sheet that rises into place, and — on
/// a paid order — the celebration burst.
class _ResultSheet extends StatelessWidget {
  const _ResultSheet.paid({required this.orderNumber})
      : queued = false,
        card = false;

  const _ResultSheet.queued()
      : queued = true,
        card = false,
        orderNumber = '—';

  /// The card checkout opened in the browser; Chargily confirms the
  /// payment to the backend, and the order turns paid in Orders.
  const _ResultSheet.cardOpened()
      : queued = true,
        card = true,
        orderNumber = '—';

  final bool queued;
  final bool card;
  final String orderNumber;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: const Duration(milliseconds: 320),
            builder: (_, double t, _) => ColoredBox(
              color: Colors.black.withValues(alpha: 0.42 * t),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: const Duration(milliseconds: 480),
            curve: Curves.easeOutCubic,
            builder: (_, double t, Widget? child) => Opacity(
              opacity: t.clamp(0, 1),
              child: Transform.translate(
                offset: Offset(0, (1 - t) * 70),
                child: child,
              ),
            ),
            child: _sheet(context),
          ),
        ),
      ],
    );
  }

  Widget _sheet(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        24,
        queued ? 24 : 8,
        24,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: NovaColors.paperCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: const [
          BoxShadow(
            offset: Offset(0, -16),
            blurRadius: 40,
            spreadRadius: -10,
            color: Color(0x330A1128),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (queued)
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: NovaColors.accentMist,
                shape: BoxShape.circle,
              ),
              child: Icon(
                card ? Icons.open_in_browser_rounded : Icons.hourglass_top_rounded,
                size: 30,
                color: NovaColors.accentDeep,
              ),
            )
          else
            // The burst paints past its slot, so the sheet reserves
            // less height than the canvas it draws on.
            SizedBox(
              height: 128,
              child: OverflowBox(
                maxWidth: 220,
                maxHeight: 220,
                child: const SuccessBurst(size: 96),
              ),
            ),
          const SizedBox(height: 14),
          Text(
            card
                ? context.tr('checkout.cardOpened')
                : queued
                    ? context.tr('checkout.orderSent')
                    : context.tr('checkout.orderPaid'),
            textAlign: TextAlign.center,
            style: NovaTypography.textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          Text(
            card
                ? context.tr('checkout.cardMsg')
                : queued
                    ? context.tr('checkout.queuedMsg')
                    : context.trf('checkout.paidMsg', {'n': orderNumber}),
            textAlign: TextAlign.center,
            style: NovaTypography.muted(NovaTypography.textTheme.bodySmall!),
          ),
          const SizedBox(height: 20),
          // The website's success actions: "View Orders" with its chip,
          // "Continue shopping" as the ghost.
          Row(
            children: [
              Expanded(
                child: NovaButton(
                  label: context.tr('checkout.keepExploring'),
                  variant: NovaButtonVariant.ghost,
                  expand: true,
                  // Back to the app's root screen, whether checkout came
                  // from a course page or straight from the Cart tab.
                  onTap: () => Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: NovaButton(
                  label: context.tr('checkout.viewOrders'),
                  expand: true,
                  onTap: () {
                    final NavigatorState navigator = Navigator.of(context);
                    navigator.popUntil((Route<dynamic> route) => route.isFirst);
                    navigator.push(
                      MaterialPageRoute<void>(builder: (_) => const OrdersScreen()),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A sweeping arc with a bright head, spun by one controller — the
/// wait state while the order is created.
class _OrbitSpinner extends StatefulWidget {
  const _OrbitSpinner();

  @override
  State<_OrbitSpinner> createState() => _OrbitSpinnerState();
}

class _OrbitSpinnerState extends State<_OrbitSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: 56,
        height: 56,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (_, _) => CustomPaint(
            painter: _OrbitPainter(_controller.value),
          ),
        ),
      ),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect bounds = Offset.zero & size;
    final Offset center = bounds.center;
    final double radius = size.shortestSide / 2 - 4;
    final double angle = t * 2 * 3.14159265;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..color = NovaColors.accent.withValues(alpha: 0.16),
    );

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      angle,
      2.1,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: angle,
          endAngle: angle + 2.1,
          colors: [NovaColors.skyStrong, NovaColors.accent],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(_OrbitPainter old) => old.t != t;
}
