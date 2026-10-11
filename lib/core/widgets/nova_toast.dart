import 'package:flutter/material.dart';

import '../theme/nova_colors.dart';
import '../theme/nova_dimens.dart';
import '../theme/nova_typography.dart';

/// The app's one confirmation toast, the website's white sticker
/// (`.cartToast`, hero-chrome.css): floating, surface, line border,
/// radius 18, with a 34 px icon tile — green for a done action, red for a
/// failure, blue otherwise.
void novaToast(BuildContext context, String message, {IconData? icon}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
        clipBehavior: Clip.none,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        duration: const Duration(milliseconds: 2000),
        content: NovaToastCard(message: message, icon: icon),
      ),
    );
}

/// The toast's sticker: also used by the realtime notification banner.
class NovaToastCard extends StatelessWidget {
  const NovaToastCard({super.key, required this.message, this.icon, this.detail, this.tone});

  final String message;

  /// A second, lighter line (a notification's message).
  final String? detail;
  final IconData? icon;

  /// The tile's (tone, background); chosen from [icon] when null.
  final (Color, Color)? tone;

  /// `--hx-shadow-sticker` + `0 24px 60px -30px rgba(18,26,51,.5)`.
  static List<BoxShadow> get shadow => <BoxShadow>[
        ...NovaDimens.shadowSticker,
        const BoxShadow(offset: Offset(0, 24), blurRadius: 60, spreadRadius: -30, color: Color(0x80121A33)),
      ];

  static final Set<IconData> _failures = <IconData>{Icons.error_outline_rounded, Icons.error_rounded};
  static final Set<IconData> _done = <IconData>{
    Icons.check_circle_rounded,
    Icons.check_rounded,
    Icons.done_all_rounded,
    Icons.delete_outline_rounded,
    Icons.content_copy_rounded,
    Icons.mark_email_read_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final IconData? icon = this.icon;
    final (Color ink, Color background) = tone ??
        (_failures.contains(icon)
            ? (NovaColors.heartRed, NovaColors.dangerBg)
            : _done.contains(icon)
                ? (NovaColors.onlineGreen, NovaColors.liveBg)
                : (NovaColors.accent, NovaColors.accentMist));
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 16, 12),
      decoration: BoxDecoration(
        color: NovaColors.paperCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: NovaColors.borderOnLight),
        boxShadow: shadow,
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(11)),
              child: Icon(icon, size: 18, color: ink),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  maxLines: detail == null ? 3 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: NovaTypography.display,
                    fontFamilyFallback: NovaTypography.fallback,
                    fontWeight: detail == null ? FontWeight.w700 : FontWeight.w800,
                    fontSize: 15,
                    height: 1.35,
                    color: NovaColors.textStrong,
                  ),
                ),
                if (detail != null && detail!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: NovaTypography.body,
                      fontFamilyFallback: NovaTypography.fallback,
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                      height: 1.4,
                      color: NovaColors.textBody,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
