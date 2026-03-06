import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/custom_emoji_metadata.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/url_launcher.dart';
import 'package:fluffychat/widgets/custom_emoji_media.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import '../../widgets/matrix.dart';
import 'settings_emotes.dart';

enum PopupMenuEmojiActions { import, export, shareToRoom }

class EmotesSettingsView extends StatelessWidget {
  final EmotesSettingsController controller;

  const EmotesSettingsView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    if (controller.widget.roomId != null && controller.room == null) {
      return Scaffold(
        appBar: AppBar(title: Text(L10n.of(context).oopsSomethingWentWrong)),
        body: Center(
          child: Text(L10n.of(context).youAreNoLongerParticipatingInThisChat),
        ),
      );
    }
    final theme = Theme.of(context);

    final client = Matrix.of(context).client;
    final imageKeys = controller.pack!.images.keys.toList()
      ..sort((a, b) {
        final aMeta = controller.imageMetadata(a);
        final bMeta = controller.imageMetadata(b);
        final orderCompare = aMeta.order.compareTo(bMeta.order);
        if (orderCompare != 0) return orderCompare;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
    final packKeys = controller.packKeys;
    if (packKeys != null && packKeys.isEmpty) {
      packKeys.add('');
    }
    final attributionUrl = Uri.tryParse(
      controller.packAttributionController.text,
    );

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !controller.showSave,
        title: controller.showSave
            ? TextButton(
                onPressed: controller.resetAction,
                child: Text(L10n.of(context).cancel),
              )
            : Text(L10n.of(context).customEmojisAndStickers),
        actions: [
          if (controller.showSave)
            ElevatedButton(
              onPressed: () => controller.save(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
              ),
              child: Text(L10n.of(context).saveChanges),
            )
          else
            PopupMenuButton<PopupMenuEmojiActions>(
              useRootNavigator: true,
              onSelected: (value) {
                switch (value) {
                  case PopupMenuEmojiActions.export:
                    controller.exportAsZip();
                    break;
                  case PopupMenuEmojiActions.import:
                    controller.importEmojiZip();
                    break;
                  case PopupMenuEmojiActions.shareToRoom:
                    controller.sharePackToRoomAction();
                    break;
                }
              },
              itemBuilder: (context) => [
                if (!controller.readonly)
                  PopupMenuItem(
                    value: PopupMenuEmojiActions.import,
                    child: Text(L10n.of(context).importFromZipFile),
                  ),
                if (imageKeys.isNotEmpty)
                  PopupMenuItem(
                    value: PopupMenuEmojiActions.export,
                    child: Text(L10n.of(context).exportEmotePack),
                  ),
                if (imageKeys.isNotEmpty)
                  const PopupMenuItem(
                    value: PopupMenuEmojiActions.shareToRoom,
                    child: Text('Share pack to room'),
                  ),
              ],
            ),
        ],
        bottom: packKeys == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: SizedBox(
                    height: 40,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: packKeys.length + 1,
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          final canCreatePack =
                              !controller.readonly && !controller.showSave;
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4.0,
                            ),
                            child: Tooltip(
                              message: controller.readonly
                                  ? L10n.of(context).noPermission
                                  : L10n.of(context).create,
                              child: FilterChip(
                                label: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.add_outlined, size: 18),
                                    const SizedBox(width: 4),
                                    Text(L10n.of(context).create),
                                  ],
                                ),
                                onSelected: canCreatePack
                                    ? (_) => controller.createImagePack()
                                    : null,
                              ),
                            ),
                          );
                        }
                        i--;
                        final key = packKeys[i];
                        final event = controller.room?.getState(
                          'im.ponies.room_emotes',
                          packKeys[i],
                        );

                        final eventPack = event?.content
                            .tryGetMap<String, Object?>('pack');
                        final packName =
                            eventPack?.tryGet<String>('display_name') ??
                            eventPack?.tryGet<String>('name') ??
                            (key.isNotEmpty ? key : 'Default');

                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4.0),
                          child: FilterChip(
                            label: Text(packName),
                            selected:
                                controller.stateKey == key ||
                                (controller.stateKey == null && key.isEmpty),
                            onSelected: controller.showSave
                                ? null
                                : (_) => controller.setStateKey(key),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
      ),
      body: MaxWidthBody(
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: <Widget>[
            if (controller.room != null) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: TextField(
                  maxLength: 256,
                  controller: controller.packDisplayNameController,
                  readOnly: controller.readonly,
                  onSubmitted: (_) => controller.submitDisplaynameAction(),
                  decoration: InputDecoration(
                    counter: const SizedBox.shrink(),
                    hintText: controller.stateKey,
                    labelText: L10n.of(context).stickerPackName,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: TextField(
                  maxLength: 256,
                  controller: controller.packAttributionController,
                  readOnly: controller.readonly,
                  keyboardType: TextInputType.url,
                  onSubmitted: (_) => controller.submitAttributionAction(),
                  decoration: InputDecoration(
                    counter: const SizedBox.shrink(),
                    labelText: L10n.of(context).attribution,
                    suffixIcon: attributionUrl == null
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.link_outlined),
                            onPressed: () => UrlLauncher(
                              context,
                              attributionUrl.toString(),
                            ).launchUrl(),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: TextField(
                  maxLength: 10,
                  keyboardType: TextInputType.number,
                  controller: controller.packOrderController,
                  readOnly: controller.readonly,
                  onSubmitted: (_) => controller.submitPackOrderAction(),
                  decoration: const InputDecoration(
                    counter: SizedBox.shrink(),
                    labelText: 'Pack order',
                  ),
                ),
              ),
            ],
            if (controller.readonly && controller.room != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lock_outline,
                        size: 18,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          L10n.of(context).noPermission,
                          style: TextStyle(
                            color: theme.colorScheme.onErrorContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (!controller.readonly) ...[
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: ElevatedButton.icon(
                  onPressed: controller.createStickers,
                  icon: const Icon(Icons.upload_outlined),
                  label: Text(L10n.of(context).createSticker),
                ),
              ),
              const Divider(),
            ],
            if (controller.room != null && imageKeys.isNotEmpty)
              SwitchListTile.adaptive(
                title: Text(L10n.of(context).enableEmotesGlobally),
                value: controller.isGloballyActive(client),
                onChanged: controller.setIsGloballyActive,
              ),
            imageKeys.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        L10n.of(context).noEmotesFound,
                        style: const TextStyle(fontSize: 20),
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    separatorBuilder: (BuildContext context, int i) =>
                        const SizedBox.shrink(),
                    itemCount: imageKeys.length,
                    itemBuilder: (BuildContext context, int i) {
                      final imageCode = imageKeys[i];
                      final image = controller.pack!.images[imageCode]!;
                      final metadata = controller.imageMetadata(imageCode);
                      final textEditingController = TextEditingController();
                      textEditingController.text = imageCode;
                      final aliasesController = TextEditingController(
                        text: metadata.aliases.join(', '),
                      );
                      final fallbackEmojisController = TextEditingController(
                        text: metadata.emojis.join(', '),
                      );
                      final orderController = TextEditingController(
                        text: metadata.order.toString(),
                      );
                      final useShortCuts =
                          (PlatformInfos.isWeb || PlatformInfos.isDesktop);
                      return Column(
                        children: [
                          ListTile(
                            title: Row(
                              children: [
                                Expanded(
                                  child: Shortcuts(
                                    shortcuts: !useShortCuts
                                        ? {}
                                        : {
                                            LogicalKeySet(
                                              LogicalKeyboardKey.enter,
                                            ): SubmitLineIntent(),
                                          },
                                    child: Actions(
                                      actions: !useShortCuts
                                          ? {}
                                          : {
                                              SubmitLineIntent: CallbackAction(
                                                onInvoke: (i) {
                                                  controller.submitImageAction(
                                                    imageCode,
                                                    image,
                                                    textEditingController,
                                                  );
                                                  return null;
                                                },
                                              ),
                                            },
                                      child: TextField(
                                        readOnly: controller.readonly,
                                        controller: textEditingController,
                                        autocorrect: false,
                                        minLines: 1,
                                        maxLines: 1,
                                        maxLength: 128,
                                        decoration: InputDecoration(
                                          hintText: L10n.of(
                                            context,
                                          ).emoteShortcode,
                                          prefixText: ': ',
                                          suffixText: ':',
                                          counter: const SizedBox.shrink(),
                                          filled: false,
                                          enabledBorder:
                                              const OutlineInputBorder(
                                                borderSide: BorderSide(
                                                  color: Colors.transparent,
                                                ),
                                              ),
                                        ),
                                        onSubmitted: (s) =>
                                            controller.submitImageAction(
                                              imageCode,
                                              image,
                                              textEditingController,
                                            ),
                                      ),
                                    ),
                                  ),
                                ),
                                if (!controller.readonly)
                                  PopupMenuButton<ImagePackUsage>(
                                    onSelected: (usage) => controller
                                        .toggleUsage(imageCode, usage),
                                    itemBuilder: (context) => [
                                      PopupMenuItem(
                                        value: ImagePackUsage.sticker,
                                        child: Row(
                                          mainAxisSize: .min,
                                          children: [
                                            if (image.usage?.contains(
                                                  ImagePackUsage.sticker,
                                                ) ??
                                                true)
                                              const Icon(Icons.check_outlined),
                                            const SizedBox(width: 12),
                                            Text(L10n.of(context).useAsSticker),
                                          ],
                                        ),
                                      ),
                                      PopupMenuItem(
                                        value: ImagePackUsage.emoticon,
                                        child: Row(
                                          mainAxisSize: .min,
                                          children: [
                                            if (image.usage?.contains(
                                                  ImagePackUsage.emoticon,
                                                ) ??
                                                true)
                                              const Icon(Icons.check_outlined),
                                            const SizedBox(width: 12),
                                            Text(L10n.of(context).useAsEmoji),
                                          ],
                                        ),
                                      ),
                                    ],
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                              ],
                            ),
                            leading: _EmoteImage(image),
                            trailing: controller.readonly
                                ? null
                                : IconButton(
                                    tooltip: L10n.of(context).delete,
                                    onPressed: () =>
                                        controller.removeImageAction(imageCode),
                                    icon: const Icon(Icons.delete_outlined),
                                  ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(
                              left: 72,
                              right: 16,
                              bottom: 8,
                            ),
                            child: Column(
                              children: [
                                TextField(
                                  readOnly: controller.readonly,
                                  controller: aliasesController,
                                  decoration: const InputDecoration(
                                    labelText: 'Aliases (comma separated)',
                                  ),
                                  onSubmitted: (value) => controller
                                      .submitAliasesAction(imageCode, value),
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  readOnly: controller.readonly,
                                  controller: fallbackEmojisController,
                                  decoration: const InputDecoration(
                                    labelText:
                                        'Fallback emojis (comma separated)',
                                  ),
                                  onSubmitted: (value) =>
                                      controller.submitFallbackEmojisAction(
                                        imageCode,
                                        value,
                                      ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        readOnly: controller.readonly,
                                        controller: orderController,
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                          labelText: 'Item order',
                                        ),
                                        onSubmitted: (value) =>
                                            controller.submitItemOrderAction(
                                              imageCode,
                                              value,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if (!controller.readonly)
                                      OutlinedButton.icon(
                                        onPressed: () => controller
                                            .editMediaSourcesAction(imageCode),
                                        icon: const Icon(Icons.tune_outlined),
                                        label: const Text('Media'),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                        ],
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }
}

class _EmoteImage extends StatelessWidget {
  final ImagePackImageContent image;

  const _EmoteImage(this.image);

  @override
  Widget build(BuildContext context) {
    const size = 44.0;
    final key = 'sticker_preview_${image.url}';
    final metadata = CustomEmojiMeta.fromImage(image);
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () => showDialog(
        context: context,
        builder: (_) => Dialog(
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CustomEmojiMedia(
                  key: ValueKey(key),
                  client: Matrix.of(context).client,
                  fallbackMxc: image.url,
                  metadata: metadata,
                  fallbackEmoji: metadata.primaryFallbackEmoji,
                  fit: BoxFit.contain,
                  width: 220,
                  height: 220,
                  isThumbnail: false,
                ),
                if (image.body?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Text(image.body!.trim()),
                ],
              ],
            ),
          ),
        ),
      ),
      child: CustomEmojiMedia(
        key: ValueKey(key),
        client: Matrix.of(context).client,
        fallbackMxc: image.url,
        metadata: metadata,
        fallbackEmoji: metadata.primaryFallbackEmoji,
        fit: BoxFit.contain,
        width: size,
        height: size,
        isThumbnail: false,
      ),
    );
  }
}

class SubmitLineIntent extends Intent {}
