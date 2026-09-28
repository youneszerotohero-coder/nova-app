import 'package:flutter/material.dart';
import '../../core/i18n/notification_text.dart';
import '../../core/i18n/nova_strings.dart';

import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../data/account_store.dart';
import '../../data/json.dart';
import '../../data/models.dart';
import '../learning/live_room_screen.dart';

/// Opens [notification] as a tap in the list does: marks it read, and a
/// Live notification also opens its room (the web notification links
/// to `/live/{id}`). The realtime banner opens notifications the same way.
void openNotification(
  AppState app,
  NavigatorState navigator,
  AppNotification notification,
) {
  app.account.markRead(notification);
  final int? liveId = notification.liveId;
  if (liveId == null) return;
  final LiveSession live = app.learning.lives.firstWhere(
    (LiveSession l) => l.id == liveId,
    orElse: () => LiveSession(
      id: liveId,
      title: notification.data.str('live_title', notification.title),
      course: '',
      teacher: '',
      subject: '',
      status: LiveStatus.scheduled,
      attendees: 0,
      scene: sceneFor(liveId),
    ),
  );
  navigator.push(
    MaterialPageRoute<void>(builder: (_) => LiveRoomScreen(live: live)),
  );
}

/// In-app notification center: the conception's event list grouped by
/// recency (Today / Yesterday / This week, Algeria days) with unread
/// dots and mark-all-read. No push in MVP — fetched in-app, 20 per page:
/// page 1 on open and on pull-to-refresh, the next pages near the end.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  /// Entrance animation for the first rows only, so later pages appear
  /// at once instead of after a long stagger delay.
  static const int _animatedRows = 16;

  bool _opened = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_opened) return;
    _opened = true;
    AppScope.of(context).account.refreshNotifications();
  }

  /// Loads the next page when the list nears its end.
  bool _onScroll(ScrollUpdateNotification notification, AccountStore account) {
    if (notification.metrics.extentAfter < 600) {
      account.loadMoreNotifications();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = AppScope.of(context);
    final AccountStore account = state.account;
    final bool canMarkAll = state.unreadCount > 0;
    final List<Widget> rows = _buildGroups(context, account);

    return PageScaffold(
      title: context.tr('common.notifications'),
      kicker: context.trf(
        'profile.notificationsSub',
        {'n': state.unreadCount.toString()},
      ),
      watermark: Icons.notifications_rounded,
      actions: [
        FrostedPillButton(
          label: context.tr('notif.markAll'),
          icon: Icons.done_all_rounded,
          enabled: canMarkAll,
          onTap: () => AppScope.of(context).account.markAllRead(),
        ),
      ],
      body: RefreshIndicator(
        onRefresh: account.refreshNotifications,
        child: NotificationListener<ScrollUpdateNotification>(
          onNotification: (ScrollUpdateNotification n) => _onScroll(n, account),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
            children: [
              ...stagger(rows.take(_animatedRows).toList()),
              ...rows.skip(_animatedRows),
            ],
          ),
        ),
      ),
    );
  }

  /// Interleaves group labels (Today / Yesterday / This week) before
  /// the first notification of each group.
  List<Widget> _buildGroups(BuildContext context, AccountStore account) {
    final List<Widget> children = <Widget>[];
    NotificationGroup? lastGroup;

    final List<AppNotification> notifications = account.notifications;
    if (notifications.isEmpty) {
      return <Widget>[
        const SizedBox(height: 40),
        EmptyState(
          icon: Icons.notifications_none_rounded,
          title: context.tr('notif.emptyTitle'),
          message: context.tr('notif.emptyMsg'),
        ),
      ];
    }

    final DateTime now = DateTime.now();
    for (final AppNotification notification in notifications) {
      final NotificationGroup group = notification.groupAt(now);
      if (group != lastGroup) {
        lastGroup = group;
        children
          ..add(const SizedBox(height: 10))
          ..add(Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              context.tr(switch (group) {
                NotificationGroup.today => 'notif.today',
                NotificationGroup.yesterday => 'notif.yesterday',
                NotificationGroup.thisWeek => 'notif.thisWeek',
                NotificationGroup.earlier => 'notif.earlier',
              }),
              style: NovaTypography.textTheme.titleMedium!.copyWith(
                color: NovaColors.textMuted,
              ),
            ),
          ));
      }
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _NotificationCard(notification: notification),
      ));
    }

    children.add(const SizedBox(height: 14));
    children.add(
      account.hasMoreNotifications
          ? _ShowMoreRow(
              loading: account.loadingMoreNotifications,
              onTap: account.loadMoreNotifications,
            )
          : const _CaughtUpFooter(),
    );
    return children;
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.notification});

  final AppNotification notification;

  @override
  Widget build(BuildContext context) {
    final bool read = notification.read;
    final AppState app = AppScope.of(context);
    final NotificationText text = notificationText(notification, app.lang);

    return PressableScale(
      onTap: () => openNotification(app, Navigator.of(context), notification),
      semanticLabel: text.title,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // Soft tinted quarter-disc anchored to the bottom-right
            // corner, echoing the notification hue.
            Positioned(
              right: -34,
              bottom: -34,
              child: Container(
                width: 104,
                height: 104,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: notification.tint.withValues(alpha: 0.55),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: NovaColors.paperCard,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: NovaColors.borderOnLight),
                boxShadow: const [
                  BoxShadow(
                    offset: Offset(0, 12),
                    blurRadius: 30,
                    spreadRadius: -14,
                    color: Color(0x1E0A1128),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: notification.tint,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(
                      notification.icon,
                      size: 26,
                      color: notification.iconColor,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          text.title,
                          style: NovaTypography.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          text.message.isNotEmpty
                              ? text.message
                              : emptyNotificationBody(notification, app.lang),
                          style: NovaTypography.muted(
                            NovaTypography.textTheme.bodyMedium!,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          notificationTime(notification, app.lang),
                          style: NovaTypography.textTheme.labelSmall!
                              .copyWith(color: NovaColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: read ? Colors.transparent : NovaColors.accent,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: NovaColors.textMuted,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Loads the next page when the list is too short to scroll there.
class _ShowMoreRow extends StatelessWidget {
  const _ShowMoreRow({required this.loading, required this.onTap});

  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String label = context.tr(loading ? 'notif.loading' : 'notif.showMore');
    return Center(
      child: PressableScale(
        onTap: loading ? null : onTap,
        semanticLabel: label,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          decoration: BoxDecoration(
            color: NovaColors.paperCard,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: NovaColors.borderOnLight),
          ),
          child: Text(
            label,
            style: NovaTypography.textTheme.labelLarge!.copyWith(
              color: loading ? NovaColors.textMuted : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// End-of-list reassurance with hairline dashes either side.
class _CaughtUpFooter extends StatelessWidget {
  const _CaughtUpFooter();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: Divider(color: NovaColors.borderOnLight),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              context.tr('notif.allCaughtUp'),
              style: NovaTypography.muted(NovaTypography.textTheme.bodySmall!),
            ),
          ),
          Expanded(
            child: Divider(color: NovaColors.borderOnLight),
          ),
        ],
      ),
    );
  }
}
