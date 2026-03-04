import 'package:flutter/foundation.dart';

@immutable
class MessageContextActionAvailability {
  final bool reply;
  final bool copy;
  final bool forward;
  final bool replyInThread;
  final bool select;
  final bool edit;
  final bool redact;
  final bool report;

  const MessageContextActionAvailability({
    required this.reply,
    required this.copy,
    required this.forward,
    required this.replyInThread,
    required this.select,
    required this.edit,
    required this.redact,
    required this.report,
  });
}

MessageContextActionAvailability resolveMessageContextActionAvailability({
  required bool isSent,
  required bool isError,
  required bool isRedacted,
  required bool isOwnEvent,
  required bool isArchived,
  required bool canRedact,
  required bool roomCanSendDefaultMessages,
  required bool hasActiveThread,
}) {
  return MessageContextActionAvailability(
    reply: isSent,
    copy: true,
    forward: !isError,
    replyInThread: isSent && roomCanSendDefaultMessages && !hasActiveThread,
    select: !isRedacted,
    edit: isOwnEvent && isSent && !isArchived,
    redact: canRedact,
    report: isSent,
  );
}

List<String> rankQuickReactions(
  Map<String, int> reactionUsage, {
  List<String> fallbackReactions = const ['👍', '❤️', '😂', '😮', '😢', '👌'],
  int limit = 6,
}) {
  if (limit <= 0) return const [];

  final normalizedUsage = <String, int>{};
  for (final entry in reactionUsage.entries) {
    final key = entry.key.trim();
    if (key.isEmpty || entry.value <= 0) continue;
    normalizedUsage[key] = entry.value;
  }

  final sortedUsage = normalizedUsage.entries.toList()
    ..sort((a, b) {
      final countCompare = b.value.compareTo(a.value);
      if (countCompare != 0) return countCompare;
      return a.key.compareTo(b.key);
    });

  final result = <String>[];
  final seen = <String>{};

  for (final entry in sortedUsage) {
    if (seen.add(entry.key)) {
      result.add(entry.key);
    }
    if (result.length >= limit) {
      return result;
    }
  }

  for (final fallback in fallbackReactions) {
    final key = fallback.trim();
    if (key.isEmpty) continue;
    if (seen.add(key)) {
      result.add(key);
    }
    if (result.length >= limit) {
      break;
    }
  }

  return result;
}
