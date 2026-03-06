import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/utils/custom_emoji_catalog.dart';
import 'package:fluffychat/utils/custom_emoji_metadata.dart';

void main() {
  ImagePackImageContent imageWithMeta({
    required String mxc,
    required int order,
    List<String> aliases = const [],
    List<String> emojis = const [],
  }) {
    final image = ImagePackImageContent.fromJson(<String, Object?>{'url': mxc});
    return applyCustomEmojiMeta(
      image,
      CustomEmojiMeta(
        aliases: aliases,
        emojis: emojis,
        order: order,
        media: CustomEmojiMediaDescriptor(
          loop: true,
          primary: CustomEmojiMediaKind.image,
          sources: [
            CustomEmojiMediaSource(
              kind: CustomEmojiMediaKind.image,
              url: Uri.parse(mxc),
              mimetype: 'image/png',
            ),
          ],
        ),
      ),
    );
  }

  test('sorts packs and entries by metadata order', () {
    final userPack = applyCustomEmojiPackOrder(
      ImagePackContent.fromJson(<String, Object?>{
        'pack': <String, Object?>{'display_name': 'User'},
        'images': {
          'late': imageWithMeta(
            mxc: 'mxc://example.org/late',
            order: 2,
          ).toJson(),
          'early': imageWithMeta(
            mxc: 'mxc://example.org/early',
            order: 1,
          ).toJson(),
        },
      }),
      5,
    );

    final roomPack = applyCustomEmojiPackOrder(
      ImagePackContent.fromJson(<String, Object?>{
        'pack': <String, Object?>{'display_name': 'Room'},
        'images': {
          'room': imageWithMeta(
            mxc: 'mxc://example.org/room',
            order: 0,
          ).toJson(),
        },
      }),
      1,
    );

    final catalog = CustomEmojiCatalog.fromImagePacks(
      <String, ImagePackContent>{'user': userPack, 'room': roomPack},
    );

    expect(catalog.entries.map((e) => e.shortcode).toList(), [
      'room',
      'early',
      'late',
    ]);
  });

  test('marks duplicate shortcodes as requiring pack prefix', () {
    final packA = ImagePackContent.fromJson(<String, Object?>{
      'pack': <String, Object?>{'display_name': 'A'},
      'images': {
        'cat': imageWithMeta(mxc: 'mxc://example.org/a_cat', order: 0).toJson(),
      },
    });
    final packB = ImagePackContent.fromJson(<String, Object?>{
      'pack': <String, Object?>{'display_name': 'B'},
      'images': {
        'cat': imageWithMeta(mxc: 'mxc://example.org/b_cat', order: 0).toJson(),
      },
    });

    final catalog = CustomEmojiCatalog.fromImagePacks(
      <String, ImagePackContent>{'a': packA, 'b': packB},
    );

    final catA = catalog.resolveToken(shortcode: 'cat', pack: 'a');
    final catB = catalog.resolveToken(shortcode: 'cat', pack: 'b');

    expect(catA?.needsPackPrefix, isTrue);
    expect(catB?.needsPackPrefix, isTrue);
  });

  test('search finds canonical, alias and fallback emoji matches', () {
    final pack = ImagePackContent.fromJson(<String, Object?>{
      'pack': <String, Object?>{'display_name': 'Animals'},
      'images': {
        'cat': imageWithMeta(
          mxc: 'mxc://example.org/cat',
          order: 0,
          aliases: const ['kitty'],
          emojis: const ['🐱'],
        ).toJson(),
      },
    });

    final catalog = CustomEmojiCatalog.fromImagePacks(
      <String, ImagePackContent>{'animals': pack},
    );

    expect(catalog.search('cat').first.entry.shortcode, 'cat');
    expect(catalog.search('kitty').first.aliasHit, 'kitty');
    expect(catalog.search('🐱').first.emojiHit, '🐱');
  });

  test('exactOnly search only returns full matches', () {
    final pack = ImagePackContent.fromJson(<String, Object?>{
      'pack': <String, Object?>{'display_name': 'Animals'},
      'images': {
        'cat': imageWithMeta(
          mxc: 'mxc://example.org/cat',
          order: 0,
          aliases: const ['kitty'],
          emojis: const ['🐱'],
        ).toJson(),
      },
    });

    final catalog = CustomEmojiCatalog.fromImagePacks(
      <String, ImagePackContent>{'animals': pack},
    );

    expect(catalog.search('ca', exactOnly: true), isEmpty);
    expect(catalog.search('cat', exactOnly: true).first.entry.shortcode, 'cat');
    expect(catalog.search('kit', exactOnly: true), isEmpty);
    expect(catalog.search('kitty', exactOnly: true).first.aliasHit, 'kitty');
    expect(catalog.search('🐱', exactOnly: true).first.emojiHit, '🐱');
  });
}
