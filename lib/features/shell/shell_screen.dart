import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/widgets/app_menu.dart';
import '../../core/widgets/nova_bottom_bar.dart';
import '../../core/widgets/nova_toast.dart';
import '../account/notifications_screen.dart';
import '../../data/models.dart';
import '../account/profile_screen.dart';
import '../auth/require_account.dart';
import '../cart/cart_screen.dart';
import '../detail/course_detail_screen.dart';
import '../home/home_screen.dart';
import '../learning/lives_screen.dart';
import '../learning/my_learning_screen.dart';
import 'student_top_bar.dart';

/// The Student space, as on the website's phone layout (D-133): the five
/// tabs of its bottom bar — Home, My lessons, Live, Cart, Account — kept
/// alive once visited and switched instantly, with a live cart badge.
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

  void _openMenu() {
    showNovaMenu(
      context,
      items: _items(context, AppScope.of(context).itemCount),
      currentIndex: _currentIndex,
      onSelect: _select,
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = AppScope.of(context);
    final List<NovaNavItem> items = _items(context, state.itemCount);

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
      _ => const ProfileScreen(),
    };
  }
}
