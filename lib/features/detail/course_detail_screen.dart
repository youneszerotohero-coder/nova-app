import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/i18n/labels.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_dimens.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/widgets/hero_style.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/nova_image.dart';
import '../../core/widgets/nova_scene_image.dart';
import '../../core/widgets/nova_toast.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../data/models.dart';
import '../auth/require_account.dart';
import '../cart/checkout_screen.dart';
import '../catalog/offers_catalog_screen.dart';
import '../catalog/units_catalog_screen.dart';
import '../home/widgets/nova_product_card.dart';
import '../learning/open_course.dart';
import '../shell/student_top_bar.dart';
import 'pack_picker.dart';
import '../shell/shell_screen.dart';
import 'teacher_detail_screen.dart';

/// The website's Unit page (`/courses/:slug`) and Offer page (`/bundles/:slug`,
/// via `.pack`), `detail.tsx` (D-134): the blue band with the back link, the
/// cover in its tilted white frame, the tags, title, teacher, description,
/// figures and the white buy row; then the Lessons (or the Offer's Units and
/// guarantees), the buy card, other Units, and the phone's sticky buy bar.
class CourseDetailScreen extends StatefulWidget {
  const CourseDetailScreen({super.key, required this.course})
      : pack = null;

  const CourseDetailScreen.pack({super.key, required this.pack})
      : course = null;

  final Course? course;
  final Pack? pack;

  @override
  State<CourseDetailScreen> createState() => _CourseDetailScreenState();
}

class _CourseDetailScreenState extends State<CourseDetailScreen> {
  late Course? _course = widget.course;
  late Pack? _pack = widget.pack;
  bool _busy = false;

  /// The open Lesson row; the first one opens when it has a description.
  int? _openLesson;

  bool get _isPack => _pack != null;
  AppState get _app => AppScope.of(context);
  bool get _owned => _isPack ? _packOwned : _app.learning.owns(_course!.id);
  bool get _free => !_isPack && _course!.isFree;

  /// The website's rule: an Offer is owned when every one of its Units is
  /// paid for (a free enrolment does not count).
  bool get _packOwned {
    final List<PackItem> items = _pack!.items;
    if (items.isEmpty) return false;
    return items.every((PackItem item) => _app.learning.owns(item.courseId) && _catalogCourse(item.courseId)?.isFree != true);
  }

  /// D-091: a paid Unit never sold on its own; Buy and Add put one of its
  /// Packs in the cart (the Student picks one when there are several).
  bool get _packOnly => !_isPack && _course!.packOnly;
  List<CoursePack> get _coursePacks => _isPack ? const <CoursePack>[] : _course!.packs;

  /// D-083: another level or filière than the signed-in Student's (said by
  /// the public detail). It stays visible and is never bought or joined;
  /// Laravel refuses it too.
  bool get _outOfTrack =>
      !_owned &&
      (_isPack ? _pack!.matchesStudentProfile : _course!.matchesStudentProfile) ==
          false;
  String get _kind => _isPack ? 'offer' : 'course';
  int get _productId => _isPack ? _pack!.id : _course!.id;
  String get _cartKey => '$_kind:$_productId';
  bool get _added => _packOnly
      ? _coursePacks.any((CoursePack pack) => _app.contains('offer:${pack.id}'))
      : _app.contains(_cartKey);

  Course? _catalogCourse(int id) =>
      _app.courses.where((Course c) => c.id == id).firstOrNull;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// Full detail from the API: the curriculum (with the Student's
  /// lock/progress when owned) or the Offer's Courses.
  Future<void> _load() async {
    final AppState app = _app;
    try {
      if (_isPack) {
        final Pack pack = await app.catalog.offer(_pack!.slug);
        if (mounted) setState(() => _pack = pack);
        return;
      }
      final bool owned = app.learning.owns(_course!.id);
      Course course = await app.catalog.course(_course!.slug, owned: owned);
      if (owned) course = await app.learning.courseWithProgress(course);
      if (mounted) setState(() => _course = course);
    } on ApiException catch (error) {
      if (mounted) _toast(apiErrorText(context, error), error: true);
    }
  }

  void _toast(String message, {bool error = false}) {
    novaToast(
      context,
      message,
      icon: error ? Icons.error_outline_rounded : Icons.check_circle_rounded,
    );
  }

  Future<bool> _addToCart() => _addItem(_kind, _productId);

  Future<void> _buyNow() => _buyItem(_kind, _productId);

