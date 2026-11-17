import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/i18n/nova_strings.dart';

bool get _underTest => !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

/// D-110: one loop of the waiting-room motion graphic and of its voice.
const Duration waitingLoop = Duration(seconds: 24);

/// The captions of the voice in the loop, in seconds (web `WAITING_VOICE`).
const List<({String key, double from, double to})> waitingCaptions = <({String key, double from, double to})>[
  (key: 'waiting.voice1', from: 0.8, to: 5.13),
  (key: 'waiting.voice2', from: 5.58, to: 10.71),
  (key: 'waiting.voice3', from: 11.16, to: 16.13),
  (key: 'waiting.voice4', from: 16.58, to: 19.77),
];

/// The caption shown at [seconds] of the loop, or -1 between sentences.
int waitingCaptionAt(double seconds) {
  final double loop = waitingLoop.inSeconds.toDouble();
  final double at = ((seconds % loop) + loop) % loop;
  return waitingCaptions.indexWhere((c) => at >= c.from && at < c.to);
}

/// The countdown as mm:ss, rounded up like the website.
String waitingCountdown(Duration remaining) {
  final int seconds = (remaining.inMilliseconds / 1000).ceil();
  return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// D-110 waiting room in the apps (web `LiveWaitingRoom`): the countdown on
/// the server's clock (the same for everyone, late arrivals included), the
/// NOVA animation with its voice and captions, a mute button, and the
/// presence the Admin counts. The countdown end never starts the Live: the
/// room leaves it when the Admin does. The web's browser device test has no
/// place here: the apps play natively.
class LiveWaitingRoom extends StatefulWidget {
  const LiveWaitingRoom({
    super.key,
    required this.endsAt,
    required this.countsDown,
    required this.serverNow,
    required this.presence,
  });

  /// The countdown end set by the Admin (null: none).
  final DateTime? endsAt;

  /// False once the Live is starting: "in a moment" instead of the countdown.
  final bool countsDown;

  /// Now on the server's clock.
  final DateTime Function() serverNow;

  /// Tells the server this Student is in the room (every 30 s).
  final Future<void> Function() presence;

  static const Duration presenceEvery = Duration(seconds: 30);

  @override
  State<LiveWaitingRoom> createState() => _LiveWaitingRoomState();
}

class _LiveWaitingRoomState extends State<LiveWaitingRoom> with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(vsync: this, duration: waitingLoop);
  late final Timer _tick;
  late final Timer _presence;
  AudioPlayer? _voice;
  StreamSubscription<Duration>? _voicePosition;
  bool _muted = false;

  static final AudioContext _voiceContext = AudioContext(
    android: const AudioContextAndroid(
      contentType: AndroidContentType.speech,
      usageType: AndroidUsageType.media,
      audioFocus: AndroidAudioFocus.gainTransientMayDuck,
    ),
    iOS: AudioContextIOS(category: AVAudioSessionCategory.playback),
  );

  @override
  void initState() {
    super.initState();
    _loop.repeat();
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) => mounted ? setState(() {}) : null);
    _beat();
    _presence = Timer.periodic(LiveWaitingRoom.presenceEvery, (_) => _beat());
    unawaited(_startVoice());
  }

  void _beat() => unawaited(widget.presence().catchError((Object _) {}));

  Future<void> _startVoice() async {
    if (_underTest) return;
    try {
      final AudioPlayer player = _voice = AudioPlayer();
      await player.setAudioContext(_voiceContext);
      await player.setReleaseMode(ReleaseMode.loop);
      // The animation follows the voice so the captions match its sentences.
      _voicePosition = player.onPositionChanged.listen((Duration at) {
        final double value = (at.inMilliseconds / waitingLoop.inMilliseconds).clamp(0, 1);
        if (mounted && (value - _loop.value).abs() > 0.02) {
          _loop.value = value;
          _loop.repeat();
        }
      });
      await player.play(AssetSource('sounds/nova_waiting_voice.mp3'));
    } catch (_) {
      // No sound on this device: the countdown and the captions stay.
    }
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    unawaited(_voice?.setVolume(_muted ? 0 : 1).catchError((Object _) {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    _presence.cancel();
    _loop.dispose();
    unawaited(_voicePosition?.cancel());
    final AudioPlayer? voice = _voice;
    if (voice != null) unawaited(voice.dispose().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DateTime? end = widget.endsAt;
    final Duration remaining = widget.countsDown && end != null ? end.difference(widget.serverNow()) : Duration.zero;
    const TextStyle white = TextStyle(fontFamily: 'Geist', color: Colors.white, fontWeight: FontWeight.w600);
    return Semantics(
      container: true,
      label: context.tr('waiting.title'),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) {
          final double side = math.max(140, math.min(math.min(box.maxWidth, 420), box.maxHeight - 150));
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: side,
                  child: AnimatedBuilder(
                    animation: _loop,
                    builder: (BuildContext context, _) {
                      final bool still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
                      return NovaWaitingAnimation(seconds: still ? 0 : _loop.value * waitingLoop.inSeconds);
                    },
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 44,
                  child: AnimatedBuilder(
                    animation: _loop,
                    builder: (BuildContext context, _) {
                      final int caption = waitingCaptionAt(_loop.value * waitingLoop.inSeconds);
                      return ExcludeSemantics(
                        child: Text(
                          caption < 0 ? '' : context.tr(waitingCaptions[caption].key),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          style: white.copyWith(fontSize: 14, height: 1.4, color: Colors.white.withValues(alpha: 0.9)),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 6),
                if (remaining > Duration.zero) ...[
                  Text(context.tr('waiting.startsIn'), style: white.copyWith(fontSize: 13, color: Colors.white70)),
                  Text(
                    waitingCountdown(remaining),
                    textDirection: TextDirection.ltr,
                    style: white.copyWith(
                      fontSize: 44,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                    ),
                  ),
                ] else
                  Text(context.tr('waiting.soon'), textAlign: TextAlign.center, style: white.copyWith(fontSize: 17)),
                const SizedBox(height: 6),
                TextButton.icon(
                  onPressed: _toggleMute,
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  icon: Icon(_muted ? Icons.volume_off_rounded : Icons.volume_up_rounded),
                  label: Text(context.tr(_muted ? 'waiting.soundOn' : 'waiting.soundOff')),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The NOVA waiting-room motion graphic (web `NovaWaitingAnimation`): the
/// official logo on a white disc, gold arcs, star and particles on a 24 s
/// loop, drawn at [seconds] of the loop. Decorative.
class NovaWaitingAnimation extends StatelessWidget {
  const NovaWaitingAnimation({super.key, required this.seconds});

  final double seconds;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints box) {
            final double k = box.maxWidth / 360;
            final double breathe = 1 + 0.035 * _wave(seconds, 6);
            return Stack(
              children: [
                Positioned.fill(child: CustomPaint(painter: _WaitingBackPainter(seconds, breathe))),
                // The official logo file (D-117), breathing with its disc.
                Positioned(
                  left: (180 - 113 * breathe) * k,
                  top: (176 - 113 * breathe) * k,
                  width: 226 * breathe * k,
                  height: 226 * breathe * k,
                  child: Image.asset('assets/images/brand/nova_logo.png'),
                ),
                Positioned.fill(child: CustomPaint(painter: _WaitingFrontPainter(seconds, breathe))),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 0 → 1 → 0 over [period] seconds, eased in and out (the CSS keyframes).
double _wave(double seconds, double period, [double delay = 0]) {
  final double phase = (((seconds + delay) % period) + period) % period / period;
  return Curves.easeInOut.transform(phase < 0.5 ? phase * 2 : 2 - phase * 2);
}

const Color _gold = Color(0xFFFFC35A);
const Color _glow = Color(0xFF5D8FFF);

const List<(double, double, double)> _particles = <(double, double, double)>[
  (42, 58, 2.2), (312, 72, 1.8), (70, 300, 2.4), (296, 286, 2), (24, 182, 1.6), (338, 196, 2.2), (120, 34, 1.4),
  (248, 336, 1.6), (96, 120, 1.2), (270, 128, 1.4), (150, 322, 1.8), (214, 26, 2), (330, 330, 1.2), (18, 330, 1.6),
];

class _WaitingBackPainter extends CustomPainter {
  _WaitingBackPainter(this.seconds, this.breathe);

  final double seconds;
  final double breathe;

  void _blob(Canvas canvas, Offset center, double radius, Color color, double alpha) {
    final Rect rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[color.withValues(alpha: alpha), color.withValues(alpha: 0)],
        ).createShader(rect),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 360);
    const Rect frame = Rect.fromLTWH(0, 0, 360, 360);
    canvas.drawRect(
      frame,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -0.16),
          radius: 0.7,
          colors: <Color>[Color(0xFF2459E6), Color(0xFF123A9E), Color(0xFF081A4D)],
          stops: <double>[0, 0.55, 1],
        ).createShader(frame),
    );
    final double a = _wave(seconds, 12);
    final double c = _wave(seconds, 8);
    _blob(canvas, Offset(70 + 40 * a, 80 + 30 * a), 110, _glow, 0.55);
    _blob(canvas, Offset(300 - 36 * a, 290 - 26 * a), 120, _glow, 0.55);
    _blob(canvas, Offset(290 - 20 * c, 70 + 18 * c), 70, _gold, 0.45 * (0.6 + 0.4 * c));
    for (int i = 0; i < _particles.length; i++) {
      final (double x, double y, double r) = _particles[i];
      final double opacity = 0.15 + 0.85 * _wave(seconds, 6, (i * 1.7) % 6);
      canvas.drawCircle(Offset(x, y), r, Paint()..color = (i % 3 == 0 ? _gold : Colors.white).withValues(alpha: opacity));
    }

    canvas.save();
    canvas.translate(180, 180);
    canvas.scale(breathe);
    canvas.translate(-180, -180);
    const Offset disc = Offset(180, 176);
    canvas.drawCircle(disc, 128, Paint()..color = Colors.white);
    void arc(double radius, double length, double turns, Color color, double width) {
      canvas.drawArc(
        Rect.fromCircle(center: disc, radius: radius),
        turns * 2 * math.pi,
        length / radius,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round,
      );
    }

    arc(140, 120, seconds / 12, _gold, 3);
    arc(149, 70, -seconds / 8, const Color(0xFF7EA7FF), 2);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WaitingBackPainter old) => old.seconds != seconds;
}

class _WaitingFrontPainter extends CustomPainter {
  _WaitingFrontPainter(this.seconds, this.breathe);

  final double seconds;
  final double breathe;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 360);
    canvas.save();
    canvas.translate(180, 180);
    canvas.scale(breathe);
    canvas.translate(106, -114);
    final double s = _wave(seconds, 4);
    canvas.rotate(s * math.pi / 4);
    canvas.scale(0.8 + 0.45 * s);
    final Path star = Path()
      ..moveTo(0, -13)
      ..cubicTo(2, -4, 4, -2, 13, 0)
      ..cubicTo(4, 2, 2, 4, 0, 13)
      ..cubicTo(-2, 4, -4, 2, -13, 0)
      ..cubicTo(-4, -2, -2, -4, 0, -13)
      ..close();
    canvas.drawPath(star, Paint()..color = _gold.withValues(alpha: 0.8 + 0.2 * s));
    canvas.restore();

    // The light sweep crosses during the second half of each 8 s.
    final double phase = (seconds % 8) / 8;
    final double x = -120 + (phase < 0.5 ? 0 : Curves.easeInOut.transform(phase * 2 - 1) * 600);
    final Rect sweep = Rect.fromLTWH(x, 0, 90, 360);
    canvas.drawRect(
      sweep,
      Paint()
        ..shader = LinearGradient(
          colors: <Color>[
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.55 * 0.18),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(sweep),
    );
  }

  @override
  bool shouldRepaint(_WaitingFrontPainter old) => old.seconds != seconds;
}
