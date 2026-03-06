import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' hide Client;
import 'package:matrix/matrix.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:slugify/slugify.dart';
import 'package:video_compress/video_compress.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/client_manager.dart';
import 'package:fluffychat/utils/custom_emoji_metadata.dart';
import 'package:fluffychat/utils/file_selector.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_file_extension.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import '../../widgets/matrix.dart';
import 'import_archive_dialog.dart';
import 'settings_emotes_view.dart';

import 'package:archive/archive.dart'
    if (dart.library.io) 'package:archive/archive_io.dart';

class EmotesSettings extends StatefulWidget {
  final String? roomId;
  const EmotesSettings({required this.roomId, super.key});

  @override
  EmotesSettingsController createState() => EmotesSettingsController();
}

class EmotesSettingsController extends State<EmotesSettings> {
  late final Room? room;

  String? stateKey;

  List<String>? get packKeys {
    final room = this.room;
    if (room == null) return null;
    final keys = room.states['im.ponies.room_emotes']?.keys.toList() ?? [];
    keys.sort((a, b) {
      final eventA = room.getState('im.ponies.room_emotes', a);
      final eventB = room.getState('im.ponies.room_emotes', b);
      final orderA = eventA == null
          ? 0
          : getCustomEmojiPackOrder(eventA.parsedImagePackContent);
      final orderB = eventB == null
          ? 0
          : getCustomEmojiPackOrder(eventB.parsedImagePackContent);
      final orderCompare = orderA.compareTo(orderB);
      if (orderCompare != 0) return orderCompare;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });
    return keys;
  }

  @override
  void initState() {
    super.initState();
    room = widget.roomId != null
        ? Matrix.of(context).client.getRoomById(widget.roomId!)
        : null;
    setStateKey(packKeys?.firstOrNull, reset: false);
    if (room == null) {
      packOrderController.text = getCustomEmojiPackOrder(_getPack()).toString();
    }
  }

  void setStateKey(String? key, {reset = true}) {
    stateKey = key;

    final event = key == null
        ? null
        : room?.getState('im.ponies.room_emotes', key);
    final eventPack = event?.content.tryGetMap<String, Object?>('pack');
    packDisplayNameController.text =
        eventPack?.tryGet<String>('display_name') ?? '';
    packOrderController.text = event == null
        ? '0'
        : getCustomEmojiPackOrder(event.parsedImagePackContent).toString();
    if (reset) resetAction();
  }

  bool showSave = false;

  ImagePackContent _getPack() {
    final client = Matrix.of(context).client;
    final event =
        (room != null
            ? room!.getState('im.ponies.room_emotes', stateKey ?? '')
            : client.accountData['im.ponies.user_emotes']) ??
        BasicEvent(type: 'm.dummy', content: {});
    // make sure we work on a *copy* of the event
    return BasicEvent.fromJson(event.toJson()).parsedImagePackContent;
  }

  ImagePackContent? _pack;

  ImagePackContent? get pack {
    if (_pack != null) {
      return _pack;
    }
    _pack = _getPack();
    return _pack;
  }

  Future<void> save(BuildContext context) async {
    if (readonly) {
      return;
    }
    final client = Matrix.of(context).client;
    final result = await showFutureLoadingDialog(
      context: context,
      future: () => room != null
          ? client.setRoomStateWithKey(
              room!.id,
              'im.ponies.room_emotes',
              stateKey ?? '',
              pack!.toJson(),
            )
          : client.setAccountData(
              client.userID!,
              'im.ponies.user_emotes',
              pack!.toJson(),
            ),
    );
    if (!result.isError) {
      setState(() {
        showSave = false;
      });
    }
  }

