import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/nova_colors.dart';
import '../utils/player_fullscreen.dart';

/// D-188 (amends D-164): the PC app is the phone app with a desktop UX. Every
/// desktop-only behaviour goes through [isDesktopApp] (the platform) and
/// [desktopLayoutOf] (the platform and a wide enough window), so Android and
/// iPhone never change.
///
/// [defaultTargetPlatform] (not `dart:io` Platform) so widget tests can
/// simulate the PC app with `debugDefaultTargetPlatformOverride`.
bool get isDesktopApp =>
    !kIsWeb &&
    switch (defaultTargetPlatform) {
      TargetPlatform.windows || TargetPlatform.linux || TargetPlatform.macOS => true,
      _ => false,
    };

/// Desktop metrics (logical pixels).
abstract final class DesktopMetrics {
  /// Below this window width the PC app keeps the phone layout (a window
  /// squeezed to a phone's width).
  static const double minLayoutWidth = 840;

  /// Below this content width lists stay one card per row.
  static const double gridMinWidth = 600;

  /// The pages' content column, centred in wider windows (D-193: 1600, so a
  /// 1920 px screen is used; 1280 left wide empty sides).
  static const double contentMaxWidth = 1600;

  /// Sign-in, registration and other one-form pages.
  static const double formMaxWidth = 560;

  /// The navigation sidebar.
  static const double railWidth = 232;

  /// The narrowest card of a catalogue grid (auto-fit columns).
  static const double cardMinWidth = 290;

  /// Space between grid cards.
  static const double gridGap = 18;

  /// Page transitions: a short fade instead of the phone's slide.
  static const Duration pageTransition = Duration(milliseconds: 120);

  /// D-193: the desktop layout draws everything at this scale. The pages
  /// keep the phone's sizes (44 px squares, 52 px buttons, 16 px text), which
  /// on a PC at Windows' usual 125–150 % look too big; 0.9 gives desktop
  /// sizes (40 px, 47 px, 14.4 px) without touching any phone layout.
  static const double uiScale = 0.9;
}

/// Whether this context lays out as the PC app: a desktop platform and a
/// content width of at least [DesktopMetrics.minLayoutWidth]. Inside a
/// [DesktopFrame] the width is the frame's, so a narrow form frame lays its
/// page out as on a phone.
bool desktopLayoutOf(BuildContext context) =>
    isDesktopApp && MediaQuery.sizeOf(context).width >= DesktopMetrics.minLayoutWidth;

/// Whether this context shows catalogues and lists as card grids: the PC
/// app with at least [DesktopMetrics.gridMinWidth] of content width (so
/// cards never stretch to the whole window, even beside the sidebar of a
/// mid-size window).
bool desktopGridOf(BuildContext context) =>
    isDesktopApp && MediaQuery.sizeOf(context).width >= DesktopMetrics.gridMinWidth;

/// How many cards of at least [minItemWidth] fit in [width] (auto-fit),
/// between [minColumns] and [maxColumns].
int desktopColumns(
  double width, {
  double minItemWidth = DesktopMetrics.cardMinWidth,
  double gap = DesktopMetrics.gridGap,
  int minColumns = 2,
  int maxColumns = 4,
}) {
  final int fit = ((width + gap) / (minItemWidth + gap)).floor();
  return math.max(minColumns, math.min(maxColumns, fit));
}

/// D-193: lays the PC app out at [DesktopMetrics.uiScale] in a desktop
/// window ([DesktopMetrics.minLayoutWidth] or wider): the app gets a
/// [MediaQuery] size 1 / scale larger, with the matching pixel ratio (images
/// decode for the real pixels), and is drawn scaled to the window. Hit
/// testing follows the scale, and the PC video hole reports its place through
/// the same transform. A narrower window and phones draw at 1. The tree is
/// the same at every width, so crossing the width keeps every state.
class DesktopUiScale extends StatelessWidget {
  const DesktopUiScale({super.key, required this.child});

  final Widget child;

  /// The scale for a window [width] logical pixels wide.
  static double scaleFor(double width) =>
      isDesktopApp && width >= DesktopMetrics.minLayoutWidth ? DesktopMetrics.uiScale : 1;

