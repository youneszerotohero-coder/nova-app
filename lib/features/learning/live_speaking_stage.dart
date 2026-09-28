import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' show VideoTrack, VideoTrackRenderer, VideoViewFit;

import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../data/live_store.dart';
import '../../data/models.dart';
import '../player/lesson_player.dart';
import '../player/playback_rules.dart';
import 'live_speaker.dart';

/// "🎤 First Last is speaking", shown to the other Students (D-073).
class LiveSpeakerLabel extends StatelessWidget {
  const LiveSpeakerLabel({super.key, required this.speaker});

  final LiveSpeakerName speaker;

  @override
  Widget build(BuildContext context) {
    final String name = speaker.fullName;
    final String text = name.isEmpty
        ? context.tr('live.aStudentSpeaking')
        : context.trf('live.studentSpeaking', <String, String>{'name': name});
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Text(
        '\u{1F3A4} $text',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w700,
          fontSize: 12,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// The speaking Student's view (D-073): the Professor's camera full size
/// over the LiveKit conversation, the identity watermark, and only a small
/// "You are speaking" pill; "Tap to hear" when the audio did not start.
class LiveSpeakingStage extends StatefulWidget {
  const LiveSpeakingStage({
    super.key,
    required this.liveId,
    required this.speaker,
    required this.fullscreen,
  });

  final int liveId;
  final LiveSpeaker speaker;
  final bool fullscreen;

  @override
  State<LiveSpeakingStage> createState() => _LiveSpeakingStageState();
}

class _LiveSpeakingStageState extends State<LiveSpeakingStage> {
  Timer? _watermarkTimer;
  int _spot = 0;

  @override
  void initState() {
    super.initState();
    _watermarkTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (mounted) setState(() => _spot = (_spot + 1) % liveWatermarkSpots.length);
    });
  }

  @override
  void dispose() {
    _watermarkTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final StudentProfile? me = AppScope.of(context).profile;
    final Widget box = ColoredBox(
      color: Colors.black,
      child: ValueListenableBuilder<int>(
        valueListenable: widget.speaker.changes,
        builder: (BuildContext context, int _, Widget? child) {
          final VideoTrack? video = widget.speaker.presenterVideo;
          final WatermarkSpot spot = liveWatermarkSpots[_spot];
          return Stack(
            fit: StackFit.expand,
            children: [
              if (video != null)
                VideoTrackRenderer(video, fit: VideoViewFit.contain)
              else
                const _VideoPausedNotice(),
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints box) => IgnorePointer(
                  child: Stack(
                    children: [
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 1200),
                        curve: Curves.easeInOutCubic,
                        top: box.maxHeight * spot.top,
                        left: spot.right ? null : box.maxWidth * spot.inset,
                        right: spot.right ? box.maxWidth * spot.inset : null,
                        child: PlayerWatermark(
                          name: me?.fullName ?? '',
                          phone: me?.phone ?? '',
                          session: 'LIVE-${widget.liveId}',
                          strong: false,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              PositionedDirectional(top: 10, end: 10, child: _speakingPill(context)),
              child!,
            ],
          );
        },
        child: ValueListenableBuilder<bool>(
          valueListenable: widget.speaker.audioBlocked,
          builder: (BuildContext context, bool blocked, Widget? _) =>
              blocked ? _tapToHear(context) : const SizedBox.shrink(),
        ),
      ),
    );
    if (widget.fullscreen) return box;
    return AspectRatio(aspectRatio: 16 / 9, child: box);
  }

  Widget _speakingPill(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: NovaColors.onlineGreen,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.mic_rounded, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            context.tr('live.youAreSpeaking'),
            style: const TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w700,
              fontSize: 11,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tapToHear(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: PressableScale(
          onTap: () => widget.speaker.startAudio(),
          semanticLabel: context.tr('live.tapToHear'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(100),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.volume_up_rounded, size: 18, color: NovaColors.ink950),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    context.tr('live.tapToHear'),
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      color: NovaColors.ink950,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The Professor's picture is not arriving (the downlink cannot carry it,
/// or the camera is off): the conversation continues with audio.
class _VideoPausedNotice extends StatelessWidget {
  const _VideoPausedNotice();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_rounded, size: 28, color: Colors.white),
            const SizedBox(height: 10),
            Text(
              context.tr('live.videoPaused'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              context.tr('live.videoPausedBody'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 11.5,
                height: 1.4,
                color: NovaColors.textMutedOnDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
