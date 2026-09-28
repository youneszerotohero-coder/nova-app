import 'package:flutter/material.dart';

import '../theme/nova_colors.dart';
import '../theme/nova_typography.dart';
import 'pressable_scale.dart';

/// Section title with the optional "See all" affordance.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Shrinks before the action does: long titles or large system
          // fonts must not overflow the row.
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NovaTypography.textTheme.headlineSmall,
            ),
          ),
          if (actionLabel != null)
            PressableScale(
              onTap: onAction,
              semanticLabel: actionLabel,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      actionLabel!,
                      style: NovaTypography.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: NovaColors.accent,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 17,
                      color: NovaColors.accent,
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
