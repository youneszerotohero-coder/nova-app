import 'package:flutter/material.dart';

import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/utils/search_text.dart';
import '../../core/widgets/hero_style.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/nova_image.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../core/widgets/subject_chip.dart';
import '../../data/catalog_store.dart';
import '../../data/models.dart';
import '../detail/teacher_detail_screen.dart';
import '../home/widgets/nova_search_field.dart';
import '../shell/student_top_bar.dart';
import 'catalog_page.dart';

/// The website's `/teachers` page (teachers.tsx): the blue band with the
/// number of teachers, the search, the subject tabs, then two columns of
/// teacher cards opening each teacher's page. Visitors browse it too.
class TeachersScreen extends StatefulWidget {
  const TeachersScreen({super.key});

  @override
  State<TeachersScreen> createState() => _TeachersScreenState();
}

class _TeachersScreenState extends State<TeachersScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  /// Null: every subject.
  String? _subject;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final CatalogStore catalog = AppScope.of(context).catalog;
    final List<Teacher> teachers = catalog.teachers;
    final bool loading = teachers.isEmpty && (catalog.state == LoadState.idle || catalog.state == LoadState.loading);
    final bool failed = teachers.isEmpty && catalog.state == LoadState.failed;
    // The subjects in the order the teachers bring them.
    final List<String> subjects = <String>{
      for (final Teacher teacher in teachers)
        for (final String subject in teacher.subjects)
          if (subject.isNotEmpty) subject,
    }.toList();
    final List<Teacher> visible = teachers
        .where((Teacher t) =>
            (_subject == null || t.subjects.contains(_subject)) && searchMatches('${t.name} ${t.subjects.join(' ')}', _query))
        .toList();
    final double bottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: NovaColors.paperPublic,
      body: RefreshIndicator(
        onRefresh: catalog.load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            const SliverToBoxAdapter(child: StudentTopBar(showBack: true)),
            SliverToBoxAdapter(
              child: CatalogBand(
                eyebrow: context.tr('teachers.eyebrow'),
                title: context.tr('teachers.title'),
                lead: context.tr('teachers.lead'),
                aside: loading || failed ? null : CatalogStat(value: teachers.length, label: context.tr('teachers.count')),
              ),
            ),
            // `.nvToolbar--teachers`: the search, then the subject tabs.
            SliverPadding(
              padding: const EdgeInsets.only(top: 28, bottom: 26),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: NovaSearchField(
                        hint: context.tr('teachers.search'),
                        controller: _search,
                        onChanged: (String text) => setState(() => _query = text),
                      ),
                    ),
                    if (subjects.length > 1) ...[
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            for (final String? subject in <String?>[null, ...subjects]) ...[
                              if (subject != null) const SizedBox(width: 6),
                              SubjectChip(
                                tab: true,
                                label: subject ?? context.tr('teachers.all'),
                                selected: _subject == subject,
                                onTap: () => setState(() => _subject = subject),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 40 + bottom),
              sliver: SliverToBoxAdapter(
                child: failed
                    ? HeroEmpty(
                        icon: Icons.warning_amber_rounded,
                        title: context.tr('teachers.unavailable'),
                        message: context.tr('teachers.errorText'),
                        action: NovaButton(label: context.tr('catalog.retry'), icon: Icons.refresh_rounded, onTap: catalog.load),
                      )
                    : loading
                        ? const _Grid(children: <Widget>[
                            CatalogCardSkeleton(mediaRatio: 4 / 5),
                            CatalogCardSkeleton(mediaRatio: 4 / 5),
                            CatalogCardSkeleton(mediaRatio: 4 / 5),
                            CatalogCardSkeleton(mediaRatio: 4 / 5),
                          ])
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // `.nvResultsCount`.
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Text(
                                  context.trf('teachers.showing', <String, String>{'count': '${visible.length}'}),
                                  style: NovaTypography.textTheme.bodyMedium!.copyWith(fontSize: 15, color: NovaColors.textBody),
                                ),
                              ),
                              if (visible.isEmpty)
                                HeroEmpty(
                                  icon: Icons.search_off_rounded,
                                  title: context.tr('teachers.emptyTitle'),
                                  message: context.tr('teachers.emptyText'),
                                )
                              else
                                _Grid(
                                  children: <Widget>[
                                    for (int i = 0; i < visible.length; i++)
                                      Entrance(
                                        key: ValueKey<int>(visible[i].id),
                                        delay: Duration(milliseconds: 60 * (i < 8 ? i : 8)),
                                        child: _TeacherCard(teacher: visible[i], index: teachers.indexOf(visible[i])),
                                      ),
                                  ],
                                ),
                            ],
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `.nvTeacherGrid` on phones: two columns, 12 apart, the cards of a row
/// as tall as each other.
class _Grid extends StatelessWidget {
  const _Grid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (int i = 0; i < children.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: children[i]),
                const SizedBox(width: 12),
                Expanded(child: i + 1 < children.length ? children[i + 1] : const SizedBox.shrink()),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// `TeacherCard` (nova-ui.tsx): the catalogue card's navy frame with the
/// portrait in the inset panel and its number, then the subjects after a
/// green dot, the name and the round arrow.
class _TeacherCard extends StatelessWidget {
  const _TeacherCard({required this.teacher, required this.index});

  final Teacher teacher;
  final int index;

  @override
  Widget build(BuildContext context) {
    final String subjects = teacher.subjects.where((String s) => s.isNotEmpty).join(' · ');
    final String? photo = teacher.photo;
    final List<String> words = teacher.name.trim().split(RegExp(r'\s+')).where((String w) => w.isNotEmpty).toList();
    final String initials = words.take(2).map((String w) => w.substring(0, 1).toUpperCase()).join();
    final bool dark = NovaColors.current.isDark;

    return PressableScale(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TeacherDetailScreen(teacher: teacher))),
      pressedScale: 0.97,
      semanticLabel: teacher.name,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: NovaColors.ink900,
          borderRadius: BorderRadius.circular(22),
          border: dark ? Border.all(color: const Color(0x14FFFFFF)) : null,
          boxShadow: dark
              ? const [BoxShadow(offset: Offset(0, 18), blurRadius: 40, spreadRadius: -22, color: Color(0xB3000000))]
              : const [BoxShadow(offset: Offset(0, 20), blurRadius: 40, spreadRadius: -24, color: Color(0x8C10276B))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 4 / 5,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const CustomPaint(painter: _PanelGrid()),
                    Center(
                      child: Text(
                        initials,
                        style: const TextStyle(fontFamily: NovaTypography.body, fontWeight: FontWeight.w600, fontSize: 42, color: Color(0xFF2B2E35)),
                      ),
                    ),
                    if (photo != null)
                      Image(
                        image: novaImageProvider(photo, cacheWidth: 360),
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    // `.novaCardTag`: the card's number.
                    PositionedDirectional(
                      top: 12,
                      end: 12,
                      child: Container(
                        height: 28,
                        padding: const EdgeInsets.symmetric(horizontal: 11),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: const [BoxShadow(offset: Offset(0, 8), blurRadius: 18, spreadRadius: -10, color: Color(0x990A0E16))],
                        ),
                        child: Text(
                          (index + 1).toString().padLeft(2, '0'),
                          style: const TextStyle(
                            fontFamily: NovaTypography.display,
                            fontWeight: FontWeight.w800,
                            fontSize: 13.5,
                            height: 1,
                            color: NovaColors.ink,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 12, 6, 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // `.novaCardMeta`: a green dot, then the subjects.
                        Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                color: Color(0xFF3ECF72),
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: Color(0x293ECF72), spreadRadius: 3)],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                subjects.isEmpty ? context.tr('teachers.fallbackRole') : subjects,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: NovaTypography.display,
                                  fontFamilyFallback: NovaTypography.fallback,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13.5,
                                  height: 1.2,
                                  color: NovaColors.textMutedOnDark,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          teacher.name,
                          style: const TextStyle(
                            fontFamily: NovaTypography.display,
                            fontFamilyFallback: NovaTypography.fallback,
                            fontWeight: FontWeight.w700,
                            fontSize: 17,
                            height: 1.2,
                            color: NovaColors.textOnDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  // `.novaCardArrow`.
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: Color(0x1AFFFFFF), shape: BoxShape.circle),
                    child: Transform.flip(
                      flipX: Directionality.of(context) == TextDirection.rtl,
                      child: const Icon(Icons.north_east_rounded, size: 16, color: NovaColors.textOnDark),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `.novaCardMedia`: the light panel with its 44 px grid.
class _PanelGrid extends CustomPainter {
  const _PanelGrid();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFEEF2FB));
    final Paint line = Paint()
      ..color = const Color(0x0F1E1E1E)
      ..strokeWidth = 1;
    for (double x = 43.5; x < size.width; x += 44) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (double y = 43.5; y < size.height; y += 44) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  @override
  bool shouldRepaint(_PanelGrid old) => false;
}
