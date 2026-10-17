import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/nova_api.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/widgets/hero_style.dart';
import '../../core/widgets/nova_toast.dart';
import '../../data/chat_store.dart';
import 'chat_audio.dart';
import 'chat_format.dart';
import 'chat_widgets.dart';

/// A send failure in the user's words (writing closed, file refused,
/// too many messages…).
String chatErrorText(BuildContext context, ApiException error) {
  final Iterable<String> details = error.fieldErrors.values;
  bool says(String code) => error.code == code || details.any((String d) => d.contains(code));
  if (says('CHAT_SEND_CLOSED')) return context.tr('chat.errClosed');
  if (says('CHAT_KIND_FORBIDDEN')) return context.tr('chat.errKind');
  if (says('CHAT_FORBIDDEN')) return context.tr('chat.errForbidden');
  if (says('VOICE_TOO_LONG')) return context.tr('chat.errVoiceLong');
  if (says('VOICE_UNREADABLE')) return context.tr('chat.errVoiceUnreadable');
  if (error.status == 429) return context.tr('chat.errTooFast');
  if (error.status == 413) return context.tr('chat.pdfTooBig');
  return apiErrorText(context, error);
}

/// The bottom of a room: the text field with send, the microphone (when
/// voice notes are allowed) and the PDF button (Teacher); or the locked
/// banner when this user cannot write here.
class ChatComposer extends StatefulWidget {
  const ChatComposer({super.key, required this.room, required this.onSent});

  final ChatRoom room;

  /// An own message was added at the bottom: the room scrolls to it.
  final VoidCallback onSent;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();

  ChatRecorder? _recorder;
  StreamSubscription<double>? _levelsSub;
  /// Time recorded so far: the ticker's own count of periods (exact even
  /// when a frame is late).
  Duration _elapsed = Duration.zero;
  Timer? _ticker;
  static const Duration _tick = Duration(milliseconds: 200);
  bool _recording = false;
  bool _busy = false;
  final List<double> _levels = <double>[];

  ChatStore get _chat => AppScope.of(context).chat;

