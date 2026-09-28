import 'package:flutter/foundation.dart';

import '../core/api/api_exception.dart';
import '../core/api/nova_api.dart';
import 'json.dart';
import 'models.dart';

enum LoadState { idle, loading, ready, failed }

/// Backend filters for `GET /offers`. Teacher and Subject are
/// Course-derived (D-056): an Offer matches when at least one of its
/// published Courses does, and a Teacher also through the Offer's own
/// Teachers (D-062).
class OfferFilter {
  const OfferFilter({
    this.teacherIds = const <int>{},
    this.subjectIds = const <int>{},
    this.maxPrice,
  });

  final Set<int> teacherIds;
  final Set<int> subjectIds;

  /// Whole dinars; null for any price.
  final int? maxPrice;

  bool get isEmpty =>
      teacherIds.isEmpty && subjectIds.isEmpty && maxPrice == null;

  /// Query parameters in a stable order, so equal filters share a key.
  Map<String, Object?> get query => <String, Object?>{
        'teacher_ids': teacherIds.toList()..sort(),
        'subject_ids': subjectIds.toList()..sort(),
        'max_price': maxPrice,
      };
}

/// The Offers the backend lists for an [OfferFilter]: [packs] once
/// known, [error] when the request failed, neither while it runs.
typedef OfferMatches = ({List<Pack>? packs, ApiException? error});

typedef _Pages = ({List<Json> rows, Json? facets});

/// Public catalogue: published Courses, Offers and Teachers. Anonymous
/// endpoints, so it loads before and independently of the session.
class CatalogStore extends ChangeNotifier {
  CatalogStore(this._api);

  /// Pre-filled catalogue, for tests and previews only. There are no
  /// backend facets offline: the Courses' own Teachers and Subjects
  /// stand in for them.
  CatalogStore.seeded({
    required this._courses,
    required this._offers,
    required this._teachers,
  })  : _api = null,
        _state = LoadState.ready {
    final Set<int> teacherIds = <int>{};
    final Set<int> subjectIds = <int>{};
    _teacherFacets = <Teacher>[
      for (final Course course in _courses)
        if (teacherIds.add(course.teacherId))
          _teacherById(course.teacherId) ??
              Teacher(
                id: course.teacherId,
                name: course.teacher,
                subject: course.subject,
                subjects: <String>[course.subject],
                scene: sceneFor(course.teacherId + 1),
                bio: '',
                photo: course.teacherPhoto,
              ),
    ];
    _subjectFacets = <RefItem>[
      for (final Course course in _courses)
        if (subjectIds.add(course.subjectId))
          RefItem(id: course.subjectId, name: course.subject),
    ];
  }

  final NovaApi? _api;

  LoadState _state = LoadState.idle;
  ApiException? _error;
  List<Course> _courses = const <Course>[];
  List<Pack> _offers = const <Pack>[];
  List<Teacher> _teachers = const <Teacher>[];
  List<Teacher> _teacherFacets = const <Teacher>[];
  List<RefItem> _subjectFacets = const <RefItem>[];

  /// Backend-filtered Offers per [OfferFilter.query], until the next
  /// [load]; [_generation] drops answers to an older catalogue.
  final Map<String, List<Pack>> _matches = <String, List<Pack>>{};
  final Map<String, ApiException> _matchErrors = <String, ApiException>{};
  final Set<String> _matchesPending = <String>{};
  int _generation = 0;

  LoadState get state => _state;
  ApiException? get error => _error;
  List<Course> get courses => _courses;
  List<Pack> get offers => _offers;
  List<Teacher> get teachers => _teachers;

  /// Teachers and Subjects Explore filters by: the backend facets of
  /// `/courses` and `/offers` (first page, union by id), so the ones
  /// sold only inside Offers are offered too. A Teacher carries the
  /// directory photo when the Teachers list has one.
  List<Teacher> get teacherFacets => _teacherFacets;
  List<RefItem> get subjectFacets => _subjectFacets;

