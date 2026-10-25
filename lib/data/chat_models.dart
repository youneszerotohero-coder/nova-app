import 'json.dart';

/// D-143 group chats: the `/chats` payloads (docs/D-143 §3.1), with the
/// D-156 photos, pins and reactions (docs/D-156 §3).

enum ChatRoomKind { group, public }

enum ChatMessageKind { text, voice, pdf, image }

/// D-156 BR-X3: the fixed reactions in their order (`config('chat.reactions')`),
/// for a room payload that does not list them.
const List<String> chatDefaultReactions = <String>['👍', '❤️', '😂', '😮', '😢', '🙏'];

/// Who wrote a message: the Admin is shown as "NOVA Administration".
enum ChatRole { student, teacher, admin }

ChatRole chatRoleOf(String value) => switch (value) {
      'teacher' => ChatRole.teacher,
      'admin' => ChatRole.admin,
      _ => ChatRole.student,
    };

ChatMessageKind chatKindOf(String value) => switch (value) {
      'voice' => ChatMessageKind.voice,
      'pdf' => ChatMessageKind.pdf,
      'image' => ChatMessageKind.image,
      _ => ChatMessageKind.text,
    };

/// A message's local delivery state; server messages are [sent].
enum ChatSendState { sent, pending, failed }

class ChatTeacher {
  const ChatTeacher({required this.id, required this.name, this.photoUrl});

  factory ChatTeacher.fromJson(Json json) => ChatTeacher(
        id: json.integer('id'),
        name: json.str('name'),
        photoUrl: json.strOrNull('photo_url'),
      );

  final int id;
  final String name;
  final String? photoUrl;
}

class ChatOffer {
  const ChatOffer({required this.id, required this.title});

  factory ChatOffer.fromJson(Json json) => ChatOffer(id: json.integer('id'), title: json.str('title'));

  final int id;
  final String title;
}

/// `ChatRoom.last_message`: what the list previews.
class ChatLastMessage {
  const ChatLastMessage({
    required this.id,
    required this.kind,
    required this.preview,
    required this.senderRole,
    this.senderName,
    this.createdAt,
  });

  factory ChatLastMessage.fromJson(Json json) => ChatLastMessage(
        id: json.integer('id'),
        kind: chatKindOf(json.str('kind')),
        preview: json.str('preview'),
        senderName: json.strOrNull('sender_name'),
        senderRole: chatRoleOf(json.str('sender_role')),
        createdAt: json.date('created_at'),
      );

  /// The preview of a message received in realtime.
  factory ChatLastMessage.of(ChatMessage message) => ChatLastMessage(
        id: message.id,
        kind: message.kind,
        // An image without a caption previews as '' (shown "Photo").
        preview: message.kind == ChatMessageKind.pdf
            ? (message.body?.isNotEmpty ?? false ? message.body! : message.attachment?.name ?? '')
            : message.body ?? '',
        senderName: message.sender.name,
        senderRole: message.sender.role,
        createdAt: message.createdAt,
      );

  final int id;
  final ChatMessageKind kind;
  final String preview;

  /// Null for the Admin.
  final String? senderName;
  final ChatRole senderRole;
  final DateTime? createdAt;
}

class ChatRoom {
  const ChatRoom({
    required this.id,
    required this.kind,
    required this.name,
    this.teacher,
    this.studentsCanSend = false,
    this.canSend = false,
    this.canSendVoice = false,
    this.canSendPdf = false,
    this.canSendImage = false,
    this.canPin = false,
    this.canReact = false,
    this.pinnedCount = 0,
    this.reactionEmojis = chatDefaultReactions,
    this.canModerate = false,
    this.canViewMembers = false,
    this.membersCount = 0,
    this.unreadCount = 0,
    this.muted = false,
    this.lastReadMessageId = 0,
    this.staffLastReadMessageId = 0,
    this.lastMessage,
    this.lastMessageAt,
    this._channel,
    this.offers = const <ChatOffer>[],
  });

