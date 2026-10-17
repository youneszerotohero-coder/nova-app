import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/widgets/nova_toast.dart';
import '../../data/chat_store.dart';
import 'chat_audio.dart';
import 'chat_format.dart';
import 'chat_widgets.dart';

/// The key of a message on screen: its id, or its `client_uuid` while it
/// is not sent yet (so the bubble keeps its state when it is confirmed).
String chatMessageKey(ChatMessage message) => message.clientUuid != null ? 'u${message.clientUuid}' : 'm${message.id}';

/// One message: own messages on the end side on the blue gradient, the
/// others on the card surface with their name colour, avatar and badge;
/// grouped by sender ([first]/[last] of a run), the time on every bubble,
/// ticks or "Seen by N" on own messages, pending and failed states.
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.message,
    required this.room,
    required this.mine,
    required this.first,
    required this.last,
    this.onTap,
    this.onLongPress,
    this.onOpenPdf,
  });

  final ChatMessage message;
  final ChatRoom room;
  final bool mine;

  /// First and last bubble of a run by the same sender.
  final bool first;
  final bool last;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onOpenPdf;

  static const double avatarSize = 30;

  @override
  Widget build(BuildContext context) {
    final double maxWidth = math.min(MediaQuery.sizeOf(context).width * 0.78, 440);
    final bool failed = message.state == ChatSendState.failed;
    const Radius round = Radius.circular(20);
    const Radius tight = Radius.circular(6);
    // A run of bubbles is joined on the sender's side; its first bubble is
    // round there, every later one tight, the last one ends on the tail.
    final BorderRadiusDirectional radius = mine
        ? BorderRadiusDirectional.only(topStart: round, bottomStart: round, topEnd: first ? round : tight, bottomEnd: tight)
        : BorderRadiusDirectional.only(topEnd: round, bottomEnd: round, topStart: first ? round : tight, bottomStart: tight);

    final Widget content = switch (message.kind) {
      ChatMessageKind.voice => ChatVoiceContent(message: message, mine: mine),
      ChatMessageKind.pdf => _PdfContent(message: message, mine: mine, onOpen: onOpenPdf),
      ChatMessageKind.text => _TextContent(text: message.body ?? '', mine: mine),
    };

    final Widget bubble = Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      decoration: BoxDecoration(
        gradient: mine ? NovaColors.accentGradient : null,
        color: mine ? null : NovaColors.paperCard,
        borderRadius: radius,
        border: mine ? null : Border.all(color: NovaColors.borderOnLight),
        boxShadow: mine
            ? const <BoxShadow>[BoxShadow(offset: Offset(0, 6), blurRadius: 16, spreadRadius: -10, color: Color(0x881F54D6))]
            : const <BoxShadow>[BoxShadow(offset: Offset(0, 4), blurRadius: 12, spreadRadius: -8, color: Color(0x33121A33))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!mine && first) ...[
            _SenderLine(sender: message.sender),
            const SizedBox(height: 3),
          ],
          content,
          const SizedBox(height: 3),
          Align(alignment: AlignmentDirectional.centerEnd, widthFactor: 1, child: _Meta(message: message, room: room, mine: mine)),
        ],
      ),
    );

    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(10, first ? 10 : 2, 10, 0),
      child: Column(
        crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!mine) ...[
                SizedBox(
                  width: avatarSize,
                  child: last
                      ? ChatPersonAvatar(
                          userId: message.sender.id,
                          role: message.sender.role,
                          name: message.sender.name,
                          photoUrl: message.sender.avatarUrl,
                          size: avatarSize,
                        )
                      : null,
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Opacity(
                    opacity: message.state == ChatSendState.pending && message.kind == ChatMessageKind.text ? 0.82 : 1,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onTap,
                      onLongPress: onLongPress,
                      child: bubble,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (failed)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 4, end: 4),
              child: GestureDetector(
                onTap: onTap,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline_rounded, size: 14, color: NovaColors.heartRed),
                    const SizedBox(width: 4),
                    Text(
                      context.tr('chat.notSent'),
                      style: TextStyle(
                        fontFamily: NovaTypography.body,
                        fontFamilyFallback: NovaTypography.fallback,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: NovaColors.heartRed,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SenderLine extends StatelessWidget {
  const _SenderLine({required this.sender});

  final ChatSender sender;

  @override
  Widget build(BuildContext context) {
    final bool staff = sender.role != ChatRole.student;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            chatNameOf(context, sender.role, sender.name),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: NovaTypography.display,
              fontFamilyFallback: NovaTypography.fallback,
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
              height: 1.25,
              color: sender.role == ChatRole.admin ? NovaColors.accent : chatHueOf(sender.id),
            ),
          ),
        ),
        if (staff) ...[
          const SizedBox(width: 6),
          ChatRoleBadge(role: sender.role),
        ],
      ],
    );
  }
}

