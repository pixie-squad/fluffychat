import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/sticker_picker_dialog.dart';
import 'package:fluffychat/utils/custom_emoji_catalog.dart';
import 'package:fluffychat/utils/custom_emoji_metadata.dart';
import 'package:fluffychat/widgets/custom_emoji_media.dart';
import 'chat.dart';

const _recentsPackSlug = '\$_recents';
const _maxRecents = 30;

List<String> getCustomEmojiRecents() {
  final raw = AppSettings.customEmojiRecents.value;
  if (raw.isEmpty) return [];
  try {
    return (jsonDecode(raw) as List).cast<String>();
  } catch (_) {
    return [];
  }
}

void addCustomEmojiRecent(String mxcUri) {
  final recents = getCustomEmojiRecents();
  recents.remove(mxcUri);
  recents.insert(0, mxcUri);
  if (recents.length > _maxRecents) recents.length = _maxRecents;
  AppSettings.customEmojiRecents.setItem(jsonEncode(recents));
}

class ChatEmojiPicker extends StatefulWidget {
  final ChatController controller;
  const ChatEmojiPicker(this.controller, {super.key});

  @override
  State<ChatEmojiPicker> createState() => _ChatEmojiPickerState();
}

class _ChatEmojiPickerState extends State<ChatEmojiPicker> {
  String? _selectedPack;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(),
      height: widget.controller.showEmojiPicker
          ? MediaQuery.sizeOf(context).height / 2
          : 0,
      child: widget.controller.showEmojiPicker
          ? DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  TabBar(
                    tabs: [
                      Tab(text: L10n.of(context).emojis),
                      Tab(text: L10n.of(context).stickers),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _EmojiTab(
                          controller: widget.controller,
                          selectedPack: _selectedPack,
                          onSelectedPackChanged: (value) {
                            setState(() => _selectedPack = value);
                          },
                        ),
                        StickerPickerDialog(
                          room: widget.controller.room,
                          onSelected: (sticker) {
                            addCustomEmojiRecent(sticker.url.toString());
                            final stickerJson = sticker.toJson();
                            widget.controller.room.sendEvent(
                              {
                                'body': sticker.body,
                                'info': sticker.info ?? {},
                                'url': sticker.url.toString(),
                                if (stickerJson[customEmojiMetaKey] is Map)
                                  customEmojiMetaKey:
                                      stickerJson[customEmojiMetaKey],
                              },
                              type: EventTypes.Sticker,
                              threadRootEventId:
                                  widget.controller.activeThreadId,
                              threadLastEventId:
                                  widget.controller.threadLastEventId,
                            );
                            widget.controller.hideEmojiPicker();
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          : null,
    );
  }
}

class _EmojiTab extends StatelessWidget {
  final ChatController controller;
  final String? selectedPack;
  final ValueChanged<String?> onSelectedPackChanged;

  const _EmojiTab({
    required this.controller,
    required this.selectedPack,
    required this.onSelectedPackChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final catalog = CustomEmojiCatalog.fromRoom(
      controller.room,
      usage: ImagePackUsage.emoticon,
    );
    final packGroups = catalog.groupedPacks();

    final isRecents = selectedPack == _recentsPackSlug;
    final selectedGroup = isRecents
        ? null
        : packGroups
            .where((p) => p.slug == selectedPack)
            .firstOrNull;

    List<CustomEmojiCatalogEntry>? recentEntries;
    if (isRecents) {
      final recentMxcs = getCustomEmojiRecents();
      recentEntries = recentMxcs
          .map((mxc) => catalog.resolveByMxc(Uri.parse(mxc)))
          .whereType<CustomEmojiCatalogEntry>()
          .toList();
    }

    return Column(
      children: [
        if (packGroups.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            color: theme.colorScheme.surface,
            child: SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: const Text('🙂'),
                      selected: selectedPack == null,
                      onSelected: (_) => onSelectedPackChanged(null),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: const Icon(Icons.history, size: 18),
                      selected: isRecents,
                      onSelected: (_) =>
                          onSelectedPackChanged(_recentsPackSlug),
                      tooltip: 'Recent',
                    ),
                  ),
                  ...packGroups.map(
                    (pack) {
                      final firstEntry = pack.firstEntry;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          selected: selectedPack == pack.slug,
                          onSelected: (_) => onSelectedPackChanged(pack.slug),
                          label: firstEntry != null
                              ? SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CustomEmojiMedia(
                                    client: controller.room.client,
                                    fallbackMxc: firstEntry.primaryMxc,
                                    metadata: firstEntry.metadata,
                                    fallbackEmoji:
                                        firstEntry.primaryFallbackEmoji,
                                    width: 24,
                                    height: 24,
                                    isThumbnail: true,
                                  ),
                                )
                              : Text(
                                  pack.displayName.isEmpty
                                      ? '?'
                                      : pack.displayName[0],
                                ),
                          tooltip: pack.displayName,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: isRecents
              ? (recentEntries != null && recentEntries.isNotEmpty
                  ? _CustomPackGrid(
                      controller: controller,
                      entries: recentEntries,
                    )
                  : Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          L10n.of(context).emoteKeyboardNoRecents,
                          style: theme.textTheme.bodyLarge,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ))
              : selectedGroup == null
              ? EmojiPicker(
                  onEmojiSelected: controller.onEmojiSelected,
                  onBackspacePressed: controller.emojiPickerBackspace,
                  config: Config(
                    locale: Localizations.localeOf(context),
                    checkPlatformCompatibility: false,
                    emojiViewConfig: EmojiViewConfig(
                      noRecents: const NoRecent(),
                      backgroundColor: theme.colorScheme.onInverseSurface,
                    ),
                    bottomActionBarConfig: const BottomActionBarConfig(
                      enabled: false,
                    ),
                    categoryViewConfig: CategoryViewConfig(
                      backspaceColor: theme.colorScheme.primary,
                      iconColor: theme.colorScheme.primary.withAlpha(128),
                      iconColorSelected: theme.colorScheme.primary,
                      indicatorColor: theme.colorScheme.primary,
                      backgroundColor: theme.colorScheme.surface,
                    ),
                    skinToneConfig: SkinToneConfig(
                      dialogBackgroundColor: Color.lerp(
                        theme.colorScheme.surface,
                        theme.colorScheme.primaryContainer,
                        0.75,
                      )!,
                      indicatorColor: theme.colorScheme.onSurface,
                    ),
                  ),
                )
              : _CustomPackGrid(
                  controller: controller,
                  entries: selectedGroup.entries,
                ),
        ),
      ],
    );
  }
}

class _CustomPackGrid extends StatelessWidget {
  final ChatController controller;
  final List<CustomEmojiCatalogEntry> entries;

  const _CustomPackGrid({required this.controller, required this.entries});

  @override
  Widget build(BuildContext context) => GridView.builder(
    padding: const EdgeInsets.all(8),
    itemCount: entries.length,
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 64,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
    ),
    itemBuilder: (context, index) {
      final entry = entries[index];
      return Tooltip(
        message: ':${entry.shortcode}:',
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            addCustomEmojiRecent(entry.primaryMxc.toString());
            controller.typeCustomEmojiShortcode(entry.insertShortcode);
            controller.onInputBarChanged(controller.sendController.text);
          },
          child: Center(
            child: CustomEmojiMedia(
              client: controller.room.client,
              fallbackMxc: entry.primaryMxc,
              metadata: entry.metadata,
              fallbackEmoji: entry.primaryFallbackEmoji,
              width: 34,
              height: 34,
              isThumbnail: false,
            ),
          ),
        ),
      );
    },
  );
}

class NoRecent extends StatelessWidget {
  const NoRecent({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(
          L10n.of(context).emoteKeyboardNoRecents,
          style: Theme.of(context).textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
