import '../../data/catalog_store.dart';
import '../../data/models.dart';

/// Filter state for Explore, edited by the filter sheet and the subject
/// chips. Teachers and Subjects are ids from the catalogue facets;
/// empty sets mean "any". Courses are filtered locally
/// ([applyCourseQuery]), packs by the backend ([offerFilter]).
class CourseQuery {
  const CourseQuery({
    this.maxPrice = maxPriceCeiling,
    this.teacherIds = const <int>{},
    this.subjectIds = const <int>{},
    this.onlyFree = false,
  });

  /// Slider ceiling; at the ceiling every course passes the price
  /// filter, displayed as "Any price".
  static const int maxPriceCeiling = 25000;
  static const int maxPriceFloor = 1000;

  final int maxPrice;
  final Set<int> teacherIds;
  final Set<int> subjectIds;

  /// Free Courses only (D-054: free is an access mode, never a price).
  final bool onlyFree;

  bool get isDefault =>
      maxPrice == maxPriceCeiling &&
      teacherIds.isEmpty &&
      subjectIds.isEmpty &&
      !onlyFree;

  /// What the backend applies to packs: Teacher and Subject (D-056) and
  /// the max price. `GET /offers` has no access filter, so "Only free"
  /// narrows Courses only.
  OfferFilter get offerFilter => OfferFilter(
        teacherIds: teacherIds,
        subjectIds: subjectIds,
        maxPrice: maxPrice < maxPriceCeiling ? maxPrice : null,
      );

  CourseQuery copyWith({
    int? maxPrice,
    Set<int>? teacherIds,
    Set<int>? subjectIds,
    bool? onlyFree,
  }) =>
      CourseQuery(
        maxPrice: maxPrice ?? this.maxPrice,
        teacherIds: teacherIds ?? this.teacherIds,
        subjectIds: subjectIds ?? this.subjectIds,
        onlyFree: onlyFree ?? this.onlyFree,
      );
}

/// Filters [courses] according to [query], keeping the catalog order
/// (backend ordering once wired).
List<Course> applyCourseQuery(List<Course> courses, CourseQuery query) {
  return courses
      .where(
        (Course course) =>
            // D-091: a course sold through Packs only is priced by its
            // cheapest Pack; without one it drops out of a price ceiling.
            (course.isFree ||
                (course.cataloguePrice != null && course.cataloguePrice! <= query.maxPrice) ||
                (course.cataloguePrice == null && query.maxPrice >= CourseQuery.maxPriceCeiling)) &&
            (query.teacherIds.isEmpty ||
                query.teacherIds.contains(course.teacherId)) &&
            (query.subjectIds.isEmpty ||
                query.subjectIds.contains(course.subjectId)) &&
            (!query.onlyFree || course.isFree),
      )
      .toList();
}
