import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_dimens.dart';
import '../../core/widgets/app_menu.dart';
import '../../core/widgets/nova_bottom_bar.dart';
import '../../core/widgets/nova_toast.dart';
import '../account/notifications_screen.dart';
import '../assistant/assistant_screen.dart';
import '../../data/models.dart';
import '../account/orders_screen.dart';
import '../account/settings_screen.dart';
import '../account/wallet_screen.dart';
import '../auth/auth_routes.dart';
import '../auth/require_account.dart';
import '../cart/cart_screen.dart';
import '../catalog/offers_catalog_screen.dart';
import '../catalog/teachers_screen.dart';
import '../catalog/units_catalog_screen.dart';
import '../detail/course_detail_screen.dart';
import '../home/home_screen.dart';
import '../learning/lives_screen.dart';
import '../learning/my_learning_screen.dart';
import '../messages/chat_list_screen.dart';
import 'student_top_bar.dart';

/// The Student space, as on the website's phone layout (D-133): the five
/// tabs of its bottom bar — Home, My lessons, Live, Cart, Account (the
/// settings, `/account/settings`) — kept alive once visited and switched
/// instantly, with a live cart badge, and the menu (the website's sidebar).
/// D-134: a visitor (no account) browses Home and the catalogue; the other
/// tabs ask to sign in, and what they asked for follows once signed in.
class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key, this.initialIndex = 0});

  final int initialIndex;

  static const int home = 0;
  static const int units = 1;
  static const int lives = 2;
  static const int cart = 3;
  static const int account = 4;

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  late int _currentIndex = widget.initialIndex;

  /// Tabs built so far; a tab is built on its first visit only.
  late final Set<int> _visited = <int>{widget.initialIndex};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resumeIntent());
    AppState.instance.shellTabRequest.addListener(_onTabRequest);
  }

  @override
  void dispose() {
    AppState.instance.shellTabRequest.removeListener(_onTabRequest);
    super.dispose();
  }

  void _onTabRequest() {
    final ValueNotifier<int?> request = AppState.instance.shellTabRequest;
    final int? tab = request.value;
    if (tab == null || !mounted) return;
    request.value = null;
    Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
    _select(tab);
  }

  /// A visitor asked for something that needs an account, then signed in
  /// or registered (D-127, D-134): it is carried out now.
  Future<void> _resumeIntent() async {
    if (!mounted) return;
    final AppState app = AppScope.of(context);
    final AccountIntent? intent = app.pendingIntent;
    if (intent == null || !app.session.signedIn) return;
    app.pendingIntent = null;
    switch (intent) {
      case OpenTab(:final int tab):
        _select(tab);
      case OpenNotifications():
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()));
      case OpenCourse(:final Course course):
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CourseDetailScreen(course: course)));
      case AddToCart(:final String kind, :final int id):
        _select(ShellScreen.cart);
        try {
          if (!app.contains('$kind:$id')) await app.commerce.add(kind: kind, id: id);
        } on ApiException catch (error) {
          if (mounted) novaToast(context, apiErrorText(context, error), icon: Icons.error_outline_rounded);
        }
    }
  }

  List<NovaNavItem> _items(BuildContext context, int cartCount) => [
        NovaNavItem(icon: Icons.home_outlined, label: context.tr('tab.home')),
        NovaNavItem(icon: Icons.menu_book_outlined, label: context.tr('tab.myCourses')),
        NovaNavItem(icon: Icons.sensors_rounded, label: context.tr('tab.lives')),
        NovaNavItem(icon: Icons.shopping_bag_outlined, label: context.tr('tab.cart'), badgeCount: cartCount),
        NovaNavItem(icon: Icons.person_outline_rounded, label: context.tr('tab.profile')),
      ];

  /// Switches tab and refreshes what that tab shows from the API, so
  /// a purchase or a new notification appears without a restart.
  void _select(int index) {
    setState(() {
      _currentIndex = index;
      _visited.add(index);
    });
    final AppState app = AppScope.of(context);
    if (!app.session.signedIn && index != ShellScreen.home) return;
    switch (index) {
      case ShellScreen.home:
        app.catalog.load();
      case ShellScreen.units:
      case ShellScreen.lives:
        app.learning.load();
      case ShellScreen.cart:
        app.commerce.load();
      case ShellScreen.account:
        app.account.load();
    }
  }

  /// The website's support address (`config/contact.ts`).
  static const String _supportEmail = 'noova.elearning@gmail.com';

  /// The menu = the website's Student sidebar: Learning (Overview, My units,
  /// Lives) and Account (Orders, Wallet, Settings), help and sign out. App
  /// only: the teachers directory. A visitor sees Home and the catalogue,
  /// then "Sign in" and "Create my account".
  void _openMenu() {
    final AppState app = AppScope.of(context);
    void push(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    NovaMenuEntry tab(IconData icon, String key, int index) =>
        NovaMenuEntry(icon: icon, label: context.tr(key), active: _currentIndex == index, onTap: () => _select(index));
    final NovaMenuEntry teachers =
        NovaMenuEntry(icon: Icons.groups_outlined, label: context.tr('menu.teachers'), onTap: () => push(const TeachersScreen()));

    if (!app.session.signedIn) {
      showNovaMenu(
        context,
        groups: <NovaMenuGroup>[
          NovaMenuGroup(label: context.tr('menu.groupLearning'), entries: <NovaMenuEntry>[
            tab(Icons.dashboard_outlined, 'menu.overview', ShellScreen.home),
            NovaMenuEntry(icon: Icons.menu_book_outlined, label: context.tr('menu.units'), onTap: () => push(const UnitsCatalogScreen())),
            NovaMenuEntry(icon: Icons.auto_awesome_outlined, label: context.tr('menu.offers'), onTap: () => push(const OffersCatalogScreen())),
            teachers,
          ]),
        ],
        onSignIn: () => requireAccount(context),
        onRegister: () => openRegistration(context),
      );
      return;
    }
    showNovaMenu(
      context,
      groups: <NovaMenuGroup>[
        NovaMenuGroup(label: context.tr('menu.groupLearning'), entries: <NovaMenuEntry>[
          tab(Icons.dashboard_outlined, 'menu.overview', ShellScreen.home),
          tab(Icons.menu_book_outlined, 'menu.myUnits', ShellScreen.units),
          tab(Icons.sensors_rounded, 'menu.lives', ShellScreen.lives),
          // D-143: the group chats (also the top bar's chat icon).
          NovaMenuEntry(icon: Icons.forum_outlined, label: context.tr('chat.title'), onTap: () => push(const ChatListScreen())),
          teachers,
        ]),
        NovaMenuGroup(label: context.tr('menu.groupAccount'), entries: <NovaMenuEntry>[
          NovaMenuEntry(icon: Icons.credit_card_rounded, label: context.tr('menu.orders'), onTap: () => push(const OrdersScreen())),
          NovaMenuEntry(icon: Icons.account_balance_wallet_outlined, label: context.tr('menu.wallet'), onTap: () => push(const WalletScreen())),
          tab(Icons.settings_outlined, 'menu.settings', ShellScreen.account),
        ]),
      ],
      onHelp: _contactSupport,
      // The same call as the settings' sign-out button.
      onSignOut: () => app.session.logout(),
    );
  }

  /// The help row (`.sidebarSupport`): a mail to the NOVA team.
  Future<void> _contactSupport() async {
    bool opened = false;
    try {
      opened = await launchUrl(Uri.parse('mailto:$_supportEmail'), mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) novaToast(context, _supportEmail, icon: Icons.mail_outline_rounded);
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = AppScope.of(context);
    // A visitor has no cart (D-134).
    final List<NovaNavItem> items = _items(context, state.session.signedIn ? state.itemCount : 0);

    return ShellNav(
      select: _select,
      openMenu: _openMenu,
      index: _currentIndex,
      child: Scaffold(
        body: Stack(
          children: [
            // A visited tab stays alive (scroll position kept, no rebuild or
            // replayed entrances on return) and switches instantly; a hidden
            // tab's animations are paused. Cross-fading two full screens on
            // every switch stuttered on average Android phones.
            Positioned.fill(
              child: IndexedStack(
                index: _currentIndex,
                children: [
                  for (int i = 0; i < items.length; i++)
                    TickerMode(
                      enabled: i == _currentIndex,
                      child: _visited.contains(i)
                          ? RepaintBoundary(child: _buildTab(i))
                          : const SizedBox.shrink(),
                    ),
                ],
              ),
            ),
            NovaBottomBar(
              items: items,
              currentIndex: _currentIndex,
              onChanged: _select,
            ),
            // D-150: the help assistant, as the website's floating button
            // above its phone tab bar (not in offline previews: no API).
            if (state.api != null)
              PositionedDirectional(
                start: 16,
                bottom: 12 + MediaQuery.viewPaddingOf(context).bottom + NovaDimens.bottomBarHeight + 14,
                child: const AssistantFab(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(int index) {
    if (!AppScope.of(context).session.signedIn) {
      return switch (index) {
        ShellScreen.home => const HomeScreen(),
        ShellScreen.units => const SignInPrompt(icon: Icons.menu_book_outlined, titleKey: 'guest.lessons', intent: OpenTab(ShellScreen.units)),
        ShellScreen.lives => const SignInPrompt(icon: Icons.sensors_rounded, titleKey: 'guest.lives', intent: OpenTab(ShellScreen.lives)),
        ShellScreen.cart => const SignInPrompt(icon: Icons.shopping_bag_outlined, titleKey: 'guest.cart', intent: OpenTab(ShellScreen.cart)),
        _ => const SignInPrompt(icon: Icons.person_outline_rounded, titleKey: 'guest.account', intent: OpenTab(ShellScreen.account)),
      };
    }
    return switch (index) {
      ShellScreen.home => const HomeScreen(),
      ShellScreen.units => const MyLearningScreen(),
      ShellScreen.lives => const LivesScreen(),
      ShellScreen.cart => const CartScreen(),
      // As on the website, "Account" opens the settings (`/account/settings`).
      _ => const SettingsScreen(),
    };
  }
}
