import 'dart:async';

import 'package:nova_mobile/core/push/push_platform.dart';
import 'package:nova_mobile/core/push/push_service.dart';

/// The phone's push system without Firebase: a permission the test sets, a
/// token, and the message streams the test drives.
class FakePushPlatform implements PushPlatform {
  FakePushPlatform({this.status = PushPermission.unknown, this.answer = PushPermission.granted, this.currentToken = 'fcm-token-1'});

  /// What the phone allows now.
  PushPermission status;

  /// What the system prompt answers.
  PushPermission answer;
  String? currentToken;
  PushPayload? launch;

  int prompts = 0;
  int deletes = 0;
  int settingsOpened = 0;
  final List<String> calls = <String>[];

  final StreamController<String> refreshes = StreamController<String>.broadcast();
  final StreamController<PushPayload> foreground = StreamController<PushPayload>.broadcast();
  final StreamController<PushPayload> opened = StreamController<PushPayload>.broadcast();

  @override
  String get platformName => 'android';

  @override
  Future<void> initialize() async => calls.add('initialize');

  @override
  Future<void> nameChannels({required String messages, required String general}) async =>
      calls.add('channels:$messages|$general');

  @override
  Future<PushPermission> permission() async => status;

  @override
  Future<PushPermission> requestPermission() async {
    prompts++;
    return status = answer;
  }

  @override
  Future<void> openSettings() async => settingsOpened++;

  @override
  Future<String?> token() async => currentToken;

  @override
  Future<void> deleteToken() async {
    deletes++;
    calls.add('deleteToken');
    currentToken = 'fcm-token-${deletes + 1}';
  }

  @override
  Stream<String> get tokenRefreshes => refreshes.stream;

  @override
  Stream<PushPayload> get foregroundMessages => foreground.stream;

  @override
  Stream<PushPayload> get openedMessages => opened.stream;

  @override
  Future<PushPayload?> launchMessage() async {
    final PushPayload? message = launch;
    launch = null;
    return message;
  }

  @override
  Future<String> appVersion() async => '0.3.0+15';
}

class MemoryPushFlags implements PushFlags {
  bool value = false;

  @override
  Future<bool> asked() async => value;

  @override
  Future<void> markAsked() async => value = true;
}
