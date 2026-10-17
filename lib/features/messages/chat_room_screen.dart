import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/widgets/nova_toast.dart';
import '../../core/widgets/page_scaffold.dart' show EmptyState;
import '../../core/widgets/hero_style.dart' show NovaButton, NovaButtonVariant;
import '../../data/chat_store.dart';
import 'chat_audio.dart';
import 'chat_bubble.dart';
import 'chat_composer.dart';
import 'chat_format.dart';
import 'chat_info_screen.dart';
import 'chat_pdf_screen.dart';
import 'chat_widgets.dart';

/// Opens room [roomId] above [navigator]'s pages; a room already on top
/// is replaced rather than stacked (in-app notice, push tap).
void openChatRoom(NavigatorState navigator, int roomId) {
  final ChatStore chat = AppState.instance.chat;
  final MaterialPageRoute<void> route = MaterialPageRoute<void>(
    settings: const RouteSettings(name: ChatRoomScreen.routeName),
    builder: (_) => ChatRoomScreen(roomId: roomId),
  );
  if (chat.activeRoom == roomId) return;
  if (chat.activeRoom != null) {
    navigator.pushReplacement(route);
  } else {
    navigator.push(route);
  }
}

/// D-143: one group chat. Messages newest at the bottom, 30 per page (older
/// pages while scrolling up, position kept), day separators, bubbles
/// grouped by sender; new messages slide in and scroll into view only when
/// the latest one is shown, otherwise "Jump to latest" counts them. The
/// room is read while its latest message is on screen.
class ChatRoomScreen extends StatefulWidget {
  const ChatRoomScreen({super.key, required this.roomId});

  final int roomId;

  static const String routeName = 'chat-room';

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final ScrollController _scroll = ScrollController();
  static const Key _center = ValueKey<String>('chat-center');

  late final ChatStore _chat;
  StreamSubscription<int>? _removed;
  AppLifecycleListener? _lifecycle;

  /// The newest message when the room first showed: older ones fill the
  /// list upwards, newer ones grow downwards without moving what is read.
  int? _anchor;

  /// Messages after it are "new" for the divider shown on opening.
  int? _unreadAfter;
  bool _atBottom = true;
  bool _covered = false;
  int _unseen = 0;
  String? _newestKey;
  int _count = 0;
  final Set<String> _shown = <String>{};

  int get _roomId => widget.roomId;

  @override
  void initState() {
    super.initState();
    _chat = AppState.instance.chat;
    _chat.setActive(_roomId, atBottom: true);
    _chat.addListener(_onStore);
    _removed = _chat.removedRooms.listen(_onRemoved);
    _scroll.addListener(_onScroll);
    _lifecycle = AppLifecycleListener(onResume: _readIfShown);
    _syncThread(initial: true);
    if (_chat.room(_roomId) == null) {
      _chat.refreshRoom(_roomId).catchError((Object _) => null);
    }
    _chat.openThread(_roomId);
  }

  @override
  void dispose() {
    _chat.leave(_roomId);
    _chat.removeListener(_onStore);
    _removed?.cancel();
    _lifecycle?.dispose();
    _scroll.dispose();
    ChatVoicePlayer.instance.stop();
    super.dispose();
  }

