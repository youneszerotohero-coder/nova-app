import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../i18n/nova_strings.dart';
import '../state/app_state.dart';
import '../theme/nova_colors.dart';
import '../theme/nova_typography.dart';
import 'hero_style.dart';
import 'pressable_scale.dart';

/// One destination of the menu.
class NovaMenuEntry {
  const NovaMenuEntry({required this.icon, required this.label, required this.onTap, this.active = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// The page the Student is on (blue row with the yellow dot).
  final bool active;
}

/// A labelled group of destinations (`.studentNav > div`).
class NovaMenuGroup {
  const NovaMenuGroup({required this.label, required this.entries});

  final String label;
  final List<NovaMenuEntry> entries;
}

/// Opens the menu: the website's Student sidebar (`StudentSidebar`,
/// `profile.tsx`; `dashboard.css`) docked to the reading-start edge (the
/// right in Arabic) over a dim backdrop. Each entry closes the menu first,
/// then runs. A signed-in Student gets the help row ([onHelp]) and sign out
/// ([onSignOut]); a visitor (D-134) gets "Sign in" ([onSignIn]) and "Create
/// my account" ([onRegister]) instead.
Future<void> showNovaMenu(
  BuildContext context, {
  required List<NovaMenuGroup> groups,
  VoidCallback? onHelp,
  VoidCallback? onSignOut,
  VoidCallback? onSignIn,
  VoidCallback? onRegister,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: context.tr('menu.close'),
    // `.studentNavBackdrop`: rgba(23, 25, 29, .38).
    barrierColor: const Color(0x6117191D),
    transitionDuration: const Duration(milliseconds: 400),
    transitionBuilder: (BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
      // `.studentSidebar`: translateX(±104 %) → 0, cubic-bezier(.16, 1, .3, 1).
      final Animation<double> curved = CurvedAnimation(
        parent: animation,
        curve: const Cubic(0.16, 1, 0.3, 1),
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        // Flips the x offset in RTL, so the panel enters from the right edge
        // it is docked to.
        textDirection: Directionality.of(context),
        position: Tween<Offset>(begin: const Offset(-1.04, 0), end: Offset.zero).animate(curved),
        child: child,
      );
    },
    pageBuilder: (BuildContext context, _, _) => _MenuPanel(
      groups: groups,
      onHelp: onHelp,
      onSignOut: onSignOut,
      onSignIn: onSignIn,
      onRegister: onRegister,
    ),
  );
}

class _MenuPanel extends StatefulWidget {
  const _MenuPanel({required this.groups, this.onHelp, this.onSignOut, this.onSignIn, this.onRegister});

  final List<NovaMenuGroup> groups;
  final VoidCallback? onHelp;
  final VoidCallback? onSignOut;
  final VoidCallback? onSignIn;
  final VoidCallback? onRegister;

  /// `.studentSidebar` width.
  static const double width = 258;

  @override
  State<_MenuPanel> createState() => _MenuPanelState();
}

class _MenuPanelState extends State<_MenuPanel> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 540))
    ..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Closes the menu, then goes where the row leads.
  VoidCallback _run(VoidCallback action) => () {
        Navigator.of(context).pop();
        action();
      };

  @override
  Widget build(BuildContext context) {
    final bool rtl = Directionality.of(context) == TextDirection.rtl;
    final EdgeInsets safe = MediaQuery.paddingOf(context);
    int row = 0;
    Widget stagger(Widget child) => _Stagger(controller: _controller, start: 0.1 + 0.06 * row++, child: child);

    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          width: _MenuPanel.width,
          height: double.infinity,
          padding: EdgeInsets.fromLTRB(17, safe.top + 24, 17, safe.bottom + 18),
          decoration: BoxDecoration(
            color: NovaColors.paperCard,
            border: BorderDirectional(end: BorderSide(color: NovaColors.borderOnLight)),
            boxShadow: [BoxShadow(offset: Offset(rtl ? -22 : 22, 0), blurRadius: 60, color: const Color(0x2E22262F))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _BrandRow(onClose: () => Navigator.of(context).pop()),
              const SizedBox(height: 22),
              Expanded(
                child: _StretchedNav(
                  children: [
                    for (int g = 0; g < widget.groups.length; g++) ...[
                      if (g > 0) const _NavGap(),
                      _NavTrack(label: true, child: stagger(_GroupLabel(widget.groups[g].label))),
                      for (final NovaMenuEntry entry in widget.groups[g].entries)
                        _NavTrack(child: stagger(_MenuRow(entry: entry, onTap: _run(entry.onTap)))),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // App only: the language (the website's floating switcher; the
              // theme is in the top bar), where the website has its push box.
              stagger(const _LanguageRow()),
              if (widget.onHelp != null) ...[
                const SizedBox(height: 10),
                stagger(_HelpRow(onTap: _run(widget.onHelp!))),
              ],
              if (widget.onSignOut != null) ...[
                const SizedBox(height: 10),
                stagger(_SignOutRow(onTap: _run(widget.onSignOut!))),
              ],
              if (widget.onSignIn != null) ...[
                const SizedBox(height: 12),
                stagger(
                  NovaButton(
                    label: context.tr('guest.signIn'),
                    chipIcon: Icons.arrow_forward_rounded,
                    expand: true,
                    small: true,
                    onTap: _run(widget.onSignIn!),
                  ),
                ),
              ],
              if (widget.onRegister != null) ...[
                const SizedBox(height: 8),
                stagger(
                  NovaButton(
                    label: context.tr('gateway.registerCta'),
                    variant: NovaButtonVariant.ghost,
                    expand: true,
                    small: true,
                    onTap: _run(widget.onRegister!),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// `.studentBrandRow`: the NOVA wordmark and the close square.
class _BrandRow extends StatelessWidget {
  const _BrandRow({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(9, 4, 9, 16),
      child: Row(
        children: [
          // `.studentBrandFull`: always "NOVA." in LTR, the N in blue, the dot
          // sitting on the baseline.
          Text.rich(
            TextSpan(
              style: TextStyle(fontFamily: NovaTypography.display, fontWeight: FontWeight.w800, fontSize: 22, height: 1, color: NovaColors.textStrong),
              children: [
                TextSpan(text: 'N', style: TextStyle(fontSize: 26, color: NovaColors.accent)),
                const TextSpan(text: 'OVA'),
                const WidgetSpan(
                  alignment: PlaceholderAlignment.aboveBaseline,
                  baseline: TextBaseline.alphabetic,
                  child: Padding(
                    padding: EdgeInsets.only(left: 2, bottom: 2),
                    child: SizedBox.square(
                      dimension: 5,
                      child: DecoratedBox(decoration: BoxDecoration(color: NovaColors.skyStrong, shape: BoxShape.circle)),
                    ),
                  ),
                ),
              ],
            ),
            textDirection: TextDirection.ltr,
          ),
          const Spacer(),
          PressableScale(
            onTap: onClose,
            pressedScale: 0.92,
            semanticLabel: context.tr('menu.close'),
            child: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: NovaColors.paperRaised, borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.close_rounded, size: 18, color: NovaColors.textStrong),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Language" and the website's language pills (`LanguageSwitcher`
/// `pills`: FR, AR, EN; the active one blue).
class _LanguageRow extends StatelessWidget {
  const _LanguageRow();

  @override
  Widget build(BuildContext context) {
    final AppState app = AppScope.of(context);
    final bool dark = NovaColors.current.isDark;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 12),
      child: Row(
        children: [
          Expanded(child: _GroupLabel(context.tr('menu.language'), padded: false)),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: dark ? const Color(0x1AFFFFFF) : const Color(0x0D000000),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: dark ? const Color(0x1FFFFFFF) : const Color(0x14000000)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final NovaLang lang in const <NovaLang>[NovaLang.fr, NovaLang.ar, NovaLang.en]) ...[
                  if (lang != NovaLang.fr) const SizedBox(width: 3),
                  PressableScale(
                    onTap: () => app.setLang(lang),
                    pressedScale: 0.94,
                    semanticLabel: lang.label,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 40, minHeight: 32),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: app.lang == lang ? const Color(0xFF1E66F5) : null,
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: app.lang == lang
                            ? const [BoxShadow(offset: Offset(0, 1), blurRadius: 4, color: Color(0x401E66F5))]
                            : null,
                      ),
                      child: Text(
                        lang.name.toUpperCase(),
                        style: TextStyle(
                          fontFamily: NovaTypography.body,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          height: 1.2,
                          color: app.lang == lang
                              ? Colors.white
                              : dark
                                  ? const Color(0xB3FFFFFF)
                                  : const Color(0xFF52565E),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// `.studentNavLabel`: mute, 13 px Baloo 800.
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text, {this.padded = true});

  final String text;
  final bool padded;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padded ? const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 7) : EdgeInsets.zero,
      child: Text(
        text,
        style: TextStyle(
          fontFamily: NovaTypography.display,
          fontFamilyFallback: NovaTypography.fallback,
          fontWeight: FontWeight.w800,
          fontSize: 13,
          height: 1.3,
          color: NovaColors.textMuted,
        ),
      ),
    );
  }
}

/// `.studentNav a`: 20 px icon and the label, ink-2 Baloo 700 16 px; the
/// open page is blue with white text, its shadow and the yellow dot.
class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.entry, required this.onTap});

  final NovaMenuEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool active = entry.active;
    final Color ink = active ? Colors.white : NovaColors.textBody;
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.97,
      semanticLabel: entry.label,
      child: Container(
        constraints: const BoxConstraints(minHeight: 50),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: active ? NovaColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(15),
          boxShadow: active
              ? const [BoxShadow(offset: Offset(0, 12), blurRadius: 22, spreadRadius: -16, color: Color(0xE61F54D6))]
              : null,
        ),
        child: Row(
          children: [
            Icon(entry.icon, size: 20, color: ink),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                entry.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: NovaTypography.display,
                  fontFamilyFallback: NovaTypography.fallback,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  height: 1.3,
                  color: ink,
                ),
              ),
            ),
            if (active)
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(color: NovaColors.yellow, shape: BoxShape.circle),
              ),
          ],
        ),
      ),
    );
  }
}

/// `.sidebarSupport`: the yellow tilted tile, "Need help?" and its line.
class _HelpRow extends StatelessWidget {
  const _HelpRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool rtl = Directionality.of(context) == TextDirection.rtl;
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.97,
      semanticLabel: context.tr('menu.needHelp'),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Transform.rotate(
              angle: -0.1047,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: NovaColors.yellow, borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.auto_awesome_outlined, size: 17, color: NovaColors.yellowInk),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('menu.needHelp'),
                    style: TextStyle(
                      fontFamily: NovaTypography.display,
                      fontFamilyFallback: NovaTypography.fallback,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      height: 1.3,
                      color: NovaColors.textStrong,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.tr('menu.talkTeam'),
                    style: TextStyle(
                      fontFamily: NovaTypography.body,
                      fontFamilyFallback: NovaTypography.fallback,
                      fontSize: 13,
                      height: 1.3,
                      color: NovaColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(rtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded, size: 18, color: NovaColors.textBody),
          ],
        ),
      ),
    );
  }
}

/// `.sidebarSignOut`: a hairline-bordered row in the danger colour.
class _SignOutRow extends StatelessWidget {
  const _SignOutRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.97,
      semanticLabel: context.tr('menu.signOut'),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: NovaColors.borderOnLight),
        ),
        child: Row(
          children: [
            Icon(Icons.logout_rounded, size: 20, color: NovaColors.heartRed),
            const SizedBox(width: 12),
            Text(
              context.tr('menu.signOut'),
              style: TextStyle(
                fontFamily: NovaTypography.display,
                fontFamilyFallback: NovaTypography.fallback,
                fontWeight: FontWeight.w800,
                fontSize: 15,
                height: 1.3,
                color: NovaColors.heartRed,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A row of the website's nav grid; a label keeps its text at the top.
class _NavTrack extends StatelessWidget {
  const _NavTrack({required this.child, this.label = false});

  final Widget child;
  final bool label;

  @override
  Widget build(BuildContext context) => child;
}

/// The 20 px gap between two groups.
class _NavGap extends StatelessWidget {
  const _NavGap();

  @override
  Widget build(BuildContext context) => const SizedBox(height: 16);
}

/// `.studentNav` is a grid that fills the sidebar's height: when there is
/// room, every row grows by the same share (the rows of the website's phone
/// menu are taller than their 50 px), the rest stays under the last group;
/// otherwise the list scrolls.
class _StretchedNav extends StatelessWidget {
  const _StretchedNav({required this.children});

  final List<Widget> children;

  /// Height of the rows before they grow: 50 px links (4 px apart), 24 px
  /// labels, 16 px between groups.
  static double _natural(Widget w) => switch (w) {
        _NavGap() => 16,
        _NavTrack(label: true) => 24,
        _ => 54,
      };

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final double natural = children.fold(0, (double sum, Widget w) => sum + _natural(w));
        final int tracks = children.whereType<_NavTrack>().length;
        if (box.maxHeight.isInfinite || natural >= box.maxHeight || tracks == 0) {
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              for (final Widget w in children)
                w is _NavTrack && !w.label ? Padding(padding: const EdgeInsets.only(bottom: 4), child: w) : w,
            ],
          );
        }
        // At most 24 px more a row: a short menu (a visitor's) stays compact.
        final double grow = math.min(24, (box.maxHeight - natural) / tracks);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final Widget w in children)
              if (w is _NavTrack)
                SizedBox(
                  height: _natural(w) + grow,
                  child: w.label
                      ? Align(alignment: AlignmentDirectional.topStart, child: w)
                      : Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: SizedBox.expand(child: w),
                        ),
                )
              else
                w,
          ],
        );
      },
    );
  }
}

/// Fades and slides a row in as the menu opens.
class _Stagger extends StatelessWidget {
  const _Stagger({required this.controller, required this.start, required this.child});

  final Animation<double> controller;
  final double start;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Animation<double> animation = CurvedAnimation(
      parent: controller,
      curve: Interval(start.clamp(0.0, 0.6), (start + 0.4).clamp(0.0, 1.0), curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        textDirection: Directionality.of(context),
        position: Tween<Offset>(begin: const Offset(-0.15, 0), end: Offset.zero).animate(animation),
        child: child,
      ),
    );
  }
}