  Future<bool> _addItem(String kind, int id) async {
    // A visitor signs in first, then lands in the cart with this item (D-134).
    if (!requireAccount(context, intent: AddToCart(kind, id))) return false;
    if (_app.contains('$kind:$id')) return true;
    setState(() => _busy = true);
    try {
      await _app.commerce.add(kind: kind, id: id);
      if (mounted) {
        _toast(kind == 'offer'
            ? context.tr('detail.packAddedToast')
            : context.tr('detail.addedToast'));
      }
      return true;
    } on ApiException catch (error) {
      if (mounted) _toast(apiErrorText(context, error), error: true);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _buyItem(String kind, int id) async {
    if (!await _addItem(kind, id) || !mounted) return;
    final CartItem? item = _app.items
        .where((CartItem i) => i.id == '$kind:$id')
        .firstOrNull;
    if (item == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => CheckoutScreen(item: item)),
    );
  }

  /// D-091: one Pack is added or bought at once; with several the
  /// Student picks one (cheapest first, as Laravel lists them).
  Future<void> _choosePack({required bool buy}) async {
    final List<CoursePack> packs = _coursePacks;
    if (packs.isEmpty) return;
    final CoursePack? pack = packs.length == 1
        ? packs.single
        : await showPackPicker(context, packs: packs, buy: buy);
    if (pack == null || !mounted) return;
    if (buy) {
      await _buyItem('offer', pack.id);
    } else {
      await _addItem('offer', pack.id);
    }
  }

  /// Free Courses are never sold (D-054): the Student joins them.
  Future<void> _joinFree() async {
    if (!requireAccount(context, intent: OpenCourse(_course!))) return;
    setState(() => _busy = true);
    try {
      await _app.learning.enrollFree(_course!);
      if (!mounted) return;
      _toast(context.tr('detail.joined'));
      await _load();
    } on ApiException catch (error) {
      if (mounted) _toast(apiErrorText(context, error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openCourse() {
    if (requireAccount(context, intent: OpenCourse(_course!))) openOwnedCourse(context, _course!);
  }

  /// An owned Offer leads to the Student's Units: back to the space.
  void _openMyUnits() => AppScope.of(context).openShellTab(ShellScreen.units);

  void _push(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final _Price price = _price(context);
    return Scaffold(
      backgroundColor: NovaColors.paperPublic,
      body: Stack(
        children: [
          ListView(
            padding: EdgeInsets.only(bottom: 96 + MediaQuery.paddingOf(context).bottom),
            children: [
              const StudentTopBar(showBack: true),
              _band(context, price),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 36, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_isPack) ..._packContent(context) else ..._courseContent(context),
                    const SizedBox(height: 28),
                    _buyCard(context, price),
                    if (!_isPack) ..._related(context),
                  ],
                ),
              ),
            ],
          ),
          PositionedDirectional(start: 0, end: 0, bottom: 0, child: _stickyBar(context, price)),
        ],
      ),
    );
  }

  // The band ------------------------------------------------------------------------------------------------------

  Widget _band(BuildContext context, _Price price) {
    final List<Widget> tags = _isPack
        ? <Widget>[_Tag(offerTypeText(context, _pack!), kind: _TagKind.strong)]
        : <Widget>[
            if (_free) _Tag(context.tr('detail.freeUnit'), kind: _TagKind.free, icon: Icons.card_giftcard_rounded),
            if (_course!.subject.isNotEmpty) _Tag(_course!.subject, kind: _TagKind.strong),
            if (_course!.level.isNotEmpty) _Tag(_course!.level),
          ];
    final String description = _isPack ? _pack!.description : _course!.description;
    return HeroBand(
      radius: const BorderRadius.vertical(bottom: Radius.circular(26)),
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_outOfTrack) ...[
            _BandNotice(
              title: context.tr('detail.outOfTrackTitle'),
              text: _outOfTrackText(context),
            ),
            const SizedBox(height: 18),
          ],
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: _BackLink(
              label: context.tr(_isPack ? 'detail.allOffers' : 'detail.allUnits'),
              onTap: () => _push(_isPack ? const OffersCatalogScreen() : const UnitsCatalogScreen()),
            ),
          ),
          const SizedBox(height: 24),
          Center(child: _CoverFrame(cover: _cover(context))),
          const SizedBox(height: 28),
          if (tags.isNotEmpty) Entrance(child: Wrap(spacing: 8, runSpacing: 8, children: tags)),
          const SizedBox(height: 20),
          Entrance(
            delay: const Duration(milliseconds: 60),
            child: HeroTitle(_isPack ? _pack!.name : _course!.title, size: 34, maxLines: 4),
          ),
          ..._teacherChips(context),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 20),
            Entrance(
              delay: const Duration(milliseconds: 120),
              child: Text(
                description,
                style: TextStyle(
                  fontFamily: NovaTypography.body,
                  fontFamilyFallback: NovaTypography.fallback,
                  fontSize: 16,
                  height: 1.7,
                  color: const Color(0xDBFFFFFF),
                ),
              ),
            ),
          ],
          const SizedBox(height: 28),
          _Stats(stats: _isPack ? _packStats(context) : _courseStats(context)),
          const SizedBox(height: 30),
          _BuyRow(price: price, actions: _actions(context, card: false)),
        ],
      ),
    );
  }

  String _outOfTrackText(BuildContext context) {
    final StudentProfile? me = _app.session.profile;
    final String profile = <String>[me?.level ?? '', me?.track ?? ''].where((String part) => part.isNotEmpty).join(' · ');
    return context
        .tr(_isPack ? 'detail.outOfTrackOffer' : 'detail.outOfTrackCourse')
        .replaceAll(' ({profile})', profile.isEmpty ? '' : ' ($profile)');
  }

  /// The poster with its corner sticker: "N Live" (or "Recorded") on a
  /// Unit, "Save x %" on an Offer.
  Widget _cover(BuildContext context) {
    final Widget art = _isPack
        ? NovaSceneImage(scene: _pack!.scene, image: _pack!.image, icon: _pack!.icon, fit: BoxFit.contain)
        : NovaSceneImage(scene: _course!.scene, image: _course!.image, icon: _course!.icon, fit: BoxFit.contain);
    final Widget? sticker = _isPack
        ? (_pack!.discountPercent > 0
            ? PositionedDirectional(
                top: 12,
                start: 12,
                child: _CoverSticker(
                  label: context.trf('card.saving', <String, String>{'percent': '${_pack!.discountPercent}'}),
                  yellow: true,
                ),
              )
            : null)
        : PositionedDirectional(
            top: 12,
            end: 12,
            child: _CoverSticker(
              label: _course!.plannedLives > 0
                  ? '${_course!.plannedLives} ${context.tr('card.live')}'
                  : context.tr('card.recorded'),
              live: _course!.plannedLives > 0,
            ),
          );
    return Stack(fit: StackFit.expand, children: [art, ?sticker]);
  }

  List<Widget> _teacherChips(BuildContext context) {
    final List<Widget> chips;
    if (_isPack) {
      chips = <Widget>[
        for (final String name in _pack!.teachers.where((String n) => n.trim().isNotEmpty))
          _TeacherChip(name: name, onTap: _teacherNamed(name)),
      ];
    } else {
      final Course course = _course!;
      chips = course.teacher.trim().isEmpty
          ? const <Widget>[]
          : <Widget>[_TeacherChip(name: course.teacher, photo: course.teacherPhoto, onTap: () => _push(TeacherDetailScreen(teacher: _teacherOf(course))))];
    }
    if (chips.isEmpty) return const <Widget>[];
    return <Widget>[
      const SizedBox(height: 22),
      Entrance(
        delay: const Duration(milliseconds: 90),
        child: Wrap(spacing: 8, runSpacing: 8, children: chips),
      ),
    ];
  }

  /// The Unit's Teacher from the catalogue, or built from the Unit itself.
  Teacher _teacherOf(Course course) =>
      _app.catalog.teachers.where((Teacher t) => t.id == course.teacherId).firstOrNull ??
      Teacher(
        id: course.teacherId,
        name: course.teacher,
        subject: course.subject,
        subjects: course.subject.isEmpty ? const <String>[] : <String>[course.subject],
        scene: course.scene,
        bio: '',
        photo: course.teacherPhoto,
      );

  /// An Offer only names its Teachers: their page opens when the catalogue
  /// knows them.
  VoidCallback? _teacherNamed(String name) {
    final Teacher? teacher = _app.catalog.teachers.where((Teacher t) => t.name == name).firstOrNull;
    return teacher == null ? null : () => _push(TeacherDetailScreen(teacher: teacher));
  }

  List<(String, String, bool)> _courseStats(BuildContext context) {
    final Course course = _course!;
    final int quizzes = course.lessons.where((Lesson l) => l.hasQuiz || l.quiz != null).length;
    final int pdfs = course.lessons.where((Lesson l) => l.hasPdf || l.pdf != null).length;
    return <(String, String, bool)>[
      (context.tr('detail.statLessons'), '${course.lessonsCount}', false),
      if (course.plannedLives > 0) (context.tr('detail.statLives'), '${course.plannedLives}', false),
      if (quizzes > 0) (context.tr('detail.statQuizzes'), '$quizzes', false),
      if (pdfs > 0) (context.tr('detail.statPdf'), '$pdfs', false),
    ];
  }

  List<(String, String, bool)> _packStats(BuildContext context) {
    final Pack pack = _pack!;
    final int count = pack.items.isNotEmpty ? pack.items.length : pack.courseCount;
    final int teachers = pack.items.map((PackItem i) => i.teacher).where((String t) => t.isNotEmpty).toSet().length;
    return <(String, String, bool)>[
      (
        context.tr('detail.statUnits'),
        count > 0 ? context.trf(count == 1 ? 'detail.unitsCountOne' : 'detail.unitsCount', <String, String>{'n': '$count'}) : context.tr('detail.unitsComing'),
        false,
      ),
      if (count > 0 && teachers > 0) (context.tr('detail.statTeachers'), '$teachers', false),
      if (pack.discountPercent > 0) (context.tr('detail.statSaving'), '−${pack.discountPercent}%', true),
    ];
  }

  // Price and actions ---------------------------------------------------------------------------------------------

  _Price _price(BuildContext context) {
    if (_isPack) {
      final Pack pack = _pack!;
      return _Price(
        label: context.tr('detail.offerPrice'),
        value: NovaProductCard.formatCardPrice(pack.price),
        was: pack.discountPercent > 0 ? NovaProductCard.formatCardPrice(pack.compareAtPrice) : null,
      );
    }
    final Course course = _course!;
    if (_free) return _Price(label: context.tr('detail.freeAccessLabel'), value: context.tr('common.free'), free: true);
    if (_packOnly) {
      final int? from = course.offerPriceFrom;
      return _Price(
        label: context.tr(from == null ? 'detail.referencePrice' : 'detail.packsFrom'),
        value: from == null ? context.tr('detail.packsOnly') : NovaProductCard.formatCardPrice(from),
      );
    }
    return _Price(label: context.tr('detail.referencePrice'), value: NovaProductCard.formatCardPrice(course.price));
  }

  /// The buy row's (or the buy card's) actions, as `accessAction` /
  /// `PurchaseActions` choose them on the website.
  Widget? _actions(BuildContext context, {required bool card}) {
    if (_isPack) {
      if (_owned) {
        return _DetailButton(
          label: '${context.tr('detail.purchased')} · ${context.tr('detail.myUnits')}',
          icon: Icons.check_circle_outline_rounded,
          onTap: _openMyUnits,
        );
      }
      if (_outOfTrack) return null;
      return _purchaseActions(context, card: card, onBuy: _buyNow, onAdd: _addToCart, addLabel: context.tr('detail.addToCart'));
    }
    final Course course = _course!;
    if (_owned) {
      return _DetailButton(
        label: context.tr(course.isFree ? 'detail.accessUnit' : 'detail.openUnit'),
        icon: card ? null : Icons.check_circle_outline_rounded,
        onTap: _openCourse,
      );
    }
    if (_outOfTrack) return null;
    if (course.isFree) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DetailButton(
            label: context.tr(_busy ? 'detail.enrolling' : 'detail.joinFree'),
            icon: Icons.card_giftcard_rounded,
            kind: _ButtonKind.live,
            arrow: !_busy,
            onTap: _busy ? null : _joinFree,
          ),
          if (!_app.session.signedIn) ...[
            const SizedBox(height: 10),
            Text(context.tr('detail.freeSigninHint'), style: _text(15, NovaColors.textMuted)),
          ],
        ],
      );
    }
    if (course.individualPurchaseEnabled) {
      return _purchaseActions(context, card: card, onBuy: _buyNow, onAdd: _addToCart, addLabel: context.tr('detail.addToCart'));
    }
    if (_coursePacks.isNotEmpty) {
      final List<CoursePack> packs = _coursePacks;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _purchaseActions(
            context,
            card: card,
            onBuy: () => _choosePack(buy: true),
            onAdd: () => _choosePack(buy: false),
            addLabel: context.tr('detail.addPack'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.layers_outlined, size: 14, color: NovaColors.textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  packs.length == 1
                      ? context.trf('detail.soldInPack', <String, String>{'title': packs.single.title})
                      : context.trf('detail.soldInPacks', <String, String>{'count': '${packs.length}'}),
                  style: _text(15, NovaColors.textMuted),
                ),
              ),
            ],
          ),
        ],
      );
    }
    // `.courseAvailabilityPanel`.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: NovaColors.accentMist, borderRadius: BorderRadius.circular(NovaDimens.radiusControl)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_user_outlined, size: 18, color: NovaColors.accent),
          const SizedBox(width: 8),
          Flexible(child: Text(context.tr('detail.offersOnly'), style: _baloo(16, NovaColors.accent))),
        ],
      ),
    );
  }

  /// "Buy now" and "Add to cart": side by side in the band, stacked in the
  /// buy card.
  Widget _purchaseActions(
    BuildContext context, {
    required bool card,
    required VoidCallback onBuy,
    required VoidCallback onAdd,
    required String addLabel,
  }) {
    final bool added = _added;
    final Widget buy = _DetailButton(label: context.tr('detail.buyNow'), onTap: _busy ? null : onBuy);
    final Widget add = _DetailButton(
      label: added ? context.tr('detail.addedToCart') : addLabel,
      icon: added ? Icons.check_rounded : Icons.shopping_bag_outlined,
      kind: added ? _ButtonKind.live : _ButtonKind.ghost,
      arrow: false,
      onTap: _busy ? null : onAdd,
    );
    if (card) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [buy, const SizedBox(height: 10), add],
      );
    }
    return Row(
      children: [
        Expanded(child: buy),
        const SizedBox(width: 10),
        Expanded(child: add),
      ],
    );
  }

  // The body ------------------------------------------------------------------------------------------------------

  List<Widget> _courseContent(BuildContext context) {
    final List<Lesson> lessons = _course!.lessons;
    final int open = _openLesson ?? (lessons.isNotEmpty && lessons.first.description.isNotEmpty ? 0 : -1);
    return <Widget>[
      _SectionHead(number: '01', label: context.tr('detail.insideUnit'), title: context.tr('detail.lessonSequence')),
      if (lessons.isEmpty)
        HeroEmpty(icon: Icons.play_arrow_rounded, title: '', message: context.tr('detail.noLessons'), orbit: false)
      else
        _RuledList(
          children: <Widget>[
            for (int i = 0; i < lessons.length; i++)
              _LessonRow(
                index: i,
                lesson: lessons[i],
                open: open == i,
                onToggle: lessons[i].description.isEmpty ? null : () => setState(() => _openLesson = open == i ? -1 : i),
              ),
          ],
        ),
    ];
  }

  List<Widget> _packContent(BuildContext context) {
    final List<PackItem> items = _pack!.items;
    return <Widget>[
      _SectionHead(number: '01', label: context.tr('detail.completePlan'), title: context.tr('detail.includedInOffer')),
      if (items.isEmpty)
        HeroEmpty(
          icon: Icons.auto_awesome_outlined,
          title: context.tr('detail.unitsComingTitle'),
          message: context.tr('detail.unitsComingText'),
          orbit: false,
        )
      else
        _RuledList(
          children: <Widget>[
            for (int i = 0; i < items.length; i++) _unitRow(context, i, items[i]),
          ],
        ),
      const SizedBox(height: 56),
      _SectionHead(number: '02', label: context.tr('detail.guarantees'), title: context.tr('detail.neverRepay')),
      for (final (IconData icon, String key) in <(IconData, String)>[
        (Icons.auto_awesome_outlined, 'detail.guaranteeOwned'),
        (Icons.layers_outlined, 'detail.guaranteeFuture'),
        (Icons.verified_user_outlined, 'detail.accessYear'),
      ]) ...[
        _Guarantee(icon: icon, text: context.tr(key)),
        const SizedBox(height: 14),
      ],
    ];
  }

  Widget _unitRow(BuildContext context, int index, PackItem item) {
    final bool access = _app.learning.owns(item.courseId);
    final Course? owned = _app.learning.owned.where((Course c) => c.id == item.courseId).firstOrNull;
    final Course? listed = _catalogCourse(item.courseId);
    final bool free = listed?.isFree ?? false;
    final String badge = access
        ? context.tr(free ? 'detail.enrolledShort' : 'detail.purchased')
        : context.tr(free ? 'common.free' : 'detail.includedBadge');
    final VoidCallback? onTap = access && owned != null
        ? () => openOwnedCourse(context, owned)
        : listed != null
            ? () => _push(CourseDetailScreen(course: listed))
            : null;
    return _UnitRow(
      index: index,
      title: item.courseTitle,
      meta: <String>[item.subject, item.teacher].where((String s) => s.isNotEmpty).join(' · '),
      badge: badge,
      badgeKind: access ? _BadgeKind.owned : (free ? _BadgeKind.free : _BadgeKind.plain),
      onTap: onTap,
    );
  }

  /// `.nvBuyCard`: the price, what the access includes, the actions and
  /// the secure-checkout line.
  Widget _buyCard(BuildContext context, _Price price) {
    final List<String> checks;
    if (_isPack) {
      final int count = _pack!.items.length;
      checks = <String>[
        if (count > 0)
          context.trf(count == 1 ? 'detail.coursesIncludedOne' : 'detail.coursesIncluded', <String, String>{'count': '$count'})
        else
          context.tr('detail.offerCoursesLater'),
        context.tr('detail.automaticOverlap'),
        context.tr('detail.accessYear'),
        context.tr('detail.protectedPdfsAll'),
      ];
    } else {
      final Course course = _course!;
      final int quizzes = course.lessons.where((Lesson l) => l.hasQuiz || l.quiz != null).length;
      final int pdfs = course.lessons.where((Lesson l) => l.hasPdf || l.pdf != null).length;
      checks = <String>[
        context.trf('detail.orderedLessons', <String, String>{'n': '${course.lessonsCount}'}),
        context.trf('detail.quizCheckpoints', <String, String>{'n': '$quizzes'}),
        context.trf('detail.protectedPdfs', <String, String>{'n': '$pdfs'}),
        context.tr('detail.accessYear'),
      ];
    }
    final Widget? actions = _actions(context, card: true);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
      decoration: BoxDecoration(
        color: NovaColors.paperCard,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: NovaColors.borderOnLight),
        boxShadow: const [BoxShadow(offset: Offset(0, 30), blurRadius: 60, spreadRadius: -40, color: Color(0x730F141E))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _PriceBlock(price: price, size: 32),
          ),
          const SizedBox(height: 18),
          for (final String line in checks)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_rounded, size: 18, color: Color(0xFF12A150)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(line, style: _text(14, NovaColors.textBody, height: 1.45))),
                ],
              ),
            ),
          if (actions != null) ...[const SizedBox(height: 8), actions],
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.verified_user_outlined, size: 15, color: NovaColors.textMuted),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  context.tr(_free ? 'detail.freeNoPayment' : 'detail.secureNote'),
                  textAlign: TextAlign.center,
                  style: _text(12.5, NovaColors.textMuted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// "02 Keep exploring": three other published Units, as catalogue cards
  /// leading to their pages.
  List<Widget> _related(BuildContext context) {
    final List<Course> others = _app.catalog.courses.where((Course c) => c.id != _course!.id).take(3).toList();
    if (others.isEmpty) return const <Widget>[];
    return <Widget>[
      const SizedBox(height: 72),
      _SectionHead(number: '02', label: context.tr('detail.keepExploring'), title: context.tr('detail.otherUnits')),
      for (final Course course in others) ...[
        NovaProductCard.unit(
          context,
          course,
          width: double.infinity,
          onTap: () => _push(CourseDetailScreen(course: course)),
        ),
        const SizedBox(height: 16),
      ],
    ];
  }

  // The sticky bar ------------------------------------------------------------------------------------------------

  /// `.detailStickyBar`: the price and the main action, always at hand.
  Widget _stickyBar(BuildContext context, _Price price) {
    final bool narrow = MediaQuery.sizeOf(context).width <= 400;
    final Widget actions;
    if (_owned) {
      actions = _StickyButton(
        label: _isPack ? context.tr('detail.myUnits') : context.tr(_course!.isFree ? 'detail.accessUnit' : 'detail.openUnit'),
        narrow: narrow,
        onTap: _isPack ? _openMyUnits : _openCourse,
      );
    } else if (_outOfTrack) {
      actions = const SizedBox.shrink();
    } else if (_free) {
      actions = _StickyButton(
        label: context.tr(_busy ? 'detail.enrolling' : 'detail.joinFree'),
        narrow: narrow,
        free: true,
        onTap: _busy ? null : _joinFree,
      );
    } else if (_isPack || _course!.individualPurchaseEnabled || _coursePacks.isNotEmpty) {
      final bool added = _added;
      actions = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StickyCartButton(
            added: added,
            narrow: narrow,
            label: context.tr(added ? 'detail.added' : 'detail.cart'),
            onTap: _busy ? null : (_packOnly ? () => _choosePack(buy: false) : _addToCart),
          ),
          const SizedBox(width: 8),
          _StickyButton(
            label: context.tr('detail.buyNow'),
            narrow: narrow,
            onTap: _busy ? null : (_packOnly ? () => _choosePack(buy: true) : _buyNow),
          ),
        ],
      );
    } else {
      actions = _StickyButton(label: context.tr('detail.viewOffers'), narrow: narrow, onTap: () => _push(const OffersCatalogScreen()));
    }
    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + MediaQuery.paddingOf(context).bottom),
      decoration: BoxDecoration(
        color: NovaColors.paperCard.withValues(alpha: 0.95),
        border: Border(top: BorderSide(color: NovaColors.borderOnLight)),
        boxShadow: const [BoxShadow(offset: Offset(0, -14), blurRadius: 30, spreadRadius: -18, color: Color(0x59121A33))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(price.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: _baloo(narrow ? 10.5 : 13, NovaColors.textMuted, weight: FontWeight.w700)),
                const SizedBox(height: 1),
                Text(price.value, maxLines: 1, overflow: TextOverflow.ellipsis, style: _baloo(narrow ? 16 : 20, price.free ? NovaColors.onlineGreen : NovaColors.textStrong)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (_outOfTrack && !_owned)
            Flexible(
              flex: 2,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.block_rounded, size: 18, color: NovaColors.textMuted),
                  const SizedBox(width: 8),
                  Flexible(child: Text(context.tr('detail.outOfTrackTitle'), style: _baloo(14, NovaColors.textMuted))),
                ],
              ),
            )
          else
            actions,
        ],
      ),
    );
  }
}

