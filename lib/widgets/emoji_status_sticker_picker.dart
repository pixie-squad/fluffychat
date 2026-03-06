import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/client_image_packs.dart';
import 'package:fluffychat/utils/custom_emoji_metadata.dart';
import 'package:fluffychat/utils/url_launcher.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/custom_emoji_media.dart';

class EmojiStatusStickerPicker extends StatefulWidget {
  final Client client;
  final void Function(ImagePackImageContent) onSelected;

  const EmojiStatusStickerPicker({
    required this.client,
    required this.onSelected,
    super.key,
  });

  @override
  State<EmojiStatusStickerPicker> createState() =>
      _EmojiStatusStickerPickerState();
}

class _EmojiStatusStickerPickerState extends State<EmojiStatusStickerPicker> {
  String? searchFilter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final stickerPacks = getClientImagePacks(widget.client);
    final packSlugs = stickerPacks.keys.toList()
      ..sort((a, b) {
        final orderA = getCustomEmojiPackOrder(stickerPacks[a]!);
        final orderB = getCustomEmojiPackOrder(stickerPacks[b]!);
        final orderCompare = orderA.compareTo(orderB);
        if (orderCompare != 0) return orderCompare;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });

    // ignore: prefer_function_declarations_over_variables
    final packBuilder = (BuildContext context, int packIndex) {
      final pack = stickerPacks[packSlugs[packIndex]]!;
      final filteredEntries = pack.images.entries.toList()
        ..sort((a, b) {
          final orderCompare = CustomEmojiMeta.fromImage(
            a.value,
          ).order.compareTo(CustomEmojiMeta.fromImage(b.value).order);
          if (orderCompare != 0) return orderCompare;
          return a.key.toLowerCase().compareTo(b.key.toLowerCase());
        });
      if (searchFilter?.isNotEmpty ?? false) {
        filteredEntries.removeWhere(
          (e) =>
              !(e.key.toLowerCase().contains(searchFilter!.toLowerCase()) ||
                  (e.value.body?.toLowerCase().contains(
                        searchFilter!.toLowerCase(),
                      ) ??
                      false)),
        );
      }
      final imageKeys = filteredEntries.map((e) => e.key).toList();
      if (imageKeys.isEmpty) {
        return const SizedBox.shrink();
      }
      final packName = pack.pack.displayName ?? packSlugs[packIndex];
      return Column(
        children: <Widget>[
          if (packIndex != 0) const SizedBox(height: 20),
          if (packName != 'user')
            ListTile(
              leading: Avatar(
                mxContent: pack.pack.avatarUrl,
                name: packName,
                client: widget.client,
              ),
              title: Text(packName),
            ),
          const SizedBox(height: 6),
          GridView.builder(
            itemCount: imageKeys.length,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 84,
              mainAxisSpacing: 8.0,
              crossAxisSpacing: 8.0,
            ),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemBuilder: (BuildContext context, int imageIndex) {
              final image = pack.images[imageKeys[imageIndex]]!;
              final metadata = CustomEmojiMeta.fromImage(image);
              return Tooltip(
                message: image.body ?? imageKeys[imageIndex],
                child: InkWell(
                  radius: AppConfig.borderRadius,
                  key: ValueKey(image.url.toString()),
                  onTap: () {
                    final imageCopy = ImagePackImageContent.fromJson(
                      image.toJson().copy(),
                    );
                    imageCopy.body ??= imageKeys[imageIndex];
                    widget.onSelected(imageCopy);
                  },
                  child: AbsorbPointer(
                    absorbing: true,
                    child: CustomEmojiMedia(
                      client: widget.client,
                      fallbackMxc: image.url,
                      metadata: metadata,
                      fallbackEmoji: metadata.primaryFallbackEmoji,
                      fit: BoxFit.contain,
                      width: 128,
                      height: 128,
                      isThumbnail: false,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      );
    };

    return Scaffold(
      backgroundColor: theme.colorScheme.onInverseSurface,
      body: SizedBox(
        width: double.maxFinite,
        child: CustomScrollView(
          slivers: <Widget>[
            SliverAppBar(
              floating: true,
              pinned: true,
              scrolledUnderElevation: 0,
              automaticallyImplyLeading: false,
              backgroundColor: Colors.transparent,
              title: SizedBox(
                height: 42,
                child: TextField(
                  autofocus: false,
                  decoration: InputDecoration(
                    filled: true,
                    hintText: L10n.of(context).search,
                    prefixIcon: const Icon(Icons.search_outlined),
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: (s) => setState(() => searchFilter = s),
                ),
              ),
            ),
            if (packSlugs.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(L10n.of(context).noEmotesFound),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => UrlLauncher(
                          context,
                          AppConfig.howDoIGetStickersTutorial,
                        ).launchUrl(),
                        icon: const Icon(Icons.explore_outlined),
                        label: Text(L10n.of(context).discover),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  packBuilder,
                  childCount: packSlugs.length,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
