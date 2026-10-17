import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../core/utils/screen_awake.dart';
import '../../data/chat_store.dart';

/// D-143 chat audio: the send/receive sounds, voice-note playback and
/// recording. Each part sits behind a small seam so tests run without
/// the platform plugins (and `flutter test` never loads them).
bool get _underTest => !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

// ── Sounds ─────────────────────────────────────────────────────────────

enum ChatSound { send, receive }

/// Plays [ChatSound]s; replaced in tests.
abstract class ChatSoundPlayer {
  Future<void> play(ChatSound sound, double volume);
}

/// The chat's own short sounds (`assets/sounds/`, synthesized for NOVA):
/// a soft pop when a message is sent, a two-note chime when one arrives.
/// Throttled, silent while a video or a Live plays (the screen is held
/// awake), and on iPhone they follow the silent switch (`ambient`).
abstract final class ChatSounds {
  static ChatSoundPlayer player = _AudioplayersSoundPlayer();

  static const Duration _sendGap = Duration(milliseconds: 250);
  static const Duration _receiveGap = Duration(milliseconds: 1500);
  static DateTime? _lastSend;
  static DateTime? _lastReceive;

  static void sent() {
    if (!_due(_lastSend, _sendGap)) return;
    _lastSend = DateTime.now();
    player.play(ChatSound.send, 0.55).catchError((Object _) {});
  }

  /// [soft]: a message in the room on screen.
  static void received({bool soft = false}) {
    if (!_due(_lastReceive, _receiveGap)) return;
    _lastReceive = DateTime.now();
    player.play(ChatSound.receive, soft ? 0.3 : 0.7).catchError((Object _) {});
  }

  static bool _due(DateTime? last, Duration gap) {
    if (ScreenAwake.held) return false;
    return last == null || DateTime.now().difference(last) >= gap;
  }

  @visibleForTesting
  static void resetThrottle() {
    _lastSend = null;
    _lastReceive = null;
  }
}

class _AudioplayersSoundPlayer implements ChatSoundPlayer {
  final Map<ChatSound, AudioPlayer> _players = <ChatSound, AudioPlayer>{};

  static final AudioContext _context = AudioContext(
    android: const AudioContextAndroid(
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.assistanceSonification,
      audioFocus: AndroidAudioFocus.none,
    ),
    iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
  );

  @override
  Future<void> play(ChatSound sound, double volume) async {
    if (_underTest) return;
    try {
      final AudioPlayer player = _players[sound] ??= AudioPlayer()..setPlayerMode(PlayerMode.lowLatency);
      // iPhone has one audio session: a voice note keeps its `playback`.
      if (!ChatVoicePlayer.instance.playing) await player.setAudioContext(_context);
      await player.stop();
      await player.play(
        AssetSource(sound == ChatSound.send ? 'sounds/chat_send.wav' : 'sounds/chat_receive.wav'),
        volume: volume,
      );
    } catch (_) {
      // No sound on this device: the message is there all the same.
    }
  }
}

// ── Voice notes playback ───────────────────────────────────────────────

/// The audio engine behind [ChatVoicePlayer]; replaced in tests.
abstract class VoiceEngine {
  /// Starts [source] (an https URL, or a local file when [local]).
  Future<void> play(String source, {required bool local, required double rate});
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setRate(double rate);
  Stream<Duration> get position;
  Stream<Duration> get duration;
  Stream<void> get completed;
}

enum VoiceState { idle, loading, playing, paused }

/// One voice note plays at a time, app-wide (starting another stops the
/// first); the speed (1×, 1.5×, 2×) is kept from one note to the next.
class ChatVoicePlayer extends ChangeNotifier {
  ChatVoicePlayer._();

  static final ChatVoicePlayer instance = ChatVoicePlayer._();

  static VoiceEngine Function() engineFactory = _AudioplayersVoiceEngine.new;

  static const List<double> speeds = <double>[1, 1.5, 2];

  VoiceEngine? _engine;
  final List<StreamSubscription<Object?>> _subscriptions = <StreamSubscription<Object?>>[];
  String? _current;
  VoiceState _state = VoiceState.idle;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _speed = 1;
  int _request = 0;

  /// The note being played or paused (its message key).
  String? get current => _current;
  VoiceState stateOf(String key) => key == _current ? _state : VoiceState.idle;
  bool get playing => _state == VoiceState.playing;
  Duration positionOf(String key) => key == _current ? _position : Duration.zero;
  Duration durationOf(String key, Duration known) =>
      key == _current && _duration > Duration.zero ? _duration : known;
  double get speed => _speed;

  VoiceEngine get _ready {
    final VoiceEngine? engine = _engine;
    if (engine != null) return engine;
    final VoiceEngine created = engineFactory();
    _subscriptions
      ..add(created.position.listen((Duration p) {
        _position = p;
        notifyListeners();
      }))
      ..add(created.duration.listen((Duration d) {
        if (d > Duration.zero) _duration = d;
        notifyListeners();
      }))
      ..add(created.completed.listen((_) {
        _state = VoiceState.idle;
        _position = Duration.zero;
        _current = null;
        notifyListeners();
      }));
    return _engine = created;
  }

  /// Play, pause or resume the note [key]; [source] resolves its URL (or
  /// local path when [local]) the first time.
  Future<void> toggle(String key, {required Future<String> Function() source, required bool local, Duration known = Duration.zero}) async {
    if (key == _current && _state == VoiceState.playing) {
      _state = VoiceState.paused;
      notifyListeners();
      await _ready.pause();
      return;
    }
    if (key == _current && _state == VoiceState.paused) {
      _state = VoiceState.playing;
      notifyListeners();
      await _ready.resume();
      return;
    }
    await start(key, source: source, local: local, known: known);
  }

