import 'package:flutter/foundation.dart';

import '../core/api/api_exception.dart';
import '../core/api/nova_api.dart';
import 'catalog_store.dart';
import 'json.dart';
import 'models.dart';
import 'playback_models.dart';

/// The signed-in Student's learning space: access grants (what they
/// own), dashboard progress and activity, and their Lives.
class LearningStore extends ChangeNotifier {
  LearningStore(this._api);

  LearningStore.seeded({
    required List<Course> owned,
    required this._lives,
  })  : _api = null,
        _owned = owned,
        _ownedIds = owned.map((Course c) => c.id).toSet(),
        _state = LoadState.ready;

  final NovaApi? _api;

  /// For best-effort traces (`/playback-diagnostics`).
  NovaApi? get api => _api;

  LoadState _state = LoadState.idle;
  List<Course> _owned = const <Course>[];
  Set<int> _ownedIds = <int>{};
  List<LiveSession> _lives = const <LiveSession>[];
  Json _dashboard = <String, dynamic>{};

  LoadState get state => _state;

  /// Courses with an active grant, with server progress, newest first.
  List<Course> get owned => _owned;
  List<LiveSession> get lives => _lives;
  Json get dashboard => _dashboard;

  bool owns(int courseId) => _ownedIds.contains(courseId);

  Future<void> load() async {
    final NovaApi? api = _api;
    if (api == null) return;
    _state = LoadState.loading;
    notifyListeners();
    try {
      final List<Json> bodies = await Future.wait(<Future<Json>>[
        api.get('/access-grants'),
        api.get('/me/dashboard'),
        api.get('/lives'),
      ]);
      final Map<int, Json> progress = <int, Json>{
        for (final Json row in bodies[1].obj('data')?.list('courses') ?? <Json>[])
          row.integer('id'): row,
      };
      _owned = <Course>[
        for (final Json grant in bodies[0].list('data'))
          _grantCourse(grant, progress[grant.obj('course')?.integer('id')]),
      ];
      _ownedIds = _owned.map((Course c) => c.id).toSet();
      _dashboard = bodies[1].obj('data') ?? <String, dynamic>{};
      _lives = bodies[2].list('data').map(LiveSession.fromJson).toList();
      _state = LoadState.ready;
    } on ApiException {
      _state = LoadState.failed;
    }
    notifyListeners();
  }

  /// Curriculum merged with the Student's per-lesson progress (lock,
  /// watched %, completion) for an owned course.
  Future<Course> courseWithProgress(Course course) async {
    final NovaApi? api = _api;
    if (api == null) return course;
    final Json data =
        (await api.get('/courses/${course.id}/progress')).obj('data') ??
            <String, dynamic>{};
    final Map<int, Json> rows = <int, Json>{
      for (final Json row in data.list('lessons')) row.integer('lesson_id'): row,
    };
    return course.copyWith(
      owned: true,
      apiProgress: dinars(data['progress_percent']),
      lessons: <Lesson>[
        for (final Lesson lesson in course.lessons)
          rows[lesson.id] == null ? lesson : lesson.withProgress(rows[lesson.id]!),
      ],
    );
  }

  /// Playback authorization for a Lesson (throttled 30/min by the
  /// backend): signed manifests, Axinom entitlement, resume point,
  /// progress session and the watermark identity. [clear] asks for the
  /// watermarked clear copy (D-070 mode B), refused in mode A with 403
  /// `VIDEO_CLEAR_DELIVERY_DISABLED`.
  Future<PlaybackAuthorization> playback(int lessonId, {bool clear = false}) async {
    final Json body = await _api!.post(
      '/lessons/$lessonId/playback',
      clear ? const <String, String>{'delivery': 'clear'} : null,
    );
    return PlaybackAuthorization.fromJson(body.obj('data') ?? <String, dynamic>{});
  }

  /// Reports the playhead; the server caps it by real elapsed time and
  /// never lets progress regress. Returns the updated lesson progress.
  Future<Json> saveProgress(int lessonId, {required int positionSeconds, required String session}) async {
    final Json body = await _api!.put('/lessons/$lessonId/progress', <String, Object>{
      'position_seconds': positionSeconds,
      'playback_session': session,
    });
    return body.obj('data') ?? <String, dynamic>{};
  }

  /// The lesson's Quiz and the Student's attempt summary; 409
  /// `QUIZ_LOCKED` until 90% of the video is watched.
  Future<(StudentQuiz, QuizAttempts)> quiz(int lessonId) async {
    final Json body = await _api!.get('/lessons/$lessonId/quiz');
    return (
      StudentQuiz.fromJson(body.obj('data') ?? <String, dynamic>{}),
      QuizAttempts.fromJson(body.obj('attempts') ?? <String, dynamic>{}),
    );
  }

  Future<int> startAttempt(int quizId) async {
    final Json body = await _api!.post('/quizzes/$quizId/attempts');
    return body.obj('data')?.integer('id') ?? 0;
  }

  Future<QuizResult> submitAttempt(int attemptId, Map<int, Set<int>> answers) async {
    final Json body = await _api!.post('/quiz-attempts/$attemptId/submit', <String, Object>{
      'answers': <Map<String, Object>>[
        for (final MapEntry<int, Set<int>> answer in answers.entries)
          <String, Object>{'question_id': answer.key, 'option_ids': answer.value.toList()},
      ],
    });
    return QuizResult.fromJson(body);
  }

  /// The lesson PDF, fetched through its 5-minute signed URL with the
  /// session cookie (both are required by the backend).
  Future<List<int>> lessonPdf(int lessonId) async {
    final Json access = (await _api!.get('/lessons/$lessonId/pdf-access')).obj('data') ??
        <String, dynamic>{};
    return _api.getBytes(access.str('url'));
  }

  /// Joins a free Course (D-054); the grant makes it owned.
  Future<void> enrollFree(Course course) async {
    final NovaApi? api = _api;
    if (api == null) return;
    await api.post('/courses/${course.id}/free-enrollment');
    await load();
  }

  void clear() {
    _owned = const <Course>[];
    _ownedIds = <int>{};
    _lives = const <LiveSession>[];
    _dashboard = <String, dynamic>{};
    _state = LoadState.idle;
    notifyListeners();
  }

  /// Access grants carry a compact course; the dashboard row adds the
  /// progress. Full details (price, level…) come from the catalogue.
  static Course _grantCourse(Json grant, Json? progress) {
    final Json course = grant.obj('course') ?? <String, dynamic>{};
    final int id = course.integer('id');
    return Course(
      id: id,
      slug: course.str('slug'),
      title: course.str('title'),
      teacher: course.str('teacher'),
      price: 0,
      compareAtPrice: 0,
      subject: course.str('subject'),
      level: '',
      scene: sceneFor(id),
      icon: subjectIcon(course.str('subject')),
      description: '',
      plannedLives: 0,
      lessons: const <Lesson>[],
      lessonsCount: progress?.integer('lessons_total') ?? 0,
      apiProgress: progress == null ? 0 : dinars(progress['progress_percent']),
      apiCompletedLessons: progress?.integer('lessons_completed'),
      owned: true,
      individualPurchaseEnabled: false,
      isFree: course.flag('is_free'),
      image: course.strOrNull('cover_url'),
    );
  }
}
