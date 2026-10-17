import 'dart:async';

import 'package:flutter/material.dart';

import '../i18n/nova_strings.dart';
import '../state/app_state.dart';
import '../update/app_update_gate.dart';
import 'push_service.dart';

/// Wraps the signed-in space (Student or Teacher shell, D-143): tapped
/// notifications open over it, and a moment after it first shows, the
/// phone's permission is explained then asked — once ([PushService]).
class PushHost extends StatefulWidget {
  const PushHost({super.key, required this.child});

  final Widget child;

  /// The space settles (and the Student reads it) before the explanation.
  static const Duration askAfter = Duration(milliseconds: 1500);

  @override
  State<PushHost> createState() => _PushHostState();
}

class _PushHostState extends State<PushHost> {
  AppState? _app;
  Timer? _ask;
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final AppState app = AppScope.of(context);
      _app = app;
      app.pushTaps.attach(this, app, Navigator.of(context));
      final PushService? push = app.push;
      if (push == null) return;
      _ask = Timer(PushHost.askAfter, () => push.offerPermission(_explain));
      // Back from the phone's settings: notifications may be allowed now.
      _lifecycle = AppLifecycleListener(onResume: push.refreshPermission);
    });
  }

  Future<bool> _explain() async {
    if (!mounted) return false;
    final bool? enable = await showPushExplainer(context);
    return enable ?? false;
  }

  @override
  void dispose() {
    _ask?.cancel();
    _lifecycle?.dispose();
    _app?.pushTaps.detach(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Why NOVA asks for notifications, before the system prompt: "Enable"
/// pops true, "Not now" false.
Future<bool?> showPushExplainer(BuildContext context) => showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) => UpdateSheet(
        icon: Icons.notifications_active_outlined,
        title: context.tr('push.askTitle'),
        body: context.tr(AppScope.of(context).session.isTeacher ? 'push.askBodyTeacher' : 'push.askBody'),
        action: context.tr('push.askEnable'),
        later: context.tr('push.askLater'),
      ),
    );
