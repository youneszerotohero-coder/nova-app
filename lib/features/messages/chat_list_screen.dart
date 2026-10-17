import 'package:flutter/material.dart';

/// D-143: the list of the signed-in user's group chats (Student or Teacher).
/// Seam created before the chat feature is written: the chat agent replaces
/// this file; the Teacher shell already mounts it.
class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key, this.embedded = false});

  /// True when shown as a shell tab (no back button).
  final bool embedded;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