  factory ChatRoom.fromJson(Json json) {
    final Json? last = json.obj('last_message');
    final Json? teacher = json.obj('teacher');
    return ChatRoom(
      id: json.integer('id'),
      kind: json.str('kind') == 'public' ? ChatRoomKind.public : ChatRoomKind.group,
      name: json.str('name'),
      teacher: teacher == null ? null : ChatTeacher.fromJson(teacher),
      studentsCanSend: json.flag('students_can_send'),
      canSend: json.flag('can_send'),
      canSendVoice: json.flag('can_send_voice'),
      canSendPdf: json.flag('can_send_pdf'),
      canSendImage: json.flag('can_send_image'),
      canPin: json.flag('can_pin'),
      canReact: json.flag('can_react'),
      pinnedCount: json.integer('pinned_count'),
      reactionEmojis: json['reaction_emojis'] is List
          ? <String>[
              for (final Object? emoji in json['reaction_emojis'] as List)
                if (emoji is String && emoji.isNotEmpty) emoji,
            ]
          : chatDefaultReactions,
      canModerate: json.flag('can_moderate'),
      canViewMembers: json.flag('can_view_members'),
      membersCount: json.integer('members_count'),
      unreadCount: json.integer('unread_count'),
      muted: json.flag('muted'),
      lastReadMessageId: json.integer('last_read_message_id'),
      staffLastReadMessageId: json.integer('staff_last_read_message_id'),
      lastMessage: last == null ? null : ChatLastMessage.fromJson(last),
      lastMessageAt: json.date('last_message_at') ?? last?.date('created_at'),
      channel: json.strOrNull('channel'),
      offers: json.list('offers').map(ChatOffer.fromJson).toList(),
    );
  }

  final int id;
  final ChatRoomKind kind;

  /// The stored name; the public room's title is localized by the app.
  final String name;
  final ChatTeacher? teacher;
  final bool studentsCanSend;
  final bool canSend;
  final bool canSendVoice;
  final bool canSendPdf;

  /// D-156 BR-X1: photos, like PDFs (the Admin, the room's Teacher).
  final bool canSendImage;

  /// D-156 BR-X2: pins and unpins any message (the Admin, the room's Teacher).
  final bool canPin;

  /// D-156 BR-X3: every viewer reacts, Students included.
  final bool canReact;
  final int pinnedCount;

  /// The quick bar's emojis, in their fixed order.
  final List<String> reactionEmojis;

  /// The Teacher of this room or the Admin: deletes any message, sees
  /// every "seen by" list, joins the staff channel.
  final bool canModerate;
  final bool canViewMembers;
  final int membersCount;
  final int unreadCount;
  final bool muted;
  final int lastReadMessageId;

  /// The furthest message the Teacher or the Admin read (✓✓).
  final int staffLastReadMessageId;
  final ChatLastMessage? lastMessage;
  final DateTime? lastMessageAt;
  final String? _channel;
  final List<ChatOffer> offers;

  bool get isPublic => kind == ChatRoomKind.public;

  /// The Reverb channel without its `private-` prefix (`chat.3`).
  String get channel => _channel ?? 'chat.$id';

  ChatRoom copyWith({
    int? unreadCount,
    bool? muted,
    int? lastReadMessageId,
    int? staffLastReadMessageId,
    ChatLastMessage? lastMessage,
    DateTime? lastMessageAt,
    int? pinnedCount,
  }) =>
      ChatRoom(
        id: id,
        kind: kind,
        name: name,
        teacher: teacher,
        studentsCanSend: studentsCanSend,
        canSend: canSend,
        canSendVoice: canSendVoice,
        canSendPdf: canSendPdf,
        canSendImage: canSendImage,
        canPin: canPin,
        canReact: canReact,
        pinnedCount: pinnedCount ?? this.pinnedCount,
        reactionEmojis: reactionEmojis,
        canModerate: canModerate,
        canViewMembers: canViewMembers,
        membersCount: membersCount,
        unreadCount: unreadCount ?? this.unreadCount,
        muted: muted ?? this.muted,
        lastReadMessageId: lastReadMessageId ?? this.lastReadMessageId,
        staffLastReadMessageId: staffLastReadMessageId ?? this.staffLastReadMessageId,
        lastMessage: lastMessage ?? this.lastMessage,
        lastMessageAt: lastMessageAt ?? this.lastMessageAt,
        channel: _channel,
        offers: offers,
      );
}

class ChatSender {
  const ChatSender({required this.id, required this.role, this.name, this.avatarUrl});

  factory ChatSender.fromJson(Json json) => ChatSender(
        id: json.integer('id'),
        name: json.strOrNull('name'),
        role: chatRoleOf(json.str('role')),
        avatarUrl: json.strOrNull('avatar_url'),
      );

