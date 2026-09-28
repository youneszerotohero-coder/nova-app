import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models.dart';
import '../i18n/notification_text.dart';
import '../state/app_state.dart';
import '../theme/nova_colors.dart';
import '../theme/nova_dimens.dart';
import 'pressable_scale.dart';

/// The short sound of a notification delivered in realtime (web
/// `lib/notification-sound.ts`): the device's own notification sound
/// over `nova/chime` (Android `NotificationChime.kt`, iOS
/// `AppDelegate.swift`), which stays quiet in silent mode. At most one
/// chime every 3 s; without the platform side (tests) nothing plays.
class NotificationChime {
  NotificationChime._();

  static const MethodChannel _channel = MethodChannel('nova/chime');
  static const Duration _minInterval = Duration(seconds: 3);
  static DateTime? _lastPlayed;

  static Future<void> play() async {
    final DateTime now = DateTime.now();
    final DateTime? last = _lastPlayed;
    if (last != null && now.difference(last) < _minInterval) return;
    _lastPlayed = now;
    try {
      await _channel.invokeMethod<void>('play');
    } catch (_) {
      // No sound on this device: the banner still shows.
    }
  }

  @visibleForTesting
  static void resetThrottle() => _lastPlayed = null;
}

/// Wraps the app from `MaterialApp.builder` so that every notification
/// arriving in realtime chimes and shows a 3-second banner over any
/// screen (web `NotificationToast`). Tapping the banner opens the
/// notification; everything outside it stays interactive.
class NotificationBannerHost extends StatefulWidget {
  const NotificationBannerHost({
    super.key,
    required this.arrivals,
    required this.onOpen,
    required this.child,
  });

  final Stream<AppNotification> arrivals;
  final ValueChanged<AppNotification> onOpen;
  final Widget child;

  static const Duration visibleFor = Duration(seconds: 3);

  @override
  State<NotificationBannerHost> createState() => _NotificationBannerHostState();
}

class _NotificationBannerHostState extends State<NotificationBannerHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion;
  late final Animation<double> _curve;
  StreamSubscription<AppNotification>? _subscription;
  Timer? _timer;
  AppNotification? _current;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 200),
    )..addStatusListener(_onStatus);
    _curve = CurvedAnimation(
      parent: _motion,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _subscription = widget.arrivals.listen(_show);
  }

  @override
  void didUpdateWidget(NotificationBannerHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.arrivals != oldWidget.arrivals) {
      _subscription?.cancel();
      _subscription = widget.arrivals.listen(_show);
    }
  }

  void _show(AppNotification notification) {
    NotificationChime.play();
    _timer?.cancel();
    setState(() => _current = notification);
    _motion.forward();
    _timer = Timer(NotificationBannerHost.visibleFor, _hide);
  }

  void _hide() {
    _timer?.cancel();
    _motion.reverse();
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && _current != null && mounted) {
      setState(() => _current = null);
    }
  }

  void _open() {
    final AppNotification? notification = _current;
    // Already opened: the banner is on its way out.
    if (notification == null || _motion.status == AnimationStatus.reverse) return;
    _hide();
    widget.onOpen(notification);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _subscription?.cancel();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppNotification? current = _current;
    return Stack(
      children: [
        widget.child,
        if (current != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: FadeTransition(
                  opacity: _curve,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, -0.6),
                      end: Offset.zero,
                    ).animate(_curve),
                    child: _Banner(notification: current, onTap: _open),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final NovaLang lang = AppScope.of(context).lang;
    final NotificationText text = notificationText(notification, lang);

    return Semantics(
      liveRegion: true,
      child: PressableScale(
        onTap: onTap,
        semanticLabel: text.title,
        // Above the Navigator there is no Material: this one gives the
        // text its plain default style.
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 16, 12),
            decoration: BoxDecoration(
              color: NovaColors.ink950,
              borderRadius: BorderRadius.circular(18),
              boxShadow: NovaDimens.shadowFloating,
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: notification.tint,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    notification.icon,
                    size: 20,
                    color: notification.iconColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        text.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: NovaColors.textOnDark,
                        ),
                      ),
                      if (text.message.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          text.message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w500,
                            fontSize: 12.5,
                            height: 1.35,
                            color: NovaColors.textMutedOnDark,
                          ),
                        ),
                      ],
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