  void _syncThread({bool initial = false}) {
    if (_anchor != null || !_chat.threadLoaded(_roomId)) return;
    final List<ChatMessage> messages = _chat.messagesOf(_roomId);
    int newest = 0;
    for (final ChatMessage m in messages) {
      if (m.isConfirmed && m.id > newest) newest = m.id;
    }
    _anchor = newest;
    final ChatRoom? room = _chat.room(_roomId);
    if (room != null && room.unreadCount > 0) _unreadAfter = room.lastReadMessageId;
    for (final ChatMessage m in messages) {
      _shown.add(chatMessageKey(m));
    }
    _rememberNewest(messages);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.minScrollExtent);
      _readIfShown();
    });
    if (!initial && mounted) setState(() {});
  }

  void _rememberNewest(List<ChatMessage> messages) {
    _newestKey = messages.isEmpty ? null : chatMessageKey(messages.last);
    _count = messages.length;
  }

  /// The store changed: new messages scroll into view when the latest one
  /// was shown (always for one's own), or are counted on the jump button.
  void _onStore() {
    if (!mounted) return;
    if (_anchor == null) {
      _syncThread();
      if (_anchor != null) return;
    }
    final List<ChatMessage> messages = _chat.messagesOf(_roomId);
    final String? newest = messages.isEmpty ? null : chatMessageKey(messages.last);
    if (newest != null && newest != _newestKey && messages.length >= _count) {
      final int from = _newestKey == null ? 0 : messages.indexWhere((ChatMessage m) => chatMessageKey(m) == _newestKey) + 1;
      final List<ChatMessage> added = messages.sublist(from.clamp(0, messages.length));
      final bool own = added.any((ChatMessage m) => m.sender.id == _chat.me && !m.isConfirmed);
      if (_atBottom || own) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _toLatest());
      } else {
        _unseen += added.where((ChatMessage m) => m.sender.id != _chat.me).length;
      }
    }
    _rememberNewest(messages);
    setState(() {});
  }

  void _onRemoved(int roomId) {
    if (roomId != _roomId || !mounted) return;
    final NavigatorState navigator = Navigator.of(context);
    final Route<dynamic>? route = ModalRoute.of(context);
    novaToast(context, context.tr('chat.roomGone'), icon: Icons.info_outline_rounded);
    if (route != null && route.isActive) {
      navigator.popUntil((Route<dynamic> r) => r == route);
      navigator.maybePop();
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final ScrollPosition position = _scroll.position;
    final bool atBottom = position.pixels - position.minScrollExtent < 72;
    if (atBottom != _atBottom) {
      setState(() {
        _atBottom = atBottom;
        if (atBottom) _unseen = 0;
      });
    }
    _chat.setActive(_roomId, atBottom: atBottom && !_covered);
    if (atBottom) _readIfShown();
    if (position.maxScrollExtent - position.pixels < 500) _chat.loadOlder(_roomId);
  }

  /// The latest message is on screen and nothing covers the room.
  void _readIfShown() {
    if (!mounted || _covered || !_atBottom || !_chat.threadLoaded(_roomId)) return;
    final AppLifecycleState? state = WidgetsBinding.instance.lifecycleState;
    if (state != null && state != AppLifecycleState.resumed) return;
    _chat.markRead(_roomId);
  }

  Future<void> _toLatest() async {
    if (!_scroll.hasClients) return;
    setState(() => _unseen = 0);
    final ScrollPosition position = _scroll.position;
    final double distance = (position.pixels - position.minScrollExtent).abs();
    if (distance > 2400) {
      _scroll.jumpTo(position.minScrollExtent);
    } else {
      await _scroll.animateTo(position.minScrollExtent, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
    }
    // Pictures and new pages may have grown the list meanwhile.
    if (_scroll.hasClients && _scroll.position.pixels > _scroll.position.minScrollExtent + 1) {
      _scroll.jumpTo(_scroll.position.minScrollExtent);
    }
    _readIfShown();
  }

  /// Another page covers the room (info, PDF): it is not read meanwhile.
  Future<void> _cover(Widget page) async {
    _covered = true;
    _chat.leave(_roomId);
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    if (!mounted) return;
    _covered = false;
    _chat.setActive(_roomId, atBottom: _atBottom);
    _readIfShown();
  }

  void _openInfo() => _cover(ChatInfoScreen(roomId: _roomId));

  void _openPdf(ChatMessage message) =>
      _cover(ChatPdfScreen(roomId: _roomId, messageId: message.id, title: message.attachment?.name ?? 'PDF'));

  // ── Actions on a message ───────────────────────────────────────────────

  Future<void> _retry(ChatMessage message) async {
    final ApiException? error = await _chat.retry(_roomId, message.clientUuid!);
    if (!mounted) return;
    if (error == null) {
      ChatSounds.sent();
    } else {
      novaToast(context, chatErrorText(context, error), icon: Icons.error_outline_rounded);
    }
  }

  Future<void> _actions(ChatMessage message, ChatRoom room) async {
    final bool mine = message.sender.id == _chat.me;
    HapticFeedback.selectionClick();
    if (!message.isConfirmed) {
      if (message.state != ChatSendState.failed) return;
      final String? choice = await _sheet(<_Action>[
        _Action('retry', Icons.refresh_rounded, context.tr('chat.retry')),
        _Action('discard', Icons.delete_outline_rounded, context.tr('chat.delete'), danger: true),
      ]);
      if (choice == 'retry') _retry(message);
      if (choice == 'discard') _chat.discard(_roomId, message.clientUuid!);
      return;
    }
    final String text = message.body ?? '';
    final bool canDelete = mine || room.canModerate;
    final bool canSeeReaders = mine || room.canModerate;
    final String? choice = await _sheet(<_Action>[
      if (text.isNotEmpty) _Action('copy', Icons.content_copy_rounded, context.tr('chat.copy')),
      if (canSeeReaders) _Action('info', Icons.visibility_outlined, context.tr('chat.messageInfo')),
      if (canDelete) _Action('delete', Icons.delete_outline_rounded, context.tr('chat.delete'), danger: true),
    ]);
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: text));
        if (mounted) novaToast(context, context.tr('chat.copied'), icon: Icons.content_copy_rounded);
      case 'info':
        showModalBottomSheet<void>(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          builder: (_) => _SeenSheet(roomId: _roomId, message: message),
        );
      case 'delete':
        _delete(message);
    }
  }

  Future<String?> _sheet(List<_Action> actions) {
    if (actions.isEmpty) return Future<String?>.value();
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) => _SheetFrame(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final _Action action in actions)
              ListTile(
                leading: Icon(action.icon, color: action.danger ? NovaColors.heartRed : NovaColors.textStrong),
                title: Text(
                  action.label,
                  style: TextStyle(
                    fontFamily: NovaTypography.display,
                    fontFamilyFallback: NovaTypography.fallback,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: action.danger ? NovaColors.heartRed : NovaColors.textStrong,
                  ),
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                onTap: () => Navigator.of(context).pop(action.id),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(ChatMessage message) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: NovaColors.paperCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(context.tr('chat.deleteTitle'), style: NovaTypography.textTheme.titleLarge),
        content: Text(context.tr('chat.deleteBody'), style: NovaTypography.textTheme.bodyMedium!.copyWith(color: NovaColors.textBody)),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          NovaButton(label: context.tr('chat.cancel'), small: true, variant: NovaButtonVariant.ghost, onTap: () => Navigator.of(context).pop(false)),
          NovaButton(label: context.tr('chat.delete'), small: true, variant: NovaButtonVariant.danger, onTap: () => Navigator.of(context).pop(true)),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    ChatVoicePlayer.instance.stop(chatMessageKey(message));
    try {
      await _chat.deleteMessage(_roomId, message.id);
      if (mounted) novaToast(context, context.tr('chat.deleted'), icon: Icons.delete_outline_rounded);
    } on ApiException catch (error) {
      if (mounted) novaToast(context, apiErrorText(context, error), icon: Icons.error_outline_rounded);
    }
  }

  // ── Layout ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ChatRoom? room = _chat.room(_roomId);
    return Scaffold(
      backgroundColor: NovaColors.paper,
      body: Column(
        children: [
          _RoomBar(room: room, onInfo: room == null ? null : _openInfo),
          Expanded(child: room == null ? _placeholder(context) : _messages(context, room)),
          if (room != null) ChatComposer(room: room, onSent: () => WidgetsBinding.instance.addPostFrameCallback((_) => _toLatest())),
        ],
      ),
    );
  }

  Widget _placeholder(BuildContext context) => const Center(child: CircularProgressIndicator());

  Widget _messages(BuildContext context, ChatRoom room) {
    final ApiException? error = _chat.threadError(_roomId);
    if (!_chat.threadLoaded(_roomId)) {
      if (error != null) {
        return EmptyState(
          icon: Icons.forum_outlined,
          hue: NovaHue.rose,
          title: context.tr('chat.loadFailed'),
          message: apiErrorText(context, error),
          actionLabel: context.tr('common.retry'),
          onAction: () => _chat.loadLatest(_roomId),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }

    final List<ChatMessage> messages = _chat.messagesOf(_roomId);
    final int anchor = _anchor ?? 0;
    final List<Widget> older = <Widget>[];
    final List<Widget> newer = <Widget>[];
    bool unreadShown = false;
    for (int i = 0; i < messages.length; i++) {
      final ChatMessage m = messages[i];
      final ChatMessage? previous = i > 0 ? messages[i - 1] : null;
      final ChatMessage? next = i + 1 < messages.length ? messages[i + 1] : null;
      final bool mine = m.sender.id == _chat.me;
      final DateTime at = m.createdAt ?? DateTime.now();
      final bool newDay = previous == null || !chatSameDay(previous.createdAt ?? at, at);
      final int? unreadAfter = _unreadAfter;
      final bool unreadHere = !unreadShown && unreadAfter != null && m.isConfirmed && !mine && m.id > unreadAfter;
      if (unreadHere) unreadShown = true;
      final bool first = newDay || unreadHere || !_sameRun(previous, m);
      final bool last = next == null || !_sameRun(m, next) || !chatSameDay(at, next.createdAt ?? at);
      final String key = chatMessageKey(m);
      final bool animate = !_shown.contains(key);
      _shown.add(key);
      final Widget item = _Appear(
        key: ValueKey<String>(key),
        animate: animate,
        mine: mine,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (newDay) _DaySeparator(label: chatDayLabel(context, at)),
            if (unreadHere) const _UnreadSeparator(),
            ChatBubble(
              message: m,
              room: room,
              mine: mine,
              first: first,
              last: last,
              onTap: m.state == ChatSendState.failed ? () => _retry(m) : null,
              onLongPress: () => _actions(m, room),
              onOpenPdf: () => _openPdf(m),
            ),
          ],
        ),
      );
      if (m.isConfirmed && m.id <= anchor) {
        older.add(item);
      } else {
        newer.add(item);
      }
    }
    final List<Widget> olderNewestFirst = older.reversed.toList();
    final bool more = _chat.hasOlder(_roomId);

    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (_) => false,
          child: CustomScrollView(
            controller: _scroll,
            reverse: true,
            center: _center,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // Before the centre, laid out downwards: what arrived since
              // the room opened, oldest first, and the bottom margin.
              SliverPadding(
                padding: const EdgeInsets.only(bottom: 10),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (BuildContext context, int i) => newer[i],
                    childCount: newer.length,
                    findChildIndexCallback: (Key key) {
                      final int index = newer.indexWhere((Widget w) => w.key == key);
                      return index < 0 ? null : index;
                    },
                  ),
                ),
              ),
              // The centre, laid out upwards: the history, newest first.
              SliverList(
                key: _center,
                delegate: SliverChildBuilderDelegate(
                  (BuildContext context, int i) => olderNewestFirst[i],
                  childCount: olderNewestFirst.length,
                  findChildIndexCallback: (Key key) {
                    final int index = olderNewestFirst.indexWhere((Widget w) => w.key == key);
                    return index < 0 ? null : index;
                  },
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: more || _chat.loadingOlder(_roomId)
                      ? const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)))
                      : messages.isEmpty
                          ? _EmptyRoom(room: room)
                          : _Beginning(room: room),
                ),
              ),
            ],
          ),
        ),
        PositionedDirectional(
          end: 14,
          bottom: 14,
          child: _JumpButton(visible: !_atBottom, count: _unseen, onTap: _toLatest),
        ),
      ],
    );
  }

  /// Same sender within ten minutes: one run of bubbles.
  static bool _sameRun(ChatMessage? a, ChatMessage b) {
    if (a == null || a.sender.id != b.sender.id) return false;
    final DateTime? x = a.createdAt;
    final DateTime? y = b.createdAt;
    if (x == null || y == null) return true;
    return y.difference(x).abs() < const Duration(minutes: 10);
  }
}

