import 'package:flutter/foundation.dart';

/// Whether the phone lets NOVA show system notifications.
enum PushPermission {
  /// Not asked yet (or unknown before Firebase starts).
  unknown,

  /// Allowed (iOS "provisional" included).
  granted,

  /// Refused; the system may still ask again (Android 13+).
  denied,

  /// Refused for good: only the phone's settings can allow it.
  blocked,
}

/// One Firebase message (D-143 §3.6): `data` carries the routing keys
/// (`type`, `room_id` or `notification_id`, `route`); [title] and [body] are
/// the system notification's text, written by the server.
@immutable
class PushPayload {
  const PushPayload({required this.data, this.title, this.body, this.messageId});

  /// Reads a local notification's payload or an FCM data map.
  factory PushPayload.fromData(Map<String, Object?> data, {String? title, String? body, String? messageId}) =>
      PushPayload(
        data: <String, String>{
          for (final MapEntry<String, Object?> entry in data.entries)
            if (entry.value != null) entry.key: '${entry.value}',
        },
        title: title,
        body: body,
        messageId: messageId,
      );

  final Map<String, String> data;
  final String? title;
  final String? body;
  final String? messageId;

  static const String chatMessage = 'chat_message';

  String get type => data['type'] ?? '';
  bool get isChat => type == chatMessage;

  /// The chat a `chat_message` push belongs to.
  int? get roomId => int.tryParse(data['room_id'] ?? '');

  /// The database notification a non-chat push announces.
  String? get notificationId {
    final String? id = data['notification_id'];
    return id == null || id.isEmpty ? null : id;
  }
}

/// The phone's push system behind one seam (Firebase Cloud Messaging and the
/// local notifications plugin in the app, a fake in tests), so
/// [PushService] holds every rule and stays testable.
abstract class PushPlatform {
  /// `android` | `ios`, as `POST /me/devices` expects it.
  String get platformName;

  /// Starts Firebase and creates the Android channels; throws when the
  /// platform cannot run push (push then stays off).
  Future<void> initialize();

  /// Names the Android channels in the app language.
  Future<void> nameChannels({required String messages, required String general});

  Future<PushPermission> permission();

  /// Shows the system prompt (Android 13+ `POST_NOTIFICATIONS`, iOS alert,
  /// badge and sound) when the system still allows it.
  Future<PushPermission> requestPermission();

  /// Opens the phone's notification settings for NOVA.
  Future<void> openSettings();

  /// The FCM registration token, null when unavailable.
  Future<String?> token();

  /// Invalidates this phone's token (a new one comes on the next [token]).
  Future<void> deleteToken();

  Stream<String> get tokenRefreshes;

  /// Messages received while the app is in the foreground.
  Stream<PushPayload> get foregroundMessages;

  /// System or local notifications tapped while the app was running.
  Stream<PushPayload> get openedMessages;

  /// The notification whose tap launched the app, once.
  Future<PushPayload?> launchMessage();

  /// `X.Y.Z+build` of the installed app, empty when unknown.
  Future<String> appVersion();
}
