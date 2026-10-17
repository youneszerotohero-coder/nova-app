import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/nova_page_header.dart';
import '../../core/widgets/nova_toast.dart';
import '../../core/widgets/page_scaffold.dart' show NovaSectionCard;
import '../../data/chat_store.dart';
import '../account/dashboard_card.dart' show heroLabel, heroText;
import 'chat_format.dart';
import 'chat_pdf_screen.dart';
import 'chat_widgets.dart';

/// D-143 chat info (BR-C8): the room, its Teacher, its Offers (Teacher and
/// Admin only), the members (searchable; a Student in the announcements
/// sees the count only), the PDFs sent, newest first, and "mute".
class ChatInfoScreen extends StatefulWidget {
  const ChatInfoScreen({super.key, required this.roomId});

  final int roomId;

  @override
  State<ChatInfoScreen> createState() => _ChatInfoScreenState();
}

class _ChatInfoScreenState extends State<ChatInfoScreen> {
  final TextEditingController _search = TextEditingController();
  Timer? _searchDebounce;

  List<ChatPerson> _members = const <ChatPerson>[];
  int? _membersTotal;
  int _membersPage = 1;
  bool _membersMore = false;
  bool _membersLoading = false;
  ApiException? _membersError;
  int _membersRequest = 0;

  List<ChatMessage> _pdfs = const <ChatMessage>[];
  bool _pdfsMore = false;
  bool _pdfsLoading = false;
  bool _pdfsLoaded = false;

