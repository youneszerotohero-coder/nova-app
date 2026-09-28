import 'package:flutter/widgets.dart';

/// Covers and portraits come from `/api/v1` as absolute URLs; bundled
/// artwork (tests, placeholders) stays an asset path. One provider for
/// both, decoded near display size when [cacheWidth] is given.
ImageProvider<Object> novaImageProvider(String source, {int? cacheWidth}) {
  final ImageProvider<Object> provider =
      source.startsWith('http://') || source.startsWith('https://')
          ? NetworkImage(source)
          : AssetImage(source);
  return ResizeImage.resizeIfNeeded(cacheWidth, null, provider);
}
