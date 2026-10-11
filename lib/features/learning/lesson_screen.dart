import 'package:flutter/material.dart';

import '../../core/api/api_exception.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_dimens.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/utils/player_fullscreen.dart';
import '../../core/widgets/hero_style.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../data/json.dart';
import '../../data/models.dart';
import '../../data/playback_models.dart';
import '../player/lesson_player.dart';
import '../shell/student_top_bar.dart';
import 'lesson_pdf_screen.dart';
import 'quiz_runner.dart';

/// One Lesson on one page (D-132), for Students who need the path spelled
/// out: 1. its video, 2. its PDF, 3. its quiz, each with a plain sentence of
/// what to do, the three steps ticked as they are done, then the previous or
/// next Lesson. A past Live is a Lesson like the others ("Recorded during the
/// live class"). Progress, completion and quiz grading stay the server's.
class LessonScreen extends StatefulWidget {
  const LessonScreen({super.key, required this.course, required this.index});

  /// Shared with the Unit page, which shows the progress made here.
  final ValueNotifier<Course> course;
  final int index;

  @override
  State<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends State<LessonScreen> {
  late int _index = widget.index;
  bool _fullscreen = false;

  /// Keeps the one player (and its native surface) alive when it moves
  /// between the inline and fullscreen layouts.
  final GlobalKey _playerKey = GlobalKey();
  final GlobalKey _videoKey = GlobalKey();
  final GlobalKey _pdfKey = GlobalKey();
  final GlobalKey _quizKey = GlobalKey();
  final ScrollController _scroll = ScrollController();

  /// PDFs opened during this visit (the server does not record reading).
  final Set<int> _pdfOpened = <int>{};

  /// The Student's attempts at this Lesson's quiz (best score, next try).
  QuizAttempts? _attempts;
  bool _quizLoading = false;

  Course get _course => widget.course.value;
  Lesson get _lesson => _course.lessons[_index];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadQuiz());
  }

  @override
  void dispose() {
    if (_fullscreen) exitPlayerFullscreen();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadQuiz() async {
    final AppState app = AppScope.of(context);
    final Lesson lesson = _lesson;
    setState(() => _attempts = null);
    if (!lesson.hasQuiz || app.api == null) return;
    setState(() => _quizLoading = true);
    try {
      final (StudentQuiz _, QuizAttempts attempts) = await app.learning.quiz(lesson.id);
      if (mounted && _lesson.id == lesson.id) setState(() => _attempts = attempts);
    } on ApiException {
      // The button still opens the quiz, which explains a refusal.
    } finally {
      if (mounted) setState(() => _quizLoading = false);
    }
  }

  void _go(int index) {
    if (index < 0 || index >= _course.lessons.length || index == _index) return;
    setState(() => _index = index);
    _scroll.jumpTo(0);
    _loadQuiz();
  }

  /// A saved progress report: update the lesson, and when it completes
  /// reload the Course so the Unit's progress follows.
  Future<void> _onProgress(Json row) async {
    final int lessonId = row.integer('lesson_id');
    final bool completed = row.flag('completed');
    final bool wasComplete = _course.lessons.any((Lesson l) => l.id == lessonId && l.completed);
    widget.course.value = _course.copyWith(lessons: <Lesson>[
      for (final Lesson lesson in _course.lessons)
        lesson.id == lessonId
            ? lesson.withProgress(<String, dynamic>{
                'video_progress_percent': row['video_progress_percent'],
                'resume_position_seconds': row['resume_position_seconds'],
                'unlocked': true,
                'has_quiz': lesson.hasQuiz,
                'quiz_required': lesson.quizRequired,
                'has_pdf': lesson.hasPdf,
                'from_live': lesson.fromLive,
                'completed': completed,
              })
            : lesson,
    ]);
    if (mounted) setState(() {});
    if (completed && !wasComplete) await _refreshCourse();
  }

  Future<void> _refreshCourse() async {
    final AppState app = AppScope.of(context);
    try {
      widget.course.value = await app.learning.courseWithProgress(_course);
      if (mounted) setState(() {});
      app.learning.load();
    } on ApiException {
      // The next manual refresh picks it up.
    }
  }

  Future<void> _setFullscreen(bool value) async {
    setState(() => _fullscreen = value);
    await (value ? enterPlayerFullscreen() : exitPlayerFullscreen());
  }

  Future<void> _openPdf() async {
    setState(() => _pdfOpened.add(_lesson.id));
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LessonPdfScreen(lesson: _lesson)));
  }

  Future<void> _openQuiz() async {
    await openLessonQuiz(context, _lesson, onPassed: _refreshCourse);
    if (mounted) _loadQuiz();
  }

  void _scrollTo(GlobalKey key) {
    final BuildContext? target = key.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(target, duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic, alignment: 0.05);
    }
  }

  Widget _player() => LessonPlayer(
        key: _playerKey,
        course: _course,
        lesson: _lesson,
        onProgress: _onProgress,
        fullscreen: _fullscreen,
        onToggleFullscreen: () => _setFullscreen(!_fullscreen),
      );

  @override
  Widget build(BuildContext context) {
    if (_fullscreen) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (bool didPop, Object? _) {
          if (!didPop) _setFullscreen(false);
        },
        child: Scaffold(backgroundColor: Colors.black, body: SizedBox.expand(child: _player())),
      );
    }

    final Lesson lesson = _lesson;
    final List<Lesson> lessons = _course.lessons;
    final bool videoDone = lesson.completed || lesson.watched >= 90;
    final bool quizPassed = (_attempts?.passed ?? lesson.quiz?.passed ?? false) || (lesson.completed && lesson.quizRequired);
    final List<({String label, _Step state, GlobalKey key})> steps = [
      (label: context.tr('lesson.stepVideo'), state: videoDone ? _Step.done : _Step.todo, key: _videoKey),
      (label: context.tr('lesson.stepPdf'), state: !lesson.hasPdf ? _Step.none : _pdfOpened.contains(lesson.id) ? _Step.done : _Step.todo, key: _pdfKey),
      (label: context.tr('lesson.stepQuiz'), state: !lesson.hasQuiz ? _Step.none : quizPassed ? _Step.done : _Step.todo, key: _quizKey),
    ];

    return Scaffold(
      body: ListView(
        controller: _scroll,
        padding: const EdgeInsets.only(bottom: 36),
        children: [
          StudentTopBar(
            showBack: true,
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(color: NovaColors.accent, borderRadius: BorderRadius.circular(100)),
              child: Text(
                context.trf('learn.lessonOf', {'i': '${_index + 1}', 'n': '${lessons.length}'}),
                style: NovaTypography.textTheme.labelLarge!.copyWith(color: Colors.white),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(lesson.title, style: NovaTypography.textTheme.displaySmall!.copyWith(fontSize: 25)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    HeroChip(
                      icon: Icons.schedule_rounded,
                      label: lesson.minutes > 0 ? context.trf('unit.minutes', {'n': '${lesson.minutes}'}) : context.tr('lesson.durationPending'),
                    ),
                    if (lesson.fromLive)
                      HeroChip(icon: Icons.sensors_rounded, label: context.tr('lesson.fromLive'), color: const Color(0xFF2F86DA), background: const Color(0x2E4FACF0)),
                    if (lesson.completed)
                      HeroChip(icon: Icons.check_circle_outline_rounded, label: context.tr('lesson.completed'), color: NovaColors.onlineGreen, background: NovaColors.onlineGreen.withValues(alpha: 0.14)),
                  ],
                ),
                if (lesson.description.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(lesson.description, style: NovaTypography.muted(NovaTypography.textTheme.bodyMedium!)),
                ],
                const SizedBox(height: 14),
                _StepsBar(steps: steps, onTap: _scrollTo),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // 1. The video meets the screen edges, as on YouTube.
          Container(
            key: _videoKey,
            padding: const EdgeInsets.only(top: 14, bottom: 14),
            color: NovaColors.paperCard,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _BlockTitle(number: 1, text: context.tr('lesson.blockVideo')),
                ),
                const SizedBox(height: 12),
                _player(),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      if (videoDone) ...[
                        const Icon(Icons.check_circle_outline_rounded, size: 18, color: NovaColors.onlineGreen),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          videoDone
                              ? context.tr('lesson.videoDone')
                              : lesson.watched > 0
                                  ? context.trf('lesson.videoProgress', {'n': '${lesson.watched}'})
                                  : context.tr('lesson.videoHint'),
                          style: NovaTypography.textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w600, color: NovaColors.textStrong.withValues(alpha: 0.8)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // 2. The PDF.
          _Block(
            key: _pdfKey,
            number: 2,
            title: context.tr('lesson.blockPdf'),
            empty: !lesson.hasPdf,
            child: !lesson.hasPdf
                ? _EmptyLine(context.tr('lesson.noPdf'))
                : _Tool(
                    icon: Icons.description_outlined,
                    iconColor: NovaColors.heartRed,
                    iconBackground: NovaColors.heartRed.withValues(alpha: 0.1),
                    title: context.tr('lesson.pdfTitle'),
                    text: _pdfOpened.contains(lesson.id) ? context.tr('lesson.pdfOpened') : context.tr('lesson.pdfText'),
                    button: NovaButton(
                      label: context.tr('lesson.openPdf'),
                      variant: NovaButtonVariant.soft,
                      chipIcon: Icons.description_outlined,
                      expand: true,
                      onTap: _openPdf,
                    ),
                  ),
          ),
          const SizedBox(height: 14),
          // 3. The quiz.
          _Block(
            key: _quizKey,
            number: 3,
            title: context.tr('lesson.blockQuiz'),
            empty: !lesson.hasQuiz,
            child: !lesson.hasQuiz ? _EmptyLine(context.tr('lesson.noQuiz')) : _quizTool(lesson, quizPassed),
          ),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: NovaButton(
                    label: context.tr('lesson.previous'),
                    variant: NovaButtonVariant.ghost,
                    icon: Icons.arrow_back_rounded,
                    expand: true,
                    onTap: _index > 0 ? () => _go(_index - 1) : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _index < lessons.length - 1
                      ? NovaButton(
                          label: context.tr('lesson.next'),
                          chipIcon: Icons.arrow_forward_rounded,
                          expand: true,
                          onTap: () => _go(_index + 1),
                        )
                      : NovaButton(
                          label: context.tr('lesson.allLessons'),
                          chipIcon: Icons.format_list_bulleted_rounded,
                          expand: true,
                          onTap: () => Navigator.of(context).maybePop(),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _quizTool(Lesson lesson, bool passed) {
    final QuizAttempts? attempts = _attempts;
    final bool waiting = attempts != null && !attempts.canStart;
    final int? best = attempts?.bestScore ?? (lesson.quiz != null && lesson.quiz!.attemptsUsed > 0 ? lesson.quiz!.bestScore : null);
    final String hint = _quizLoading
        ? context.tr('lesson.quizLoading')
        : waiting && attempts.retryAt != null
            ? context.trf('lesson.quizRetryAt', {'date': shortDate(attempts.retryAt)})
            : best != null
                ? context.trf('lesson.bestScore', {'n': '$best'})
                : lesson.quizRequired
                    ? context.tr('lesson.quizRequired')
                    : context.tr('lesson.quizFree');
    return _Tool(
      icon: passed ? Icons.emoji_events_outlined : Icons.help_outline_rounded,
      iconColor: passed ? NovaColors.onlineGreen : NovaColors.badgeOrange,
      iconBackground: passed ? NovaColors.onlineGreen.withValues(alpha: 0.14) : NovaColors.yellow.withValues(alpha: 0.3),
      title: passed ? context.tr('lesson.quizPassed') : context.tr('lesson.quizTitle'),
      text: hint,
      button: NovaButton(
        label: passed || best != null ? context.tr('lesson.quizRetake') : context.tr('lesson.quizStart'),
        variant: passed ? NovaButtonVariant.ghost : NovaButtonVariant.yellow,
        chipIcon: Icons.play_arrow_rounded,
        expand: true,
        onTap: waiting ? null : _openQuiz,
      ),
    );
  }
}

enum _Step { done, todo, none }

/// `.lessonSteps`: Video / PDF / Quiz, ticked as they are done; a tap goes there.
class _StepsBar extends StatelessWidget {
  const _StepsBar({required this.steps, required this.onTap});

  final List<({String label, _Step state, GlobalKey key})> steps;
  final ValueChanged<GlobalKey> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: NovaColors.paperCard,
        borderRadius: BorderRadius.circular(NovaDimens.radiusTile),
        border: Border.all(color: NovaColors.borderOnLight),
        boxShadow: NovaDimens.shadowCard,
      ),
      child: Row(
        children: [
          for (int i = 0; i < steps.length; i++)
            Expanded(
              child: PressableScale(
                onTap: steps[i].state == _Step.none ? null : () => onTap(steps[i].key),
                semanticLabel: steps[i].label,
                child: Opacity(
                  opacity: steps[i].state == _Step.none ? 0.5 : 1,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 400),
                          transitionBuilder: (Widget child, Animation<double> a) => ScaleTransition(
                            scale: CurvedAnimation(parent: a, curve: Curves.elasticOut),
                            child: child,
                          ),
                          child: Container(
                            key: ValueKey<_Step>(steps[i].state),
                            width: 34,
                            height: 34,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: switch (steps[i].state) {
                                _Step.done => NovaColors.onlineGreen,
                                _Step.todo => NovaColors.yellow,
                                _Step.none => NovaColors.accentMist,
                              },
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: steps[i].state == _Step.done
                                ? const Icon(Icons.check_rounded, size: 20, color: Colors.white)
                                : Text(
                                    '${i + 1}',
                                    style: NovaTypography.textTheme.titleMedium!.copyWith(
                                      color: steps[i].state == _Step.todo ? NovaColors.yellowInk : NovaColors.accent,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(steps[i].label, style: NovaTypography.textTheme.labelLarge),
                        Text(
                          switch (steps[i].state) {
                            _Step.done => context.tr('lesson.stepDone'),
                            _Step.todo => context.tr('lesson.stepTodo'),
                            _Step.none => context.tr('lesson.stepNone'),
                          },
                          style: NovaTypography.textTheme.labelSmall!.copyWith(
                            color: steps[i].state == _Step.done ? NovaColors.onlineGreen : NovaColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BlockTitle extends StatelessWidget {
  const _BlockTitle({required this.number, required this.text, this.muted = false});

  final int number;
  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: muted ? NovaColors.textStrong.withValues(alpha: 0.18) : NovaColors.accent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text('$number', style: NovaTypography.textTheme.titleMedium!.copyWith(color: Colors.white)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: NovaTypography.textTheme.headlineSmall)),
      ],
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({super.key, required this.number, required this.title, required this.child, this.empty = false});

  final int number;
  final String title;
  final Widget child;
  final bool empty;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Entrance(
        delay: Duration(milliseconds: 80 * number),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: NovaColors.paperCard,
            borderRadius: BorderRadius.circular(NovaDimens.radiusTile),
            border: Border.all(color: NovaColors.borderOnLight),
            boxShadow: NovaDimens.shadowCard,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _BlockTitle(number: number, text: title, muted: empty),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _Tool extends StatelessWidget {
  const _Tool({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.title,
    required this.text,
    required this.button,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String title;
  final String text;
  final Widget button;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: iconBackground, borderRadius: BorderRadius.circular(16)),
              child: Icon(icon, size: 26, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: NovaTypography.textTheme.titleMedium!.copyWith(fontSize: 17)),
                  const SizedBox(height: 3),
                  Text(text, style: NovaTypography.muted(NovaTypography.textTheme.bodyMedium!)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        button,
      ],
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: NovaColors.paperRaised, borderRadius: BorderRadius.circular(12)),
      child: Text(text, style: NovaTypography.muted(NovaTypography.textTheme.bodyMedium!).copyWith(fontWeight: FontWeight.w600)),
    );
  }
}