  ChatStore get _chat => AppScope.of(context).chat;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_chat.room(widget.roomId)?.canViewMembers ?? false) _loadMembers(reset: true);
      _loadPdfs(reset: true);
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadMembers({bool reset = false}) async {
    if (_membersLoading && !reset) return;
    final int request = ++_membersRequest;
    final int page = reset ? 1 : _membersPage + 1;
    setState(() {
      _membersLoading = true;
      _membersError = null;
    });
    try {
      final ChatMembersPage result = await _chat.members(widget.roomId, search: _search.text, page: page);
      if (!mounted || request != _membersRequest) return;
      setState(() {
        _members = reset ? result.members : <ChatPerson>[..._members, ...result.members];
        _membersPage = page;
        _membersMore = result.hasMore;
        if (_search.text.trim().isEmpty) _membersTotal = result.total;
      });
    } on ApiException catch (error) {
      if (mounted && request == _membersRequest) setState(() => _membersError = error);
    } finally {
      if (mounted && request == _membersRequest) setState(() => _membersLoading = false);
    }
  }

  void _onSearch(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () => _loadMembers(reset: true));
  }

  Future<void> _loadPdfs({bool reset = false}) async {
    if (_pdfsLoading) return;
    setState(() => _pdfsLoading = true);
    try {
      final ChatPdfsPage result = await _chat.pdfs(widget.roomId, beforeId: reset || _pdfs.isEmpty ? null : _pdfs.last.id);
      if (!mounted) return;
      setState(() {
        _pdfs = reset ? result.pdfs : <ChatMessage>[..._pdfs, ...result.pdfs];
        _pdfsMore = result.hasMore;
        _pdfsLoaded = true;
      });
    } on ApiException {
      if (mounted) setState(() => _pdfsLoaded = true);
    } finally {
      if (mounted) setState(() => _pdfsLoading = false);
    }
  }

  Future<void> _toggleMute(bool muted) async {
    try {
      await _chat.setMuted(widget.roomId, muted);
      if (mounted) {
        novaToast(context, context.tr(muted ? 'chat.mutedDone' : 'chat.unmutedDone'), icon: muted ? Icons.notifications_off_rounded : Icons.check_circle_rounded);
      }
    } on ApiException catch (error) {
      if (mounted) novaToast(context, apiErrorText(context, error), icon: Icons.error_outline_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ChatStore chat = AppScope.of(context).chat;
    return ListenableBuilder(
      listenable: chat,
      builder: (BuildContext context, _) {
        final ChatRoom? room = chat.room(widget.roomId);
        if (room == null) return Scaffold(backgroundColor: NovaColors.paper, body: const Center(child: CircularProgressIndicator()));
        final String members = context.trf('chat.members', <String, String>{'n': '${room.membersCount}'});
        final List<Widget> cards = <Widget>[
          _about(context, room),
          if (room.teacher != null) _teacher(context, room.teacher!),
          if (room.offers.isNotEmpty) _offers(context, room),
          _membersCard(context, room),
          _pdfsCard(context, room),
        ];
        return Scaffold(
          backgroundColor: NovaColors.paper,
          body: ListView(
            padding: EdgeInsets.only(bottom: 40 + MediaQuery.paddingOf(context).bottom),
            children: [
              NovaPageHeader(
                title: chatRoomTitle(context, room),
                kicker: context.tr(room.isPublic ? 'chat.kindPublic' : 'chat.kindGroup'),
                lead: members,
                showBack: true,
              ),
              const SizedBox(height: 18),
              for (int i = 0; i < cards.length; i++)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: Entrance(delay: Duration(milliseconds: 40 * i), child: cards[i]),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _about(BuildContext context, ChatRoom room) {
    final String mode = room.isPublic
        ? context.tr('chat.modePublic')
        : context.tr(room.studentsCanSend ? 'chat.modeOpen' : 'chat.modeTeacherOnly');
    return NovaSectionCard(
      icon: Icons.forum_outlined,
      title: context.tr('chat.about'),
      child: Column(
        children: [
          Row(
            children: [
              ChatRoomAvatar(room: room, size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(chatRoomTitle(context, room), style: heroLabel(17)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(room.canSend ? Icons.edit_note_rounded : Icons.lock_outline_rounded, size: 16, color: NovaColors.textMuted),
                        const SizedBox(width: 4),
                        Expanded(child: Text(mode, style: heroText(13.5, color: NovaColors.textMuted, height: 1.35))),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: NovaColors.borderOnLight),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(room.muted ? Icons.notifications_off_rounded : Icons.notifications_active_outlined, color: NovaColors.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr('chat.mute'), style: heroLabel(15)),
                    Text(context.tr('chat.muteHint'), style: heroText(12.5, color: NovaColors.textMuted, height: 1.35)),
                  ],
                ),
              ),
              Switch.adaptive(
                value: room.muted,
                activeTrackColor: NovaColors.accent,
                onChanged: _toggleMute,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _teacher(BuildContext context, ChatTeacher teacher) {
    return NovaSectionCard(
      icon: Icons.school_outlined,
      title: context.tr('chat.teacher'),
      child: Row(
        children: [
          _TeacherAvatar(teacher: teacher),
          const SizedBox(width: 12),
          Expanded(child: Text(teacher.name, style: heroLabel(16))),
          const ChatRoleBadge(role: ChatRole.teacher),
        ],
      ),
    );
  }

  Widget _offers(BuildContext context, ChatRoom room) {
    return NovaSectionCard(
      icon: Icons.auto_awesome_outlined,
      title: context.tr('chat.offers'),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final ChatOffer offer in room.offers)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(color: NovaColors.accentMist, borderRadius: BorderRadius.circular(100)),
              child: Text(offer.title, style: heroLabel(13.5, color: NovaColors.accent)),
            ),
        ],
      ),
    );
  }

  Widget _membersCard(BuildContext context, ChatRoom room) {
    final String count = context.trf('chat.members', <String, String>{'n': '${_membersTotal ?? room.membersCount}'});
    if (!room.canViewMembers) {
      return NovaSectionCard(
        icon: Icons.groups_outlined,
        title: context.tr('chat.membersTitle'),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: NovaColors.accentMist, borderRadius: BorderRadius.circular(14)),
              child: Icon(Icons.groups_rounded, color: NovaColors.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(count, style: heroLabel(16)),
                  Text(context.tr('chat.membersPrivate'), style: heroText(12.5, color: NovaColors.textMuted, height: 1.35)),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return NovaSectionCard(
      icon: Icons.groups_outlined,
      title: context.tr('chat.membersTitle'),
      subtitle: count,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _search,
            onChanged: _onSearch,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: context.tr('chat.searchMembers'),
              prefixIcon: const Icon(Icons.search_rounded),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          if (_membersError != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(apiErrorText(context, _membersError!), style: heroText(13.5, color: NovaColors.heartRed)),
            )
          else if (_members.isEmpty && _membersLoading)
            const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
          else if (_members.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(context.tr('chat.noMembers'), textAlign: TextAlign.center, style: heroText(13.5, color: NovaColors.textMuted)),
            ),
          for (final ChatPerson person in _members)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  ChatPersonAvatar(userId: person.userId, role: person.role, name: person.name, photoUrl: person.avatarUrl, size: 38),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      chatNameOf(context, person.role, person.name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: heroText(15, color: NovaColors.textStrong, weight: FontWeight.w600, height: 1.3),
                    ),
                  ),
                  ChatRoleBadge(role: person.role),
                ],
              ),
            ),
          if (_membersMore)
            TextButton(
              onPressed: _membersLoading ? null : () => _loadMembers(),
              child: Text(context.tr(_membersLoading ? 'notif.loading' : 'notif.showMore'), style: heroLabel(14, color: NovaColors.accent)),
            ),
        ],
      ),
    );
  }

  Widget _pdfsCard(BuildContext context, ChatRoom room) {
    final NovaLang lang = AppScope.of(context).lang;
    return NovaSectionCard(
      icon: Icons.picture_as_pdf_outlined,
      title: context.tr('chat.pdfs'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_pdfsLoaded)
            const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
          else if (_pdfs.isEmpty)
            Text(context.tr('chat.noPdfs'), style: heroText(13.5, color: NovaColors.textMuted)),
          for (final ChatMessage pdf in _pdfs)
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => ChatPdfScreen(roomId: widget.roomId, messageId: pdf.id, title: pdf.attachment?.name ?? 'PDF'),
                )),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: NovaColors.dangerBg, borderRadius: BorderRadius.circular(10)),
                        child: Icon(Icons.picture_as_pdf_rounded, size: 21, color: NovaColors.heartRed),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              pdf.attachment?.name ?? 'PDF',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textDirection: chatTextDirection(pdf.attachment?.name ?? ''),
                              style: heroText(14.5, color: NovaColors.textStrong, weight: FontWeight.w700, height: 1.3),
                            ),
                            Text(
                              <String>[
                                chatFileSize(pdf.attachment?.size ?? 0, lang),
                                if (pdf.createdAt != null) chatDate(pdf.createdAt!, lang),
                                chatNameOf(context, pdf.sender.role, pdf.sender.name),
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: heroText(12.5, color: NovaColors.textMuted, height: 1.35),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: NovaColors.textMuted),
                    ],
                  ),
                ),
              ),
            ),
          if (_pdfsMore)
            TextButton(
              onPressed: _pdfsLoading ? null : () => _loadPdfs(),
              child: Text(context.tr(_pdfsLoading ? 'notif.loading' : 'notif.showMore'), style: heroLabel(14, color: NovaColors.accent)),
            ),
        ],
      ),
    );
  }
}

/// The Teacher's photo, or their monogram.
class _TeacherAvatar extends StatelessWidget {
  const _TeacherAvatar({required this.teacher});

  final ChatTeacher teacher;

  @override
  Widget build(BuildContext context) => ChatPersonAvatar(
        userId: teacher.id + 100000,
        role: ChatRole.teacher,
        name: teacher.name,
        photoUrl: teacher.photoUrl,
        size: 44,
      );
}
