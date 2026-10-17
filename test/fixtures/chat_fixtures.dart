import 'dart:async';

import 'package:nova_mobile/data/chat_store.dart';
import 'package:nova_mobile/features/messages/chat_audio.dart';

import 'fake_api.dart';

/// D-143 payloads exactly as `/api/v1/chats…` and the Reverb events send
/// them (docs/D-143 §3.1, §3.5).

const int meId = 77;
const int teacherUserId = 5;

Map<String, Object?> roomJson({
  required int id,
  String kind = 'group',
  String name = 'Maths 3AS',
  Map<String, Object?>? teacher = const <String, Object?>{'id': 9, 'name': 'Karim Benali', 'photo_url': null},
  bool studentsCanSend = true,
  bool? canSend,
  bool? canSendVoice,
  bool canSendPdf = false,
  bool canModerate = false,
  bool canViewMembers = true,
  int membersCount = 134,
  int unread = 0,
  bool muted = false,
  int lastRead = 0,
  int staffLastRead = 0,
  Map<String, Object?>? lastMessage,
  String? lastMessageAt,
  List<Map<String, Object?>> offers = const <Map<String, Object?>>[],
}) =>
    <String, Object?>{
      'id': id,
      'kind': kind,
      'name': name,
      'teacher': kind == 'public' ? null : teacher,
      'students_can_send': studentsCanSend,
      'can_send': canSend ?? (kind == 'group' && studentsCanSend),
      'can_send_voice': canSendVoice ?? (kind == 'group' && studentsCanSend),
      'can_send_pdf': canSendPdf,
      'can_moderate': canModerate,
      'can_view_members': kind == 'public' ? false : canViewMembers,
      'members_count': membersCount,
      'unread_count': unread,
      'muted': muted,
      'last_read_message_id': lastRead,
      'staff_last_read_message_id': staffLastRead,
      'last_message': lastMessage,
      'last_message_at': lastMessageAt ?? lastMessage?['created_at'],
      'channel': 'chat.$id',
      'offers': offers,
    };

Map<String, Object?> lastJson(int id, String preview, {String kind = 'text', String? sender = 'Karim Benali', String role = 'teacher', String createdAt = '2026-10-11T08:00:00+00:00'}) =>
    <String, Object?>{'id': id, 'kind': kind, 'preview': preview, 'sender_name': sender, 'sender_role': role, 'created_at': createdAt};

Map<String, Object?> sender(int id, {String? name, String role = 'student', String? avatar}) =>
    <String, Object?>{'id': id, 'name': role == 'admin' ? null : name, 'role': role, 'avatar_url': avatar};

Map<String, Object?> messageJson({
  required int id,
  int roomId = 3,
  String kind = 'text',
  String? body,
  Map<String, Object?>? from,
  Map<String, Object?>? attachment,
  String? clientUuid,
  String createdAt = '2026-10-11T08:00:00+00:00',
  int? seenCount,
}) =>
    <String, Object?>{
      'id': id,
      'room_id': roomId,
      'kind': kind,
      'body': body ?? (kind == 'text' ? 'Message $id' : null),
      'sender': from ?? sender(teacherUserId, name: 'Karim Benali', role: 'teacher'),
      'attachment': attachment,
      'client_uuid': clientUuid,
      'created_at': createdAt,
      'seen_count': seenCount,
    };

Map<String, Object?> voiceAttachment({int durationMs = 42000, List<int>? waveform}) => <String, Object?>{
      'name': 'voice.m4a',
      'size': 48211,
      'mime': 'audio/mp4',
      'duration_ms': durationMs,
      'waveform': waveform ?? <int>[for (int i = 0; i < 48; i++) 12 + ((i * 37) % 80)],
    };

Map<String, Object?> pdfAttachment({String name = 'Série 4 — Suites numériques.pdf', int size = 1258291}) =>
    <String, Object?>{'name': name, 'size': size, 'mime': 'application/pdf', 'duration_ms': null, 'waveform': null};

/// One `GET /chats/{room}/messages` answer.
FakeResponse messagesPage(List<Map<String, Object?>> messages, {bool hasMore = false}) => FakeResponse(200, <String, Object?>{
      'data': messages,
      'meta': <String, Object?>{
        'has_more': hasMore,
        'oldest_id': messages.isEmpty ? null : messages.first['id'],
        'newest_id': messages.isEmpty ? null : messages.last['id'],
      },
    });

