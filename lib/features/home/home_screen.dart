import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/widgets/hero_style.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/nova_page_header.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../data/models.dart';
import '../auth/auth_routes.dart';
import '../catalog/offers_catalog_screen.dart';
import '../catalog/units_catalog_screen.dart';
import '../detail/course_detail_screen.dart';
import '../learning/live_room_screen.dart';
import '../learning/open_course.dart';
import '../shell/shell_screen.dart';
import '../shell/student_top_bar.dart';
import 'widgets/nova_product_card.dart';

/// What the Home shows, by the website's rules (`AccountHome`,
/// `profile.tsx`): the Student's Units first, then catalogue Units cut to
/// fill rows of three (six cards at least); their Offers first, then enough
/// others to fill rows of three. An Offer whose Units are all paid but that
/// the Student does not hold is "covered" (nothing left to buy in it).
class HomeSelection {
  const HomeSelection._({required this.ownedUnits, required this.otherUnits, required this.ownedOffers, required this.otherOffers});

  /// [owned] are the Student's Units (access grants), [catalogue] the Units
  /// and [offers] the Offers of their level. [ownedOfferIds] is
  /// `owned_offer_ids` of `/access-grants` (D-086); without it an Offer is
  /// the Student's when all its Units are paid (the website's rule for
  /// payloads without the list).
  factory HomeSelection.of({
    required List<Course> owned,
    required List<Course> catalogue,
    required List<Pack> offers,
    Set<int>? ownedOfferIds,
  }) {
    int fullRows(int value) => (value / 3).ceil() * 3;
    final Set<int> ownedIds = owned.map((Course c) => c.id).toSet();
    // Only paid access (never a free enrolment) covers an Offer's Units.
    final Set<int> paidIds = owned.where((Course c) => !c.isFree).map((Course c) => c.id).toSet();
    bool covered(Pack pack) => pack.items.isNotEmpty && pack.items.every((PackItem item) => paidIds.contains(item.courseId));
    bool holds(Pack pack) => ownedOfferIds == null ? covered(pack) : ownedOfferIds.contains(pack.id);

    // The others are catalogue cards, never "Purchased".
    final List<Course> others = <Course>[
      for (final Course c in catalogue)
        if (!ownedIds.contains(c.id)) c.owned ? c.copyWith(owned: false) : c,
    ];
    final List<Pack> ownedOffers = offers.where(holds).toList();
    final List<Pack> otherOffers = offers.where((Pack p) => !holds(p)).toList();
    return HomeSelection._(
      ownedUnits: owned,
      otherUnits: others.take(math.max(0, fullRows(math.max(owned.length + 3, 6)) - owned.length)).toList(),
      ownedOffers: ownedOffers,
      otherOffers: <(Pack, bool)>[
        for (final Pack pack in otherOffers.take(fullRows(ownedOffers.length + 3) - ownedOffers.length)) (pack, covered(pack)),
      ],
    );
  }

  final List<Course> ownedUnits;
  final List<Course> otherUnits;
  final List<Pack> ownedOffers;

  /// The other Offers, each with whether it is covered.
  final List<(Pack, bool)> otherOffers;

  bool get hasUnits => ownedUnits.isNotEmpty || otherUnits.isNotEmpty;
  bool get hasOffers => ownedOffers.isNotEmpty || otherOffers.isNotEmpty;
}

