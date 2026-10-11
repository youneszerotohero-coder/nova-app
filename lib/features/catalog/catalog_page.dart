import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_dimens.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/widgets/hero_style.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../data/catalog_store.dart';
import '../../data/models.dart';
import '../detail/course_detail_screen.dart';
import '../home/widgets/filter_sheet.dart';
import '../home/widgets/nova_product_card.dart';
import '../home/widgets/nova_search_field.dart';
import '../learning/open_course.dart';
import '../shell/student_top_bar.dart';
import 'offers_catalog_screen.dart';

/// Which of the website's two catalogues a [CatalogPage] shows.
enum CatalogKind { units, offers }

/// The website's `/courses` and `/bundles` page (`CatalogPage`,
/// catalog.tsx) at phone size: the full-width blue band, the search
/// field, the blue "Filters" button and the sort, the result count with
/// the active filters, then one column of catalogue cards. The backend
/// searches, filters and sorts; visitors browse it read-only (D-134).
class CatalogPage extends StatefulWidget {
  const CatalogPage({super.key, required this.kind});

  final CatalogKind kind;

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  CatalogQuery _query = const CatalogQuery();
  final TextEditingController _search = TextEditingController();
  Timer? _typing;

  bool get _units => widget.kind == CatalogKind.units;

  @override
  void dispose() {
    _typing?.cancel();
    _search.dispose();
    super.dispose();
  }

  CatalogMatches<Object> _matches(CatalogQuery query) {
    final CatalogStore catalog = AppScope.of(context).catalog;
    return _units ? catalog.unitsFor(query) : catalog.offersFor(query);
  }

  void _apply(CatalogQuery query) {
    _typing?.cancel();
    if (query.search != _search.text) _search.text = query.search;
    setState(() => _query = query);
  }