  @override
  void dispose() {
    _ticker?.cancel();
    _levelsSub?.cancel();
    final ChatRecorder? recorder = _recorder;
    if (recorder != null) {
      // Leaving the room while recording sends nothing.
      if (_recording) recorder.cancel().catchError((Object _) {});
      recorder.dispose().catchError((Object _) {});
    }
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _deliver(Future<ApiException?> sending) async {
    widget.onSent();
    final ApiException? error = await sending;
    if (!mounted) return;
    if (error == null) {
      ChatSounds.sent();
    } else if (error.code != NovaApi.cancelled) {
      novaToast(context, chatErrorText(context, error), icon: Icons.error_outline_rounded);
    }
  }

  void _sendText() {
    final String text = _text.text.trim();
    if (text.isEmpty) return;
    _text.clear();
    HapticFeedback.lightImpact();
    _deliver(_chat.sendText(widget.room.id, text));
  }

  // ── Voice ────────────────────────────────────────────────────────────

  Future<void> _startRecording() async {
    if (_busy || _recording) return;
    _busy = true;
    final ChatRecorder recorder = _recorder ??= ChatRecorder.factory();
    try {
      if (!await recorder.hasPermission()) {
        if (mounted) novaToast(context, context.tr('chat.micDenied'), icon: Icons.mic_off_rounded);
        return;
      }
      await ChatVoicePlayer.instance.stop();
      await recorder.start();
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      _levels.clear();
      _elapsed = Duration.zero;
      _levelsSub = recorder.levels.listen((double level) {
        if (mounted) setState(() => _levels.add(level));
      });
      _ticker = Timer.periodic(_tick, (Timer timer) {
        if (!mounted) return;
        _elapsed = _tick * timer.tick;
        if (_elapsed >= ChatStore.maxVoice) {
          // The 5-minute cap: what was said is sent.
          _sendRecording();
        } else {
          setState(() {});
        }
      });
      setState(() => _recording = true);
    } catch (_) {
      if (mounted) novaToast(context, context.tr('chat.recordFailed'), icon: Icons.error_outline_rounded);
    } finally {
      _busy = false;
    }
  }

  void _stopClock() {
    _ticker?.cancel();
    _ticker = null;
    _levelsSub?.cancel();
    _levelsSub = null;
  }

  Future<void> _cancelRecording() async {
    if (!_recording || _busy) return;
    _busy = true;
    _stopClock();
    HapticFeedback.selectionClick();
    try {
      await _recorder?.cancel();
    } catch (_) {
      // Nothing to discard.
    }
    _busy = false;
    if (mounted) setState(() => _recording = false);
  }

  Future<void> _sendRecording() async {
    if (!_recording || _busy) return;
    _busy = true;
    final Duration duration = _elapsed > ChatStore.maxVoice ? ChatStore.maxVoice : _elapsed;
    _stopClock();
    String? path;
    try {
      path = await _recorder?.stop();
    } catch (_) {
      path = null;
    }
    _busy = false;
    if (!mounted) return;
    setState(() => _recording = false);
    if (path == null || duration < const Duration(milliseconds: 800)) {
      novaToast(context, context.tr('chat.voiceTooShort'), icon: Icons.mic_none_rounded);
      return;
    }
    HapticFeedback.lightImpact();
    _deliver(_chat.sendVoice(widget.room.id, path: path, durationMs: duration.inMilliseconds, waveform: waveformOf(_levels)));
  }

  // ── PDF ──────────────────────────────────────────────────────────────

  Future<void> _pickPdf() async {
    final List<PlatformFile> files;
    try {
      files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const <String>['pdf']);
    } catch (_) {
      return;
    }
    final PlatformFile? picked = files.isEmpty ? null : files.first;
    final String? path = picked?.path;
    if (picked == null || path == null || !mounted) return;
    final int size = await File(path).length();
    if (!mounted) return;
    if (size > ChatStore.maxPdfBytes) {
      novaToast(context, context.tr('chat.pdfTooBig'), icon: Icons.error_outline_rounded);
      return;
    }
    final String? caption = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChatPdfSendSheet(name: picked.name, size: size),
    );
    if (caption == null || !mounted) return;
    HapticFeedback.lightImpact();
    _deliver(_chat.sendPdf(widget.room.id, path: path, name: picked.name, caption: caption));
  }

  @override
  Widget build(BuildContext context) {
    final ChatRoom room = widget.room;
    final double bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      decoration: BoxDecoration(
        color: NovaColors.paperCard,
        border: Border(top: BorderSide(color: NovaColors.borderOnLight)),
      ),
      padding: EdgeInsets.fromLTRB(8, 8, 8, 8 + (MediaQuery.viewInsetsOf(context).bottom > 0 ? 0 : bottom)),
      child: !room.canSend
          ? _LockedBanner(room: room)
          : AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              transitionBuilder: (Widget child, Animation<double> a) => FadeTransition(
                opacity: a,
                child: SlideTransition(position: Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero).animate(a), child: child),
              ),
              child: _recording ? _recordingBar(context) : _inputBar(context, room),
            ),
    );
  }

  Widget _inputBar(BuildContext context, ChatRoom room) {
    return Row(
      key: const ValueKey<String>('composer-input'),
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (room.canSendPdf)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: ChatIconButton(icon: Icons.attach_file_rounded, label: context.tr('chat.attachPdf'), onTap: _pickPdf),
          ),
        Expanded(
          child: Container(
            constraints: const BoxConstraints(minHeight: 46),
            decoration: BoxDecoration(
              color: NovaColors.paperRaised,
              borderRadius: BorderRadius.circular(23),
              border: Border.all(color: NovaColors.borderOnLight),
            ),
            child: TextField(
              controller: _text,
              focusNode: _focus,
              minLines: 1,
              maxLines: 5,
              maxLength: ChatStore.maxTextLength,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              buildCounter: (BuildContext context, {required int currentLength, required bool isFocused, required int? maxLength}) =>
                  currentLength > ChatStore.maxTextLength - 200
                      ? Padding(
                          padding: const EdgeInsetsDirectional.only(end: 14, bottom: 4),
                          child: Text('$currentLength/${ChatStore.maxTextLength}', style: TextStyle(fontSize: 11, color: NovaColors.textMuted)),
                        )
                      : null,
              style: TextStyle(
                fontFamily: NovaTypography.body,
                fontFamilyFallback: NovaTypography.fallback,
                fontWeight: FontWeight.w500,
                fontSize: 15.5,
                height: 1.35,
                color: NovaColors.textStrong,
              ),
              decoration: InputDecoration(
                hintText: context.tr('chat.writeHint'),
                hintStyle: TextStyle(
                  fontFamily: NovaTypography.body,
                  fontFamilyFallback: NovaTypography.fallback,
                  fontSize: 15,
                  color: NovaColors.textMuted,
                ),
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _text,
          builder: (BuildContext context, TextEditingValue value, _) {
            final bool showSend = value.text.trim().isNotEmpty || !room.canSendVoice;
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (Widget child, Animation<double> a) => ScaleTransition(scale: a, child: child),
              child: showSend
                  ? ChatIconButton(
                      key: const ValueKey<String>('send'),
                      icon: Icons.send_rounded,
                      label: context.tr('chat.send'),
                      gradient: true,
                      size: 46,
                      onTap: value.text.trim().isEmpty ? null : _sendText,
                    )
                  : ChatIconButton(
                      key: const ValueKey<String>('mic'),
                      icon: Icons.mic_rounded,
                      label: context.tr('chat.record'),
                      gradient: true,
                      size: 46,
                      onTap: _startRecording,
                    ),
            );
          },
        ),
      ],
    );
  }

  Widget _recordingBar(BuildContext context) {
    final Duration elapsed = _elapsed;
    final bool nearCap = ChatStore.maxVoice - elapsed < const Duration(seconds: 30);
    return SizedBox(
      key: const ValueKey<String>('composer-recording'),
      height: 48,
      child: Row(
        children: [
          ChatIconButton(
            icon: Icons.delete_outline_rounded,
            label: context.tr('chat.cancelRecording'),
            color: NovaColors.heartRed,
            onTap: _cancelRecording,
          ),
          const SizedBox(width: 6),
          const _RecordingDot(),
          const SizedBox(width: 8),
          Text(
            chatDuration(elapsed),
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontFamily: NovaTypography.body,
              fontWeight: FontWeight.w700,
              fontSize: 15,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              color: nearCap ? NovaColors.heartRed : NovaColors.textStrong,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 30,
              child: CustomPaint(painter: _LevelsPainter(levels: _levels, color: NovaColors.accent, rtl: Directionality.of(context) == TextDirection.rtl)),
            ),
          ),
          const SizedBox(width: 8),
          ChatIconButton(icon: Icons.send_rounded, label: context.tr('chat.sendVoice'), gradient: true, size: 46, onTap: _sendRecording),
        ],
      ),
    );
  }
}

