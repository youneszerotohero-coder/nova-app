import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../state/app_state.dart';

/// Anti-piracy watermark required on Lessons, Lives and Replays:
/// the student's full name, phone and a short rotating session
/// reference, repositioned periodically, above everything.
class WatermarkOverlay extends StatefulWidget {
  const WatermarkOverlay({
    super.key,
    this.sessionRef = '',
    this.name,
    this.phone,
  });

  /// Rotating session reference; playback authorizations carry the
  /// server's own `watermark.session` (Phase 2).
  final String sessionRef;

  /// Server-issued identity; defaults to the signed-in Student's full
  /// name and full phone (D-029: both are mandatory).
  final String? name;
  final String? phone;

  @override
  State<WatermarkOverlay> createState() => _WatermarkOverlayState();
}

class _WatermarkOverlayState extends State<WatermarkOverlay> {
  int _corner = 0;
  Timer? _rotation;

  @override
  void initState() {
    super.initState();
    _rotation = Timer.periodic(
      const Duration(seconds: 6),
      (_) => mounted ? setState(() => _corner = (_corner + 1) % 4) : null,
    );
  }

  @override
  void dispose() {
    _rotation?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final StudentProfile? student = AppScope.of(context).profile;
    final Alignment alignment = switch (_corner) {
      0 => Alignment.topLeft,
      1 => Alignment.topRight,
      2 => Alignment.bottomRight,
      _ => Alignment.bottomLeft,
    };

    return IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeInOutCubic,
          alignment: alignment,
          child: Text(
            <String>[
              '${widget.name ?? student?.fullName ?? ''} · '
                  '${widget.phone ?? student?.phone ?? ''}',
              if (widget.sessionRef.isNotEmpty) widget.sessionRef,
            ].join('\n'),
            textAlign: TextAlign.start,
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w700,
              fontSize: 11,
              height: 1.35,
              color: Colors.white.withValues(alpha: 0.16),
            ),
          ),
        ),
      ),
    );
  }
}
