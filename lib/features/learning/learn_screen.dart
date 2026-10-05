import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfx/pdfx.dart';

import '../../core/utils/player_fullscreen.dart';
import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/widgets/celebration_dialog.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/nova_toast.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../core/widgets/progress_ring.dart';
import '../../core/widgets/watermark_overlay.dart';
import '../../data/json.dart';
import '../../data/models.dart';
import '../../data/playback_models.dart';
import '../player/lesson_player.dart';

/// The learning space for one owned course, on the backend's rules:
/// the protected lesson player (resume, verified progress, 90 %
/// completion), server-computed sequential unlocking, lesson Quizzes
/// (opened at 90 %, graded server-side) and watermarked lesson PDFs.
class LearnScreen extends StatefulWidget {
  const LearnScreen({super.key, required this.course});

  final Course course;

  @override
  State<LearnScreen> createState() => _LearnScreenState();
}

class _LearnScreenState extends State<LearnScreen> {
  late Course _course = widget.course;
  int _tab = 0;
  bool _fullscreen = false;

  /// Keeps the one player (and its native surface) alive when it moves
  /// between the inline and fullscreen layouts.
  final GlobalKey _playerKey = GlobalKey();

  /// First lesson not yet completed; a finished course opens on its last.
  late int _activeLesson = _initialActiveLesson(widget.course);

  static int _initialActiveLesson(Course course) {
    if (course.lessons.isEmpty) return 0;
    final int index = course.lessons.indexWhere((Lesson lesson) => !lesson.completed);
    return index == -1 ? course.lessons.length - 1 : index;
  }

  /// The backend decides which lessons are open (all earlier lessons
  /// completed); the active one always is.
  bool _canOpen(int index) => index == _activeLesson || _course.lessons[index].unlocked;

  void _selectLesson(int index) {
    if (!_canOpen(index) || index == _activeLesson) return;
    setState(() => _activeLesson = index);
  }

  /// A saved progress report: update the lesson, and when it completes
  /// reload the course so the next lesson unlocks.
  Future<void> _onProgress(Json row) async {
    final int lessonId = row.integer('lesson_id');
    final bool completed = row.flag('completed');
    final List<Lesson> lessons = <Lesson>[
      for (final Lesson lesson in _course.lessons)
        lesson.id == lessonId
            ? lesson.withProgress(<String, dynamic>{
                'video_progress_percent': row['video_progress_percent'],
                'resume_position_seconds': row['resume_position_seconds'],
                'unlocked': true,
                'has_quiz': lesson.hasQuiz,
                'quiz_required': lesson.quizRequired,
                'has_pdf': lesson.hasPdf,
                'completed': completed,
              })
            : lesson,
    ];
    if (!mounted) return;
    final bool wasComplete =
        _course.lessons.any((Lesson l) => l.id == lessonId && l.completed);
    setState(() => _course = _course.copyWith(lessons: lessons));
    if (completed && !wasComplete) await _refreshCourse();
  }

  Future<void> _refreshCourse() async {
    final AppState app = AppScope.of(context);
    try {
      final Course fresh = await app.learning.courseWithProgress(_course);
      if (mounted) setState(() => _course = fresh);
      app.learning.load();
    } on ApiException {
      // The next manual refresh picks it up.
    }
  }

  Future<void> _setFullscreen(bool value) async {
    setState(() => _fullscreen = value);
    await (value ? enterPlayerFullscreen() : exitPlayerFullscreen());
  }

  @override
  void dispose() {
    if (_fullscreen) exitPlayerFullscreen();
    super.dispose();
  }

