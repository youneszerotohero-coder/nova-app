import 'dart:io';
import 'dart:ui';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Where a downloaded Lesson PDF goes (owner decision 2026-10-29): the
/// app's documents (`downloads/`), then the system share sheet, from which
/// the Student saves it to Files or Drive, prints it or sends it. The copy
/// carries the Student's name, phone and the date on every page.
abstract class LessonPdfSaver {
  /// Tests install a fake (no file system, no share sheet).
  static LessonPdfSaver Function() factory = _ShareSheetPdfSaver.new;

  /// [origin] anchors the share sheet on iPad.
  Future<void> save(String fileName, List<int> bytes, {Rect? origin});
}

class _ShareSheetPdfSaver implements LessonPdfSaver {
  @override
  Future<void> save(String fileName, List<int> bytes, {Rect? origin}) async {
    final Directory documents = await getApplicationDocumentsDirectory();
    final Directory folder = await Directory('${documents.path}/downloads').create(recursive: true);
    final File file = await File('${folder.path}/$fileName').writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(
      files: <XFile>[XFile(file.path, mimeType: 'application/pdf', name: fileName)],
      sharePositionOrigin: origin,
    ));
  }
}
