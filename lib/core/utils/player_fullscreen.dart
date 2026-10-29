import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// PC app: the window itself goes full screen (`nova/screen`, the runner's
/// nova_platform.cpp); phones have no window to resize.
bool get _windowsApp => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

Future<void> _windowFullscreen(bool on) async {
  try {
    await const MethodChannel('nova/screen').invokeMethod<void>('fullscreen', on);
  } on PlatformException {
    // The window keeps its size; the player still fills it.
  } on MissingPluginException {
    // Same.
  }
}

/// Player fullscreen: landscape and no system bars.
Future<void> enterPlayerFullscreen() async {
  if (_windowsApp) return _windowFullscreen(true);
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
  if (_windowsApp) return _windowFullscreen(false);
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
}
