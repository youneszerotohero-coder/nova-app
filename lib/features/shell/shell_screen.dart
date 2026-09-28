import 'package:flutter/material.dart';

import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/widgets/app_menu.dart';
import '../../core/widgets/nova_bottom_bar.dart';
import '../account/profile_screen.dart';
import '../cart/cart_screen.dart';
import '../explore/explore_screen.dart';
import '../home/home_screen.dart';
import '../learning/my_learning_screen.dart';

/// Hosts the five tab destinations under the floating pill navigation:
/// home, explore, my learning, cart and profile, kept alive once visited
/// and switched instantly, with a live cart badge.
class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  int _currentIndex = 0;

  /// Tabs built so far; a tab is built on its first visit only.
  final Set<int> _visited = <int>{0};

  List<NovaNavItem> _items(BuildContext context, int cartCount) => [
        NovaNavItem(
          icon: Icons.home_rounded,
          label: context.tr('tab.home'),
        ),
        NovaNavItem(
          icon: Icons.search_rounded,
          label: context.tr('tab.explore'),
        ),
        NovaNavItem(
          icon: Icons.play_circle_outline_rounded,
          label: context.tr('tab.myCourses'),
        ),
        NovaNavItem(
          icon: Icons.shopping_bag_outlined,
          label: context.tr('tab.cart'),
          badgeCount: cartCount,
        ),
        NovaNavItem(
          icon: Icons.person_outline_rounded,
          label: context.tr('tab.profile'),
        ),
      ];

  /// Switches tab and refreshes what that tab shows from the API, so
  /// a purchase or a new notification appears without a restart.
  void _select(int index) {
    setState(() {
      _currentIndex = index;
      _visited.add(index);
    });
    final AppState app = AppScope.of(context);
    switch (index) {
      case 1:
        app.catalog.load();
      case 2:
        app.learning.load();
      case 3:
        app.commerce.load();
      case 4:
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

    return Scaffold(
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
                        ? RepaintBoundary(child: _buildTab(context, i))
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
    );
  }

  Widget _buildTab(BuildContext context, int index) {
    switch (index) {
      case 0:
        return HomeScreen(
          onMenuTap: _openMenu,
          onExplore: () => _select(1),
        );
      case 1:
        return const ExploreScreen();
      case 2:
        return const MyLearningScreen();
      case 3:
        return const CartScreen();
      default:
        return const ProfileScreen();
    }
  }
}

/// Retained for menu parity: themed placeholder when a tab has no
/// screen yet.
class PlaceholderTab extends StatelessWidget {
  const PlaceholderTab({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label is on its way', style: NovaTypography.textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            'This tab opens in a next increment.',
            style: NovaTypography.muted(NovaTypography.textTheme.bodyMedium!),
          ),
        ],
      ),
    );
  }
}