class _Action {
  const _Action(this.id, this.icon, this.label, {this.danger = false});

  final String id;
  final IconData icon;
  final String label;
  final bool danger;
}

/// A new bubble slides up and fades in, once.
class _Appear extends StatefulWidget {
  const _Appear({super.key, required this.animate, required this.mine, required this.child});

  final bool animate;
  final bool mine;
  final Widget child;

  @override
  State<_Appear> createState() => _AppearState();
}

class _AppearState extends State<_Appear> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: widget.animate ? 0 : 1,
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animate) return widget.child;
    final Animation<double> curve = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween<Offset>(begin: Offset(widget.mine ? 0.04 : -0.04, 0.18), end: Offset.zero).animate(curve),
        child: widget.child,
      ),
    );
  }
}

class _DaySeparator extends StatelessWidget {
  const _DaySeparator({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 4),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: NovaColors.paperCard,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: NovaColors.borderOnLight),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: NovaTypography.display,
              fontFamilyFallback: NovaTypography.fallback,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
              height: 1.3,
              color: NovaColors.textBody,
            ),
          ),
        ),
      ),
    );
  }
}

class _UnreadSeparator extends StatelessWidget {
  const _UnreadSeparator();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 2),
      child: Row(
        children: [
          Expanded(child: Divider(color: NovaColors.accent.withValues(alpha: 0.35))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              context.tr('chat.newMessages'),
              style: TextStyle(
                fontFamily: NovaTypography.display,
                fontFamilyFallback: NovaTypography.fallback,
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
                color: NovaColors.accent,
              ),
            ),
          ),
          Expanded(child: Divider(color: NovaColors.accent.withValues(alpha: 0.35))),
        ],
      ),
    );
  }
}

