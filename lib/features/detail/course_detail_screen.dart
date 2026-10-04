import 'package:flutter/material.dart';

import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/utils/format_price.dart';
import '../../core/widgets/circle_icon_button.dart';
import '../../core/i18n/labels.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/widgets/motion.dart';
import '../../core/theme/nova_dimens.dart';
import '../../core/widgets/nova_decor.dart';
import '../../core/widgets/nova_scene_image.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/pressable_scale.dart';
import '../cart/checkout_screen.dart';
import '../../data/models.dart';
import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/widgets/nova_toast.dart';
import '../learning/open_course.dart';
import 'pack_picker.dart';

/// Course detail (and Offer detail via `.pack`): hero, description,
/// curriculum accordion, purchase card with the add-to-cart / buy-now
/// pair and the "already owned" state that opens the course instead.
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
  int _openLesson = 0;

  bool get _isPack => _pack != null;
  AppState get _app => AppScope.of(context);
  String get _title => _isPack ? _pack!.name : _course!.title;
  NovaScene get _scene => _isPack ? _pack!.scene : _course!.scene;
  IconData get _icon => _isPack ? _pack!.icon : _course!.icon;
  String? get _image => _isPack ? _pack!.image : _course!.image;
  int get _price => _isPack
      ? _pack!.price
      : _packOnly
          ? (_course!.offerPriceFrom ?? 0)
          : _course!.price;
  int get _compareAt => _isPack
      ? _pack!.compareAtPrice
      : _packOnly
          ? _price
          : _course!.compareAtPrice;
  bool get _owned => !_isPack && _app.learning.owns(_course!.id);
  bool get _free => !_isPack && _course!.isFree;

  /// D-091: a paid Unit never sold on its own; Buy and Add put one of its
  /// Packs in the cart (the Student picks one when there are several).
  bool get _packOnly => !_isPack && _course!.packOnly;
  List<CoursePack> get _coursePacks => _isPack ? const <CoursePack>[] : _course!.packs;
  bool get _purchasable =>
      _isPack || _course!.individualPurchaseEnabled || (_packOnly && _coursePacks.isNotEmpty);

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _DetailHero(
                  title: _title,
                  scene: _scene,
                  image: _image,
                  icon: _icon,
                  kicker: _isPack ? offerTypeText(context, _pack!) : _course!.subject,
                  kind: _isPack
                      ? context.tr('detail.offer')
                      : context.tr('detail.course'),
                  stats: _isPack ? _packStats() : _courseStats(),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isPack ? _pack!.description : _course!.description,
                        style: NovaTypography.textTheme.bodyMedium!.copyWith(
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (_isPack)
                        ..._buildPackContent()
                      else
                        ..._buildCourseContent(),
                      const SizedBox(height: 20),
                      if (_outOfTrack) ...[
                        _OutOfTrackNotice(pack: _isPack),
                        const SizedBox(height: 16),
                      ],
                      _buildPurchaseCard(context),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _BottomBar(
            // Several Packs: the price is the one the Student picks.
            price: _packOnly && _coursePacks.length != 1 ? 0 : _price,
            compareAt: _compareAt,
            owned: _owned,
            free: _free,
            busy: _busy,
            purchasable: _purchasable,
            packOnly: _packOnly,
            outOfTrack: _outOfTrack,
            added: _added,
            onAdd: _packOnly ? () => _choosePack(buy: false) : _addToCart,
            onBuy: _packOnly ? () => _choosePack(buy: true) : _buyNow,
            onJoinFree: _joinFree,
            onOpen: _openCourse,
          ),
        ],
      ),
    );
  }

  void _openCourse() => openOwnedCourse(context, _course!);

  List<String> _courseStats() {
    final Course course = _course!;
    return <String>[
      context.trf('detail.lessonsStat', {'n': course.lessonsCount.toString()}),
      context.trf('detail.livesStat', {'n': course.plannedLives.toString()}),
      context.trf('common.prof', {'name': course.teacher}),
    ];
  }

  List<String> _packStats() {
    final Pack pack = _pack!;
    return <String>[
      context.trf('detail.coursesStat', {'n': pack.courseCount.toString()}),
      context.trf('detail.lessonsStat', {'n': pack.lessonsCount.toString()}),
      if (pack.discountPercent > 0)
        context.trf('detail.save', {'n': pack.discountPercent.toString()}),
    ];
  }

  List<Widget> _buildCourseContent() {
    final Course course = _course!;
    return [
      Text(context.tr('detail.insideCourse'),
          style: NovaTypography.textTheme.headlineSmall),
      const SizedBox(height: 12),
      ...stagger(
        course.lessons
            .asMap()
            .entries
            .map(
              (MapEntry<int, Lesson> entry) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _LessonAccordionTile(
                  index: entry.key,
                  lesson: entry.value,
                  open: _openLesson == entry.key,
                  onToggle: () =>
                      setState(() => _openLesson = _openLesson == entry.key ? -1 : entry.key),
                ),
              ),
            )
            .toList(),
      ),
    ];
  }

  List<Widget> _buildPackContent() {
    final Pack pack = _pack!;
    return [
      Text(context.tr('detail.included'),
          style: NovaTypography.textTheme.headlineSmall),
      const SizedBox(height: 12),
      ...stagger(
        pack.items
            .map(
              (PackItem item) {
                final bool ownedCourse = _app.learning.owns(item.courseId);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: NovaCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.courseTitle,
                                style: NovaTypography.textTheme.titleSmall,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                ownedCourse
                                    ? context.tr('detail.purchasedCredited')
                                    : <String>[item.subject, item.teacher]
                                        .where((String s) => s.isNotEmpty)
                                        .join(' · '),
                                style: NovaTypography.muted(
                                  NovaTypography.textTheme.bodySmall!,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          ownedCourse
                              ? Icons.check_circle_rounded
                              : Icons.workspace_premium_rounded,
                          size: 20,
                          color: ownedCourse
                              ? NovaColors.accent
                              : NovaColors.textMuted,
                        ),
                      ],
                    ),
                  ),
                );
              },
            )
            .toList(),
      ),
      const SizedBox(height: 6),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: NovaColors.accentMist,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            const Icon(Icons.verified_rounded,
                size: 20, color: NovaColors.accentDeep),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.tr('detail.overlapNote'),
                style: NovaTypography.textTheme.bodySmall!.copyWith(
                  color: NovaColors.accentDeep,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _buildPurchaseCard(BuildContext context) {
    final bool packPriceKnown = _packOnly && _course!.offerPriceFrom != null;
    return NovaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (packPriceKnown)
            Text(
              context.tr('detail.packsFrom'),
              style: NovaTypography.muted(NovaTypography.textTheme.labelMedium!),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _free
                    ? context.tr('common.free')
                    : _packOnly && !packPriceKnown
                        ? context.tr('detail.packsOnly')
                        : formatDaPrice(_price),
                style: NovaTypography.textTheme.displaySmall,
              ),
              if (!_free && _compareAt > _price) ...[
                const SizedBox(width: 8),
                Text(
                  formatDaPrice(_compareAt),
                  style: NovaTypography.textTheme.bodyMedium!.copyWith(
                    decoration: TextDecoration.lineThrough,
                    decorationColor: NovaColors.textMuted,
                  ),
                ),
              ],
            ],
          ),
          if (_packOnly && _coursePacks.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.layers_rounded, size: 16, color: NovaColors.accentDeep),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    _coursePacks.length == 1
                        ? context.trf('detail.soldInPack', <String, String>{'title': _coursePacks.single.title})
                        : context.trf('detail.soldInPacks', <String, String>{'count': '${_coursePacks.length}'}),
                    style: NovaTypography.textTheme.bodySmall!.copyWith(
                      color: NovaColors.accentDeep,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          ...[
            context.tr('detail.checklist1'),
            context.tr('detail.checklist2'),
            context.tr('detail.checklist3'),
          ].map(
            (String line) => Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                children: [
                  const Icon(Icons.check_rounded,
                      size: 17, color: NovaColors.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      line,
                      style: NovaTypography.textTheme.bodySmall!.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.tr('detail.secureNote'),
            style: NovaTypography.muted(NovaTypography.textTheme.labelSmall!),
          ),
        ],
      ),
    );
  }
}

