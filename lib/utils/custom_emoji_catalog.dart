import 'package:matrix/matrix.dart';

import 'package:fluffychat/utils/client_image_packs.dart';
import 'package:fluffychat/utils/custom_emoji_metadata.dart';

final RegExp customEmojiTokenRegex = RegExp(r':(?:([\w-]+)~)?([\w-]+):');

class ParsedCustomEmojiToken {
  final String fullMatch;
  final String? pack;
  final String shortcode;
  final int start;
  final int end;

  const ParsedCustomEmojiToken({
    required this.fullMatch,
    required this.pack,
    required this.shortcode,
    required this.start,
    required this.end,
  });
}

Iterable<ParsedCustomEmojiToken> parseCustomEmojiTokens(String input) sync* {
  for (final match in customEmojiTokenRegex.allMatches(input)) {
    final shortcode = match.group(2);
    if (shortcode == null || shortcode.isEmpty) continue;
    yield ParsedCustomEmojiToken(
      fullMatch: match.group(0) ?? '',
      pack: match.group(1),
      shortcode: shortcode,
      start: match.start,
      end: match.end,
    );
  }
}

class CustomEmojiCatalogEntry {
  final String shortcode;
  final String packSlug;
  final String packDisplayName;
  final Uri? packAvatarUrl;
  final int packOrder;
  final ImagePackImageContent image;
  final CustomEmojiMeta metadata;

  CustomEmojiCatalogEntry({
    required this.shortcode,
    required this.packSlug,
    required this.packDisplayName,
    required this.packAvatarUrl,
    required this.packOrder,
    required this.image,
    required this.metadata,
    this.needsPackPrefix = false,
  });

  String get qualifiedShortcode => '$packSlug~$shortcode';

  String get insertShortcode =>
      ':${needsPackPrefix ? '$packSlug~' : ''}$shortcode:';

  bool needsPackPrefix;

  String? get primaryFallbackEmoji => metadata.primaryFallbackEmoji;

  Uri get primaryMxc => image.url;

  int get itemOrder => metadata.order;
}

class CustomEmojiCatalogMatch {
  final CustomEmojiCatalogEntry entry;
  final int score;
  final String? aliasHit;
  final String? emojiHit;

  const CustomEmojiCatalogMatch({
    required this.entry,
    required this.score,
    this.aliasHit,
    this.emojiHit,
  });
}

class CustomEmojiPackGroup {
  final String slug;
  final String displayName;
  final Uri? avatarUrl;
  final int order;
  final List<CustomEmojiCatalogEntry> entries;

  const CustomEmojiPackGroup({
    required this.slug,
    required this.displayName,
    required this.avatarUrl,
    required this.order,
    required this.entries,
  });

  String? get iconEmoji {
    if (entries.isEmpty) return null;
    for (final entry in entries) {
      final fallback = entry.primaryFallbackEmoji;
      if (fallback != null && fallback.isNotEmpty) return fallback;
    }
    return null;
  }

  CustomEmojiCatalogEntry? get firstEntry =>
      entries.isEmpty ? null : entries.first;
}

class CustomEmojiCatalog {
  final List<CustomEmojiCatalogEntry> entries;

  final Map<String, List<CustomEmojiCatalogEntry>> _entriesByShortcode;
  final Map<String, CustomEmojiCatalogEntry> _entriesByQualifiedShortcode;
  final Map<String, List<CustomEmojiCatalogEntry>> _entriesByMxc;

  CustomEmojiCatalog._(
    this.entries,
    this._entriesByShortcode,
    this._entriesByQualifiedShortcode,
    this._entriesByMxc,
  );

  factory CustomEmojiCatalog.fromRoom(Room room, {ImagePackUsage? usage}) =>
      CustomEmojiCatalog.fromImagePacks(room.getImagePacks(usage));

  factory CustomEmojiCatalog.fromClient(
    Client client, {
    ImagePackUsage? usage,
  }) => CustomEmojiCatalog.fromImagePacks(getClientImagePacks(client, usage));

