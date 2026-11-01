import 'package:flutter/material.dart';

import '../i18n/nova_strings.dart';
import '../state/app_state.dart';
import '../theme/nova_colors.dart';
import '../theme/nova_typography.dart';
import '../desktop/desktop_layout.dart';
import '../desktop/desktop_navigation.dart';
import '../utils/player_fullscreen.dart';
import 'app_menu.dart';
import 'nova_bottom_bar.dart';

/// D-188, PC app: the phone's bottom bar as a desktop sidebar — the same
/// destinations, in the same navy (`.studentBottomNav`) with the yellow
/// active marker, each a 20 px icon beside its label, with a hover state and
/// the hand cursor. At the window's start edge (the right in Arabic).
///
/// D-193: the sidebar also carries what the phone's menu holds ([groups]:
/// the catalogue, chats, orders…; [footer]: language, help, sign out), so the
/// PC app has one sidebar and no menu panel sliding over it.
class NovaSideRail extends StatelessWidget {
  const NovaSideRail({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onChanged,
    this.groups = const <NovaMenuGroup>[],
    this.footer,
  });

  final List<NovaNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onChanged;
  final List<NovaMenuGroup> groups;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final double top = MediaQuery.paddingOf(context).top;
    return Container(
      width: DesktopMetrics.railWidth,
      color: NovaColors.ink950,
      padding: EdgeInsets.fromLTRB(14, top + 18, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 6, bottom: 18),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: Image.asset('assets/images/brand/nova_logo.png', semanticLabel: 'NOVA'),
                ),
                const SizedBox(width: 10),
                Text(
                  'NOVA',
                  style: TextStyle(
                    fontFamily: NovaTypography.display,
                    fontFamilyFallback: NovaTypography.fallback,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    height: 1.2,
                    letterSpacing: 1.2,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (int i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(height: 2),
                  _RailItem(item: items[i], active: i == currentIndex, onTap: () => onChanged(i)),
                ],
                for (final NovaMenuGroup group in groups) ...[
                  _RailGroupLabel(group.label),
                  for (int i = 0; i < group.entries.length; i++) ...[
                    if (i > 0) const SizedBox(height: 2),
                    _RailItem(
                      item: NovaNavItem(icon: group.entries[i].icon, label: group.entries[i].label),
                      active: group.entries[i].active,
                      onTap: group.entries[i].onTap,
                    ),
                  ],
                ],
              ],
            ),
          ),
          if (footer != null) ...[
            Container(height: 1, margin: const EdgeInsets.only(top: 8, bottom: 10), color: Colors.white.withValues(alpha: 0.1)),
            footer!,
          ],
        ],
      ),
    );
  }
}

/// A group's title in the sidebar (`.studentNavLabel` on navy).
class _RailGroupLabel extends StatelessWidget {
  const _RailGroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 18, 12, 6),
      child: Text(
        text.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: NovaTypography.body,
          fontFamilyFallback: NovaTypography.fallback,
          fontWeight: FontWeight.w700,
          fontSize: 11,
          height: 1.2,
          letterSpacing: 0.8,
          color: Colors.white.withValues(alpha: 0.45),
        ),
      ),
    );
  }
}

/// D-193: the sidebar's bottom — the language pills, then help and sign out
/// (a signed-in Student) or sign in and create an account (a visitor).
class NovaRailFooter extends StatelessWidget {
  const NovaRailFooter({super.key, this.onHelp, this.onSignOut, this.onSignIn, this.onRegister});

  final VoidCallback? onHelp;
  final VoidCallback? onSignOut;
  final VoidCallback? onSignIn;
  final VoidCallback? onRegister;