  Future<void> start(String key, {required Future<String> Function() source, required bool local, Duration known = Duration.zero, double from = 0}) async {
    final int request = ++_request;
    if (_current != null) await _ready.stop();
    _current = key;
    _state = VoiceState.loading;
    _position = Duration.zero;
    _duration = known;
    notifyListeners();
    try {
      final String resolved = await source();
      if (request != _request) return;
      await _ready.play(resolved, local: local, rate: _speed);
      if (request != _request) return;
      _state = VoiceState.playing;
      if (from > 0 && known > Duration.zero) await _ready.seek(known * from);
    } catch (_) {
      if (request != _request) return;
      _state = VoiceState.idle;
      _current = null;
      rethrow;
    } finally {
      if (request == _request) notifyListeners();
    }
  }

  /// Seeks the current note to [fraction] (0..1) of [known].
  Future<void> seek(String key, double fraction, Duration known) async {
    if (key != _current) return;
    final Duration total = durationOf(key, known);
    final Duration target = total * fraction.clamp(0, 1);
    _position = target;
    notifyListeners();
    await _ready.seek(target);
  }

  void cycleSpeed() {
    _speed = speeds[(speeds.indexOf(_speed) + 1) % speeds.length];
    notifyListeners();
    if (_current != null) _ready.setRate(_speed).catchError((Object _) {});
  }

  /// Stops whatever plays (a room closed, a message deleted).
  Future<void> stop([String? key]) async {
    if (_current == null || (key != null && key != _current)) return;
    _request++;
    _current = null;
    _state = VoiceState.idle;
    _position = Duration.zero;
    notifyListeners();
    await _engine?.stop();
  }

  @visibleForTesting
  void reset() {
    _request++;
    for (final StreamSubscription<Object?> s in _subscriptions) {
      s.cancel();
    }
    _subscriptions.clear();
    _engine = null;
    _current = null;
    _state = VoiceState.idle;
    _position = Duration.zero;
    _duration = Duration.zero;
    _speed = 1;
  }
}

class _AudioplayersVoiceEngine implements VoiceEngine {
  _AudioplayersVoiceEngine() : _player = AudioPlayer() {
    _player.setReleaseMode(ReleaseMode.stop);
  }

  final AudioPlayer _player;

  static final AudioContext _context = AudioContext(
    android: const AudioContextAndroid(
      contentType: AndroidContentType.speech,
      usageType: AndroidUsageType.media,
      audioFocus: AndroidAudioFocus.gainTransientMayDuck,
    ),
    // Voice notes play in silent mode too, like any messaging app.
    iOS: AudioContextIOS(category: AVAudioSessionCategory.playback),
  );

  @override
  Future<void> play(String source, {required bool local, required double rate}) async {
    await _player.setAudioContext(_context);
    await _player.play(local ? DeviceFileSource(source, mimeType: 'audio/mp4') : UrlSource(source, mimeType: 'audio/mp4'));
    await _player.setPlaybackRate(rate);
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> resume() => _player.resume();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setRate(double rate) => _player.setPlaybackRate(rate);

  @override
  Stream<Duration> get position => _player.onPositionChanged;

  @override
  Stream<Duration> get duration => _player.onDurationChanged;

  @override
  Stream<void> get completed => _player.onPlayerComplete;
}

// ── Recording ──────────────────────────────────────────────────────────

/// Records voice notes; replaced in tests.
abstract class ChatRecorder {
  static ChatRecorder Function() factory = _RecordChatRecorder.new;

  /// Asks for the microphone when needed.
  Future<bool> hasPermission();

  Future<void> start();

  /// The recorded file, or null when nothing was recorded.
  Future<String?> stop();

  /// Stops and deletes the recording: nothing is sent.
  Future<void> cancel();

  /// Input level 0..1, about ten times a second.
  Stream<double> get levels;

  Future<void> dispose();
}

class _RecordChatRecorder implements ChatRecorder {
  final AudioRecorder _recorder = AudioRecorder();

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> start() async {
    final Directory dir = await getTemporaryDirectory();
    final String path = '${dir.path}/nova-voice-${ChatStore.newClientUuid()}.m4a';
    // AAC in an MP4 box (.m4a), mono: what the server keeps (D-143).
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100, numChannels: 1),
      path: path,
    );
  }

  @override
  Future<String?> stop() => _recorder.stop();

  @override
  Future<void> cancel() => _recorder.cancel();

  @override
  Stream<double> get levels => _recorder
      .onAmplitudeChanged(const Duration(milliseconds: 100))
      // dBFS (about -60 quiet … 0 loud) to 0..1.
      .map((Amplitude a) => ((a.current + 50) / 50).clamp(0.0, 1.0).toDouble());

  @override
  Future<void> dispose() => _recorder.dispose();
}

/// 48 peaks 0..100 from recorded input levels (the pending bubble's
/// waveform until the server's arrives).
List<int> waveformOf(List<double> levels, {int bars = 48}) {
  if (levels.isEmpty) return const <int>[];
  return List<int>.generate(bars, (int i) {
    final int from = (i * levels.length / bars).floor();
    final int to = math.max(from + 1, ((i + 1) * levels.length / bars).floor());
    double peak = 0;
    for (int j = from; j < to && j < levels.length; j++) {
      peak = math.max(peak, levels[j]);
    }
    return (peak * 100).round().clamp(4, 100);
  });
}