/// Immersive cover: the artwork runs to the edges, the back button
/// floats on it, and the kind, title and headline stats sit over a
/// scrim so they stay readable whatever the scene.
class _DetailHero extends StatelessWidget {
  const _DetailHero({
    required this.title,
    required this.scene,
    this.image,
    required this.icon,
    required this.kicker,
    required this.kind,
    required this.stats,
  });

  final String title;
  final NovaScene scene;

  /// Poster photo; the painted [scene] stands in when absent.
  final String? image;
  final IconData icon;

  /// Subject (course) or offer type (pack).
  final String kicker;

  /// "Course" / "Offer" — what the page is showing.
  final String kind;
  final List<String> stats;

  @override
  Widget build(BuildContext context) {
    final double topInset = MediaQuery.paddingOf(context).top;

    return Container(
      height: 320 + topInset,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(NovaDimens.radiusCardLarge),
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Hero(
            tag: 'cover-$title',
            child: NovaSceneImage(scene: scene, image: image),
          ),
          // Placed by hand rather than through the scene so it clears
          // both the button row above and the title below.
          if (image == null)
            Positioned(
            right: -12,
            top: topInset + 52,
            child: Icon(
              icon,
              size: 124,
              color: Colors.white.withValues(alpha: 0.22),
            ),
          ),
          if (image == null)
            const Positioned.fill(
            child: NovaDecor(color: Colors.white, opacity: 0.2, seed: 2),
          ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.3, 1],
                  colors: [Colors.transparent, Color(0xD9131F3A)],
                ),
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            top: topInset + 14,
            child: Row(
              children: [
                FrostedIconButton(
                  icon: Icons.arrow_back_rounded,
                  semanticLabel: context.tr('common.back'),
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    kind.toUpperCase(),
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                      letterSpacing: 1.8,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Sparkle(size: 12),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        kicker.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                          letterSpacing: 2.2,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: NovaTypography.textTheme.displaySmall!.copyWith(
                    color: Colors.white,
                    height: 1.08,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: stats
                      .map((String stat) => _FrostedStat(stat))
                      .toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FrostedStat extends StatelessWidget {
  const _FrostedStat(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w600,
          fontSize: 11.5,
          color: Colors.white,
        ),
      ),
    );
  }
}


class _LessonAccordionTile extends StatelessWidget {
  const _LessonAccordionTile({
    required this.index,
    required this.lesson,
    required this.open,
    required this.onToggle,
  });

  final int index;
  final Lesson lesson;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onToggle,
      pressedScale: 0.985,
      semanticLabel: 'Lesson ${index + 1}: ${lesson.title}',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: NovaColors.paperCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: open ? NovaColors.accent : NovaColors.borderOnLight,
            width: open ? 1.4 : 1,
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  (index + 1).toString().padLeft(2, '0'),
                  style: NovaTypography.textTheme.titleSmall!.copyWith(
                    color: NovaColors.accent,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    lesson.title,
                    style: NovaTypography.textTheme.titleSmall,
                  ),
                ),
                AnimatedRotation(
                  turns: open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 240),
                  child: Icon(
                    Icons.expand_more_rounded,
                    size: 20,
                    color: NovaColors.textMuted,
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
                  padding: const EdgeInsetsDirectional.only(top: 10, start: 30),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${context.trf('detail.lessonVideo', {'n': lesson.minutes.toString()})}'
                        '${lesson.pdf != null ? ' ${context.tr('detail.pdfSheet')}' : ''}'
                        '${lesson.quiz != null ? ' ${context.tr('detail.quizCheckpoint')}' : ''}',
                        style: NovaTypography.muted(
                          NovaTypography.textTheme.bodySmall!,
                        ),
                      ),
                      if (lesson.quiz != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          lesson.quiz!.required
                              ? 'Required quiz · ${lesson.quiz!.passingScore}% to pass'
                              : 'Optional quiz',
                          style: NovaTypography.textTheme.bodySmall!.copyWith(
                            color: NovaColors.accentDeep,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sticky purchase bar fixed above the safe area.
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.price,
    required this.compareAt,
    required this.owned,
    required this.free,
    required this.busy,
    required this.purchasable,
    this.packOnly = false,
    required this.outOfTrack,
    required this.added,
    required this.onAdd,
    required this.onBuy,
    required this.onJoinFree,
    required this.onOpen,
  });

  /// Not for the Student's level or filière (D-083): nothing to buy or join.
  final bool outOfTrack;

  final int price;
  final int compareAt;
  final bool owned;

  /// A free Course (D-054): joined, never bought.
  final bool free;

  /// A cart or enrolment request is in flight.
  final bool busy;
  final bool purchasable;

  /// D-091: Add puts a Pack in the cart.
  final bool packOnly;
  final bool added;
  final VoidCallback onAdd;
  final VoidCallback onBuy;
  final VoidCallback onJoinFree;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    if (owned) {
      return _BarContainer(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(context.tr('detail.ownedTitle'), style: NovaTypography.textTheme.titleSmall),
                  Text(
                    context.tr('detail.ownedSub'),
                    style: NovaTypography.muted(
                      NovaTypography.textTheme.bodySmall!,
                    ),
                  ),
                ],
              ),
            ),
            CircleIconButton(
              icon: Icons.play_arrow_rounded,
              dark: true,
              semanticLabel: 'Open course',
              onTap: onOpen,
            ),
          ],
        ),
      );
    }

    if (outOfTrack) {
      return _BarContainer(
        child: Row(
          children: [
            Icon(Icons.block_rounded, size: 20, color: NovaColors.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.tr('detail.outOfTrackTitle'),
                style: NovaTypography.textTheme.titleSmall!.copyWith(
                  color: NovaColors.textMuted,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (free) {
      return _BarContainer(
        child: PressableScale(
          onTap: busy ? null : onJoinFree,
          pressedScale: 0.97,
          semanticLabel: context.tr('detail.joinFree'),
          child: Container(
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: NovaColors.accentGradient,
              borderRadius: BorderRadius.circular(100),
            ),
            child: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    context.tr('detail.joinFree'),
                    style: NovaTypography.textTheme.labelLarge!
                        .copyWith(color: Colors.white),
                  ),
          ),
        ),
      );
    }

    if (!purchasable) {
      return _BarContainer(
        child: Row(
          children: [
            Icon(Icons.lock_outline_rounded,
                size: 20, color: NovaColors.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.tr('detail.offersOnly'),
                style: NovaTypography.textTheme.titleSmall!.copyWith(
                  color: NovaColors.textMuted,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return _BarContainer(
      child: Row(
        children: [
          Expanded(
            child: PressableScale(
              onTap: busy ? null : onAdd,
              pressedScale: 0.96,
              semanticLabel: added ? 'Added to cart' : 'Add to cart',
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: added ? NovaColors.accentMist : NovaColors.paperCard,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: added ? NovaColors.accent : NovaColors.borderOnLight,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOutBack,
                      child: Icon(
                        added
                            ? Icons.check_rounded
                            : Icons.add_shopping_cart_rounded,
                        key: ValueKey<bool>(added),
                        size: 19,
                        color:
                            added ? NovaColors.accent : NovaColors.textStrong,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        added
                            ? context.tr('detail.added')
                            : context.tr(packOnly ? 'detail.addPack' : 'detail.addToCart'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: NovaTypography.textTheme.labelLarge,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: PressableScale(
              onTap: busy ? null : onBuy,
              pressedScale: 0.96,
              semanticLabel: 'Buy now',
              child: Container(
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: NovaColors.ink950,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        context.tr('detail.buyNow'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: NovaTypography.textTheme.labelLarge!.copyWith(color: NovaColors.textOnDark),
                      ),
                    ),
                    // Several Packs (D-091): the price is the one picked.
                    if (!packOnly || price > 0) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          formatDaPrice(price),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.fade,
                          style: NovaTypography.textTheme.labelLarge!.copyWith(
                            color: NovaColors.textMutedOnDark,
                          ),
                        ),
                      ),
                    ],
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

/// The website's "Not available for your level or track" notice, naming the
/// Student's own level and filière.
class _OutOfTrackNotice extends StatelessWidget {
  const _OutOfTrackNotice({required this.pack});

  final bool pack;

  @override
  Widget build(BuildContext context) {
    final StudentProfile? me = AppScope.of(context).session.profile;
    final String profile = <String>[me?.level ?? '', me?.track ?? '']
        .where((String part) => part.isNotEmpty)
        .join(' · ');
    final String text = context
        .tr(pack ? 'detail.outOfTrackOffer' : 'detail.outOfTrackCourse')
        .replaceAll(' ({profile})', profile.isEmpty ? '' : ' ($profile)');
    final NovaHue hue = NovaHue.rose;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: hue.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: hue.solid.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 19, color: hue.onSurface),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('detail.outOfTrackTitle'),
                  style: NovaTypography.textTheme.titleSmall!.copyWith(
                    color: hue.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  text,
                  style: NovaTypography.textTheme.bodySmall!.copyWith(
                    color: hue.onSurface,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BarContainer extends StatelessWidget {
  const _BarContainer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: NovaColors.paper,
        border: Border(top: BorderSide(color: NovaColors.borderOnLight)),
        boxShadow: const [
          BoxShadow(
            offset: Offset(0, -14),
            blurRadius: 30,
            spreadRadius: -12,
            color: Color(0x220A1128),
          ),
        ],
      ),
      child: child,
    );
  }
}
