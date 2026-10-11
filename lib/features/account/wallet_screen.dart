import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_dimens.dart';
import '../../core/widgets/hero_style.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/nova_page_header.dart';
import '../../core/widgets/nova_toast.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../data/json.dart';
import '../../data/models.dart';
import '../catalog/units_catalog_screen.dart';
import 'dashboard_card.dart';

/// The website's `/account/wallet` (`WalletView`, `profile.tsx`): the blue
/// wallet header with the balance on a white sticker (points are never
/// cash), the points history, and the referral code with its counts.
class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState app = AppScope.of(context);
    final List<PointsEntry> ledger = app.account.ledger;
    final List<Widget> sections = <Widget>[
      const _WalletHero(),
      DashboardCard(
        kicker: context.tr('dash.immutable_ledger'),
        title: context.tr('dash.points_history'),
        child: ledger.isEmpty
            ? _SoftNote(context.tr('dash.no_point_tx'))
            : Column(children: [for (final PointsEntry entry in ledger) _LedgerRow(entry: entry)]),
      ),
      const _ReferralCard(),
    ];
    return Scaffold(
      backgroundColor: NovaColors.paper,
      body: ListView(
        padding: EdgeInsets.only(bottom: 40 + MediaQuery.paddingOf(context).bottom),
        children: [
          NovaPageHeader(
            kicker: context.tr('dash.wallet_eyebrow'),
            title: context.tr('wallet.title'),
            lead: context.tr('dash.wallet_desc'),
          ),
          const SizedBox(height: 20),
          for (int i = 0; i < sections.length; i++)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
              child: Entrance(delay: Duration(milliseconds: 60 * i), child: sections[i]),
            ),
        ],
      ),
    );
  }
}

/// `.walletHero`: the band's blue (deep blue in dark mode), the yellow
/// "Browse Units" call, and the balance on a white card turned 3°.
class _WalletHero extends StatelessWidget {
  const _WalletHero();

  @override
  Widget build(BuildContext context) {
    final int balance = AppScope.of(context).account.pointsBalance;
    return HeroBand(
      doodles: false,
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('dash.points_balance'), style: heroLabel(15, color: NovaColors.yellow)),
          const SizedBox(height: 8),
          Text(context.tr('dash.wallet_ready'), style: heroLabel(27, color: Colors.white, height: 1.35)),
          const SizedBox(height: 6),
          Text(
            context.tr('dash.wallet_points_notice'),
            style: heroText(15.5, color: Colors.white.withValues(alpha: 0.86)),
          ),
          const SizedBox(height: 18),
          NovaButton(
            label: context.tr('dash.browse_courses'),
            variant: NovaButtonVariant.yellow,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const UnitsCatalogScreen()),
            ),
          ),
          const SizedBox(height: 26),
          // `.walletBalanceOrb`: always white, the number in the light blue.
          Transform.rotate(
            angle: 3 * math.pi / 180,
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 146),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(NovaDimens.radiusTile),
                boxShadow: NovaDimens.shadowSticker,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 35,
                    height: 35,
                    decoration: BoxDecoration(color: const Color(0x294FACF0), borderRadius: BorderRadius.circular(11)),
                    child: const Icon(Icons.account_balance_wallet_outlined, size: 17, color: NovaColors.blue),
                  ),
                  const SizedBox(height: 8),
                  CountUpText(balance, style: heroLabel(22, color: NovaColors.blue, height: 1.2)),
                  const SizedBox(height: 6),
                  Text(context.tr('dash.points_available'), style: heroText(14, color: const Color(0xFF46506A))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `.pointsLedgerRow`: the credit / debit chip, the movement and its date,
/// and the balance after it.
class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.entry});

  final PointsEntry entry;

  @override
  Widget build(BuildContext context) {
    final bool credit = entry.delta >= 0;
    final String typeKey = 'points.type_${entry.type}';
    final String title = K.containsKey(typeKey) ? context.tr(typeKey) : entry.label;
    final String detail = entry.hasReason ? entry.label : context.tr('dash.commerce_transaction');
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: NovaColors.borderOnLight))),
      child: Row(
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 46),
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: credit ? NovaColors.liveBg : NovaColors.dangerBg,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              '${entry.delta > 0 ? '+' : ''}${entry.delta}',
              textDirection: TextDirection.ltr,
              style: heroLabel(14, color: credit ? NovaColors.onlineGreen : NovaColors.heartRed, height: 1.2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: heroLabel(15)),
                const SizedBox(height: 3),
                Text('$detail · ${entry.date}', style: heroText(13.5, color: NovaColors.textMuted, height: 1.4)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text('${entry.balance}', textDirection: TextDirection.ltr, style: heroText(13)),
        ],
      ),
    );
  }
}

