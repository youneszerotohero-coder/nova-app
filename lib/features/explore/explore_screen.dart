import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/i18n/labels.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_dimens.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/utils/format_price.dart';
import '../../core/utils/search_text.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/nova_course_card.dart';
import '../../core/widgets/nova_page_header.dart';
import '../../core/widgets/nova_scene_image.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../core/widgets/section_header.dart';
import '../../core/widgets/subject_chip.dart';
import '../detail/course_detail_screen.dart';
import '../detail/pack_card.dart';
import '../detail/teacher_detail_screen.dart';
import '../home/course_query.dart';
import '../../data/catalog_store.dart';
import '../../data/models.dart';
import '../../core/state/app_state.dart';
import '../home/widgets/filter_sheet.dart';
import '../home/widgets/nova_search_field.dart';
import 'search_suggestions.dart';

/// Explore tab: search over Courses, Offers (packs) and the teacher
/// directory — the mobile port of the catalog pages. Courses show as
/// one tall poster card per row, in the web catalog's card style.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  String _query = '';
  CourseQuery _courseQuery = const CourseQuery();

  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final OverlayPortalController _dropdown = OverlayPortalController();
  final LayerLink _searchLink = LayerLink();
  final GlobalKey _searchKey = GlobalKey();

  static const int _maxPackSuggestions = 4;
  static const int _maxCourseSuggestions = 6;

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(_syncDropdown);
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    _syncDropdown();
  }

  /// The dropdown shows while the Student types into the focused field.
  void _syncDropdown() {
    final bool show = _searchFocus.hasFocus && _query.trim().isNotEmpty;
    if (show && !_dropdown.isShowing) _dropdown.show();
    if (!show && _dropdown.isShowing) _dropdown.hide();
  }

  /// A suggestion opens its page directly; the list keeps the search.
  void _openSuggestion(Widget page) {
    _searchFocus.unfocus();
    _dropdown.hide();
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  /// Items whose [label] starts with the query come first.
  List<T> _ranked<T>(Iterable<T> items, String Function(T item) label, int max) {
    final String q = searchKey(_query).trim();
    final List<T> leading = <T>[];
    final List<T> rest = <T>[];
    for (final T item in items) {
      (searchKey(label(item)).startsWith(q) ? leading : rest).add(item);
    }
    return <T>[...leading, ...rest].take(max).toList();
  }

  Widget _buildDropdown(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);
    final RenderBox? field =
        _searchKey.currentContext?.findRenderObject() as RenderBox?;
    final double fieldBottom = field == null || !field.hasSize
        ? media.padding.top + 160
        : field.localToGlobal(Offset(0, field.size.height)).dy;
    // Room between the field and the keyboard (or the screen bottom).
    final double room =
        media.size.height - media.viewInsets.bottom - fieldBottom - 24;

    return Positioned(
      top: 0,
      left: 0,
      width: field != null && field.hasSize
          ? field.size.width
          : media.size.width - 40,
      child: CompositedTransformFollower(
        link: _searchLink,
        showWhenUnlinked: false,
        targetAnchor: Alignment.bottomLeft,
        offset: const Offset(0, 8),
        child: TextFieldTapRegion(
          child: SearchSuggestions(
            packs: _ranked(
              _searchPacks(AppScope.of(context).catalog.offers) ??
                  const <Pack>[],
              (Pack p) => p.name,
              _maxPackSuggestions,
            ),
            courses: _ranked(
              _searchMatches,
              (Course c) => c.title,
              _maxCourseSuggestions,
            ),
            maxHeight: room.clamp(140, 440),
            onPack: (Pack pack) =>
                _openSuggestion(CourseDetailScreen.pack(pack: pack)),
            onCourse: (Course course) =>
                _openSuggestion(CourseDetailScreen(course: course)),
          ),
        ),
      ),
    );
  }

  void _openFilters() {
    final CatalogStore catalog = AppScope.of(context).catalog;
    showNovaFilterSheet(
      context,
      courses: _searchMatches,
      current: _courseQuery,
      packs: (CourseQuery query) =>
          _searchPacks(catalog.offersMatching(query.offerFilter).packs),
      onApply: (CourseQuery query) => setState(() => _courseQuery = query),
    );
  }

  /// Packs matching the search text by name or teacher; null (not
  /// filtered yet) stays null.
  List<Pack>? _searchPacks(List<Pack>? packs) {
    return packs
        ?.where(
          (Pack p) =>
              searchMatches(p.name, _query) ||
              p.teachers.any((String t) => searchMatches(t, _query)),
        )
        .toList();
  }

  /// Courses matching the search text, before the filters apply.
  List<Course> get _searchMatches {
    return AppScope.of(context)
        .courses
        .where(
          (Course c) =>
              searchMatches(c.title, _query) ||
              searchMatches(c.teacher, _query) ||
              searchMatches(c.subject, _query),
        )
        .toList();
  }

  List<Course> get _results => applyCourseQuery(_searchMatches, _courseQuery);

  /// The rail and the filter sheet share one subject selection: "All"
  /// (null) clears it, any other chip toggles that subject.
  void _toggleSubject(int? subjectId) {
    final Set<int> subjects = subjectId == null
        ? const <int>{}
        : _courseQuery.subjectIds.contains(subjectId)
            ? ({..._courseQuery.subjectIds}..remove(subjectId))
            : {..._courseQuery.subjectIds, subjectId};
    setState(() => _courseQuery = _courseQuery.copyWith(subjectIds: subjects));
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = AppScope.of(context);
    final List<Course> results = _results;
    // Packs are filtered by the backend (D-056).
    final OfferMatches packs =
        app.catalog.offersMatching(_courseQuery.offerFilter);

    return RefreshIndicator(
      onRefresh: app.catalog.load,
      child: ListView(
      padding: const EdgeInsets.only(bottom: 130),
      // Scrolling the results closes the keyboard and the dropdown.
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        NovaPageHeader(
          title: context.tr('explore.title'),
          kicker: context.trf('explore.kicker', {
            'c': app.catalog.courses.length.toString(),
            'p': app.catalog.offers.length.toString(),
          }),
          watermark: Icons.travel_explore_rounded,
          bottom: OverlayPortal(
            controller: _dropdown,
            overlayChildBuilder: _buildDropdown,
            child: CompositedTransformTarget(
              key: _searchKey,
              link: _searchLink,
              child: NovaSearchField(
                hint: context.tr('explore.searchHint'),
                controller: _search,
                focusNode: _searchFocus,
                margin: EdgeInsets.zero,
                filtersActive: !_courseQuery.isDefault,
                onFilterTap: _openFilters,
                onChanged: _onQueryChanged,
                onSubmitted: (_) => _searchFocus.unfocus(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        _SubjectChips(
          subjects: app.catalog.subjectFacets,
          selected: _courseQuery.subjectIds,
          onSelect: _toggleSubject,
        ),
        const SizedBox(height: 8),
        _CountedHeader(
          title: context.tr('seg.courses'),
          count: results.length,
        ),
        const SizedBox(height: 12),
        if (results.isEmpty)
          EmptyState(
            icon: Icons.search_off_rounded,
            title: context.tr('explore.noMatchTitle'),
            message: context.tr('explore.noMatchMsg'),
          )
        else
          // One poster per row, tall enough for the photo to carry the
          // course — the card itself only adds the title and the price.
          ...stagger(
            [
              for (final Course course in results)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: NovaCourseCard(
                    aspectRatio: 1,
                    heroTag: 'cover-${course.title}',
                    title: course.title,
                    scene: course.scene,
                    image: course.image,
                    icon: course.icon,
                    // Free Courses are joined, never sold (D-054).
                    price: course.isFree || course.packOnly ? null : course.price,
                    compareAtPrice: course.compareAtPrice,
                    actionLabel: course.owned
                        ? context.tr('common.open')
                        : course.isFree
                            ? context.tr('common.free')
                            : course.packOnly
                                ? packPriceText(context, course)
                                : null,
                    badges: [
                      CardBadge(course.subject),
                      if (course.owned)
                        CardBadge(
                          context.tr('common.owned'),
                          icon: Icons.check_rounded,
                          tone: NovaColors.onlineGreen,
                        )
                      else if (course.discountPercent > 0)
                        CardBadge(
                          formatDiscount(course.discountPercent),
                          tone: NovaColors.heartRed,
                        ),
                    ],
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => CourseDetailScreen(course: course),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        const SizedBox(height: NovaDimens.sectionGap),
        SectionHeader(title: context.tr('seg.packs')),
        _PacksSegment(
          packs: _searchPacks(packs.packs),
          error: packs.error,
          onRetry: app.catalog.load,
        ),
        const SizedBox(height: NovaDimens.sectionGap),
        SectionHeader(title: context.tr('seg.teachers')),
        _TeachersSegment(query: _query),
      ],
      ),
    );
  }
}

/// Section title with the live result count beside it.
class _CountedHeader extends StatelessWidget {
  const _CountedHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Text(title, style: NovaTypography.textTheme.headlineSmall),
          const SizedBox(width: 10),
          AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: NovaHue.sky.surfaceStrong,
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text(
              context.trf('explore.found', {'n': count.toString()}),
              style: NovaTypography.textTheme.labelSmall!.copyWith(
                color: NovaHue.sky.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubjectChips extends StatelessWidget {
  const _SubjectChips({
    required this.subjects,
    required this.selected,
    required this.onSelect,
  });

  /// The catalogue's Subject facets, in backend order.
  final List<RefItem> subjects;
  final Set<int> selected;
  final ValueChanged<int?> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: SubjectChip.railHeight,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
        clipBehavior: Clip.none,
        scrollDirection: Axis.horizontal,
        itemCount: subjects.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, int index) {
          final RefItem? chip = index == 0 ? null : subjects[index - 1];

          return SubjectChip(
            label: chip?.name ?? context.tr('common.all'),
            icon: chip == null ? Icons.apps_rounded : null,
            selected:
                chip == null ? selected.isEmpty : selected.contains(chip.id),
            onTap: () => onSelect(chip?.id),
          );
        },
      ),
    );
  }
}

class _PacksSegment extends StatelessWidget {
  const _PacksSegment({
    required this.packs,
    required this.error,
    required this.onRetry,
  });

  /// Packs to list; null while the backend filters them.
  final List<Pack>? packs;
  final ApiException? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ApiException? failure = error;
    if (failure != null) {
      return EmptyState(
        icon: Icons.cloud_off_rounded,
        hue: NovaHue.lilac,
        title: context.tr('seg.packs'),
        message: apiErrorText(context, failure),
        actionLabel: context.tr('common.retry'),
        onAction: onRetry,
      );
    }

    final List<Pack>? packs = this.packs;
    if (packs == null) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
      );
    }

    if (packs.isEmpty) {
      return EmptyState(
        icon: Icons.inventory_2_rounded,
        hue: NovaHue.lilac,
        title: context.tr('explore.noPackTitle'),
        message: context.tr('explore.noPackMsg'),
      );
    }

    return Column(
      children: stagger(
        packs
            .map(
              (Pack pack) => Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                child: PackCard(pack: pack),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _TeachersSegment extends StatelessWidget {
  const _TeachersSegment({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final List<Teacher> teachers = AppScope.of(context).catalog.teachers
        .where(
          (Teacher t) =>
              searchMatches(t.name, query) ||
              t.subjects.any((String s) => searchMatches(s, query)),
        )
        .toList();

    if (teachers.isEmpty) {
      return EmptyState(
        icon: Icons.person_off_rounded,
        hue: NovaHue.rose,
        title: context.tr('explore.noTeacherTitle'),
        message: context.tr('explore.noTeacherMsg'),
      );
    }

    return Column(
      children: stagger(
        teachers
            .map(
              (Teacher teacher) => Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: TeacherRowCard(teacher: teacher),
              ),
            )
            .toList(),
      ),
    );
  }
}

/// Teacher directory row.
class TeacherRowCard extends StatelessWidget {
  const TeacherRowCard({super.key, required this.teacher});

  final Teacher teacher;

  @override
  Widget build(BuildContext context) {
    final NovaHue hue = NovaHue.of(teacher.subject);

    return PressableScale(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TeacherDetailScreen(teacher: teacher),
        ),
      ),
      semanticLabel: 'Open teacher ${teacher.name}',
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: NovaColors.paperCard,
          borderRadius: BorderRadius.circular(NovaDimens.radiusTile),
          border: Border.all(color: NovaColors.borderOnLight),
          boxShadow: NovaDimens.shadowSoft,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hue.surface,
                border: Border.all(
                  color: hue.solid.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: ClipOval(
                child: SizedBox(
                  width: 50,
                  height: 50,
                  child: NovaSceneImage(
                    scene: teacher.scene,
                    image: teacher.photo,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    teacher.name,
                    style: NovaTypography.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    context.trf(
                      'explore.assignedSubjects',
                      {'n': teacher.subjects.length.toString()},
                    ),
                    style: NovaTypography.muted(
                      NovaTypography.textTheme.bodySmall!,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: hue.surfaceStrong,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.arrow_outward_rounded,
                size: 16,
                color: hue.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