/// The website's account home (`/account`, D-084/D-125): the greeting band
/// with "Continue learning" and "See the Offers", the live-now bar while one
/// of the Student's Lives runs (or its waiting room is open), then the Units
/// (theirs first) and the Offers, each a row of swipeable cards.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState app = AppScope.of(context);
    final StudentProfile? student = app.profile;
    // D-134: a visitor browsing without an account.
    final bool guest = !app.session.signedIn;
    // The grants' Units, with the catalogue's details when it lists them.
    final Map<int, Course> listed = <int, Course>{for (final Course c in app.courses) c.id: c};
    final HomeSelection home = HomeSelection.of(
      owned: <Course>[
        if (!guest)
          for (final Course c in app.learning.owned) listed[c.id]?.copyWith(owned: true) ?? c,
      ],
      catalogue: app.catalog.courses,
      offers: app.catalog.offers,
      ownedOfferIds: guest ? null : app.learning.ownedOfferIds,
    );
    // D-110: an open waiting room counts too: the Student goes in early.
    final LiveSession? liveNow = guest
        ? null
        : app.learning.lives
            .where((LiveSession l) => l.status == LiveStatus.live || (l.rawStatus == 'scheduled' && l.waitingRoomOpen))
            .firstOrNull;
    final double cardWidth = (MediaQuery.sizeOf(context).width - 28) * 0.84;

    return RefreshIndicator(
      onRefresh: () => Future.wait(<Future<void>>[app.catalog.load(), if (!guest) app.refreshAccount()]),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 130),
        children: [
          NovaPageHeader(
            showBack: false,
            kicker: guest ? context.tr('guest.eyebrow') : _today(context),
            title: guest
                ? context.tr('guest.homeTitle')
                : student == null || student.firstName.isEmpty
                    ? context.tr('home.greetingGeneric')
                    : context.trf('home.greeting', {'name': student.firstName}),
            lead: context.tr(guest ? 'guest.homeText' : 'home.lead'),
            // `.hxHeadActions`: each button at its own width, side by side
            // while they fit.
            bottom: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (guest)
                  NovaButton(
                    label: context.tr('gateway.registerCta'),
                    variant: NovaButtonVariant.yellow,
                    chipIcon: Icons.arrow_forward_rounded,
                    onTap: () => openRegistration(context),
                  )
                else
                  NovaButton(
                    label: context.tr('home.continue'),
                    variant: NovaButtonVariant.yellow,
                    chipIcon: Icons.arrow_forward_rounded,
                    onTap: () => ShellNav.maybeOf(context)?.select(ShellScreen.units),
                  ),
                NovaButton(
                  label: context.tr('home.seeOffers'),
                  variant: NovaButtonVariant.onBlueGhost,
                  onTap: () => _push(context, const OffersCatalogScreen()),
                ),
              ],
            ),
          ),
          // `.studentHead` is 18 px above the page; its parts are 30 px apart.
          if (liveNow != null) ...[
            const SizedBox(height: 18),
            _LiveNowBar(live: liveNow),
          ],
          if (home.hasUnits) ...[
            SizedBox(height: liveNow == null ? 18 : 30),
            _SectionHead(
              title: context.tr('home.unitsTitle'),
              text: home.ownedUnits.isNotEmpty ? context.tr('home.unitsTextOwned') : context.tr('home.unitsText'),
              action: context.tr('home.allUnits'),
              onAction: () => _push(context, const UnitsCatalogScreen()),
            ),
            const SizedBox(height: 18),
            _Rail(
              itemWidth: cardWidth,
              children: [
                for (final Course course in home.ownedUnits)
                  NovaProductCard.unit(context, course, width: cardWidth, onTap: () => openOwnedCourse(context, course)),
                for (final Course course in home.otherUnits)
                  NovaProductCard.unit(context, course, width: cardWidth, onTap: () => _push(context, CourseDetailScreen(course: course))),
              ],
            ),
          ],
          if (home.hasOffers) ...[
            SizedBox(height: liveNow == null && !home.hasUnits ? 18 : 30),
            _SectionHead(
              title: context.tr('home.offersTitle'),
              text: home.ownedOffers.isNotEmpty ? context.tr('home.offersTextOwned') : context.tr('home.offersText'),
              action: context.tr('home.allOffers'),
              onAction: () => _push(context, const OffersCatalogScreen()),
            ),
            const SizedBox(height: 18),
            _Rail(
              itemWidth: cardWidth,
              children: [
                for (final Pack pack in home.ownedOffers)
                  NovaProductCard.offer(
                    context,
                    pack,
                    width: cardWidth,
                    ownership: OfferOwnership.owned,
                    onTap: () => _push(context, CourseDetailScreen.pack(pack: pack)),
                    onAction: () => ShellNav.maybeOf(context)?.select(ShellScreen.units),
                  ),
                for (final (Pack pack, bool covered) in home.otherOffers)
                  NovaProductCard.offer(
                    context,
                    pack,
                    width: cardWidth,
                    ownership: covered ? OfferOwnership.covered : OfferOwnership.none,
                    onTap: () => _push(context, CourseDetailScreen.pack(pack: pack)),
                    onAction: covered ? () => ShellNav.maybeOf(context)?.select(ShellScreen.units) : null,
                  ),
              ],
            ),
          ],
          if (!home.hasUnits && !home.hasOffers) ...[
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: HeroEmpty(
                icon: Icons.menu_book_outlined,
                title: context.tr('home.emptyTitle'),
                message: context.tr('home.emptyText'),
                action: NovaButton(
                  label: context.tr('home.seeOffers'),
                  chipIcon: Icons.arrow_forward_rounded,
                  onTap: () => _push(context, const OffersCatalogScreen()),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static void _push(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  /// The website's eyebrow (`Intl.DateTimeFormat` with `ar-DZ`, `fr-DZ`,
  /// `en-US`: weekday, day, month), Algeria time: "الأحد، 11 أكتوبر",
  /// "dimanche 11 octobre", "Sunday, October 11".
  static String _today(BuildContext context) {
    final DateTime now = algeriaTime(clock.now());
    final NovaLang lang = AppScope.of(context).lang;
    const Map<NovaLang, List<String>> days = <NovaLang, List<String>>{
      NovaLang.ar: <String>['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'],
      NovaLang.fr: <String>['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'],
      NovaLang.en: <String>['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'],
    };
    const Map<NovaLang, List<String>> months = <NovaLang, List<String>>{
      NovaLang.ar: <String>['جانفي', 'فيفري', 'مارس', 'أفريل', 'ماي', 'جوان', 'جويلية', 'أوت', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'],
      NovaLang.fr: <String>['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'],
      NovaLang.en: <String>['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'],
    };
    final String day = days[lang]![now.weekday - 1];
    final String month = months[lang]![now.month - 1];
    return switch (lang) {
      NovaLang.en => '$day, $month ${now.day}',
      NovaLang.ar => '$day، ${now.day} $month',
      NovaLang.fr => '$day ${now.day} $month',
    };
  }
}

/// `.homeSectionHead` on phones: the 22 px title, one ink-2 line, then the
/// white "All …" pill with its sky arrow.
class _SectionHead extends StatelessWidget {
  const _SectionHead({required this.title, required this.text, required this.action, required this.onAction});

  final String title;
  final String text;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontFamily: NovaTypography.display,
              fontFamilyFallback: NovaTypography.fallback,
              fontWeight: FontWeight.w800,
              fontSize: 22,
              height: 1.15,
              color: NovaColors.textStrong,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            text,
            style: TextStyle(
              fontFamily: NovaTypography.body,
              fontFamilyFallback: NovaTypography.fallback,
              fontSize: 15.5,
              height: 1.5,
              color: NovaColors.textBody,
            ),
          ),
          const SizedBox(height: 16),
          PressableScale(
            onTap: onAction,
            semanticLabel: action,
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: NovaColors.paperCard,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: NovaColors.borderOnLight),
                boxShadow: const [BoxShadow(offset: Offset(0, 8), blurRadius: 20, color: Color(0x0D28313B))],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    action,
                    style: TextStyle(
                      fontFamily: NovaTypography.display,
                      fontFamilyFallback: NovaTypography.fallback,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      height: 1.2,
                      color: NovaColors.accent,
                    ),
                  ),
                  const SizedBox(width: 7),
                  const Icon(Icons.arrow_forward_rounded, size: 15, color: NovaColors.skyStrong),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `.accountHome .enrolledCourseGrid` on phones: one swipeable row, cards
/// 84 % wide and 12 px apart, snapping to the 14 px edge; the cards of a
/// row share one height.
class _Rail extends StatelessWidget {
  const _Rail({required this.itemWidth, required this.children});

  final double itemWidth;
  final List<Widget> children;

  static const double _gap = 12;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: _SnapPhysics(extent: itemWidth + _gap),
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (int i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: _gap),
              Entrance(delay: Duration(milliseconds: 60 * i), child: children[i]),
            ],
          ],
        ),
      ),
    );
  }
}

