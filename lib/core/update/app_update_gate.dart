import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../i18n/nova_strings.dart';
import '../theme/nova_colors.dart';
import '../theme/nova_typography.dart';
import '../widgets/gradient_pill_button.dart';
import '../widgets/pressable_scale.dart';
import 'store_updates.dart';

/// Offers store updates over the whole app: shortly after launch, and
/// when the app comes back to the foreground at most every 12 h (a
/// Student in a Live is not interrupted by a check each time they switch
/// apps). A flexible Android download that finishes offers a restart.
class AppUpdateGate extends StatefulWidget {
  const AppUpdateGate({
    super.key,
    required this.navigatorKey,
    required this.child,
    this.enabled = true,
    this.updates,
    this.launch,
  });

  /// Shows the sheets above the current route.
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  /// Off for offline previews and tests without a store.
  final bool enabled;
  final StoreUpdates? updates;

  /// Opens the App Store page; injectable for tests.
  final Future<bool> Function(Uri url)? launch;

  static const Duration firstCheckDelay = Duration(seconds: 4);
  static const Duration recheckAfter = Duration(hours: 12);

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate> with WidgetsBindingObserver {
  late final StoreUpdates _updates = widget.updates ?? StoreUpdates();
  Timer? _first;
  StreamSubscription<Map<Object?, Object?>>? _installs;
  DateTime? _lastCheck;
  bool _checking = false;
  bool _sheetOpen = false;

  @override
  void initState() {
    super.initState();
    if (!widget.enabled) return;
    WidgetsBinding.instance.addObserver(this);
    _first = Timer(AppUpdateGate.firstCheckDelay, _check);
  }

  @override
  void dispose() {
    _first?.cancel();
    _installs?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final DateTime? last = _lastCheck;
    if (last == null || DateTime.now().difference(last) >= AppUpdateGate.recheckAfter) _check();
  }

  Future<void> _check() async {
    if (_checking || !mounted) return;
    _checking = true;
    _lastCheck = DateTime.now();
    try {
      final UpdateOffer? offer = await _updates.check();
      if (offer == null || !mounted) return;
      switch (offer.action) {
        case UpdateAction.restart:
          await _offerRestart();
        case UpdateAction.immediate:
          // Google Play's full-screen flow; if it is left, it resumes at
          // the next check.
          await _updates.start(immediate: true);
        case UpdateAction.prompt:
          if (offer.storeUrl != null) {
            await _offerStore(offer);
          } else {
            await _startFlexible(offer);
          }
      }
    } finally {
      _checking = false;
    }
  }

  /// Android: Play asks the Student, then downloads in the background.
  Future<void> _startFlexible(UpdateOffer offer) async {
    _installs ??= _updates.installStates.listen((Map<Object?, Object?> state) {
      if (state['status'] == 'downloaded') _offerRestart();
    }, onError: (Object _) {});
    final String result = await _updates.start(immediate: false);
    if (result == 'canceled') await _updates.declined(offer.version);
  }

  /// iPhone: the NOVA sheet, then the App Store page.
  Future<void> _offerStore(UpdateOffer offer) async {
    final bool? update = await _sheet(
      icon: Icons.system_update_rounded,
      title: 'update.availableTitle',
      body: 'update.availableBody',
      version: offer.version,
      action: 'update.now',
    );
    if (update == true) {
      final Uri url = offer.storeUrl!;
      await (widget.launch ?? _openStore)(url);
    } else {
      await _updates.declined(offer.version);
    }
  }

  Future<void> _offerRestart() async {
    final bool? restart = await _sheet(
      icon: Icons.restart_alt_rounded,
      title: 'update.readyTitle',
      body: 'update.readyBody',
      action: 'update.restart',
    );
    if (restart == true) await _updates.complete();
  }

  static Future<bool> _openStore(Uri url) => launchUrl(url, mode: LaunchMode.externalApplication);

  Future<bool?> _sheet({
    required IconData icon,
    required String title,
    required String body,
    required String action,
    String? version,
  }) async {
    final BuildContext? context = widget.navigatorKey.currentContext;
    if (context == null || _sheetOpen) return null;
    _sheetOpen = true;
    try {
      return await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (BuildContext context) => UpdateSheet(
          icon: icon,
          title: context.tr(title),
          body: context.trf(body, <String, String>{'v': version ?? ''}),
          action: context.tr(action),
          later: context.tr('update.later'),
        ),
      );
    } finally {
      _sheetOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// "Update available" / "Update ready": the primary action pops `true`,
/// "Later" pops `false`.
class UpdateSheet extends StatelessWidget {
  const UpdateSheet({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
    required this.later,
  });

  final IconData icon;
  final String title;
  final String body;
  final String action;
  final String later;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(10),
      padding: EdgeInsets.fromLTRB(22, 24, 22, 18 + MediaQuery.paddingOf(context).bottom),
      decoration: BoxDecoration(
        color: NovaColors.paperCard,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: const BoxDecoration(gradient: NovaColors.accentGradient, shape: BoxShape.circle),
            child: Icon(icon, size: 28, color: Colors.white),
          ),
          const SizedBox(height: 14),
          Text(title, textAlign: TextAlign.center, style: NovaTypography.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: NovaTypography.textTheme.bodyMedium!.copyWith(color: NovaColors.textMuted),
          ),
          const SizedBox(height: 20),
          GradientPillButton(
            icon: icon,
            label: action,
            width: double.infinity,
            height: 52,
            semanticLabel: action,
            onTap: () => Navigator.of(context).pop(true),
          ),
          const SizedBox(height: 6),
          PressableScale(
            onTap: () => Navigator.of(context).pop(false),
            semanticLabel: later,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
              child: Text(later, style: NovaTypography.textTheme.labelLarge!.copyWith(color: NovaColors.textMuted)),
            ),
          ),
        ],
      ),
    );
  }
}
