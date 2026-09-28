import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n/nova_strings.dart';
import '../theme/nova_colors.dart';
import '../widgets/nova_toast.dart';

/// Screen-capture state for the whole app (D-067, conception §6.5).
///
/// Android is covered natively by `FLAG_SECURE` (MainActivity), which
/// blacks out screenshots, recordings and the recents thumbnail, so
/// nothing here fires there. iOS cannot block capture: `CaptureGuard`
/// reports recording/mirroring and screenshots over `nova/capture`, and
/// this monitor turns them into state the UI and the players obey.
class CaptureMonitor extends ChangeNotifier {
  CaptureMonitor._();

  static final CaptureMonitor instance = CaptureMonitor._();

  static const EventChannel _channel = EventChannel('nova/capture');

  StreamSubscription<dynamic>? _subscription;
  bool _captured = false;
  final StreamController<void> _screenshots =
      StreamController<void>.broadcast();

  /// True while the screen is being recorded, mirrored or AirPlayed.
  /// Protected players must stop and the app stays blurred.
  bool get captured => _captured;

  /// Fires after a screenshot was taken (iOS reports it after the fact).
  Stream<void> get screenshots => _screenshots.stream;

  void start() {
    if (_subscription != null || kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    _subscription = _channel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is! Map) return;
        if (event['captured'] is bool) setCaptured(event['captured'] as bool);
        if (event['screenshot'] == true) _screenshots.add(null);
      },
      onError: (Object _) {},
    );
  }

  @visibleForTesting
  void setCaptured(bool value) {
    if (value == _captured) return;
    _captured = value;
    notifyListeners();
  }
}

/// Wraps the app from `MaterialApp.builder`: blurs everything while the
/// screen is captured and while the app is inactive (so the iOS
/// app-switcher snapshot never shows a lesson), and warns after a
/// screenshot.
class CaptureShield extends StatefulWidget {
  const CaptureShield({super.key, required this.child});

  final Widget child;

  @override
  State<CaptureShield> createState() => _CaptureShieldState();
}

class _CaptureShieldState extends State<CaptureShield>
    with WidgetsBindingObserver {
  final CaptureMonitor _monitor = CaptureMonitor.instance;
  StreamSubscription<void>? _screenshots;
  bool _inactive = false;

  bool get _iOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _monitor
      ..start()
      ..addListener(_onChange);
    _screenshots = _monitor.screenshots.listen((_) {
      if (!mounted) return;
      novaToast(
        context,
        context.tr('capture.screenshot'),
        icon: Icons.shield_outlined,
      );
    });
  }

  void _onChange() => setState(() {});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bool inactive = state != AppLifecycleState.resumed;
    if (inactive != _inactive) setState(() => _inactive = inactive);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _monitor.removeListener(_onChange);
    _screenshots?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool captured = _monitor.captured;
    final bool shield = captured || (_iOS && _inactive);

    return Stack(
      children: [
        widget.child,
        if (shield)
          Positioned.fill(
            child: _Shield(showMessage: captured),
          ),
      ],
    );
  }
}

class _Shield extends StatelessWidget {
  const _Shield({required this.showMessage});

  final bool showMessage;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: ColoredBox(
          color: NovaColors.ink950.withValues(alpha: 0.72),
          child: !showMessage
              ? const SizedBox.expand()
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.videocam_off_rounded,
                          size: 44,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          context.tr('capture.blocked'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            height: 1.4,
                            color: Colors.white,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
