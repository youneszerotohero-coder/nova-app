import 'package:flutter/material.dart';

import '../theme/nova_colors.dart';
import '../theme/nova_dimens.dart';
import '../theme/nova_typography.dart';
import 'hero_style.dart';
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
  Color? color,
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
      color: color ?? NovaColors.onlineGreen,
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
          margin: const EdgeInsets.symmetric(horizontal: 28),
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 22),
          decoration: BoxDecoration(
            color: NovaColors.paperCard,
            borderRadius: BorderRadius.circular(NovaDimens.radiusTile),
            border: Border.all(color: NovaColors.borderOnLight),
            boxShadow: NovaDimens.shadowLift,
          ),
          child: Column(
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
              HeroTitle(title, onBlue: false, size: 20, textAlign: TextAlign.center),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: NovaTypography.body,
                  fontFamilyFallback: NovaTypography.fallback,
                  fontSize: 15,
                  height: 1.6,
                  color: NovaColors.textBody,
                ),
              ),
              const SizedBox(height: 20),
              // `HxSuccess`'s action: the blue `.hxBtn` with its chip.
              NovaButton(
                label: actionLabel,
                chipIcon: Icons.arrow_forward_rounded,
                expand: true,
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
