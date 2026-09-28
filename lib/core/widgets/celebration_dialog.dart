import 'package:flutter/material.dart';

import '../theme/nova_colors.dart';
import '../theme/nova_dimens.dart';
import '../theme/nova_typography.dart';
import 'nova_decor.dart';
import 'pressable_scale.dart';
import 'success_burst.dart';

/// Celebrates a milestone worth stopping for — a passed quiz, a
/// finished course — with the burst, a headline and one way out.
///
/// Kept deliberately rare: everyday confirmations use `novaToast`.
Future<void> showNovaCelebration(
  BuildContext context, {
  required String title,
  required String message,
  required String actionLabel,
  Color color = NovaColors.onlineGreen,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: actionLabel,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    transitionDuration: const Duration(milliseconds: 360),
    transitionBuilder: (
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child,
    ) {
      final Animation<double> curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeIn,
      );
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.86, end: 1).animate(curved),
          child: child,
        ),
      );
    },
    pageBuilder: (BuildContext context, _, _) => _CelebrationCard(
      title: title,
      message: message,
      actionLabel: actionLabel,
      color: color,
    ),
  );
}

class _CelebrationCard extends StatelessWidget {
  const _CelebrationCard({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.color,
  });

  final String title;
  final String message;
  final String actionLabel;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 22),
          decoration: BoxDecoration(
            color: NovaColors.paperCard,
            borderRadius: BorderRadius.circular(NovaDimens.radiusCardLarge),
            boxShadow: NovaDimens.shadowFloating,
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: NovaDecor(color: color, opacity: 0.1, seed: 2),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The burst paints past its slot, so the card
                  // reserves less height than the canvas it draws on.
                  SizedBox(
                    height: 122,
                    child: OverflowBox(
                      maxWidth: 220,
                      maxHeight: 220,
                      child: SuccessBurst(size: 92, color: color),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: NovaTypography.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: NovaTypography.muted(
                      NovaTypography.textTheme.bodySmall!,
                    ),
                  ),
                  const SizedBox(height: 20),
                  PressableScale(
                    onTap: () => Navigator.of(context).pop(),
                    pressedScale: 0.96,
                    semanticLabel: actionLabel,
                    child: Container(
                      height: 50,
                      width: double.infinity,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: NovaColors.ink950,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        actionLabel,
                        style: NovaTypography.textTheme.labelLarge!.copyWith(
                          color: NovaColors.textOnDark,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
