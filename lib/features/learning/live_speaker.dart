// LiveKit's audio-session API is marked experimental; it is the supported
// way to set the iPhone session the accepted speaker needs.
// ignore_for_file: experimental_member_use

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../data/live_store.dart';

/// The accepted Student's microphone in the Live (web `useLiveRoom`,
/// Student role): LiveKit with the microphone only — the backend grant
/// allows no camera — echo cancellation, noise suppression and gain
/// control on. One automatic reconnect after 750 ms, then [onDropped].
///
/// While speaking, the protected broadcast is released (D-066) and the
/// Student watches and hears the Professor over this connection
/// ([presenterVideo], D-073).
class LiveSpeaker {
  LiveSpeaker({required this.onDropped});

  /// The connection is gone for good; the room lowers the hand and
  /// returns the Student to the broadcast.
  final void Function() onDropped;

  /// Bumped whenever a remote track appears, disappears or is muted, so
  /// the stage rebuilds.
  final ValueNotifier<int> changes = ValueNotifier<int>(0);

  /// Remote audio could not start: the stage offers "Tap to hear".
  final ValueNotifier<bool> audioBlocked = ValueNotifier<bool>(false);

  Room? _room;
  EventsListener<RoomEvent>? _events;
  SpeakerGrant? _grant;
  bool _retried = false;
  bool _closing = false;

  bool get connected => _room?.connectionState == ConnectionState.connected;

  static bool get _iOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// The Professor's camera, the main picture of the stage; null while it
  /// is not received (e.g. paused because the downlink cannot carry it).
  VideoTrack? get presenterVideo {
    final Room? room = _room;
    if (room == null) return null;
    for (final RemoteParticipant participant in room.remoteParticipants.values) {
      for (final RemoteTrackPublication<RemoteVideoTrack> publication in participant.videoTrackPublications) {
        final RemoteVideoTrack? track = publication.track;
        if (publication.source == TrackSource.camera && track != null && !publication.muted) return track;
      }
    }
    return null;
  }

  Future<void> connect(SpeakerGrant grant) async {
    _grant = grant;
    _closing = false;
    if (_iOS) await _configureAppleAudio();
    final Room room = Room(
      roomOptions: const RoomOptions(
        adaptiveStream: true,
        dynacast: true,
        defaultAudioCaptureOptions: AudioCaptureOptions(
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true,
        ),
      ),
    );
    _room = room;
    void changed() => changes.value++;
    _events = room.createListener()
      ..on<RoomDisconnectedEvent>((_) => _onDisconnected())
      ..on<TrackSubscribedEvent>((_) => changed())
      ..on<TrackUnsubscribedEvent>((_) => changed())
      ..on<TrackMutedEvent>((_) => changed())
      ..on<TrackUnmutedEvent>((_) => changed())
      ..on<ParticipantDisconnectedEvent>((_) => changed())
      ..on<AudioPlaybackStatusChanged>((AudioPlaybackStatusChanged event) {
        audioBlocked.value = !event.isPlaying;
      });
    await room.connect(grant.url, grant.token);
    await room.localParticipant?.setMicrophoneEnabled(true);
    if (!room.canPlaybackAudio) audioBlocked.value = true;
    changed();
  }

  /// iPhone: the conversation plays through the loudspeaker (not the
  /// earpiece) while the microphone records (`playAndRecord`,
  /// `defaultToSpeaker`).
  Future<void> _configureAppleAudio() async {
    try {
      await AudioManager.instance.setAudioSessionOptions(
        const AudioSessionOptions.communication(
          apple: AppleAudioSessionConfiguration(
            category: AppleAudioCategory.playAndRecord,
            categoryOptions: <AppleAudioCategoryOption>{
              AppleAudioCategoryOption.defaultToSpeaker,
              AppleAudioCategoryOption.allowBluetooth,
              AppleAudioCategoryOption.allowBluetoothA2DP,
            },
            mode: AppleAudioMode.voiceChat,
          ),
        ),
      );
      await AudioManager.instance.setSpeakerOutputPreferred(true);
    } catch (_) {
      // LiveKit's own session management still applies.
    }
  }

  /// "Tap to hear": a user gesture starts the remote audio.
  Future<void> startAudio() async {
    if (_iOS) await _configureAppleAudio();
    await _room?.startAudio();
    audioBlocked.value = !(_room?.canPlaybackAudio ?? true);
  }

  /// The teaching team muted the Student (or unmuted them).
  Future<void> setMicrophone(bool enabled) async {
    await _room?.localParticipant?.setMicrophoneEnabled(enabled);
  }

  Future<void> _onDisconnected() async {
    if (_closing) return;
    final SpeakerGrant? grant = _grant;
    if (!_retried && grant != null) {
      _retried = true;
      await Future<void>.delayed(const Duration(milliseconds: 750));
      try {
        await _dispose();
        await connect(grant);
        return;
      } catch (_) {
        // Fall through to giving up.
      }
    }
    onDropped();
  }

  Future<void> close() async {
    _closing = true;
    await _dispose();
    if (_iOS) {
      // Hand the audio session back so the broadcast plays as media again.
      try {
        await AudioManager.instance.setAudioSessionManagementMode(AudioSessionManagementMode.automatic);
      } catch (_) {}
    }
  }

  Future<void> _dispose() async {
    await _events?.dispose();
    _events = null;
    final Room? room = _room;
    _room = null;
    if (room != null) {
      await room.disconnect();
      await room.dispose();
    }
    changes.value++;
  }
}
