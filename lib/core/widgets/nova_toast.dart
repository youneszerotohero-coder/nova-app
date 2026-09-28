import 'package:flutter/material.dart';

import '../theme/nova_colors.dart';

/// The app's one confirmation toast: floating, ink-filled, rounded.
void novaToast(BuildContext context, String message, {IconData? icon}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: NovaColors.ink950,
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 100),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        duration: const Duration(milliseconds: 2000),
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: NovaColors.accentLight),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: NovaColors.textOnDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
}