  @override
  Widget build(BuildContext context) {
    final AppState app = AppScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 12, bottom: 8),
          child: Row(
            children: [
              Icon(Icons.translate_rounded, size: 16, color: Colors.white.withValues(alpha: 0.6)),
              const Spacer(),
              for (final NovaLang lang in const <NovaLang>[NovaLang.fr, NovaLang.ar, NovaLang.en]) ...[
                if (lang != NovaLang.fr) const SizedBox(width: 4),
                _RailPill(
                  label: lang.name.toUpperCase(),
                  semanticLabel: lang.label,
                  active: app.lang == lang,
                  onTap: () => app.setLang(lang),
                ),
              ],
            ],
          ),
        ),
        if (onHelp != null)
          _RailItem(item: NovaNavItem(icon: Icons.help_outline_rounded, label: context.tr('menu.needHelp')), active: false, onTap: onHelp!),
        if (onSignOut != null) ...[
          const SizedBox(height: 2),
          _RailItem(
            item: NovaNavItem(icon: Icons.logout_rounded, label: context.tr('menu.signOut')),
            active: false,
            onTap: onSignOut!,
            ink: const Color(0xFFFF8A8A),
          ),
        ],
        if (onSignIn != null) ...[
          const SizedBox(height: 4),
          _RailItem(item: NovaNavItem(icon: Icons.login_rounded, label: context.tr('guest.signIn')), active: true, onTap: onSignIn!),
        ],
        if (onRegister != null) ...[
          const SizedBox(height: 2),
          _RailItem(item: NovaNavItem(icon: Icons.person_add_alt_1_outlined, label: context.tr('gateway.registerCta')), active: false, onTap: onRegister!),
        ],
      ],
    );
  }
}

class _RailPill extends StatelessWidget {
  const _RailPill({required this.label, required this.semanticLabel, required this.active, required this.onTap});

