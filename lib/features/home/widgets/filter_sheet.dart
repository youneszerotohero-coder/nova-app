import 'package:flutter/material.dart';

import '../../../core/i18n/nova_strings.dart';
import '../../../core/state/app_state.dart';
import '../../../core/theme/nova_colors.dart';
import '../../../core/theme/nova_dimens.dart';
import '../../../core/theme/nova_typography.dart';
import '../../../core/utils/format_price.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../../core/widgets/subject_chip.dart';
import '../../../data/catalog_store.dart';
import '../../../data/models.dart';

/// Opens the catalogue's "Filters" bottom sheet (the website's phone
/// `.nvFilters` sheet, pages.css): every change applies at once through
/// [onChanged], as on the website, and the footer button shows the
/// [count] of results for the current choice (null while it loads).
Future<void> showCatalogFilterSheet(
  BuildContext context, {
  required bool units,
  required CatalogQuery query,
  required ValueChanged<CatalogQuery> onChanged,
  required int? Function(CatalogQuery query) count,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    // `.nvSheetBackdrop`: rgba(10, 12, 16, .45).
    barrierColor: const Color(0x730A0C10),
    builder: (BuildContext context) => _FilterSheet(units: units, initial: query, onChanged: onChanged, count: count),
  );
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.units, required this.initial, required this.onChanged, required this.count});

  final bool units;
  final CatalogQuery initial;
  final ValueChanged<CatalogQuery> onChanged;
  final int? Function(CatalogQuery query) count;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late CatalogQuery _query = widget.initial;

  /// The last known count, kept while the next one loads.
  int? _shown;

  void _set(CatalogQuery query) {
    setState(() => _query = query);
    widget.onChanged(query);
  }

  static Set<T> _toggled<T>(Set<T> set, T value) => set.contains(value) ? ({...set}..remove(value)) : {...set, value};

  @override
  Widget build(BuildContext context) {
    final CatalogStore catalog = AppScope.of(context).catalog;
    final CatalogFacets facets = widget.units ? catalog.unitFacets : catalog.offerFacets;
    final int? count = widget.count(_query);
    if (count != null) _shown = count;
    final bool showAccess = widget.units && (_query.access != CatalogAccess.all || (facets.free > 0 && facets.paid > 0));
    final List<_Option> types = <_Option>[
      for (final String type in facets.types)
        (value: type, label: K.containsKey('offer.type_$type') ? context.tr('offer.type_$type') : type),
    ];

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.86),
      decoration: BoxDecoration(
        color: NovaColors.paperCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: const [BoxShadow(offset: Offset(0, -20), blurRadius: 50, color: Color(0x400A0E16))],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 5,
                margin: const EdgeInsets.only(top: 10),
                decoration: BoxDecoration(color: NovaColors.borderOnLight, borderRadius: BorderRadius.circular(999)),
              ),
            ),
            // `.nvFiltersHead`.
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: NovaColors.borderOnLight))),
              child: Row(
                children: [
                  Icon(Icons.tune_rounded, size: 18, color: NovaColors.textStrong),
                  const SizedBox(width: 8),
                  Expanded(child: Text(context.tr('catalog.refine'), style: _labelStyle(17))),
                  if (_query.filterCount > 0)
                    PressableScale(
                      onTap: () => _set(_query.cleared()),
                      semanticLabel: context.tr('catalog.clearAll'),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 44),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        alignment: Alignment.center,
                        child: Text(context.tr('catalog.clearAll'), style: _labelStyle(15, NovaColors.accent)),
                      ),
                    ),
                  const SizedBox(width: 10),
                  PressableScale(
                    onTap: () => Navigator.of(context).pop(),
                    pressedScale: 0.92,
                    semanticLabel: context.tr('catalog.closeFilters'),
                    child: Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      // `--nh-hero`: blue-soft, surface-2 in dark mode.
                      decoration: BoxDecoration(
                        color: NovaColors.current.isDark ? NovaColors.paperRaised : NovaColors.accentMist,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.close_rounded, size: 19, color: NovaColors.textStrong),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 2, 18, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showAccess) _AccessBlock(value: _query.access, onChanged: (CatalogAccess access) => _set(_query.copyWith(access: access))),
                    if (!widget.units && (types.length > 1 || _query.types.isNotEmpty))
                      _FilterGroup(
                        title: context.tr('catalog.offerType'),
                        options: types,
                        selected: _query.types,
                        initiallyOpen: true,
                        onToggle: (Object type) => _set(_query.copyWith(types: _toggled(_query.types, type as String))),
                      ),
                    if (facets.levels.isNotEmpty || _query.levelIds.isNotEmpty)
                      _FilterGroup(
                        title: context.tr('catalog.grade'),
                        options: _options(facets.levels),
                        selected: _query.levelIds,
                        initiallyOpen: true,
                        clearLabel: context.tr('catalog.allLevels'),
                        onClear: () => _set(_query.copyWith(levelIds: const <int>{})),
                        onToggle: (Object id) => _set(_query.copyWith(levelIds: _toggled(_query.levelIds, id as int))),
                      ),
                    if (facets.tracks.isNotEmpty || _query.trackIds.isNotEmpty)
                      _FilterGroup(
                        title: context.tr('catalog.track'),
                        options: _options(facets.tracks),
                        selected: _query.trackIds,
                        onToggle: (Object id) => _set(_query.copyWith(trackIds: _toggled(_query.trackIds, id as int))),
                      ),
                    if (facets.subjects.isNotEmpty || _query.subjectIds.isNotEmpty)
                      _FilterGroup(
                        title: context.tr('catalog.subject'),
                        options: _options(facets.subjects),
                        selected: _query.subjectIds,
                        onToggle: (Object id) => _set(_query.copyWith(subjectIds: _toggled(_query.subjectIds, id as int))),
                      ),
                    if (facets.teachers.isNotEmpty || _query.teacherIds.isNotEmpty)
                      _FilterGroup(
                        title: context.tr('catalog.teacher'),
                        options: <_Option>[for (final Teacher t in facets.teachers) (value: t.id, label: t.name)],
                        selected: _query.teacherIds,
                        initiallyOpen: !widget.units,
                        onToggle: (Object id) => _set(_query.copyWith(teacherIds: _toggled(_query.teacherIds, id as int))),
                      ),
                    _PriceBlock(
                      value: _query.maxPrice,
                      onChanged: (int? price) => _set(_query.copyWith(maxPrice: () => price)),
                    ),
                  ],
                ),
              ),
            ),
            // `.nvFiltersFoot` and `.nvApply`.
            Container(
              padding: EdgeInsets.fromLTRB(18, 12, 18, 12 + MediaQuery.paddingOf(context).bottom),
              decoration: BoxDecoration(
                color: NovaColors.paperCard,
                border: Border(top: BorderSide(color: NovaColors.borderOnLight)),
              ),
              child: PressableScale(
                onTap: () => Navigator.of(context).pop(),
                pressedScale: 0.97,
                child: Container(
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: NovaColors.accent,
                    borderRadius: BorderRadius.circular(NovaDimens.radiusControl),
                  ),
                  child: Text(
                    context.trf('catalog.showResults', <String, String>{'count': _shown == null ? '…' : '$_shown'}),
                    style: _labelStyle(17, Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static List<_Option> _options(List<RefItem> items) => <_Option>[for (final RefItem item in items) (value: item.id, label: item.name)];
}

typedef _Option = ({Object value, String label});

TextStyle _labelStyle(double size, [Color? color]) => TextStyle(
      fontFamily: NovaTypography.display,
      fontFamilyFallback: NovaTypography.fallback,
      fontWeight: FontWeight.w800,
      fontSize: size,
      height: 1.25,
      color: color ?? NovaColors.textStrong,
    );

/// A block of the sheet, with the line under it (`.nvFilterBlock`).
BoxDecoration get _blockLine => BoxDecoration(border: Border(bottom: BorderSide(color: NovaColors.borderOnLight)));

/// `catalog.access`: the segmented All / Free / Paid choice (`.nvSegments`).
class _AccessBlock extends StatelessWidget {
  const _AccessBlock({required this.value, required this.onChanged});

  final CatalogAccess value;
  final ValueChanged<CatalogAccess> onChanged;

  @override
  Widget build(BuildContext context) {
    final Map<CatalogAccess, String> labels = <CatalogAccess, String>{
      CatalogAccess.all: context.tr('catalog.accessAll'),
      CatalogAccess.free: context.tr('catalog.accessFree'),
      CatalogAccess.paid: context.tr('catalog.accessPaid'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: _blockLine,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.tr('catalog.access'), style: _labelStyle(16)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: NovaColors.accentMist, borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: [
                for (final MapEntry<CatalogAccess, String> option in labels.entries) ...[
                  if (option.key != CatalogAccess.all) const SizedBox(width: 3),
                  Expanded(
                    child: Semantics(
                      selected: option.key == value,
                      child: PressableScale(
                        onTap: () => onChanged(option.key),
                        pressedScale: 0.97,
                        semanticLabel: option.value,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 240),
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: option.key == value ? NovaColors.accent : Colors.transparent,
                            borderRadius: BorderRadius.circular(11),
                            boxShadow: option.key == value
                                ? const [BoxShadow(offset: Offset(0, 8), blurRadius: 16, spreadRadius: -10, color: Color(0xCC1F54D6))]
                                : null,
                          ),
                          child: Text(
                            option.value,
                            style: _labelStyle(15, option.key == value ? Colors.white : NovaColors.textBody).copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A facet that opens and closes (`FilterGroup`, `.nvFilterGroup`): its
/// title with the yellow count of chosen options, then the chips.
class _FilterGroup extends StatefulWidget {
  const _FilterGroup({
    required this.title,
    required this.options,
    required this.selected,
    required this.onToggle,
    this.initiallyOpen = false,
    this.clearLabel,
    this.onClear,
  });

  final String title;
  final List<_Option> options;
  final Set<Object> selected;
  final ValueChanged<Object> onToggle;
  final bool initiallyOpen;

  /// An "All levels" chip first, chosen while nothing is.
  final String? clearLabel;
  final VoidCallback? onClear;

  @override
  State<_FilterGroup> createState() => _FilterGroupState();
}

class _FilterGroupState extends State<_FilterGroup> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final int chosen = widget.selected.length;
    return Container(
      decoration: _blockLine,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            expanded: _open,
            child: PressableScale(
              onTap: () => setState(() => _open = !_open),
              pressedScale: 0.99,
              semanticLabel: widget.title,
              child: Container(
                constraints: const BoxConstraints(minHeight: 54),
                padding: const EdgeInsets.symmetric(vertical: 15),
                color: Colors.transparent,
                child: Row(
                  children: [
                    Text(widget.title, style: _labelStyle(15)),
                    if (chosen > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        constraints: const BoxConstraints(minWidth: 22),
                        height: 22,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: NovaColors.yellow, borderRadius: BorderRadius.circular(999)),
                        child: Text('$chosen', style: _labelStyle(12, NovaColors.yellowInk).copyWith(height: 1)),
                      ),
                    ],
                    const Spacer(),
                    AnimatedRotation(
                      turns: _open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOutCubic,
                      child: Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: NovaColors.textMuted),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            alignment: AlignmentDirectional.topStart,
            child: !_open
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (widget.onClear != null)
                          SubjectChip(label: widget.clearLabel ?? '', selected: chosen == 0, check: false, onTap: widget.onClear!),
                        for (final _Option option in widget.options)
                          SubjectChip(
                            label: option.label,
                            selected: widget.selected.contains(option.value),
                            onTap: () => widget.onToggle(option.value),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// `catalog.max_price`: 0 to 50 000 DA in steps of 500; the top end is
/// "Any price" (`.nvPrice`). The list follows when the thumb is let go.
class _PriceBlock extends StatefulWidget {
  const _PriceBlock({required this.value, required this.onChanged});

  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  State<_PriceBlock> createState() => _PriceBlockState();
}

class _PriceBlockState extends State<_PriceBlock> {
  /// The thumb while it is dragged.
  int? _dragging;

  static int? _price(double v) => v.round() >= CatalogQuery.priceCeiling ? null : v.round();

  @override
  Widget build(BuildContext context) {
    final int price = _dragging ?? widget.value ?? CatalogQuery.priceCeiling;
    final TextStyle scale = TextStyle(
      fontFamily: NovaTypography.body,
      fontFamilyFallback: NovaTypography.fallback,
      fontSize: 13,
      height: 1.3,
      color: NovaColors.textMuted,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(context.tr('catalog.maxPrice'), style: _labelStyle(16))),
              Text(
                price >= CatalogQuery.priceCeiling ? context.tr('catalog.anyPrice') : formatDaPrice(price),
                style: scale.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 5,
              activeTrackColor: NovaColors.accent,
              inactiveTrackColor: NovaColors.lineStrong,
              thumbColor: NovaColors.accent,
              overlayColor: NovaColors.accent.withValues(alpha: 0.12),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9, elevation: 0, pressedElevation: 0),
              trackShape: const RoundedRectSliderTrackShape(),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
            ),
            child: Slider(
              value: price.toDouble(),
              max: CatalogQuery.priceCeiling.toDouble(),
              divisions: CatalogQuery.priceCeiling ~/ CatalogQuery.priceStep,
              semanticFormatterCallback: (double v) => formatDaPrice(v.round()),
              onChanged: (double v) => setState(() => _dragging = v.round()),
              onChangeEnd: (double v) {
                setState(() => _dragging = null);
                widget.onChanged(_price(v));
              },
            ),
          ),
          Row(
            children: [
              Text(context.tr('catalog.priceFree'), style: scale),
              const Spacer(),
              Text(formatDaPrice(CatalogQuery.priceCeiling), style: scale),
            ],
          ),
        ],
      ),
    );
  }
}
