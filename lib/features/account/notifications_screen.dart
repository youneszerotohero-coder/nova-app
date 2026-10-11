import 'package:flutter/material.dart';
import '../../core/i18n/notification_text.dart';
import '../../core/i18n/nova_strings.dart';

import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_dimens.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/nova_page_header.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../data/account_store.dart';
import '../../data/json.dart';
import '../../data/models.dart';
import '../learning/live_room_screen.dart';
import '../learning/open_course.dart';
import 'dashboard_card.dart';

/// Opens [notification] as a tap in the list does: marks it read, and a
/// Live notification also opens its room (the web notification links
/// to `/live/{id}`). The realtime banner opens notifications the same way.
void openNotification(
  AppState app,
  NavigatorState navigator,
  AppNotification notification,
) {
  app.account.markRead(notification);
  // D-132: a past Live is a Lesson; its notification and new-lesson ones open it.
  final int lessonId = notification.data.integer('lesson_id', notification.type == 'lesson_published' ? notification.data.integer('entity_id') : 0);
  final int courseId = notification.data.integer('course_id');
  final int? fromLive = notification.liveId == null
      ? null
      : app.learning.lives.where((LiveSession l) => l.id == notification.liveId).firstOrNull?.lessonId;
  final Course? course = app.learning.owned.where((Course c) => c.id == courseId || c.slug == notification.data.str('course_slug')).firstOrNull ??
      app.learning.owned.where((Course c) => c.slug == app.learning.lives.where((LiveSession l) => l.id == notification.liveId).firstOrNull?.courseSlug).firstOrNull;
  if (course != null && (lessonId > 0 || fromLive != null)) {
    openOwnedCourse(navigator.context, course, lessonId: lessonId > 0 ? lessonId : fromLive);
    return;
  }
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

/// In-app notification center: the website's bell panel
/// (`.notificationPanel`, `dashboard.css`) as a page — every row with the
/// yellow icon tile, unread rows on blue-soft, "Mark all read" in blue —
/// grouped by recency (Today / Yesterday / This week, Algeria days). No push
/// in MVP — fetched in-app, 20 per page: page 1 on open and on
/// pull-to-refresh, the next pages near the end.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
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

    return Scaffold(
      backgroundColor: NovaColors.paper,
      body: RefreshIndicator(
        onRefresh: account.refreshNotifications,
        child: NotificationListener<ScrollUpdateNotification>(
          onNotification: (ScrollUpdateNotification n) => _onScroll(n, account),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(bottom: 40 + MediaQuery.paddingOf(context).bottom),
            children: [
              NovaPageHeader(
                title: context.tr('common.notifications'),
                kicker: context.trf('profile.notificationsSub', {'n': state.unreadCount.toString()}),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Entrance(child: _panel(context, state, account)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// `.notificationPanel`: surface, radius 24, line border, lifted shadow.
  Widget _panel(BuildContext context, AppState state, AccountStore account) {
    final bool canMarkAll = state.unreadCount > 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NovaColors.paperCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: NovaColors.borderOnLight),
        boxShadow: NovaDimens.shadowLift,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The page title is the band's: only "Mark all read" stays here.
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(6, 0, 0, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Opacity(
                  opacity: canMarkAll ? 1 : 0.45,
                  child: TextButton(
                    onPressed: canMarkAll ? () => account.markAllRead() : null,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      foregroundColor: NovaColors.accent,
                      disabledForegroundColor: NovaColors.accent,
                    ),
                    child: Text(context.tr('notif.markAll'), style: heroLabel(14, color: NovaColors.accent)),
                  ),
                ),
              ],
            ),
          ),
          ..._buildGroups(context, account),
        ],
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
      // `.notificationEmpty`: surface-2, radius 14, ink-2.
      return <Widget>[
        Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: NovaColors.paperRaised, borderRadius: BorderRadius.circular(14)),
          child: Column(
            children: [
              Text(context.tr('notif.emptyTitle'), textAlign: TextAlign.center, style: heroLabel(15)),
              const SizedBox(height: 4),
              Text(context.tr('notif.emptyMsg'), textAlign: TextAlign.center, style: heroText(15)),
            ],
          ),
        ),
      ];
    }

    final DateTime now = DateTime.now();
    for (final AppNotification notification in notifications) {
      final NotificationGroup group = notification.groupAt(now);
      if (group != lastGroup) {
        lastGroup = group;
        children.add(Padding(
          padding: EdgeInsetsDirectional.fromSTEB(6, children.isEmpty ? 2 : 12, 6, 6),
          child: Text(
            context.tr(switch (group) {
              NotificationGroup.today => 'notif.today',
              NotificationGroup.yesterday => 'notif.yesterday',
              NotificationGroup.thisWeek => 'notif.thisWeek',
              NotificationGroup.earlier => 'notif.earlier',
            }),
            style: heroLabel(13, color: NovaColors.textMuted),
          ),
        ));
      }
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: _NotificationRow(notification: notification),
      ));
    }

    children.add(const SizedBox(height: 8));
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

/// A panel row (`.notificationPanel > a`): the yellow tile, the title, the
/// message and the time; unread on blue-soft, read rows faded.
class _NotificationRow extends StatelessWidget {
  const _NotificationRow({required this.notification});

  final AppNotification notification;

  @override
  Widget build(BuildContext context) {
    final bool read = notification.read;
    final AppState app = AppScope.of(context);
    final NotificationText text = notificationText(notification, app.lang);

    return Material(
      color: read ? Colors.transparent : NovaColors.accentMist,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openNotification(app, Navigator.of(context), notification),
        child: Opacity(
          opacity: read ? 0.72 : 1,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: NovaColors.yellow, borderRadius: BorderRadius.circular(11)),
                  child: Icon(notification.icon, size: 18, color: NovaColors.yellowInk),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(text.title, style: heroLabel(15)),
                      const SizedBox(height: 3),
                      Text(
                        text.message.isNotEmpty ? text.message : emptyNotificationBody(notification, app.lang),
                        style: heroText(14),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        notificationTime(notification, app.lang),
                        style: heroText(12.5, color: NovaColors.textMuted, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `.notificationMore`: loads the next page when the list is too short to
/// scroll there.
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
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          alignment: Alignment.center,
          child: Text(label, style: heroLabel(15, color: loading ? NovaColors.textMuted : NovaColors.accent)),
        ),
      ),
    );
  }
}

/// End-of-list reassurance with hairlines either side.
class _CaughtUpFooter extends StatelessWidget {
  const _CaughtUpFooter();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
      child: Row(
        children: [
          Expanded(child: Divider(color: NovaColors.borderOnLight)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(context.tr('notif.allCaughtUp'), style: heroText(13, color: NovaColors.textMuted)),
          ),
          Expanded(child: Divider(color: NovaColors.borderOnLight)),
        ],
      ),
    );
  }
}
