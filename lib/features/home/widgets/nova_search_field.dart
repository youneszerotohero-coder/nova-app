import 'package:flutter/material.dart';

import '../../../core/i18n/nova_strings.dart';
import '../../../core/theme/nova_colors.dart';
import '../../../core/theme/nova_dimens.dart';
import '../../../core/theme/nova_typography.dart';
import '../../../core/widgets/pressable_scale.dart';

/// The catalogue search field (`.nvSearch`, pages.css): 56 high, radius 17,
/// surface with a line border and the card shadow; focused, a blue border
/// and a blue-soft ring. A clear button shows while there is text, and
/// tapping anywhere else closes the keyboard.
class NovaSearchField extends StatefulWidget {
  const NovaSearchField({
    super.key,
    required this.hint,
    required this.controller,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
  });

  final String hint;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<NovaSearchField> createState() => _NovaSearchFieldState();
}

class _NovaSearchFieldState extends State<NovaSearchField> {
  FocusNode? _ownFocus;

  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _focus.addListener(_refresh);
  }

  @override
  void didUpdateWidget(NovaSearchField old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _ownFocus)?.removeListener(_refresh);
      _focus.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_refresh);
    _ownFocus?.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final bool focused = _focus.hasFocus;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: 56,
      padding: const EdgeInsetsDirectional.fromSTEB(18, 0, 8, 0),
      decoration: BoxDecoration(
        color: NovaColors.paperCard,
        borderRadius: BorderRadius.circular(NovaDimens.radiusControl),
        border: Border.all(color: focused ? NovaColors.accent : NovaColors.borderOnLight),
        boxShadow: focused ? <BoxShadow>[BoxShadow(color: NovaColors.accentMist, spreadRadius: 4)] : NovaDimens.shadowCard,
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 20, color: NovaColors.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              // Mobile keeps the keyboard up on outside taps by default.
              onTapOutside: (_) => _focus.unfocus(),
              textInputAction: TextInputAction.search,
              style: NovaTypography.textTheme.bodyLarge!.copyWith(fontSize: 16, fontWeight: FontWeight.w400),
              cursorColor: NovaColors.accent,
              decoration: InputDecoration.collapsed(
                hintText: widget.hint,
                hintStyle: NovaTypography.textTheme.bodyLarge!.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  color: NovaColors.textMuted,
                ),
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: widget.controller,
            builder: (BuildContext context, TextEditingValue value, _) => value.text.isEmpty
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsetsDirectional.only(start: 8),
                    child: PressableScale(
                      onTap: () {
                        widget.controller.clear();
                        widget.onChanged?.call('');
                      },
                      pressedScale: 0.92,
                      semanticLabel: context.tr('catalog.clearSearch'),
                      child: Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: NovaColors.accentMist,
                          borderRadius: BorderRadius.circular(NovaDimens.radiusSmall),
                        ),
                        child: Icon(Icons.close_rounded, size: 17, color: NovaColors.accent),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
