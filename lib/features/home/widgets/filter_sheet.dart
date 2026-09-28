import 'package:flutter/material.dart';

import '../../../core/i18n/nova_strings.dart';
import '../../../core/state/app_state.dart';
import '../../../core/theme/nova_colors.dart';
import '../../../core/theme/nova_dimens.dart';
import '../../../core/theme/nova_typography.dart';
import '../../../core/utils/format_price.dart';
import '../../../core/widgets/hue_card.dart';
import '../../../core/widgets/monogram_avatar.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../../core/widgets/subject_chip.dart';
import '../course_query.dart';
import '../../../data/catalog_store.dart';
import '../../../data/models.dart';

/// Opens the animated filter sheet for the catalog.
///
/// The sheet slides up with the standard modal motion while its
/// sections stagger in; the Apply button reports the edited query.
/// [packs] answers the packs Explore would list for a query, null
/// while the backend has not answered yet.
Future<void> showNovaFilterSheet(
  BuildContext context, {
  required List<Course> courses,
  required CourseQuery current,
  required List<Pack>? Function(CourseQuery query) packs,
  required ValueChanged<CourseQuery> onApply,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (BuildContext context) => _FilterSheet(
      courses: courses,
      packs: packs,
      initial: current,
      onApply: onApply,
    ),
  );
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.courses,
    required this.packs,
    required this.initial,
    required this.onApply,
  });

  final List<Course> courses;
  final List<Pack>? Function(CourseQuery query) packs;
  final CourseQuery initial;
  final ValueChanged<CourseQuery> onApply;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  late CourseQuery _query = widget.initial;

  late final int _freeCount =
      widget.courses.where((Course c) => c.isFree).length;

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Courses and packs the query would list; null until the backend
  /// has filtered the packs.
  int? get _matchCount {
    final List<Pack>? packs = widget.packs(_query);
    if (packs == null) return null;
    return applyCourseQuery(widget.courses, _query).length + packs.length;
  }

  Set<int> _toggled(Set<int> set, int value) =>
      set.contains(value) ? ({...set}..remove(value)) : {...set, value};

  void _reset() => setState(() => _query = const CourseQuery());

  @override
  Widget build(BuildContext context) {
    final bool dirty = !_query.isDefault;
    final int? matches = _matchCount;
    // The options are the catalogue facets, so Teachers and Subjects
    // sold only inside packs are offered too.
    final CatalogStore catalog = AppScope.of(context).catalog;
    final List<Teacher> teachers = catalog.teacherFacets;
    final List<RefItem> subjects = catalog.subjectFacets;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom + 14,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 10),
          // The chip rails draw unclipped so glows survive; the card
          // edge is where they stop.
          clipBehavior: Clip.antiAlias,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.86,
          ),
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 18),
          decoration: BoxDecoration(
            color: NovaColors.paperCard,
            borderRadius: BorderRadius.circular(NovaDimens.radiusCardLarge),
            boxShadow: NovaDimens.shadowFloating,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: NovaColors.textMuted.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
              _Stagger(
                controller: _controller,
                start: 0,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _Header(dirty: dirty, onReset: _reset),
                ),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(top: 6, bottom: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Stagger(
                        controller: _controller,
                        start: 0.1,
                        child: _SectionTitle(
                          label: context.tr('filter.teachers'),
                          selected: _query.teacherIds.length,
                          onClear: () => setState(
                            () => _query =
                                _query.copyWith(teacherIds: const <int>{}),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _Stagger(
                        controller: _controller,
                        start: 0.18,
                        child: SizedBox(
                          // Portrait (66) + gap (8) + first name; no count line any more.
                          height: 94,
                          child: ListView.separated(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 20),
                            scrollDirection: Axis.horizontal,
                            itemCount: teachers.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 6),
                            itemBuilder: (_, int index) {
                              final Teacher teacher = teachers[index];
                              return _TeacherOption(
                                name: teacher.name,
                                photo: teacher.photo,
                                selected:
                                    _query.teacherIds.contains(teacher.id),
                                onTap: () => setState(
                                  () => _query = _query.copyWith(
                                    teacherIds: _toggled(
                                      _query.teacherIds,
                                      teacher.id,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _Stagger(
                        controller: _controller,
                        start: 0.26,
                        child: _SectionTitle(
                          label: context.tr('filter.subjects'),
                          selected: _query.subjectIds.length,
                          onClear: () => setState(
                            () => _query =
                                _query.copyWith(subjectIds: const <int>{}),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _Stagger(
                        controller: _controller,
                        start: 0.32,
                        child: SizedBox(
                          height: SubjectChip.railHeight,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
                            clipBehavior: Clip.none,
                            scrollDirection: Axis.horizontal,
                            itemCount: subjects.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 8),
                            itemBuilder: (_, int index) {
                              final RefItem subject = subjects[index];
                              return SubjectChip(
                                label: subject.name,
                                selected:
                                    _query.subjectIds.contains(subject.id),
                                onTap: () => setState(
                                  () => _query = _query.copyWith(
                                    subjectIds: _toggled(
                                      _query.subjectIds,
                                      subject.id,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _Stagger(
                        controller: _controller,
                        start: 0.4,
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 20),
                          child: _PriceSlider(
                            value: _query.maxPrice,
                            enabled: !_query.onlyFree,
                            onChanged: (int value) => setState(
                              () =>
                                  _query = _query.copyWith(maxPrice: value),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _Stagger(
                        controller: _controller,
                        start: 0.48,
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 20),
                          child: _FreeToggle(
                            value: _query.onlyFree,
                            freeCount: _freeCount,
                            onChanged: (bool value) => setState(
                              () =>
                                  _query = _query.copyWith(onlyFree: value),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _Stagger(
                controller: _controller,
                start: 0.58,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _ApplyButton(
                    count: matches,
                    onTap: () {
                      Navigator.of(context).pop();
                      widget.onApply(_query);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.dirty, required this.onReset});

  final bool dirty;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const IconTile(
          icon: Icons.tune_rounded,
          hue: NovaHue.sky,
          filled: true,
          size: 38,
        ),
        const SizedBox(width: 12),
        Text(context.tr('filter.title'), style: NovaTypography.textTheme.headlineSmall),
        const Spacer(),
        AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: dirty ? 1 : 0.4,
          child: PressableScale(
            onTap: dirty ? onReset : null,
            pressedScale: 0.94,
            semanticLabel: context.tr('filter.resetAll'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
              decoration: BoxDecoration(
                color: NovaColors.subtleFill,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.refresh_rounded,
                    size: 14,
                    color: NovaColors.textStrong,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    context.tr('filter.reset'),
                    style: NovaTypography.textTheme.labelSmall!
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Section label with a live "Any" / "2 selected" state; tapping the
/// selected pill clears that section only.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.label,
    required this.selected,
    required this.onClear,
  });

  final String label;
  final int selected;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _SectionLabel(label),
          const Spacer(),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (Widget child, Animation<double> animation) =>
                FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: animation, child: child),
            ),
            child: selected == 0
                ? Text(
                    context.tr('filter.any'),
                    key: const ValueKey<String>('any'),
                    style: NovaTypography.muted(
                      NovaTypography.textTheme.labelSmall!,
                    ),
                  )
                : PressableScale(
                    key: const ValueKey<String>('selected'),
                    onTap: onClear,
                    pressedScale: 0.94,
                    semanticLabel: context.trf('filter.clear', <String, String>{'label': label}),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(10, 5, 6, 5),
                      decoration: BoxDecoration(
                        color: NovaHue.sky.surfaceStrong,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            context.trf('filter.selected', <String, String>{'n': '$selected'}),
                            style: NovaTypography.textTheme.labelSmall!
                                .copyWith(
                              color: NovaHue.sky.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.close_rounded,
                            size: 14,
                            color: NovaHue.sky.onSurface,
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w700,
        fontSize: 10.5,
        letterSpacing: 1.6,
        color: NovaColors.textMuted,
      ),
    );
  }
}

/// A teacher as a portrait you tap: a gradient ring and a tick spring
/// in when selected, with the first name underneath.
class _TeacherOption extends StatelessWidget {
  const _TeacherOption({
    required this.name,
    required this.photo,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final String? photo;
  final bool selected;
  final VoidCallback onTap;

  static const double _portrait = 58;

  @override
  Widget build(BuildContext context) {
    final NovaHue hue = NovaHue.of(name);

    return Semantics(
      selected: selected,
      child: PressableScale(
        onTap: onTap,
        pressedScale: 0.92,
        semanticLabel: name,
        child: SizedBox(
          width: 78,
          child: Column(
            children: [
              SizedBox(
                width: _portrait + 8,
                height: _portrait + 8,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.all(2.5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: selected ? hue.gradient : null,
                        color: selected ? null : NovaColors.borderOnLight,
                        boxShadow: selected ? hue.shadow : null,
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: NovaColors.paperCard,
                        ),
                        child: MonogramAvatar(
                          label: name,
                          size: _portrait - 1,
                          showRing: false,
                          photo: photo,
                        ),
                      ),
                    ),
                    PositionedDirectional(
                      end: 0,
                      bottom: 0,
                      child: AnimatedScale(
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOutBack,
                        scale: selected ? 1 : 0,
                        child: Container(
                          width: 22,
                          height: 22,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: hue.solid,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: NovaColors.paperCard,
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            size: 12,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                name.split(' ').first,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NovaTypography.textTheme.titleSmall!.copyWith(
                  fontSize: 12.5,
                  color: selected ? hue.onSurface : NovaColors.textStrong,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Max price, dimmed while "Only free" makes it irrelevant.
class _PriceSlider extends StatelessWidget {
  const _PriceSlider({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: enabled ? 1 : 0.4,
      child: IgnorePointer(
        ignoring: !enabled,
        child: Column(
          children: [
            Row(
              children: [
                _SectionLabel(context.tr('filter.maxPrice')),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: NovaHue.sky.surfaceStrong,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    value >= CourseQuery.maxPriceCeiling
                        ? context.tr('filter.anyPrice')
                        : context.trf('filter.upTo', <String, String>{'price': formatDaPrice(value)}),
                    style: NovaTypography.textTheme.labelSmall!.copyWith(
                      color: NovaHue.sky.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 6,
                activeTrackColor: NovaColors.accent,
                inactiveTrackColor: NovaColors.subtleFill,
                thumbColor: Colors.white,
                overlayColor: NovaColors.accent.withValues(alpha: 0.12),
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 11,
                  elevation: 3,
                ),
                trackShape: const RoundedRectSliderTrackShape(),
              ),
              child: Slider(
                value: value.toDouble(),
                min: CourseQuery.maxPriceFloor.toDouble(),
                max: CourseQuery.maxPriceCeiling.toDouble(),
                divisions: 24,
                onChanged: (double v) => onChanged(v.round()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FreeToggle extends StatelessWidget {
  const _FreeToggle({
    required this.value,
    required this.freeCount,
    required this.onChanged,
  });

  final bool value;
  final int freeCount;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: () => onChanged(!value),
      pressedScale: 0.98,
      child: HueCard(
        hue: NovaHue.mint,
        padding: const EdgeInsetsDirectional.fromSTEB(14, 8, 8, 8),
        radius: NovaDimens.radiusTile,
        child: Row(
          children: [
            IconTile(
              icon: Icons.volunteer_activism_rounded,
              hue: NovaHue.mint,
              size: 38,
              filled: value,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('filter.onlyFree'),
                    style: NovaTypography.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    switch (freeCount) {
                      0 => context.tr('filter.noFree'),
                      1 => context.tr('filter.oneFree'),
                      _ => context.trf('filter.manyFree', <String, String>{'n': '$freeCount'}),
                    },
                    style: NovaTypography.muted(
                      NovaTypography.textTheme.bodySmall!,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              activeThumbColor: Colors.white,
              activeTrackColor: NovaHue.mint.solid,
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: NovaColors.textMuted.withValues(alpha: 0.35),
              trackOutlineColor: const WidgetStatePropertyAll<Color>(
                Colors.transparent,
              ),
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

/// Live count of matching courses and packs; with no match it goes
/// quiet instead of offering to show an empty list. While the backend
/// filters the packs the count is unknown ([count] null) and applying
/// stays possible.
class _ApplyButton extends StatelessWidget {
  const _ApplyButton({required this.count, required this.onTap});

  final int? count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool empty = count == 0;

    return PressableScale(
      onTap: empty ? null : onTap,
      pressedScale: 0.97,
      semanticLabel: context.tr('filter.apply'),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        height: 58,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: empty ? null : NovaColors.accentGradient,
          color: empty ? NovaColors.subtleFill : null,
          borderRadius: BorderRadius.circular(100),
          boxShadow: empty ? null : NovaDimens.shadowAccent,
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: Row(
            key: ValueKey<int?>(count),
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                empty ? Icons.search_off_rounded : Icons.check_rounded,
                size: 20,
                color: empty ? NovaColors.textMuted : Colors.white,
              ),
              const SizedBox(width: 10),
              Text(
                switch (count) {
                  null => context.tr('filter.showResults'),
                  0 => context.tr('filter.noResults'),
                  1 => context.tr('filter.showOne'),
                  _ => context.trf('filter.showMany', <String, String>{'n': '$count'}),
                },
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  height: 1,
                  letterSpacing: -0.2,
                  color: empty ? NovaColors.textMuted : Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fades and lifts a row in as the sheet opens.
class _Stagger extends StatelessWidget {
  const _Stagger({
    required this.controller,
    required this.start,
    required this.child,
  });

  final AnimationController controller;
  final double start;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Animation<double> animation = CurvedAnimation(
      parent: controller,
      curve: Interval(start, (start + 0.42).clamp(0, 1), curve: Curves.easeOutCubic),
    );

    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? child) => Opacity(
        opacity: animation.value,
        child: Transform.translate(
          offset: Offset(0, (1 - animation.value) * 16),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