  Future<void> setIsGloballyActive(bool active) async {
    if (room == null) {
      return;
    }
    final client = Matrix.of(context).client;
    final content =
        client.accountData['im.ponies.emote_rooms']?.content ??
        <String, dynamic>{};
    if (active) {
      if (content['rooms'] is! Map) {
        content['rooms'] = <String, dynamic>{};
      }
      if (content['rooms'][room!.id] is! Map) {
        content['rooms'][room!.id] = <String, dynamic>{};
      }
      if (content['rooms'][room!.id][stateKey ?? ''] is! Map) {
        content['rooms'][room!.id][stateKey ?? ''] = <String, dynamic>{};
      }
    } else if (content['rooms'] is Map && content['rooms'][room!.id] is Map) {
      content['rooms'][room!.id].remove(stateKey ?? '');
    }
    // and save
    await showFutureLoadingDialog(
      context: context,
      future: () => client.setAccountData(
        client.userID!,
        'im.ponies.emote_rooms',
        content,
      ),
    );
    setState(() {});
  }

  final TextEditingController packDisplayNameController =
      TextEditingController();

  final TextEditingController packOrderController = TextEditingController();

  void removeImageAction(String oldImageCode) => setState(() {
    pack!.images.remove(oldImageCode);
    showSave = true;
  });

  void toggleUsage(String imageCode, ImagePackUsage usage) {
    setState(() {
      final usages = pack!.images[imageCode]!.usage ??= List.from(
        ImagePackUsage.values,
      );
      if (!usages.remove(usage)) usages.add(usage);
      showSave = true;
    });
  }

  void submitDisplaynameAction() {
    if (readonly) return;
    packDisplayNameController.text = packDisplayNameController.text.trim();
    final input = packDisplayNameController.text;

    setState(() {
      pack!.pack.displayName = input;
      showSave = true;
    });
  }

  void submitImageAction(
    String oldImageCode,
    ImagePackImageContent image,
    TextEditingController controller,
  ) {
    controller.text = controller.text.trim().replaceAll(' ', '-');
    final imageCode = controller.text;
    if (imageCode == oldImageCode) return;
    if (pack!.images.keys.any((k) => k == imageCode && k != oldImageCode)) {
      controller.text = oldImageCode;
      showOkAlertDialog(
        useRootNavigator: false,
        context: context,
        title: L10n.of(context).emoteExists,
        okLabel: L10n.of(context).ok,
      );
      return;
    }
    if (!RegExp(r'^[-\w]+$').hasMatch(imageCode)) {
      controller.text = oldImageCode;
      showOkAlertDialog(
        useRootNavigator: false,
        context: context,
        title: L10n.of(context).emoteInvalid,
        okLabel: L10n.of(context).ok,
      );
      return;
    }
    setState(() {
      pack!.images[imageCode] = image;
      pack!.images.remove(oldImageCode);
      showSave = true;
    });
  }

  void submitPackOrderAction() {
    if (readonly) return;
    final order = int.tryParse(packOrderController.text.trim()) ?? 0;
    setState(() {
      _pack = applyCustomEmojiPackOrder(pack!, order);
      showSave = true;
    });
  }

  CustomEmojiMeta imageMetadata(String imageCode) =>
      CustomEmojiMeta.fromImage(pack!.images[imageCode]!);

  void addAlias(String imageCode, String value) {
    var alias = value.trim();
    if (alias.startsWith(':')) alias = alias.substring(1);
    if (alias.endsWith(':')) alias = alias.substring(0, alias.length - 1);
    if (alias.isEmpty) return;
    _updateImageMeta(imageCode, (current) {
      if (current.aliases.any((a) => a.toLowerCase() == alias.toLowerCase())) {
        return current;
      }
      final aliases = [...current.aliases, alias]..sort();
      return CustomEmojiMeta(
        aliases: aliases,
        emojis: current.emojis,
        order: current.order,
        media: current.media,
      );
    });
  }

  void removeAlias(String imageCode, String alias) {
    _updateImageMeta(imageCode, (current) {
      final aliases = current.aliases.where((a) => a != alias).toList();
      return CustomEmojiMeta(
        aliases: aliases,
        emojis: current.emojis,
        order: current.order,
        media: current.media,
      );
    });
  }

