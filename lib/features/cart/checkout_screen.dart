import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/utils/format_price.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/theme/nova_dimens.dart';
import '../../core/widgets/gradient_pill_button.dart';
import '../../core/widgets/hue_card.dart';
import '../../core/widgets/nova_page_header.dart';
import '../../core/widgets/nova_scene_image.dart';
import '../../core/widgets/success_burst.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../data/commerce_store.dart';
import '../account/orders_screen.dart';
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
                  watermark: Icons.lock_rounded,
                ),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: NovaDimens.screenPadding,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: stagger(<Widget>[
                      _programCard(),
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: _summaryCard(),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 22),
                        child: AnimatedSize(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topCenter,
                          child: _free ? _coveredCard() : _paymentSection(),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: _actions(),
                      ),
                    ]),
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

  /// What is being bought: cover, kind, title, access year and price.
  Widget _programCard() {
    final Object? year = _quote?.json['academic_year'];
    return _Card(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: 60,
              height: 60,
              child: NovaSceneImage(
                scene: widget.item.scene,
                image: widget.item.image,
                icon: widget.item.icon,
                alignment: Alignment.center,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: NovaHue.sky.surfaceStrong,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    _kindLabel(context),
                    style: NovaTypography.textTheme.labelSmall!.copyWith(
                      color: NovaHue.sky.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  widget.item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: NovaTypography.textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  year is String
                      ? context.trf('checkout.accessYear', {'y': year})
                      : context.tr('checkout.accessActiveYear'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: NovaTypography.muted(
                    NovaTypography.textTheme.labelSmall!,
                  ).copyWith(fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            formatDaPrice(_quote?.base ?? widget.item.price),
            // Amounts read left to right in Arabic too.
            textDirection: TextDirection.ltr,
            style: NovaTypography.textTheme.titleMedium!.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  /// The server quote line by line, ending on the total due.
  Widget _summaryCard() {
    final Quote? quote = _quote;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.tr('checkout.orderSummary'),
                  style: NovaTypography.textTheme.titleMedium,
                ),
              ),
              if (_quoting && quote != null)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (quote != null)
            AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _quoting ? 0.55 : 1,
              child: _breakdown(quote),
            )
          else if (_quoteError != null)
            _quoteFailure(_quoteError!)
          else
            const _SummarySkeleton(),
        ],
      ),
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
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: NovaColors.accentMist,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('checkout.totalDue'),
                      style: NovaTypography.textTheme.titleSmall!.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.tr('checkout.vatNote'),
                      style: NovaTypography.muted(
                        NovaTypography.textTheme.labelSmall!,
                      ).copyWith(fontWeight: FontWeight.w500, height: 1.3),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _AnimatedPrice(
                quote.finalAmount,
                style: NovaTypography.textTheme.headlineMedium!.copyWith(
                  color: NovaHue.sky.onSurface,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _quoteFailure(String message) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ErrorBanner(message: message),
        const SizedBox(height: 10),
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

  Widget _paymentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                context.tr('checkout.method'),
                style: NovaTypography.textTheme.titleMedium,
              ),
            ),
            Icon(Icons.lock_rounded, size: 13, color: NovaColors.textMuted),
            const SizedBox(width: 5),
            Text(
              context.tr('checkout.securePayment'),
              style: NovaTypography.muted(NovaTypography.textTheme.labelSmall!),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _MethodTile(
          selected: _method == _PayMethod.card,
          icon: Icons.credit_card_rounded,
          hue: NovaHue.sky,
          title: context.tr('checkout.card'),
          subtitle: context.tr('checkout.cardSub'),
          onTap: () => setState(() => _method = _PayMethod.card),
        ),
        const SizedBox(height: 10),
        _MethodTile(
          selected: _method == _PayMethod.ccp,
          icon: Icons.receipt_long_rounded,
          hue: NovaHue.butter,
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
  Widget _coveredCard() {
    return HueCard(
      hue: NovaHue.mint,
      padding: const EdgeInsets.all(14),
      radius: NovaDimens.radiusTile,
      child: Row(
        children: [
          const IconTile(
            icon: Icons.verified_rounded,
            hue: NovaHue.mint,
            size: 38,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              context.tr('checkout.covered'),
              style: NovaTypography.textTheme.bodySmall!.copyWith(
                color: NovaHue.mint.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The one primary action, with the discount code link beneath it.
  Widget _actions() {
    final String label = _free
        ? context.tr('checkout.confirmOrder')
        : _method == _PayMethod.ccp
            ? context.tr('checkout.sendOrder')
            : context.tr('checkout.continue');
    final bool enabled = _canSubmit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_submitError != null) ...[
          _ErrorBanner(message: _submitError!),
          const SizedBox(height: 12),
        ],
        AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: enabled ? 1 : 0.5,
          child: GradientPillButton(
            icon: Icons.lock_rounded,
            label: label,
            width: double.infinity,
            semanticLabel: label,
            onTap: enabled ? _submit : null,
          ),
        ),
        const SizedBox(height: 6),
        _codeSection(),
      ],
    );
  }

  /// Mirrors the website: a "Have a discount code?" link under the pay
  /// button that reveals one field for a referral or a promo code.
  Widget _codeSection() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: !_codeVisible
          ? Align(
              alignment: AlignmentDirectional.centerEnd,
              child: _TextLink(
                icon: Icons.local_offer_rounded,
                label: context.tr('checkout.haveCode'),
                dashed: true,
                onTap: () => setState(() => _codeOpen = true),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: _TextLink(
                    label: context.tr('checkout.codeLabel'),
                    trailingIcon: _appliedCode == null
                        ? Icons.expand_less_rounded
                        : null,
                    onTap: _appliedCode == null
                        ? () => setState(() {
                              _codeOpen = false;
                              _codeError = null;
                            })
                        : null,
                  ),
                ),
                Text(
                  context.tr('checkout.codeHelp'),
                  style: NovaTypography.muted(
                    NovaTypography.textTheme.labelSmall!,
                  ).copyWith(fontWeight: FontWeight.w500),
                ),
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
    );
  }

  Widget _codeField() {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
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
      onChanged: (_) => setState(() => _codeError = null),
      onSubmitted: (_) => _applyCode(),
      style: NovaTypography.textTheme.bodyMedium!.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
        color: applied ? NovaHue.mint.onSurface : NovaColors.textStrong,
      ),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: NovaColors.paperCard,
        hintText: context.tr('checkout.codeHint'),
        hintStyle: NovaTypography.muted(NovaTypography.textTheme.bodyMedium!),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: border(
          _codeError != null ? NovaColors.heartRed : NovaColors.borderOnLight,
        ),
        disabledBorder: border(NovaHue.mint.solid.withValues(alpha: 0.5)),
        focusedBorder: border(NovaColors.accent, 1.4),
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
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: NovaColors.paperCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: NovaColors.borderOnLight),
          ),
          child: Text(label, style: NovaTypography.textTheme.labelLarge),
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
        opacity: enabled || _checkingCode ? 1 : 0.5,
        child: Container(
          height: 48,
          constraints: const BoxConstraints(minWidth: 84),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: NovaColors.accent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: _checkingCode
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  label,
                  style: NovaTypography.textTheme.labelLarge!.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
    );
  }

  /// Applied code, refusal reason, or the linked referral the backend
  /// applied without a code (website wording for each).
  Widget _codeStatus() {
    final String? applied = _appliedCode;
    final Quote? quote = _quote;
    final Color ok = NovaHue.mint.onSurface;
    final Widget? line = applied != null && quote != null
        ? _StatusLine(
            icon: Icons.check_circle_rounded,
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
                color: NovaColors.heartRed,
                text: _codeError!,
              )
            : applied == null && quote?.commercialDiscount == 'referral'
                ? _StatusLine(
                    icon: Icons.check_circle_rounded,
                    color: ok,
                    text: context.tr('checkout.referralAuto'),
                  )
                : null;
    if (line == null) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(top: 10), child: line);
  }
}

