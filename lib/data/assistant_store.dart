import 'package:flutter/foundation.dart';

import '../core/api/api_exception.dart';
import '../core/api/nova_api.dart';
import 'json.dart';

/// D-150: the help assistant in the app, the website's `assistant-chat.tsx`
/// on the same endpoints — a signed-in Student's chat (`/me/assistant`) or a
/// visitor's (`/assistant/visitor`, D-141, kept by the session cookie). Every
/// card and link comes from Laravel; nothing here decides access.
class AssistantStore extends ChangeNotifier {
  AssistantStore(this._api, {required this.signedIn});

  final NovaApi _api;

  /// A signed-in Student; otherwise the visitor chat.
  final bool signedIn;

  static const int maxTextLength = 2000;

  String get _conversation => signedIn ? '/me/assistant' : '/assistant/visitor';

  List<AssistantMessage> _messages = <AssistantMessage>[];
  List<AssistantMessage> get messages => _messages;

  bool _loaded = false;
  bool get loaded => _loaded;

  bool _sending = false;
  bool get sending => _sending;

  /// The last failure, shown above the composer until the next action.
  ApiException? _error;
  ApiException? get error => _error;

  /// Whether the failure was loading the conversation (vs sending).
  bool _loadFailed = false;
  bool get loadFailed => _loadFailed;

  int _pending = 0;
  bool _disposed = false;

  Future<void> load() async {
    _error = null;
    _loadFailed = false;
    _notify();
    try {
      final Json body = await _api.get(_conversation);
      _messages = _read(body);
      _loaded = true;
    } on ApiException catch (error) {
      _error = error;
      _loadFailed = true;
    }
    _notify();
  }

  /// Sends [content]; on failure the text is returned to put back in the
  /// composer, otherwise null.
  Future<String?> send(String content) async {
    final String text = content.trim();
    if (text.isEmpty || _sending) return null;
    _error = null;
    _sending = true;
    final AssistantMessage optimistic = AssistantMessage(
      id: 'pending-${++_pending}',
      student: true,
      pending: true,
      blocks: <AssistantBlock>[AssistantBlock(<String, dynamic>{'type': 'text', 'text': text})],
    );
    _messages = <AssistantMessage>[..._messages, optimistic];
    _notify();
    try {
      final Json body = await _api.post('$_conversation/messages', <String, Object>{'text': text});
      _messages = <AssistantMessage>[..._messages.where((AssistantMessage m) => m.id != optimistic.id), ..._read(body)];
      return null;
    } on ApiException catch (error) {
      _messages = _messages.where((AssistantMessage m) => m.id != optimistic.id).toList();
      _error = error;
      return text;
    } finally {
      _sending = false;
      _notify();
    }
  }

  /// "New conversation": the server forgets this chat.
  Future<void> reset() async {
    if (_sending) return;
    try {
      await _api.delete(_conversation);
      _messages = <AssistantMessage>[];
      _error = null;
      _loaded = true;
      _loadFailed = false;
    } on ApiException catch (error) {
      _error = error;
    }
    _notify();
  }

  static List<AssistantMessage> _read(Json body) =>
      (body.obj('data') ?? <String, dynamic>{}).list('messages').map(AssistantMessage.fromJson).toList();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

@immutable
class AssistantMessage {
  const AssistantMessage({required this.id, required this.student, required this.blocks, this.pending = false});

  factory AssistantMessage.fromJson(Json json) => AssistantMessage(
        id: json.str('id'),
        student: json.str('role') == 'student',
        blocks: json.list('blocks').map(AssistantBlock.new).where((AssistantBlock b) => b.known).toList(),
      );

  final String id;

  /// Written by the Student (end side), otherwise by the assistant.
  final bool student;
  final List<AssistantBlock> blocks;

  /// Shown at once, not yet answered by the server.
  final bool pending;
}

/// One block of a message, as the website reads it: `text`, a `product`
/// card (Offer or Unit), a `link` to a page, an `order` with its state.
/// Other kinds (the sandbox's receipts and passwords) are not shown here.
@immutable
class AssistantBlock {
  const AssistantBlock(this.json);

  final Json json;

  String get type => json.str('type');
  bool get known => const <String>{'text', 'product', 'link', 'order'}.contains(type);

  String get text => json.str('text');

  // product
  bool get isOffer => json.str('kind') == 'offer';
  String get title => json.str('title');
  String get subtitle => json.str('subtitle');
  String? get coverUrl => json.strOrNull('cover_url');
  int get price => dinars(json['price']);
  bool get owned => json.flag('owned');

  /// The website path the block leads to (`/bundles/…`, `/learn/…`,
  /// `/account/orders`…), opened by `openAssistantHref`.
  String get href => json.str('href');

  // link
  String get target => json.str('target');

  // order
  String get orderNumber => json.str('order_number');
  int get amount => dinars(json['amount']);
  bool get paid => json.str('state') == 'paid';
}
