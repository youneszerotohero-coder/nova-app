import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';

import 'push_platform.dart';

/// The NOVA PC app's notifications (owner decision 2026-10-29).
///
/// Firebase Cloud Messaging does not exist on Windows, so no token is
/// registered with the server. What the app already receives over its
/// realtime connection (Reverb: notifications and chat messages, shown by
/// [NotificationBannerHost] and [ChatNoticeHost]) is also shown as a Windows
/// notification while NOVA is not the window in use ([showIfAway]); a click
/// opens it exactly like a tapped phone notification ([PushTapRouter]).
/// Nothing arrives while the app is closed: there is no server push on PC.
class WindowsPushPlatform implements PushPlatform {
  WindowsPushPlatform._({FlutterLocalNotificationsPlugin? plugin})
      : _local = plugin ?? FlutterLocalNotificationsPlugin();

  /// The running PC app's notifications; null elsewhere (phones, tests).
  static final WindowsPushPlatform? instance =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows ? WindowsPushPlatform._() : null;

  /// Same as the Start menu shortcut's AppUserModelID (installer).
  static const String appUserModelId = 'NovaElearning.NOVA';

  /// The notification activation callback's identifier (fixed for NOVA).
  static const String activatorGuid = '430ea789-52da-4752-b2b8-942e27a9189c';

  static const MethodChannel _appInfo = MethodChannel('nova/app_update');

  final FlutterLocalNotificationsPlugin _local;
  final StreamController<PushPayload> _opened = StreamController<PushPayload>.broadcast();
  bool _ready = false;
  PushPayload? _launch;
  int _nextId = 1;

  @override
  String get platformName => 'windows';

  @override
  Future<void> initialize() async {
    await _local.initialize(
      settings: const InitializationSettings(
        windows: WindowsInitializationSettings(
          appName: 'NOVA',
          appUserModelId: appUserModelId,
          guid: activatorGuid,
        ),
      ),
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final PushPayload? payload = _decode(response.payload);
        if (payload != null) _opened.add(payload);
      },
    );
    final NotificationAppLaunchDetails? launch = await _local.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      _launch = _decode(launch!.notificationResponse?.payload);
    }
    _ready = true;
  }

  /// Shows [payload] as a Windows notification when the NOVA window is not
  /// the one in use (minimized, behind another window); otherwise the
  /// in-app banner that already shows it is enough. True when a Windows
  /// notification was shown (it has its own sound).
  static bool showIfAway(PushPayload payload) {
    final WindowsPushPlatform? platform = instance;
    if (platform == null || !platform._ready) return false;
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) return false;
    platform._show(payload);
    return true;
  }

  Future<void> _show(PushPayload payload) async {
    try {
      await _local.show(
        id: _nextId++,
        title: payload.title,
        body: payload.body,
        notificationDetails: const NotificationDetails(windows: WindowsNotificationDetails()),
        payload: jsonEncode(payload.data),
      );
    } catch (_) {
      // Notifications turned off for NOVA in Windows: the banner showed it.
    }
  }

  // Windows decides in its own Settings; there is nothing to ask.
  @override
  Future<void> nameChannels({required String messages, required String general}) async {}

  @override
  Future<PushPermission> permission() async => PushPermission.granted;

  @override
  Future<PushPermission> requestPermission() async => PushPermission.granted;

  @override
  Future<void> openSettings() async {
    await launchUrl(Uri.parse('ms-settings:notifications'));
  }

  // No server push on PC: no token to register.
  @override
  Future<String?> token() async => null;

  @override
  Future<void> deleteToken() async {}

  @override
  Stream<String> get tokenRefreshes => const Stream<String>.empty();

  @override
  Stream<PushPayload> get foregroundMessages => const Stream<PushPayload>.empty();

  @override
  Stream<PushPayload> get openedMessages => _opened.stream;

  @override
  Future<PushPayload?> launchMessage() async {
    final PushPayload? launch = _launch;
    _launch = null;
    return launch;
  }

  @override
  Future<String> appVersion() async {
    try {
      final Map<String, dynamic>? info = await _appInfo.invokeMapMethod<String, dynamic>('version');
      return '${info?['version'] ?? ''}';
    } on PlatformException {
      return '';
    } on MissingPluginException {
      return '';
    }
  }

  static PushPayload? _decode(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final Object? data = jsonDecode(payload);
      return data is Map<String, dynamic> ? PushPayload.fromData(data) : null;
    } on FormatException {
      return null;
    }
  }
}
