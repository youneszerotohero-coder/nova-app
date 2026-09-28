import 'package:flutter/material.dart';

import 'nova_image.dart';

import '../theme/nova_colors.dart';

/// A person's avatar: their [photo] when one exists, otherwise a
/// deterministic warm-gradient monogram. An optional `colors` pair
/// overrides the derived palette.
class MonogramAvatar extends StatelessWidget {
  const MonogramAvatar({
    super.key,
    required this.label,
    this.size = 44,
    this.ringColor,
    this.showRing = true,
    this.colors,
    this.photo,
  });

  final String label;
  final double size;

  /// Defaults to the active paper tone when null.
  final Color? ringColor;
  final bool showRing;
  final List<Color>? colors;

  /// Asset path of the portrait; the monogram is the fallback.
  final String? photo;

  static const List<List<Color>> _palettes = [
    [Color(0xFFF6A45C), Color(0xFFEC5F9D)],
    [Color(0xFFF2C14E), Color(0xFFF2806E)],
    [Color(0xFF9BC1BC), Color(0xFF6D9DC5)],
    [Color(0xFFC9A7EB), Color(0xFF8E7CC3)],
    [Color(0xFFF49FBC), Color(0xFFB388EB)],
    [Color(0xFF87BCA4), Color(0xFF5B9279)],
  ];

  List<Color> _colorsFor(String name) {
    final int hash = name.toLowerCase().codeUnits.fold(
          7,
          (int acc, int code) => (acc * 31 + code) & 0xFFFF,
        );
    return _palettes[hash % _palettes.length];
  }

  String _initials(String name) {
    final List<String> parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    final String first = parts.first.characters.first;
    final String last = parts.last.characters.first;
    return '$first$last'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final List<Color> palette = colors ?? _colorsFor(label);
    final Widget monogram = Center(
      child: Text(
        _initials(label),
        style: TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w700,
          fontSize: size * 0.34,
          height: 1,
          letterSpacing: -0.2,
          color: Colors.white,
        ),
      ),
    );

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      foregroundDecoration: showRing
          ? BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: ringColor ?? NovaColors.paper,
                width: 2,
              ),
            )
          : null,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: palette,
        ),
      ),
      child: photo == null
          ? monogram
          : Image(
              image: novaImageProvider(
                photo!,
                cacheWidth:
                    (size * MediaQuery.devicePixelRatioOf(context)).round(),
              ),
              fit: BoxFit.cover,
              // The monogram shows through until the photo is ready,
              // and stays if it cannot load.
              frameBuilder: (_, Widget child, int? frame, bool sync) =>
                  sync || frame != null ? child : monogram,
              errorBuilder: (_, _, _) => monogram,
            ),
    );
  }
}
