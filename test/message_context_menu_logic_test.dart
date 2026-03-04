import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pages/chat/events/message_context_menu_logic.dart';

void main() {
  group('rankQuickReactions', () {
    test('returns fallback first 6 when usage is empty', () {
      expect(
        rankQuickReactions({}),
        equals(['👍', '❤️', '😂', '😮', '😢', '👌']),
      );
    });

    test('sorts usage by count desc and key asc for ties', () {
      expect(
        rankQuickReactions({'z': 5, 'a': 5, '👍': 2}),
        equals(['a', 'z', '👍', '❤️', '😂', '😮']),
      );
    });

    test('removes duplicates between usage and fallback list', () {
      expect(
        rankQuickReactions({'👍': 10, '❤️': 8}),
        equals(['👍', '❤️', '😂', '😮', '😢', '👌']),
      );
    });
  });

  group('resolveMessageContextActionAvailability', () {
    test('edit is only enabled for own sent event in non-archived room', () {
      final notOwn = resolveMessageContextActionAvailability(
        isSent: true,
        isError: false,
        isRedacted: false,
        isOwnEvent: false,
        isArchived: false,
        canRedact: true,
        roomCanSendDefaultMessages: true,
        hasActiveThread: false,
      );
      final own = resolveMessageContextActionAvailability(
        isSent: true,
        isError: false,
        isRedacted: false,
        isOwnEvent: true,
        isArchived: false,
        canRedact: true,
        roomCanSendDefaultMessages: true,
        hasActiveThread: false,
      );

      expect(notOwn.edit, isFalse);
      expect(own.edit, isTrue);
    });

    test('redact and report are disabled for unsupported statuses', () {
      final availability = resolveMessageContextActionAvailability(
        isSent: false,
        isError: true,
        isRedacted: false,
        isOwnEvent: true,
        isArchived: false,
        canRedact: false,
        roomCanSendDefaultMessages: true,
        hasActiveThread: false,
      );

      expect(availability.redact, isFalse);
      expect(availability.report, isFalse);
    });

    test('reply in thread is disabled when already in a thread', () {
      final availability = resolveMessageContextActionAvailability(
        isSent: true,
        isError: false,
        isRedacted: false,
        isOwnEvent: true,
        isArchived: false,
        canRedact: true,
        roomCanSendDefaultMessages: true,
        hasActiveThread: true,
      );

      expect(availability.replyInThread, isFalse);
    });
  });
}