class _TextContent extends StatelessWidget {
  const _TextContent({required this.text, required this.mine});

  final String text;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textDirection: chatTextDirection(text),
      style: TextStyle(
        fontFamily: NovaTypography.body,
        fontFamilyFallback: NovaTypography.fallback,
        fontWeight: FontWeight.w500,
        fontSize: 15.5,
        height: 1.42,
        color: mine ? Colors.white : NovaColors.textStrong,
      ),
    );
  }
}

/// The time, then ✓ / ✓✓ on a Student's own message (✓✓ once the Teacher
/// or the Admin read it), or "Seen by N" on the Teacher's.
class _Meta extends StatelessWidget {
  const _Meta({required this.message, required this.room, required this.mine});

  final ChatMessage message;
  final ChatRoom room;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final Color ink = mine ? Colors.white.withValues(alpha: 0.78) : NovaColors.textMuted;
    final TextStyle style = TextStyle(
      fontFamily: NovaTypography.body,
      fontFamilyFallback: NovaTypography.fallback,
      fontWeight: FontWeight.w600,
      fontSize: 11,
      height: 1.2,
      color: ink,
    );
    final bool staffSender = message.sender.role != ChatRole.student;
    final int? seen = message.seenCount;
    final List<Widget> children = <Widget>[];
    if (mine && staffSender && seen != null && message.isConfirmed) {
      children
        ..add(Icon(Icons.visibility_rounded, size: 12, color: ink))
        ..add(const SizedBox(width: 3))
        ..add(Text(context.trf('chat.seenBy', <String, String>{'n': '$seen'}), style: style))
        ..add(const SizedBox(width: 6));
    }
    children.add(Text(chatClock(message.createdAt), style: style));
    if (mine) {
      final Widget tick = switch (message.state) {
        ChatSendState.pending => Icon(Icons.schedule_rounded, key: const ValueKey<String>('tick-pending'), size: 13, color: ink),
        ChatSendState.failed => const Icon(Icons.error_rounded, key: ValueKey<String>('tick-failed'), size: 13, color: Color(0xFFFFC9C9)),
        ChatSendState.sent => staffSender
            ? Icon(Icons.done_rounded, key: const ValueKey<String>('tick-sent'), size: 14, color: ink)
            : message.id <= room.staffLastReadMessageId
                ? Icon(Icons.done_all_rounded, key: const ValueKey<String>('tick-seen'), size: 15, color: NovaColors.yellow, semanticLabel: context.tr('chat.seenByTeacher'))
                : Icon(Icons.done_rounded, key: const ValueKey<String>('tick-sent'), size: 14, color: ink, semanticLabel: context.tr('chat.sent')),
      };
      children
        ..add(const SizedBox(width: 3))
        ..add(AnimatedSwitcher(duration: const Duration(milliseconds: 200), child: tick));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}

// ── PDF ────────────────────────────────────────────────────────────────

class _PdfContent extends StatelessWidget {
  const _PdfContent({required this.message, required this.mine, this.onOpen});

