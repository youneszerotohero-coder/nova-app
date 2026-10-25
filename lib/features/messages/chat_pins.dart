import 'package:flutter/material.dart';

import '../../core/i18n/nova_strings.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_typography.dart';
import '../../data/chat_store.dart';
import 'chat_format.dart';
import 'chat_widgets.dart';

/// D-156 BR-X2 pinned messages: the bar under the room's app bar and the
/// list of pins.

/// "Sender: line" of a pinned message.
String chatPinLine(BuildContext context, ChatMessage message) =>
    '${chatNameOf(context, message.sender.role, message.sender.name)}: ${chatMessageLine(context, message)}';

/// The newest pin (tap: jump to it) and "N pinned messages" (the list).
class ChatPinnedBar extends StatelessWidget {
  const ChatPinnedBar({super.key, required this.room, required this.pins, required this.onJump, required this.onList});

  final ChatRoom room;

  /// Newest pinned first; empty while loading.
  final List<ChatMessage> pins;
  final ValueChanged<ChatMessage> onJump;
  final VoidCallback onList;

  @override
  Widget build(BuildContext context) {
    final ChatMessage? newest = pins.isEmpty ? null : pins.first;
    final int count = room.pinnedCount > pins.length ? room.pinnedCount : pins.length;
    final String title = count > 1 ? context.trf('chat.pinnedMany', <String, String>{'n': '$count'}) : context.tr('chat.pinnedOne');
    return Material(
      key: const ValueKey<String>('chat-pinned-bar'),
      color: NovaColors.paperCard,
      child: InkWell(
        onTap: newest == null ? onList : () => onJump(newest),
        child: Container(
          padding: const EdgeInsetsDirectional.fromSTEB(14, 8, 4, 8),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: NovaColors.borderOnLight))),
          child: Row(
            children: [
              Container(width: 3, height: 34, decoration: BoxDecoration(color: NovaColors.accent, borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 10),
              Icon(Icons.push_pin_rounded, size: 18, color: NovaColors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: NovaTypography.display,
                        fontFamilyFallback: NovaTypography.fallback,
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                        height: 1.3,
                        color: NovaColors.accent,
                      ),
                    ),
                    Text(
                      newest == null ? '' : chatPinLine(context, newest),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: NovaTypography.body,
                        fontFamilyFallback: NovaTypography.fallback,
                        fontWeight: FontWeight.w500,
                        fontSize: 13.5,
                        height: 1.35,
                        color: NovaColors.textBody,
                      ),
                    ),
                  ],
                ),
              ),
              ChatIconButton(
                icon: Icons.format_list_bulleted_rounded,
                label: context.tr('chat.pinsTitle'),
                color: NovaColors.textBody,
                size: 40,
                onTap: onList,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Every pin of the room, newest pinned first; a tap picks one (the room
/// scrolls to it).
class ChatPinsSheet extends StatelessWidget {
  const ChatPinsSheet({super.key, required this.chat, required this.roomId, required this.onPick});

  final ChatStore chat;
  final int roomId;
  final ValueChanged<ChatMessage> onPick;

  @override
  Widget build(BuildContext context) {
    return ChatSheetFrame(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.6),
        child: ListenableBuilder(
          listenable: chat,
          builder: (BuildContext context, _) {
            final List<ChatMessage> pins = chat.pinsOf(roomId);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
                  child: Text(context.tr('chat.pinsTitle'), style: NovaTypography.textTheme.titleLarge),
                ),
                if (pins.isEmpty)
                  // Still loading; nothing once the last pin went.
                  (chat.room(roomId)?.pinnedCount ?? 0) > 0
                      ? const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
                      : const SizedBox(height: 24)
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: pins.length,
                      itemBuilder: (BuildContext context, int i) {
                        final ChatMessage pin = pins[i];
                        final DateTime? at = pin.createdAt;
                        return ListTile(
                          key: ValueKey<String>('pin-${pin.id}'),
                          leading: ChatPersonAvatar(userId: pin.sender.id, role: pin.sender.role, name: pin.sender.name, photoUrl: pin.sender.avatarUrl, size: 38),
                          title: Text(
                            chatNameOf(context, pin.sender.role, pin.sender.name),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: NovaTypography.textTheme.titleSmall,
                          ),
                          subtitle: Text(
                            chatMessageLine(context, pin),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textDirection: chatTextDirection(pin.body ?? ''),
                            style: NovaTypography.textTheme.bodySmall!.copyWith(color: NovaColors.textBody),
                          ),
                          trailing: at == null ? null : Text(chatListTime(context, at), style: NovaTypography.textTheme.bodySmall),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          onTap: () => onPick(pin),
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