/// `.referralCard`: the code on a dashed blue panel, the two counts, and
/// who referred the Student.
class _ReferralCard extends StatelessWidget {
  const _ReferralCard();

  @override
  Widget build(BuildContext context) {
    final AppState app = AppScope.of(context);
    final Json referral = app.account.referral;
    final String code = referral.str('own_code', app.profile?.referralCode ?? '');
    final Json? relationship = referral.obj('relationship');
    return DashboardCard(
      kicker: context.tr('dash.referral_activity'),
      title: context.tr('dash.share_and_reward'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CustomPaint(
            foregroundPainter: _DashedBorder(color: NovaColors.blueLine, radius: 18),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: NovaColors.accentMist, borderRadius: BorderRadius.circular(18)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.tr('dash.referral_code'), style: heroLabel(14, color: NovaColors.accent)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            code.isEmpty ? '—' : code,
                            textDirection: TextDirection.ltr,
                            style: heroLabel(21, height: 1.2).copyWith(letterSpacing: 0.8),
                          ),
                        ),
                      ),
                      if (code.isNotEmpty) _CopyButton(code: code),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(context.tr('dash.referral_reward_notice'), style: heroText(14)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _Stat(value: referral.integer('referred_students'), label: context.tr('dash.referred_students'))),
              const SizedBox(width: 10),
              Expanded(child: _Stat(value: referral.integer('rewarded_referrals'), label: context.tr('dash.rewards_credited'))),
            ],
          ),
          const SizedBox(height: 12),
          if (relationship == null)
            _SoftNote(context.tr('dash.no_referral_relationship'))
          else
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: NovaColors.paperRaised, borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.tr('dash.referred_by'), style: heroText(13.5, color: NovaColors.textMuted)),
                  const SizedBox(height: 2),
                  Text(relationship.str('referrer_name'), style: heroLabel(15)),
                  const SizedBox(height: 2),
                  Text(
                    '${context.tr('dash.referral_status')}: ${_status(context, relationship.str('status'))}',
                    style: heroText(13.5, color: NovaColors.textMuted),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _status(BuildContext context, String status) {
    final String key = 'dash.referral_status_$status';
    return K.containsKey(key) ? context.tr(key) : status.replaceAll('_', ' ');
  }
}

/// Copies the code (the app cannot select it like the page can).
class _CopyButton extends StatelessWidget {
  const _CopyButton({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: code));
        if (context.mounted) novaToast(context, context.tr('wallet.copied'), icon: Icons.content_copy_rounded);
      },
      pressedScale: 0.94,
      semanticLabel: context.tr('wallet.copy'),
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(color: NovaColors.accent, borderRadius: BorderRadius.circular(12)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.content_copy_rounded, size: 15, color: Colors.white),
            const SizedBox(width: 6),
            Text(context.tr('wallet.copy'), style: heroLabel(14, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

/// `.referralStats > div`: surface-2, radius 16, the count in blue.
class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: NovaColors.paperRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NovaColors.borderOnLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$value', style: heroLabel(19, color: NovaColors.accent, height: 1.2)),
          const SizedBox(height: 3),
          Text(label, style: heroText(14, height: 1.35)),
        ],
      ),
    );
  }
}

/// `.walletEmpty` / `.referralEmpty`: surface-2, radius 14, ink-2 text.
class _SoftNote extends StatelessWidget {
  const _SoftNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: NovaColors.paperRaised, borderRadius: BorderRadius.circular(14)),
      child: Text(text, style: heroText(15)),
    );
  }
}

/// A 2 px dashed rounded border (`border: 2px dashed`).
class _DashedBorder extends CustomPainter {
  _DashedBorder({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final Path outline = Path()..addRRect(RRect.fromRectAndRadius((Offset.zero & size).deflate(1), Radius.circular(radius)));
    for (final metric in outline.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 10) {
        canvas.drawPath(metric.extractPath(d, math.min(d + 6, metric.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color || old.radius != radius;
}
