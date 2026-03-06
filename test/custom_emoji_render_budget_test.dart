import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/widgets/custom_emoji_media.dart';

void main() {
  tearDown(CustomEmojiAnimatedRenderBudget.resetForTests);

  group('CustomEmojiAnimatedRenderBudget', () {
    test('caps active animated renderers at maxActive', () {
      CustomEmojiAnimatedRenderBudget.resetForTests(maxActiveOverride: 50);

      final owners = List<Object>.generate(51, (_) => Object());

      for (var i = 0; i < 50; i++) {
        expect(CustomEmojiAnimatedRenderBudget.tryAcquire(owners[i]), isTrue);
      }

      expect(CustomEmojiAnimatedRenderBudget.activeCountForTests, 50);
      expect(CustomEmojiAnimatedRenderBudget.tryAcquire(owners.last), isFalse);
    });

    test('reacquiring the same owner does not use extra slots', () {
      final owner = Object();

      expect(CustomEmojiAnimatedRenderBudget.tryAcquire(owner), isTrue);
      expect(CustomEmojiAnimatedRenderBudget.tryAcquire(owner), isTrue);
      expect(CustomEmojiAnimatedRenderBudget.activeCountForTests, 1);
    });

    test('released slots can be reused', () {
      final first = Object();
      final second = Object();

      expect(CustomEmojiAnimatedRenderBudget.tryAcquire(first), isTrue);
      CustomEmojiAnimatedRenderBudget.release(first);
      expect(CustomEmojiAnimatedRenderBudget.activeCountForTests, 0);
      expect(CustomEmojiAnimatedRenderBudget.tryAcquire(second), isTrue);
      expect(CustomEmojiAnimatedRenderBudget.activeCountForTests, 1);
    });

    test('respects custom maxActive override for tests', () {
      CustomEmojiAnimatedRenderBudget.resetForTests(maxActiveOverride: 3);

      final owners = List<Object>.generate(4, (_) => Object());

      for (var i = 0; i < 3; i++) {
        expect(CustomEmojiAnimatedRenderBudget.tryAcquire(owners[i]), isTrue);
      }
      expect(CustomEmojiAnimatedRenderBudget.tryAcquire(owners[3]), isFalse);
    });
  });
}