  /// The website asks on every keystroke; the app waits for a pause.
  void _onSearch(String text) {
    _typing?.cancel();
    _typing = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _query = _query.copyWith(search: text));
    });
  }

  void _openFilters() {
    FocusScope.of(context).unfocus();
    final CatalogStore catalog = AppScope.of(context).catalog;
    showCatalogFilterSheet(
      context,
      units: _units,
      query: _query,
      onChanged: _apply,
      count: (CatalogQuery query) => (_units ? catalog.unitsFor(query) : catalog.offersFor(query)).items?.length,
    );
  }

  void _open(Object item) {
    final NavigatorState navigator = Navigator.of(context);
    if (item is Course && item.owned) {
      openOwnedCourse(context, item);
    } else if (item is Course) {
      navigator.push(MaterialPageRoute<void>(builder: (_) => CourseDetailScreen(course: item)));
    } else if (item is Pack) {
      navigator.push(MaterialPageRoute<void>(builder: (_) => CourseDetailScreen.pack(pack: item)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = AppScope.of(context);
    final CatalogStore catalog = app.catalog;
    final CatalogMatches<Object> matches = _matches(_query);
    final bool plain = _query.isDefault;
    // The plain list is the catalogue itself: it loads with the app.
    final bool firstLoad = plain && matches.items!.isEmpty && (catalog.state == LoadState.idle || catalog.state == LoadState.loading);
    final Object? error = plain ? (catalog.state == LoadState.failed && matches.items!.isEmpty ? catalog.error : null) : matches.error;
    final List<Object>? items = firstLoad || error != null
        ? null
        : matches.items?.map((Object item) => item is Course && app.learning.owns(item.id) ? item.copyWith(owned: true) : item).toList();
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
                eyebrow: context.tr(_units ? 'catalog.unitsEyebrow' : 'catalog.offersEyebrow'),
                title: context.tr(_units ? 'catalog.unitsTitle' : 'catalog.offersTitle'),
                lead: context.tr(_units ? 'catalog.unitsLead' : 'catalog.offersLead'),
              ),
            ),
            // `.nvToolbar`: the search, then the filter button and the sort side by side.
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 28, 16, 26),
              sliver: SliverToBoxAdapter(
                child: Column(
                  children: [
                    NovaSearchField(
                      hint: context.tr(_units ? 'catalog.searchUnits' : 'catalog.searchOffers'),
                      controller: _search,
                      onChanged: _onSearch,
                      onSubmitted: (String text) {
                        _typing?.cancel();
                        setState(() => _query = _query.copyWith(search: text));
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _FilterButton(count: _query.filterCount, onTap: _openFilters)),
                        const SizedBox(width: 12),
                        Expanded(child: _SortField(value: _query.sort, onChanged: (CatalogSort sort) => _apply(_query.copyWith(sort: sort)))),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (items != null)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                sliver: SliverToBoxAdapter(
                  child: _ResultsHead(
                    count: items.length,
                    units: _units,
                    audience: catalog.audience,
                    chips: _activeChips(context, _units ? catalog.unitFacets : catalog.offerFacets),
                  ),
                ),
              ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 40 + bottom),
              sliver: error != null
                  ? SliverToBoxAdapter(
                      child: HeroEmpty(
                        icon: Icons.warning_amber_rounded,
                        title: context.tr(_units ? 'catalog.errorUnitsTitle' : 'catalog.errorOffersTitle'),
                        message: context.tr(_units ? 'catalog.errorUnitsText' : 'catalog.errorOffersText'),
                        action: NovaButton(label: context.tr('catalog.retry'), icon: Icons.refresh_rounded, onTap: catalog.load),
                      ),
                    )
                  : items == null
                      ? SliverList.separated(
                          itemCount: 2,
                          separatorBuilder: (_, _) => const SizedBox(height: 16),
                          itemBuilder: (_, _) => const CatalogCardSkeleton(),
                        )
                      : items.isEmpty
                          ? SliverToBoxAdapter(child: _empty(context))
                          : SliverList.separated(
                              itemCount: items.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 16),
                              itemBuilder: (BuildContext context, int index) {
                                final Object item = items[index];
                                final Widget card = item is Course
                                    ? NovaProductCard.unit(context, item, width: double.infinity, onTap: () => _open(item))
                                    : NovaProductCard.offer(context, item as Pack, width: double.infinity, onTap: () => _open(item));
                                return index < maxStaggered
                                    ? Entrance(key: ValueKey<String>(item is Course ? 'unit ${item.id}' : 'offer ${(item as Pack).id}'), delay: Duration(milliseconds: 60 * index), child: card)
                                    : card;
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }

  /// Nothing published at all, or nothing for this search and filters.
  Widget _empty(BuildContext context) {
    if (_query.filterCount == 0 && _query.search.trim().isEmpty) {
      return HeroEmpty(
        icon: Icons.auto_awesome_outlined,
        title: context.tr(_units ? 'catalog.emptyUnitsTitle' : 'catalog.emptyOffersTitle'),
        message: context.tr(_units ? 'catalog.emptyUnitsText' : 'catalog.emptyOffersText'),
        action: _units
            ? NovaButton(
                label: context.tr('catalog.browseOffers'),
                chipIcon: Icons.arrow_forward_rounded,
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const OffersCatalogScreen())),
              )
            : null,
      );
    }
    return HeroEmpty(
      icon: Icons.search_off_rounded,
      title: context.tr('catalog.noMatchTitle'),
      message: context.tr('catalog.noMatchText'),
      action: NovaButton(
        label: context.tr('catalog.resetFilters'),
        variant: NovaButtonVariant.ghost,
        onTap: () => _apply(_query.cleared()),
      ),
    );
  }

  /// `.nvActiveChips`: one blue chip per chosen filter, in the website's
  /// order; tapping one removes it.
  List<Widget> _activeChips(BuildContext context, CatalogFacets facets) {
    String name(List<RefItem> items, int id) => items.where((RefItem i) => i.id == id).map((RefItem i) => i.name).firstOrNull ?? '$id';
    Set<T> without<T>(Set<T> set, T value) => <T>{...set}..remove(value);
    final CatalogQuery q = _query;
    return <Widget>[
      for (final int id in q.levelIds)
        _ActiveChip(label: name(facets.levels, id), onTap: () => _apply(q.copyWith(levelIds: without(q.levelIds, id)))),
      for (final int id in q.subjectIds)
        _ActiveChip(label: name(facets.subjects, id), onTap: () => _apply(q.copyWith(subjectIds: without(q.subjectIds, id)))),
      for (final int id in q.teacherIds)
        _ActiveChip(
          label: facets.teachers.where((Teacher t) => t.id == id).map((Teacher t) => t.name).firstOrNull ?? '$id',
          onTap: () => _apply(q.copyWith(teacherIds: without(q.teacherIds, id))),
        ),
      for (final int id in q.trackIds)
        _ActiveChip(label: name(facets.tracks, id), onTap: () => _apply(q.copyWith(trackIds: without(q.trackIds, id)))),
      for (final String type in q.types)
        _ActiveChip(
          label: K.containsKey('offer.type_$type') ? context.tr('offer.type_$type') : type,
          onTap: () => _apply(q.copyWith(types: without(q.types, type))),
        ),
      if (q.access != CatalogAccess.all)
        _ActiveChip(
          label: context.tr(q.access == CatalogAccess.free ? 'catalog.accessFree' : 'catalog.accessPaid'),
          onTap: () => _apply(q.copyWith(access: CatalogAccess.all)),
        ),
      if (q.maxPrice != null)
        _ActiveChip(
          label: context.trf('catalog.underPrice', <String, String>{'price': '\u2066${_grouped(q.maxPrice!)}\u2069'}),
          onTap: () => _apply(q.copyWith(maxPrice: () => null)),
        ),
    ];
  }

  /// 25000 → "25 000" (thin spaces, as the card prices).
  static String _grouped(int amount) {
    final String digits = '$amount';
    final StringBuffer out = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      out.write(digits[i]);
      final int left = digits.length - 1 - i;
      if (left > 0 && left % 3 == 0) out.write(' ');
    }
    return '$out';
  }
}

