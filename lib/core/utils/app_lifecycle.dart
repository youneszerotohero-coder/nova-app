import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Whether [state] means NOVA left the screen, so a video pauses: on a
/// phone any state but `resumed` (another app, the switcher, a call); in the
/// PC app only a minimized or closing window — another window taking the
/// focus (`inactive`) leaves the video playing, as in any desktop player.
bool leftScreen(AppLifecycleState state, {TargetPlatform? platform}) {
  final bool desktop = !kIsWeb && (platform ?? defaultTargetPlatform) == TargetPlatform.windows;
  if (!desktop) return state != AppLifecycleState.resumed;
  return state == AppLifecycleState.hidden ||
      state == AppLifecycleState.paused ||
      state == AppLifecycleState.detached;
}
