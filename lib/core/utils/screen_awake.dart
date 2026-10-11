import 'package:flutter/services.dart';

/// D-133: the screen stays on while a video plays, as on YouTube: a lesson,
/// a Live or the speaking stage holds it; pause, end or leaving releases it,
/// and the phone's normal sleep timer applies again. Native side: Android
/// `FLAG_KEEP_SCREEN_ON` on the activity window, iPhone `isIdleTimerDisabled`.
abstract final class ScreenAwake {
  static const MethodChannel _channel = MethodChannel('nova/screen');
  static final Set<Object> _holders = <Object>{};

  /// Whether something currently keeps the screen on.
  static bool get held => _holders.isNotEmpty;

  static void hold(Object holder) {
    if (_holders.add(holder) && _holders.length == 1) _set(true);
  }

  static void release(Object holder) {
    if (_holders.remove(holder) && _holders.isEmpty) _set(false);
  }

  static void _set(bool on) {
    _channel.invokeMethod<void>('keepOn', on).catchError((Object _) {
      // No native side (tests, previews): nothing to keep on.
    });
  }
}
