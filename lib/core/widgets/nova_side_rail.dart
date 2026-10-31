import 'package:flutter/material.dart';

import '../theme/nova_colors.dart';
import '../theme/nova_typography.dart';
import '../desktop/desktop_layout.dart';
import 'nova_bottom_bar.dart';

/// D-188, PC app: the phone's bottom bar as a desktop sidebar — the same
/// destinations, in the same navy (`.studentBottomNav`) with the yellow
/// active marker, each a 20 px icon beside its label, with a hover state and
/// the hand cursor. At the window's start edge (the right in Arabic).
class NovaSideRail extends StatelessWidget {
  const NovaSideRail({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onChanged,
  });

  final List<NovaNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final double top = MediaQuery.paddingOf(context).top;
    return Container(
      width: DesktopMetrics.railWidth,
      color: NovaColors.ink950,
      padding: EdgeInsets.fromLTRB(14, top + 18, 14, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 6, bottom: 22),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
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
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: 4),
            _RailItem(item: items[i], active: i == currentIndex, onTap: () => onChanged(i)),
          ],
        ],
      ),
    );
  }
}

class _RailItem extends StatefulWidget {
  const _RailItem({required this.item, required this.active, required this.onTap});

  final NovaNavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bool active = widget.active;
    final Color ink = active ? NovaColors.yellowInk : Colors.white.withValues(alpha: _hover ? 0.95 : 0.74);
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
            height: 44,
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
  });

  final List<NovaNavItem> items;
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

  @override
  Widget build(BuildContext context) {
    final Widget content = KeyedSubtree(key: _content, child: widget.content);
    if (desktopLayoutOf(context)) {
      return Scaffold(
        backgroundColor: widget.backgroundColor,
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NovaSideRail(items: widget.items, currentIndex: widget.currentIndex, onChanged: widget.onChanged),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: DesktopFrame(child: content)),
                  ?widget.desktopOverlay,
                ],
              ),
            ),
          ],
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
