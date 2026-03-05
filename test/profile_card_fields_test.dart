import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/utils/profile_card_fields.dart';

void main() {
  group('FeaturedChannelProfileField', () {
    test('fromJson parses valid payload', () {
      final field = FeaturedChannelProfileField.fromJson({
        'room_id': '!room:example.org',
        'title': 'Fluffy Channel',
        'subtitle': 'General chat',
        'avatar_url': 'mxc://example.org/abc123',
      });

      expect(field.roomId, '!room:example.org');
      expect(field.title, 'Fluffy Channel');
      expect(field.subtitle, 'General chat');
      expect(field.avatarUrl, Uri.parse('mxc://example.org/abc123'));
    });

    test('fromJson rejects missing or empty room id', () {
      expect(
        () => FeaturedChannelProfileField.fromJson({}),
        throwsFormatException,
      );
      expect(
        () => FeaturedChannelProfileField.fromJson({'room_id': ''}),
        throwsFormatException,
      );
      expect(
        () => FeaturedChannelProfileField.fromJson({'room_id': '   '}),
        throwsFormatException,
      );
    });

    test('fromJson accepts only mxc avatar urls', () {
      final field = FeaturedChannelProfileField.fromJson({
        'room_id': '!room:example.org',
        'avatar_url': 'https://example.org/avatar.png',
      });

      expect(field.avatarUrl, isNull);
    });

    test('toJson emits expected shape', () {
      final field = FeaturedChannelProfileField(
        roomId: '#fluffy:example.org',
        title: 'Fluffy',
        subtitle: 'A room',
        avatarUrl: Uri.parse('mxc://example.org/avatar'),
      );

      expect(field.toJson(), {
        'room_id': '#fluffy:example.org',
        'title': 'Fluffy',
        'subtitle': 'A room',
        'avatar_url': 'mxc://example.org/avatar',
      });
    });
  });

  group('normalizeFeaturedChannelIdentifier', () {
    test('normalizes room id input', () {
      expect(
        normalizeFeaturedChannelIdentifier('!room:example.org'),
        '!room:example.org',
      );
    });

    test('normalizes room alias input', () {
      expect(
        normalizeFeaturedChannelIdentifier('#fluffy:example.org'),
        '#fluffy:example.org',
      );
    });

    test('normalizes matrix.to alias links', () {
      expect(
        normalizeFeaturedChannelIdentifier(
          'https://matrix.to/#/%23fluffy:example.org?via=example.org',
        ),
        '#fluffy:example.org',
      );
    });

    test('normalizes matrix.to room id links', () {
      expect(
        normalizeFeaturedChannelIdentifier(
          'https://matrix.to/#/!room:example.org',
        ),
        '!room:example.org',
      );
    });

    test('rejects invalid input', () {
      expect(normalizeFeaturedChannelIdentifier('not-a-room'), isNull);
      expect(normalizeFeaturedChannelIdentifier('@alice:example.org'), isNull);
      expect(
        normalizeFeaturedChannelIdentifier(
          'https://matrix.to/#/@alice:example.org',
        ),
        isNull,
      );
    });
  });
}
