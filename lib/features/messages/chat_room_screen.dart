import 'package:flutter/material.dart';

/// D-143: one group chat (messages, composer, info). Seam created before the
/// chat feature is written: the chat agent replaces this file; push taps and
/// the Teacher shell already open it.
class ChatRoomScreen extends StatelessWidget {
  const ChatRoomScreen({super.key, required this.roomId});

  final int roomId;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