  Widget _player() {
    if (_course.lessons.isEmpty) return const SizedBox.shrink();
    return LessonPlayer(
      key: _playerKey,
      course: _course,
      lesson: _course.lessons[_activeLesson],
      onProgress: _onProgress,
      fullscreen: _fullscreen,
      onToggleFullscreen: () => _setFullscreen(!_fullscreen),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_fullscreen) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (bool didPop, Object? _) {
          if (!didPop) _setFullscreen(false);
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SizedBox.expand(child: _player()),
        ),
      );
    }

    return PageScaffold(
      title: _course.title,
      kicker: context.trf('learn.headerProgress', {
        'a': _course.completedLessons.toString(),
        'b': _course.lessons.length.toString(),
        'n': _course.progressPercent.toString(),
      }),
      watermark: _course.icon,
      body: Column(
        children: [
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _Tabs(
              labels: [
                context.tr('learn.lessons'),
                context.tr('learn.quizzes'),
                context.tr('learn.resources'),
                context.tr('learn.progressTab'),
              ],
              selected: _tab,
              onChanged: (int i) => setState(() => _tab = i),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (Widget child, Animation<double> a) =>
                  FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.015),
                    end: Offset.zero,
                  ).animate(a),
                  child: child,
                ),
              ),
              child: switch (_tab) {
                0 => _buildLessons(),
                1 => _QuizzesTab(
                    key: const ValueKey<int>(1),
                    course: _course,
                    onPassed: _refreshCourse,
                  ),
                2 => _ResourcesTab(
                    key: const ValueKey<int>(2),
                    course: _course,
                  ),
                _ => _ProgressTab(
                    key: const ValueKey<int>(3),
                    course: _course,
                  ),
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLessons() {
    if (_course.lessons.isEmpty) {
      return EmptyState(
        icon: Icons.video_library_outlined,
        title: context.tr('learn.noLessons'),
        message: context.tr('learn.noLessonsMsg'),
      );
    }
    final Lesson lesson = _course.lessons[_activeLesson];
    final bool awaitingQuiz = !lesson.completed && lesson.quizRequired;

    return ListView(
      key: const ValueKey<int>(0),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
      children: [
        _player(),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Text(
                lesson.title,
                style: NovaTypography.textTheme.titleMedium,
              ),
            ),
            if (awaitingQuiz)
              Icon(Icons.quiz_outlined, size: 19, color: NovaColors.textMuted),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${context.trf('learn.lessonOf', {
            'i': (_activeLesson + 1).toString(),
            'n': _course.lessons.length.toString(),
          })}'
          '${lesson.hasPdf ? context.tr('learn.includesPdf') : ''}'
          '${lesson.quizRequired ? context.tr('learn.quizRequiredToUnlock') : ''}',
          style: NovaTypography.muted(NovaTypography.textTheme.bodySmall!),
        ),
        if (lesson.watched > 0 && !lesson.completed) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill(
                icon: Icons.history_rounded,
                label: context.trf('learn.watchedPill', {'n': lesson.watched.toString()}),
              ),
              if (awaitingQuiz)
                _Pill(
                  icon: Icons.quiz_rounded,
                  label: context.tr('learn.passQuizToUnlock'),
                  onTap: () => setState(() => _tab = 1),
                ),
            ],
          ),
        ],
        const SizedBox(height: 18),
        Text(context.tr('detail.curriculum'), style: NovaTypography.textTheme.titleMedium),
        const SizedBox(height: 10),
        ...stagger(
          _course.lessons
              .asMap()
              .entries
              .map(
                (MapEntry<int, Lesson> entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _LessonRow(
                    index: entry.key,
                    lesson: entry.value,
                    active: entry.key == _activeLesson,
                    locked: !_canOpen(entry.key),
                    onTap: () => _selectLesson(entry.key),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: NovaColors.accentMist,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: NovaColors.accentDeep),
            const SizedBox(width: 6),
            Text(
              label,
              style: NovaTypography.textTheme.labelSmall!.copyWith(color: NovaColors.accentDeep),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.labels,
    required this.selected,
    required this.onChanged,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: labels.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, int index) {
          final bool active = index == selected;
          return PressableScale(
            onTap: () => onChanged(index),
            pressedScale: 0.94,
            semanticLabel: labels[index],
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? NovaColors.ink950 : NovaColors.subtleFill,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color:
                      active ? NovaColors.ink950 : NovaColors.borderOnLight,
                ),
              ),
              child: Text(
                labels[index],
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  color: active ? Colors.white : NovaColors.textStrong,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LessonRow extends StatelessWidget {
  const _LessonRow({
    required this.index,
    required this.lesson,
    required this.active,
    required this.locked,
    required this.onTap,
  });

  final int index;
  final Lesson lesson;
  final bool active;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool done = lesson.completed;

    return PressableScale(
      onTap: locked ? null : onTap,
      pressedScale: 0.98,
      semanticLabel: lesson.title,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        opacity: locked ? 0.55 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: NovaColors.paperCard,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: active ? NovaColors.accent : NovaColors.borderOnLight,
              width: active ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done
                      ? NovaColors.accent
                      : locked
                          ? NovaColors.veilOnDark
                          : NovaColors.accentMist,
                ),
                child: Icon(
                  locked
                      ? Icons.lock_rounded
                      : done
                          ? Icons.check_rounded
                          : Icons.play_arrow_rounded,
                  size: 17,
                  color: done
                      ? Colors.white
                      : locked
                          ? NovaColors.textMuted
                          : NovaColors.accentDeep,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lesson.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: NovaTypography.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      locked
                          ? context.tr('learn.lockedRow')
                          : '${context.trf('learn.rowMinutes', {'n': lesson.minutes.toString()})}'
                              '${lesson.hasPdf ? ' · PDF' : ''}'
                              '${lesson.hasQuiz ? ' · ${context.tr('learn.rowQuiz')}' : ''}',
                      style: NovaTypography.muted(
                        NovaTypography.textTheme.bodySmall!,
                      ),
                    ),
                  ],
                ),
              ),
              if (!locked && lesson.watched > 0 && !done)
                SizedBox(
                  width: 30,
                  height: 30,
                  child: ProgressRing(
                    percent: lesson.watched,
                    size: 30,
                    strokeWidth: 3,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}


/// Quizzes tab: one card per lesson that has a Quiz. Every Quiz opens at any
/// time; watching the lesson is not a condition (D-114).
class _QuizzesTab extends StatelessWidget {
  const _QuizzesTab({super.key, required this.course, required this.onPassed});

  final Course course;
  final Future<void> Function() onPassed;

  @override
  Widget build(BuildContext context) {
    final List<Lesson> quizzes =
        course.lessons.where((Lesson lesson) => lesson.hasQuiz).toList();

    if (quizzes.isEmpty) {
      return EmptyState(
        icon: Icons.quiz_outlined,
        title: context.tr('learn.noCheckpoint'),
        message: context.tr('learn.noCheckpointMsg'),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
      children: stagger(
        quizzes
            .map(
              (Lesson lesson) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _QuizCard(
                  lesson: lesson,
                  onOpen: () => openLessonQuiz(context, lesson, onPassed: onPassed),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _QuizCard extends StatelessWidget {
  const _QuizCard({required this.lesson, required this.onOpen});

  final Lesson lesson;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final bool passed = lesson.completed;

    return PressableScale(
      onTap: onOpen,
      semanticLabel: 'Open quiz: ${lesson.title}',
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: NovaColors.paperCard,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: NovaColors.borderOnLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(lesson.title, style: NovaTypography.textTheme.titleSmall),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: passed ? NovaColors.accentMist : NovaColors.veilOnDark,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    passed ? context.tr('learn.passed') : context.tr('learn.checkpoint'),
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      fontSize: 10.5,
                      color: passed ? NovaColors.accentDeep : NovaColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              lesson.quizRequired
                  ? context.tr('learn.quizRequired')
                  : context.tr('detail.quizOptional'),
              style: NovaTypography.muted(NovaTypography.textTheme.bodySmall!),
            ),
          ],
        ),
      ),
    );
  }
}

/// Loads the lesson Quiz and opens the runner, or explains why not.
Future<void> openLessonQuiz(
  BuildContext context,
  Lesson lesson, {
  required Future<void> Function() onPassed,
}) async {
  final AppState app = AppScope.of(context);
  try {
    final (StudentQuiz quiz, QuizAttempts attempts) = await app.learning.quiz(lesson.id);
    if (!context.mounted) return;
    if (!attempts.canStart) {
      novaToast(
        context,
        attempts.retryAt == null
            ? context.tr('learn.noAttemptsLeft')
            : context.trf('learn.retryAt', {'t': shortDate(attempts.retryAt)}),
        icon: Icons.timelapse_rounded,
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => QuizRunnerSheet(
        lesson: lesson,
        quiz: quiz,
        attempts: attempts,
        onPassed: onPassed,
      ),
    );
  } on ApiException catch (error) {
    if (!context.mounted) return;
    novaToast(
      context,
      error.code == 'QUIZ_LOCKED' ? context.tr('learn.quizLockedMsg') : apiErrorText(context, error),
      icon: Icons.lock_clock_rounded,
    );
  }
}

/// Full-screen quiz runner: one question at a time, then the whole
/// attempt is submitted and graded by the backend (answers are never
/// scored on the device).
class QuizRunnerSheet extends StatefulWidget {
  const QuizRunnerSheet({
    super.key,
    required this.lesson,
    required this.quiz,
    required this.attempts,
    required this.onPassed,
  });

  final Lesson lesson;
  final StudentQuiz quiz;
  final QuizAttempts attempts;
  final Future<void> Function() onPassed;

  @override
  State<QuizRunnerSheet> createState() => _QuizRunnerSheetState();
}

class _QuizRunnerSheetState extends State<QuizRunnerSheet> {
  int _question = 0;
  final Map<int, Set<int>> _answers = <int, Set<int>>{};
  bool _submitting = false;
  QuizResult? _result;
  String? _error;

  List<QuizItem> get _questions => widget.quiz.questions;
  Set<int> get _selected => _answers[_questions[_question].id] ?? <int>{};

  void _toggleOption(int optionId) {
    if (_result != null) return;
    final QuizItem question = _questions[_question];
    setState(() {
      final Set<int> selected = _answers.putIfAbsent(question.id, () => <int>{});
      if (question.multiple) {
        selected.contains(optionId) ? selected.remove(optionId) : selected.add(optionId);
      } else {
        selected
          ..clear()
          ..add(optionId);
      }
    });
  }

  Future<void> _next() async {
    if (_question + 1 < _questions.length) {
      setState(() => _question++);
      return;
    }
    await _submit();
  }

  Future<void> _submit() async {
    final AppState app = AppScope.of(context);
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final int attemptId =
          widget.attempts.openAttemptId ?? await app.learning.startAttempt(widget.quiz.id);
      final QuizResult result = await app.learning.submitAttempt(attemptId, _answers);
      if (!mounted) return;
      setState(() => _result = result);
      if (result.passed) await widget.onPassed();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = apiErrorText(context, error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _close() {
    final QuizResult? result = _result;
    Navigator.of(context).pop();
    if (result != null && result.passed) {
      showNovaCelebration(
        context,
        title: context.tr('learn.quizPassedTitle'),
        message: context.trf(
          widget.lesson.watched >= 90 ? 'learn.quizPassedMsg' : 'learn.quizPassedWatchMsg',
          {'n': result.score.toString()},
        ),
        actionLabel: context.tr('learn.keepGoing'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.heightOf(context) * 0.92,
      decoration: BoxDecoration(
        color: NovaColors.paper,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4.5,
              decoration: BoxDecoration(
                color: NovaColors.borderOnLight,
                borderRadius: BorderRadius.circular(100),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('learn.checkpointTitle'),
                          style: NovaTypography.textTheme.labelSmall!.copyWith(
                            color: NovaColors.accentDeep,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          widget.lesson.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: NovaTypography.textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _submitting ? null : _close,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(child: _result == null ? _questionView(context) : _resultView(context)),
          ],
        ),
      ),
    );
  }

  Widget _questionView(BuildContext context) {
    if (_questions.isEmpty) {
      return EmptyState(
        icon: Icons.quiz_outlined,
        title: context.tr('learn.noCheckpoint'),
        message: context.tr('learn.noCheckpointMsg'),
      );
    }
    final QuizItem question = _questions[_question];
    final bool last = _question + 1 == _questions.length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(100),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: (_question + 1) / _questions.length),
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                    builder: (BuildContext context, double value, _) => LinearProgressIndicator(
                      value: value,
                      minHeight: 6,
                      backgroundColor: NovaColors.borderOnLight,
                      valueColor: const AlwaysStoppedAnimation<Color>(NovaColors.accent),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                context.trf('learn.questionOf', {
                  'i': (_question + 1).toString(),
                  'n': _questions.length.toString(),
                }),
                style: NovaTypography.muted(NovaTypography.textTheme.bodySmall!),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(question.prompt, style: NovaTypography.textTheme.headlineSmall),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              for (final (int i, QuizOption option) in question.options.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _OptionTile(
                    letter: String.fromCharCode(65 + i),
                    label: option.label,
                    selected: _selected.contains(option.id),
                    correct: false,
                    wrong: false,
                    showState: false,
                    onTap: () => _toggleOption(option.id),
                  ),
                ),
            ],
          ),
        ),
        _BottomAction(
          hint: _error ??
              (question.multiple ? context.tr('learn.several') : context.tr('learn.pickOne')),
          hintIsError: _error != null,
          label: last ? context.tr('learn.submitQuiz') : context.tr('learn.nextQuestion'),
          busy: _submitting,
          onTap: _selected.isEmpty || _submitting ? null : _next,
          onBack: _question > 0 && !_submitting ? () => setState(() => _question--) : null,
        ),
      ],
    );
  }

  Widget _resultView(BuildContext context) {
    final QuizResult result = _result!;
    final QuizAttempts attempts = result.attempts;
    final String remaining = attempts.remaining == null
        ? context.tr('learn.unlimited')
        : attempts.remaining.toString();

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              const SizedBox(height: 10),
              Center(
                child: ProgressRing(
                  percent: result.score,
                  size: 120,
                  strokeWidth: 10,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                result.passed ? context.tr('learn.quizPassedTitle') : context.tr('learn.quizFailedTitle'),
                textAlign: TextAlign.center,
                style: NovaTypography.textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                context.trf('learn.quizScoreLine', {
                  'n': result.score.toString(),
                  'p': widget.quiz.passingScore.toString(),
                }),
                textAlign: TextAlign.center,
                style: NovaTypography.muted(NovaTypography.textTheme.bodyMedium!),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: NovaColors.paperCard,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: NovaColors.borderOnLight),
                ),
                child: Column(
                  children: [
                    _ResultRow(context.tr('learn.bestScore'), '${attempts.bestScore ?? result.score}%'),
                    _ResultRow(context.tr('learn.attemptsLeft'), remaining),
                    if (attempts.retryAt != null)
                      _ResultRow(context.tr('learn.retryFrom'), shortDate(attempts.retryAt)),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              for (final (int i, QuizItem question) in _questions.indexed)
                if (result.correctByQuestion.containsKey(question.id))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(
                          result.correctByQuestion[question.id]!
                              ? Icons.check_circle_rounded
                              : Icons.cancel_rounded,
                          size: 18,
                          color: result.correctByQuestion[question.id]!
                              ? NovaColors.onlineGreen
                              : NovaColors.heartRed,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${i + 1}. ${question.prompt}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: NovaTypography.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
        _BottomAction(
          hint: !result.passed
              ? context.tr('learn.reviewAndRetry')
              : widget.lesson.watched >= 90
                  ? context.tr('learn.nextUnlocked')
                  : context.tr('learn.finishVideoToComplete'),
          label: context.tr('learn.done'),
          onTap: _close,
        ),
      ],
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: NovaTypography.muted(NovaTypography.textTheme.bodySmall!)),
          ),
          Text(value, style: NovaTypography.textTheme.titleSmall),
        ],
      ),
    );
  }
}

class _BottomAction extends StatelessWidget {
  const _BottomAction({
    required this.hint,
    required this.label,
    required this.onTap,
    this.hintIsError = false,
    this.busy = false,
    this.onBack,
  });

  final String hint;
  final bool hintIsError;
  final String label;
  final bool busy;
  final VoidCallback? onTap;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + MediaQuery.paddingOf(context).bottom),
      decoration: BoxDecoration(
        color: NovaColors.paperCard,
        border: Border(top: BorderSide(color: NovaColors.borderOnLight)),
      ),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(onPressed: onBack, icon: const Icon(Icons.arrow_back_rounded)),
          Expanded(
            child: Text(
              hint,
              style: hintIsError
                  ? NovaTypography.textTheme.bodySmall!.copyWith(color: NovaColors.heartRed)
                  : NovaTypography.muted(NovaTypography.textTheme.bodySmall!),
            ),
          ),
          const SizedBox(width: 12),
          PressableScale(
            onTap: onTap,
            semanticLabel: label,
            child: Container(
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 22),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: onTap == null ? NovaColors.veilOnDark : NovaColors.ink950,
                borderRadius: BorderRadius.circular(100),
              ),
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                    )
                  : Text(
                      label,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: NovaColors.textOnDark,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.letter,
    required this.label,
    required this.selected,
    required this.correct,
    required this.wrong,
    required this.showState,
    required this.onTap,
  });

  final String letter;
  final String label;
  final bool selected;
  final bool correct;
  final bool wrong;
  final bool showState;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color border = showState && correct
        ? NovaColors.accent
        : showState && wrong
            ? NovaColors.heartRed
            : selected
                ? NovaColors.accent
                : NovaColors.borderOnLight;
    final Color bg = showState && correct
        ? NovaColors.accentMist
        : showState && wrong
            ? NovaColors.heartRed.withValues(alpha: 0.08)
            : selected
                ? NovaColors.accentMist
                : NovaColors.paperCard;

    return PressableScale(
      onTap: onTap,
      pressedScale: 0.985,
      semanticLabel: label,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: border, width: 1.3),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected || (showState && correct)
                    ? NovaColors.accent
                    : Colors.transparent,
                border: Border.all(
                  color: selected || (showState && correct)
                      ? NovaColors.accent
                      : NovaColors.textMuted,
                ),
              ),
              child: Center(
                child: showState && correct
                    ? const Icon(Icons.check_rounded,
                        size: 16, color: Colors.white)
                    : showState && wrong
                        ? const Icon(Icons.close_rounded,
                            size: 15, color: NovaColors.heartRed)
                        : Text(
                            letter,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                              color: selected
                                  ? Colors.white
                                  : NovaColors.textMuted,
                            ),
                          ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label, style: NovaTypography.textTheme.bodyMedium),
            ),
          ],
        ),
      ),
    );
  }
}