/// Paper card with the hairline border and soft lift of the app's
/// list cards.
class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: NovaColors.paperCard,
        borderRadius: BorderRadius.circular(NovaDimens.radiusTile),
        border: Border.all(color: NovaColors.borderOnLight),
        boxShadow: NovaDimens.shadowSoft,
      ),
      child: child,
    );
  }
}

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
          Expanded(
            child: Text(
              label,
              style: NovaTypography.textTheme.bodySmall,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            textDirection: TextDirection.ltr,
            style: NovaTypography.textTheme.bodySmall!.copyWith(
              fontWeight: FontWeight.w700,
              color: discount ? NovaHue.mint.onSurface : NovaColors.textStrong,
            ),
          ),
        ],
      ),
    );
  }
}

/// Still placeholder rows while the first quote loads, so the card
/// keeps its shape instead of jumping.
class _SummarySkeleton extends StatelessWidget {
  const _SummarySkeleton();

  @override
  Widget build(BuildContext context) {
    Widget bar(double width, double height) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: NovaColors.subtleFill,
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
      children: [row(), row(), bar(double.infinity, 58)],
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

class _MethodTile extends StatelessWidget {
  const _MethodTile({
    required this.selected,
    required this.icon,
    required this.hue,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final NovaHue hue;
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
            color: selected ? NovaColors.accentMist : NovaColors.paperCard,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? NovaColors.accent : NovaColors.borderOnLight,
              width: selected ? 1.4 : 1,
            ),
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
                      style: NovaTypography.textTheme.bodySmall,
                    ),
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
                  color: selected ? NovaColors.accent : Colors.transparent,
                  border: Border.all(
                    color: selected ? NovaColors.accent : NovaColors.textMuted,
                    width: 1.6,
                  ),
                ),
                child: selected
                    ? const Icon(Icons.check_rounded,
                        size: 14, color: Colors.white)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The CCP receipt drop zone under the payment methods: what to attach
/// until a file is chosen, then its name.
class _ReceiptPicker extends StatelessWidget {
  const _ReceiptPicker({required this.file, required this.onTap});

  final File? file;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final File? file = this.file;
    final bool attached = file != null;
    final NovaHue hue = attached ? NovaHue.mint : NovaHue.sky;
    final String action = attached
        ? context.tr('checkout.receiptChange')
        : context.tr('checkout.receiptUpload');

    return PressableScale(
      onTap: onTap,
      pressedScale: 0.98,
      semanticLabel: '${context.tr('checkout.receipt')} · $action',
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 10, 10),
        decoration: BoxDecoration(
          color: hue.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: hue.solid.withValues(alpha: 0.45), width: 1.2),
        ),
        child: Row(
          children: [
            IconTile(
              icon: attached
                  ? Icons.check_circle_rounded
                  : Icons.upload_file_rounded,
              hue: hue,
              size: 36,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('checkout.receipt'),
                    style: NovaTypography.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    attached
                        ? file.uri.pathSegments.last
                        : context.tr('checkout.receiptTypes'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NovaTypography.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: hue.surfaceStrong,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                action,
                style: NovaTypography.textTheme.labelSmall!.copyWith(
                  color: hue.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A tappable accent text line: the discount-code link, its collapse
/// toggle and the quote retry.
class _TextLink extends StatelessWidget {
  const _TextLink({
    required this.label,
    this.icon,
    this.trailingIcon,
    this.dashed = false,
    this.onTap,
  });

  final String label;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool dashed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = NovaHue.sky.onSurface;
    return PressableScale(
      onTap: onTap,
      semanticLabel: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: NovaTypography.textTheme.labelLarge!.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
                decoration: dashed ? TextDecoration.underline : null,
                decorationStyle: TextDecorationStyle.dashed,
                decorationColor: color,
              ),
            ),
            if (trailingIcon != null) ...[
              const SizedBox(width: 2),
              Icon(trailingIcon, size: 18, color: color),
            ],
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
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: NovaTypography.textTheme.bodySmall!.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// A readable failure (from `apiErrorText`) on a rose wash.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: NovaHue.rose.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: NovaHue.rose.solid.withValues(alpha: 0.3)),
        ),
        child: _StatusLine(
          icon: Icons.error_outline_rounded,
          color: NovaHue.rose.onSurface,
          text: message,
        ),
      ),
    );
  }
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
            Row(
              children: [
                Expanded(
                  child: PressableScale(
                    // Back to the app's root screen, whether checkout came
                    // from a course page or straight from the Cart tab.
                    onTap: () => Navigator.of(context)
                        .popUntil((Route<dynamic> route) => route.isFirst),
                    semanticLabel: 'Continue shopping',
                    child: Container(
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(100),
                        border: Border.all(color: NovaColors.borderOnLight),
                        color: NovaColors.paperCard,
                      ),
                      child: Text(
                        context.tr('checkout.keepExploring'),
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: NovaColors.textStrong,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PressableScale(
                    onTap: () {
                      final NavigatorState navigator = Navigator.of(context);
                      navigator.popUntil((Route<dynamic> route) => route.isFirst);
                      navigator.push(
                        MaterialPageRoute<void>(
                          builder: (_) => const OrdersScreen(),
                        ),
                      );
                    },
                    semanticLabel: context.tr('checkout.viewOrders'),
                    child: Container(
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(100),
                        color: NovaColors.ink950,
                      ),
                      child: Text(
                        context.tr('checkout.viewOrders'),
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: NovaColors.textOnDark,
                        ),
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
          colors: const [NovaColors.accentLight, NovaColors.accentDeep],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(_OrbitPainter old) => old.t != t;
}
