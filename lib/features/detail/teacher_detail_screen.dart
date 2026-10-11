import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_dimens.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/widgets/hero_style.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/nova_image.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../data/catalog_store.dart';
import '../../data/models.dart';
import '../catalog/teachers_screen.dart';
import '../home/widgets/nova_product_card.dart';
import '../shell/student_top_bar.dart';
import 'course_detail_screen.dart';

/// The website's teacher page (`/teachers/:id`, `detail.tsx`, D-134): the
/// band with the back link, the photo in its tilted white frame, the
/// subjects, the name, the bio, the figures (Offers / Units / subjects) and
/// the two buttons; then the Teacher's Offers first, then their Units.
/// Teacher entities stay read-only per the conception.
class TeacherDetailScreen extends StatefulWidget {
  const TeacherDetailScreen({super.key, required this.teacher});

  final Teacher teacher;

  @override
  State<TeacherDetailScreen> createState() => _TeacherDetailScreenState();
}

class _TeacherDetailScreenState extends State<TeacherDetailScreen> {
  final GlobalKey _offersKey = GlobalKey();
  final GlobalKey _unitsKey = GlobalKey();

  Teacher get teacher => widget.teacher;

  void _scrollTo(GlobalKey key) {
    final BuildContext? target = key.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(target, duration: const Duration(milliseconds: 500), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = AppScope.of(context);
    final List<Course> courses = app.courses.where((Course c) => c.teacherId == teacher.id).toList();
    // The backend decides which Offers carry this Teacher (D-062).
    final OfferMatches matches = app.catalog.offersMatching(OfferFilter(teacherIds: <int>{teacher.id}));
    final List<Pack>? offers = matches.packs;
    final bool nothingPublished = offers != null && offers.isEmpty && courses.isEmpty;

    return Scaffold(
      backgroundColor: NovaColors.paperPublic,
      body: ListView(
        padding: EdgeInsets.only(bottom: 40 + MediaQuery.paddingOf(context).bottom),
        children: [
          const StudentTopBar(showBack: true),
          _band(context, offers: offers, units: courses.length, nothingPublished: nothingPublished),
          const SizedBox(height: 36),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ..._offerSection(context, matches, app.catalog),
                if (courses.isNotEmpty) ...[
                  if (offers != null && offers.isNotEmpty) const SizedBox(height: 48),
                  _SectionHeader(
                    key: _unitsKey,
                    title: context.trf('teacher.coursesBy', <String, String>{'name': teacher.name}),
                    count: courses.length,
                  ),
                  ...stagger(<Widget>[
                    for (final Course course in courses)
                      Padding(padding: const EdgeInsets.only(bottom: 16), child: TeacherCourseRow(course: course)),
                  ]),
                ],
                if (nothingPublished)
                  HeroEmpty(
                    icon: Icons.menu_book_rounded,
                    title: context.tr('teacher.emptyTitle'),
                    message: context.tr('teacher.emptyText'),
                    orbit: false,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _band(BuildContext context, {required List<Pack>? offers, required int units, required bool nothingPublished}) {
    final List<String> subjects = teacher.subjects.isNotEmpty
        ? teacher.subjects
        : (teacher.subject.isEmpty ? const <String>[] : <String>[teacher.subject]);
    final TextStyle label = _baloo(15, NovaColors.yellow);
    final TextStyle value = _baloo(27, Colors.white, height: 1);
    Widget stat(String name, String figure, {bool first = false}) => Expanded(
          child: Container(
            padding: EdgeInsetsDirectional.only(top: 12, start: first ? 0 : 18),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0x3DFFFFFF)))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: label),
                const SizedBox(height: 6),
                Text(figure, style: value),
              ],
            ),
          ),
        );
    return HeroBand(
      radius: const BorderRadius.vertical(bottom: Radius.circular(26)),
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: PressableScale(
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TeachersScreen())),
              semanticLabel: context.tr('detail.allTeachers'),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.arrow_back_rounded, size: 16, color: Color(0xE0FFFFFF)),
                    const SizedBox(width: 8),
                    Text(context.tr('detail.allTeachers'), style: _baloo(16, const Color(0xE0FFFFFF))),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Center(child: _PhotoFrame(teacher: teacher)),
          const SizedBox(height: 28),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Entrance(child: _SubjectsPill(label: subjects.isEmpty ? context.tr('teacher.fallbackRole') : subjects.join(' · '))),
          ),
          const SizedBox(height: 16),
          Entrance(
            delay: const Duration(milliseconds: 60),
            child: HeroTitle(teacher.name, size: 40, maxLines: 3),
          ),
          if (teacher.bio.isNotEmpty) ...[
            const SizedBox(height: 16),
            Entrance(
              delay: const Duration(milliseconds: 120),
              child: Text(
                teacher.bio,
                style: const TextStyle(
                  fontFamily: NovaTypography.body,
                  fontFamilyFallback: NovaTypography.fallback,
                  fontSize: 16,
                  height: 1.7,
                  color: Color(0xD6FFFFFF),
                ),
              ),
            ),
          ],
          const SizedBox(height: 30),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              stat(context.tr('teacher.statOffers'), offers == null ? '—' : '${offers.length}', first: true),
              stat(context.tr('detail.statUnits'), '$units'),
              stat(context.tr(subjects.length == 1 ? 'teacher.statSubject' : 'teacher.statSubjects'), '${subjects.length}'),
            ],
          ),
          if (!nothingPublished) ...[
            const SizedBox(height: 32),
            if (offers == null || offers.isNotEmpty)
              _ProfileButton(label: context.tr('teacher.seeOffers'), onTap: () => _scrollTo(_offersKey)),
            if ((offers == null || offers.isNotEmpty) && units > 0) const SizedBox(height: 12),
            if (units > 0) _ProfileButton(label: context.tr('teacher.seeUnits'), ghost: true, onTap: () => _scrollTo(_unitsKey)),
          ],
        ],
      ),
    );
  }

  /// The Teacher's Offers: a spinner while the backend filters, a retry
  /// on failure, nothing when they are in no Offer.
  List<Widget> _offerSection(BuildContext context, OfferMatches matches, CatalogStore catalog) {
    final ApiException? error = matches.error;
    final List<Pack>? found = matches.packs;
    if (error != null) {
      return <Widget>[
        EmptyState(
          icon: Icons.cloud_off_rounded,
          hue: NovaHue.rose,
          title: context.tr('seg.packs'),
          message: apiErrorText(context, error),
          actionLabel: context.tr('common.retry'),
          onAction: catalog.load,
        ),
        const SizedBox(height: 24),
      ];
    }
    if (found == null) {
      return const <Widget>[
        Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
        ),
      ];
    }
    if (found.isEmpty) return const <Widget>[];
    return <Widget>[
      _SectionHeader(
        key: _offersKey,
        title: context.trf('teacher.packsBy', <String, String>{'name': teacher.name}),
        count: found.length,
      ),
      ...stagger(<Widget>[
        for (final Pack pack in found)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: NovaProductCard.offer(
              context,
              pack,
              width: double.infinity,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => CourseDetailScreen.pack(pack: pack)),
              ),
            ),
          ),
      ]),
    ];
  }
}