/// Resources tab: the course's lesson PDFs, opened in-app.
class _ResourcesTab extends StatelessWidget {
  const _ResourcesTab({super.key, required this.course});

  final Course course;

  @override
  Widget build(BuildContext context) {
    final List<Lesson> pdfs = course.lessons.where((Lesson lesson) => lesson.hasPdf).toList();

    if (pdfs.isEmpty) {
      return EmptyState(
        icon: Icons.picture_as_pdf_rounded,
        title: context.tr('learn.noResources'),
        message: context.tr('learn.noResourcesMsg'),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
      children: stagger(
        pdfs
            .map(
              (Lesson lesson) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _PdfRow(lesson: lesson, locked: !lesson.unlocked),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _PdfRow extends StatelessWidget {
  const _PdfRow({required this.lesson, required this.locked});

  final Lesson lesson;

  /// PDFs follow their lesson's lock (backend `LessonPolicy@view`).
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: locked
          ? null
          : () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => _PdfViewerScreen(lesson: lesson)),
              ),
      semanticLabel: 'Open PDF: ${lesson.title}',
      child: Opacity(
        opacity: locked ? 0.55 : 1,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: NovaColors.paperCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: NovaColors.borderOnLight),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: NovaColors.heartRed.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  locked ? Icons.lock_rounded : Icons.picture_as_pdf_rounded,
                  size: 22,
                  color: NovaColors.heartRed,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(lesson.title, style: NovaTypography.textTheme.titleSmall),
                    const SizedBox(height: 3),
                    Text(
                      locked ? context.tr('learn.lockedRow') : context.tr('learn.privatePdf'),
                      style: NovaTypography.muted(NovaTypography.textTheme.bodySmall!),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 22, color: NovaColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// A lesson PDF: fetched through its short-lived signed URL with the
/// session, rendered in-app under the Student's watermark. The window is
/// `FLAG_SECURE` on Android and blurred during capture on iOS.
class _PdfViewerScreen extends StatefulWidget {
  const _PdfViewerScreen({required this.lesson});

  final Lesson lesson;

  @override
  State<_PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<_PdfViewerScreen> {
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
      final List<int> bytes = await app.learning.lessonPdf(widget.lesson.id);
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
                      widget.lesson.title,
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

class _ProgressTab extends StatelessWidget {
  const _ProgressTab({super.key, required this.course});

  final Course course;

  @override
  Widget build(BuildContext context) {
    final int minutes =
        course.lessons.fold(0, (int sum, Lesson lesson) => sum + lesson.minutes);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
      children: [
        NovaCard(
          child: Column(
            children: [
              ProgressRing(
                percent: course.progressPercent,
                size: 132,
                strokeWidth: 11,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CountUpText(
                      course.progressPercent,
                      suffix: '%',
                      style: NovaTypography.textTheme.displaySmall!.copyWith(
                        fontSize: 30,
                      ),
                    ),
                    Text(
                      context.tr('learn.courseProgress'),
                      style: NovaTypography.muted(
                        NovaTypography.textTheme.bodySmall!,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                context.tr('learn.progressNote'),
                textAlign: TextAlign.center,
                style: NovaTypography.muted(NovaTypography.textTheme.bodySmall!),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: NovaCard(
                child: Column(
                  children: [
                    CountUpText(
                      course.completedLessons,
                      style: NovaTypography.textTheme.headlineSmall!.copyWith(
                        color: NovaColors.accentDeep,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.tr('learn.lessonsDone'),
                      textAlign: TextAlign.center,
                      style: NovaTypography.muted(
                        NovaTypography.textTheme.labelSmall!,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: NovaCard(
                child: Column(
                  children: [
                    CountUpText(
                      minutes,
                      style: NovaTypography.textTheme.headlineSmall!.copyWith(
                        color: NovaColors.accentDeep,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.tr('learn.watchMinutes'),
                      textAlign: TextAlign.center,
                      style: NovaTypography.muted(
                        NovaTypography.textTheme.labelSmall!,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ...stagger(
          course.lessons
              .asMap()
              .entries
              .map(
                (MapEntry<int, Lesson> entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: NovaCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${entry.key + 1}. ${entry.value.title}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: NovaTypography.textTheme.titleSmall,
                              ),
                            ),
                            _statusLabel(context, entry.value),
                          ],
                        ),
                        const SizedBox(height: 9),
                        ProgressBar(percent: entry.value.watched, height: 5),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _statusLabel(BuildContext context, Lesson lesson) {
    final String label = lesson.completed
        ? context.tr('learn.complete')
        : lesson.watched > 0
            ? context.tr('learn.inProgress')
            : context.tr('learn.notStarted');
    return Text(
      label,
      style: NovaTypography.textTheme.labelSmall!.copyWith(
        color: lesson.completed ? NovaColors.accentDeep : NovaColors.textMuted,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}
