import 'package:flutter/material.dart';

import '../../core/i18n/nova_strings.dart';
import '../../core/theme/nova_colors.dart';
import '../../data/live_store.dart';

/// D-186: the comment the Admin pinned, at the top of the Live chat (web
/// `PinnedCommentBanner`): its text under « Pinned by the teaching team »,
/// never its author.
class LivePinnedCommentBanner extends StatelessWidget {
  const LivePinnedCommentBanner({super.key, required this.comment});

  final LivePinnedComment comment;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: context.tr('live.pinned'),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: NovaColors.yellow.withValues(alpha: 0.14),
          border: Border.all(color: NovaColors.yellow, width: 1.5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.push_pin_rounded, size: 18, color: NovaColors.yellow),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('live.pinned'),
                    style: const TextStyle(
                      fontFamily: 'Geist',
                      fontWeight: FontWeight.w800,
                      fontSize: 11.5,
                      color: NovaColors.yellow,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    comment.message,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Geist',
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      height: 1.4,
                      color: NovaColors.textOnDark,
                    ),
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
