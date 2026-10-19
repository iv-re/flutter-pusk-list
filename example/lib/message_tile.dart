import 'package:example/chat_data.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// One chat bubble.
class MessageTile extends StatelessWidget {
  const MessageTile({
    required this.message,
    required this.highlighted,
    this.onLongPress,
    super.key,
  });

  final Message message;
  final ValueListenable<String?> highlighted;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mine = message.author.isMe;
    final foreground = mine ? scheme.onPrimary : scheme.onSurface;

    final bubble = ValueListenableBuilder(
      valueListenable: highlighted,
      builder: (context, id, child) => AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: id == message.id
              ? scheme.tertiary
              : mine
              ? scheme.primary
              : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(18),
        ),
        child: child,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 9, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!mine)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  message.author.name,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: message.author.color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Text.rich(
              TextSpan(
                text: message.text,
                children: const [
                  // Room for the time in the last line.
                  WidgetSpan(child: SizedBox(width: 44)),
                ],
              ),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: foreground,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisAlignment: mine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!mine) ...[_Avatar(message.author), const SizedBox(width: 8)],
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: GestureDetector(
                onLongPress: onLongPress,
                child: Stack(
                  children: [
                    bubble,
                    Positioned(
                      right: 12,
                      bottom: 7,
                      child: Text(
                        formatTime(message.time),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: foreground.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar(this.author);

  final Author author;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 15,
      backgroundColor: author.color,
      child: Text(
        author.name[0],
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }
}

/// Day chip or spacing between two messages.
class MessageSeparator extends StatelessWidget {
  const MessageSeparator({required this.newer, required this.older, super.key});

  final Message newer;
  final Message older;

  @override
  Widget build(BuildContext context) {
    if (isSameDay(newer.time, older.time)) return const SizedBox(height: 8);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.85,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              formatDay(newer.time),
              style: theme.textTheme.labelMedium,
            ),
          ),
        ),
      ),
    );
  }
}
