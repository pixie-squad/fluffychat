import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/mxc_image.dart';

class PackShareMessage extends StatefulWidget {
  final Event event;

  const PackShareMessage(this.event, {super.key});

  @override
  State<PackShareMessage> createState() => _PackShareMessageState();
}

class _PackShareMessageState extends State<PackShareMessage> {
  bool _imported = false;

  bool _isPackGloballyActive(Client client) {
    final roomId = widget.event.roomId;
    final stateKey = widget.event.stateKey ?? '';
    if (roomId == null) return false;
    return client.accountData['im.ponies.emote_rooms']?.content
            .tryGetMap<String, Object?>('rooms')
            ?.tryGetMap<String, Object?>(roomId)
            ?.tryGetMap<String, Object?>(stateKey) !=
        null;
  }

  Future<void> _importPack() async {
    final client = Matrix.of(context).client;
    final roomId = widget.event.roomId;
    final stateKey = widget.event.stateKey ?? '';
    if (roomId == null) return;

    final content =
        client.accountData['im.ponies.emote_rooms']?.content ??
        <String, dynamic>{};

    if (content['rooms'] is! Map) {
      content['rooms'] = <String, dynamic>{};
    }
    if (content['rooms'][roomId] is! Map) {
      content['rooms'][roomId] = <String, dynamic>{};
    }
    if (content['rooms'][roomId][stateKey] is! Map) {
      content['rooms'][roomId][stateKey] = <String, dynamic>{};
    }

    final result = await showFutureLoadingDialog(
      context: context,
      future: () => client.setAccountData(
        client.userID!,
        'im.ponies.emote_rooms',
        content,
      ),
    );

    if (result.isError) return;
    if (mounted) {
      setState(() {
        _imported = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final client = Matrix.of(context).client;

    ImagePackContent pack;
    try {
      pack = widget.event.parsedImagePackContent;
    } catch (_) {
      return const SizedBox.shrink();
    }

    final packName =
        pack.pack.displayName ?? widget.event.stateKey ?? 'Sticker Pack';
    final sender =
        widget.event.senderFromMemoryOrFallback.calcDisplayname();
    final previewImages = pack.images.values.take(5).toList();
    final isImported = _imported || _isPackGloballyActive(client);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 360),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withAlpha(128),
              borderRadius:
                  BorderRadius.circular(AppConfig.borderRadius / 3),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  L10n.of(context)
                      .userSharedStickerPack(sender, packName),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11 * AppSettings.fontSizeFactor.value,
                  ),
                ),
                if (previewImages.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: previewImages
                        .map(
                          (image) => Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 2),
                            child: MxcImage(
                              uri: image.url,
                              width: 32,
                              height: 32,
                              isThumbnail: true,
                              client: client,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  if (pack.images.length > 5) ...[
                    const SizedBox(height: 4),
                    Text(
                      '+${pack.images.length - 5} more',
                      style: TextStyle(
                        fontSize: 10 * AppSettings.fontSizeFactor.value,
                        color:
                            theme.colorScheme.onSurface.withAlpha(150),
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 8),
                if (isImported)
                  Text(
                    L10n.of(context).alreadyImported,
                    style: TextStyle(
                      fontSize: 11 * AppSettings.fontSizeFactor.value,
                      color: theme.colorScheme.primary,
                    ),
                  )
                else
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: Text(L10n.of(context).importStickerPack),
                    onPressed: _importPack,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