/// The top of the history.
class _Beginning extends StatelessWidget {
  const _Beginning({required this.room});

  final ChatRoom room;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: NovaColors.accentMist, borderRadius: BorderRadius.circular(14)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline_rounded, size: 14, color: NovaColors.accent),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                context.tr(room.isPublic ? 'chat.beginningPublic' : 'chat.beginning'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: NovaTypography.body,
                  fontFamilyFallback: NovaTypography.fallback,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                  height: 1.35,
                  color: NovaColors.accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyRoom extends StatelessWidget {
  const _EmptyRoom({required this.room});

  final ChatRoom room;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Column(
        children: [
          ChatRoomAvatar(room: room, size: 72),
          const SizedBox(height: 14),
          Text(chatRoomTitle(context, room), textAlign: TextAlign.center, style: NovaTypography.textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            context.tr(room.canSend ? 'chat.emptyRoomWrite' : 'chat.emptyRoom'),
            textAlign: TextAlign.center,
            style: NovaTypography.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _JumpButton extends StatelessWidget {
  const _JumpButton({required this.visible, required this.count, required this.onTap});

  final bool visible;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedScale(
        scale: visible ? 1 : 0.6,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutBack,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 160),
          child: Semantics(
            button: true,
            label: context.tr('chat.jumpLatest'),
            child: GestureDetector(
              onTap: onTap,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: NovaColors.paperCard,
                      shape: BoxShape.circle,
                      border: Border.all(color: NovaColors.borderOnLight),
                      boxShadow: const <BoxShadow>[BoxShadow(offset: Offset(0, 8), blurRadius: 20, spreadRadius: -8, color: Color(0x66121A33))],
                    ),
                    child: Icon(Icons.keyboard_double_arrow_down_rounded, color: NovaColors.accent),
                  ),
                  if (count > 0)
                    PositionedDirectional(
                      top: -6,
                      end: -4,
                      child: ChatUnreadPill(count: count),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The room's bar: back, the room's picture and name, its members, info.
class _RoomBar extends StatelessWidget {
  const _RoomBar({required this.room, required this.onInfo});

  final ChatRoom? room;
  final VoidCallback? onInfo;

  @override
  Widget build(BuildContext context) {
    final ChatRoom? room = this.room;
    final double top = MediaQuery.paddingOf(context).top;
    final String subtitle = room == null
        ? ''
        : room.isPublic || room.teacher == null
            ? context.trf('chat.members', <String, String>{'n': '${room.membersCount}'})
            : '${room.teacher!.name} · ${context.trf('chat.members', <String, String>{'n': '${room.membersCount}'})}';
    return Container(
      padding: EdgeInsets.only(top: top),
      decoration: BoxDecoration(
        color: NovaColors.paperCard,
        border: Border(bottom: BorderSide(color: NovaColors.borderOnLight)),
      ),
      child: SizedBox(
        height: 64,
        child: Row(
          children: [
            const SizedBox(width: 4),
            ChatIconButton(
              icon: Icons.arrow_back_rounded,
              label: context.tr('common.back'),
              color: NovaColors.textStrong,
              onTap: () => Navigator.of(context).maybePop(),
            ),
            if (room != null) ...[
              Hero(tag: 'chat-avatar-${room.id}', child: ChatRoomAvatar(room: room, size: 42)),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onInfo,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              chatRoomTitle(context, room),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: NovaTypography.display,
                                fontFamilyFallback: NovaTypography.fallback,
                                fontWeight: FontWeight.w800,
                                fontSize: 17,
                                height: 1.25,
                                color: NovaColors.textStrong,
                              ),
                            ),
                          ),
                          if (room.muted) ...[
                            const SizedBox(width: 6),
                            Icon(Icons.notifications_off_rounded, size: 15, color: NovaColors.textMuted),
                          ],
                        ],
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: NovaTypography.body,
                          fontFamilyFallback: NovaTypography.fallback,
                          fontWeight: FontWeight.w500,
                          fontSize: 12.5,
                          height: 1.3,
                          color: NovaColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              ChatIconButton(
                icon: Icons.info_outline_rounded,
                label: context.tr('chat.info'),
                color: NovaColors.textStrong,
                onTap: onInfo,
              ),
              const SizedBox(width: 4),
            ] else
              const Spacer(),
          ],
        ),
      ),
    );
  }
}

/// The white sheet the message actions sit in.
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(10, 10, 10, 12 + MediaQuery.paddingOf(context).bottom),
      decoration: BoxDecoration(
        color: NovaColors.paperCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: NovaColors.lineStrong, borderRadius: BorderRadius.circular(4))),
          const SizedBox(height: 8),
          Material(type: MaterialType.transparency, child: child),
        ],
      ),
    );
  }
}

