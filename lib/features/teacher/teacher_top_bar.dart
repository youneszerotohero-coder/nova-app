import 'package:flutter/material.dart';

import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/widgets/nova_image.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../data/session_store.dart';
import '../account/notifications_screen.dart';
import '../shell/student_top_bar.dart';
import 'teacher_settings_screen.dart';
import 'teacher_shell.dart';

/// The Teacher's top bar (D-143), in the Student bar's style
/// (`.studentTopbar`: 72 px, the surface at 90 %, a hairline under it): the
/// Teacher's photo and name at the start (→ Settings), then the theme switch
/// and the bell with its unread count (→ Notifications). Every Teacher page
/// shows it through [StudentTopBar].
class TeacherTopBar extends StatelessWidget {
  const TeacherTopBar({super.key, this.trailing});

  /// A page action, before the theme switch.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final AppState app = AppScope.of(context);
    final TeacherIdentity? teacher = app.session.teacher;
    final String name = teacher?.fullName ?? app.profile?.fullName ?? '';
    final double top = MediaQuery.paddingOf(context).top;

    return Container(
      padding: EdgeInsets.only(top: top),
      decoration: BoxDecoration(
        color: NovaColors.paperCard.withValues(alpha: 0.9),
        border: Border(bottom: BorderSide(color: NovaColors.borderOnLight)),
      ),
      child: SizedBox(
        height: 72,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Expanded(
                child: PressableScale(
                  onTap: () => _open(context, TeacherShell.settings, const TeacherSettingsScreen()),
                  pressedScale: 0.97,
                  semanticLabel: context.tr('topbar.settings'),
                  child: Row(
                    children: [
                      TeacherAvatar(name: name, photoUrl: teacher?.photoUrl, size: 44),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: NovaTypography.display,
                                fontFamilyFallback: NovaTypography.fallback,
                                fontWeight: FontWeight.w800,
                                fontSize: 15.5,
                                height: 1.2,
                                color: NovaColors.textStrong,
                              ),
                            ),
                            Text(
                              context.tr('teacher.role'),
                              style: TextStyle(
                                fontFamily: NovaTypography.body,
                                fontFamilyFallback: NovaTypography.fallback,
                                fontWeight: FontWeight.w600,
                                fontSize: 12.5,
                                height: 1.3,
                                color: NovaColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (trailing != null) ...[trailing!, const SizedBox(width: 8)],
              const _ThemeToggle(),
              const SizedBox(width: 8),
              _Bell(
                count: app.unreadCount,
                onTap: () => _open(context, TeacherShell.notifications, const NotificationsScreen()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A shell tab when the bar sits in the Teacher shell, else the page.
  static void _open(BuildContext context, int tab, Widget page) {
    final ShellNav? nav = ShellNav.maybeOf(context);
    if (nav != null) {
      nav.select(tab);
    } else {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    }
  }
}

/// The Teacher's photo (`photo_url`), or their initials on the blue square
/// the Student bar uses.
class TeacherAvatar extends StatelessWidget {
  const TeacherAvatar({super.key, required this.name, this.photoUrl, this.size = 44});

  final String name;
  final String? photoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final double radius = size * 0.3;
    final Widget initials = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: NovaColors.accent, borderRadius: BorderRadius.circular(radius)),
      child: Text(
        StudentTopBar.initialsOf(name),
        style: TextStyle(
          fontFamily: NovaTypography.display,
          fontFamilyFallback: NovaTypography.fallback,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.3,
          height: 1.1,
          color: Colors.white,
        ),
      ),
    );
    final String? url = photoUrl;
    if (url == null || url.isEmpty) return initials;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image(
        image: novaImageProvider(url, cacheWidth: (size * 3).round()),
        width: size,
        height: size,
        fit: BoxFit.cover,
        semanticLabel: name,
        errorBuilder: (BuildContext context, Object error, StackTrace? stack) => initials,
      ),
    );
  }
}

/// `.dashboardThemeToggle`, as in the Student bar.
class _ThemeToggle extends StatelessWidget {
  const _ThemeToggle();

  @override
  Widget build(BuildContext context) {
    final AppState app = AppScope.of(context);
    final bool dark = app.darkMode;
    return PressableScale(
      onTap: () => app.setDarkMode(!dark),
      pressedScale: 0.92,
      semanticLabel: context.tr('menu.darkMode'),
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF20242B) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: dark ? const Color(0xFF3C434D) : const Color(0xFFD8DDE3)),
        ),
        child: Icon(
          dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
          size: 18,
          color: dark ? const Color(0xFFF5F7FA) : const Color(0xFF30343A),
        ),
      ),
    );
  }
}

/// `.notificationButton`: the bell with the danger-red unread badge.
class _Bell extends StatelessWidget {
  const _Bell({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.92,
      semanticLabel: context.tr('topbar.notifications'),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: NovaColors.paperCard,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: NovaColors.borderOnLight),
            ),
            child: Icon(Icons.notifications_none_rounded, size: 20, color: NovaColors.textBody),
          ),
          if (count > 0)
            PositionedDirectional(
              top: -6,
              end: -6,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18),
                height: 18,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: NovaColors.heartRed,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Text(
                  count > 9 ? '9+' : '$count',
                  style: const TextStyle(fontFamily: NovaTypography.body, fontWeight: FontWeight.w700, fontSize: 10, height: 1, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
