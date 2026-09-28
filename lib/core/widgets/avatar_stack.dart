import 'package:flutter/material.dart';

import '../theme/nova_colors.dart';
import 'monogram_avatar.dart';

/// Overlapping learner avatars with a "+N" counter — the social proof
/// row on course cards and live sessions.
class AvatarStack extends StatelessWidget {
  const AvatarStack({
    super.key,
    required this.labels,
    this.extra = 0,
    this.size = 28,
    this.ringColor,
    this.counterColor,
    this.counterTextColor,
    this.photos,
  });

  /// Names the monograms are derived from; the first few are shown.
  final List<String> labels;

  /// How many more learners the "+N" chip stands for.
  final int extra;
  final double size;

  /// The colour the avatars are cut out of — match the card fill.
  final Color? ringColor;
  final Color? counterColor;
  final Color? counterTextColor;

  /// Portraits by label; labels without one fall back to monograms.
  final Map<String, String>? photos;

  @override
  Widget build(BuildContext context) {
    final List<String> shown = labels.take(3).toList();
    final double overlap = size * 0.32;

    return SizedBox(
      height: size,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: shown.isEmpty ? 0 : size + (shown.length - 1) * (size - overlap),
            height: size,
            child: Stack(
              children: [
                for (int i = 0; i < shown.length; i++)
                  Positioned(
                    left: i * (size - overlap),
                    child: MonogramAvatar(
                      label: shown[i],
                      photo: photos?[shown[i]],
                      size: size,
                      ringColor: ringColor ?? NovaColors.paperCard,
                    ),
                  ),
              ],
            ),
          ),
          if (extra > 0) ...[
            const SizedBox(width: 8),
            Text(
              '+$extra',
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                fontSize: size * 0.43,
                height: 1,
                color: counterTextColor ?? NovaColors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
