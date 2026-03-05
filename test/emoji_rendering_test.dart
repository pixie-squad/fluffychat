import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/config/emoji_rendering.dart';

void main() {
  test('emoji fallback list starts with Apple emoji font family', () {
    expect(emojiFallbackFamilies, isNotEmpty);
    expect(emojiFallbackFamilies.first, emojiFontFamily);
  });

  test('apple emoji text style points to configured emoji family', () {
    expect(appleEmojiTextStyle.fontFamily, emojiFontFamily);
    expect(
      appleEmojiTextStyle.fontFamilyFallback,
      equals(emojiFallbackFamilies),
    );
  });
}