// Shared text styles ----------------------------------------------------------------------------------------------

TextStyle _baloo(double size, Color color, {FontWeight weight = FontWeight.w800, double height = 1.3}) => TextStyle(
      fontFamily: NovaTypography.display,
      fontFamilyFallback: NovaTypography.fallback,
      fontWeight: weight,
      fontSize: size,
      height: height,
      color: color,
    );

TextStyle _text(double size, Color color, {double height = 1.5, FontWeight weight = FontWeight.w400}) => TextStyle(
      fontFamily: NovaTypography.body,
      fontFamilyFallback: NovaTypography.fallback,
      fontWeight: weight,
      fontSize: size,
      height: height,
      color: color,
    );

// Band pieces -----------------------------------------------------------------------------------------------------

/// `.nvBack` on the band: the arrow and "All units" in white.
class _BackLink extends StatelessWidget {
  const _BackLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      semanticLabel: label,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.arrow_back_rounded, size: 16, color: Color(0xE0FFFFFF)),
            const SizedBox(width: 8),
            Text(label, style: _baloo(16, const Color(0xE0FFFFFF))),
          ],
        ),
      ),
    );
  }
}

/// `.nvDetailBand .nvNotice`: white, the danger text, a bold lead.
class _BandNotice extends StatelessWidget {
  const _BandNotice({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: NovaDimens.shadowSticker,
      ),
      child: Text.rich(
        TextSpan(
          style: _text(14, NovaColors.heartRed, height: 1.55),
          children: <InlineSpan>[
            TextSpan(text: title, style: _baloo(14, NovaColors.heartRed, height: 1.55)),
            TextSpan(text: ' $text'),
          ],
        ),
      ),
    );
  }
}

