import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/utils/player_fullscreen.dart';
import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/realtime/reverb_client.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/nova_scene_image.dart';
import '../../core/widgets/nova_toast.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../data/json.dart';
import '../../data/live_store.dart';
import '../../data/models.dart';
import '../player/live_player.dart';
import '../player/playback_rules.dart';
import 'live_comment_reply.dart';
import 'live_pinned_comment.dart';
import 'live_speaker.dart';
import 'live_speaking_stage.dart';
import 'live_waiting_room.dart';
import 'open_course.dart';

/// The Student's hand, web `live-room.tsx` states.
enum _Hand { passive, pending, connecting, interactive }

/// Live room for an owned course: the protected broadcast (or its
/// replay), the private question composer — write-only, per the
/// conception — and raise-hand to speak with the microphone once the
/// teaching team accepts.
class LiveRoomScreen extends StatefulWidget {
  const LiveRoomScreen({super.key, required this.live, @visibleForTesting this.speakerFactory});

  final LiveSession live;

  /// Tests: a speaker without a LiveKit room.
  final LiveSpeaker Function(VoidCallback onDropped)? speakerFactory;

  @override
  State<LiveRoomScreen> createState() => _LiveRoomScreenState();
}

class _LiveRoomScreenState extends State<LiveRoomScreen> {
  /// The broadcast runs ~12 s behind the Professor (the packager's
  /// suggested presentation delay, D-065), so "X is speaking" follows the
  /// realtime event by the same offset (web `PASSIVE_SPEAKER_LABEL_DELAY_MS`).
  static const Duration speakerLabelDelay = Duration(seconds: 12);

  final TextEditingController _question = TextEditingController();
  final GlobalKey _playerKey = GlobalKey();
  final Random _random = Random();

  LiveDetail? _detail;
  Duration _skew = Duration.zero;
  String? _loadError;
  bool _sending = false;
  bool _fullscreen = false;
  int? _viewers;

  /// D-181 (Live 69: the presence missed the apps): the server's count of Students watching, read every 30 s.
  int? _audience;
  Timer? _audienceTimer;

  _Hand _hand = _Hand.passive;
  LiveSpeaker? _speaker;

  /// The speaker of an accepted hand until it is connected: the turn can
  /// end meanwhile, and it must close too (Live 66, 2026-10-30).
  LiveSpeaker? _connecting;

  /// The speaking stage's downlink cannot carry the Professor's camera
  /// ([LiveSpeaker.downlinkWeak]).
  bool _downlinkWeak = false;

  /// The turn is ending: the conversation is closing.
  bool _endingHand = false;

  /// The Student waited in this room's waiting room (web
  /// `wasInWaitingRoom`): the reveal is held after the doors open (D-128).
  bool _waited = false;

  /// Who is speaking, as the other Students see it (D-073).
  LiveSpeakerName? _speakerName;
  bool _speakerFromRealtime = false;

  /// D-186: the comment the Admin pinned, from the Live and its broadcasts.
  LivePinnedComment? _pinned;

  /// D-204: the Admin's private answers to this Student's comments (newest
  /// first) and, per Live for the app session, the ones the Student hid.
  List<LiveCommentReply> _replies = const <LiveCommentReply>[];
  static final Map<int, Set<int>> _hiddenRepliesByLive = <int, Set<int>>{};
  Set<int> get _hiddenReplies => _hiddenRepliesByLive.putIfAbsent(_id, () => <int>{});
  LiveCommentReply? get _visibleReply => _replies.where((LiveCommentReply reply) => !_hiddenReplies.contains(reply.id)).firstOrNull;
  final Set<Timer> _speakerTimers = <Timer>{};

  Timer? _poll;
  Timer? _clock;
  final List<VoidCallback> _channels = <VoidCallback>[];
  VoidCallback? _presence;

  LiveStore get _store => AppState.instance.live!;
  ReverbClient? get _realtime => AppState.instance.realtime;
  int get _id => widget.live.id;