  void addFallbackEmoji(String imageCode, String value) {
    final emoji = value.trim();
    if (emoji.isEmpty) return;
    _updateImageMeta(imageCode, (current) {
      if (current.emojis.contains(emoji)) return current;
      final emojis = [...current.emojis, emoji];
      return CustomEmojiMeta(
        aliases: current.aliases,
        emojis: emojis,
        order: current.order,
        media: current.media,
      );
    });
  }

  void removeFallbackEmoji(String imageCode, String emoji) {
    _updateImageMeta(imageCode, (current) {
      final emojis = current.emojis.where((e) => e != emoji).toList();
      return CustomEmojiMeta(
        aliases: current.aliases,
        emojis: emojis,
        order: current.order,
        media: current.media,
      );
    });
  }

  void reorderImage(List<String> imageKeys, int oldIndex, int newIndex) {
    if (readonly) return;
    if (oldIndex < newIndex) newIndex--;
    if (oldIndex == newIndex) return;
    final key = imageKeys.removeAt(oldIndex);
    imageKeys.insert(newIndex, key);
    setState(() {
      for (var i = 0; i < imageKeys.length; i++) {
        final code = imageKeys[i];
        final image = pack!.images[code];
        if (image == null) continue;
        final current = CustomEmojiMeta.fromImage(image);
        if (current.order != i) {
          pack!.images[code] = applyCustomEmojiMeta(
            image,
            CustomEmojiMeta(
              aliases: current.aliases,
              emojis: current.emojis,
              order: i,
              media: current.media,
            ),
          );
        }
      }
      showSave = true;
    });
  }

  void submitItemOrderAction(String imageCode, String value) {
    final parsed = int.tryParse(value.trim()) ?? 0;
    _updateImageMeta(imageCode, (current) {
      return CustomEmojiMeta(
        aliases: current.aliases,
        emojis: current.emojis,
        order: parsed,
        media: current.media,
      );
    });
  }

  Future<void> editMediaSourcesAction(String imageCode) async {
    final metadata = imageMetadata(imageCode);
    final updated = await showTextInputDialog(
      context: context,
      title: L10n.of(context).advancedConfigs,
      initialText: const JsonEncoder.withIndent(
        '  ',
      ).convert(metadata.media.toJson()),
      minLines: 5,
      maxLines: 12,
      keyboardType: TextInputType.multiline,
      validator: (input) {
        try {
          final decoded = jsonDecode(input);
          if (decoded is! Map<String, dynamic>) return 'Invalid JSON object';
          final rawSources = decoded.tryGetList<Object?>('sources');
          if (rawSources == null || rawSources.isEmpty) {
            return 'sources must not be empty';
          }
          return null;
        } catch (_) {
          return 'Invalid JSON';
        }
      },
    );
    if (updated == null) return;

    final decoded = jsonDecode(updated);
    if (decoded is! Map<String, dynamic>) return;
    final map = Map<String, Object?>.from(decoded);

    final loop = map.tryGet<bool>('loop') ?? true;
    final sourcesRaw = map.tryGetList<Object?>('sources') ?? const [];
    final sources = <CustomEmojiMediaSource>[];
    for (final source in sourcesRaw) {
      if (source is! Map) continue;
      try {
        sources.add(
          CustomEmojiMediaSource.fromJson(Map<String, Object?>.from(source)),
        );
      } catch (_) {}
    }
    if (sources.isEmpty) return;

    final requestedPrimary = customEmojiMediaKindFromString(
      map.tryGet<String>('primary'),
    );
    final primary =
        requestedPrimary != null &&
            sources.any((source) => source.kind == requestedPrimary)
        ? requestedPrimary
        : sources.first.kind;

    _updateImageMeta(imageCode, (current) {
      return CustomEmojiMeta(
        aliases: current.aliases,
        emojis: current.emojis,
        order: current.order,
        media: CustomEmojiMediaDescriptor(
          loop: loop,
          primary: primary,
          sources: sources,
        ),
      );
    });
  }

