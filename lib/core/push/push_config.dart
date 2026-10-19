import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// D-143 (BR-M3): the Firebase project the app talks to — no
/// `google-services.json` nor `GoogleService-Info.plist` in the repository.
/// D-149: the production project `nova-b557b` is the default (these values
/// ship inside every app, they are not secrets); a `--dart-define` still
/// overrides each one:
///
///   NOVA_FCM_API_KEY, NOVA_FCM_PROJECT_ID, NOVA_FCM_SENDER_ID,
///   NOVA_FCM_APP_ID_ANDROID, NOVA_FCM_APP_ID_IOS, NOVA_FCM_STORAGE_BUCKET (optional).
///
/// An empty value turns push off for that platform: the app then behaves
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

  /// This build's values for [platform] (Firebase gives each platform its
  /// own API key).
  factory PushConfig.fromEnvironment(TargetPlatform platform) => PushConfig(
        apiKey: platform == TargetPlatform.iOS
            ? const String.fromEnvironment('NOVA_FCM_API_KEY', defaultValue: 'AIzaSyDYz58V2zoljN2hdeJ1pdhABt9sdWvB59g')
            : const String.fromEnvironment('NOVA_FCM_API_KEY', defaultValue: 'AIzaSyBLNASvIg17wwnMj7HaBHMtQlkEde1qU5o'),
        projectId: const String.fromEnvironment('NOVA_FCM_PROJECT_ID', defaultValue: 'nova-b557b'),
        senderId: const String.fromEnvironment('NOVA_FCM_SENDER_ID', defaultValue: '626629111453'),
        appIdAndroid: const String.fromEnvironment(
          'NOVA_FCM_APP_ID_ANDROID',
          defaultValue: '1:626629111453:android:854aa19d12a032685e6e74',
        ),
        appIdIos: const String.fromEnvironment(
          'NOVA_FCM_APP_ID_IOS',
          defaultValue: '1:626629111453:ios:9220f1b8392bbccd5e6e74',
        ),
        storageBucket: const String.fromEnvironment(
          'NOVA_FCM_STORAGE_BUCKET',
          defaultValue: 'nova-b557b.firebasestorage.app',
        ),
      );

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
