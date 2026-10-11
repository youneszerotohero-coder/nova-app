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

/// What a catalogue page lists for a [CatalogQuery]: [items] once known,
/// [error] when the request failed, neither while it runs.
typedef CatalogMatches<T> = ({List<T>? items, ApiException? error});

/// The website's catalogue orders (`sort` of `/courses` and `/offers`).
enum CatalogSort {
  recommended('recommended'),
  priceLow('price-low'),
  priceHigh('price-high');

  const CatalogSort(this.code);

  final String code;
}

/// `access` of `/courses`: every Unit, the free ones or the paid ones.
enum CatalogAccess { all, free, paid }

/// The Units (`/courses`) and Offers (`/offers`) pages' search, sort and
/// filters, sent as the website's parameters (`catalog.tsx`). Empty sets
/// mean "any"; [maxPrice] null means any price.
class CatalogQuery {
  const CatalogQuery({
    this.search = '',
    this.sort = CatalogSort.recommended,
    this.levelIds = const <int>{},
    this.trackIds = const <int>{},
    this.subjectIds = const <int>{},
    this.teacherIds = const <int>{},
    this.types = const <String>{},
    this.access = CatalogAccess.all,
    this.maxPrice,
  });

  /// The price slider runs from 0 to 50 000 DA in steps of 500; its top
  /// end means any price.
  static const int priceCeiling = 50000;
  static const int priceStep = 500;

  final String search;
  final CatalogSort sort;
  final Set<int> levelIds;
  final Set<int> trackIds;
  final Set<int> subjectIds;
  final Set<int> teacherIds;

  /// Offer types (`dawra`, `trimestre`…); Offers only.
  final Set<String> types;

  /// Units only.
  final CatalogAccess access;
  final int? maxPrice;

  /// The count on the "Filters" button: search and sort are not filters.
  int get filterCount =>
      levelIds.length +
      trackIds.length +
      subjectIds.length +
      teacherIds.length +
      types.length +
      (maxPrice == null ? 0 : 1) +
      (access == CatalogAccess.all ? 0 : 1);

  /// The plain list the catalogue loads first.
  bool get isDefault => filterCount == 0 && search.trim().isEmpty && sort == CatalogSort.recommended;

  /// No search and no filter; the order stays (the website's reset).
  CatalogQuery cleared() => CatalogQuery(sort: sort);

  /// The request parameters, in a stable order so equal queries share a key.
  Map<String, Object?> params({required bool units}) => <String, Object?>{
        'sort': sort == CatalogSort.recommended ? null : sort.code,
        'search': search.trim().isEmpty ? null : search.trim(),
        'level_ids': levelIds.toList()..sort(),
        'track_ids': trackIds.toList()..sort(),
        'subject_ids': subjectIds.toList()..sort(),
        'teacher_ids': teacherIds.toList()..sort(),
        'types': units ? null : (types.toList()..sort()),
        'access': units && access != CatalogAccess.all ? access.name : null,
        'max_price': maxPrice,
      };

  CatalogQuery copyWith({
    String? search,
    CatalogSort? sort,
    Set<int>? levelIds,
    Set<int>? trackIds,
    Set<int>? subjectIds,
    Set<int>? teacherIds,
    Set<String>? types,
    CatalogAccess? access,
    int? Function()? maxPrice,
  }) =>
      CatalogQuery(
        search: search ?? this.search,
        sort: sort ?? this.sort,
        levelIds: levelIds ?? this.levelIds,
        trackIds: trackIds ?? this.trackIds,
        subjectIds: subjectIds ?? this.subjectIds,
        teacherIds: teacherIds ?? this.teacherIds,
        types: types ?? this.types,
        access: access ?? this.access,
        maxPrice: maxPrice == null ? this.maxPrice : maxPrice(),
      );
}