  @override
  void initState() {
    super.initState();
    _load();
    _listen();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && (_detail?.isLive ?? false)) setState(() {});
    });
    _audienceTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refreshAudience());
  }

  /// Only the audience count: the rest of the room keeps its realtime updates.
  Future<void> _refreshAudience() async {
    if (!(_detail?.isLive ?? false)) return;
    try {
      final int? count = await _store.audience(_id);
      if (mounted && count != null) setState(() => _audience = count);
    } catch (_) {
      // The next tick tries again; the last count stays shown.
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _clock?.cancel();
    _audienceTimer?.cancel();
    for (final Timer timer in _speakerTimers) {
      timer.cancel();
    }
    for (final VoidCallback stop in _channels) {
      stop();
    }
    _presence?.call();
    _speaker?.close();
    _connecting?.close();
    if (_hand == _Hand.pending || _hand == _Hand.interactive || _hand == _Hand.connecting) {
      _store.lowerHand(_id).catchError((Object _) {});
    }
    if (_fullscreen) exitPlayerFullscreen();
    _question.dispose();
    super.dispose();
  }

  // Data ----------------------------------------------------------------

  Future<void> _load() async {
    try {
      final LiveDetail detail = await _store.detail(_id);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loadError = null;
        if (detail.serverTime != null) _skew = detail.serverTime!.difference(DateTime.now());
        if (detail.inWaitingRoom) _waited = true;
        // Realtime is the fresher source once it has spoken.
        if (!_speakerFromRealtime) _speakerName = detail.isLive ? detail.speaker : null;
        _pinned = detail.pinnedComment;
        _replies = detail.commentReplies;
      });
      if (detail.isOver && detail.live.lessonId != null) {
        _openLesson(detail.live);
        return;
      }
      _applyHandStatus(detail.handStatus);
      if (detail.muted) _speaker?.setMicrophone(false);
      _watchPresence(detail.isLive);
    } on ApiException catch (error) {
      if (mounted) setState(() => _loadError = apiErrorText(context, error));
    }
    _schedulePoll();
  }

  /// D-132: a finished Live is a Lesson of its Unit; the room gives way to it.
  void _openLesson(LiveSession live) {
    final AppState app = AppScope.of(context);
    final NavigatorState navigator = Navigator.of(context);
    // D-207: the Lesson of a Unit of the Live this Student holds (older servers: the Live's one Course).
    final Course? course = app.learning.owned
            .where((Course c) => live.replayLessons.containsKey(c.slug))
            .firstOrNull ??
        app.learning.owned.where((Course c) => c.slug == live.courseSlug).firstOrNull;
    if (course == null) return;
    navigator.pop();
    openOwnedCourse(navigator.context, course, lessonId: live.replayLessons[course.slug] ?? live.lessonId);
  }

  /// Web cadence: every 20 s with realtime, every 8 s without, while the
  /// Live is starting or its media is not ready; without realtime the
  /// room also keeps polling while live so it notices the end.
  void _schedulePoll() {
    _poll?.cancel();
    final LiveDetail? detail = _detail;
    final bool realtime = _realtime?.connected.value ?? false;
    final bool needed = detail == null ||
        detail.isWaiting ||
        (detail.isLive && (detail.mediaState != 'ready' || !realtime));
    if (!needed) return;
    _poll = Timer(Duration(seconds: realtime ? 20 : 8), _load);
  }

  void _listen() {
    final ReverbClient? client = _realtime;
    final StudentProfile? me = AppState.instance.profile;
    if (client == null || !client.configured || me == null) return;
    _channels.add(client.subscribe('private-student.${me.studentId}', (String event, Json data) {
      if (data.integer('live_id') != _id) return;
      if (event == 'LiveStateChanged') _load();
      if (event == 'LiveHandChanged') _applyHandStatus(data.strOrNull('status'));
      if (event == 'LivePinnedCommentChanged') _applyPinned(data);
      if (event == 'LiveCommentReplied') _applyReply(data);
    }));
  }

  /// Presence on `live.{id}` while the Live runs: the viewer count.
  void _watchPresence(bool live) {
    final ReverbClient? client = _realtime;
    if (client == null || !client.configured) return;
    if (live && _presence == null) {
      _presence = client.subscribe('presence-live.$_id', (String event, Json data) {
        if (event == 'presence' && mounted) setState(() => _viewers = data.integer('count'));
        if (event == 'LiveStateChanged') _load();
        if (event == 'LiveSpeakerChanged') _announceSpeaker(LiveSpeakerName.fromJson(data.obj('speaker')));
        if (event == 'LivePinnedCommentChanged') _applyPinned(data);
      });
    } else if (!live && _presence != null) {
      _presence!();
      _presence = null;
    }
  }

  /// `LivePinnedCommentChanged` (D-186): the Admin pinned another comment,
  /// or removed it (null); shown at once, also on the student channel.
  void _applyPinned(Json data) {
    if (data.integer('live_id') != _id || !mounted) return;
    setState(() => _pinned = LivePinnedComment.fromJson(data.obj('pinned_comment')));
  }

  /// `LiveCommentReplied` (D-204): the Admin answered one of this Student's
  /// comments; shown over the picture at once.
  void _applyReply(Json data) {
    final LiveCommentReply? reply = LiveCommentReply.fromJson(data.obj('reply'));
    if (reply == null || !mounted || _replies.any((LiveCommentReply known) => known.id == reply.id)) return;
    setState(() => _replies = <LiveCommentReply>[reply, ..._replies]);
  }

  void _hideReply(int id) => setState(() => _hiddenReplies.add(id));

  /// The answer card over the picture, under the speaker label when one is shown.
  Widget? _replyOverlay({required bool isLive, required bool speakerShown, required double top}) {
    final LiveCommentReply? reply = _visibleReply;
    if (!isLive || reply == null) return null;
    return PositionedDirectional(
      top: speakerShown ? top + 46 : top,
      start: 12,
      end: 12,
      child: Center(child: LiveCommentReplyCard(reply: reply, onHide: () => _hideReply(reply.id))),
    );
  }

  /// `LiveSpeakerChanged` (D-073): shown to the other Students once the
  /// delayed broadcast reaches the moment the speaker changed.
  void _announceSpeaker(LiveSpeakerName? speaker) {
    _speakerFromRealtime = true;
    late final Timer timer;
    timer = Timer(speakerLabelDelay, () {
      _speakerTimers.remove(timer);
      if (mounted) setState(() => _speakerName = speaker);
    });
    _speakerTimers.add(timer);
  }

  /// A Student action while the Live is momentarily locked (409
  /// `LIVE_BUSY`, D-071) is retried with jittered back-off before an error
  /// is shown.
  Future<T> _retryBusy<T>(Future<T> Function() action) async {
    for (int attempt = 1;; attempt++) {
      try {
        return await action();
      } on ApiException catch (error) {
        if (error.code != 'LIVE_BUSY' || attempt >= 4 || !mounted) rethrow;
        await Future<void>.delayed(liveRetryDelay(attempt, _random));
      }
    }
  }

  // Questions -----------------------------------------------------------

  Future<void> _sendQuestion() async {
    final String message = _question.text.trim();
    if (message.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _retryBusy(() => _store.ask(_id, message));
      if (!mounted) return;
      _question.clear();
      FocusScope.of(context).unfocus();
      novaToast(context, context.tr('live.messageSent'), icon: Icons.mark_email_read_rounded);
    } on ApiException catch (error) {
      if (mounted) novaToast(context, apiErrorText(context, error), icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // Hand ----------------------------------------------------------------

  Future<void> _toggleHand() async {
    try {
      if (_hand == _Hand.passive) {
        await _retryBusy(() => _store.raiseHand(_id));
        if (mounted) setState(() => _hand = _Hand.pending);
      } else {
        await _lowerHand();
      }
    } on ApiException catch (error) {
      if (mounted) novaToast(context, apiErrorText(context, error), icon: Icons.error_outline_rounded);
    }
  }

  Future<void> _lowerHand() async {
    await _closeSpeaker();
    if (mounted) setState(() => _hand = _Hand.passive);
    await _retryBusy(() => _store.lowerHand(_id));
  }

  /// The team lowered the hand or removed the speaking Student.
  Future<void> _endHand() async {
    if (_endingHand) return;
    _endingHand = true;
    await _closeSpeaker();
    _endingHand = false;
    if (mounted) setState(() => _hand = _Hand.passive);
  }

  /// The conversation closes before the turn ends (LiveKit's voices and, on
  /// iPhone, its audio session), so the kept broadcast is never heard over
  /// it (owner decision 2026-10-30). Bounded: a conversation that cannot
  /// close does not hold the broadcast back.
  Future<void> _closeSpeaker() async {
    final LiveSpeaker? connecting = _connecting;
    _connecting = null;
    if (connecting != null) {
      await connecting.close().timeout(const Duration(seconds: 2), onTimeout: () {}).catchError((Object _) {});
    }
    final LiveSpeaker? speaker = _speaker;
    if (speaker == null) return;
    speaker.changes.removeListener(_onSpeakerChanges);
    await speaker.close().timeout(const Duration(seconds: 2), onTimeout: () {}).catchError((Object _) {});
    if (identical(_speaker, speaker)) _speaker = null;
    _downlinkWeak = false;
  }

  void _applyHandStatus(String? status) {
    switch (status) {
      case 'pending':
        if (_hand == _Hand.passive && mounted) setState(() => _hand = _Hand.pending);
      case 'accepted':
        if (_hand != _Hand.connecting && _hand != _Hand.interactive) _connectSpeaker();
      default:
        if (_hand != _Hand.passive) unawaited(_endHand());
    }
  }

  Future<void> _connectSpeaker() async {
    setState(() => _hand = _Hand.connecting);
    void dropped() {
      if (!mounted) return;
      novaToast(context, context.tr('live.speakerDropped'), icon: Icons.mic_off_rounded);
      _lowerHand().catchError((Object _) {});
    }

    final LiveSpeaker speaker = widget.speakerFactory?.call(dropped) ?? LiveSpeaker(onDropped: dropped);
    _connecting = speaker;
    // Accept → microphone published: the audio session is set while the
    // grant is requested, then the connection and the microphone capture
    // run together; only the publication waits for both.
    speaker.prepareAudio();
    try {
      final SpeakerGrant grant = await _retryBusy(() => _store.speaker(_id));
      // The turn ended while the grant was requested: already closed.
      if (!identical(_connecting, speaker)) return;
      await speaker.connect(grant);
      if (!identical(_connecting, speaker) || !mounted) {
        // Ended while connecting: closed, never shown, never heard.
        await speaker.close();
        return;
      }
      _connecting = null;
      if (_detail?.muted ?? false) await speaker.setMicrophone(false);
      _speaker = speaker;
      speaker.changes.addListener(_onSpeakerChanges);
      setState(() {
        _hand = _Hand.interactive;
        _downlinkWeak = speaker.downlinkWeak;
      });
    } catch (error) {
      final bool ended = !identical(_connecting, speaker);
      if (!ended) _connecting = null;
      await speaker.close();
      if (!mounted || ended) return;
      novaToast(
        context,
        error is ApiException ? apiErrorText(context, error) : context.tr('live.micUnavailable'),
        icon: Icons.mic_off_rounded,
      );
      await _lowerHand().catchError((Object _) {});
    }
  }

  void _onSpeakerChanges() {
    // The team removed the Student in LiveKit: the turn is over, even
    // before (or without) the realtime event saying so.
    if (_speaker?.removed ?? false) return unawaited(_endHand());
    final bool weak = _speaker?.downlinkWeak ?? false;
    if (weak != _downlinkWeak && mounted) setState(() => _downlinkWeak = weak);
  }

  // Fullscreen ----------------------------------------------------------

  Future<void> _setFullscreen(bool value) async {
    setState(() => _fullscreen = value);
    await (value ? enterPlayerFullscreen() : exitPlayerFullscreen());
  }

  // UI ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final LiveDetail? detail = _detail;
    // D-117: a prepared Live behind closed doors, and the D-128 reveal
    // delay, are shown as the wait; the 1 s clock rebuild ends the delay.
    final bool isLive = detail != null &&
        detail.showsBroadcast(waited: _waited, serverNow: DateTime.now().add(_skew));
    final Widget? player = detail == null ? null : _player(detail, broadcast: isLive);
    final bool speakerShown = isLive && _speakerName != null && _hand != _Hand.interactive && _hand != _Hand.connecting;
    final Widget? replyOverlay = _replyOverlay(isLive: isLive, speakerShown: speakerShown, top: _fullscreen ? 14 : 12);

    if (_fullscreen && player != null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (bool didPop, Object? _) {
          if (!didPop) _setFullscreen(false);
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              SizedBox.expand(child: player),
              if (speakerShown)
                PositionedDirectional(
                  top: 14,
                  start: 16,
                  end: 16,
                  child: Center(child: LiveSpeakerLabel(speaker: _speakerName!)),
                ),
              ?replyOverlay,
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: NovaColors.ink950,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(context, detail, isLive: isLive),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  NovaSceneImage(
                    scene: widget.live.scene,
                    image: widget.live.image,
                    icon: Icons.videocam_rounded,
                    iconScale: 1.4,
                  ),
                  ColoredBox(color: NovaColors.ink950.withValues(alpha: 0.72)),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: detail == null
                          ? _message(
                              context,
                              _loadError == null ? null : Icons.error_outline_rounded,
                              _loadError ?? context.tr('live.connecting'),
                            )
                          : player ?? _statusCard(context, detail),
                    ),
                  ),
                  if (speakerShown)
                    PositionedDirectional(
                      top: 12,
                      start: 16,
                      end: 16,
                      child: Center(child: LiveSpeakerLabel(speaker: _speakerName!)),
                    ),
                  ?replyOverlay,
                ],
              ),
            ),
            if (detail == null || !detail.isOver) _composer(context, detail),
          ],
        ),
      ),
    );
  }

  LivePlayer? _lastPlayer;

  /// The same widget while its inputs are unchanged, so the 1 s clock
  /// rebuild of the room and its polls skip the player and its native
  /// picture (2026-10-30, iPhone picture not fluid). The player reads only
  /// the Live's id.
  LivePlayer _livePlayer(LiveDetail detail, {required bool speaking}) {
    final LivePlayer? last = _lastPlayer;
    final bool weak = speaking && _downlinkWeak;
    if (last != null &&
        last.live.id == detail.live.id &&
        last.mediaState == detail.mediaState &&
        last.fullscreen == _fullscreen &&
        last.suspended == speaking &&
        last.downlinkWeak == weak) {
      return last;
    }
    return _lastPlayer = LivePlayer(
      key: _playerKey,
      live: detail.live,
      mediaState: detail.mediaState,
      onWithdrawn: _load,
      fullscreen: _fullscreen,
      onToggleFullscreen: () => _setFullscreen(!_fullscreen),
      suspended: speaking,
      downlinkWeak: weak,
    );
  }

  Widget? _player(LiveDetail detail, {required bool broadcast}) {
    final LiveSpeaker? speaker = _speaker;
    final bool speaking = detail.isLive && _hand == _Hand.interactive && speaker != null;
    if (!broadcast && !speaking) return null;
    // While the Student speaks the Professor stays full size over the
    // conversation (D-073), and the broadcast player is kept under the
    // stage, muted and hidden, so the turn's end shows it again at once
    // (owner decision 2026-10-30, amends D-066 for the apps). The tree is
    // the same in both states: the native player is never moved.
    return ClipRRect(
      borderRadius: BorderRadius.circular(_fullscreen ? 0 : 18),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          if (broadcast)
            IgnorePointer(
              ignoring: speaking,
              child: ExcludeSemantics(
                excluding: speaking,
                child: _livePlayer(detail, speaking: speaking),
              ),
            ),
          if (speaking)
            LiveSpeakingStage(key: ObjectKey(speaker), liveId: _id, speaker: speaker, fullscreen: _fullscreen),
        ],
      ),
    );
  }

  Widget _statusCard(BuildContext context, LiveDetail detail) {
    if (detail.isLive && !detail.doorsClosed) {
      // D-128: the doors just opened; the first picture is on its way.
      return _message(context, null, context.tr('live.starting'));
    }
    if (detail.inWaitingRoom) {
      return LiveWaitingRoom(
        endsAt: detail.live.waitingRoomEndsAt,
        countsDown: detail.status == 'scheduled' || detail.doorsClosed,
        serverNow: () => DateTime.now().add(_skew),
        presence: () => _store.waitingRoomPresence(_id),
      );
    }
    if (detail.isWaiting) {
      final DateTime? at = detail.live.scheduledAt;
      return _message(
        context,
        Icons.schedule_rounded,
        at == null
            ? context.tr('live.waiting')
            : context.trf('live.waitingAt', {'t': detail.live.scheduledLabel ?? ''}),
      );
    }
    return _message(
      context,
      Icons.event_available_rounded,
      switch (detail.status) {
        'cancelled' => context.tr('live.cancelled'),
        'failed' => context.tr('live.failed'),
        'processing_replay' || 'ending' => context.tr('live.replaySoon'),
        _ => context.tr('live.ended'),
      },
    );
  }

  Widget _message(BuildContext context, IconData? icon, String text) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon == null)
          const SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
          )
        else
          Icon(icon, size: 34, color: Colors.white),
        const SizedBox(height: 14),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Geist',
            fontWeight: FontWeight.w600,
            fontSize: 14,
            height: 1.45,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _header(BuildContext context, LiveDetail? detail, {required bool isLive}) {
    final String? mediaLabel = !isLive
        ? null
        : switch (detail?.mediaState) {
            'preparing' => context.tr('live.startingShort'),
            'recovering' => context.tr('live.reconnecting'),
            'unavailable' => context.tr('live.interruptedShort'),
            _ => null,
          };
    final Duration? elapsed = isLive ? detail?.classElapsed(DateTime.now().add(_skew)) : null;
    final String? clock = elapsed == null ? null : clockLabel(elapsed);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 20, 6),
      child: Row(
        children: [
          FrostedIconButton(
            icon: Icons.arrow_back_rounded,
            semanticLabel: context.tr('common.back'),
            size: 40,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (isLive)
                      Pulse(
                        child: Icon(Icons.circle_rounded, size: 9, color: NovaColors.heartRed),
                      ),
                    if (isLive) const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        <String>[
                          context.tr('live.class'),
                          ?clock,
                          ?mediaLabel,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Geist',
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  widget.live.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Geist',
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: NovaColors.textMutedOnDark,
                  ),
                ),
              ],
            ),
          ),
          if (isLive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Row(
                children: [
                  const Icon(Icons.visibility_rounded, size: 13, color: NovaColors.textMutedOnDark),
                  const SizedBox(width: 5),
                  Text(
                    // D-181: the Students watching now (presence, else the server's count), never the attended total.
                    '${_audience ?? detail?.live.watchingNow ?? _viewers ?? '—'}',
                    style: const TextStyle(
                      fontFamily: 'Geist',
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      color: NovaColors.textOnDark,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _composer(BuildContext context, LiveDetail? detail) {
    final bool canAsk = detail != null &&
        !detail.isOver &&
        !detail.muted &&
        detail.live.commentsEnabled;
    final bool canRaise = detail?.isLive ?? false;

    return Container(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom),
      color: NovaColors.ink950,
      child: Column(
        children: [
          // D-186: the pinned comment at the top of the Live chat.
          if (_pinned != null) ...<Widget>[
            LivePinnedCommentBanner(comment: _pinned!),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _question,
                  enabled: canAsk,
                  maxLength: detail?.live.commentMaxLength ?? 500,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendQuestion(),
                  style: const TextStyle(fontFamily: 'Geist', fontSize: 13.5, color: NovaColors.textOnDark),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: canAsk ? context.tr('live.questionHint') : context.tr('live.questionsClosed'),
                    hintStyle: const TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 12.5,
                      color: NovaColors.textMutedOnDark,
                    ),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(100),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              PressableScale(
                onTap: canAsk && !_sending ? _sendQuestion : null,
                semanticLabel: 'Send question',
                child: Opacity(
                  opacity: canAsk ? 1 : 0.4,
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: const BoxDecoration(
                      gradient: NovaColors.accentGradient,
                      shape: BoxShape.circle,
                    ),
                    child: _sending
                        ? const Padding(
                            padding: EdgeInsets.all(13),
                            child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                          )
                        : const Icon(Icons.send_rounded, size: 20, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
          if (canRaise) ...[
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: _handButton(context)),
          ],
        ],
      ),
    );
  }

  Widget _handButton(BuildContext context) {
    final bool active = _hand != _Hand.passive;
    final (IconData icon, String key) = switch (_hand) {
      _Hand.passive => (Icons.back_hand_rounded, 'live.raiseHand'),
      _Hand.pending => (Icons.front_hand_rounded, 'live.handInQueue'),
      _Hand.connecting => (Icons.settings_voice_rounded, 'live.connectingMic'),
      _Hand.interactive => (Icons.mic_rounded, 'live.speakingLower'),
    };
    return PressableScale(
      onTap: _hand == _Hand.connecting ? null : _toggleHand,
      semanticLabel: context.tr(key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _hand == _Hand.interactive
              ? NovaColors.onlineGreen
              : active
                  ? NovaColors.accent
                  : Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: active ? Colors.transparent : Colors.white.withValues(alpha: 0.16),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutBack,
              child: Icon(icon, key: ValueKey<_Hand>(_hand), size: 19, color: Colors.white),
            ),
            const SizedBox(width: 9),
            Text(
              context.tr(key),
              style: const TextStyle(
                fontFamily: 'Geist',
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
