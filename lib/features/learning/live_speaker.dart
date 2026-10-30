// LiveKit's audio-session API is marked experimental; it is the supported
// way to set the iPhone session the accepted speaker needs.
// ignore_for_file: experimental_member_use

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../core/security/capture_shield.dart';
import '../../data/live_store.dart';

/// What the speaking stage shows of the Professor (D-073).
enum PresenterPicture {
  /// Not received yet: the room connects, the camera is subscribed or its
  /// first frame is on its way. Never a black screen.
  connecting,

  /// The Professor's camera, moving.
  showing,

  /// No camera picture (camera off, or paused by the server because the
  /// downlink cannot carry it); the conversation goes on with audio.
  paused,
}

/// [PresenterPicture] from what the LiveKit room reports, kept pure so it is
/// unit-tested without a room.
PresenterPicture presenterPictureFor({
  required bool connected,
  required bool professorPresent,
  required bool cameraPublished,
  required bool cameraMuted,
  required bool subscribed,
  required bool pausedByServer,
  required bool frameShown,
}) {
  if (!connected || !professorPresent) return PresenterPicture.connecting;
  if (!cameraPublished || cameraMuted || pausedByServer) return PresenterPicture.paused;
  if (!subscribed || !frameShown) return PresenterPicture.connecting;
  return PresenterPicture.showing;
}

/// Whether the stage's renderer has shown the Professor's camera: a frame
/// decoded after the renderer was attached (frames decoded before it are
/// not on screen). Fed with `framesDecoded` of the receiver's stats; a
/// phone whose stats never give it shows the picture after [blindLimit]
/// readings, as before.
class PresenterFrameWatch {
  static const int blindLimit = 30;

  num? _baseline;
  int _blind = 0;

  /// True once a new frame was decoded since the first observation.
  bool shown = false;

  bool observe(num? framesDecoded) {
    if (framesDecoded == null) {
      if (++_blind >= blindLimit) shown = true;
      return shown;
    }
    final num? baseline = _baseline;
    if (baseline == null) {
      _baseline = framesDecoded;
    } else if (framesDecoded > baseline) {
      shown = true;
    }
    return shown;
  }
}

/// LiveKit ended the speaking turn itself (Live 66, 2026-10-30): the
/// teaching team removed the Student or the room was deleted. Such a
/// disconnection is final: never reconnected with the turn's grant.
bool speakerTurnEndedBy(DisconnectReason? reason) =>
    reason == DisconnectReason.participantRemoved || reason == DisconnectReason.roomDeleted;

/// Only a lost connection is worth one reconnect: not the end of the turn,
/// the same Student joining from another device, nor a disconnection the
/// app asked for.
bool speakerReconnectsAfter(DisconnectReason? reason) =>
    !speakerTurnEndedBy(reason) &&
    reason != DisconnectReason.duplicateIdentity &&
    reason != DisconnectReason.clientInitiated;

/// The accepted Student's microphone in the Live (web `useLiveRoom`,
/// Student role): LiveKit with the microphone only — the backend grant
/// allows no camera — echo cancellation, noise suppression and gain
/// control on. A lost connection gets one automatic reconnect after
/// 750 ms, then [onDropped]; a turn LiveKit ended ([speakerTurnEndedBy])
/// sets [removed] instead, and the room closes the stage.
///
/// While speaking, the Student watches and hears the Professor over this
/// connection ([presenterVideo], D-073); the broadcast player is kept muted
/// and hidden under the stage (owner decision 2026-10-30, amends D-066 for
/// the apps), so LiveKit is the only audible source.
///
/// iPhone screen recording or mirroring (owner decision 2026-10-29): the
/// recording is black but would still carry the class's voices, so the
/// remote audio is silenced while the screen is captured and comes back
/// when the capture stops. The Student's own microphone is unchanged.
class LiveSpeaker {
  LiveSpeaker({
    required this.onDropped,
    @visibleForTesting Future<void> Function(bool silent)? silenceRemoteAudio,
  }) {
    _silenceRemoteAudio = silenceRemoteAudio ?? _silenceRoomAudio;
    CaptureMonitor.instance.addListener(_onCapture);
    _onCapture();
  }

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
  bool _removed = false;
  Future<void>? _audioReady;

  /// The teaching team ended the turn in LiveKit ([speakerTurnEndedBy]).
  bool get removed => _removed;
  late final Future<void> Function(bool silent) _silenceRemoteAudio;
  bool _silent = false;

