import 'package:flutter/material.dart';

import '../../core/i18n/nova_strings.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/widgets/monogram_avatar.dart';
import '../../data/chat_store.dart';
import 'chat_format.dart';

/// The NOVA mark in a white circle: the public room and the Admin.
class ChatNovaMark extends StatelessWidget {
  const ChatNovaMark({super.key, this.size = 52});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.12),
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: NovaColors.accent.withValues(alpha: 0.35), width: size > 40 ? 2 : 1.5),
      ),
      child: Image.asset('assets/images/brand/nova_logo.png', semanticLabel: 'NOVA'),
    );
  }
}

/// A room's picture: the NOVA mark for the public room, the Teacher's photo,
/// or a monogram of the room name.
class ChatRoomAvatar extends StatelessWidget {
  const ChatRoomAvatar({super.key, required this.room, this.size = 52});

  final ChatRoom room;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (room.isPublic) return ChatNovaMark(size: size);
    final String? photo = room.teacher?.photoUrl;
    final Color hue = chatHueOf(room.id + 7);
    return MonogramAvatar(
      label: room.name,
      size: size,
      showRing: false,
      photo: photo,
      colors: photo == null ? <Color>[hue, Color.lerp(hue, NovaColors.accent, 0.55)!] : null,
    );
  }
}

/// A sender's or member's picture: the NOVA mark for the Admin, their
/// photo, or a monogram in their name colour.
class ChatPersonAvatar extends StatelessWidget {
  const ChatPersonAvatar({super.key, required this.userId, required this.role, this.name, this.photoUrl, this.size = 32});

  final int userId;
  final ChatRole role;
  final String? name;
  final String? photoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (role == ChatRole.admin) return ChatNovaMark(size: size);
    final Color hue = chatHueOf(userId);
    return MonogramAvatar(
      label: name ?? '?',
      size: size,
      showRing: false,
      photo: photoUrl,
      colors: <Color>[hue, Color.lerp(hue, Colors.black, 0.18)!],
    );
  }
}

/// The small "Teacher" / "NOVA" badge next to a staff name.
class ChatRoleBadge extends StatelessWidget {
  const ChatRoleBadge({super.key, required this.role});

  final ChatRole role;

  @override
  Widget build(BuildContext context) {
    if (role == ChatRole.student) return const SizedBox.shrink();
    final bool admin = role == ChatRole.admin;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: admin ? NovaColors.yellow : NovaColors.accentMist,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(admin ? Icons.verified_rounded : Icons.school_rounded, size: 11, color: admin ? NovaColors.yellowInk : NovaColors.accent),
          const SizedBox(width: 3),
          Text(
            context.tr(admin ? 'chat.badgeNova' : 'chat.badgeTeacher'),
            style: TextStyle(
              fontFamily: NovaTypography.display,
              fontFamilyFallback: NovaTypography.fallback,
              fontWeight: FontWeight.w800,
              fontSize: 10.5,
              height: 1.25,
              color: admin ? NovaColors.yellowInk : NovaColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}

/// The blue unread count (grey when the room is muted).
class ChatUnreadPill extends StatelessWidget {
  const ChatUnreadPill({super.key, required this.count, this.muted = false});

  final int count;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (Widget child, Animation<double> animation) => ScaleTransition(scale: animation, child: child),
      child: count <= 0
          ? const SizedBox.shrink()
          : Container(
              key: ValueKey<int>(count),
              constraints: const BoxConstraints(minWidth: 22),
              height: 22,
              padding: const EdgeInsets.symmetric(horizontal: 7),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: muted ? NovaColors.textMuted : NovaColors.accent,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                count > 99 ? '99+' : '$count',
                style: const TextStyle(fontFamily: NovaTypography.body, fontWeight: FontWeight.w700, fontSize: 11.5, height: 1, color: Colors.white),
              ),
            ),
    );
  }
}

/// A round icon button of the chat chrome (app bar, composer).
class ChatIconButton extends StatelessWidget {
  const ChatIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.size = 44,
    this.color,
    this.background,
    this.gradient = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final double size;
  final Color? color;
  final Color? background;
  final bool gradient;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        type: MaterialType.transparency,
        child: InkResponse(
          onTap: onTap,
          radius: size * 0.6,
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: gradient ? null : background,
              gradient: gradient ? NovaColors.accentGradient : null,
              boxShadow: gradient
                  ? const <BoxShadow>[BoxShadow(offset: Offset(0, 6), blurRadius: 14, spreadRadius: -6, color: Color(0x661F54D6))]
                  : null,
            ),
            child: Icon(icon, size: size * 0.5, color: color ?? (gradient ? Colors.white : NovaColors.textBody)),
          ),
        ),
      ),
    );
  }
}