  void _updateImageMeta(
    String imageCode,
    CustomEmojiMeta Function(CustomEmojiMeta current) update,
  ) {
    if (readonly) return;
    final image = pack!.images[imageCode];
    if (image == null) return;
    final current = CustomEmojiMeta.fromImage(image);
    final next = update(current);
    setState(() {
      pack!.images[imageCode] = applyCustomEmojiMeta(image, next);
      showSave = true;
    });
  }

  bool isGloballyActive(Client? client) =>
      room != null &&
      client!.accountData['im.ponies.emote_rooms']?.content
              .tryGetMap<String, Object?>('rooms')
              ?.tryGetMap<String, Object?>(room!.id)
              ?.tryGetMap<String, Object?>(stateKey ?? '') !=
          null;

  bool get readonly =>
      room != null &&
      room?.canChangeStateEvent('im.ponies.room_emotes') == false;

  void resetAction() {
    setState(() {
      _pack = _getPack();
      packOrderController.text = getCustomEmojiPackOrder(_pack!).toString();
      showSave = false;
    });
  }

  Future<void> createImagePack() async {
    final room = this.room;
    if (room == null) throw Exception('Cannot create image pack without room');
    if (readonly) return;

    final input = await showTextInputDialog(
      context: context,
      title: L10n.of(context).newStickerPack,
      hintText: L10n.of(context).name,
      okLabel: L10n.of(context).create,
    );
    final name = input?.trim();
    if (name == null || name.isEmpty) return;
    if (!mounted) return;

    final keyName = slugify(name, delimiter: '_');
    if (keyName.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(L10n.of(context).emoteInvalid)));
      return;
    }

    if (packKeys?.contains(keyName) ?? false) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.of(context).stickerPackNameAlreadyExists)),
      );
      return;
    }

    await showFutureLoadingDialog(
      context: context,
      future: () => room.client.setRoomStateWithKey(
        room.id,
        'im.ponies.room_emotes',
        keyName,
        {
          'images': {},
          'pack': {'display_name': name},
        },
      ),
    );
    if (!mounted) return;
    await room.client.oneShotSync();
    if (!mounted) return;
    setState(() {
      setStateKey(keyName);
    });
  }

  Future<void> saveAction() async {
    await save(context);
    setState(() {
      showSave = false;
    });
  }

  Future<void> sharePackToRoomAction() async {
    final client = Matrix.of(context).client;
    final target = await showTextInputDialog(
      context: context,
      title: 'Share pack to room',
      hintText: '#room:example.org / !roomId:example.org',
      okLabel: L10n.of(context).share,
      cancelLabel: L10n.of(context).cancel,
    );
    final roomIdentifier = target?.trim();
    if (roomIdentifier == null || roomIdentifier.isEmpty) return;

    final targetRoom = roomIdentifier.sigil == '!'
        ? client.getRoomById(roomIdentifier)
        : client.getRoomByAlias(roomIdentifier);
    if (targetRoom == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Room not found in current account')),
      );
      return;
    }

    final baseStateKey = stateKey;
    final displayName = pack?.pack.displayName?.trim().isNotEmpty == true
        ? pack!.pack.displayName!.trim()
        : (baseStateKey?.trim().isNotEmpty == true
              ? baseStateKey!.trim()
              : 'pack');
    final shareStateKey = slugify(displayName);

    await showFutureLoadingDialog(
      context: context,
      future: () => client.setRoomStateWithKey(
        targetRoom.id,
        'im.ponies.room_emotes',
        shareStateKey,
        pack!.toJson(),
      ),
    );
  }

  Future<void> createStickers() async {
    final pickedFiles = await selectFiles(
      context,
      type: FileType.custom,
      allowedExtensions: const [
        'png',
        'jpg',
        'jpeg',
        'webp',
        'mp4',
        'webm',
        'json',
        'tgs',
      ],
      allowMultiple: true,
    );
    if (pickedFiles.isEmpty) return;
    if (!mounted) return;

    await showFutureLoadingDialog(
      context: context,
      futureWithProgress: (setProgress) async {
        for (final (i, pickedFile) in pickedFiles.indexed) {
          setProgress(i / pickedFiles.length);
          final imageCode = pickedFile.name.split('.').first;
          final image = await uploadPackAssetFile(pickedFile);
          setState(() {
            pack!.images[imageCode] = image;
          });
        }
      },
    );

    setState(() {
      showSave = true;
    });
  }

  Future<ImagePackImageContent> uploadPackAssetFile(XFile pickedFile) async {
    final bytes = await pickedFile.readAsBytes();
    return uploadPackAssetBytes(
      bytes: bytes,
      filename: pickedFile.name,
      mimeType: pickedFile.mimeType ?? lookupMimeType(pickedFile.path),
      sourcePath: pickedFile.path,
    );
  }

  Future<ImagePackImageContent> uploadPackAssetBytes({
    required Uint8List bytes,
    required String filename,
    String? mimeType,
    String? sourcePath,
  }) async {
    var resolvedMimeType =
        mimeType ?? lookupMimeType(filename) ?? 'application/octet-stream';
    var resolvedFilename = filename;
    var sanitizedBytes = bytes;
    final initialMediaKind = inferCustomEmojiMediaKind(
      mimetype: resolvedMimeType,
      uri: Uri.parse(resolvedFilename),
    );
    if (initialMediaKind == CustomEmojiMediaKind.webm ||
        initialMediaKind == CustomEmojiMediaKind.mp4) {
      final sanitized = await _stripAudioTrackFromStickerMedia(
        bytes: bytes,
        filename: filename,
        mimeType: resolvedMimeType,
        sourcePath: sourcePath,
      );
      if (sanitized != null) {
        sanitizedBytes = sanitized.bytes;
        resolvedFilename = sanitized.filename;
        resolvedMimeType = sanitized.mimeType;
      }
    }
    final mediaKind = inferCustomEmojiMediaKind(
      mimetype: resolvedMimeType,
      uri: Uri.parse(resolvedFilename),
    );

    MatrixFile uploadFile;
    Map<String, Object?> info;

    if (mediaKind == CustomEmojiMediaKind.image) {
      var imageFile = MatrixImageFile(
        bytes: sanitizedBytes,
        name: resolvedFilename,
      );
      imageFile =
          await imageFile.generateThumbnail(
            nativeImplementations: ClientManager.nativeImplementations,
          ) ??
          imageFile;
      uploadFile = imageFile;
      info = <String, Object?>{...imageFile.info};

      if (info['w'] is int && info['h'] is int) {
        final ratio = (info['w'] as int) / (info['h'] as int);
        if ((info['w'] as int) > (info['h'] as int)) {
          info['w'] = 256;
          info['h'] = (256.0 / ratio).round();
        } else {
          info['h'] = 256;
          info['w'] = (ratio * 256.0).round();
        }
      }
    } else {
      uploadFile = MatrixFile(
        bytes: sanitizedBytes,
        name: resolvedFilename,
        mimeType: resolvedMimeType,
      ).detectFileType;
      info = <String, Object?>{
        ...uploadFile.info,
        'mimetype': resolvedMimeType,
        'size': sanitizedBytes.length,
      };
    }

    final uri = await Matrix.of(context).client.uploadContent(
      uploadFile.bytes,
      filename: uploadFile.name,
      contentType: uploadFile.mimeType,
    );

    final image = ImagePackImageContent.fromJson(<String, Object?>{
      'url': uri.toString(),
      if (info.isNotEmpty) 'info': info,
    });
    final meta = CustomEmojiMeta(
      aliases: const [],
      emojis: const [],
      order: 0,
      media: CustomEmojiMediaDescriptor(
        loop: true,
        primary: mediaKind,
        sources: [
          CustomEmojiMediaSource(
            kind: mediaKind,
            url: uri,
            mimetype: uploadFile.mimeType,
          ),
        ],
      ),
    );
    return applyCustomEmojiMeta(image, meta);
  }

  Future<_SanitizedStickerMedia?> _stripAudioTrackFromStickerMedia({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
    String? sourcePath,
  }) async {
    if (kIsWeb || !PlatformInfos.isMobile) return null;

    final isVideoMime = mimeType.toLowerCase().startsWith('video/');
    if (!isVideoMime) return null;

    var inputPath = sourcePath;
    final createdTempSource = inputPath == null || inputPath.isEmpty;

    try {
      if (createdTempSource) {
        final tempDir = await getTemporaryDirectory();
        final fallbackExt = mimeType.toLowerCase().contains('webm')
            ? 'webm'
            : 'mp4';
        final ext = filename.contains('.')
            ? filename.split('.').last
            : fallbackExt;
        inputPath =
            '${tempDir.path}/emoji_strip_${DateTime.now().microsecondsSinceEpoch}.$ext';
        await XFile.fromData(
          bytes,
          mimeType: mimeType,
          name: filename,
        ).saveTo(inputPath);
      }

      final mediaInfo = await VideoCompress.compressVideo(
        inputPath,
        deleteOrigin: createdTempSource,
        includeAudio: false,
      );
      final outputPath = mediaInfo?.path;
      if (outputPath == null || outputPath.isEmpty) return null;

      final strippedBytes = await XFile(outputPath).readAsBytes();
      if (strippedBytes.isEmpty) return null;

      final sanitizedFilename = outputPath.split(RegExp(r'[\\/]')).last;
      final sanitizedMimeType =
          lookupMimeType(outputPath) ?? lookupMimeType(sanitizedFilename);

      Logs().v('Removed audio track from emoji/sticker media "$filename".');
      return _SanitizedStickerMedia(
        bytes: strippedBytes,
        filename: sanitizedFilename.isEmpty ? filename : sanitizedFilename,
        mimeType: sanitizedMimeType ?? mimeType,
      );
    } catch (e, s) {
      Logs().w(
        'Unable to strip audio from emoji/sticker media "$filename".',
        e,
        s,
      );
      return null;
    } finally {
      try {
        await VideoCompress.deleteAllCache();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return EmotesSettingsView(this);
  }

  Future<void> importEmojiZip() async {
    final result = await selectFiles(context, type: FileType.any);

    if (result.isEmpty) return;

    final buffer = InputMemoryStream(await result.single.readAsBytes());

    final archive = ZipDecoder().decodeStream(buffer);

    await showDialog(
      context: context,
      // breaks [Matrix.of] calls otherwise
      useRootNavigator: false,
      builder: (context) =>
          ImportEmoteArchiveDialog(controller: this, archive: archive),
    );
    setState(() {});
  }

  Future<void> exportAsZip() async {
    final client = Matrix.of(context).client;

    await showFutureLoadingDialog(
      context: context,
      future: () async {
        final pack = _getPack();
        final archive = Archive();
        for (final entry in pack.images.entries) {
          final emote = entry.value;
          final name = entry.key;
          final url = await emote.url.getDownloadUri(client);
          final response = await get(
            url,
            headers: {'authorization': 'Bearer ${client.accessToken}'},
          );

          archive.addFile(
            ArchiveFile(name, response.bodyBytes.length, response.bodyBytes),
          );
        }
        final fileName =
            '${pack.pack.displayName ?? client.userID?.localpart ?? 'emotes'}.zip';
        final output = ZipEncoder().encode(archive);

        MatrixFile(
          name: fileName,
          bytes: Uint8List.fromList(output),
        ).save(context);
      },
    );
  }
}

class _SanitizedStickerMedia {
  final Uint8List bytes;
  final String filename;
  final String mimeType;

  const _SanitizedStickerMedia({
    required this.bytes,
    required this.filename,
    required this.mimeType,
  });
}
