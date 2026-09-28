import 'package:flutter/material.dart';

import '../../../core/i18n/nova_strings.dart';
import '../../../core/theme/nova_colors.dart';
import '../../../core/theme/nova_typography.dart';
import '../../../core/widgets/monogram_avatar.dart';

/// Personal greeting row: portrait on the left, bold hello with the
/// welcome line underneath.
class GreetingHeader extends StatelessWidget {
  const GreetingHeader({
    super.key,
    required this.name,
    required this.subtitle,
    required this.avatarLabel,
    this.avatarPhoto,
    this.onAvatarTap,
  });

  final String name;
  final String subtitle;

  /// Monogram source for the avatar until profile photos exist.
  final String avatarLabel;

  /// Portrait shown instead of the monogram when available.
  final String? avatarPhoto;
  final VoidCallback? onAvatarTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          PressableAvatar(
            avatarLabel: avatarLabel,
            photo: avatarPhoto,
            onAvatarTap: onAvatarTap,
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${context.tr('home.hello')}, $name',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NovaTypography.textTheme.headlineMedium,
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: NovaTypography.muted(
                    NovaTypography.textTheme.bodyMedium!,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PressableAvatar extends StatelessWidget {
  const PressableAvatar({
    super.key,
    required this.avatarLabel,
    this.onAvatarTap,
    this.photo,
  });

  final String avatarLabel;
  final String? photo;
  final VoidCallback? onAvatarTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Profile',
      child: GestureDetector(
        onTap: onAvatarTap,
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: NovaColors.accent.withValues(alpha: 0.35),
              width: 2,
            ),
          ),
          child: MonogramAvatar(
            label: avatarLabel,
            size: 46,
            photo: photo,
            showRing: false,
            colors: const [NovaColors.accentLight, NovaColors.accentDeep],
          ),
        ),
      ),
    );
  }
}
