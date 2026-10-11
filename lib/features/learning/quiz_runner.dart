import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/widgets/celebration_dialog.dart';
import '../../core/widgets/nova_toast.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../core/widgets/progress_ring.dart';
import '../../data/models.dart';
import '../../data/playback_models.dart';

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
                        fontFamily: 'Geist',
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
                              fontFamily: 'Geist',
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

