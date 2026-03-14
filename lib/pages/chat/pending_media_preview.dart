import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'chat.dart';

class PendingMediaPreview extends StatelessWidget {
  final ChatController controller;

  const PendingMediaPreview(this.controller, {super.key});

  static const double _thumbnailSize = 80.0;
  static const double _containerHeight = 96.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final files = controller.pendingMediaFiles;

    return AnimatedContainer(
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
      height: files.isEmpty ? 0 : _containerHeight,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: theme.colorScheme.onInverseSurface,
      ),
      child: files.isEmpty
          ? const SizedBox.shrink()
          : Row(
              children: [
                const SizedBox(width: 4),
                _AddMoreButton(controller: controller),
                Expanded(
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    itemCount: files.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) => _MediaThumbnail(
                      file: files[index],
                      onRemove: () => controller.removePendingMedia(index),
                    ),
                  ),
                ),
                _ToggleButtons(controller: controller),
                const SizedBox(width: 4),
              ],
            ),
    );
  }
}

class _AddMoreButton extends StatelessWidget {
  final ChatController controller;

  const _AddMoreButton({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: SizedBox(
        width: PendingMediaPreview._thumbnailSize,
        height: PendingMediaPreview._thumbnailSize,
        child: Material(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.hardEdge,
          child: InkWell(
            onTap: () => controller.sendFileAction(type: FileType.image),
            borderRadius: BorderRadius.circular(12),
            child: const Center(
              child: Icon(Icons.add_photo_alternate_outlined, size: 28),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToggleButtons extends StatefulWidget {
  final ChatController controller;

  const _ToggleButtons({required this.controller});

  @override
  State<_ToggleButtons> createState() => _ToggleButtonsState();
}

class _ToggleButtonsState extends State<_ToggleButtons> {
  late bool _compress;
  late bool _groupAlbum;

  @override
  void initState() {
    super.initState();
    _compress = AppSettings.compressMedia.value;
    _groupAlbum = AppSettings.groupAsAlbum.value;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final showGroupToggle = widget.controller.pendingMediaFiles.length > 1;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ToggleIcon(
            icon: _compress ? Icons.compress : Icons.high_quality_outlined,
            active: _compress,
            tooltip: _compress ? l10n.compress : l10n.sendOriginal,
            onPressed: () {
              setState(() => _compress = !_compress);
              AppSettings.compressMedia.setItem(_compress);
            },
            theme: theme,
          ),
          if (showGroupToggle)
            _ToggleIcon(
              icon: _groupAlbum
                  ? Icons.photo_library
                  : Icons.photo_library_outlined,
              active: _groupAlbum,
              tooltip: l10n.groupAsAlbum,
              onPressed: () {
                setState(() => _groupAlbum = !_groupAlbum);
                AppSettings.groupAsAlbum.setItem(_groupAlbum);
              },
              theme: theme,
            ),
        ],
      ),
    );
  }
}

class _ToggleIcon extends StatelessWidget {
  final IconData icon;
  final bool active;
  final String tooltip;
  final VoidCallback onPressed;
  final ThemeData theme;

  const _ToggleIcon({
    required this.icon,
    required this.active,
    required this.tooltip,
    required this.onPressed,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: IconButton(
        iconSize: 18,
        padding: EdgeInsets.zero,
        tooltip: tooltip,
        icon: Icon(
          icon,
          color: active
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
        ),
        onPressed: onPressed,
      ),
    );
  }
}

class _MediaThumbnail extends StatelessWidget {
  final XFile file;
  final VoidCallback onRemove;

  const _MediaThumbnail({
    required this.file,
    required this.onRemove,
  });

  bool get _isVideo {
    final mimeType = file.mimeType ?? lookupMimeType(file.name);
    return mimeType != null && mimeType.startsWith('video');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: PendingMediaPreview._thumbnailSize,
      height: PendingMediaPreview._thumbnailSize,
      child: Stack(
        children: [
          Positioned.fill(
            child: Material(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.hardEdge,
              child: _isVideo
                  ? Center(
                      child: Icon(
                        Icons.videocam_outlined,
                        size: 32,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  : FutureBuilder<Uint8List>(
                      future: file.readAsBytes(),
                      builder: (context, snapshot) {
                        if (snapshot.data == null) {
                          return const Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child:
                                  CircularProgressIndicator.adaptive(strokeWidth: 2),
                            ),
                          );
                        }
                        return Image.memory(
                          snapshot.data!,
                          width: PendingMediaPreview._thumbnailSize,
                          height: PendingMediaPreview._thumbnailSize,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Center(
                            child: Icon(
                              Icons.broken_image_outlined,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
          if (_isVideo)
            Positioned(
              bottom: 4,
              left: 4,
              child: Icon(
                Icons.play_circle_filled,
                color: Colors.white.withAlpha(200),
                size: 20,
              ),
            ),
          Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(2),
                child: const Icon(Icons.close, color: Colors.white, size: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