  /// True while the remote audio is silenced by a screen capture.
  bool get remoteAudioSilenced => _silent;

  /// The camera track whose first frame the stage rendered.
  String? _shownTrack;

  /// Camera publications the server said it paused (allocator, D-065
  /// `allow_pause`). A publication starts "paused" in the SDK until the
  /// server speaks, so only an explicit pause counts.
  final Set<String> _pausedByServer = <String>{};

  static const AudioCaptureOptions _microphone = AudioCaptureOptions(
    echoCancellation: true,
    noiseSuppression: true,
    autoGainControl: true,
  );

  bool get connected => _room?.connectionState == ConnectionState.connected;

  static bool get _iOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// The Professor's camera, the main picture of the stage; null while it
  /// is not received (e.g. paused because the downlink cannot carry it).
  RemoteVideoTrack? get presenterVideo {
    final RemoteTrackPublication<RemoteVideoTrack>? publication = _presenterCamera;
    final RemoteVideoTrack? track = publication?.track;
    return publication != null && track != null && !publication.muted ? track : null;
  }

  RemoteTrackPublication<RemoteVideoTrack>? get _presenterCamera {
    final Room? room = _room;
    if (room == null) return null;
    for (final RemoteParticipant participant in room.remoteParticipants.values) {
      for (final RemoteTrackPublication<RemoteVideoTrack> publication in participant.videoTrackPublications) {
        if (publication.source == TrackSource.camera) return publication;
      }
    }
    return null;
  }

  /// What the stage shows: "connecting" until the first frame of the
  /// Professor's camera is on screen, never a black picture.
  PresenterPicture get presenterPicture {
    final Room? room = _room;
    final RemoteTrackPublication<RemoteVideoTrack>? camera = _presenterCamera;
    final RemoteVideoTrack? track = camera?.track;
    return presenterPictureFor(
      connected: room != null && room.connectionState == ConnectionState.connected,
      professorPresent: room != null && room.remoteParticipants.isNotEmpty,
      cameraPublished: camera != null,
      cameraMuted: camera?.muted ?? false,
      subscribed: track != null,
      pausedByServer: camera != null && _pausedByServer.contains(camera.sid),
      frameShown: track != null && track.sid != null && track.sid == _shownTrack,
    );
  }

  /// The server paused the Professor's camera for this Student because
  /// their downlink cannot carry it (D-065 `allow_pause`): the weak
  /// downlink the room uses to pause the hidden broadcast (owner decision
  /// 2026-10-30). A camera the Professor switched off is not one.
  bool get downlinkWeak {
    final RemoteTrackPublication<RemoteVideoTrack>? camera = _presenterCamera;
    return camera != null && _pausedByServer.contains(camera.sid);
  }

  /// The stage rendered [track]'s first frame.
  void presenterFrameShown(VideoTrack track) {
    if (track.sid == null || track.sid == _shownTrack) return;
    _shownTrack = track.sid;
    changes.value++;
  }

  /// iPhone: the conversation's audio session, prepared from the moment
  /// the hand is accepted, while the grant and the connection are on their
  /// way rather than before them. Nothing is captured or published here.
  void prepareAudio() {
    _audioReady ??= _iOS ? _configureAppleAudio() : Future<void>.value();
  }

  Future<void> connect(SpeakerGrant grant) async {
    _grant = grant;
    _closing = false;
    await open(grant);
  }

