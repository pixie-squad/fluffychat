import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:matrix/matrix.dart';
import 'package:slugify/slugify.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/custom_emoji_catalog.dart';
import 'package:fluffychat/utils/markdown_context_builder.dart';
import 'package:fluffychat/widgets/custom_emoji_media.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import '../../widgets/avatar.dart';
import '../../widgets/matrix.dart';
import 'command_hints.dart';

class InputBar extends StatelessWidget {
  // Pre-compiled regexes for getSuggestions (avoid recompilation per keystroke)
  static final _commandRegex = RegExp(r'^/(\w*)$');
  static final _emojiRegex = RegExp(
    r'^:(?:([\p{L}\p{N}_-]+)~)?([\p{L}\p{N}_-]*)$',
    unicode: true,
  );
  static final _userMentionRegex = RegExp(r'(?:\s|^)@([-\w]+)$');
  static final _roomMentionRegex = RegExp(r'(?:\s|^)#([-\w]+)$');

  // Pre-compiled regexes for insertSuggestion
  static final _insertCommandRegex = RegExp(r'^(/\w*)$');
  static final _insertUserRegex = RegExp(r'(\s|^)(@[-\w]+)$');
  static final _insertRoomRegex = RegExp(r'(\s|^)(#[-\w]+)$');

  final Room room;
  final int? minLines;
  final int? maxLines;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<Uint8List?>? onSubmitImage;
  final FocusNode? focusNode;
  final TextEditingController? controller;
  final InputDecoration decoration;
  final ValueChanged<String>? onChanged;
  final bool? autofocus;
  final bool readOnly;
  final List<Emoji> suggestionEmojis;

  const InputBar({
    required this.room,
    this.minLines,
    this.maxLines,
    this.keyboardType,
    this.onSubmitted,
    this.onSubmitImage,
    this.focusNode,
    this.controller,
    required this.decoration,
    this.onChanged,
    this.autofocus,
    this.textInputAction,
    this.readOnly = false,
    required this.suggestionEmojis,
    super.key,
  });

  FutureOr<List<Map<String, Object?>>> getSuggestions(
    TextEditingValue text,
  ) async {
    if (text.selection.baseOffset != text.selection.extentOffset ||
        text.selection.baseOffset < 0) {
      return []; // no entries if there is selected text
    }
    final searchText = text.text.substring(0, text.selection.baseOffset);
    if (searchText.isEmpty) return [];

    var lastWsIndex = -1;
    for (var i = searchText.length - 1; i >= 0; i--) {
      final c = searchText.codeUnitAt(i);
      if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D) {
        lastWsIndex = i;
        break;
      }
    }
    final currentWord = lastWsIndex == -1
        ? searchText
        : searchText.substring(lastWsIndex + 1);

    // Debounce: RawAutocomplete discards stale results via call-ID,
    // so rapid keystrokes will only apply the latest result.
    await Future.delayed(const Duration(milliseconds: 50));

    final ret = <Map<String, Object?>>[];
    const maxResults = 30;

    final commandMatch = _commandRegex.firstMatch(searchText);
    if (commandMatch != null) {
      final commandSearch = commandMatch[1]!.toLowerCase();
      for (final command in room.client.commands.keys) {
        if (command.contains(commandSearch)) {
          ret.add({'type': 'command', 'name': command});
        }

        if (ret.length >= maxResults) return ret;
      }
    }

    String? packSearch;
    var emoteSearch = '';
    final emojiMatch = _emojiRegex.firstMatch(currentWord);
    final hasColonTrigger = emojiMatch != null;
    if (emojiMatch != null) {
      packSearch = emojiMatch[1];
      emoteSearch = (emojiMatch[2] ?? '').toLowerCase();
    } else if (!currentWord.startsWith('@') &&
        !currentWord.startsWith('#') &&
        !currentWord.startsWith('/') &&
        currentWord.isNotEmpty) {
      // Without ":", only show exact custom emoji matches.
      emoteSearch = currentWord.toLowerCase();
    }