ChatRoom room(Map<String, Object?> json) => ChatRoom.fromJson(Map<String, dynamic>.of(json));

ChatMessage message(Map<String, Object?> json) => ChatMessage.fromJson(<String, dynamic>{
      ...json,
      'sender': Map<String, dynamic>.of(json['sender']! as Map<String, Object?>),
      if (json['attachment'] != null) 'attachment': Map<String, dynamic>.of(json['attachment']! as Map<String, Object?>),
    });

/// Records the sounds asked for.
class RecordingSoundPlayer implements ChatSoundPlayer {
  final List<(ChatSound, double)> played = <(ChatSound, double)>[];

  @override
  Future<void> play(ChatSound sound, double volume) async => played.add((sound, volume));
}

/// A recorder without a microphone: levels come from [emit].
class FakeRecorder implements ChatRecorder {
  FakeRecorder({this.allowed = true});

  final bool allowed;
  final StreamController<double> _levels = StreamController<double>.broadcast();
  bool started = false;
  bool cancelled = false;

  void emit(double level) => _levels.add(level);

  @override
  Future<bool> hasPermission() async => allowed;

  @override
  Future<void> start() async => started = true;

  @override
  Future<String?> stop() async => '/tmp/nova-test-voice.m4a';

  @override
  Future<void> cancel() async => cancelled = true;

  @override
  Stream<double> get levels => _levels.stream;

  @override
  Future<void> dispose() async {}
}

