import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// D-143 (BR-M3): the Firebase project the app talks to, given at build time
/// with `--dart-define`s — no `google-services.json` nor
/// `GoogleService-Info.plist` in the repository:
///
///   NOVA_FCM_API_KEY, NOVA_FCM_PROJECT_ID, NOVA_FCM_SENDER_ID,
///   NOVA_FCM_APP_ID_ANDROID, NOVA_FCM_APP_ID_IOS, NOVA_FCM_STORAGE_BUCKET (optional).
///
/// A missing value turns push off for that platform: the app then behaves
/// exactly as before (in-app notifications over Reverb only).
@immutable
class PushConfig {
  const PushConfig({
    this.apiKey = '',
    this.projectId = '',
    this.senderId = '',
    this.appIdAndroid = '',
    this.appIdIos = '',
    this.storageBucket = '',
  });

  const PushConfig.fromEnvironment()
      : apiKey = const String.fromEnvironment('NOVA_FCM_API_KEY'),
        projectId = const String.fromEnvironment('NOVA_FCM_PROJECT_ID'),
        senderId = const String.fromEnvironment('NOVA_FCM_SENDER_ID'),
        appIdAndroid = const String.fromEnvironment('NOVA_FCM_APP_ID_ANDROID'),
        appIdIos = const String.fromEnvironment('NOVA_FCM_APP_ID_IOS'),
        storageBucket = const String.fromEnvironment('NOVA_FCM_STORAGE_BUCKET');

  final String apiKey;
  final String projectId;
  final String senderId;
  final String appIdAndroid;
  final String appIdIos;
  final String storageBucket;

  /// The options for [platform], or null when push is off there.
  FirebaseOptions? optionsFor(TargetPlatform platform) {
    final String appId = switch (platform) {
      TargetPlatform.android => appIdAndroid,
      TargetPlatform.iOS => appIdIos,
      _ => '',
    };
    if (<String>[apiKey, projectId, senderId, appId].any((String value) => value.trim().isEmpty)) {
      return null;
    }
    return FirebaseOptions(
      apiKey: apiKey.trim(),
      appId: appId.trim(),
      messagingSenderId: senderId.trim(),
      projectId: projectId.trim(),
      storageBucket: storageBucket.trim().isEmpty ? null : storageBucket.trim(),
    );
  }
}