/// `.nvDetailArt`: the cover on the `#EEF2FB` grid panel, in a white frame
/// turned 2°.
class _CoverFrame extends StatelessWidget {
  const _CoverFrame({required this.cover});

  final Widget cover;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) => Transform.rotate(
        angle: 2 * math.pi / 180,
        child: Container(
          width: math.min(box.maxWidth * 0.78, 420),
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
            borderRadius: BorderRadius.circular(20),
            child: AspectRatio(
              aspectRatio: 25 / 23,
              child: CustomPaint(painter: const _PanelGrid(), child: cover),
            ),
          ),
        ),
      ),
    );
  }
}

/// The `#EEF2FB` panel and its 44 px grid behind a poster.
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

/// `.novaCardTag` / `.novaCardBadge` on the cover.
class _CoverSticker extends StatelessWidget {
  const _CoverSticker({required this.label, this.yellow = false, this.live = false});

  final String label;
  final bool yellow;
  final bool live;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: yellow ? NovaColors.yellow : Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [BoxShadow(offset: Offset(0, 8), blurRadius: 18, spreadRadius: -10, color: Color(0x990A0E16))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (live) ...[
            Container(width: 7, height: 7, decoration: const BoxDecoration(color: Color(0xFFE5484D), shape: BoxShape.circle)),
            const SizedBox(width: 6),
          ],
          Text(label, style: _baloo(13.5, yellow ? NovaColors.yellowInk : NovaColors.ink, height: 1)),
        ],
      ),
    );
  }
}

