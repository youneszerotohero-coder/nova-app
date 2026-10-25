import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/i18n/nova_strings.dart';
import '../../core/theme/nova_typography.dart';
import '../../data/chat_store.dart';
import 'chat_format.dart';

/// D-156 chat photos: their pictures and the full-screen viewer.

/// A chat photo's preview or full copy: the bytes come through the
/// message's signed link and stay in memory (Flutter's image cache), like
/// chat PDFs. Keyed by message and variant, not by the 5-minute URL, so a
/// renewed link never downloads a picture again.
@immutable
class ChatImageProvider extends ImageProvider<ChatImageProvider> {
  const ChatImageProvider({required this.chat, required this.roomId, required this.messageId, this.preview = false});

  final ChatStore chat;
  final int roomId;
  final int messageId;
  final bool preview;

  @override
  Future<ChatImageProvider> obtainKey(ImageConfiguration configuration) => SynchronousFuture<ChatImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(ChatImageProvider key, ImageDecoderCallback decode) => MultiFrameImageStreamCompleter(
        codec: _load(key, decode),
        scale: 1,
        debugLabel: 'chat-image-${key.messageId}${key.preview ? '-preview' : ''}',
      );

  static Future<ui.Codec> _load(ChatImageProvider key, ImageDecoderCallback decode) async {
    final List<int> bytes = await key.chat.imageBytes(key.roomId, key.messageId, preview: key.preview);
    final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(bytes is Uint8List ? bytes : Uint8List.fromList(bytes));
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) =>
      other is ChatImageProvider && other.roomId == roomId && other.messageId == messageId && other.preview == preview;

  @override
  int get hashCode => Object.hash(roomId, messageId, preview);
}

/// The Hero between a photo's bubble and its viewer.
String chatImageHeroTag(ChatMessage message) => 'chat-image-${message.roomId}-${message.id}';

/// The bubble's picture box: the photo's own aspect ratio, kept between a
/// tall portrait (1:2) and a wide panorama (2.4:1), 4:3 when unknown.
Size chatImageBox(ChatAttachment? attachment, double maxWidth) {
  final double width = maxWidth.clamp(120.0, 260.0);
  final double ratio = (attachment?.aspectRatio ?? 4 / 3).clamp(0.5, 2.4);
  return Size(width, width / ratio);
}

/// Opens a sent photo full screen: black, pinch or double-tap to zoom,
/// the preview shown at once while the full copy loads. The app's capture
/// protection (FLAG_SECURE, the iOS CaptureShield) covers it like every
/// route.
Route<void> chatImageRoute(ChatStore chat, ChatMessage message) => PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 240),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (BuildContext context, Animation<double> animation, _) => ChatImageViewer(chat: chat, message: message),
      transitionsBuilder: (BuildContext context, Animation<double> animation, _, Widget child) =>
          FadeTransition(opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut), child: child),
    );

class ChatImageViewer extends StatefulWidget {
  const ChatImageViewer({super.key, required this.chat, required this.message});

  final ChatStore chat;
  final ChatMessage message;

  @override
  State<ChatImageViewer> createState() => _ChatImageViewerState();
}

class _ChatImageViewerState extends State<ChatImageViewer> {
  final TransformationController _zoom = TransformationController();
  Offset _tap = Offset.zero;

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  void _toggleZoom() {
    if (_zoom.value.getMaxScaleOnAxis() > 1.01) {
      _zoom.value = Matrix4.identity();
      return;
    }
    const double scale = 2.5;
    _zoom.value = Matrix4.identity()
      ..translateByDouble(-_tap.dx * (scale - 1), -_tap.dy * (scale - 1), 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  @override
  Widget build(BuildContext context) {
    final ChatMessage message = widget.message;
    final double ratio = message.attachment?.aspectRatio ?? 4 / 3;
    final String caption = message.body?.trim() ?? '';
    final EdgeInsets safe = MediaQuery.paddingOf(context);
    ImageProvider<Object> copy({required bool preview}) =>
        ChatImageProvider(chat: widget.chat, roomId: message.roomId, messageId: message.id, preview: preview);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onDoubleTapDown: (TapDownDetails details) => _tap = details.localPosition,
                onDoubleTap: _toggleZoom,
                child: InteractiveViewer(
                  transformationController: _zoom,
                  minScale: 1,
                  maxScale: 5,
                  child: Center(
                    child: Hero(
                      tag: chatImageHeroTag(message),
                      child: AspectRatio(
                        aspectRatio: ratio,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // Already in memory from the bubble.
                            Image(image: copy(preview: true), fit: BoxFit.contain, gaplessPlayback: true, errorBuilder: (_, _, _) => const SizedBox.shrink()),
                            Image(
                              key: const ValueKey<String>('chat-image-full'),
                              image: copy(preview: false),
                              fit: BoxFit.contain,
                              frameBuilder: (BuildContext context, Widget child, int? frame, bool sync) => AnimatedOpacity(
                                opacity: frame == null ? 0 : 1,
                                duration: const Duration(milliseconds: 200),
                                child: child,
                              ),
                              // The preview stays when the full copy cannot load.
                              errorBuilder: (_, _, _) => const SizedBox.shrink(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (caption.isNotEmpty)
              PositionedDirectional(
                start: 0,
                end: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: Container(
                    padding: EdgeInsets.fromLTRB(20, 36, 20, 18 + safe.bottom),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[Color(0x00000000), Color(0xB3000000)],
                      ),
                    ),
                    child: Text(
                      caption,
                      textDirection: chatTextDirection(caption),
                      style: const TextStyle(
                        fontFamily: NovaTypography.body,
                        fontFamilyFallback: NovaTypography.fallback,
                        fontWeight: FontWeight.w500,
                        fontSize: 15,
                        height: 1.4,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            PositionedDirectional(
              top: safe.top + 8,
              start: 8,
              child: Material(
                color: Colors.black.withValues(alpha: 0.45),
                shape: const CircleBorder(),
                child: IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  tooltip: context.tr('chat.close'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
