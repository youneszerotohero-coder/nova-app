import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'push_config.dart';
import 'push_platform.dart';

/// Firebase's background entry point: the system already shows the
/// notification payloads, so nothing heavy runs here (D-143).
@pragma('vm:entry-point')
Future<void> novaPushBackgroundHandler(RemoteMessage message) async {}

/// [PushPlatform] over Firebase Cloud Messaging, with the local
/// notifications plugin for the Android channels and local notification
/// taps. Built only when the `--dart-define` options exist ([fromEnvironment]).
///
/// The FCM registration token (`getToken`, `onTokenRefresh`,
/// `deleteToken`) is what the backend sends to (HTTP v1 `message.token`);
/// firebase_messaging 17 deprecates it for installation ids, hence the
/// `deprecated_member_use` ignores below.
class FirebasePushPlatform implements PushPlatform {
  FirebasePushPlatform(this.options);

  /// The platform for this build, or null when its options are missing.
  static FirebasePushPlatform? fromEnvironment() {
    if (kIsWeb) return null;
    final FirebaseOptions? options = const PushConfig.fromEnvironment().optionsFor(defaultTargetPlatform);
    return options == null ? null : FirebasePushPlatform(options);
  }

  final FirebaseOptions options;

  /// Chat messages: high importance, sound (BR-C9).
  static const String messagesChannel = 'nova_messages';

  /// Everything else (new Lesson, Lives, CCP, points…); the manifest's
  /// default channel for messages that name none.
  static const String generalChannel = 'nova_general';

  static const MethodChannel _appInfo = MethodChannel('nova/app_update');

  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  final StreamController<PushPayload> _opened = StreamController<PushPayload>.broadcast();
  PushPayload? _localLaunch;

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  @override
  String get platformName => defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  @override
  Future<void> initialize() async {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp(options: options);
    FirebaseMessaging.onBackgroundMessage(novaPushBackgroundHandler);
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) => _opened.add(_payload(message)));
    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_nova'),
        // The app asks itself, after its explanation (PushService).
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final PushPayload? payload = _decode(response.payload);
        if (payload != null) _opened.add(payload);
      },
    );
    await nameChannels(messages: 'Messages', general: 'NOVA');
    final NotificationAppLaunchDetails? launch = await _local.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      _localLaunch = _decode(launch!.notificationResponse?.payload);
    }
  }

  @override
  Future<void> nameChannels({required String messages, required String general}) async {
    final AndroidFlutterLocalNotificationsPlugin? android =
        _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    // Creating a channel again only renames it; the user's own choices stay.
    await android.createNotificationChannel(AndroidNotificationChannel(
      messagesChannel,
      messages,
      importance: Importance.high,
    ));
    await android.createNotificationChannel(AndroidNotificationChannel(
      generalChannel,
      general,
    ));
  }

  @override
  Future<PushPermission> permission() async =>
      _permission((await _messaging.getNotificationSettings()).authorizationStatus);

  @override
  Future<PushPermission> requestPermission() async =>
      _permission((await _messaging.requestPermission()).authorizationStatus);

  @override
  Future<void> openSettings() async {
    await _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.openAppNotificationSettings();
    await _local.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.openAppNotificationSettings();
  }

  @override
  Future<String?> token() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // The FCM token needs the APNs one, which may land a moment after launch.
      for (int attempt = 0; attempt < 5 && await _messaging.getAPNSToken() == null; attempt++) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    // ignore: deprecated_member_use
    return _messaging.getToken();
  }

  @override
  // ignore: deprecated_member_use
  Future<void> deleteToken() => _messaging.deleteToken();

  @override
  // ignore: deprecated_member_use
  Stream<String> get tokenRefreshes => _messaging.onTokenRefresh;

  @override
  Stream<PushPayload> get foregroundMessages => FirebaseMessaging.onMessage.map(_payload);

  @override
  Stream<PushPayload> get openedMessages => _opened.stream;

  @override
  Future<PushPayload?> launchMessage() async {
    final RemoteMessage? message = await _messaging.getInitialMessage();
    if (message != null) return _payload(message);
    final PushPayload? local = _localLaunch;
    _localLaunch = null;
    return local;
  }

  @override
  Future<String> appVersion() async {
    try {
      final Map<String, dynamic>? info = await _appInfo.invokeMapMethod<String, dynamic>('version');
      final String version = '${info?['version'] ?? ''}';
      final String build = '${info?['build'] ?? ''}';
      if (version.isEmpty) return '';
      return build.isEmpty ? version : '$version+$build';
    } on PlatformException {
      return '';
    } on MissingPluginException {
      return '';
    }
  }

  static PushPayload _payload(RemoteMessage message) => PushPayload.fromData(
        message.data,
        title: message.notification?.title,
        body: message.notification?.body,
        messageId: message.messageId,
      );

  static PushPayload? _decode(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final Object? data = jsonDecode(payload);
      return data is Map<String, dynamic> ? PushPayload.fromData(data) : null;
    } on FormatException {
      return null;
    }
  }

  static PushPermission _permission(AuthorizationStatus status) => switch (status) {
        AuthorizationStatus.authorized || AuthorizationStatus.provisional => PushPermission.granted,
        AuthorizationStatus.notDetermined => PushPermission.unknown,
        AuthorizationStatus.denied => PushPermission.denied,
        AuthorizationStatus.deniedPermanently => PushPermission.blocked,
      };
}
