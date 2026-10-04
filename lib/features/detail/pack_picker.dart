import 'package:flutter/material.dart';

import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/utils/format_price.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../data/models.dart';

/// D-091: the Packs containing a Unit sold through Packs only, cheapest
/// first; the one picked is added to the cart ([buy] false) or bought.
Future<CoursePack?> showPackPicker(
  BuildContext context, {
  required List<CoursePack> packs,
  required bool buy,
}) {
  return showModalBottomSheet<CoursePack>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (BuildContext context) => _PackPicker(packs: packs, buy: buy),
  );
}

class _PackPicker extends StatelessWidget {
  const _PackPicker({required this.packs, required this.buy});

  final List<CoursePack> packs;
  final bool buy;

  @override
  Widget build(BuildContext context) {
    final AppState app = AppScope.of(context);
    return Container(
      margin: const EdgeInsets.all(10),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 16 + MediaQuery.paddingOf(context).bottom),
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
      decoration: BoxDecoration(
        color: NovaColors.paperCard,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.tr('detail.choosePackTitle'), style: NovaTypography.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            context.tr('detail.choosePackHint'),
            style: NovaTypography.muted(NovaTypography.textTheme.bodySmall!),
          ),
          const SizedBox(height: 14),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: packs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (BuildContext context, int index) {
                final CoursePack pack = packs[index];
                return _PackOption(
                  pack: pack,
                  buy: buy,
                  inCart: app.contains('offer:${pack.id}'),
                  onTap: () => Navigator.of(context).pop(pack),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: PressableScale(
              onTap: () => Navigator.of(context).pop(),
              semanticLabel: context.tr('menu.close'),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  context.tr('menu.close'),
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: NovaColors.textMuted,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PackOption extends StatelessWidget {
  const _PackOption({
    required this.pack,
    required this.buy,
    required this.inCart,
    required this.onTap,
  });

  final CoursePack pack;
  final bool buy;
  final bool inCart;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String typeKey = 'offer.type_${pack.type}';
    final String type = K.containsKey(typeKey) ? context.tr(typeKey) : pack.type;
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.98,
      semanticLabel: pack.title,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: NovaColors.subtleFill,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: inCart ? NovaColors.accent : NovaColors.borderOnLight),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pack.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: NovaTypography.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    inCart ? '$type · ${context.tr('detail.added')}' : type,
                    style: NovaTypography.muted(NovaTypography.textTheme.bodySmall!),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatDaPrice(pack.price), style: NovaTypography.textTheme.titleSmall),
                const SizedBox(height: 3),
                Text(
                  context.tr(buy ? 'detail.buyNow' : 'detail.addToCart'),
                  style: NovaTypography.textTheme.labelMedium!.copyWith(color: NovaColors.accentDeep),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
