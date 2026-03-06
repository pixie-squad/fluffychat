import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/utils/custom_emoji_catalog.dart';
import 'package:fluffychat/widgets/custom_emoji_media.dart';

class ComposerEmojiTextController extends TextEditingController {
  Room _room;
  Client _client;
  CustomEmojiCatalog _catalog;

  ComposerEmojiTextController({
    required Room room,
    required Client client,
    super.text,
  }) : _room = room,
       _client = client,
       _catalog = CustomEmojiCatalog.fromRoom(
         room,
         usage: ImagePackUsage.emoticon,
       );

  Room get room => _room;

  Client get client => _client;

  CustomEmojiCatalog get catalog => _catalog;

  void updateRoomAndClient({required Room room, required Client client}) {
    _room = room;
    _client = client;
    refreshCatalog(notify: true);
  }

  void refreshCatalog({bool notify = false}) {
    _catalog = CustomEmojiCatalog.fromRoom(
      _room,
      usage: ImagePackUsage.emoticon,
    );
    if (notify) {
      notifyListeners();
    }
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final text = value.text;
    if (text.isEmpty) {
      return TextSpan(style: style, text: text);
    }

    final tokens = parseCustomEmojiTokens(text).toList();
    if (tokens.isEmpty) {
      return TextSpan(style: style, text: text);
    }

    final children = <InlineSpan>[];
    var cursor = 0;
    final fontSize =
        style?.fontSize ?? DefaultTextStyle.of(context).style.fontSize ?? 14;
    final emojiSize = (fontSize * 1.25).clamp(12.0, 40.0);

    for (final token in tokens) {
      if (token.start > cursor) {
        children.add(
          TextSpan(text: text.substring(cursor, token.start), style: style),
        );
      }

      final entry = _catalog.resolveToken(
        shortcode: token.shortcode,
        pack: token.pack,
      );
      if (entry == null) {
        children.add(TextSpan(text: token.fullMatch, style: style));
      } else {
        children.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            baseline: TextBaseline.alphabetic,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0.5),
              child: CustomEmojiMedia(
                client: _client,
                fallbackMxc: entry.primaryMxc,
                metadata: entry.metadata,
                fallbackEmoji: entry.primaryFallbackEmoji,
                width: emojiSize,
                height: emojiSize,
                fit: BoxFit.contain,
              ),
            ),
          ),
        );
      }

      cursor = token.end;
    }

    if (cursor < text.length) {
      children.add(TextSpan(text: text.substring(cursor), style: style));
    }

    return TextSpan(style: style, children: children);
  }
}
