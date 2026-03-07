import 'package:matrix/matrix.dart';

const String customEmojiMetaKey = 'im.fluffychat.meta';
const String customEmojiPackOrderKey = 'im.fluffychat.order';
const String customEmojiSourceBodyKey = 'im.fluffychat.source_body';
const String customEmojiEmbeddedKey = 'im.fluffychat.emojis';

enum CustomEmojiMediaKind { image, webm, mp4, lottieJson, lottieTgs }

CustomEmojiMediaKind? customEmojiMediaKindFromString(String? value) =>
    switch (value) {
      'image' => CustomEmojiMediaKind.image,
      'webm' => CustomEmojiMediaKind.webm,
      'mp4' => CustomEmojiMediaKind.mp4,
      'lottie_json' => CustomEmojiMediaKind.lottieJson,
      'lottie_tgs' => CustomEmojiMediaKind.lottieTgs,
      _ => null,
    };

String customEmojiMediaKindToString(CustomEmojiMediaKind value) =>
    switch (value) {
      CustomEmojiMediaKind.image => 'image',
      CustomEmojiMediaKind.webm => 'webm',
      CustomEmojiMediaKind.mp4 => 'mp4',
      CustomEmojiMediaKind.lottieJson => 'lottie_json',
      CustomEmojiMediaKind.lottieTgs => 'lottie_tgs',
    };

CustomEmojiMediaKind inferCustomEmojiMediaKind({String? mimetype, Uri? uri}) {
  final mime = (mimetype ?? '').toLowerCase();
  if (mime.contains('video/webm')) return CustomEmojiMediaKind.webm;
  if (mime.contains('video/mp4')) return CustomEmojiMediaKind.mp4;
  if (mime.contains('application/gzip') ||
      mime.contains('application/x-tgsticker')) {
    return CustomEmojiMediaKind.lottieTgs;
  }
  if (mime.contains('application/json') || mime.contains('lottie')) {
    return CustomEmojiMediaKind.lottieJson;
  }

  final path = (uri?.path.toLowerCase() ?? '');
  if (path.endsWith('.webm')) return CustomEmojiMediaKind.webm;
  if (path.endsWith('.mp4')) return CustomEmojiMediaKind.mp4;
  if (path.endsWith('.tgs')) return CustomEmojiMediaKind.lottieTgs;
  if (path.endsWith('.json')) return CustomEmojiMediaKind.lottieJson;

  return CustomEmojiMediaKind.image;
}

class CustomEmojiMediaSource {
  final CustomEmojiMediaKind kind;
  final Uri url;
  final String? mimetype;

  const CustomEmojiMediaSource({
    required this.kind,
    required this.url,
    this.mimetype,
  });

  factory CustomEmojiMediaSource.fromJson(Map<String, Object?> json) {
    final urlStr = json.tryGet<String>('url') ?? '';
    final url = Uri.tryParse(urlStr);
    if (url == null || !url.isAbsolute) {
      throw const FormatException('Invalid media source URL');
    }
    return CustomEmojiMediaSource(
      kind:
          customEmojiMediaKindFromString(json.tryGet<String>('kind')) ??
          inferCustomEmojiMediaKind(
            mimetype: json.tryGet<String>('mimetype'),
            uri: url,
          ),
      url: url,
      mimetype: json.tryGet<String>('mimetype'),
    );
  }

  Map<String, Object?> toJson() => {
    'kind': customEmojiMediaKindToString(kind),
    'url': url.toString(),
    if (mimetype != null && mimetype!.isNotEmpty) 'mimetype': mimetype,
  };
}

class CustomEmojiMediaDescriptor {
  final bool loop;
  final CustomEmojiMediaKind primary;
  final List<CustomEmojiMediaSource> sources;

  const CustomEmojiMediaDescriptor({
    required this.loop,
    required this.primary,
    required this.sources,
  });

  Map<String, Object?> toJson() => {
    'loop': loop,
    'primary': customEmojiMediaKindToString(primary),
    'sources': sources.map((source) => source.toJson()).toList(),
  };

  List<CustomEmojiMediaSource> prioritizedSources() {
    final primarySources = <CustomEmojiMediaSource>[];
    final secondarySources = <CustomEmojiMediaSource>[];
    for (final source in sources) {
      if (source.kind == primary) {
        primarySources.add(source);
      } else {
        secondarySources.add(source);
      }
    }
    return [...primarySources, ...secondarySources];
  }
}

class CustomEmojiMeta {
  final List<String> aliases;
  final List<String> emojis;
  final int order;
  final CustomEmojiMediaDescriptor media;

  const CustomEmojiMeta({
    required this.aliases,
    required this.emojis,
    required this.order,
    required this.media,
  });

