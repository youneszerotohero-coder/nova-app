import 'package:flutter/material.dart';

import '../../../core/theme/nova_colors.dart';
import '../../../core/theme/nova_dimens.dart';
import '../../../core/theme/nova_typography.dart';
import '../../../core/widgets/pressable_scale.dart';

/// Rounded search pill with a trailing charcoal filter button, as in
/// the visual direction. A clear button shows while there is text, and
/// tapping anywhere else closes the keyboard.
class NovaSearchField extends StatelessWidget {
  const NovaSearchField({
    super.key,
    required this.hint,
    required this.controller,
    this.focusNode,
    this.onFilterTap,
    this.onChanged,
    this.onSubmitted,
    this.filtersActive = false,
    this.margin = const EdgeInsets.symmetric(horizontal: 20),
  });

  final String hint;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final VoidCallback? onFilterTap;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Shows an orange dot on the filter button while the applied
  /// course filters differ from their defaults.
  final bool filtersActive;

  /// Zero it when the field already sits inside a padded block.
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Container(
        height: 58,
        padding: const EdgeInsetsDirectional.fromSTEB(18, 0, 6, 0),
        decoration: BoxDecoration(
          color: NovaColors.paperCard,
          borderRadius: BorderRadius.circular(NovaDimens.radiusChip),
          border: Border.all(color: NovaColors.borderOnLight),
          boxShadow: NovaDimens.shadowCard,
        ),
        child: Row(
          children: [
            Icon(
              Icons.search_rounded,
              size: 22,
              color: NovaColors.textMuted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: onChanged,
                onSubmitted: onSubmitted,
                // Mobile keeps the keyboard up on outside taps by default.
                onTapOutside: (_) => focusNode?.unfocus(),
                textInputAction: TextInputAction.search,
                style: NovaTypography.textTheme.bodyLarge,
                cursorColor: NovaColors.textStrong,
                decoration: InputDecoration.collapsed(
                  hintText: hint,
                  hintStyle: NovaTypography.muted(
                    NovaTypography.textTheme.bodyLarge!,
                  ),
                ),
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (BuildContext context, TextEditingValue value, _) =>
                  value.text.isEmpty
                      ? const SizedBox.shrink()
                      : PressableScale(
                          onTap: () {
                            controller.clear();
                            onChanged?.call('');
                          },
                          semanticLabel: 'Clear search',
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Icon(
                              Icons.close_rounded,
                              size: 20,
                              color: NovaColors.textMuted,
                            ),
                          ),
                        ),
            ),
            PressableScale(
              onTap: onFilterTap,
              pressedScale: 0.92,
              semanticLabel: 'Filters',
              child: Container(
                width: 48,
                height: 48,
                // The filter button stays black across the blue
                // direction, per the owner's callout on the mock.
                decoration: const BoxDecoration(
                  color: NovaColors.nearBlack,
                  shape: BoxShape.circle,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(
                      Icons.tune_rounded,
                      size: 20,
                      color: NovaColors.textOnDark,
                    ),
                    if (filtersActive)
                      Positioned(
                        top: 7,
                        right: 7,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: NovaColors.badgeOrange,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: NovaColors.nearBlack,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
