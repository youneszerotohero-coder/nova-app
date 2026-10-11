import 'package:flutter/material.dart';

import '../theme/nova_colors.dart';
import '../theme/nova_typography.dart';
import 'pressable_scale.dart';

/// The website's choice chip: `.nvChip` (pages.css) in the catalogue
/// filter sheet — surface with a line border, blue with a check when
/// chosen — or, with [tab], a `.nvSubjectTabs` pill of the teachers page,
/// filled with the ink colour when chosen.
class SubjectChip extends StatelessWidget {
  const SubjectChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.tab = false,
    this.check = true,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool tab;

  /// The check mark of a chosen option; the "All levels" chip has none.
  final bool check;

  @override
  Widget build(BuildContext context) {
    final Color background = selected ? (tab ? NovaColors.textStrong : NovaColors.accent) : NovaColors.paperCard;
    final Color foreground = selected ? (tab ? NovaColors.paperPublic : Colors.white) : NovaColors.textBody;
    return Semantics(
      selected: selected,
      button: true,
      child: PressableScale(
        onTap: onTap,
        pressedScale: 0.96,
        semanticLabel: label,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          height: tab ? 44 : 38,
          padding: EdgeInsets.symmetric(horizontal: tab ? 16 : 14),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(tab ? 999 : 13),
            border: Border.all(color: selected ? background : NovaColors.borderOnLight),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected && check && !tab) ...[
                Icon(Icons.check_rounded, size: 13, color: foreground),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: tab ? NovaTypography.body : NovaTypography.display,
                    fontFamilyFallback: NovaTypography.fallback,
                    fontWeight: tab ? FontWeight.w500 : FontWeight.w700,
                    fontSize: tab ? 13.5 : 14,
                    height: 1.2,
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
