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
import '../detail/course_detail_screen.dart';
import '../explore/explore_screen.dart';
import '../learning/live_room_screen.dart';
import '../learning/open_course.dart';
import '../shell/shell_screen.dart';
import '../shell/student_top_bar.dart';
import 'widgets/nova_product_card.dart';

/// The website's account home (`/account`, D-084/D-125): the greeting band
/// with "Continue learning" and "See the Offers", the live-now bar while one
/// of the Student's Lives runs, then the Units (theirs first) and the Offers.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState app = AppScope.of(context);
    final StudentProfile? student = app.profile;
    final List<Course> courses = <Course>[
      ...app.courses.where((Course c) => c.owned),
      ...app.courses.where((Course c) => !c.owned),
    ];
    final List<Pack> packs = app.catalog.offers;
    final LiveSession? liveNow = app.learning.lives.where((LiveSession l) => l.status == LiveStatus.live).firstOrNull;
    final bool owns = app.learning.owned.isNotEmpty;
    final String forward = Directionality.of(context) == TextDirection.rtl ? '←' : '→';
    // D-134: a visitor browsing without an account.
    final bool guest = !app.session.signedIn;

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
                  icon: Icons.auto_awesome_outlined,
                  onTap: () => _explore(context),
                ),
              ],
            ),
          ),
          if (liveNow != null) ...[
            const SizedBox(height: 14),
            _LiveNowBar(live: liveNow),
          ],
          const SizedBox(height: 26),
          _SectionHead(
            title: context.tr('home.unitsTitle'),
            text: owns ? context.tr('home.unitsTextOwned') : context.tr('home.unitsText'),
            action: '${context.tr('home.allUnits')} $forward',
            onAction: () => _explore(context),
          ),
          const SizedBox(height: 14),
          if (courses.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: HeroEmpty(icon: Icons.auto_stories_outlined, title: context.tr('home.emptyTitle'), message: context.tr('home.emptyText')),
            )
          else
            _Rail(
              children: [
                for (final Course course in courses)
                  NovaProductCard.unit(
                    context,
                    course,
                    onTap: () => course.owned
                        ? openOwnedCourse(context, course)
                        : Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CourseDetailScreen(course: course))),
                  ),
              ],
            ),
          if (packs.isNotEmpty) ...[
            const SizedBox(height: 28),
            _SectionHead(
              title: context.tr('home.offersTitle'),
              text: context.tr('home.offersText'),
              action: '${context.tr('home.allOffers')} $forward',
              onAction: () => _explore(context),
            ),
            const SizedBox(height: 14),
            _Rail(
              children: [
                for (final Pack pack in packs)
                  NovaProductCard.offer(
                    context,
                    pack,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CourseDetailScreen.pack(pack: pack))),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static void _explore(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: ExploreScreen())));

  /// "الأحد 11 أكتوبر": the website's eyebrow, Algeria time.
  static String _today(BuildContext context) {
    final DateTime now = algeriaTime(clock.now());
    final NovaLang lang = AppScope.of(context).lang;
    const Map<NovaLang, List<String>> days = <NovaLang, List<String>>{
      NovaLang.ar: <String>['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'],
      NovaLang.fr: <String>['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'],
      NovaLang.en: <String>['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'],
    };
    const Map<NovaLang, List<String>> months = <NovaLang, List<String>>{
      NovaLang.ar: <String>['جانفي', 'فيفري', 'مارس', 'أفريل', 'ماي', 'جوان', 'جويلية', 'أوت', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'],
      NovaLang.fr: <String>['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'],
      NovaLang.en: <String>['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'],
    };
    final String day = days[lang]![now.weekday - 1];
    final String month = months[lang]![now.month - 1];
    return lang == NovaLang.en ? '$day, $month ${now.day}' : '$day ${now.day} $month';
  }
}

/// `.homeSectionHead`: title, one line, and the white "All …" pill.
class _SectionHead extends StatelessWidget {
  const _SectionHead({required this.title, required this.text, required this.action, required this.onAction});

  final String title;
  final String text;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: NovaTypography.textTheme.displaySmall),
          const SizedBox(height: 4),
          Text(text, style: NovaTypography.muted(NovaTypography.textTheme.bodyMedium!)),
          const SizedBox(height: 12),
          PressableScale(
            onTap: onAction,
            semanticLabel: action,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: NovaColors.paperCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: NovaColors.borderOnLight),
              ),
              child: Text(action, style: NovaTypography.textTheme.labelLarge!.copyWith(color: NovaColors.accent)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 14),
            Entrance(delay: Duration(milliseconds: 60 * i), child: children[i]),
          ],
        ],
      ),
    );
  }
}

/// `.homeLiveNow`: a Live of the Student is on; one tap opens its room.
class _LiveNowBar extends StatelessWidget {
  const _LiveNowBar({required this.live});

  final LiveSession live;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: PressableScale(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LiveRoomScreen(live: live))),
        semanticLabel: live.title,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: NovaColors.yellow, borderRadius: BorderRadius.circular(20)),
          child: Row(
            children: [
              const _Pulse(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      live.waitingRoomOpen && live.rawStatus != 'live' ? context.tr('home.waitingRoom') : context.tr('home.liveNow'),
                      style: NovaTypography.textTheme.titleMedium!.copyWith(color: NovaColors.yellowInk),
                    ),
                    Text(live.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: NovaTypography.textTheme.bodySmall!.copyWith(color: NovaColors.yellowInk)),
                  ],
                ),
              ),
              const Icon(Icons.play_circle_fill_rounded, size: 34, color: NovaColors.accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pulse extends StatefulWidget {
  const _Pulse();

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 18,
      child: AnimatedBuilder(
        animation: _c,
        builder: (BuildContext context, _) => Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 8 + 10 * _c.value,
              height: 8 + 10 * _c.value,
              decoration: BoxDecoration(color: const Color(0xFFE5484D).withValues(alpha: 1 - _c.value), shape: BoxShape.circle),
            ),
            Container(width: 9, height: 9, decoration: const BoxDecoration(color: Color(0xFFE5484D), shape: BoxShape.circle)),
          ],
        ),
      ),
    );
  }
}
