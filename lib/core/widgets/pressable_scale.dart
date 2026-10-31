import 'package:flutter/material.dart';

import '../desktop/desktop_layout.dart';

/// Wraps any tappable content with the gentle press-down scale
/// the visual direction implies for card-like surfaces. D-188, PC app: the
/// hand cursor and a 2 px lift while the mouse is over it.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.97,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;
  final String? semanticLabel;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onTap != null;
    final Widget pressable = _pressable(enabled);
    if (!isDesktopApp) return pressable;
    final bool lifted = enabled && _hover && !_pressed;
    // The same widgets whether enabled or not, so the content keeps its state.
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      // A translation only: no repaint of the content, no off-screen layer.
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, lifted ? -2 : 0, 0),
        child: pressable,
      ),
    );
  }

  Widget _pressable(bool enabled) {
    return Semantics(
      container: true,
      button: enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        // The whole box answers, not only its painted pixels (an icon
        // glyph, a line of text): no more second taps.
        behavior: enabled ? HitTestBehavior.opaque : null,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? widget.pressedScale : 1,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}
