import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/utils/custom_emoji_metadata.dart';

void main() {
  group('CustomEmojiMeta', () {
    test('builds legacy defaults when metadata is missing', () {
      final image = ImagePackImageContent.fromJson(<String, Object?>{
        'url': 'mxc://example.org/plain',
      });

      final meta = CustomEmojiMeta.fromImage(image);

      expect(meta.aliases, isEmpty);
      expect(meta.emojis, isEmpty);
      expect(meta.order, 0);
      expect(meta.media.loop, isTrue);
      expect(meta.media.primary, CustomEmojiMediaKind.image);
      expect(meta.media.sources, hasLength(1));
      expect(
        meta.media.sources.single.url.toString(),
        'mxc://example.org/plain',
      );
    });

    test('parses metadata and preserves unknown image keys after writing', () {
      final image = ImagePackImageContent.fromJson(<String, Object?>{
        'url': 'mxc://example.org/cat',
        'xyz.custom_key': 'keep_me',
        customEmojiMetaKey: {
          'aliases': [' kitty ', ':cat_alt:', 'kitty'],
          'emojis': ['😺', '😺', '🐱'],
          'order': '3',
          'media': {
            'loop': true,
            'primary': 'mp4',
            'sources': [
              {
                'kind': 'mp4',
                'url': 'mxc://example.org/cat_mp4',
                'mimetype': 'video/mp4',
              },
            ],
          },
        },
      });

      final parsed = CustomEmojiMeta.fromImage(image);
      expect(parsed.aliases, equals(['kitty', 'cat_alt']));
      expect(parsed.emojis, equals(['😺', '🐱']));
      expect(parsed.order, 3);
      expect(parsed.media.primary, CustomEmojiMediaKind.mp4);
      expect(
        parsed.media.sources.single.url.toString(),
        'mxc://example.org/cat_mp4',
      );

      final updated = applyCustomEmojiMeta(
        image,
        CustomEmojiMeta(
          aliases: const ['cat'],
          emojis: const ['🐈'],
          order: 8,
          media: CustomEmojiMediaDescriptor(
            loop: true,
            primary: CustomEmojiMediaKind.image,
            sources: [
              CustomEmojiMediaSource(
                kind: CustomEmojiMediaKind.image,
                url: Uri.parse('mxc://example.org/cat'),
                mimetype: 'image/png',
              ),
            ],
          ),
        ),
      );

      final updatedJson = updated.toJson();
      expect(updatedJson['xyz.custom_key'], 'keep_me');
      expect(updatedJson[customEmojiMetaKey], containsPair('order', 8));
    });
  });

  group('Pack order', () {
    test('reads and writes pack order metadata', () {
      final pack = ImagePackContent.fromJson(<String, Object?>{
        'images': <String, Object?>{},
        'pack': <String, Object?>{},
        customEmojiPackOrderKey: 4,
      });
      expect(getCustomEmojiPackOrder(pack), 4);

      final updated = applyCustomEmojiPackOrder(pack, 11);
      expect(getCustomEmojiPackOrder(updated), 11);
    });
  });
}
