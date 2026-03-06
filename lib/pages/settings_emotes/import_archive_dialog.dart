import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:archive/archive.dart';
import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';
import 'package:mime/mime.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/settings_emotes/settings_emotes.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';

class ImportEmoteArchiveDialog extends StatefulWidget {
  final EmotesSettingsController controller;
  final Archive archive;

  const ImportEmoteArchiveDialog({
    super.key,
    required this.controller,
    required this.archive,
  });

  @override
  State<ImportEmoteArchiveDialog> createState() =>
      _ImportEmoteArchiveDialogState();
}

class _ImportEmoteArchiveDialogState extends State<ImportEmoteArchiveDialog> {
  Map<ArchiveFile, String> _importMap = {};

  bool _loading = false;

  double _progress = 0;

  @override
  void initState() {
    _importFileMap();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(L10n.of(context).importEmojis),
      content: _loading
          ? Center(child: CircularProgressIndicator(value: _progress))
          : SingleChildScrollView(
              child: Wrap(
                alignment: WrapAlignment.spaceEvenly,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 8,
                spacing: 8,
                children: _importMap.entries
                    .map(
                      (e) => _EmojiImportPreview(
                        key: ValueKey(e.key.name),
                        entry: e,
                        onNameChanged: (name) => _importMap[e.key] = name,
                        onRemove: () =>
                            setState(() => _importMap.remove(e.key)),
                      ),
                    )
                    .toList(),
              ),
            ),
      actions: [
        TextButton(
          onPressed: _loading ? null : Navigator.of(context).pop,
          child: Text(L10n.of(context).cancel),
        ),
        TextButton(
          onPressed: _loading
              ? null
              : _importMap.isNotEmpty
              ? _addEmotePack
              : null,
          child: Text(L10n.of(context).importNow),
        ),
      ],
    );
  }

  void _importFileMap() {
    _importMap = Map.fromEntries(
      widget.archive.files
          .where(
            (e) => e.isFile && !e.name.toLowerCase().endsWith('.gif'),
          )
          .map((e) => MapEntry(e, e.name.emoteNameFromPath))
          .sorted((a, b) => a.value.compareTo(b.value)),
    );
  }

  Future<void> _addEmotePack() async {
    setState(() {
      _loading = true;
      _progress = 0;
    });
    final imports = _importMap;
    final successfulUploads = <String>{};

    // check for duplicates first

    final skipKeys = [];

    for (final entry in imports.entries) {
      final imageCode = entry.value;

      if (widget.controller.pack!.images.containsKey(imageCode)) {
        final completer = Completer<OkCancelResult>();
        WidgetsBinding.instance.addPostFrameCallback((timeStamp) async {
          final result = await showOkCancelAlertDialog(
            useRootNavigator: false,
            context: context,
            title: L10n.of(context).emoteExists,
            message: imageCode,
            cancelLabel: L10n.of(context).replace,
            okLabel: L10n.of(context).skip,
          );
          completer.complete(result);
        });

        final result = await completer.future;
        if (result == OkCancelResult.ok) {
          skipKeys.add(entry.key);
        }
      }
    }

    for (final key in skipKeys) {
      imports.remove(key);
    }

    for (final entry in imports.entries) {
      setState(() {
        _progress += 1 / imports.length;
      });
      final file = entry.key;
      final imageCode = entry.value;

      try {
        final uploaded = await widget.controller.uploadPackAssetBytes(
          bytes: Uint8List.fromList(List<int>.from(file.content as List)),
          filename: file.name,
          mimeType: lookupMimeType(file.name),
        );
        widget.controller.pack!.images[imageCode] = uploaded;
        successfulUploads.add(file.name);
      } catch (e) {
        Logs().d('Could not upload emote $imageCode');
      }
    }

    await widget.controller.save(context);
    _importMap.removeWhere(
      (key, value) => successfulUploads.contains(key.name),
    );

    _loading = false;
    _progress = 0;

    // in case we have unhandled / duplicated emotes left, don't pop
    if (mounted) setState(() {});
    if (_importMap.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => Navigator.of(context).pop(),
      );
    }
  }
}

class _EmojiImportPreview extends StatefulWidget {
  final MapEntry<ArchiveFile, String> entry;
  final ValueChanged<String> onNameChanged;
  final VoidCallback onRemove;

  const _EmojiImportPreview({
    super.key,
    required this.entry,
    required this.onNameChanged,
    required this.onRemove,
  });

  @override
  State<_EmojiImportPreview> createState() => _EmojiImportPreviewState();
}

class _EmojiImportPreviewState extends State<_EmojiImportPreview> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = TextEditingController(text: widget.entry.value);
    final bytes = Uint8List.fromList(
      List<int>.from(widget.entry.key.content as List),
    );
    final mimeType = lookupMimeType(widget.entry.key.name);
    final isImage = mimeType?.startsWith('image/') ?? false;

    return Stack(
      alignment: Alignment.topRight,
      children: [
        IconButton(
          onPressed: widget.onRemove,
          icon: const Icon(Icons.remove_circle),
          tooltip: L10n.of(context).remove,
        ),
        Column(
          mainAxisSize: .min,
          mainAxisAlignment: .center,
          crossAxisAlignment: .center,
          children: [
            isImage
                ? Image.memory(
                    bytes,
                    height: 64,
                    width: 64,
                    errorBuilder: (context, e, s) =>
                        _ArchiveFilePreview(name: widget.entry.key.name),
                  )
                : _ArchiveFilePreview(
                    name: widget.entry.key.name,
                    mimeType: mimeType,
                  ),
            SizedBox(
              width: 128,
              child: TextField(
                controller: controller,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^[-\w]+$')),
                ],
                autocorrect: false,
                minLines: 1,
                maxLines: 1,
                decoration: InputDecoration(
                  hintText: L10n.of(context).emoteShortcode,
                  prefixText: ': ',
                  suffixText: ':',
                  border: const OutlineInputBorder(),
                  prefixStyle: TextStyle(
                    color: theme.colorScheme.secondary,
                    fontWeight: FontWeight.bold,
                  ),
                  suffixStyle: TextStyle(
                    color: theme.colorScheme.secondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onChanged: widget.onNameChanged,
                onSubmitted: widget.onNameChanged,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ArchiveFilePreview extends StatelessWidget {
  final String name;
  final String? mimeType;

  const _ArchiveFilePreview({required this.name, this.mimeType});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final normalizedMime = (mimeType ?? lookupMimeType(name) ?? '')
        .toLowerCase();
    final icon = switch (normalizedMime) {
      String mime when mime.startsWith('video/') => Icons.videocam_outlined,
      String mime when mime.contains('json') || mime.contains('lottie') =>
        Icons.animation_outlined,
      String mime when mime.contains('gzip') => Icons.archive_outlined,
      _ => Icons.insert_drive_file_outlined,
    };

    return SizedBox.square(
      dimension: 64,
      child: Tooltip(
        message: name,
        child: Column(
          mainAxisAlignment: .start,
          mainAxisSize: .min,
          crossAxisAlignment: .center,
          children: [
            Icon(icon),
            Text(
              name.split('.').last.toUpperCase(),
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

extension on String {
  /// normalizes a file path into its name only replacing any special character
  /// [^-\w] with an underscore and removing the extension
  ///
  /// Used to compute emote name proposal based on file name
  String get emoteNameFromPath {
    // ... removing leading path
    return split(RegExp(r'[/\\]')).last
        // ... removing file extension
        .split('.')
        .first
        // ... lowering
        .toLowerCase()
        // ... replacing unexpected characters
        .replaceAll(RegExp(r'[^-\w]'), '_');
  }
}
