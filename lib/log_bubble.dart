import 'package:flutter/material.dart';

class LogBubble extends StatelessWidget {
  final String text;
  final bool isUser;

  const LogBubble({
    super.key,
    required this.text,
    required this.isUser,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final bubbleColor = isUser
        ? colorScheme.secondary.withValues(alpha: 0.1)
        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);

    final borderColor = isUser
        ? colorScheme.secondary
        : colorScheme.outline;

    final label = isUser ? 'Client' : 'Agent';
    final labelColor = isUser ? colorScheme.secondary : colorScheme.outline;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: labelColor,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              color: bubbleColor,
              border: Border.all(color: borderColor, width: 1.0),
              borderRadius: BorderRadius.zero,
            ),
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'Courier',
                fontSize: 13.0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