  /// One LiveKit connection with the microphone published: the first, and
  /// the one reconnect after a lost connection.
  @protected
  @visibleForTesting
  Future<void> open(SpeakerGrant grant) async {
    prepareAudio();
    final Room room = Room(
      roomOptions: const RoomOptions(
        // Not adaptive: the Professor publishes one layer (D-065), so the
        // only effect of adaptive stream was to keep the camera switched
        // off until the stage was on screen, i.e. after the microphone was
        // published, and only then to ask the Professor for a keyframe
        // (seconds of black on a slow studio link). The camera now flows
        // from its subscription, while the microphone is published.
        adaptiveStream: false,
        dynacast: true,
        defaultAudioCaptureOptions: _microphone,
      ),
    );
    _room = room;
    _shownTrack = null;
    _pausedByServer.clear();
    void changed() => changes.value++;
    _events = room.createListener()
      ..on<RoomDisconnectedEvent>((RoomDisconnectedEvent event) => disconnected(event.reason))
      ..on<TrackSubscribedEvent>((TrackSubscribedEvent event) {
        // A voice that arrives during a capture starts silenced.
        if (_silent) _silenceTrack(event.publication, event.track, true).catchError((Object _) {});
        changed();
      })
      ..on<TrackUnsubscribedEvent>((_) => changed())
      ..on<TrackMutedEvent>((_) => changed())
      ..on<TrackUnmutedEvent>((_) => changed())
      ..on<TrackStreamStateUpdatedEvent>((TrackStreamStateUpdatedEvent event) {
        if (event.streamState == StreamState.paused) {
          _pausedByServer.add(event.publication.sid);
        } else {
          _pausedByServer.remove(event.publication.sid);
        }
        changed();
      })
      ..on<TrackPublishedEvent>((_) => changed())
      ..on<TrackUnpublishedEvent>((_) => changed())
      ..on<ParticipantConnectedEvent>((_) => changed())
      ..on<ParticipantDisconnectedEvent>((_) => changed())
      ..on<AudioPlaybackStatusChanged>((AudioPlaybackStatusChanged event) {
        audioBlocked.value = !event.isPlaying;
      });
    // The microphone (and its permission prompt) is captured while the room
    // connects rather than after it, once the iPhone audio session is set;
    // a capture left over by a failure stops.
    final List<Object?> ready = await Future.wait<Object?>(
      <Future<Object?>>[
        room.connect(grant.url, grant.token),
        _audioReady!.then((_) => LocalAudioTrack.create(_microphone)),
      ],
      cleanUp: (Object? value) {
        if (value is LocalAudioTrack) unawaited(value.stop());
      },
    );
    final LocalAudioTrack microphone = ready[1]! as LocalAudioTrack;
    if (_closing || !identical(_room, room)) {
      // The turn ended while connecting: nothing is published.
      unawaited(microphone.stop());
      return;
    }
    try {
      await room.localParticipant!.publishAudioTrack(microphone);
    } catch (_) {
      unawaited(microphone.stop());
      rethrow;
    }
    // Accepted while the screen is already recorded: the class starts silent.
    if (_silent) await _silenceRemoteAudio(true);
    if (!room.canPlaybackAudio) audioBlocked.value = true;
    changed();
  }

  /// Screen recording or mirroring started or stopped (iPhone).
  void _onCapture() {
    final bool silent = CaptureMonitor.instance.captured;
    if (silent == _silent) return;
    _silent = silent;
    _silenceRemoteAudio(silent).catchError((Object _) {});
  }

  Future<void> _silenceRoomAudio(bool silent) async {
    final Room? room = _room;
    if (room == null) return;
    for (final RemoteParticipant participant in room.remoteParticipants.values) {
      for (final RemoteTrackPublication<RemoteAudioTrack> publication in participant.audioTrackPublications) {
        await _silenceTrack(publication, publication.track, silent);
      }
    }
  }

  /// At once on the phone — a disabled WebRTC track plays at volume 0 —
  /// and on the server, which stops (or resumes) forwarding it. The
  /// WebRTC track is set directly: LiveKit's `Track.disable()` does
  /// nothing before the track has started, which comes after
  /// [TrackSubscribedEvent].
  static Future<void> _silenceTrack(RemoteTrackPublication publication, Track? track, bool silent) async {
    if (track is! RemoteAudioTrack) return;
    track.mediaStreamTrack.enabled = !silent;
    await (silent ? publication.disable() : publication.enable());
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

  /// LiveKit closed the room connection ([RoomDisconnectedEvent]).
  ///
  /// Live 66 (2026-10-30): a Student the Admin removed started a new
  /// LiveKit session 2–6 s later with the turn's grant, which the server
  /// closed again — the removal was taken for a lost connection, and the
  /// reconnect also went on after the stage had closed meanwhile.
  @visibleForTesting
  Future<void> disconnected(DisconnectReason? reason) async {
    if (_closing) return;
    if (speakerTurnEndedBy(reason)) {
      _removed = true;
      changes.value++;
      return;
    }
    final SpeakerGrant? grant = _grant;
    if (!_retried && grant != null && speakerReconnectsAfter(reason)) {
      _retried = true;
      await Future<void>.delayed(const Duration(milliseconds: 750));
      // The turn ended meanwhile (realtime, or the Student lowered the hand).
      if (_closing) return;
      try {
        await _dispose();
        await open(grant);
        return;
      } catch (_) {
        if (_closing) return;
        // Fall through to giving up.
      }
    }
    onDropped();
  }

  Future<void> close() async {
    _closing = true;
    CaptureMonitor.instance.removeListener(_onCapture);
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