  factory CustomEmojiCatalog.fromImagePacks(
    Map<String, ImagePackContent> packs,
  ) {
    final entries = <CustomEmojiCatalogEntry>[];

    for (final packEntry in packs.entries) {
      final packSlug = packEntry.key;
      final pack = packEntry.value;
      final packOrder = getCustomEmojiPackOrder(pack);
      final packDisplayName = pack.pack.displayName ?? packSlug;
      final packAvatarUrl = pack.pack.avatarUrl;

      final imageEntries = pack.images.entries.toList()
        ..sort((a, b) {
          final aMeta = CustomEmojiMeta.fromImage(a.value);
          final bMeta = CustomEmojiMeta.fromImage(b.value);
          final orderCompare = aMeta.order.compareTo(bMeta.order);
          if (orderCompare != 0) return orderCompare;
          return a.key.toLowerCase().compareTo(b.key.toLowerCase());
        });

      for (final imageEntry in imageEntries) {
        entries.add(
          CustomEmojiCatalogEntry(
            shortcode: imageEntry.key,
            packSlug: packSlug,
            packDisplayName: packDisplayName,
            packAvatarUrl: packAvatarUrl,
            packOrder: packOrder,
            image: imageEntry.value,
            metadata: CustomEmojiMeta.fromImage(imageEntry.value),
          ),
        );
      }
    }

    entries.sort((a, b) {
      final packOrderCompare = a.packOrder.compareTo(b.packOrder);
      if (packOrderCompare != 0) return packOrderCompare;

      final packNameCompare = a.packDisplayName.toLowerCase().compareTo(
        b.packDisplayName.toLowerCase(),
      );
      if (packNameCompare != 0) return packNameCompare;

      final entryOrderCompare = a.itemOrder.compareTo(b.itemOrder);
      if (entryOrderCompare != 0) return entryOrderCompare;

      return a.shortcode.toLowerCase().compareTo(b.shortcode.toLowerCase());
    });

    final byShortcode = <String, List<CustomEmojiCatalogEntry>>{};
    final byQualified = <String, CustomEmojiCatalogEntry>{};
    final byMxc = <String, List<CustomEmojiCatalogEntry>>{};

    for (final entry in entries) {
      byShortcode
          .putIfAbsent(entry.shortcode.toLowerCase(), () => [])
          .add(entry);
      byQualified['${entry.packSlug.toLowerCase()}~${entry.shortcode.toLowerCase()}'] =
          entry;
      byMxc.putIfAbsent(entry.primaryMxc.toString(), () => []).add(entry);
    }

    for (final entry in entries) {
      entry.needsPackPrefix =
          (byShortcode[entry.shortcode.toLowerCase()]?.length ?? 0) > 1;
    }

    return CustomEmojiCatalog._(entries, byShortcode, byQualified, byMxc);
  }

  CustomEmojiCatalogEntry? resolveToken({
    required String shortcode,
    String? pack,
  }) {
    if (pack != null && pack.isNotEmpty) {
      return _entriesByQualifiedShortcode['${pack.toLowerCase()}~${shortcode.toLowerCase()}'];
    }
    final matches = _entriesByShortcode[shortcode.toLowerCase()];
    if (matches == null || matches.isEmpty) return null;
    return matches.first;
  }

  CustomEmojiCatalogEntry? resolveByMxc(Uri uri) {
    final matches = _entriesByMxc[uri.toString()];
    if (matches == null || matches.isEmpty) return null;
    return matches.first;
  }

  List<CustomEmojiPackGroup> groupedPacks() {
    final grouped = <String, List<CustomEmojiCatalogEntry>>{};
    for (final entry in entries) {
      grouped.putIfAbsent(entry.packSlug, () => []).add(entry);
    }

    final groups =
        grouped.entries.map((entry) {
          final first = entry.value.first;
          final sortedEntries = List<CustomEmojiCatalogEntry>.from(entry.value)
            ..sort((a, b) {
              final orderCompare = a.itemOrder.compareTo(b.itemOrder);
              if (orderCompare != 0) return orderCompare;
              return a.shortcode.toLowerCase().compareTo(
                b.shortcode.toLowerCase(),
              );
            });
          return CustomEmojiPackGroup(
            slug: entry.key,
            displayName: first.packDisplayName,
            avatarUrl: first.packAvatarUrl,
            order: first.packOrder,
            entries: sortedEntries,
          );
        }).toList()..sort((a, b) {
          final orderCompare = a.order.compareTo(b.order);
          if (orderCompare != 0) return orderCompare;
          return a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          );
        });