  factory CustomEmojiMeta.legacy(ImagePackImageContent image) {
    final mimetype = image.info?.tryGet<String>('mimetype');
    final defaultKind = inferCustomEmojiMediaKind(
      mimetype: mimetype,
      uri: image.url,
    );
    return CustomEmojiMeta(
      aliases: const [],
      emojis: const [],
      order: 0,
      media: CustomEmojiMediaDescriptor(
        loop: true,
        primary: defaultKind,
        sources: [
          CustomEmojiMediaSource(
            kind: defaultKind,
            url: image.url,
            mimetype: mimetype,
          ),
        ],
      ),
    );
  }

  factory CustomEmojiMeta.fromImage(ImagePackImageContent image) {
    final json = image.toJson();
    final metaJson = json.tryGetMap<String, Object?>(customEmojiMetaKey);
    if (metaJson == null) {
      return CustomEmojiMeta.legacy(image);
    }

    final aliases = _normalizeAliasList(metaJson.tryGetList<String>('aliases'));
    final emojis = _normalizeEmojiList(metaJson.tryGetList<String>('emojis'));

    final orderRaw = metaJson['order'];
    final order = switch (orderRaw) {
      int value => value,
      String value => int.tryParse(value) ?? 0,
      _ => 0,
    };

    final mediaJson = metaJson.tryGetMap<String, Object?>('media');
    final mimetype = image.info?.tryGet<String>('mimetype');
    final fallbackKind = inferCustomEmojiMediaKind(
      mimetype: mimetype,
      uri: image.url,
    );

    final loop = mediaJson?.tryGet<bool>('loop') ?? true;
    final primary =
        customEmojiMediaKindFromString(mediaJson?.tryGet<String>('primary')) ??
        fallbackKind;

    final parsedSources = <CustomEmojiMediaSource>[];
    for (final raw in mediaJson?.tryGetList<Object?>('sources') ?? const []) {
      if (raw is! Map) continue;
      try {
        parsedSources.add(
          CustomEmojiMediaSource.fromJson(Map<String, Object?>.from(raw)),
        );
      } catch (_) {
        // ignore malformed source entry and keep remaining entries
      }
    }

    if (parsedSources.isEmpty) {
      parsedSources.add(
        CustomEmojiMediaSource(
          kind: fallbackKind,
          url: image.url,
          mimetype: mimetype,
        ),
      );
    }

    final dedupedSources = <CustomEmojiMediaSource>[];
    final seen = <String>{};
    for (final source in parsedSources) {
      final dedupeKey =
          '${customEmojiMediaKindToString(source.kind)}|${source.url}|${source.mimetype ?? ''}';
      if (seen.add(dedupeKey)) {
        dedupedSources.add(source);
      }
    }

    final hasPrimary = dedupedSources.any((source) => source.kind == primary);
    final resolvedPrimary = hasPrimary ? primary : dedupedSources.first.kind;

    return CustomEmojiMeta(
      aliases: aliases,
      emojis: emojis,
      order: order,
      media: CustomEmojiMediaDescriptor(
        loop: loop,
        primary: resolvedPrimary,
        sources: dedupedSources,
      ),
    );
  }

  String? get primaryFallbackEmoji => emojis.isEmpty ? null : emojis.first;

  Map<String, Object?> toJson() => {
    'aliases': aliases,
    'emojis': emojis,
    'order': order,
    'media': media.toJson(),
  };
}

ImagePackImageContent applyCustomEmojiMeta(
  ImagePackImageContent image,
  CustomEmojiMeta meta,
) {
  final json = Map<String, Object?>.from(image.toJson());
  json[customEmojiMetaKey] = meta.toJson();
  return ImagePackImageContent.fromJson(json);
}

int getCustomEmojiPackOrder(ImagePackContent pack) {
  final value = pack.toJson()[customEmojiPackOrderKey];
  return switch (value) {
    int number => number,
    String stringValue => int.tryParse(stringValue) ?? 0,
    _ => 0,
  };
}

ImagePackContent applyCustomEmojiPackOrder(ImagePackContent pack, int order) {
  final json = Map<String, Object?>.from(pack.toJson());
  json[customEmojiPackOrderKey] = order;
  return ImagePackContent.fromJson(json);
}

List<String> _normalizeAliasList(List<String>? input) => _normalizeList(input)
    .map((alias) {
      var normalized = alias.trim();
      if (normalized.startsWith(':')) normalized = normalized.substring(1);
      if (normalized.endsWith(':')) {
        normalized = normalized.substring(0, normalized.length - 1);
      }
      return normalized;
    })
    .where((alias) => alias.isNotEmpty)
    .toList();

List<String> _normalizeEmojiList(List<String>? input) =>
    _normalizeList(input).where((emoji) => emoji.isNotEmpty).toList();

List<String> _normalizeList(List<String>? input) {
  final deduped = <String>[];
  final seen = <String>{};
  for (final value in input ?? const <String>[]) {
    final trimmed = value.trim();
    final key = trimmed.toLowerCase();
    if (trimmed.isEmpty || !seen.add(key)) continue;
    deduped.add(trimmed);
  }
  return deduped;
}
