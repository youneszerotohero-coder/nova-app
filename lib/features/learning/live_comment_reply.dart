import 'package:flutter/material.dart';

import '../../core/i18n/nova_strings.dart';
import '../../core/theme/nova_colors.dart';
import '../../data/live_store.dart';

/// D-204: the Admin's private answer to this Student's comment, over the
/// picture with the question it answers (web `StudentReplyCard`), until the
/// Student hides it to keep watching.
class LiveCommentReplyCard extends StatelessWidget {
  const LiveCommentReplyCard({super.key, required this.reply, required this.onHide});

  final LiveCommentReply reply;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: context.tr('live.replyFromTeam'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 6, 10),
          decoration: BoxDecoration(
            color: NovaColors.ink.withValues(alpha: 0.92),
            border: Border.all(color: NovaColors.yellow, width: 1.5),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.mark_chat_read_rounded, size: 20, color: NovaColors.yellow),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.tr('live.replyFromTeam'),
                      style: const TextStyle(
                        fontFamily: 'Geist',
                        fontWeight: FontWeight.w800,
                        fontSize: 11.5,
                        color: NovaColors.yellow,
                      ),
                    ),
                    if (reply.question.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 3),
                      Text(
                        context.trf('live.yourQuestion', <String, String>{'question': reply.question}),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 12.5,
                          height: 1.35,
                          color: NovaColors.textMutedOnDark,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      reply.message,
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Geist',
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        height: 1.4,
                        color: NovaColors.textOnDark,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onHide,
                tooltip: context.tr('live.hideReply'),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded, size: 20, color: NovaColors.textOnDark),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