  /// The user id.
  final int id;

  /// Null for the Admin ("NOVA Administration").
  final String? name;
  final ChatRole role;
  final String? avatarUrl;
}

class ChatAttachment {
  const ChatAttachment({
    required this.name,
    this.size = 0,
    this.mime = '',
    this.durationMs = 0,
    this.waveform = const <int>[],
    this.width = 0,
    this.height = 0,
  });

  factory ChatAttachment.fromJson(Json json) => ChatAttachment(
        name: json.str('name'),
        size: json.integer('size'),
        mime: json.str('mime'),
        durationMs: json.integer('duration_ms'),
        width: json.integer('width'),
        height: json.integer('height'),
        waveform: <int>[
          for (final Object? v in (json['waveform'] is List ? json['waveform'] as List : const <Object?>[]))
            if (v is num) v.round().clamp(0, 100),
        ],
      );

  final String name;
  final int size;
  final String mime;
  final int durationMs;

  /// ≤ 48 peaks 0..100.
  final List<int> waveform;

  /// D-156: an image's `full` size in pixels (0 when unknown), so its
  /// bubble takes its final size before the picture loads.
  final int width;
  final int height;

  /// Width / height, or null when unknown.
  double? get aspectRatio => width > 0 && height > 0 ? width / height : null;
}

/// D-156 BR-X3: one emoji's count on a message (counts > 0 only).
class ChatReaction {
  const ChatReaction({required this.emoji, required this.count});

  factory ChatReaction.fromJson(Json json) => ChatReaction(emoji: json.str('emoji'), count: json.integer('count'));

  final String emoji;
  final int count;

  /// The `reactions` list of a payload, without empty entries.
  static List<ChatReaction> listOf(Json json) => <ChatReaction>[
        for (final Json reaction in json.list('reactions'))
          if (reaction.str('emoji').isNotEmpty && reaction.integer('count') > 0) ChatReaction.fromJson(reaction),
      ];
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.roomId,
    required this.kind,
    required this.sender,
    this.body,
    this.attachment,
    this.clientUuid,
    this.createdAt,
    this.seenCount,
    this.pinnedAt,
    this.reactions = const <ChatReaction>[],
    this.myReaction,
    this.state = ChatSendState.sent,
    this.progress,
    this.localPath,
    this.error,
  });

  factory ChatMessage.fromJson(Json json) {
    final Json? attachment = json.obj('attachment');
    final Object? seen = json['seen_count'];
    return ChatMessage(
      id: json.integer('id'),
      roomId: json.integer('room_id'),
      kind: chatKindOf(json.str('kind')),
      body: json.strOrNull('body'),
      sender: ChatSender.fromJson(json.obj('sender') ?? <String, dynamic>{}),
      attachment: attachment == null ? null : ChatAttachment.fromJson(attachment),
      clientUuid: json.strOrNull('client_uuid'),
      createdAt: json.date('created_at'),
      seenCount: seen is num ? seen.round() : null,
      pinnedAt: json.date('pinned_at'),
      reactions: ChatReaction.listOf(json),
      myReaction: json.strOrNull('my_reaction'),
    );
  }

  /// The server id; 0 while the message is pending or failed.
  final int id;
  final int roomId;
  final ChatMessageKind kind;
  final String? body;
  final ChatSender sender;
  final ChatAttachment? attachment;
  final String? clientUuid;
  final DateTime? createdAt;

  /// Members who read it ("Seen by N"); only in REST answers to its
  /// sender, the Teacher and the Admin.
  final int? seenCount;

  /// D-156: when it was pinned; null while it is not.
  final DateTime? pinnedAt;

  /// D-156: the counts per emoji, in the fixed order.
  final List<ChatReaction> reactions;

  /// The viewer's own reaction (always null in broadcasts).
  final String? myReaction;
  final ChatSendState state;

  /// Upload progress 0..1 of a pending voice note or PDF.
  final double? progress;

  /// The recorded or picked file of an unsent voice note or PDF.
  final String? localPath;

  /// Why the last send failed (an `ApiException` code).
  final String? error;

  bool get isConfirmed => state == ChatSendState.sent && id > 0;

  bool get isPinned => pinnedAt != null;

  ChatMessage copyWith({
    int? seenCount,
    ChatSendState? state,
    double? progress,
    String? error,
    DateTime? createdAt,
  }) =>
      ChatMessage(
        id: id,
        roomId: roomId,
        kind: kind,
        body: body,
        sender: sender,
        attachment: attachment,
        clientUuid: clientUuid,
        createdAt: createdAt ?? this.createdAt,
        seenCount: seenCount ?? this.seenCount,
        pinnedAt: pinnedAt,
        reactions: reactions,
        myReaction: myReaction,
        state: state ?? this.state,
        progress: progress,
        localPath: localPath,
        error: error,
      );

  /// The same message with these reactions and the viewer's own (null:
  /// none).
  ChatMessage withReactions(List<ChatReaction> reactions, String? myReaction) =>
      _with(reactions: reactions, myReaction: myReaction, pinnedAt: pinnedAt);

  /// The same message pinned at [pinnedAt], or unpinned (null).
  ChatMessage withPin(DateTime? pinnedAt) => _with(reactions: reactions, myReaction: myReaction, pinnedAt: pinnedAt);

  ChatMessage _with({required List<ChatReaction> reactions, required String? myReaction, required DateTime? pinnedAt}) => ChatMessage(
        id: id,
        roomId: roomId,
        kind: kind,
        body: body,
        sender: sender,
        attachment: attachment,
        clientUuid: clientUuid,
        createdAt: createdAt,
        seenCount: seenCount,
        pinnedAt: pinnedAt,
        reactions: reactions,
        myReaction: myReaction,
        state: state,
        progress: progress,
        localPath: localPath,
        error: error,
      );
}