    return groups;
  }

  List<CustomEmojiCatalogMatch> search(
    String query, {
    int limit = 30,
    String? pack,
    bool exactOnly = false,
  }) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return const [];

    final candidateEntries = pack == null || pack.isEmpty
        ? entries
        : entries.where((entry) => entry.packSlug == pack).toList();

    final results = <CustomEmojiCatalogMatch>[];
    for (final entry in candidateEntries) {
      final match = _matchEntry(entry, normalized, exactOnly: exactOnly);
      if (match != null) {
        results.add(match);
      }
    }

    results.sort((a, b) {
      final scoreCompare = a.score.compareTo(b.score);
      if (scoreCompare != 0) return scoreCompare;

      final canonicalCompare = a.entry.shortcode.toLowerCase().compareTo(
        b.entry.shortcode.toLowerCase(),
      );
      if (canonicalCompare != 0) return canonicalCompare;

      final packCompare = a.entry.packOrder.compareTo(b.entry.packOrder);
      if (packCompare != 0) return packCompare;

      return a.entry.packDisplayName.toLowerCase().compareTo(
        b.entry.packDisplayName.toLowerCase(),
      );
    });

    if (results.length <= limit) return results;
    return results.take(limit).toList();
  }

  CustomEmojiCatalogMatch? _matchEntry(
    CustomEmojiCatalogEntry entry,
    String normalizedQuery, {
    required bool exactOnly,
  }) {
    final canonical = entry.shortcode.toLowerCase();
    if (canonical == normalizedQuery) {
      return CustomEmojiCatalogMatch(entry: entry, score: 0);
    }

    final aliases = entry.metadata.aliases.map((alias) => alias.toLowerCase());
    final exactAlias = aliases
        .where((alias) => alias == normalizedQuery)
        .firstOrNull;
    if (exactAlias != null) {
      return CustomEmojiCatalogMatch(
        entry: entry,
        score: 2,
        aliasHit: exactAlias,
      );
    }

    final emojis = entry.metadata.emojis;
    final exactEmoji = emojis
        .where((emoji) => emoji == normalizedQuery)
        .firstOrNull;
    if (exactEmoji != null) {
      return CustomEmojiCatalogMatch(
        entry: entry,
        score: 4,
        emojiHit: exactEmoji,
      );
    }
    if (exactOnly) return null;

    if (canonical.startsWith(normalizedQuery)) {
      return CustomEmojiCatalogMatch(entry: entry, score: 1);
    }

    final prefixAlias = aliases
        .where((alias) => alias.startsWith(normalizedQuery))
        .firstOrNull;
    if (prefixAlias != null) {
      return CustomEmojiCatalogMatch(
        entry: entry,
        score: 3,
        aliasHit: prefixAlias,
      );
    }

    if (canonical.contains(normalizedQuery)) {
      return CustomEmojiCatalogMatch(entry: entry, score: 5);
    }

    final containsAlias = aliases
        .where((alias) => alias.contains(normalizedQuery))
        .firstOrNull;
    if (containsAlias != null) {
      return CustomEmojiCatalogMatch(
        entry: entry,
        score: 6,
        aliasHit: containsAlias,
      );
    }

    final containsEmoji = emojis
        .where((emoji) => emoji.contains(normalizedQuery))
        .firstOrNull;
    if (containsEmoji != null) {
      return CustomEmojiCatalogMatch(
        entry: entry,
        score: 7,
        emojiHit: containsEmoji,
      );
    }

    return null;
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