/// `scroll-snap-type: x mandatory`: a swipe settles on a card's start.
class _SnapPhysics extends ScrollPhysics {
  const _SnapPhysics({required this.extent, super.parent});

  final double extent;

  @override
  _SnapPhysics applyTo(ScrollPhysics? ancestor) => _SnapPhysics(extent: extent, parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    if ((velocity <= 0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final Tolerance tolerance = toleranceFor(position);
    double page = position.pixels / extent;
    if (velocity < -tolerance.velocity) {
      page -= 0.5;
    } else if (velocity > tolerance.velocity) {
      page += 0.5;
    }
    final double target = (page.roundToDouble() * extent).clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - position.pixels).abs() < tolerance.distance) return null;
    return ScrollSpringSimulation(spring, position.pixels, target, velocity, tolerance: tolerance);
  }

  @override
  bool get allowImplicitScrolling => false;
}

/// `.homeLiveNow`: the hero's blue with a pulsing dot, "Your live class is
/// on now" (or "The waiting room is open"), the Live and its Unit, and the
/// yellow "Join live" button, full width on phones.
class _LiveNowBar extends StatelessWidget {
  const _LiveNowBar({required this.live});

  final LiveSession live;

  @override
  Widget build(BuildContext context) {
    final bool waiting = live.status != LiveStatus.live;
    final bool dark = NovaColors.current.isDark;
    void open() => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LiveRoomScreen(live: live)));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: PressableScale(
        onTap: open,
        semanticLabel: live.title,
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 14, 16, 14),
          decoration: BoxDecoration(
            color: NovaColors.accent,
            gradient: RadialGradient(
              center: const Alignment(-0.8, -0.6),
              radius: 0.9,
              colors: <Color>[Color.alphaBlend(const Color(0x736CA0FF), NovaColors.accent), NovaColors.accent],
              stops: const <double>[0, 0.7],
            ),
            borderRadius: BorderRadius.circular(24),
            border: dark ? Border.all(color: const Color(0xFF2B323C)) : null,
            boxShadow: const [BoxShadow(offset: Offset(0, 18), blurRadius: 36, spreadRadius: -20, color: Color(0xE61F54D6))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const _Pulse(),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr(waiting ? 'home.waitingRoom' : 'home.liveNow'),
                          style: const TextStyle(
                            fontFamily: NovaTypography.display,
                            fontFamilyFallback: NovaTypography.fallback,
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                            height: 1.3,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          live.course.isEmpty ? live.title : '${live.title} · ${live.course}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: NovaTypography.body,
                            fontFamilyFallback: NovaTypography.fallback,
                            fontSize: 14.5,
                            height: 1.35,
                            color: Color(0xDBFFFFFF),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: NovaColors.yellow, borderRadius: BorderRadius.circular(13)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.tr('home.joinLive'),
                      style: const TextStyle(
                        fontFamily: NovaTypography.display,
                        fontFamilyFallback: NovaTypography.fallback,
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                        height: 1.2,
                        color: NovaColors.yellowInk,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.arrow_forward_rounded, size: 15, color: NovaColors.yellowInk),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.homeLiveDot`: `#FF5D5D` with a fading ring (`homeLivePulse`, 1.8 s).
class _Pulse extends StatefulWidget {
  const _Pulse();

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 22,
      child: AnimatedBuilder(
        animation: _c,
        builder: (BuildContext context, _) {
          // The ring grows to 9 px and fades out over the first 70 %.
          final double t = (_c.value / 0.7).clamp(0.0, 1.0);
          return Center(
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: const Color(0xFFFF5D5D),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(spreadRadius: 9 * t, color: const Color(0xFFFF5D5D).withValues(alpha: 0.55 * (1 - t)))],
              ),
            ),
          );
        },
      ),
    );
  }
}
