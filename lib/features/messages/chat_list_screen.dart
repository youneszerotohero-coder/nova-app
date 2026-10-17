import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_dimens.dart';
import '../../core/widgets/hero_style.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/nova_page_header.dart';
import '../../core/widgets/page_scaffold.dart' show EmptyState;
import '../../data/chat_store.dart';
import '../account/dashboard_card.dart' show heroLabel, heroText;
import 'chat_format.dart';
import 'chat_room_screen.dart';
import 'chat_widgets.dart';

/// D-143: the signed-in user's group chats (Student or Teacher): the NOVA
/// announcements first, then the most recent conversations, each with its
/// last message, time, unread count and muted mark. Pull to refresh.
class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key, this.embedded = false});

  /// True when shown as a shell tab (no back button).
  final bool embedded;

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  bool _opened = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_opened) return;
    _opened = true;
    // Fresh counts each time the list opens.
    AppScope.of(context).chat.loadRooms();
  }

  @override
  Widget build(BuildContext context) {
    final ChatStore chat = AppScope.of(context).chat;
    return ListenableBuilder(
      listenable: chat,
      builder: (BuildContext context, _) {
        final int unread = chat.unreadTotal;
        return Scaffold(
          backgroundColor: NovaColors.paper,
          body: RefreshIndicator(
            onRefresh: chat.loadRooms,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(bottom: 40 + MediaQuery.paddingOf(context).bottom + (widget.embedded ? 80 : 0)),
              children: [
                NovaPageHeader(
                  title: context.tr('chat.title'),
                  kicker: unread > 0 ? context.trf('chat.unreadKicker', <String, String>{'n': '$unread'}) : context.tr('chat.kicker'),
                  showBack: !widget.embedded,
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Entrance(child: _body(context, chat)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context, ChatStore chat) {
    if (!chat.roomsLoaded) {
      if (chat.roomsError != null && !chat.loadingRooms) {
        return EmptyState(
          icon: Icons.wifi_off_rounded,
          hue: NovaHue.rose,
          title: context.tr('chat.loadFailed'),
          message: apiErrorText(context, chat.roomsError!),
          actionLabel: context.tr('common.retry'),
          onAction: chat.loadRooms,
        );
      }
      return const _Panel(child: Column(children: [_SkeletonRow(), _SkeletonRow(), _SkeletonRow()]));
    }
    if (chat.rooms.isEmpty) {
      return HeroEmpty(
        icon: Icons.forum_outlined,
        title: context.tr('chat.emptyTitle'),
        message: context.tr('chat.emptyMsg'),
      );
    }
    final List<ChatRoom> rooms = chat.rooms;
    return _Panel(
      child: Column(
        children: [
          for (int i = 0; i < rooms.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, indent: 74, color: NovaColors.borderOnLight),
            Entrance(
              delay: Duration(milliseconds: 30 * i),
              offset: 8,
              child: _RoomRow(key: ValueKey<int>(rooms[i].id), room: rooms[i]),
            ),
          ],
        ],
      ),
    );
  }
}

/// The list's card (`.notificationPanel`).
class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
      decoration: BoxDecoration(
        color: NovaColors.paperCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: NovaColors.borderOnLight),
        boxShadow: NovaDimens.shadowLift,
      ),
      child: child,
    );
  }
}

class _RoomRow extends StatelessWidget {
  const _RoomRow({super.key, required this.room});

  final ChatRoom room;

  @override
  Widget build(BuildContext context) {
    final ChatLastMessage? last = room.lastMessage;
    final bool unread = room.unreadCount > 0;
    final String title = chatRoomTitle(context, room);
    final String sender = last == null ? '' : chatNameOf(context, last.senderRole, last.senderName);
    return Material(
      color: room.isPublic ? NovaColors.accentMist.withValues(alpha: 0.55) : Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openChatRoom(Navigator.of(context), room.id),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
          child: Row(
            children: [
              Hero(tag: 'chat-avatar-${room.id}', child: ChatRoomAvatar(room: room, size: 52)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (room.isPublic) ...[
                          Icon(Icons.campaign_rounded, size: 16, color: NovaColors.accent),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: heroLabel(16),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          chatListTime(context, last?.createdAt ?? room.lastMessageAt),
                          style: heroText(12.5, color: unread ? NovaColors.accent : NovaColors.textMuted, weight: unread ? FontWeight.w700 : FontWeight.w500, height: 1.3),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (last != null && last.kind != ChatMessageKind.text) ...[
                          Icon(
                            last.kind == ChatMessageKind.voice ? Icons.mic_rounded : Icons.picture_as_pdf_rounded,
                            size: 15,
                            color: last.kind == ChatMessageKind.voice ? NovaColors.accent : NovaColors.heartRed,
                          ),
                          const SizedBox(width: 3),
                        ],
                        Expanded(
                          child: Text.rich(
                            TextSpan(children: [
                              if (last != null && sender.isNotEmpty && !room.isPublic)
                                TextSpan(
                                  text: '$sender: ',
                                  style: heroText(14, color: NovaColors.textStrong, weight: FontWeight.w600, height: 1.35),
                                ),
                              TextSpan(text: last == null ? context.tr('chat.noMessages') : chatPreview(context, last)),
                            ]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: heroText(14, color: unread ? NovaColors.textBody : NovaColors.textMuted, weight: unread ? FontWeight.w600 : FontWeight.w500, height: 1.35),
                          ),
                        ),
                        if (room.muted) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.notifications_off_rounded, size: 16, color: NovaColors.textMuted, semanticLabel: context.tr('chat.muted')),
                        ],
                        if (unread) ...[
                          const SizedBox(width: 6),
                          ChatUnreadPill(count: room.unreadCount, muted: room.muted),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A loading row: grey shapes where a room will be.
class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    Widget bar(double width, double height) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(color: NovaColors.subtleFill, borderRadius: BorderRadius.circular(8)),
        );
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(width: 52, height: 52, decoration: BoxDecoration(color: NovaColors.subtleFill, shape: BoxShape.circle)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [bar(140, 14), const SizedBox(height: 10), bar(double.infinity, 12)],
            ),
          ),
        ],
      ),
    );
  }
}