/// The screenshot tour's chats (Arabic Student view, on the golden day
/// 2026-10-11 at 10:00 Algeria time).
ChatStore tourChatStore() {
  final Map<String, Object?> karim = sender(teacherUserId, name: 'كريم بن علي', role: 'teacher', avatar: 'assets/images/people/teacher_karim.jpg');
  final Map<String, Object?> lina = sender(41, name: 'لينة حدّاد');
  final Map<String, Object?> amine = sender(42, name: 'Amine Cherif');
  final Map<String, Object?> me = sender(meId, name: 'Ines Benali');
  final Map<String, Object?> nova = sender(1, role: 'admin');
  return ChatStore.seeded(
    me: meId,
    rooms: <ChatRoom>[
      room(roomJson(
        id: 1,
        kind: 'public',
        name: 'Annonces',
        unread: 1,
        membersCount: 2384,
        lastMessage: lastJson(90, 'الحصة المباشرة تاع الرياضيات تبدا اليوم على 20:00', role: 'admin', sender: null, createdAt: '2026-10-11T07:40:00+00:00'),
      )),
      room(roomJson(
        id: 3,
        name: 'رياضيات 3 ثانوي — Bac 2026',
        teacher: const <String, Object?>{'id': 9, 'name': 'كريم بن علي', 'photo_url': 'assets/images/people/teacher_karim.jpg'},
        unread: 4,
        membersCount: 134,
        lastRead: 64,
        staffLastRead: 66,
        lastMessage: lastJson(70, 'شكرا أستاذ، فهمت دروك', sender: 'لينة حدّاد', role: 'student', createdAt: '2026-10-11T08:52:00+00:00'),
      )),
      room(roomJson(
        id: 4,
        name: 'Physique — BAC 2026',
        teacher: const <String, Object?>{'id': 10, 'name': 'Nadia Saidi', 'photo_url': 'assets/images/people/teacher_nadia.jpg'},
        muted: true,
        unread: 2,
        membersCount: 88,
        lastMessage: lastJson(51, '', kind: 'voice', sender: 'Nadia Saidi', createdAt: '2026-10-10T19:10:00+00:00'),
      )),
      room(roomJson(
        id: 5,
        name: 'علوم الطبيعة والحياة',
        teacher: const <String, Object?>{'id': 11, 'name': 'ياسين مراد', 'photo_url': 'assets/images/people/teacher_yacine.jpg'},
        studentsCanSend: false,
        membersCount: 61,
        lastMessage: lastJson(33, 'ملخص الوحدة 2.pdf', kind: 'pdf', sender: 'ياسين مراد', createdAt: '2026-10-07T16:00:00+00:00'),
      )),
    ],
    messages: <int, List<ChatMessage>>{
      3: <ChatMessage>[
        message(messageJson(id: 58, from: karim, body: 'مساء الخير! غدوة نكملو المتتاليات، حضّرو التمرين 12 ص 45.', createdAt: '2026-10-10T18:30:00+00:00')),
        message(messageJson(id: 59, from: amine, body: 'Monsieur, l’exercice 12 c’est la partie b aussi ?', createdAt: '2026-10-10T18:41:00+00:00')),
        message(messageJson(id: 60, from: karim, body: 'Oui, a et b. 👍', createdAt: '2026-10-10T18:44:00+00:00')),
        message(messageJson(id: 61, from: nova, body: 'تذكير: الحصة المباشرة تاع الرياضيات اليوم على 20:00 🎥', createdAt: '2026-10-11T07:05:00+00:00')),
        message(messageJson(id: 62, from: karim, kind: 'voice', attachment: voiceAttachment(durationMs: 47000), createdAt: '2026-10-11T07:58:00+00:00')),
        message(messageJson(
          id: 63,
          from: karim,
          kind: 'pdf',
          body: 'سلسلة التمارين تاع اليوم، الحل نهار الخميس.',
          attachment: pdfAttachment(name: 'سلسلة 4 — المتتاليات العددية.pdf', size: 1258291),
          createdAt: '2026-10-11T08:00:00+00:00',
        )),
        message(messageJson(id: 64, from: me, body: 'أستاذ، التمرين 3 السؤال ب ما فهمتوش 🙏', createdAt: '2026-10-11T08:20:00+00:00')),
        message(messageJson(id: 65, from: me, body: 'كيفاش نبيّنو بلي المتتالية متزايدة؟', createdAt: '2026-10-11T08:21:00+00:00')),
        message(messageJson(id: 66, from: karim, body: 'أحسب u(n+1) − u(n) وبيّن بلي موجب 😉', createdAt: '2026-10-11T08:30:00+00:00')),
        message(messageJson(id: 67, from: lina, body: 'حتى أنا كان عندي نفس المشكل', createdAt: '2026-10-11T08:40:00+00:00')),
        message(messageJson(id: 68, from: lina, kind: 'voice', attachment: voiceAttachment(durationMs: 9000, waveform: <int>[for (int i = 0; i < 48; i++) 20 + ((i * 53) % 70)]), createdAt: '2026-10-11T08:41:00+00:00')),
        message(messageJson(id: 69, from: me, body: 'Merci monsieur, c’est clair maintenant ✨', createdAt: '2026-10-11T08:50:00+00:00')),
        message(messageJson(id: 70, from: lina, body: 'شكرا أستاذ، فهمت دروك', createdAt: '2026-10-11T08:52:00+00:00')),
      ],
    },
    members: <int, List<ChatPerson>>{
      3: <ChatPerson>[
        ChatPerson.fromJson(<String, dynamic>{'user_id': teacherUserId, 'name': 'كريم بن علي', 'role': 'teacher', 'avatar_url': 'assets/images/people/teacher_karim.jpg'}),
        ChatPerson.fromJson(<String, dynamic>{'user_id': 42, 'name': 'Amine Cherif', 'role': 'student'}),
        ChatPerson.fromJson(<String, dynamic>{'user_id': meId, 'name': 'Ines Benali', 'role': 'student', 'avatar_url': 'assets/images/people/student_ines.jpg'}),
        ChatPerson.fromJson(<String, dynamic>{'user_id': 43, 'name': 'سارة بوزيد', 'role': 'student'}),
        ChatPerson.fromJson(<String, dynamic>{'user_id': 41, 'name': 'لينة حدّاد', 'role': 'student'}),
        ChatPerson.fromJson(<String, dynamic>{'user_id': 44, 'name': 'Yanis Ait Ali', 'role': 'student'}),
      ],
    },
    pdfs: <int, List<ChatMessage>>{
      3: <ChatMessage>[
        message(messageJson(id: 63, from: karim, kind: 'pdf', attachment: pdfAttachment(name: 'سلسلة 4 — المتتاليات العددية.pdf', size: 1258291), createdAt: '2026-10-11T08:00:00+00:00')),
        message(messageJson(id: 41, from: karim, kind: 'pdf', attachment: pdfAttachment(name: 'Bac blanc 2025 — corrigé.pdf', size: 845000), createdAt: '2026-10-03T15:00:00+00:00')),
      ],
    },
  );
}