TextStyle _baloo(double size, Color color, {double height = 1.3}) => TextStyle(
      fontFamily: NovaTypography.display,
      fontFamilyFallback: NovaTypography.fallback,
      fontWeight: FontWeight.w800,
      fontSize: size,
      height: height,
      color: color,
    );

/// `.nvProfilePhoto`: the photo (or the initials) on the `#EEF2FB` grid
/// panel, in a white frame turned −2°.
class _PhotoFrame extends StatelessWidget {
  const _PhotoFrame({required this.teacher});

  final Teacher teacher;

  @override
  Widget build(BuildContext context) {
    final String initials = teacher.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((String w) => w.isNotEmpty)
        .take(2)
        .map((String w) => w.substring(0, 1).toUpperCase())
        .join();
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) => Transform.rotate(
        angle: -2 * math.pi / 180,
        child: Container(
          width: math.min(MediaQuery.sizeOf(context).width * 0.78, math.min(box.maxWidth, 360)),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                offset: const Offset(0, 40),
                blurRadius: 70,
                spreadRadius: -36,
                color: NovaColors.current.isDark ? const Color(0xCC000000) : const Color(0xB3061450),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: AspectRatio(
              aspectRatio: 4 / 5,
              child: CustomPaint(
                painter: const _PanelGrid(),
                child: teacher.photo == null
                    ? Center(
                        child: Text(
                          initials,
                          style: const TextStyle(fontFamily: NovaTypography.body, fontSize: 48, fontWeight: FontWeight.w600, color: Color(0xFF2B2E35)),
                        ),
                      )
                    : Image(
                        image: novaImageProvider(teacher.photo!, cacheWidth: 720),
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        semanticLabel: teacher.name,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The `#EEF2FB` panel and its 44 px grid behind a photo.
class _PanelGrid extends CustomPainter {
  const _PanelGrid();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFEEF2FB));
    final Paint line = Paint()..color = const Color(0x0F1E1E1E);
    for (double x = 43; x < size.width; x += 44) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 1, size.height), line);
    }
    for (double y = 43; y < size.height; y += 44) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), line);
    }
  }

  @override
  bool shouldRepaint(_PanelGrid old) => false;
}