  Future<void> load() async {
    final NovaApi? api = _api;
    if (api == null || _state == LoadState.loading) return;
    _state = LoadState.loading;
    _generation++;
    _matches.clear();
    _matchErrors.clear();
    _matchesPending.clear();
    notifyListeners();
    try {
      final List<_Pages> lists = await Future.wait(<Future<_Pages>>[
        _all(api, '/courses'),
        _all(api, '/offers'),
        _all(api, '/teachers'),
      ]);
      _courses = lists[0].rows.map((Json j) => Course.fromJson(j)).toList();
      _offers = lists[1].rows.map(Pack.fromJson).toList();
      _teachers = lists[2].rows.map(Teacher.fromJson).toList();
      final List<Json?> facets = <Json?>[lists[0].facets, lists[1].facets];
      _teacherFacets = _facet(
        facets,
        'teachers',
        (Json row) => _teacherById(row.integer('id')) ?? Teacher.fromJson(row),
      );
      _subjectFacets = _facet(facets, 'subjects', RefItem.fromJson);
      _error = null;
      _state = LoadState.ready;
    } on ApiException catch (error) {
      _error = error;
      _state = LoadState.failed;
    }
    notifyListeners();
  }

  /// The Offers the backend lists for [filter] (every page); [offers]
  /// itself when there is no filter. The request starts on the first
  /// ask and listeners hear when it lands. Offline (seeded) there is no
  /// backend to ask, so the Offers come back unfiltered.
  OfferMatches offersMatching(OfferFilter filter) {
    final NovaApi? api = _api;
    if (api == null || filter.isEmpty) return (packs: _offers, error: null);
    final Map<String, Object?> query = filter.query;
    final String key = query.toString();
    final List<Pack>? known = _matches[key];
    if (known != null) return (packs: known, error: null);
    final ApiException? failed = _matchErrors[key];
    if (failed != null) return (packs: null, error: failed);
    if (_matchesPending.add(key)) _fetchMatches(api, key, query);
    return (packs: null, error: null);
  }

  Future<void> _fetchMatches(
    NovaApi api,
    String key,
    Map<String, Object?> query,
  ) async {
    final int generation = _generation;
    try {
      final _Pages pages = await _all(api, '/offers', query);
      if (generation != _generation) return;
      _matches[key] = pages.rows.map(Pack.fromJson).toList();
    } on ApiException catch (error) {
      if (generation != _generation) return;
      _matchErrors[key] = error;
    }
    _matchesPending.remove(key);
    notifyListeners();
  }

  /// Course detail with its curriculum. Owned courses read the
  /// Student route (the public one hides non-sold courses).
  Future<Course> course(String slug, {bool owned = false}) async {
    final NovaApi? api = _api;
    if (api == null) {
      return _courses.firstWhere((Course c) => c.slug == slug);
    }
    final Json body =
        await api.get(owned ? '/learning/courses/$slug' : '/courses/$slug');
    return Course.fromJson(body.obj('data') ?? <String, dynamic>{}, owned: owned);
  }

  Future<Pack> offer(String slug) async {
    final NovaApi? api = _api;
    if (api == null) return _offers.firstWhere((Pack p) => p.slug == slug);
    return Pack.fromJson((await api.get('/offers/$slug')).obj('data') ?? <String, dynamic>{});
  }

  Teacher? teacherNamed(String name) {
    for (final Teacher teacher in _teachers) {
      if (teacher.name == name) return teacher;
    }
    return null;
  }

  String? teacherPhoto(String name) => teacherNamed(name)?.photo;

  Teacher? _teacherById(int id) {
    for (final Teacher teacher in _teachers) {
      if (teacher.id == id) return teacher;
    }
    return null;
  }

  /// One facet group of several `facets` objects, each id once, in the
  /// order the backend sends them.
  static List<T> _facet<T>(
    List<Json?> facets,
    String key,
    T Function(Json row) build,
  ) {
    final Set<int> seen = <int>{};
    return <T>[
      for (final Json? group in facets)
        if (group != null)
          for (final Json row in group.list(key))
            if (seen.add(row.integer('id'))) build(row),
    ];
  }

  /// Every page of a paginated public list, with the `facets` of its
  /// first page; the catalogue is small, and Explore filters Courses
  /// locally like the web page does.
  static Future<_Pages> _all(
    NovaApi api,
    String path, [
    Map<String, Object?> filters = const <String, Object?>{},
  ]) async {
    final List<Json> rows = <Json>[];
    Json? facets;
    int page = 1;
    int last = 1;
    do {
      final Json body = await api.get(path, query: <String, Object?>{
        ...filters,
        'per_page': 50,
        'page': page,
      });
      rows.addAll(body.list('data'));
      facets ??= body.obj('facets');
      last = body.obj('meta')?.integer('last_page', 1) ?? 1;
      page++;
    } while (page <= last && page <= 20);
    return (rows: rows, facets: facets);
  }
}