  final ChatMessage message;
  final bool mine;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final ChatAttachment? file = message.attachment;
    final NovaLang lang = AppScope.of(context).lang;
    final bool pending = message.state == ChatSendState.pending;
    final String caption = message.body ?? '';
    final Color ink = mine ? Colors.white : NovaColors.textStrong;
    final Color mute = mine ? Colors.white.withValues(alpha: 0.78) : NovaColors.textMuted;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: message.isConfirmed ? onOpen : null,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: mine ? Colors.white.withValues(alpha: 0.14) : NovaColors.paperRaised,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: mine ? Colors.white.withValues(alpha: 0.18) : NovaColors.borderOnLight),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (pending)
                  _UploadRing(message: message, mine: mine, size: 42)
                else
                  Container(
                    width: 42,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: mine ? Colors.white : NovaColors.dangerBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.picture_as_pdf_rounded, size: 24, color: NovaColors.heartRed),
                  ),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chatFileName(file?.name ?? 'document.pdf'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textDirection: chatTextDirection(file?.name ?? ''),
                        style: TextStyle(
                          fontFamily: NovaTypography.body,
                          fontFamilyFallback: NovaTypography.fallback,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          height: 1.3,
                          color: ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        pending
                            ? context.trf('chat.uploading', <String, String>{'p': '${((message.progress ?? 0) * 100).round()}'})
                            : chatIsolate('${chatFileSize(file?.size ?? 0, lang)} · PDF'),
                        style: TextStyle(
                          fontFamily: NovaTypography.body,
                          fontFamilyFallback: NovaTypography.fallback,
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                          height: 1.3,
                          color: mute,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!pending && message.isConfirmed) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.open_in_full_rounded, size: 16, color: mute),
                ],
              ],
            ),
          ),
        ),
        if (caption.isNotEmpty) ...[
          const SizedBox(height: 6),
          _TextContent(text: caption, mine: mine),
        ],
      ],
    );
  }
}

/// A voice note or PDF on its way: the upload progress with a cancel.
class _UploadRing extends StatelessWidget {
  const _UploadRing({required this.message, required this.mine, this.size = 40});

  final ChatMessage message;
  final bool mine;
  final double size;

  @override
  Widget build(BuildContext context) {
    final Color ink = mine ? Colors.white : NovaColors.accent;
    return Semantics(
      button: true,
      label: context.tr('chat.cancelUpload'),
      child: GestureDetector(
        onTap: () => AppScope.of(context).chat.cancelUpload(message.roomId, message.clientUuid!),
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: size - 4,
                height: size - 4,
                child: CircularProgressIndicator(
                  value: (message.progress ?? 0) < 0.02 ? null : message.progress,
                  strokeWidth: 3,
                  color: ink,
                  backgroundColor: ink.withValues(alpha: 0.2),
                ),
              ),
              Icon(Icons.close_rounded, size: size * 0.45, color: ink),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Voice ──────────────────────────────────────────────────────────────

/// A voice note: play/pause, the waveform (tap or drag to seek), the time,
/// and 1× / 1.5× / 2× while it plays. Streamed from the signed URL.
class ChatVoiceContent extends StatelessWidget {
  const ChatVoiceContent({super.key, required this.message, required this.mine});

  final ChatMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final ChatVoicePlayer player = ChatVoicePlayer.instance;
    final String key = chatMessageKey(message);
    final ChatAttachment? file = message.attachment;
    final Duration known = Duration(milliseconds: file?.durationMs ?? 0);
    final bool pending = message.state == ChatSendState.pending;
    final Color played = mine ? Colors.white : NovaColors.accent;
    final Color rest = mine ? Colors.white.withValues(alpha: 0.42) : NovaColors.lineStrong;
    final double width = math.min(MediaQuery.sizeOf(context).width * 0.62, 260);

    return ListenableBuilder(
      listenable: player,
      builder: (BuildContext context, _) {
        final VoiceState state = player.stateOf(key);
        final Duration total = player.durationOf(key, known);
        final Duration position = player.positionOf(key);
        final double progress = total.inMilliseconds <= 0 ? 0 : (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
        final bool active = state != VoiceState.idle;

        Future<void> toggle() async {
          final ChatStore chat = AppScope.of(context).chat;
          final bool local = !message.isConfirmed;
          try {
            await player.toggle(
              key,
              local: local,
              known: known,
              source: () async => local ? message.localPath! : (await chat.fileLink(message.roomId, message.id)).url,
            );
          } catch (_) {
            if (context.mounted) novaToast(context, context.tr('chat.voiceUnavailable'), icon: Icons.error_outline_rounded);
          }
        }

        void seekTo(double dx, double barWidth) {
          if (!active || barWidth <= 0) return;
          final bool rtl = Directionality.of(context) == TextDirection.rtl;
          final double fraction = (rtl ? barWidth - dx : dx) / barWidth;
          player.seek(key, fraction, known);
        }

        return SizedBox(
          width: width,
          child: Row(
            children: [
              if (pending)
                _UploadRing(message: message, mine: mine)
              else
                _PlayButton(state: state, mine: mine, onTap: toggle),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LayoutBuilder(
                      builder: (BuildContext context, BoxConstraints constraints) => GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (TapDownDetails d) => seekTo(d.localPosition.dx, constraints.maxWidth),
                        onHorizontalDragUpdate: (DragUpdateDetails d) => seekTo(d.localPosition.dx, constraints.maxWidth),
                        child: SizedBox(
                          height: 30,
                          width: double.infinity,
                          child: CustomPaint(
                            key: ValueKey<String>('waveform-$key'),
                            painter: ChatWaveformPainter(
                              peaks: file?.waveform ?? const <int>[],
                              progress: progress,
                              played: played,
                              rest: rest,
                              rtl: Directionality.of(context) == TextDirection.rtl,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          chatDuration(active && position > Duration.zero ? position : total),
                          style: TextStyle(
                            fontFamily: NovaTypography.body,
                            fontWeight: FontWeight.w600,
                            fontSize: 11.5,
                            height: 1.2,
                            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                            color: mine ? Colors.white.withValues(alpha: 0.85) : NovaColors.textMuted,
                          ),
                        ),
                        const Spacer(),
                        AnimatedOpacity(
                          opacity: active ? 1 : 0,
                          duration: const Duration(milliseconds: 180),
                          child: _SpeedChip(speed: player.speed, mine: mine, onTap: active ? player.cycleSpeed : null),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.state, required this.mine, required this.onTap});

  final VoiceState state;
  final bool mine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool playing = state == VoiceState.playing;
    return Semantics(
      button: true,
      label: context.tr(playing ? 'chat.pause' : 'chat.play'),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, color: mine ? Colors.white : NovaColors.accent),
          child: state == VoiceState.loading
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.4, color: mine ? NovaColors.accent : Colors.white),
                )
              : AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  transitionBuilder: (Widget child, Animation<double> a) => ScaleTransition(scale: a, child: child),
                  child: Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    key: ValueKey<bool>(playing),
                    size: 24,
                    color: mine ? NovaColors.accent : Colors.white,
                  ),
                ),
        ),
      ),
    );
  }
}

class _SpeedChip extends StatelessWidget {
  const _SpeedChip({required this.speed, required this.mine, this.onTap});

  final double speed;
  final bool mine;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final String label = speed == speed.roundToDouble() ? '${speed.round()}×' : '$speed×';
    return Semantics(
      button: true,
      label: context.trf('chat.speed', <String, String>{'x': label}),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: mine ? Colors.white.withValues(alpha: 0.22) : NovaColors.accentMist,
            borderRadius: BorderRadius.circular(100),
          ),
          child: Text(
            label,
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontFamily: NovaTypography.body,
              fontWeight: FontWeight.w700,
              fontSize: 11,
              height: 1.2,
              color: mine ? Colors.white : NovaColors.accent,
            ),
          ),
        ),
      ),
    );
  }
}