enum _TagKind { plain, strong, free }

/// `.nvTag` on the band: white, yellow (`--strong`) or live green (`--free`).
class _Tag extends StatelessWidget {
  const _Tag(this.label, {this.kind = _TagKind.plain, this.icon});

  final String label;
  final _TagKind kind;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color ink) = switch (kind) {
      _TagKind.plain => (Colors.white, NovaColors.ink),
      _TagKind.strong => (NovaColors.yellow, NovaColors.yellowInk),
      _TagKind.free => (NovaColors.onlineGreen, Colors.white),
    };
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), boxShadow: NovaDimens.shadowSticker),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: ink), const SizedBox(width: 6)],
          Text(label, style: _baloo(15, ink, height: 1)),
        ],
      ),
    );
  }
}

/// `.nvTeacherChip`: the Teacher's photo or initials, "Teacher" and the name.
class _TeacherChip extends StatelessWidget {
  const _TeacherChip({required this.name, this.photo, this.onTap});

  final String name;
  final String? photo;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final String initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((String w) => w.isNotEmpty)
        .take(2)
        .map((String w) => w.substring(0, 1).toUpperCase())
        .join();
    return PressableScale(
      onTap: onTap,
      pressedScale: onTap == null ? 1 : 0.97,
      semanticLabel: name,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(6, 6, 18, 6),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: NovaDimens.shadowSticker),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              clipBehavior: Clip.antiAlias,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: Color(0xFFE9F0FF), shape: BoxShape.circle),
              child: photo == null
                  ? Text(initials, style: _text(13, NovaColors.ink, weight: FontWeight.w700, height: 1))
                  : Image(image: novaImageProvider(photo!, cacheWidth: 120), width: 40, height: 40, fit: BoxFit.cover, alignment: Alignment.topCenter),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(context.tr('detail.teacherLabel'), style: _baloo(13, const Color(0xFF6F7892), height: 1.2)),
                  const SizedBox(height: 2),
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _baloo(16, NovaColors.ink, height: 1.2)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `.nvDetailStats` on the band: two columns, a white rule above each
/// figure, yellow labels, white values (the saving in light green).
class _Stats extends StatelessWidget {
  const _Stats({required this.stats});