/// `.nhPill` on the band: white, a yellow dot, the subjects.
class _SubjectsPill extends StatelessWidget {
  const _SubjectsPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 36),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(13), boxShadow: NovaDimens.shadowSticker),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 9, height: 9, decoration: const BoxDecoration(color: NovaColors.yellow, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Flexible(child: Text(label, style: _baloo(15, NovaColors.ink, height: 1.2))),
        ],
      ),
    );
  }
}

/// `NhButton` on the band: the ink button (it flips in dark mode) or the
/// white ghost, 58 high, the label at the start and the chip at the end.
class _ProfileButton extends StatelessWidget {
  const _ProfileButton({required this.label, required this.onTap, this.ghost = false});

  final String label;
  final VoidCallback onTap;
  final bool ghost;

  @override
  Widget build(BuildContext context) {
    final Color bg = ghost ? const Color(0x1AFFFFFF) : NovaColors.textStrong;
    final Color ink = ghost ? Colors.white : NovaColors.paperCard;
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.97,
      semanticLabel: label,
      child: Container(
        height: 58,
        padding: const EdgeInsetsDirectional.only(start: 24, end: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(NovaDimens.radiusControl),
          border: Border.all(color: ghost ? const Color(0x57FFFFFF) : Colors.transparent),
        ),
        child: Row(
          children: [
            Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: _baloo(16, ink, height: 1.2))),
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: ghost ? Colors.white : NovaColors.skyStrong,
                borderRadius: BorderRadius.circular(12),
              ),
              // `ArrowUpRight`, mirrored in Arabic.
              child: Icon(
                Directionality.of(context) == TextDirection.rtl ? Icons.north_west_rounded : Icons.north_east_rounded,
                size: 18,
                color: ghost ? NovaColors.accent : const Color(0xFF0B1A2A),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `.nvProfileSection header`: the title and its count pill over a hairline.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({super.key, required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 22),
      padding: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: NovaColors.borderOnLight))),
      child: Row(
        children: [
          Flexible(
            child: Text(
              title,
              style: TextStyle(
                fontFamily: NovaTypography.body,
                fontFamilyFallback: NovaTypography.fallback,
                fontWeight: FontWeight.w600,
                fontSize: 24,
                height: 1.3,
                color: NovaColors.textStrong,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Container(
            constraints: const BoxConstraints(minWidth: 34),
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: NovaColors.textStrong, borderRadius: BorderRadius.circular(100)),
            child: Text(
              '$count',
              style: TextStyle(fontFamily: NovaTypography.body, fontWeight: FontWeight.w600, fontSize: 13, color: NovaColors.paperPublic),
            ),
          ),
        ],
      ),
    );
  }
}

/// One Unit on a teacher's page: the catalogue card, full width.
class TeacherCourseRow extends StatelessWidget {
  const TeacherCourseRow({super.key, required this.course});

  final Course course;

  @override
  Widget build(BuildContext context) {
    return NovaProductCard.unit(
      context,
      course,
      width: double.infinity,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => CourseDetailScreen(course: course)),
      ),
    );
  }
}
