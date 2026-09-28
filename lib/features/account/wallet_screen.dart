import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/i18n/labels.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_dimens.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/widgets/hue_card.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/nova_decor.dart';
import '../../core/widgets/nova_toast.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../data/models.dart';
import '../../core/state/app_state.dart';

/// Wallet & rewards: the points balance (never convertible to cash),
/// the immutable ledger and the Student's referral code.
class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState app = AppScope.of(context);
    final List<PointsEntry> ledger = app.account.ledger;

    return PageScaffold(
      title: context.tr('wallet.title'),
      kicker: '${app.account.pointsBalance} ${context.tr('wallet.available')}',
      watermark: Icons.stars_rounded,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        children: [
          const _BalanceCard(),
          const SizedBox(height: 22),
          Text(
            context.tr('wallet.ledger'),
            style: NovaTypography.textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(
            context.tr('wallet.ledgerNote'),
            style: NovaTypography.muted(NovaTypography.textTheme.bodySmall!),
          ),
          const SizedBox(height: 14),
          if (ledger.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                context.tr('wallet.empty'),
                style: NovaTypography.muted(NovaTypography.textTheme.bodyMedium!),
              ),
            ),
          ...stagger(
            ledger
                .map(
                  (PointsEntry entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _LedgerRow(entry: entry),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 14),
          const _ReferralCard(),
          const SizedBox(height: 16),
          PressableScale(
            onTap: () => Navigator.of(context).maybePop(),
            semanticLabel: context.tr('wallet.earn'),
            child: Container(
              height: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: NovaColors.ink950,
                borderRadius: BorderRadius.circular(100),
                boxShadow: NovaDimens.shadowSoft,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.auto_awesome_rounded,
                    size: 18,
                    color: NovaColors.gold,
                  ),
                  const SizedBox(width: 9),
                  Text(
                    context.tr('wallet.earn'),
                    style: NovaTypography.textTheme.labelLarge!.copyWith(
                      color: NovaColors.textOnDark,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The balance: ink card, gold number, and the rule that points are
/// never cash spelled out underneath.
class _BalanceCard extends StatelessWidget {
  const _BalanceCard();

  @override
  Widget build(BuildContext context) {
    return HueCard(
      hue: NovaHue.butter,
      style: HueCardStyle.dark,
      decorSeed: 4,
      radius: NovaDimens.radiusHero,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconTile(
                icon: Icons.stars_rounded,
                hue: NovaHue.butter,
                filled: true,
                size: 42,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.tr('wallet.available').toUpperCase(),
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700,
                    fontSize: 10.5,
                    letterSpacing: 1.8,
                    color: NovaColors.textMutedOnDark,
                  ),
                ),
              ),
              const Sparkle(size: 16, color: NovaColors.gold),
            ],
          ),
          const SizedBox(height: 16),
          CountUpText(
            AppScope.of(context).account.pointsBalance,
            style: const TextStyle(
              fontFamily: 'InterDisplay',
              fontWeight: FontWeight.w700,
              fontSize: 48,
              height: 1,
              letterSpacing: -1.6,
              color: NovaColors.gold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            context.tr('wallet.note'),
            style: const TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w500,
              fontSize: 11.5,
              height: 1.45,
              color: NovaColors.textMutedOnDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.entry});

  final PointsEntry entry;

  @override
  Widget build(BuildContext context) {
    final bool earned = entry.delta >= 0;
    final NovaHue hue = earned ? NovaHue.mint : NovaHue.rose;

    return NovaCard(
      child: Row(
        children: [
          IconTile(
            icon: earned
                ? Icons.arrow_downward_rounded
                : Icons.arrow_upward_rounded,
            hue: hue,
            size: 40,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pointsEntryText(context, entry), style: NovaTypography.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  entry.date,
                  style: NovaTypography.muted(
                    NovaTypography.textTheme.bodySmall!,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${earned ? '+' : ''}${entry.delta}',
                style: NovaTypography.textTheme.titleSmall!.copyWith(
                  color: hue.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                context.trf('wallet.balanceShort', {'n': entry.balance.toString()}),
                style: NovaTypography.muted(
                  NovaTypography.textTheme.labelSmall!,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReferralCard extends StatelessWidget {
  const _ReferralCard();

  @override
  Widget build(BuildContext context) {
    final AppState app = AppScope.of(context);
    final String code = app.account.referral['own_code'] is String
        ? app.account.referral['own_code'] as String
        : app.profile?.referralCode ?? '';
    return HueCard(
      hue: NovaHue.lilac,
      decorSeed: 6,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconTile(
                icon: Icons.card_giftcard_rounded,
                hue: NovaHue.lilac,
                filled: true,
                size: 40,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('wallet.refer'),
                      style: NovaTypography.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.tr('wallet.referDesc'),
                      style: NovaTypography.textTheme.bodySmall!.copyWith(
                        color: NovaHue.lilac.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.fromLTRB(18, 10, 10, 10),
            decoration: BoxDecoration(
              color: NovaColors.paperCard,
              borderRadius: BorderRadius.circular(100),
              border: Border.all(
                color: NovaHue.lilac.solid.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    code,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      letterSpacing: 2.4,
                      color: NovaHue.lilac.onSurface,
                    ),
                  ),
                ),
                PressableScale(
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: code));
                    if (context.mounted) {
                      novaToast(
                        context,
                        context.tr('wallet.copied'),
                        icon: Icons.content_copy_rounded,
                      );
                    }
                  },
                  semanticLabel: 'Copy referral code',
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
                      context.tr('wallet.copy'),
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                        color: NovaColors.textOnDark,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            context.tr('wallet.referMeta'),
            style: NovaTypography.muted(NovaTypography.textTheme.bodySmall!),
          ),
        ],
      ),
    );
  }
}