  final List<(String, String, bool)> stats;

  @override
  Widget build(BuildContext context) {
    final List<Widget> cells = <Widget>[
      for (final (String label, String value, bool saving) in stats)
        Container(
          padding: const EdgeInsets.only(top: 12),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0x3DFFFFFF)))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: _baloo(15, NovaColors.yellow)),
              const SizedBox(height: 6),
              Text(
                value,
                style: _baloo(value.length > 8 ? 16 : 25.6, saving ? const Color(0xFF7CF0AE) : Colors.white, height: 1.1),
              ),
            ],
          ),
        ),
    ];
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final double cell = (box.maxWidth - 22) / 2;
        return Wrap(
          spacing: 22,
          runSpacing: 14,
          children: [for (final Widget c in cells) SizedBox(width: cell, child: c)],
        );
      },
    );
  }
}

class _Price {
  const _Price({required this.label, required this.value, this.was, this.free = false});

  final String label;
  final String value;

  /// The crossed former total of an Offer.
  final String? was;
  final bool free;
}

/// `.nvPrice`: the small label, the price (green when free), the crossed
/// total.
class _PriceBlock extends StatelessWidget {
  const _PriceBlock({required this.price, this.size = 24});

  final _Price price;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(price.label, style: _baloo(15, NovaColors.textMuted)),
        const SizedBox(height: 3),
        Text(price.value, style: _baloo(size, price.free ? NovaColors.onlineGreen : NovaColors.textStrong, height: 1.1)),
        if (price.was != null) ...[
          const SizedBox(height: 3),
          Text(
            price.was!,
            style: _text(13, NovaColors.textMuted).copyWith(decoration: TextDecoration.lineThrough, decorationColor: NovaColors.textMuted),
          ),
        ],
      ],
    );
  }
}

