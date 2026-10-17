import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../features/account/notifications_screen.dart';
import '../../features/messages/chat_room_screen.dart';
import '../state/app_state.dart';
import 'push_platform.dart';

/// D-143 (BR-M2): a tapped system notification opens its screen over the
/// signed-in space — a chat message its chat, anything else the
/// notifications (and, like a tap in that list, the Lesson or Live it
/// names). A tap that launched the app waits until the space shows
/// ([PushHost] attaches the navigator after the sign-in steps).
class PushTapRouter {
  PushPayload? _pending;
  Object? _host;
  AppState? _app;
  NavigatorState? _navigator;

  /// The tap waiting for the signed-in space, if any.
  PushPayload? get pending => _pending;

  void open(PushPayload payload) {
    _pending = payload;
    _flush();
  }

  /// The signed-in space shows: [navigator] opens taps from now on.
  void attach(Object host, AppState app, NavigatorState navigator) {
    _host = host;
    _app = app;
    _navigator = navigator;
    _flush();
  }

  void detach(Object host) {
    if (!identical(_host, host)) return;
    _host = null;
    _app = null;
    _navigator = null;
  }

  /// Signed out: a tap meant for that account is dropped.
  void clear() => _pending = null;

  void _flush() {
    final PushPayload? payload = _pending;
    final AppState? app = _app;
    final NavigatorState? navigator = _navigator;
    if (payload == null || app == null || navigator == null || !navigator.mounted || !app.session.signedIn) return;
    _pending = null;
    openPushTap(app, navigator, payload);
  }
}

/// Opens [payload]'s screen on [navigator].
Future<void> openPushTap(AppState app, NavigatorState navigator, PushPayload payload) async {
  if (payload.isChat) {
    final int? roomId = payload.roomId;
    if (roomId != null) {
      navigator.push(MaterialPageRoute<void>(builder: (_) => ChatRoomScreen(roomId: roomId)));
    }
    return;
  }
  navigator.push(MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()));
  final String? id = payload.notificationId;
  if (id == null) return;
  await app.account.refreshNotifications();
  if (!navigator.mounted) return;
  final AppNotification? notification =
      app.account.notifications.where((AppNotification n) => n.id == id).firstOrNull;
  if (notification != null) openNotification(app, navigator, notification);
}
