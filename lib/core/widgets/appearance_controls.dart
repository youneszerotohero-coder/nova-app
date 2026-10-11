import 'package:flutter/material.dart';

import '../i18n/nova_strings.dart';
import '../state/app_state.dart';
import '../theme/nova_colors.dart';
import '../theme/nova_typography.dart';
import 'pressable_scale.dart';

/// Dark-mode switch + language selector, shared by the navigation
/// menu and the Settings screen. The languages are the website's
/// segmented control (`.nvSegments`, pages.css): a blue-soft track, the
/// active language blue with white text.
class AppearanceControls extends StatelessWidget {
  const AppearanceControls({super.key, this.compact = false});

  /// Compact renders the menu variant (language codes).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final AppState state = AppScope.of(context);
    TextStyle label(double size, Color color) => TextStyle(
          fontFamily: NovaTypography.display,
          fontFamilyFallback: NovaTypography.fallback,
          fontWeight: FontWeight.w800,
          fontSize: size,
          height: 1.25,
          color: color,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: NovaColors.accentMist, borderRadius: BorderRadius.circular(13)),
              child: Icon(
                state.darkMode ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                size: 20,
                color: NovaColors.accent,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(child: Text(context.tr('menu.darkMode'), style: label(15, NovaColors.textStrong))),
            Switch(
              value: state.darkMode,
              activeThumbColor: Colors.white,
              activeTrackColor: NovaColors.accent,
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: NovaColors.lineStrong,
              trackOutlineColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
              onChanged: (bool value) => AppScope.of(context).setDarkMode(value),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(context.tr('menu.language'), style: label(13.5, NovaColors.textMuted)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: NovaColors.accentMist, borderRadius: BorderRadius.circular(14)),
          child: Row(
            children: [
              for (final NovaLang lang in NovaLang.values) ...[
                if (lang != NovaLang.values.first) const SizedBox(width: 3),
                Expanded(
                  child: PressableScale(
                    onTap: () => AppScope.of(context).setLang(lang),
                    pressedScale: 0.95,
                    semanticLabel: lang.label,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: state.lang == lang ? NovaColors.accent : Colors.transparent,
                        borderRadius: BorderRadius.circular(11),
                        boxShadow: state.lang == lang
                            ? const [BoxShadow(offset: Offset(0, 8), blurRadius: 16, spreadRadius: -10, color: Color(0xCC1F54D6))]
                            : null,
                      ),
                      child: Text(
                        compact ? lang.name.toUpperCase() : lang.label,
                        style: label(compact ? 13 : 15, state.lang == lang ? Colors.white : NovaColors.textBody),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