/// `.nvBuyRow`: the white sticker under the figures with the price and the
/// actions (full width on phones).
class _BuyRow extends StatelessWidget {
  const _BuyRow({required this.price, required this.actions});

  final _Price price;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NovaColors.paperCard,
        borderRadius: BorderRadius.circular(NovaDimens.radiusTile),
        boxShadow: NovaDimens.shadowSticker,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 8),
            child: _PriceBlock(price: price),
          ),
          if (actions != null) ...[const SizedBox(height: 14), actions!],
        ],
      ),
    );
  }
}

enum _ButtonKind { blue, ghost, live }

/// The detail's buttons (`.buyNowButton`, `.addToCartButton`, `.primaryLink`,
/// `.freeEnrollButton`): radius 17, at least 54 high, 17 px Baloo 800, the
/// reading-direction arrow after the label.
class _DetailButton extends StatelessWidget {
  const _DetailButton({required this.label, required this.onTap, this.icon, this.kind = _ButtonKind.blue, this.arrow = true});

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final _ButtonKind kind;
  final bool arrow;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color ink, Color? line) = switch (kind) {
      _ButtonKind.blue => (NovaColors.accent, Colors.white, null),
      _ButtonKind.ghost => (Colors.transparent, NovaColors.textStrong, NovaColors.lineStrong),
      _ButtonKind.live => (NovaColors.onlineGreen, Colors.white, null),
    };
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: PressableScale(
        onTap: onTap,
        pressedScale: 0.97,
        semanticLabel: label,
        child: Container(
          constraints: const BoxConstraints(minHeight: 54),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(NovaDimens.radiusControl),
            border: Border.all(color: line ?? Colors.transparent),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: 18, color: ink), const SizedBox(width: 10)],
                Text(label, maxLines: 1, style: _baloo(17, ink, height: 1.2)),
                if (arrow) ...[const SizedBox(width: 10), Icon(Icons.arrow_forward_rounded, size: 18, color: ink)],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Body pieces -----------------------------------------------------------------------------------------------------

/// `.nvSectionHead`: the yellow number tile, the blue label, the title.
class _SectionHead extends StatelessWidget {
  const _SectionHead({required this.number, required this.label, required this.title});

