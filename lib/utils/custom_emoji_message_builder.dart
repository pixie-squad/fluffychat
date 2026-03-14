import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:matrix/matrix.dart';
// ignore: implementation_imports
import 'package:matrix/src/utils/markdown.dart' as matrix_markdown;

import 'package:fluffychat/utils/custom_emoji_catalog.dart';
import 'package:fluffychat/utils/custom_emoji_metadata.dart';

class CustomEmojiMessageBuildResult {
  final Map<String, dynamic> content;
  final String body;
  final String? formattedBody;

  const CustomEmojiMessageBuildResult({
    required this.content,
    required this.body,
    required this.formattedBody,
  });
}

CustomEmojiMessageBuildResult buildCustomEmojiMessage({
  required Room room,
  required String sourceBody,
  Event? inReplyTo,
  bool parseMarkdown = true,
  bool addMentions = true,
  String msgtype = MessageTypes.Text,
}) {
  final catalog = CustomEmojiCatalog.fromRoom(
    room,
    usage: ImagePackUsage.emoticon,
  );

  final body = _buildFallbackBody(sourceBody, catalog);

  String? formattedBody;
  Map<String, Object?>? embeddedEmojis;
  if (parseMarkdown) {
    final html = matrix_markdown.markdown(
      sourceBody,
      getEmotePacks: () => room.getImagePacksFlat(ImagePackUsage.emoticon),
      getMention: room.getMention,
      convertLinebreaks: room.client.convertLinebreaksInFormatting,
    );
    final patchResult = _patchEmojiFallbackInHtml(html, catalog, sourceBody);
    formattedBody = patchResult.html;
    embeddedEmojis = patchResult.embeddedEmojis;
  }

  final content = <String, dynamic>{
    'msgtype': msgtype,
    'body': body,
    customEmojiSourceBodyKey: sourceBody,
    if (embeddedEmojis != null && embeddedEmojis.isNotEmpty)
      customEmojiEmbeddedKey: embeddedEmojis,
  };

  final mentions = addMentions
      ? _buildMentions(room, sourceBody, inReplyTo: inReplyTo)
      : null;
  if (mentions != null) {
    content['m.mentions'] = mentions;
  }

  if (formattedBody != null && formattedBody.isNotEmpty) {
    content['format'] = 'org.matrix.custom.html';
    content['formatted_body'] = formattedBody;
  }

  return CustomEmojiMessageBuildResult(
    content: content,
    body: body,
    formattedBody: formattedBody,
  );
}

String _buildFallbackBody(String sourceBody, CustomEmojiCatalog catalog) {
  final output = StringBuffer();
  var cursor = 0;
  for (final token in parseCustomEmojiTokens(sourceBody)) {
    output.write(sourceBody.substring(cursor, token.start));
    final entry = catalog.resolveToken(
      shortcode: token.shortcode,
      pack: token.pack,
    );
    final fallback = entry?.primaryFallbackEmoji;
    output.write(
      (fallback != null && fallback.isNotEmpty) ? fallback : token.fullMatch,
    );
    cursor = token.end;
  }
  output.write(sourceBody.substring(cursor));
  return output.toString();
}

class _PatchResult {
  final String html;
  final Map<String, Object?> embeddedEmojis;
  const _PatchResult(this.html, this.embeddedEmojis);
}

_PatchResult _patchEmojiFallbackInHtml(
  String html,
  CustomEmojiCatalog catalog,
  String sourceBody,
) {
  final fragment = html_parser.parseFragment(html);
  final embedded = <String, Object?>{};

  for (final img in fragment.querySelectorAll('img[data-mx-emoticon]')) {
    final src = Uri.tryParse(img.attributes['src'] ?? '');
    if (src == null) continue;
    final entry = catalog.resolveByMxc(src);
    if (entry == null) continue;
    final fallback = entry.primaryFallbackEmoji;
    if (fallback != null && fallback.isNotEmpty) {
      img.attributes['alt'] = fallback;
      img.attributes['title'] = fallback;
    }
    // Embed image metadata so receivers without the pack can render it.
    final imageJson = entry.image.toJson();
    embedded[src.toString()] = imageJson;
  }

  final serialized = _serializeFragment(fragment);
  return _PatchResult(
    serialized.isNotEmpty ? serialized : sourceBody,
    embedded,
  );
}

Map<String, dynamic>? _buildMentions(
  Room room,
  String sourceBody, {
  Event? inReplyTo,
}) {
  final potentialMentions = sourceBody
      .split('@')
      .map(
        (text) => text.startsWith('[')
            ? '@${text.split(']').first}]'
            : '@${text.split(RegExp(r'\s+')).first}',
      )
      .toList();

  if (potentialMentions.isNotEmpty) {
    potentialMentions.removeAt(0);
  }

  final hasRoomMention = potentialMentions.remove('@room');

  final mentionUsers =
      potentialMentions
          .map(
            (mention) =>
                mention.isValidMatrixId ? mention : room.getMention(mention),
          )
          .whereType<String>()
          .toSet()
          .toList()
        ..remove(room.client.userID);

  if (inReplyTo != null) {
    mentionUsers.add(inReplyTo.senderId);
  }

  if (!hasRoomMention && mentionUsers.isEmpty) return null;

  return {
    if (hasRoomMention) 'room': true,
    if (mentionUsers.isNotEmpty) 'user_ids': mentionUsers,
  };
}

String _serializeFragment(dom.DocumentFragment fragment) => fragment.nodes
    .map(
      (node) => switch (node) {
        final dom.Element element => element.outerHtml,
        final dom.Text text => text.text,
        _ => node.text,
      },
    )
    .join();
