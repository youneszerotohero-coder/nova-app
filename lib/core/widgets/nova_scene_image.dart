import 'package:flutter/material.dart';

import 'nova_image.dart';

/// Painted warm scenes that stand in for photography across the UI.
/// Each scene layers soft light blobs over a base gradient, keeping the
/// sunny, joyful feel of the visual direction with zero binary assets.
enum NovaScene {
  sunrise([Color(0xFFF7C59F), Color(0xFFEF8A67), Color(0xFFC86B85)]),
  blush([Color(0xFFF9D8C0), Color(0xFFF2A3B3), Color(0xFFD77A8E)]),
  amber([Color(0xFFFBD3A2), Color(0xFFF5A15F), Color(0xFFDD7B4E)]),
  sky([Color(0xFFBFD8E8), Color(0xFF8FB8D8), Color(0xFF6D8FC0)]),
  sage([Color(0xFFD3E2C8), Color(0xFFA8C6A0), Color(0xFF7BA488)]),
  dusk([Color(0xFFE8B4C8), Color(0xFFB08BB8), Color(0xFF7E6C9E)]),
  sand([Color(0xFFF3E0C0), Color(0xFFE4B87F), Color(0xFFC98D5A)]),
  azure([Color(0xFF54A0F0), Color(0xFF2368CC), Color(0xFF0D3B7E)]),
  midnight([Color(0xFF4A6DB5), Color(0xFF27479A), Color(0xFF10275F)]);

  const NovaScene(this.colors);

  /// Base gradient stops, lightest first.
  final List<Color> colors;
}

/// Cover art for a course, offer, live or teacher. Shows the poster
/// [image] when there is one, fading it in over the painted [scene],
/// which stays as the placeholder while it decodes and as the fallback
/// if it cannot load.
class NovaSceneImage extends StatelessWidget {
  const NovaSceneImage({
    super.key,
    required this.scene,
    this.image,
    this.icon,
    this.alignment = Alignment.bottomLeft,
    this.iconScale = 1.0,
  });

  final NovaScene scene;

  /// Asset path of the poster photo.
  final String? image;

  /// Optional large soft-white glyph anchoring a painted scene. Never
  /// drawn over a photo, where it would read as clip-art.
  final IconData? icon;
  final Alignment alignment;
  final double iconScale;

  @override
  Widget build(BuildContext context) {
    final Widget painted = CustomPaint(
      painter: _ScenePainter(scene),
      child: icon == null || image != null
          ? const SizedBox.expand()
          : Align(
              alignment: alignment,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Transform.scale(
                  scale: iconScale,
                  child: Icon(
                    icon,
                    size: 64,
                    color: Colors.white.withValues(alpha: 0.75),
                    shadows: const [
                      Shadow(
                        offset: Offset(0, 6),
                        blurRadius: 24,
                        color: Color(0x331D1B1F),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
    if (image == null) return painted;

    return Stack(
      fit: StackFit.expand,
      children: [
        painted,
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return Image(
              image: novaImageProvider(
                image!,
                cacheWidth: _decodeWidth(context, constraints),
              ),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              frameBuilder: (
                BuildContext context,
                Widget child,
                int? frame,
                bool wasSynchronouslyLoaded,
              ) {
                if (wasSynchronouslyLoaded) return child;
                return AnimatedOpacity(
                  opacity: frame == null ? 0 : 1,
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOut,
                  child: child,
                );
              },
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            );
          },
        ),
      ],
    );
  }

  /// Decodes near display size instead of full resolution, with room
  /// for `BoxFit.cover` cropping a wider or taller poster. Images are
  /// never upscaled, so overshooting only costs nothing.
  static int? _decodeWidth(BuildContext context, BoxConstraints constraints) {
    final double longest = [
      constraints.maxWidth,
      constraints.maxHeight,
    ].where((double v) => v.isFinite).fold(0, (double a, double b) => a > b ? a : b);
    if (longest <= 0) return null;
    return (longest * 1.6 * MediaQuery.devicePixelRatioOf(context)).round();
  }
}

class _ScenePainter extends CustomPainter {
  _ScenePainter(this.scene);

  final NovaScene scene;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect bounds = Offset.zero & size;

    // Base vertical gradient, light at the top like backlit photos.
    final Paint base = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: scene.colors,
      ).createShader(bounds);
    canvas.drawRect(bounds, base);

    // Sun disc: a warm glow high on one side.
    final Paint sun = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60)
      ..color = Colors.white.withValues(alpha: 0.55);
    canvas.drawCircle(
      Offset(size.width * 0.78, size.height * 0.16),
      size.shortestSide * 0.22,
      sun,
    );

    // Soft color blobs for depth.
    void blob(Offset center, double radius, Color color) {
      final Paint paint = Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 48)
        ..color = color;
      canvas.drawCircle(center, radius, paint);
    }

    blob(
      Offset(size.width * 0.12, size.height * 0.32),
      size.shortestSide * 0.30,
      Colors.white.withValues(alpha: 0.30),
    );
    blob(
      Offset(size.width * 0.86, size.height * 0.72),
      size.shortestSide * 0.34,
      scene.colors.last.withValues(alpha: 0.55),
    );
    blob(
      Offset(size.width * 0.28, size.height * 0.94),
      size.shortestSide * 0.26,
      scene.colors[1].withValues(alpha: 0.42),
    );

    // Gentle top highlight, like late-afternoon haze.
    final Paint haze = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: const [0, 0.4],
        colors: [Colors.white.withValues(alpha: 0.22), Colors.transparent],
      ).createShader(bounds);
    canvas.drawRect(bounds, haze);
  }

  @override
  bool shouldRepaint(_ScenePainter oldDelegate) => oldDelegate.scene != scene;
}