  final String label;
  final String semanticLabel;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: semanticLabel,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: 34,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? const Color(0xFF1E66F5) : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: NovaTypography.body,
                fontWeight: FontWeight.w700,
                fontSize: 11,
                height: 1.2,
                color: active ? Colors.white : Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RailItem extends StatefulWidget {
  const _RailItem({required this.item, required this.active, required this.onTap, this.ink});

  final NovaNavItem item;
  final bool active;
  final VoidCallback onTap;

  /// The label and icon colour when not active (sign out: red).
  final Color? ink;

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bool active = widget.active;
    final Color ink = active
        ? NovaColors.yellowInk
        : widget.ink ?? Colors.white.withValues(alpha: _hover ? 0.95 : 0.74);
    return Semantics(
      button: true,
      selected: active,
      label: widget.item.label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            height: 40,
            padding: const EdgeInsetsDirectional.only(start: 12, end: 10),
            decoration: BoxDecoration(
              color: active
                  ? NovaColors.yellow
                  : _hover
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(widget.item.icon, size: 20, color: ink),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: NovaTypography.display,
                      fontFamilyFallback: NovaTypography.fallback,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w700,
                      fontSize: 14,
                      height: 1.2,
                      color: ink,
                    ),
                  ),
                ),
                if (widget.item.badgeCount > 0)
                  Container(
                    constraints: const BoxConstraints(minWidth: 20),
                    height: 20,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: const Color(0xFFFF5D5D), borderRadius: BorderRadius.circular(100)),
                    child: Text(
                      widget.item.badgeCount > 99 ? '99+' : '${widget.item.badgeCount}',
                      style: const TextStyle(
                        fontFamily: NovaTypography.body,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        height: 1.2,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// D-188: a shell's frame — the phone's floating bottom bar, or in the PC app
/// (a desktop window at least [DesktopMetrics.minLayoutWidth] wide) the
/// sidebar beside the content, which sits in the centred desktop column. The
/// content keeps its state when the window crosses that width.
class NovaShellFrame extends StatefulWidget {
  const NovaShellFrame({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onChanged,
    required this.content,
    this.phoneOverlay,
    this.desktopOverlay,
    this.backgroundColor,
    this.railGroups = const <NovaMenuGroup>[],
    this.railFooter,
    this.desktopNavigatorKey,
  });

  /// D-193: the desktop navigator beside the sidebar, where pages open (the
  /// shell pushes its sidebar's pages there).
  final GlobalKey<NavigatorState>? desktopNavigatorKey;

  final List<NovaNavItem> items;

  /// D-193: the menu's other destinations and its bottom, in the sidebar.
  final List<NovaMenuGroup> railGroups;
  final Widget? railFooter;
  final int currentIndex;
  final ValueChanged<int> onChanged;

  /// The tabs (an `IndexedStack`).
  final Widget content;

  /// Drawn over the content on phones (e.g. a floating button above the bar).
  final Widget? phoneOverlay;

  /// Drawn over the content area on desktop.
  final Widget? desktopOverlay;
  final Color? backgroundColor;

  @override
  State<NovaShellFrame> createState() => _NovaShellFrameState();
}

class _NovaShellFrameState extends State<NovaShellFrame> {
  final GlobalKey _content = GlobalKey();
  late final GlobalKey<NavigatorState> _pages = widget.desktopNavigatorKey ?? GlobalKey<NavigatorState>();
  final DesktopRouteObserver _routes = DesktopRouteObserver();

  @override
  void initState() {
    super.initState();
    DesktopShellPages.attach(_pages, _routes);
  }

  @override
  void didUpdateWidget(NovaShellFrame old) {
    super.didUpdateWidget(old);
    // A tab chosen while a page is open beside the sidebar: back to the tab.
    if (old.currentIndex != widget.currentIndex) _pages.currentState?.popUntil((Route<dynamic> route) => route.isFirst);
  }

  @override
  void dispose() {
    DesktopShellPages.detach(_pages);
    super.dispose();
  }

  void _onRail(int index) {
    _pages.currentState?.popUntil((Route<dynamic> route) => route.isFirst);
    widget.onChanged(index);
  }

  @override
  Widget build(BuildContext context) {
    final Widget content = KeyedSubtree(key: _content, child: widget.content);
    if (desktopLayoutOf(context)) {
      // D-193: the sidebar stays beside every page, as in desktop apps (and
      // the website): pages open in this area's own navigator, never over
      // the sidebar. A full-screen player hides it.
      return Scaffold(
        backgroundColor: widget.backgroundColor,
        body: ValueListenableBuilder<bool>(
          valueListenable: playerFullscreen,
          builder: (BuildContext context, bool fullscreen, _) => Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (fullscreen)
                const SizedBox.shrink()
              else
                NovaSideRail(
                  items: widget.items,
                  currentIndex: widget.currentIndex,
                  onChanged: _onRail,
                  groups: widget.railGroups,
                  footer: widget.railFooter,
                ),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: _ShellContent(
                        content: content,
                        child: Navigator(
                          key: _pages,
                          observers: <NavigatorObserver>[_routes],
                          onGenerateRoute: (RouteSettings settings) => MaterialPageRoute<void>(
                            settings: settings,
                            builder: (BuildContext context) => DesktopFrame(child: _ShellContent.of(context)),
                          ),
                        ),
                      ),
                    ),
                    if (!fullscreen) ?widget.desktopOverlay,
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: widget.backgroundColor,
      body: Stack(
        children: [
          Positioned.fill(child: content),
          NovaBottomBar(items: widget.items, currentIndex: widget.currentIndex, onChanged: widget.onChanged),
          ?widget.phoneOverlay,
        ],
      ),
    );
  }
}

/// Hands the shell's tabs to the first page of the desktop navigator, which
/// is built once: a new tab index reaches it through this inherited widget.
class _ShellContent extends InheritedWidget {
  const _ShellContent({required this.content, required super.child});

  final Widget content;

  static Widget of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ShellContent>()?.content ?? const SizedBox.shrink();

  @override
  bool updateShouldNotify(_ShellContent old) => old.content != content;
}
