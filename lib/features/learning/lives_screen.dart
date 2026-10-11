import 'package:flutter/material.dart';

import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/widgets/hero_style.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/nova_page_header.dart';
import '../../core/widgets/nova_toast.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../data/models.dart';
import '../shell/shell_screen.dart';
import '../shell/student_top_bar.dart';
import 'live_room_screen.dart';

/// "Live" tab, the website's Lives page (D-084/D-132): the Student's running
/// and coming Lives only. A finished Live is a Lesson of its Unit, which the
/// note under the filters says.
class LivesScreen extends StatefulWidget {
  const LivesScreen({super.key});

  @override
  State<LivesScreen> createState() => _LivesScreenState();
}

class _LivesScreenState extends State<LivesScreen> {
  /// 0 all, 1 live now, 2 upcoming.
  int _filter = 0;

  @override
  Widget build(BuildContext context) {
    final AppState app = AppScope.of(context);
    final List<LiveSession> current = app.learning.lives.where((LiveSession l) => l.current).toList();
    final bool missed = app.learning.lives.any((LiveSession l) => !l.current);
    final List<LiveSession> shown = current.where((LiveSession l) => switch (_filter) {
          1 => l.status == LiveStatus.live,
          2 => l.status != LiveStatus.live,
          _ => true,
        }).toList();
    final List<String> filters = <String>[
      '${context.tr('learning.all')} (${current.length})',
      '${context.tr('lives.onNow')} (${current.where((LiveSession l) => l.status == LiveStatus.live).length})',
      '${context.tr('learning.upcoming')} (${current.where((LiveSession l) => l.status != LiveStatus.live).length})',
    ];

    return RefreshIndicator(
      onRefresh: app.learning.load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 130),
        children: [
          NovaPageHeader(
            showBack: false,
            kicker: context.tr('lives.eyebrow'),
            title: context.tr('lives.title'),
            lead: context.tr('lives.lead'),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 44,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              scrollDirection: Axis.horizontal,
              itemCount: filters.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, int i) => PressableScale(
                onTap: () => setState(() => _filter = i),
                semanticLabel: filters[i],
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _filter == i ? NovaColors.accent : NovaColors.paperCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _filter == i ? NovaColors.accent : NovaColors.borderOnLight),
                  ),
                  child: Text(
                    filters[i],
                    style: NovaTypography.textTheme.labelLarge!.copyWith(color: _filter == i ? Colors.white : NovaColors.textStrong),
                  ),
                ),
              ),
            ),
          ),
          if (missed) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: _MissedNote(onTap: () => ShellNav.maybeOf(context)?.select(ShellScreen.units)),
            ),
          ],
          const SizedBox(height: 16),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: HeroEmpty(icon: Icons.sensors_rounded, title: context.tr('lives.empty'), message: context.tr('lives.emptyText')),
            )
          else
            for (int i = 0; i < shown.length; i++)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Entrance(delay: Duration(milliseconds: 60 * i), child: LiveTicket(live: shown[i])),
              ),
        ],
      ),
    );
  }
}

/// `.livesReplayNote`: where finished Lives are now.
class _MissedNote extends StatelessWidget {
  const _MissedNote({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      semanticLabel: context.tr('lives.missedTitle'),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: NovaColors.paperCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: NovaColors.borderOnLight),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: NovaColors.accentMist, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.play_arrow_rounded, color: NovaColors.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.tr('lives.missedTitle'), style: NovaTypography.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(context.tr('lives.missedText'), style: NovaTypography.muted(NovaTypography.textTheme.bodySmall!)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_forward_rounded, size: 16, color: NovaColors.accent),
                      const SizedBox(width: 6),
                      Text(context.tr('tab.myCourses'), style: NovaTypography.textTheme.labelLarge!.copyWith(color: NovaColors.accent)),
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

/// The website's Live ticket: a navy card, its status chip and viewers, the
/// day's icon, then the title, the Unit and the time.
class LiveTicket extends StatelessWidget {
  const LiveTicket({super.key, required this.live});

  final LiveSession live;

  @override
  Widget build(BuildContext context) {
    final bool isLive = live.status == LiveStatus.live;
    final bool canEnter = isLive || live.waitingRoomOpen;
    return PressableScale(
      onTap: () {
        if (canEnter) {
          Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LiveRoomScreen(live: live)));
        } else {
          novaToast(context, context.tr('learning.reminderSet'), icon: Icons.notifications_active_rounded);
        }
      },
      semanticLabel: live.title,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0E1530),
          borderRadius: BorderRadius.circular(26),
          boxShadow: const [BoxShadow(offset: Offset(0, 20), blurRadius: 40, spreadRadius: -24, color: Color(0x8C10276B))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isLive ? const Color(0xFFE5484D) : const Color(0xFFF2A33A),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(isLive ? Icons.sensors_rounded : Icons.event_rounded, size: 14, color: Colors.white),
                      const SizedBox(width: 5),
                      Text(
                        isLive ? context.tr('lives.onNow') : context.tr('lives.scheduled'),
                        style: NovaTypography.textTheme.labelMedium!.copyWith(color: Colors.white),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.people_alt_outlined, size: 14, color: Colors.white),
                      const SizedBox(width: 5),
                      Text('${live.attendees}', style: NovaTypography.textTheme.labelMedium!.copyWith(color: Colors.white)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: isLive ? const Color(0xFFE5484D) : const Color(0xFFF2A33A),
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(blurRadius: 22, color: (isLive ? const Color(0xFFE5484D) : const Color(0xFFF2A33A)).withValues(alpha: 0.45))],
                ),
                child: Icon(isLive ? Icons.play_arrow_rounded : Icons.calendar_month_rounded, size: 28, color: Colors.white),
              ),
            ),
            const SizedBox(height: 18),
            Text(live.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: NovaTypography.textTheme.titleLarge!.copyWith(color: Colors.white)),
            const SizedBox(height: 2),
            Text(live.course, maxLines: 1, overflow: TextOverflow.ellipsis, style: NovaTypography.textTheme.titleMedium!.copyWith(color: NovaColors.yellow)),
            if (live.scheduledLabel != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.schedule_rounded, size: 15, color: Color(0xFFC4CBE0)),
                  const SizedBox(width: 6),
                  Text(live.scheduledLabel!, style: NovaTypography.textTheme.bodySmall!.copyWith(color: const Color(0xFFC4CBE0))),
                ],
              ),
            ],
            if (canEnter) ...[
              const SizedBox(height: 14),
              NovaButton(
                label: live.waitingRoomOpen && !isLive ? context.tr('home.waitingRoom') : context.tr('lives.join'),
                variant: NovaButtonVariant.yellow,
                expand: true,
                small: true,
                chipIcon: Icons.play_arrow_rounded,
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LiveRoomScreen(live: live))),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
