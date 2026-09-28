import 'package:flutter/services.dart';

/// Player fullscreen: landscape and no system bars.
Future<void> enterPlayerFullscreen() async {
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
}

/// Back to the layout the app starts with: every orientation, both system
/// bars shown and the app laid out above the navigation bar. Restoring
/// `edgeToEdge` instead drew the app under an opaque navigation bar on
/// Android before 15, hiding the bottom tab bar after leaving a player.
Future<void> exitPlayerFullscreen() async {
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
}