  final String number;
  final String label;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Transform.rotate(
                angle: -4 * math.pi / 180,
                child: Container(
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: NovaColors.yellow, borderRadius: BorderRadius.circular(9)),
                  child: Text(number, style: _baloo(16, NovaColors.yellowInk, height: 1)),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(child: Text(label, style: _baloo(16, NovaColors.accent, height: 1.2))),
            ],
          ),
          const SizedBox(height: 14),
          Text(title, style: _text(28, NovaColors.textStrong, height: 1.3, weight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// `.nvLessons` / `.nvUnits`: rows between hairlines.
class _RuledList extends StatelessWidget {
  const _RuledList({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final BorderSide line = BorderSide(color: NovaColors.borderOnLight);
    return Container(
      decoration: BoxDecoration(border: Border(top: line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final Widget child in children)
            DecoratedBox(decoration: BoxDecoration(border: Border(bottom: line)), child: child),
        ],
      ),
    );
  }
}

/// A Lesson: its number, title, duration and Quiz / PDF chips; the
/// description opens under it.
class _LessonRow extends StatelessWidget {
  const _LessonRow({required this.index, required this.lesson, required this.open, required this.onToggle});

  final int index;
  final Lesson lesson;
  final bool open;
  final VoidCallback? onToggle;

  String _duration(BuildContext context) {
    final int seconds = lesson.durationSeconds > 0 ? lesson.durationSeconds : lesson.minutes * 60;
    if (seconds <= 0) return context.tr('detail.durationPending');
    final int hours = seconds ~/ 3600;
    final int minutes = ((seconds % 3600) / 60).round();
    return hours > 0
        ? context.trf('detail.durationHours', <String, String>{'h': '$hours', 'm': '$minutes'})
        : context.trf('detail.durationMinutes', <String, String>{'m': '$minutes'});
  }

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onToggle,
      pressedScale: 1,
      semanticLabel: lesson.title,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 34,
                  child: Text((index + 1).toString().padLeft(2, '0'), style: _baloo(15.5, NovaColors.textMuted, height: 1.4)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(lesson.title, style: _text(16.8, NovaColors.textStrong, height: 1.35, weight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(_duration(context), style: _text(13, NovaColors.textMuted)),
                          if (lesson.hasQuiz || lesson.quiz != null) _MiniChip(context.tr('detail.quizChip')),
                          if (lesson.hasPdf || lesson.pdf != null) _MiniChip(context.tr('detail.statPdf')),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 18,
                  child: onToggle == null
                      ? null
                      : AnimatedRotation(
                          turns: open ? 0.5 : 0,
                          duration: const Duration(milliseconds: 300),
                          child: Icon(Icons.expand_more_rounded, size: 18, color: NovaColors.textMuted),
                        ),
                ),
              ],
            ),
            ClipRect(
              child: AnimatedAlign(
                alignment: AlignmentDirectional.topStart,
                heightFactor: open ? 1 : 0,
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(top: 12, start: 46),
                  child: Text(lesson.description, style: _text(15, NovaColors.textBody, height: 1.65)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `.nvChipMini`: "Quiz", "PDF".
class _MiniChip extends StatelessWidget {
  const _MiniChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: NovaColors.current.isDark ? NovaColors.paperRaised : NovaColors.accentMist,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Center(widthFactor: 1, child: Text(label, style: _baloo(13.5, NovaColors.textBody, height: 1))),
    );
  }
}

enum _BadgeKind { plain, free, owned }

/// An Offer's Unit (`.miniCourseRow`): number, title, subject · Teacher,
/// its badge, the arrow.
class _UnitRow extends StatelessWidget {
  const _UnitRow({
    required this.index,
    required this.title,
    required this.meta,
    required this.badge,
    required this.badgeKind,
    required this.onTap,
  });

  final int index;
  final String title;
  final String meta;
  final String badge;
  final _BadgeKind badgeKind;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color ink) = switch (badgeKind) {
      _BadgeKind.plain => (NovaColors.current.isDark ? NovaColors.paperRaised : NovaColors.accentMist, NovaColors.textBody),
      _BadgeKind.free => (const Color(0xFFE5F6EC), const Color(0xFF0F7A3C)),
      _BadgeKind.owned => (NovaColors.textStrong, NovaColors.paperPublic),
    };
    return PressableScale(
      onTap: onTap,
      pressedScale: onTap == null ? 1 : 0.99,
      semanticLabel: title,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 34,
              child: Text((index + 1).toString().padLeft(2, '0'), style: _baloo(15.5, NovaColors.textMuted, height: 1.4)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: _text(16.8, NovaColors.textStrong, height: 1.35, weight: FontWeight.w600)),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(meta, style: _text(13, NovaColors.textMuted)),
                  ],
                  const SizedBox(height: 6),
                  Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(100)),
                    child: Center(widthFactor: 1, child: Text(badge, style: _text(12, ink, weight: FontWeight.w600, height: 1))),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              Directionality.of(context) == TextDirection.rtl ? Icons.north_west_rounded : Icons.north_east_rounded,
              size: 18,
              color: NovaColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

/// `.nvGuarantees` card: the round icon and one line.
class _Guarantee extends StatelessWidget {
  const _Guarantee({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: NovaColors.paperCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: NovaColors.borderOnLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: NovaColors.current.isDark ? NovaColors.paperRaised : NovaColors.accentMist,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: NovaColors.textStrong),
          ),
          const SizedBox(height: 14),
          Text(text, style: _text(15, NovaColors.textStrong)),
        ],
      ),
    );
  }
}

// Sticky bar pieces -----------------------------------------------------------------------------------------------

/// `.stickyBuyBtn` / `.stickyPrimaryBtn` / `.stickyFreeBtn`: 48 high,
/// radius 14, the label and its arrow.
class _StickyButton extends StatelessWidget {
  const _StickyButton({required this.label, required this.narrow, required this.onTap, this.free = false});

  final String label;
  final bool narrow;
  final VoidCallback? onTap;
  final bool free;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: PressableScale(
        onTap: onTap,
        pressedScale: 0.96,
        semanticLabel: label,
        child: Container(
          height: 48,
          padding: EdgeInsets.symmetric(horizontal: narrow ? 12 : 18),
          decoration: BoxDecoration(
            color: free ? const Color(0xFF047857) : NovaColors.accent,
            borderRadius: BorderRadius.circular(14),
            boxShadow: free ? null : const [BoxShadow(offset: Offset(0, 10), blurRadius: 20, spreadRadius: -12, color: Color(0xCC1F54D6))],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: _baloo(narrow ? 13 : 16, Colors.white, height: 1.2)),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_rounded, size: narrow ? 15 : 17, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.stickyCartBtn`: the bag (a check once added); its word hides on
/// narrow phones, as on the website.
class _StickyCartButton extends StatelessWidget {
  const _StickyCartButton({required this.added, required this.narrow, required this.label, required this.onTap});

  final bool added;
  final bool narrow;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color ink = added ? NovaColors.onlineGreen : NovaColors.textStrong;
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: PressableScale(
        onTap: onTap,
        pressedScale: 0.94,
        semanticLabel: context.tr(added ? 'detail.addedToCart' : 'detail.addToCart'),
        child: Container(
          height: 48,
          constraints: const BoxConstraints(minWidth: 48),
          padding: EdgeInsets.symmetric(horizontal: narrow ? 10 : 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: added ? NovaColors.liveBg : NovaColors.paperCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: added ? Colors.transparent : NovaColors.lineStrong),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(added ? Icons.check_rounded : Icons.shopping_bag_outlined, size: 16, color: ink),
              if (!narrow) ...[const SizedBox(width: 6), Text(label, style: _baloo(15, ink, weight: FontWeight.w700))],
            ],
          ),
        ),
      ),
    );
  }
}
