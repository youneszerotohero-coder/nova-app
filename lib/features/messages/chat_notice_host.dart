import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/widgets/nova_toast.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../data/chat_store.dart';
import 'chat_audio.dart';
import 'chat_format.dart';
import 'chat_room_screen.dart';

/// D-143 in-app notice of a chat message (BR-C9), above every screen: a
/// message in the room on screen plays the soft receive sound; one for
/// another room also slides in the app's notification banner (sender and
/// preview) for 3 s, and tapping it opens that room. Own messages and
/// muted rooms never reach it ([ChatStore.arrivals]).
class ChatNoticeHost extends StatefulWidget {
  const ChatNoticeHost({super.key, required this.navigatorKey, required this.child});

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  static const Duration visibleFor = Duration(seconds: 3);

  @override
  State<ChatNoticeHost> createState() => _ChatNoticeHostState();
}

class _ChatNoticeHostState extends State<ChatNoticeHost> with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    reverseDuration: const Duration(milliseconds: 200),
  )..addStatusListener(_onStatus);
  late final Animation<double> _curve = CurvedAnimation(parent: _motion, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
  StreamSubscription<ChatArrival>? _subscription;
  Stream<ChatArrival>? _source;
  Timer? _timer;
  ChatArrival? _current;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final Stream<ChatArrival> source = AppScope.of(context).chat.arrivals;
    if (source == _source) return;
    _subscription?.cancel();
    _source = source;
    _subscription = source.listen(_onArrival);
  }

  void _onArrival(ChatArrival arrival) {
    if (!mounted) return;
    ChatSounds.received(soft: arrival.inOpenRoom);
    if (arrival.inOpenRoom) return;
    _timer?.cancel();
    setState(() => _current = arrival);
    _motion.forward();
    _timer = Timer(ChatNoticeHost.visibleFor, _hide);
  }

  void _hide() {
    _timer?.cancel();
    _motion.reverse();
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && _current != null && mounted) setState(() => _current = null);
  }

  void _open() {
    final ChatArrival? arrival = _current;
    if (arrival == null || _motion.status == AnimationStatus.reverse) return;
    _hide();
    final NavigatorState? navigator = widget.navigatorKey.currentState;
    if (navigator != null) openChatRoom(navigator, arrival.room.id);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _subscription?.cancel();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ChatArrival? current = _current;
    return Stack(
      children: [
        widget.child,
        if (current != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: FadeTransition(
                  opacity: _curve,
                  child: SlideTransition(
                    position: Tween<Offset>(begin: const Offset(0, -0.6), end: Offset.zero).animate(_curve),
                    child: _Notice(arrival: current, onTap: _open),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.arrival, required this.onTap});

  final ChatArrival arrival;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ChatMessage message = arrival.message;
    final String sender = chatNameOf(context, message.sender.role, message.sender.name);
    final String preview = switch (message.kind) {
      ChatMessageKind.voice => '🎤 ${context.tr('chat.voiceMessage')}',
      ChatMessageKind.pdf => '📄 ${message.attachment?.name ?? context.tr('chat.pdf')}',
      ChatMessageKind.text => message.body ?? '',
    };
    final String title = chatRoomTitle(context, arrival.room);
    return Semantics(
      liveRegion: true,
      child: PressableScale(
        onTap: onTap,
        semanticLabel: title,
        child: Material(
          type: MaterialType.transparency,
          child: NovaToastCard(
            message: title,
            detail: '$sender: $preview',
            icon: Icons.forum_rounded,
            tone: (NovaColors.accent, NovaColors.accentMist),
          ),
        ),
      ),
    );
  }
}