/// The voice note's bars: the server's peaks (0..100) resampled to the
/// width, the played part in the strong colour, from the reading start.
class ChatWaveformPainter extends CustomPainter {
  ChatWaveformPainter({required this.peaks, required this.progress, required this.played, required this.rest, this.rtl = false});

  final List<int> peaks;
  final double progress;
  final Color played;
  final Color rest;
  final bool rtl;

  static const double bar = 2.6;
  static const double gap = 2.2;

  /// [count] bar heights 0..1 from [peaks] (flat when there are none).
  static List<double> resample(List<int> peaks, int count) {
    if (count <= 0) return const <double>[];
    if (peaks.isEmpty) return List<double>.filled(count, 0.16);
    return List<double>.generate(count, (int i) {
      final double from = i * peaks.length / count;
      final double to = math.max(from + 1, (i + 1) * peaks.length / count);
      int peak = 0;
      for (int j = from.floor(); j < to.ceil() && j < peaks.length; j++) {
        peak = math.max(peak, peaks[j]);
      }
      return (peak / 100).clamp(0.12, 1.0);
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final int count = ((size.width + gap) / (bar + gap)).floor();
    final List<double> heights = resample(peaks, count);
    final Paint paint = Paint()..strokeCap = StrokeCap.round;
    final double playedBars = progress * count;
    for (int i = 0; i < count; i++) {
      final double h = math.max(3, heights[i] * size.height);
      final double x = rtl ? size.width - (i * (bar + gap)) - bar : i * (bar + gap);
      paint.color = i < playedBars ? played : rest;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, (size.height - h) / 2, bar, h), const Radius.circular(bar)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(ChatWaveformPainter old) =>
      old.progress != progress || old.peaks != peaks || old.played != played || old.rest != rest || old.rtl != rtl;
}
