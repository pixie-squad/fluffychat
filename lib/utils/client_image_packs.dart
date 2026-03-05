import 'package:matrix/matrix.dart';
import 'package:slugify/slugify.dart';

/// Gets all user-level and globally-activated image packs from a [Client],
/// without requiring a [Room] context. This mirrors the first two steps of
/// [Room.getImagePacks] from the Matrix SDK.
Map<String, ImagePackContent> getClientImagePacks(
  Client client, [
  ImagePackUsage? usage,
]) {
  final allMxcs = <Uri>{};
  final packs = <String, ImagePackContent>{};

  void addImagePack(BasicEvent? event, {Room? room, String? slug}) {
    if (event == null) return;
    final imagePack = event.parsedImagePackContent;
    final finalSlug = slugify(slug ?? 'pack');
    for (final entry in imagePack.images.entries) {
      final image = entry.value;
      if (allMxcs.contains(image.url)) continue;
      final imageUsage = image.usage ?? imagePack.pack.usage;
      if (usage != null &&
          imageUsage != null &&
          !imageUsage.contains(usage)) {
        continue;
      }
      packs
          .putIfAbsent(
            finalSlug,
            () => ImagePackContent.fromJson({})
              ..pack.displayName = imagePack.pack.displayName ??
                  room?.getLocalizedDisplayname() ??
                  finalSlug
              ..pack.avatarUrl = imagePack.pack.avatarUrl ?? room?.avatar
              ..pack.attribution = imagePack.pack.attribution,
          )
          .images[entry.key] = image;
      allMxcs.add(image.url);
    }
  }

  // User-level pack
  addImagePack(client.accountData['im.ponies.user_emotes'], slug: 'user');

  // Globally-activated room packs
  final packRooms = client.accountData['im.ponies.emote_rooms'];
  final rooms = packRooms?.content.tryGetMap<String, Object?>('rooms');
  if (packRooms != null && rooms != null) {
    for (final roomEntry in rooms.entries) {
      final roomId = roomEntry.key;
      final room = client.getRoomById(roomId);
      final roomEntryValue = roomEntry.value;
      if (room != null && roomEntryValue is Map<String, Object?>) {
        for (final stateKeyEntry in roomEntryValue.entries) {
          final stateKey = stateKeyEntry.key;
          final fallbackSlug =
              '${room.getLocalizedDisplayname()}-${stateKey.isNotEmpty ? '$stateKey-' : ''}${room.id}';
          addImagePack(
            room.getState('im.ponies.room_emotes', stateKey),
            room: room,
            slug: fallbackSlug,
          );
        }
      }
    }
  }

  return packs;
}
