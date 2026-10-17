import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfx/pdfx.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/watermark_overlay.dart';
import '../../data/models.dart';

/// A lesson PDF (D-132: opened from the Lesson page): fetched through its short-lived signed URL with the
/// session, rendered in-app under the Student's watermark. The window is
/// `FLAG_SECURE` on Android and blurred during capture on iOS.
class LessonPdfScreen extends StatefulWidget {
  const LessonPdfScreen({super.key, required this.lesson, this.pdf});

  final Lesson lesson;

  /// D-142: one of the Lesson's PDFs; without it, the Lesson's first PDF.
  final LessonPdf? pdf;

  @override
  State<LessonPdfScreen> createState() => _LessonPdfScreenState();
}

class _LessonPdfScreenState extends State<LessonPdfScreen> {
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
      final List<int> bytes = await app.learning.lessonPdf(widget.lesson.id, pdfId: widget.pdf?.id);
      if (!mounted) return;
      setState(() {
        _controller = PdfControllerPinch(
          document: PdfDocument.openData(Uint8List.fromList(bytes)),
        );
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
                  ),
                  Expanded(
                    child: Text(
                      widget.pdf?.title ?? widget.lesson.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: NovaTypography.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  if (_error != null)
                    EmptyState(
                      icon: Icons.picture_as_pdf_rounded,
                      title: context.tr('learn.pdfUnavailable'),
                      message: _error!,
                    )
                  else if (controller == null)
                    const Center(child: CircularProgressIndicator())
                  else
                    PdfViewPinch(
                      controller: controller,
                      backgroundDecoration: BoxDecoration(color: NovaColors.paper),
                    ),
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