/// One catalogue's filter options: the `facets` of its first page, which
/// the backend computes on everything listed, whatever the filters.
class CatalogFacets {
  const CatalogFacets({
    this.levels = const <RefItem>[],
    this.tracks = const <RefItem>[],
    this.subjects = const <RefItem>[],
    this.teachers = const <Teacher>[],
    this.free = 0,
    this.paid = 0,
    this.types = const <String>[],
  });

  final List<RefItem> levels;
  final List<RefItem> tracks;
  final List<RefItem> subjects;
  final List<Teacher> teachers;

  /// Units only: how many listed Units are free and paid.
  final int free;
  final int paid;

  /// Offers only: the types of the published Offers.
  final List<String> types;
}

typedef _Pages = ({List<Json> rows, Json? facets, Json? audience});

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
    _unitFacets = CatalogFacets(
      subjects: _subjectFacets,
      teachers: _teacherFacets,
      free: _courses.where((Course c) => c.isFree).length,
      paid: _courses.where((Course c) => !c.isFree).length,
    );
    _offerFacets = CatalogFacets(
      subjects: _subjectFacets,
      teachers: _teacherFacets,
      types: <String>{for (final Pack pack in _offers) if (pack.type.isNotEmpty) pack.type}.toList(),
    );
  }

  final NovaApi? _api;

  LoadState _state = LoadState.idle;
  ApiException? _error;
  List<Course> _courses = const <Course>[];
  List<Pack> _offers = const <Pack>[];
  List<Teacher> _teachers = const <Teacher>[];
  List<Teacher> _teacherFacets = const <Teacher>[];
  List<RefItem> _subjectFacets = const <RefItem>[];
  CatalogFacets _unitFacets = const CatalogFacets();
  CatalogFacets _offerFacets = const CatalogFacets();
  String? _audience;

  /// Backend-filtered lists per request, until the next [load];
  /// [_generation] drops answers to an older catalogue.
  final Map<String, List<Object>> _matches = <String, List<Object>>{};
  final Map<String, ApiException> _matchErrors = <String, ApiException>{};
  final Set<String> _matchesPending = <String>{};
  int _generation = 0;

  LoadState get state => _state;
  ApiException? get error => _error;
  List<Course> get courses => _courses;
  List<Pack> get offers => _offers;
  List<Teacher> get teachers => _teachers;

  /// Teachers and Subjects of both catalogues: the backend facets of
  /// `/courses` and `/offers` (first page, union by id), so the ones
  /// sold only inside Offers are offered too. A Teacher carries the
  /// directory photo when the Teachers list has one.
  List<Teacher> get teacherFacets => _teacherFacets;
  List<RefItem> get subjectFacets => _subjectFacets;

  /// The Units page's filter options (`facets` of `/courses`).
  CatalogFacets get unitFacets => _unitFacets;

  /// The Offers page's filter options (`facets` of `/offers`).
  CatalogFacets get offerFacets => _offerFacets;

  /// The signed-in Student's level and filière the backend narrowed the
  /// lists to (D-083), e.g. "3AS · علوم تجريبية"; null for a visitor.
  String? get audience => _audience;

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
      _teacherFacets = _facet(facets, 'teachers', _facetTeacher);
      _subjectFacets = _facet(facets, 'subjects', RefItem.fromJson);
      _unitFacets = _facetsOf(lists[0].facets);
      _offerFacets = _facetsOf(lists[1].facets);
      _audience = _audienceLabel(lists[0].audience ?? lists[1].audience);
      _error = null;
      _state = LoadState.ready;
    } on ApiException catch (error) {
      _error = error;
      _state = LoadState.failed;
    }
    notifyListeners();
  }

  /// The Units the backend lists for [query]: [courses] itself for the
  /// plain list; otherwise the request starts on the first ask and
  /// listeners hear when it lands. Offline (seeded) there is no backend
  /// to ask, so the list comes back as is.
  CatalogMatches<Course> unitsFor(CatalogQuery query) =>
      _matching('/courses', query.params(units: true), plain: query.isDefault, all: _courses);

  /// The Offers the backend lists for [query], as [unitsFor] does.
  CatalogMatches<Pack> offersFor(CatalogQuery query) =>
      _matching('/offers', query.params(units: false), plain: query.isDefault, all: _offers);

  /// The Offers the backend lists for [filter] (every page); [offers]
  /// itself when there is no filter.
  OfferMatches offersMatching(OfferFilter filter) {
    final CatalogMatches<Pack> matches =
        _matching('/offers', filter.query, plain: filter.isEmpty, all: _offers);
    return (packs: matches.items, error: matches.error);
  }

  CatalogMatches<T> _matching<T extends Object>(
    String path,
    Map<String, Object?> query, {
    required bool plain,
    required List<T> all,
  }) {
    final NovaApi? api = _api;
    if (api == null || plain) return (items: all, error: null);
    final String key = '$path $query';
    final List<Object>? known = _matches[key];
    if (known != null) return (items: known.cast<T>(), error: null);
    final ApiException? failed = _matchErrors[key];
    if (failed != null) return (items: null, error: failed);
    if (_matchesPending.add(key)) _fetchMatches(api, path, key, query);
    return (items: null, error: null);
  }

  Future<void> _fetchMatches(
    NovaApi api,
    String path,
    String key,
    Map<String, Object?> query,
  ) async {
    final int generation = _generation;
    try {
      final _Pages pages = await _all(api, path, query);
      if (generation != _generation) return;
      _matches[key] = path == '/courses'
          ? pages.rows.map((Json j) => Course.fromJson(j)).toList()
          : pages.rows.map(Pack.fromJson).toList();
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

  Teacher _facetTeacher(Json row) => _teacherById(row.integer('id')) ?? Teacher.fromJson(row);

  CatalogFacets _facetsOf(Json? facets) {
    final Json access = facets?.obj('access') ?? <String, dynamic>{};
    final Object? types = facets?['types'];
    return CatalogFacets(
      levels: _facet(<Json?>[facets], 'levels', RefItem.fromJson),
      tracks: _facet(<Json?>[facets], 'tracks', RefItem.fromJson),
      subjects: _facet(<Json?>[facets], 'subjects', RefItem.fromJson),
      teachers: _facet(<Json?>[facets], 'teachers', _facetTeacher),
      free: access.integer('free'),
      paid: access.integer('paid'),
      types: types is List ? types.whereType<String>().toList() : const <String>[],
    );
  }

  /// `audience` as the website writes it: the level's code (or name),
  /// then the filière (`academicProfileLabel`).
  static String? _audienceLabel(Json? audience) {
    if (audience == null) return null;
    final Json? level = audience.obj('level');
    final Json? track = audience.obj('track');
    final String label = <String>[
      if (level != null) level.str('code').isNotEmpty ? level.str('code') : localName(level),
      if (track != null) localName(track),
    ].where((String part) => part.isNotEmpty).join(' · ');
    return label.isEmpty ? null : label;
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

  /// Every page of a paginated public list, with the `facets` and the
  /// `audience` of its first page; the catalogue is small, so the
  /// catalogue pages show every match without paging.
  static Future<_Pages> _all(
    NovaApi api,
    String path, [
    Map<String, Object?> filters = const <String, Object?>{},
  ]) async {
    final List<Json> rows = <Json>[];
    Json? facets;
    Json? audience;
    int page = 1;
    int last = 1;
    do {
      final Json body = await api.get(path, query: <String, Object?>{
        ...filters,
        'per_page': 50,
        'page': page,
      });
      rows.addAll(body.list('data'));
      if (page == 1) {
        facets = body.obj('facets');
        audience = body.obj('audience');
      }
      last = body.obj('meta')?.integer('last_page', 1) ?? 1;
      page++;
    } while (page <= last && page <= 20);
    return (rows: rows, facets: facets, audience: audience);
  }
}
