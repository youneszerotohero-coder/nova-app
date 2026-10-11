import 'package:flutter/material.dart';

import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/widgets/pressable_scale.dart';
import '../account/notifications_screen.dart';
import '../account/settings_screen.dart';
import '../auth/require_account.dart';
import 'shell_screen.dart';

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

/// The website's Student top bar (`.studentTopbar`, `profile.tsx`), in its
/// order: the menu button at the start (the right in Arabic), then at the
/// end the theme switch, the bell with its unread count and the Student's
/// initials (blue square → settings). A visitor (D-134) has no bell, and a
/// "Sign in" pill where the initials stand. A pushed page shows the "Back"
/// pill at the start and the NOVA logo at the end instead.
class StudentTopBar extends StatelessWidget {
  const StudentTopBar({super.key, this.showBack = false, this.trailing});

  final bool showBack;

  /// Replaces the logo (e.g. a page action).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final double top = MediaQuery.paddingOf(context).top;
    if (showBack) {
      return Padding(
        padding: EdgeInsets.fromLTRB(14, top + 8, 14, 10),
        child: Row(
          children: [
            const BackPill(),
            const Spacer(),
            trailing ?? const NovaLogoBadge(),
          ],
        ),
      );
    }

    final AppState app = AppScope.of(context);
    final String name = app.profile == null ? '' : '${app.profile!.firstName} ${app.profile!.lastName}';
    // `.studentTopbar`: 72 px, the surface at 90 % and a hairline under it;
    // `.studentTopActions`: 8 px apart.
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
              // Outside the shell (a page shown on its own) there is no menu.
              if (ShellNav.maybeOf(context) != null) const _MenuButton(),
              const Spacer(),
              if (trailing != null) ...[trailing!, const SizedBox(width: 8)],
              const _ThemeToggle(),
              const SizedBox(width: 8),
              if (!app.session.signedIn)
                // D-134: a visitor has no initials nor notifications: sign in.
                _SignInPill(onTap: () => requireAccount(context))
              else ...[
                _Square(
                  semanticLabel: context.tr('topbar.notifications'),
                  badge: app.unreadCount,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const NotificationsScreen())),
                  child: Icon(Icons.notifications_none_rounded, size: 20, color: NovaColors.textBody),
                ),
                const SizedBox(width: 8),
                // `.studentAvatar`: a hairline before the initials (`#e4e6e9`
                // in both themes), 9 px from them.
                Container(width: 1, height: 44, color: const Color(0xFFE4E6E9)),
                const SizedBox(width: 9),
                PressableScale(
                  onTap: () => _openSettings(context),
                  pressedScale: 0.92,
                  semanticLabel: context.tr('topbar.settings'),
                  child: Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: NovaColors.accent, borderRadius: BorderRadius.circular(13)),
                    child: Text(
                      initialsOf(name),
                      style: const TextStyle(
                        fontFamily: NovaTypography.display,
                        fontFamilyFallback: NovaTypography.fallback,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        height: 1.1,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The initials lead to the settings (`/account/settings`), the Account tab.
  static void _openSettings(BuildContext context) {
    final ShellNav? nav = ShellNav.maybeOf(context);
    if (nav != null) {
      nav.select(ShellScreen.account);
    } else {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
    }
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

/// The website's menu button (`.studentMenu`): surface-2, ink lines.
class _MenuButton extends StatelessWidget {
  const _MenuButton();

  @override
  Widget build(BuildContext context) {
    return _Square(
      semanticLabel: 'Menu',
      onTap: ShellNav.maybeOf(context)?.openMenu,
      color: NovaColors.paperRaised,
      child: Icon(Icons.menu_rounded, size: 20, color: NovaColors.textStrong),
    );
  }
}

/// `.dashboardThemeToggle` (`dark-mode.css`): white with a grey border and a
/// dark sun, or a charcoal square with a light moon in dark mode.
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

/// A 44 px square of the top bar (`.studentMenu`, `.notificationButton`):
/// radius 13, the surface with a hairline unless [color] fills it. Its badge
/// (`.notificationButton i`) is the danger red with a white ring, over the
/// top end corner.
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
                  badge > 9 ? '9+' : '$badge',
                  style: const TextStyle(fontFamily: NovaTypography.body, fontWeight: FontWeight.w700, fontSize: 10, height: 1, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