/// D-156: the answer of `PUT|DELETE …/reaction`.
class ChatReactions {
  const ChatReactions({required this.messageId, required this.reactions, this.myReaction});

  factory ChatReactions.fromJson(Json json) => ChatReactions(
        messageId: json.integer('message_id'),
        reactions: ChatReaction.listOf(json),
        myReaction: json.strOrNull('my_reaction'),
      );

  final int messageId;
  final List<ChatReaction> reactions;
  final String? myReaction;
}

/// A row of the members list or of a message's "seen by" list.
class ChatPerson {
  const ChatPerson({required this.userId, required this.role, this.name, this.avatarUrl, this.readAt, this.emoji, this.reactedAt});

  factory ChatPerson.fromJson(Json json) => ChatPerson(
        userId: json.integer('user_id'),
        name: json.strOrNull('name'),
        role: chatRoleOf(json.str('role')),
        avatarUrl: json.strOrNull('avatar_url'),
        readAt: json.date('read_at'),
        emoji: json.strOrNull('emoji'),
        reactedAt: json.date('reacted_at'),
      );

  final int userId;
  final String? name;
  final ChatRole role;
  final String? avatarUrl;
  final DateTime? readAt;

  /// D-156 "who reacted": this person's emoji, and when.
  final String? emoji;
  final DateTime? reactedAt;
}

/// One page of `GET /chats/{room}/members`.
class ChatMembersPage {
  const ChatMembersPage({required this.members, required this.total, required this.hasMore});

  final List<ChatPerson> members;
  final int total;
  final bool hasMore;
}

/// One page of `GET /chats/{room}/pdfs` (newest first).
class ChatPdfsPage {
  const ChatPdfsPage({required this.pdfs, required this.hasMore});

  final List<ChatMessage> pdfs;
  final bool hasMore;
}

/// The signed, 5-minute URL of a message's file.
class ChatFileLink {
  const ChatFileLink({required this.url, required this.expiresAt, this.mime = '', this.name = ''});

  factory ChatFileLink.fromJson(Json json) => ChatFileLink(
        url: json.str('url'),
        expiresAt: json.date('expires_at') ?? DateTime.now().add(const Duration(minutes: 5)),
        mime: json.str('mime'),
        name: json.str('name'),
      );

  final String url;
  final DateTime expiresAt;
  final String mime;
  final String name;
}

/// A message from someone else delivered in realtime: the app plays the
/// receive sound and, for another room, shows the in-app notice.
class ChatArrival {
  const ChatArrival({required this.room, required this.message, required this.inOpenRoom});

  final ChatRoom room;
  final ChatMessage message;

  /// The room is on screen: a soft sound only.
  final bool inOpenRoom;
}
