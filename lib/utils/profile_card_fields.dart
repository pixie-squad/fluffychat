import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

const String profileBioField = 'r.trd.bio';
const String profileBackgroundColorField = 'r.trd.profile_bg_color';
const String profileBannerField = 'r.trd.profile_banner_mxc';
const String profileEmojiStatusField = 'r.trd.emoji_status_mxc';
const String profileFeaturedChannelField = 'r.trd.featured_channel';

class FeaturedChannelProfileField {
  final String roomId;
  final String? title;
  final String? subtitle;
  final Uri? avatarUrl;

  const FeaturedChannelProfileField({
    required this.roomId,
    this.title,
    this.subtitle,
    this.avatarUrl,
  });

  factory FeaturedChannelProfileField.fromJson(Map<Object?, Object?> json) {
    final roomId = json['room_id'];
    if (roomId is! String || roomId.trim().isEmpty) {
      throw const FormatException('Invalid featured channel room id');
    }

    final title = json['title'];
    final subtitle = json['subtitle'];
    final avatarRaw = json['avatar_url'];
    final avatar = avatarRaw is String ? Uri.tryParse(avatarRaw) : null;

    return FeaturedChannelProfileField(
      roomId: roomId.trim(),
      title: title is String ? title : null,
      subtitle: subtitle is String ? subtitle : null,
      avatarUrl: avatar?.scheme == 'mxc' ? avatar : null,
    );
  }

  Map<String, Object?> toJson() => {
    'room_id': roomId,
    if (title != null && title!.trim().isNotEmpty) 'title': title!.trim(),
    if (subtitle != null && subtitle!.trim().isNotEmpty)
      'subtitle': subtitle!.trim(),
    if (avatarUrl?.scheme == 'mxc') 'avatar_url': avatarUrl.toString(),
  };
}

String? normalizeFeaturedChannelIdentifier(String input) {
  var value = input.trim();
  if (value.isEmpty) return null;

  final parsed = Uri.tryParse(value);
  final isMatrixTo =
      parsed != null &&
      (parsed.scheme == 'http' || parsed.scheme == 'https') &&
      parsed.host.toLowerCase() == 'matrix.to';
  if (isMatrixTo) {
    var fragment = parsed.fragment;
    if (fragment.isEmpty) return null;
    fragment = Uri.decodeComponent(fragment);
    if (fragment.startsWith('/')) {
      fragment = fragment.substring(1);
    }
    final queryStart = fragment.indexOf('?');
    if (queryStart > -1) {
      fragment = fragment.substring(0, queryStart);
    }
    value = fragment.trim();
  }

  if (!value.isValidMatrixId || !{'#', '!'}.contains(value.sigil)) {
    return null;
  }
  return value;
}

class ProfileCardFields {
  final String? bio;
  final Color? backgroundColor;
  final Uri? bannerMxc;
  final Uri? emojiStatusMxc;
  final FeaturedChannelProfileField? featuredChannel;

  const ProfileCardFields({
    this.bio,
    this.backgroundColor,
    this.bannerMxc,
    this.emojiStatusMxc,
    this.featuredChannel,
  });
}

class _ProfileEmojiStatusCache {
  final Map<String, Uri?> _cache = {};
  final Map<String, Future<Uri?>> _inFlight = {};
  final ValueNotifier<int> version = ValueNotifier<int>(0);

  bool has(String userId) => _cache.containsKey(userId);

  Uri? getCached(String userId) => _cache[userId];

  Future<Uri?> get(Client client, String userId) {
    if (_cache.containsKey(userId)) {
      return Future<Uri?>.value(_cache[userId]);
    }
    final pending = _inFlight[userId];
    if (pending != null) return pending;

    final future = loadProfileEmojiStatus(client, userId).then((uri) {
      _cache[userId] = uri;
      _inFlight.remove(userId);
      return uri;
    });
    _inFlight[userId] = future;
    return future;
  }

  void invalidate(String userId) {
    _cache.remove(userId);
    _inFlight.remove(userId);
    version.value++;
  }
}

final profileEmojiStatusCache = _ProfileEmojiStatusCache();

Future<ProfileCardFields> loadProfileCardFields(
  Client client,
  String userId,
) async {
  final bioRaw = await _loadProfileField(client, userId, profileBioField);
  final backgroundRaw = await _loadProfileField(
    client,
    userId,
    profileBackgroundColorField,
  );
  final bannerRaw = await _loadProfileField(client, userId, profileBannerField);
  final emojiRaw = await _loadProfileField(
    client,
    userId,
    profileEmojiStatusField,
  );
  final featuredRaw = await _loadProfileField(
    client,
    userId,
    profileFeaturedChannelField,
  );

  return ProfileCardFields(
    bio: _readStringField(bioRaw),
    backgroundColor: _readBackgroundColorField(backgroundRaw),
    bannerMxc: _readMxcUriField(bannerRaw),
    emojiStatusMxc: _readMxcUriField(emojiRaw),
    featuredChannel: _readFeaturedChannelField(featuredRaw),
  );
}

Future<Uri?> loadProfileEmojiStatus(Client client, String userId) async {
  final emojiRaw = await _loadProfileField(
    client,
    userId,
    profileEmojiStatusField,
  );
  return _readMxcUriField(emojiRaw);
}

Future<Object?> _loadProfileField(
  Client client,
  String userId,
  String key,
) async {
  try {
    final data = await client.getProfileField(userId, key);
    return data[key];
  } catch (_) {
    return null;
  }
}

String? _readStringField(Object? raw) {
  if (raw is! String) return null;
  final value = raw.trim();
  return value.isEmpty ? null : value;
}

Color? _readBackgroundColorField(Object? raw) {
  if (raw is num) {
    return Color(raw.toInt());
  }
  if (raw is String) {
    final parsed = int.tryParse(raw);
    if (parsed != null) return Color(parsed);
  }
  return null;
}

Uri? _readMxcUriField(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  final uri = Uri.tryParse(raw);
  return uri?.scheme == 'mxc' ? uri : null;
}

FeaturedChannelProfileField? _readFeaturedChannelField(Object? raw) {
  if (raw is! Map<Object?, Object?>) return null;
  try {
    return FeaturedChannelProfileField.fromJson(raw);
  } catch (_) {
    return null;
  }
}
