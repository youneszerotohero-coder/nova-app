import 'package:flutter/material.dart';

import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_dimens.dart';
import '../../core/widgets/nova_bottom_bar.dart';
import '../account/notifications_screen.dart';
import '../messages/chat_list_screen.dart';
import '../shell/shell_screen.dart';
import '../shell/student_top_bar.dart';
import 'teacher_settings_screen.dart';

/// The Teacher space (D-143, BR-T5): the Student shell's look with three
/// tabs — Chats, Notifications, Settings — and nothing of the Student space
/// (no catalogue, cart, Lessons, Lives, guest mode nor device checks). Each
/// page carries the Teacher top bar ([StudentTopBar] shows it for a
/// Teacher); a visited tab stays alive, as in the Student shell.
class TeacherShell extends StatefulWidget {
  const TeacherShell({super.key, this.initialIndex = chats});

  final int initialIndex;

  static const int chats = 0;
  static const int notifications = 1;
  static const int settings = 2;

  @override
  State<TeacherShell> createState() => _TeacherShellState();
}

class _TeacherShellState extends State<TeacherShell> {
  late int _currentIndex = widget.initialIndex;
  late final Set<int> _visited = <int>{widget.initialIndex};

  void _select(int index) {
    // A Student page asking for its Account tab means Settings here.
    final int tab = index == ShellScreen.account ? TeacherShell.settings : index.clamp(0, TeacherShell.settings);
    setState(() {
      _currentIndex = tab;
      _visited.add(tab);
    });
    if (tab == TeacherShell.notifications) AppScope.of(context).account.refreshNotifications();
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = AppScope.of(context);
    final List<NovaNavItem> items = <NovaNavItem>[
      NovaNavItem(icon: Icons.forum_outlined, label: context.tr('teacher.tabChats')),
      NovaNavItem(icon: Icons.notifications_none_rounded, label: context.tr('teacher.tabNotifications'), badgeCount: app.unreadCount),
      NovaNavItem(icon: Icons.settings_outlined, label: context.tr('teacher.tabSettings')),
    ];

    return ShellNav(
      select: _select,
      // The Teacher space has no menu: its three tabs are everything.
      openMenu: () {},
      index: _currentIndex,
      child: Scaffold(
        backgroundColor: NovaColors.paper,
        body: Stack(
          children: [
            Positioned.fill(
              child: IndexedStack(
                index: _currentIndex,
                children: [
                  for (int i = 0; i < items.length; i++)
                    TickerMode(
                      enabled: i == _currentIndex,
                      child: _visited.contains(i) ? RepaintBoundary(child: _buildTab(i)) : const SizedBox.shrink(),
                    ),
                ],
              ),
            ),
            NovaBottomBar(items: items, currentIndex: _currentIndex, onChanged: _select),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(int index) => switch (index) {
        TeacherShell.chats => const ChatListScreen(embedded: true),
        // The notifications page ends above the floating bottom bar.
        TeacherShell.notifications => const _AboveBottomBar(child: NotificationsScreen()),
        _ => const TeacherSettingsScreen(),
      };
}

/// Lifts a page's bottom inset above the floating bottom bar.
class _AboveBottomBar extends StatelessWidget {
  const _AboveBottomBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
        padding: media.padding.copyWith(bottom: media.padding.bottom + NovaDimens.bottomBarHeight + 24),
      ),
      child: child,
    );
  }
}