/// The public pages' blue band (`PageHero` / `.nvPageHead.hxBand`): full
/// width under the top bar, rounded 26 at the bottom on phones, with the
/// yellow eyebrow, the title and its circled word, the lead and an
/// optional sticker ([aside]).
class CatalogBand extends StatelessWidget {
  const CatalogBand({super.key, required this.eyebrow, required this.title, this.lead, this.aside});

  final String eyebrow;
  final String title;
  final String? lead;
  final Widget? aside;

  @override
  Widget build(BuildContext context) {
    return HeroBand(
      radius: const BorderRadius.vertical(bottom: Radius.circular(26)),
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HeroEyebrow(eyebrow),
          const SizedBox(height: 16),
          HeroTitle(title, size: 35, maxLines: 3),
          if (lead != null) ...[
            const SizedBox(height: 16),
            Text(
              lead!,
              style: NovaTypography.textTheme.bodyLarge!.copyWith(
                fontSize: 16,
                height: 1.7,
                fontWeight: FontWeight.w400,
                color: Colors.white.withValues(alpha: 0.84),
              ),
            ),
          ],
          if (aside != null) ...[const SizedBox(height: 20), aside!],
        ],
      ),
    );
  }
}

/// `.nvStat`: a big blue number and its label on a white sticker, tilted
/// on the band.
class CatalogStat extends StatelessWidget {
  const CatalogStat({super.key, required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: 3 * math.pi / 180,
      child: Container(
        constraints: const BoxConstraints(minWidth: 140),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
        decoration: BoxDecoration(
          color: NovaColors.paperCard,
          borderRadius: BorderRadius.circular(20),
          boxShadow: NovaDimens.shadowSticker,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$value', style: _baloo(32, NovaColors.accent).copyWith(height: 1.05)),
            const SizedBox(height: 2),
            Text(label, style: _baloo(15, NovaColors.textBody, FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

/// `.nhCardSkeleton`: the catalogue card's frame while the list loads.
class CatalogCardSkeleton extends StatelessWidget {
  const CatalogCardSkeleton({super.key, this.mediaRatio = 25 / 23});

  final double mediaRatio;

  @override
  Widget build(BuildContext context) {
    const Color bar = Color(0xFF2C2C2F);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 22),
      decoration: BoxDecoration(color: const Color(0xFF232325), borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: mediaRatio,
            child: DecoratedBox(decoration: BoxDecoration(color: bar, borderRadius: BorderRadius.circular(16))),
          ),
          const SizedBox(height: 12),
          for (final double width in <double>[0.7, 0.45]) ...[
            FractionallySizedBox(
              widthFactor: width,
              child: Container(
                height: 16,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(color: bar, borderRadius: BorderRadius.circular(8)),
              ),
            ),
            if (width == 0.7) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

TextStyle _baloo(double size, Color color, [FontWeight weight = FontWeight.w800]) => TextStyle(
      fontFamily: NovaTypography.display,
      fontFamilyFallback: NovaTypography.fallback,
      fontWeight: weight,
      fontSize: size,
      height: 1.25,
      color: color,
    );

/// `.nvFilterToggle`: the blue "Filters" button with the yellow count.
class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.97,
      semanticLabel: context.tr('catalog.filters'),
      child: ExcludeSemantics(
        child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(color: NovaColors.accent, borderRadius: BorderRadius.circular(NovaDimens.radiusControl)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.tune_rounded, size: 19, color: Colors.white),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                context.tr('catalog.filters'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _baloo(16, Colors.white),
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 8),
              Container(
                constraints: const BoxConstraints(minWidth: 22),
                height: 22,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: NovaColors.yellow, borderRadius: BorderRadius.circular(999)),
                child: Text('$count', style: _baloo(12, NovaColors.yellowInk).copyWith(height: 1)),
              ),
            ],
          ],
        ),
      ),
      ),
    );
  }
}

/// `.nvSort`: the order, as a field that opens the three choices (its
/// "Sort by" label is hidden on phones, as on the website).
class _SortField extends StatelessWidget {
  const _SortField({required this.value, required this.onChanged});

