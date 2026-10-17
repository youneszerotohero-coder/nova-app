import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfx/pdfx.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/watermark_overlay.dart';

/// A PDF sent in a group chat, as Lesson PDFs are shown: its bytes come
/// through the message's signed URL, stay in memory (never written to
/// disk) and render under the viewer's moving watermark; the window is
/// protected from capture like the rest of the app.
class ChatPdfScreen extends StatefulWidget {
  const ChatPdfScreen({super.key, required this.roomId, required this.messageId, required this.title});

  final int roomId;
  final int messageId;
  final String title;

  @override
  State<ChatPdfScreen> createState() => _ChatPdfScreenState();
}

class _ChatPdfScreenState extends State<ChatPdfScreen> {
  PdfControllerPinch? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final AppState app = AppScope.of(context);
    try {
      final List<int> bytes = await app.chat.pdfBytes(widget.roomId, widget.messageId);
      if (!mounted) return;
      setState(() {
        _controller = PdfControllerPinch(document: PdfDocument.openData(Uint8List.fromList(bytes)));
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = apiErrorText(context, error));
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final PdfControllerPinch? controller = _controller;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 20, 10),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                    tooltip: context.tr('common.back'),
                  ),
                  Expanded(
                    child: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: NovaTypography.textTheme.titleMedium),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  if (_error != null)
                    EmptyState(icon: Icons.picture_as_pdf_rounded, title: context.tr('learn.pdfUnavailable'), message: _error!)
                  else if (controller == null)
                    const Center(child: CircularProgressIndicator())
                  else
                    PdfViewPinch(controller: controller, backgroundDecoration: BoxDecoration(color: NovaColors.paper)),
                  const IgnorePointer(child: WatermarkOverlay()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
