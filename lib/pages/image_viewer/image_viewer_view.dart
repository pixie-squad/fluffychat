import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/image_viewer/video_player.dart';
import 'package:fluffychat/utils/custom_emoji_metadata.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/custom_emoji_media.dart';
import 'package:fluffychat/widgets/hover_builder.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'image_viewer.dart';

class ImageViewerView extends StatelessWidget {
  final ImageViewerController controller;

  const ImageViewerView(this.controller, {super.key});

  Uri? _stickerMxcUrl(Event event) {
    if (event.messageType != MessageTypes.Sticker) return null;
    final uri = Uri.tryParse(event.content.tryGet<String>('url') ?? '');
    return (uri?.scheme == 'mxc') ? uri : null;
  }

  CustomEmojiMeta? _stickerMeta(Event event) {
    final mxcUrl = _stickerMxcUrl(event);
    if (mxcUrl == null) return null;
    final imageJson = <String, Object?>{
      'url': mxcUrl.toString(),
      if (event.infoMap.isNotEmpty)
        'info': Map<String, Object?>.from(event.infoMap),
    };
    final rawMeta = event.content.tryGetMap<String, Object?>(
      customEmojiMetaKey,
    );
    if (rawMeta != null) {
      imageJson[customEmojiMetaKey] = Map<String, Object?>.from(rawMeta);
    }
    return CustomEmojiMeta.fromImage(ImagePackImageContent.fromJson(imageJson));
  }

  Widget _buildMedia(BuildContext context, Event event) {
    final mxcUrl = _stickerMxcUrl(event);
    final meta = _stickerMeta(event);
    final viewport = MediaQuery.sizeOf(context);
    if (mxcUrl != null &&
        meta != null &&
        meta.media.primary != CustomEmojiMediaKind.image) {
      return CustomEmojiMedia(
        client: event.room.client,
        fallbackMxc: mxcUrl,
        metadata: meta,
        fallbackEmoji: meta.primaryFallbackEmoji ?? event.body,
        width: viewport.width,
        height: viewport.height,
        fit: BoxFit.contain,
        autoplay: true,
        isThumbnail: false,
      );
    }

    return MxcImage(
      key: ValueKey(event.eventId),
      event: event,
      fit: BoxFit.contain,
      isThumbnail: false,
      animated: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final iconButtonStyle = IconButton.styleFrom(
      backgroundColor: Colors.black.withAlpha(200),
      foregroundColor: Colors.white,
    );
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Scaffold(
        backgroundColor: Colors.black.withAlpha(128),
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          elevation: 0,
          leading: IconButton(
            style: iconButtonStyle,
            icon: const Icon(Icons.close),
            onPressed: Navigator.of(context).pop,
            color: Colors.white,
            tooltip: L10n.of(context).close,
          ),
          backgroundColor: Colors.transparent,
          actions: [
            IconButton(
              style: iconButtonStyle,
              icon: const Icon(Icons.reply_outlined),
              onPressed: controller.forwardAction,
              color: Colors.white,
              tooltip: L10n.of(context).share,
            ),
            const SizedBox(width: 8),
            IconButton(
              style: iconButtonStyle,
              icon: const Icon(Icons.download_outlined),
              onPressed: () => controller.saveFileAction(context),
              color: Colors.white,
              tooltip: L10n.of(context).downloadFile,
            ),
            const SizedBox(width: 8),
            if (PlatformInfos.isMobile)
              // Use builder context to correctly position the share dialog on iPad
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: Builder(
                  builder: (context) => IconButton(
                    style: iconButtonStyle,
                    onPressed: () => controller.shareFileAction(context),
                    tooltip: L10n.of(context).share,
                    color: Colors.white,
                    icon: Icon(Icons.adaptive.share_outlined),
                  ),
                ),
              ),
          ],
        ),
        body: HoverBuilder(
          builder: (context, hovered) => Stack(
            children: [
              KeyboardListener(
                focusNode: controller.focusNode,
                onKeyEvent: controller.onKeyEvent,
                child: PageView.builder(
                  scrollDirection: Axis.vertical,
                  controller: controller.pageController,
                  itemCount: controller.allEvents.length,
                  itemBuilder: (context, i) {
                    final event = controller.allEvents[i];
                    switch (event.messageType) {
                      case MessageTypes.Video:
                        return Padding(
                          padding: const EdgeInsets.only(top: 52.0),
                          child: Center(
                            child: GestureDetector(
                              // Ignore taps to not go back here:
                              onTap: () {},
                              child: EventVideoPlayer(event),
                            ),
                          ),
                        );
                      case MessageTypes.Image:
                      case MessageTypes.Sticker:
                      default:
                        return InteractiveViewer(
                          minScale: 1.0,
                          maxScale: 10.0,
                          onInteractionEnd: controller.onInteractionEnds,
                          child: Center(
                            child: Hero(
                              tag: event.eventId,
                              child: GestureDetector(
                                // Ignore taps to not go back here:
                                onTap: () {},
                                child: _buildMedia(context, event),
                              ),
                            ),
                          ),
                        );
                    }
                  },
                ),
              ),
              if (hovered)
                Align(
                  alignment: Alignment.centerRight,
                  child: Column(
                    mainAxisSize: .min,
                    children: [
                      if (controller.canGoBack)
                        Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: IconButton(
                            style: iconButtonStyle,
                            tooltip: L10n.of(context).previous,
                            icon: const Icon(Icons.arrow_upward_outlined),
                            onPressed: controller.prevImage,
                          ),
                        ),
                      if (controller.canGoNext)
                        Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: IconButton(
                            style: iconButtonStyle,
                            tooltip: L10n.of(context).next,
                            icon: const Icon(Icons.arrow_downward_outlined),
                            onPressed: controller.nextImage,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
