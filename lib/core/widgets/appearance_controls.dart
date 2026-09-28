import 'package:flutter/material.dart';

import '../i18n/nova_strings.dart';
import '../state/app_state.dart';
import '../theme/nova_colors.dart';
import '../theme/nova_typography.dart';
import 'pressable_scale.dart';

/// Dark-mode switch + language selector, shared by the navigation
/// menu and the Settings screen.
class AppearanceControls extends StatelessWidget {
  const AppearanceControls({super.key, this.compact = false});

  /// Compact renders the menu variant (pill language chips).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final AppState state = AppScope.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              state.darkMode
                  ? Icons.dark_mode_rounded
                  : Icons.light_mode_rounded,
              size: 20,
              color: NovaColors.accentDeep,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                context.tr('menu.darkMode'),
                style: NovaTypography.textTheme.titleSmall,
              ),
            ),
            Switch(
              value: state.darkMode,
              activeThumbColor: Colors.white,
              activeTrackColor: NovaColors.accent,
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: NovaColors.textMuted.withValues(alpha: 0.35),
              trackOutlineColor: const WidgetStatePropertyAll<Color>(
                Colors.transparent,
              ),
              onChanged: (bool value) =>
                  AppScope.of(context).setDarkMode(value),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          context.tr('menu.language'),
          style: NovaTypography.muted(NovaTypography.textTheme.labelSmall!),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final NovaLang lang in NovaLang.values) ...[
              if (lang != NovaLang.en) const SizedBox(width: 8),
              Expanded(
                child: PressableScale(
                  onTap: () => AppScope.of(context).setLang(lang),
                  pressedScale: 0.95,
                  semanticLabel: lang.label,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: state.lang == lang
                          ? NovaColors.accent
                          : NovaColors.paperCard,
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(
                        color: state.lang == lang
                            ? NovaColors.accent
                            : NovaColors.borderOnLight,
                      ),
                    ),
                    child: Text(
                      compact ? lang.name.toUpperCase() : lang.label,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w700,
                        fontSize: compact ? 12 : 12.5,
                        color: state.lang == lang
                            ? Colors.white
                            : NovaColors.textStrong,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