  final CatalogSort value;
  final ValueChanged<CatalogSort> onChanged;

  @override
  Widget build(BuildContext context) {
    final Map<CatalogSort, String> labels = <CatalogSort, String>{
      CatalogSort.recommended: context.tr('catalog.sortRecommended'),
      CatalogSort.priceLow: context.tr('catalog.sortPriceLow'),
      CatalogSort.priceHigh: context.tr('catalog.sortPriceHigh'),
    };
    return PopupMenuButton<CatalogSort>(
      tooltip: context.tr('catalog.sortBy'),
      initialValue: value,
      onSelected: onChanged,
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      color: NovaColors.paperCard,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: const Color(0x3D101822),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NovaDimens.radiusSmall),
        side: BorderSide(color: NovaColors.borderOnLight),
      ),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<CatalogSort>>[
        for (final MapEntry<CatalogSort, String> option in labels.entries)
          PopupMenuItem<CatalogSort>(
            value: option.key,
            height: 44,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    option.value,
                    style: _baloo(15, option.key == value ? NovaColors.accent : NovaColors.textStrong, FontWeight.w700),
                  ),
                ),
                if (option.key == value) Icon(Icons.check_rounded, size: 17, color: NovaColors.accent),
              ],
            ),
          ),
      ],
      child: Container(
        height: 52,
        padding: const EdgeInsetsDirectional.fromSTEB(18, 0, 10, 0),
        decoration: BoxDecoration(
          color: NovaColors.paperCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: NovaColors.borderOnLight),
          boxShadow: NovaDimens.shadowCard,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(labels[value]!, maxLines: 1, overflow: TextOverflow.ellipsis, style: _baloo(15, NovaColors.textStrong)),
            ),
            Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: NovaColors.textMuted),
          ],
        ),
      ),
    );
  }
}

/// `.nvResultsHead`: «<b>6</b> وحدات», the Student's level and filière
/// when the backend narrowed the list to them, then the active filters.
class _ResultsHead extends StatelessWidget {
  const _ResultsHead({required this.count, required this.units, required this.audience, required this.chips});

  final int count;
  final bool units;
  final String? audience;
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    final TextStyle text = NovaTypography.textTheme.bodyMedium!.copyWith(fontSize: 15, color: NovaColors.textBody);
    final String label = context.tr(units ? (count == 1 ? 'catalog.unitFound' : 'catalog.unitsFound') : 'catalog.offersFound');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 34),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(text: '$count', style: _baloo(18, NovaColors.textStrong)),
                  TextSpan(text: ' $label'),
                  if (audience != null) TextSpan(text: ' · ${context.trf('catalog.audience', <String, String>{'profile': audience!})}'),
                ],
              ),
              style: text,
            ),
          ),
        ),
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: chips),
        ],
      ],
    );
  }
}

/// `.nvActiveChips button`: a chosen filter, removed on tap.
class _ActiveChip extends StatelessWidget {
  const _ActiveChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.95,
      semanticLabel: label,
      child: Container(
        height: 36,
        padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 10, 0),
        decoration: BoxDecoration(color: NovaColors.accent, borderRadius: BorderRadius.circular(NovaDimens.radiusSmall)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: _baloo(14, Colors.white, FontWeight.w700)),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.close_rounded, size: 14, color: Colors.white),
          ],
        ),
      ),
    );
  }
}
