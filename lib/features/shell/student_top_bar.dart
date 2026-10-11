import 'package:flutter/material.dart';

import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/widgets/pressable_scale.dart';
import '../account/notifications_screen.dart';
import '../account/settings_screen.dart';
import '../auth/require_account.dart';

/// Lets a tab page switch tabs or open the menu (the shell provides it).
class ShellNav extends InheritedWidget {
  const ShellNav({super.key, required this.select, required this.openMenu, required this.index, required super.child});

  final ValueChanged<int> select;
  final VoidCallback openMenu;
  final int index;

  static ShellNav? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ShellNav>();

  @override
  bool updateShouldNotify(ShellNav old) => old.index != index;
}

/// The website's Student top bar (`.studentTopbar`): the Student's initials
/// (blue square → settings), the bell with its unread count and the theme
/// switch, with the NOVA logo at the other end. A pushed page shows the
/// "Back" pill instead of the initials.
class StudentTopBar extends StatelessWidget {
  const StudentTopBar({super.key, this.showBack = false, this.trailing});

  final bool showBack;

  /// Replaces the logo (e.g. a page action).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final AppState app = AppScope.of(context);
    final String name = app.profile == null ? '' : '${app.profile!.firstName} ${app.profile!.lastName}';
    return Padding(
      padding: EdgeInsets.fromLTRB(14, MediaQuery.paddingOf(context).top + 8, 14, 10),
      child: Row(
        children: [
          if (showBack)
            const BackPill()
          else if (!app.session.signedIn) ...[
            // D-134: a visitor has no initials nor notifications: sign in.
            _SignInPill(onTap: () => requireAccount(context)),
            const SizedBox(width: 8),
            _Square(
              semanticLabel: context.tr('menu.darkMode'),
              onTap: () => app.setDarkMode(!app.darkMode),
              child: Icon(app.darkMode ? Icons.dark_mode_outlined : Icons.light_mode_outlined, size: 20, color: NovaColors.textStrong),
            ),
          ] else ...[
            _Square(
              semanticLabel: context.tr('topbar.settings'),
              color: NovaColors.accent,
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
              child: Text(
                initialsOf(name),
                style: const TextStyle(
                  fontFamily: NovaTypography.body,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _Square(
              semanticLabel: context.tr('topbar.notifications'),
              badge: app.unreadCount,
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const NotificationsScreen())),
              child: Icon(Icons.notifications_none_rounded, size: 21, color: NovaColors.textStrong),
            ),
            const SizedBox(width: 8),
            _Square(
              semanticLabel: context.tr('menu.darkMode'),
              onTap: () => app.setDarkMode(!app.darkMode),
              child: Icon(app.darkMode ? Icons.dark_mode_outlined : Icons.light_mode_outlined, size: 20, color: NovaColors.textStrong),
            ),
          ],
          const Spacer(),
          trailing ?? (ShellNav.maybeOf(context) == null || showBack ? const NovaLogoBadge() : const _MenuButton()),
        ],
      ),
    );
  }

  /// "LB" for Lina Benali; "N" before the name is known.
  static String initialsOf(String name) {
    final List<String> words = name.trim().split(RegExp(r'\s+')).where((String w) => w.isNotEmpty).toList();
    if (words.isEmpty) return 'N';
    return words.take(2).map((String w) => w.substring(0, 1).toUpperCase()).join();
  }
}

/// A visitor's way to their account, where the Student's initials stand.
class _SignInPill extends StatelessWidget {
  const _SignInPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.94,
      semanticLabel: context.tr('guest.signIn'),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: NovaColors.accent, borderRadius: BorderRadius.circular(13)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.login_rounded, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              context.tr('guest.signIn'),
              style: const TextStyle(
                fontFamily: NovaTypography.display,
                fontFamilyFallback: NovaTypography.fallback,
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The website's menu button (`.studentMenu`), at the far end of the bar.
class _MenuButton extends StatelessWidget {
  const _MenuButton();

  @override
  Widget build(BuildContext context) {
    return _Square(
      semanticLabel: 'Menu',
      onTap: ShellNav.maybeOf(context)?.openMenu,
      color: NovaColors.paperRaised,
      child: Icon(Icons.menu_rounded, size: 22, color: NovaColors.textStrong),
    );
  }
}

/// The website's "ارجع" pill: a white pill with a blue arrow chip.
class BackPill extends StatelessWidget {
  const BackPill({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap ?? () => Navigator.of(context).maybePop(),
      semanticLabel: context.tr('common.back'),
      child: Container(
        height: 42,
        padding: const EdgeInsetsDirectional.fromSTEB(6, 0, 14, 0),
        decoration: BoxDecoration(
          color: NovaColors.paperCard,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: NovaColors.borderOnLight),
          boxShadow: const [BoxShadow(offset: Offset(0, 6), blurRadius: 16, spreadRadius: -10, color: Color(0x55121A33))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: NovaColors.accentMist, shape: BoxShape.circle),
              child: Icon(Icons.arrow_back_rounded, size: 17, color: NovaColors.accent),
            ),
            const SizedBox(width: 8),
            Text(
              context.tr('common.back'),
              style: TextStyle(
                fontFamily: NovaTypography.display,
                fontFamilyFallback: NovaTypography.fallback,
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: NovaColors.textStrong,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The round NOVA logo of the website's header.
class NovaLogoBadge extends StatelessWidget {
  const NovaLogoBadge({super.key, this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.08),
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: NovaColors.borderOnLight),
      ),
      child: Image.asset('assets/images/brand/nova_logo.png', semanticLabel: 'NOVA'),
    );
  }
}

class _Square extends StatelessWidget {
  const _Square({required this.child, required this.semanticLabel, this.onTap, this.color, this.badge = 0});

  final Widget child;
  final String semanticLabel;
  final VoidCallback? onTap;
  final Color? color;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.92,
      semanticLabel: semanticLabel,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color ?? NovaColors.paperCard,
              borderRadius: BorderRadius.circular(13),
              border: color == null ? Border.all(color: NovaColors.borderOnLight) : null,
            ),
            child: child,
          ),
          if (badge > 0)
            PositionedDirectional(
              top: -5,
              start: -5,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18),
                height: 18,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5484D),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: NovaColors.paper, width: 2),
                ),
                child: Text(
                  badge > 9 ? '9+' : '$badge',
                  style: const TextStyle(fontFamily: NovaTypography.body, fontWeight: FontWeight.w800, fontSize: 9.5, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
