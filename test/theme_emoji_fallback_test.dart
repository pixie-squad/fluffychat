import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/config/emoji_rendering.dart';
import 'package:fluffychat/config/themes.dart';

void main() {
  testWidgets('buildTheme applies configured emoji fallback list', (
    WidgetTester tester,
  ) async {
    late ThemeData theme;

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(1200, 800)),
        child: Builder(
          builder: (context) {
            theme = FluffyThemes.buildTheme(
              context,
              Brightness.light,
              Colors.blue,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final fallback = theme.textTheme.bodyMedium?.fontFamilyFallback;
    expect(fallback, isNotNull);
    expect(fallback, isNotEmpty);
    expect(fallback!.first, equals(emojiFontFamily));
  });
}
