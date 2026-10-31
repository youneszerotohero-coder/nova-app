import 'dart:io';
import 'dart:ui';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/desktop/desktop_layout.dart';

/// Where a downloaded Lesson PDF goes (owner decision 2026-10-29). Phones: the
/// app's documents (`downloads/`), then the system share sheet, from which
/// the Student saves it to Files or Drive, prints it or sends it. PC app: the
/// Windows share sheet cannot save a file, so the copy goes to the Downloads
/// folder and opens in the PC's PDF reader. The copy carries the Student's
/// name, phone and the date on every page.
abstract class LessonPdfSaver {
  /// Tests install a fake (no file system, no share sheet).
  static LessonPdfSaver Function() factory =
      () => isDesktopApp ? _DownloadsFolderPdfSaver() : _ShareSheetPdfSaver();

  /// [origin] anchors the share sheet on iPad. Returns the saved file's path
  /// when the copy stays in a folder the Student knows (PC app), else null.
  Future<String?> save(String fileName, List<int> bytes, {Rect? origin});
}

class _ShareSheetPdfSaver implements LessonPdfSaver {
  @override
  Future<String?> save(String fileName, List<int> bytes, {Rect? origin}) async {
    final Directory documents = await getApplicationDocumentsDirectory();
    final Directory folder = await Directory('${documents.path}/downloads').create(recursive: true);
    final File file = await File('${folder.path}/$fileName').writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(
      files: <XFile>[XFile(file.path, mimeType: 'application/pdf', name: fileName)],
      sharePositionOrigin: origin,
    ));
    return null;
  }
}

class _DownloadsFolderPdfSaver implements LessonPdfSaver {
  @override
  Future<String?> save(String fileName, List<int> bytes, {Rect? origin}) async {
    final Directory folder = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    final File file = await freeDownloadPath(folder.path, fileName).writeAsBytes(bytes, flush: true);
    await launchUrl(Uri.file(file.path));
    return file.path;
  }
}

/// `name.pdf`, then `name (2).pdf`, `name (3).pdf`…: an earlier copy is
/// never overwritten.
File freeDownloadPath(String folder, String fileName) {
  final int dot = fileName.toLowerCase().endsWith('.pdf') ? fileName.length - 4 : fileName.length;
  final String base = fileName.substring(0, dot);
  final String extension = fileName.substring(dot);
  File file = File('$folder${Platform.pathSeparator}$fileName');
  for (int n = 2; file.existsSync(); n++) {
    file = File('$folder${Platform.pathSeparator}$base ($n)$extension');
  }
  return file;
}