  @override
  Widget build(BuildContext context) {
    if (!isDesktopApp) return child;
    final MediaQueryData media = MediaQuery.of(context);
    final double scale = scaleFor(media.size.width);
    final Size size = media.size / scale;
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.fill,
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: MediaQuery(
            data: media.copyWith(
              size: size,
              devicePixelRatio: media.devicePixelRatio * scale,
              padding: media.padding / scale,
              viewPadding: media.viewPadding / scale,
              viewInsets: media.viewInsets / scale,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Centres [child] in a column at most [maxWidth] wide on desktop, the sides
/// painted with the page colour; the column's width becomes the
/// [MediaQuery] width so the page sizes itself for it. While a player is
/// full screen ([playerFullscreen]) the column takes the whole window. On
/// phones [child] is returned unchanged.
///
/// The widget tree is the same whatever the window width, so resizing the
/// window never rebuilds the page (scroll positions, players and forms keep
/// their state).
class DesktopFrame extends StatelessWidget {
  const DesktopFrame({
    super.key,
    required this.child,
    this.maxWidth = DesktopMetrics.contentMaxWidth,
    this.color,
  });

  const DesktopFrame.form({super.key, required this.child, this.color}) : maxWidth = DesktopMetrics.formMaxWidth;

  final Widget child;
  final double maxWidth;

  /// The sides' colour; the page background by default.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (!isDesktopApp) return child;
    return ValueListenableBuilder<bool>(
      valueListenable: playerFullscreen,
      child: child,
      builder: (BuildContext context, bool fullscreen, Widget? child) => LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final MediaQueryData media = MediaQuery.of(context);
          final double width = fullscreen ? constraints.maxWidth : math.min(constraints.maxWidth, maxWidth);
          return ColoredBox(
            color: color ?? NovaColors.paper,
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: width,
                child: MediaQuery(
                  data: media.copyWith(size: Size(width, media.size.height)),
                  child: child!,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Cards in rows of auto-fit columns (desktop catalogues and lists). With
/// [equalHeight] the cards of a row share one height (as the website's grid
/// rows), which needs cards that report intrinsic sizes.
class DesktopCardGrid extends StatelessWidget {
  const DesktopCardGrid({
    super.key,
    required this.children,
    this.minItemWidth = DesktopMetrics.cardMinWidth,
    this.maxColumns = 4,
    this.minColumns = 2,
    this.gap = DesktopMetrics.gridGap,
    this.equalHeight = false,
  });

  final List<Widget> children;
  final double minItemWidth;
  final int maxColumns;
  final int minColumns;
  final double gap;
  final bool equalHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final int columns = desktopColumns(
          constraints.maxWidth,
          minItemWidth: minItemWidth,
          gap: gap,
          minColumns: minColumns,
          maxColumns: maxColumns,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (int start = 0; start < children.length; start += columns) ...[
              if (start > 0) SizedBox(height: gap),
              _row(children.skip(start).take(columns).toList(), columns),
            ],
          ],
        );
      },
    );
  }

  Widget _row(List<Widget> cells, int columns) {
    final Widget row = Row(
      crossAxisAlignment: equalHeight ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < columns; i++) ...[
          if (i > 0) SizedBox(width: gap),
          Expanded(child: i < cells.length ? cells[i] : const SizedBox.shrink()),
        ],
      ],
    );
    return equalHeight ? IntrinsicHeight(child: row) : row;
  }
}

/// [DesktopCardGrid] as a sliver: rows are built lazily as they scroll in,
/// for long catalogues.
class SliverDesktopCardGrid extends StatelessWidget {
  const SliverDesktopCardGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.minItemWidth = DesktopMetrics.cardMinWidth,
    this.maxColumns = 4,
    this.gap = DesktopMetrics.gridGap,
    this.equalHeight = false,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double minItemWidth;
  final int maxColumns;
  final double gap;
  final bool equalHeight;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (BuildContext context, SliverConstraints constraints) {
        final int columns = desktopColumns(constraints.crossAxisExtent, minItemWidth: minItemWidth, gap: gap, maxColumns: maxColumns);
        final int rows = (itemCount / columns).ceil();
        return SliverList.separated(
          itemCount: rows,
          separatorBuilder: (_, _) => SizedBox(height: gap),
          itemBuilder: (BuildContext context, int row) {
            final Widget line = Row(
              crossAxisAlignment: equalHeight ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < columns; i++) ...[
                  if (i > 0) SizedBox(width: gap),
                  Expanded(
                    child: row * columns + i < itemCount ? itemBuilder(context, row * columns + i) : const SizedBox.shrink(),
                  ),
                ],
              ],
            );
            return equalHeight ? IntrinsicHeight(child: line) : line;
          },
        );
      },
    );
  }
}