/// "Message info": who read the message, and when, by pages of 50 with the total.
class _SeenSheet extends StatefulWidget {
  const _SeenSheet({required this.roomId, required this.message});

  final int roomId;
  final ChatMessage message;

  @override
  State<_SeenSheet> createState() => _SeenSheetState();
}

class _SeenSheetState extends State<_SeenSheet> {
  final List<ChatPerson> _readers = <ChatPerson>[];
  int _total = 0;
  int _page = 0;
  bool _hasMore = false;
  bool _loading = true;
  Object? _error;

  ChatStore? _chat;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_chat == null) {
      _chat = AppScope.of(context).chat;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ChatMembersPage page = await _chat!.seenBy(widget.roomId, widget.message.id, page: _page + 1);
      if (!mounted) return;
      setState(() {
        _readers.addAll(page.members.where((ChatPerson p) => !_readers.any((ChatPerson r) => r.userId == p.userId)));
        _total = page.total;
        _hasMore = page.hasMore;
        _page += 1;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool firstLoad = _page == 0;
    return _SheetFrame(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
              child: Text(
                firstLoad ? context.tr('chat.messageInfo') : context.trf('chat.seenBy', <String, String>{'n': '$_total'}),
                style: NovaTypography.textTheme.titleLarge,
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(apiErrorText(context, _error!), style: NovaTypography.textTheme.bodySmall),
              )
            else if (firstLoad && _loading)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            else if (_readers.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(context.tr('chat.seenNobody'), textAlign: TextAlign.center, style: NovaTypography.textTheme.bodySmall),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _readers.length + (_hasMore ? 1 : 0),
                  itemBuilder: (BuildContext context, int i) {
                    if (i == _readers.length) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Center(
                          child: _loading
                              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.4))
                              : TextButton(
                                  onPressed: _load,
                                  child: Text(context.trf('chat.seenMore', <String, String>{'shown': '${_readers.length}', 'total': '$_total'})),
                                ),
                        ),
                      );
                    }
                    final ChatPerson person = _readers[i];
                    final DateTime? at = person.readAt;
                    return ListTile(
                      leading: ChatPersonAvatar(userId: person.userId, role: person.role, name: person.name, photoUrl: person.avatarUrl, size: 38),
                      title: Row(
                        children: [
                          Flexible(child: Text(chatNameOf(context, person.role, person.name), maxLines: 1, overflow: TextOverflow.ellipsis, style: NovaTypography.textTheme.titleSmall)),
                          const SizedBox(width: 6),
                          ChatRoleBadge(role: person.role),
                        ],
                      ),
                      subtitle: at == null ? null : Text('${chatDayLabel(context, at)} · ${chatClock(at)}', style: NovaTypography.textTheme.bodySmall),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