/// The red dot that breathes while recording.
class _RecordingDot extends StatefulWidget {
  const _RecordingDot();

  @override
  State<_RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<_RecordingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: context.tr('chat.recording'),
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.35, end: 1).animate(_pulse),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.8, end: 1.1).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: NovaColors.heartRed,
              shape: BoxShape.circle,
              boxShadow: <BoxShadow>[BoxShadow(color: NovaColors.heartRed.withValues(alpha: 0.45), blurRadius: 8)],
            ),
          ),
        ),
      ),
    );
  }
}

/// The live input level, newest bar at the reading end.
class _LevelsPainter extends CustomPainter {
  _LevelsPainter({required this.levels, required this.color, required this.rtl}) : _count = levels.length;

  final List<double> levels;
  final Color color;
  final bool rtl;
  final int _count;

  @override
  void paint(Canvas canvas, Size size) {
    const double bar = 2.6;
    const double gap = 2.2;
    final int slots = ((size.width + gap) / (bar + gap)).floor();
    final Paint paint = Paint();
    for (int i = 0; i < slots; i++) {
      // i = 0 is the newest level.
      final int index = levels.length - 1 - i;
      final double level = index >= 0 ? levels[index] : 0;
      final double h = 3 + level * (size.height - 3);
      final double fromEnd = i * (bar + gap) + bar;
      final double x = rtl ? fromEnd - bar : size.width - fromEnd;
      paint.color = index >= 0 ? color : color.withValues(alpha: 0.25);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, (size.height - h) / 2, bar, h), const Radius.circular(bar)), paint);
    }
  }

  @override
  bool shouldRepaint(_LevelsPainter old) => old._count != _count || old.color != color || old.rtl != rtl;
}

class _LockedBanner extends StatelessWidget {
  const _LockedBanner({required this.room});

  final ChatRoom room;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey<String>('composer-locked'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: NovaColors.paperRaised, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Icon(room.isPublic ? Icons.campaign_rounded : Icons.lock_rounded, size: 18, color: NovaColors.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.tr(room.isPublic ? 'chat.lockedPublic' : 'chat.lockedGroup'),
              style: TextStyle(
                fontFamily: NovaTypography.body,
                fontFamilyFallback: NovaTypography.fallback,
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
                height: 1.4,
                color: NovaColors.textBody,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Before a PDF is sent: its name and size, and an optional caption.
/// Pops the caption ('' for none), or null when cancelled.
class ChatPdfSendSheet extends StatefulWidget {
  const ChatPdfSendSheet({super.key, required this.name, required this.size});

  final String name;
  final int size;

  @override
  State<ChatPdfSendSheet> createState() => _ChatPdfSendSheetState();
}

class _ChatPdfSendSheetState extends State<ChatPdfSendSheet> {
  final TextEditingController _caption = TextEditingController();

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final NovaLang lang = AppScope.of(context).lang;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        padding: EdgeInsets.fromLTRB(18, 10, 18, 18 + MediaQuery.paddingOf(context).bottom),
        decoration: BoxDecoration(
          color: NovaColors.paperCard,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(width: 40, height: 4, decoration: BoxDecoration(color: NovaColors.lineStrong, borderRadius: BorderRadius.circular(4))),
            ),
            const SizedBox(height: 16),
            Text(context.tr('chat.sendPdfTitle'), style: NovaTypography.textTheme.titleLarge),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: NovaColors.paperRaised,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: NovaColors.borderOnLight),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: NovaColors.dangerBg, borderRadius: BorderRadius.circular(10)),
                    child: Icon(Icons.picture_as_pdf_rounded, color: NovaColors.heartRed),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(chatFileName(widget.name), maxLines: 2, overflow: TextOverflow.ellipsis, style: NovaTypography.textTheme.titleSmall),
                        const SizedBox(height: 2),
                        Text(chatIsolate('${chatFileSize(widget.size, lang)} · PDF'), style: NovaTypography.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _caption,
              maxLength: ChatStore.maxCaptionLength,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(hintText: context.tr('chat.captionHint')),
            ),
            const SizedBox(height: 8),
            NovaButton(
              label: context.tr('chat.send'),
              icon: Icons.send_rounded,
              expand: true,
              onTap: () => Navigator.of(context).pop(_caption.text.trim()),
            ),
          ],
        ),
      ),
    );
  }
}
