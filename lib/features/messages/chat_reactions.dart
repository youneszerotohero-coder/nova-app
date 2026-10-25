import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_typography.dart';
import '../../data/chat_store.dart';
import 'chat_format.dart';
import 'chat_widgets.dart';

/// D-156 BR-X3 emoji reactions: the quick bar of the message menu, the
/// chips under a bubble and the "who reacted" list.

/// The six emojis on top of the message menu; the viewer's own is ringed.
class ChatQuickReactions extends StatelessWidget {
  const ChatQuickReactions({super.key, required this.emojis, required this.selected, required this.onPick});

  final List<String> emojis;
  final String? selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 2, 6, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final String emoji in emojis)
            Semantics(
              button: true,
              selected: emoji == selected,
              label: context.trf('chat.reactWith', <String, String>{'e': emoji}),
              child: InkResponse(
                key: ValueKey<String>('quick-$emoji'),
                onTap: () => onPick(emoji),
                radius: 26,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: emoji == selected ? NovaColors.accentMist : NovaColors.paperRaised,
                    border: Border.all(color: emoji == selected ? NovaColors.accent : NovaColors.borderOnLight, width: emoji == selected ? 1.6 : 1),
                  ),
                  child: ExcludeSemantics(child: Text(emoji, style: const TextStyle(fontSize: 24, height: 1.1))),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The counts under a bubble (emoji + count, the viewer's own
/// highlighted). A tap toggles that emoji; a long press opens who reacted.
class ChatReactionChips extends StatelessWidget {
  const ChatReactionChips({super.key, required this.message, this.onToggle, this.onShowReactors});

  final ChatMessage message;
  final ValueChanged<String>? onToggle;
  final VoidCallback? onShowReactors;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final ChatReaction reaction in message.reactions)
          _Chip(
            key: ValueKey<String>('reaction-${message.id}-${reaction.emoji}'),
            reaction: reaction,
            mine: reaction.emoji == message.myReaction,
            onTap: onToggle == null ? null : () => onToggle!(reaction.emoji),
            onLongPress: onShowReactors,
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.reaction, required this.mine, this.onTap, this.onLongPress});

  final ChatReaction reaction;
  final bool mine;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      selected: mine,
      label: '${reaction.emoji} ${reaction.count}',
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: mine ? NovaColors.accentMist : NovaColors.paperCard,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: mine ? NovaColors.accent : NovaColors.borderOnLight, width: mine ? 1.4 : 1),
          ),
          child: ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(reaction.emoji, style: const TextStyle(fontSize: 14, height: 1.2)),
                const SizedBox(width: 4),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  transitionBuilder: (Widget child, Animation<double> a) => ScaleTransition(scale: a, child: child),
                  child: Text(
                    '${reaction.count}',
                    key: ValueKey<int>(reaction.count),
                    style: TextStyle(
                      fontFamily: NovaTypography.body,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      height: 1.2,
                      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                      color: mine ? NovaColors.accent : NovaColors.textBody,
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

/// "Who reacted": the counts by emoji, then the names with their emoji,
/// pages of 50 (newest first). Only for viewers who may see the members.
class ChatReactorsSheet extends StatefulWidget {
  const ChatReactorsSheet({super.key, required this.roomId, required this.message});

  final int roomId;
  final ChatMessage message;

  @override
  State<ChatReactorsSheet> createState() => _ChatReactorsSheetState();
}

class _ChatReactorsSheetState extends State<ChatReactorsSheet> {
  final List<ChatPerson> _people = <ChatPerson>[];
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
      final ChatMembersPage page = await _chat!.reactors(widget.roomId, widget.message.id, page: _page + 1);
      if (!mounted) return;
      setState(() {
        _people.addAll(page.members.where((ChatPerson p) => !_people.any((ChatPerson q) => q.userId == p.userId)));
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
    return ChatSheetFrame(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Text(context.tr('chat.reactionsTitle'), style: NovaTypography.textTheme.titleLarge),
            ),
            // The live counts, by emoji.
            ListenableBuilder(
              listenable: _chat!,
              builder: (BuildContext context, _) {
                final ChatMessage message =
                    _chat!.messagesOf(widget.roomId).where((ChatMessage m) => m.id == widget.message.id).firstOrNull ?? widget.message;
                if (message.reactions.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Align(alignment: AlignmentDirectional.centerStart, child: ChatReactionChips(message: message)),
                );
              },
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(apiErrorText(context, _error!), style: NovaTypography.textTheme.bodySmall),
              )
            else if (_page == 0 && _loading)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            else if (_people.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(context.tr('chat.reactionsNobody'), textAlign: TextAlign.center, style: NovaTypography.textTheme.bodySmall),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _people.length + (_hasMore ? 1 : 0),
                  itemBuilder: (BuildContext context, int i) {
                    if (i == _people.length) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Center(
                          child: _loading
                              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.4))
                              : TextButton(
                                  onPressed: _load,
                                  child: Text(context.trf('chat.seenMore', <String, String>{'shown': '${_people.length}', 'total': '$_total'})),
                                ),
                        ),
                      );
                    }
                    final ChatPerson person = _people[i];
                    return ListTile(
                      leading: ChatPersonAvatar(userId: person.userId, role: person.role, name: person.name, photoUrl: person.avatarUrl, size: 38),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(chatNameOf(context, person.role, person.name), maxLines: 1, overflow: TextOverflow.ellipsis, style: NovaTypography.textTheme.titleSmall),
                          ),
                          const SizedBox(width: 6),
                          ChatRoleBadge(role: person.role),
                        ],
                      ),
                      trailing: Text(person.emoji ?? '', style: const TextStyle(fontSize: 22, height: 1.1)),
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
