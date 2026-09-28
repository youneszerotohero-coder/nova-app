import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/state/app_state.dart';
import '../../core/widgets/nova_toast.dart';
import '../../data/models.dart';
import 'learn_screen.dart';

/// Opens an owned Course in the learning space with its curriculum and
/// the Student's per-lesson lock/progress loaded from the backend.
Future<void> openOwnedCourse(BuildContext context, Course course) async {
  final AppState app = AppScope.of(context);
  final NavigatorState navigator = Navigator.of(context);
  // Back cannot close the spinner: the pop below would then close the
  // screen under it instead.
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: Center(child: CircularProgressIndicator()),
    ),
  );
  Course? full;
  ApiException? failure;
  try {
    full = course.lessons.isEmpty
        ? await app.catalog.course(course.slug, owned: true)
        : course;
    full = await app.learning.courseWithProgress(full);
  } on ApiException catch (error) {
    failure = error;
  } finally {
    navigator.pop();
  }
  if (failure == null) {
    final Course opened = full!;
    navigator.push(
      MaterialPageRoute<void>(builder: (_) => LearnScreen(course: opened)),
    );
  } else if (context.mounted) {
    novaToast(context, apiErrorText(context, failure),
        icon: Icons.error_outline_rounded);
  }
}