    if (emojiMatch != null || emoteSearch.isNotEmpty) {
      final catalog = CustomEmojiCatalog.fromRoom(
        room,
        usage: ImagePackUsage.emoticon,
      );
      final availableSlots = max(0, maxResults - ret.length);
      if (availableSlots > 0) {
        final customMatches = (emojiMatch != null && emoteSearch.isEmpty)
            ? catalog.entries
                  .where(
                    (entry) =>
                        packSearch == null ||
                        packSearch.isEmpty ||
                        entry.packSlug == packSearch,
                  )
                  .take(availableSlots)
                  .map(
                    (entry) =>
                        CustomEmojiCatalogMatch(entry: entry, score: 999),
                  )
                  .toList()
            : catalog.search(
                emoteSearch,
                limit: availableSlots,
                pack: packSearch,
                exactOnly: !hasColonTrigger,
              );

        for (final match in customMatches) {
          final entry = match.entry;
          ret.add({
            'type': 'custom_emoji',
            'entry': entry,
            'name': entry.shortcode,
            'pack': entry.packSlug,
            'pack_avatar_url': entry.packAvatarUrl?.toString(),
            'pack_display_name': entry.packDisplayName,
            'mxc': entry.primaryMxc.toString(),
            'fallback_emoji': entry.primaryFallbackEmoji,
            'alias_hit': match.aliasHit,
            'emoji_hit': match.emojiHit,
            'current_word': currentWord,
            'insert': '${entry.insertShortcode} ',
          });
          if (ret.length >= maxResults) break;
        }
      }

      // aside of custom emoji, also propose unicode emojis when typing :query
      final remainingSlots = maxResults - ret.length;
      if (emojiMatch != null &&
          (packSearch == null || packSearch.isEmpty) &&
          emoteSearch.length >= 2 &&
          remainingSlots > 0) {
        final matchingUnicodeEmojis = <Emoji>[];
        for (final emoji in suggestionEmojis) {
          if (emoji.name.toLowerCase().contains(emoteSearch)) {
            matchingUnicodeEmojis.add(emoji);
          }
          if (matchingUnicodeEmojis.length >= remainingSlots * 3) break;
        }
        matchingUnicodeEmojis.sort((a, b) {
          final indexA = a.name.indexOf(emoteSearch);
          final indexB = b.name.indexOf(emoteSearch);
          if (indexA == -1 || indexB == -1) {
            if (indexA == indexB) return 0;
            if (indexA == -1) return 1;
            return 0;
          }
          return indexA.compareTo(indexB);
        });
        for (final emoji in matchingUnicodeEmojis) {
          ret.add({
            'type': 'emoji',
            'emoji': emoji.emoji,
            'label': emoji.name,
            'current_word': currentWord,
          });
          if (ret.length >= maxResults) break;
        }
      }
    }
    final userMatch = _userMentionRegex.firstMatch(searchText);
    if (userMatch != null) {
      final userSearch = userMatch[1]!.toLowerCase();
      for (final user in room.getParticipants()) {
        if ((user.displayName != null &&
                (user.displayName!.toLowerCase().contains(userSearch) ||
                    slugify(
                      user.displayName!.toLowerCase(),
                    ).contains(userSearch))) ||
            user.id.localpart!.toLowerCase().contains(userSearch)) {
          ret.add({
            'type': 'user',
            'mxid': user.id,
            'mention': user.mention,
            'displayname': user.displayName,
            'avatar_url': user.avatarUrl?.toString(),
          });
        }
        if (ret.length >= maxResults) {
          break;
        }
      }
    }
    final roomMatch = _roomMentionRegex.firstMatch(searchText);
    if (roomMatch != null) {
      final roomSearch = roomMatch[1]!.toLowerCase();
      for (final r in room.client.rooms) {
        if (r.getState(EventTypes.RoomTombstone) != null) {
          continue; // we don't care about tombstoned rooms
        }
        final state = r.getState(EventTypes.RoomCanonicalAlias);
        if ((state != null &&
                ((state.content['alias'] is String &&
                        state.content
                            .tryGet<String>('alias')!
                            .localpart!
                            .toLowerCase()
                            .contains(roomSearch)) ||
                    (state.content['alt_aliases'] is List &&
                        (state.content['alt_aliases'] as List).any(
                          (l) =>
                              l is String &&
                              l.localpart!.toLowerCase().contains(roomSearch),
                        )))) ||
            (r.name.toLowerCase().contains(roomSearch))) {
          ret.add({
            'type': 'room',
            'mxid': (r.canonicalAlias.isNotEmpty) ? r.canonicalAlias : r.id,
            'displayname': r.getLocalizedDisplayname(),
            'avatar_url': r.avatar?.toString(),
          });
        }
        if (ret.length >= maxResults) {
          break;
        }
      }
    }
    return ret;
  }

  Widget buildSuggestion(
    BuildContext context,
    Map<String, Object?> suggestion,
    void Function(Map<String, Object?>) onSelected,
    Client? client,
  ) {
    final theme = Theme.of(context);
    const size = 30.0;
    if (suggestion['type'] == 'command') {
      final command = suggestion['name'] as String;
      final hint = commandHint(L10n.of(context), command);
      return Tooltip(
        message: hint,
        waitDuration: const Duration(days: 1), // don't show on hover
        child: ListTile(
          onTap: () => onSelected(suggestion),
          title: Text(
            commandExample(command),
            style: const TextStyle(fontFamily: 'RobotoMono'),
          ),
          subtitle: Text(
            hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ),
      );
    }
    if (suggestion['type'] == 'emoji') {
      final label = suggestion['label'] as String;
      return Tooltip(
        message: label,
        waitDuration: const Duration(days: 1), // don't show on hover
        child: ListTile(
          onTap: () => onSelected(suggestion),
          leading: SizedBox.square(
            dimension: size,
            child: Text(
              suggestion['emoji'] as String,
              style: const TextStyle(fontSize: 16),
            ),
          ),
          title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      );
    }
    if (suggestion['type'] == 'custom_emoji') {
      final entry = suggestion['entry'] as CustomEmojiCatalogEntry?;
      final aliasHit = suggestion['alias_hit'] as String?;
      final emojiHit = suggestion['emoji_hit'] as String?;
      final matchHint = aliasHit != null
          ? 'alias: $aliasHit'
          : emojiHit != null
          ? 'fallback: $emojiHit'
          : null;
      return ListTile(
        onTap: () => onSelected(suggestion),
        leading: entry == null
            ? MxcImage(
                key: ValueKey(suggestion['name']),
                uri: suggestion['mxc'] is String
                    ? Uri.parse(suggestion['mxc'] as String)
                    : null,
                width: size,
                height: size,
                isThumbnail: false,
              )
            : CustomEmojiMedia(
                key: ValueKey('${entry.packSlug}_${entry.shortcode}'),
                client: client ?? room.client,
                fallbackMxc: entry.primaryMxc,
                metadata: entry.metadata,
                fallbackEmoji: entry.primaryFallbackEmoji,
                width: size,
                height: size,
                isThumbnail: false,
              ),
        title: Row(
          crossAxisAlignment: .center,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(suggestion['name'] as String),
                  if (matchHint != null)
                    Text(
                      matchHint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: Opacity(
                  opacity: suggestion['pack_avatar_url'] != null ? 0.8 : 0.5,
                  child: suggestion['pack_avatar_url'] != null
                      ? Avatar(
                          mxContent: Uri.tryParse(
                            suggestion['pack_avatar_url'] as String? ?? '',
                          ),
                          name: suggestion['pack_display_name'] as String?,
                          size: size * 0.9,
                          client: client,
                        )
                      : Text(suggestion['pack_display_name'] as String),
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (suggestion['type'] == 'user' || suggestion['type'] == 'room') {
      final url = Uri.parse(suggestion['avatar_url'] as String? ?? '');
      return ListTile(
        onTap: () => onSelected(suggestion),
        leading: Avatar(
          mxContent: url,
          name:
              suggestion['displayname'] as String? ??
              suggestion['mxid'] as String?,
          size: size,
          client: client,
        ),
        title: Text(
          suggestion['displayname'] as String? ?? suggestion['mxid'] as String,
        ),
      );
    }
    return const SizedBox.shrink();
  }

  String insertSuggestion(Map<String, Object?> suggestion) {
    final replaceText = controller!.text.substring(
      0,
      controller!.selection.baseOffset,
    );
    var startText = '';
    final afterText = replaceText == controller!.text
        ? ''
        : controller!.text.substring(controller!.selection.baseOffset + 1);
    var insertText = '';
    if (suggestion['type'] == 'command') {
      insertText = '${suggestion['name'] as String} ';
      startText = replaceText.replaceAllMapped(
        _insertCommandRegex,
        (Match m) => '/$insertText',
      );
    }
    if (suggestion['type'] == 'emoji') {
      insertText = '${suggestion['emoji'] as String} ';
      startText = replaceText.replaceAllMapped(
        suggestion['current_word'] as String,
        (Match m) => insertText,
      );
    }
    if (suggestion['type'] == 'custom_emoji') {
      insertText = suggestion['insert'] as String? ?? '';
      final currentWord = suggestion['current_word'] as String? ?? '';
      final baseOffset = controller!.selection.baseOffset;
      final replacementStart = max(0, baseOffset - currentWord.length);
      final text = controller!.text;
      final before = text.substring(0, replacementStart);
      final after = text.substring(baseOffset);
      return '$before$insertText$after';
    }
    if (suggestion['type'] == 'user') {
      insertText = '${suggestion['mention'] as String} ';
      startText = replaceText.replaceAllMapped(
        _insertUserRegex,
        (Match m) => '${m[1]}$insertText',
      );
    }
    if (suggestion['type'] == 'room') {
      insertText = '${suggestion['mxid'] as String} ';
      startText = replaceText.replaceAllMapped(
        _insertRoomRegex,
        (Match m) => '${m[1]}$insertText',
      );
    }

    return startText + afterText;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Autocomplete<Map<String, Object?>>(
      focusNode: focusNode,
      textEditingController: controller,
      optionsBuilder: getSuggestions,
      fieldViewBuilder: (context, controller, focusNode, _) => TextField(
        controller: controller,
        focusNode: focusNode,
        readOnly: readOnly,
        contextMenuBuilder: (c, e) => MarkdownContextBuilder(
          editableTextState: e,
          controller: controller,
        ),
        contentInsertionConfiguration: ContentInsertionConfiguration(
          onContentInserted: (KeyboardInsertedContent content) {
            final data = content.data;
            if (data == null) return;
            onSubmitImage?.call(data);
          },
        ),
        minLines: minLines,
        maxLines: maxLines,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        autofocus: autofocus!,
        inputFormatters: [
          LengthLimitingTextInputFormatter((maxPDUSize / 3).floor()),
        ],
        onSubmitted: (text) {
          // fix for library for now
          // it sets the types for the callback incorrectly
          onSubmitted!(text);
        },
        maxLength: AppSettings.textMessageMaxLength.value,
        decoration: decoration,
        onChanged: (text) {
          // fix for the library for now
          // it sets the types for the callback incorrectly
          onChanged!(text);
        },
        textCapitalization: TextCapitalization.sentences,
      ),
      optionsViewBuilder: (c, onSelected, s) {
        final suggestions = s.toList();
        return Material(
          elevation: theme.appBarTheme.scrolledUnderElevation ?? 4,
          shadowColor: theme.appBarTheme.shadowColor,
          borderRadius: BorderRadius.circular(AppConfig.borderRadius),
          clipBehavior: Clip.hardEdge,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: suggestions.length,
            itemBuilder: (context, i) => buildSuggestion(
              c,
              suggestions[i],
              onSelected,
              Matrix.of(context).client,
            ),
          ),
        );
      },
      displayStringForOption: insertSuggestion,
      optionsViewOpenDirection: OptionsViewOpenDirection.up,
    );
  }
}
