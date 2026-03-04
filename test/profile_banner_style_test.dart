import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/utils/profile_banner_style.dart';

void main() {
  test(
    'resolveProfileBannerStyle prefers dark foreground for bright samples',
    () {
      final style = resolveProfileBannerStyle(const [
        Color(0xFFFFFFFF),
        Color(0xFFF4F4F4),
        Color(0xFFEAEAEA),
      ]);

      expect(style.foregroundColor, Colors.black);
    },
  );

  test(
    'resolveProfileBannerStyle prefers light foreground for dark samples',
    () {
      final style = resolveProfileBannerStyle(const [
        Color(0xFF101010),
        Color(0xFF181818),
        Color(0xFF202020),
      ]);

      expect(style.foregroundColor, Colors.white);
    },
  );

  test('resolveProfileBannerStyle adds overlay for mixed-noise samples', () {
    final style = resolveProfileBannerStyle(const [
      Color(0xFFFFFFFF),
      Color(0xFF111111),
      Color(0xFFEFEFEF),
      Color(0xFF1B1B1B),
    ], targetContrast: 4.5);

    expect(style.overlayAlpha, greaterThan(0));
  });

  test(
    'resolveProfileBannerStyleFromBytes falls back on invalid image bytes',
    () {
      final style = resolveProfileBannerStyleFromBytes(
        Uint8List.fromList([1, 2, 3]),
      );

      expect(
        style.foregroundColor,
        ProfileBannerStyle.fallback.foregroundColor,
      );
      expect(style.overlayColor, ProfileBannerStyle.fallback.overlayColor);
      expect(style.overlayAlpha, ProfileBannerStyle.fallback.overlayAlpha);
    },
  );
}
