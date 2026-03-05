import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:matrix/matrix.dart';
import 'package:slugify/slugify.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/emoji_rendering.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/markdown_context_builder.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import '../../widgets/avatar.dart';
import '../../widgets/matrix.dart';
import 'command_hints.dart';

class InputBar extends StatelessWidget {
  // Pre-compiled regexes for getSuggestions (avoid recompilation per keystroke)
  static final _commandRegex = RegExp(r'^/(\w*)$');
  static final _emojiRegex = RegExp(
    r'(?:\s|^):(?:([\p{L}\p{N}_-]+)~)?([\p{L}\p{N}_-]+)$',
    unicode: true,
  );
  static final _userMentionRegex = RegExp(r'(?:\s|^)@([-\w]+)$');
  static final _roomMentionRegex = RegExp(r'(?:\s|^)#([-\w]+)$');

  // Pre-compiled regexes for insertSuggestion
  static final _insertCommandRegex = RegExp(r'^(/\w*)$');
  static final _insertEmoteRegex = RegExp(r'(\s|^)(:(?:[-\w]+~)?[-\w]+)$');
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

  FutureOr<List<Map<String, String?>>> getSuggestions(
    TextEditingValue text,
  ) async {
    if (text.selection.baseOffset != text.selection.extentOffset ||
        text.selection.baseOffset < 0) {
      return []; // no entries if there is selected text
    }
    final searchText = text.text.substring(0, text.selection.baseOffset);
    if (searchText.isEmpty) return [];

    // Fast path: skip all regex work when no trigger character is present.
    // This is the common case for normal typing in any language.
    var lastWsIndex = -1;
    for (var i = searchText.length - 1; i >= 0; i--) {
      final c = searchText.codeUnitAt(i);
      if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D) {
        lastWsIndex = i;
        break;
      }
    }
    final lastWord = lastWsIndex == -1
        ? searchText
        : searchText.substring(lastWsIndex + 1);
    final hasTrigger =
        lastWord.startsWith(':') ||
        lastWord.startsWith('@') ||
        lastWord.startsWith('#') ||
        (searchText.startsWith('/') && lastWsIndex == -1);
    if (!hasTrigger) return [];

    // Debounce: RawAutocomplete discards stale results via call-ID,
    // so rapid keystrokes will only apply the latest result.
    await Future.delayed(const Duration(milliseconds: 50));

    final ret = <Map<String, String?>>[];
    const maxResults = 30;

    final commandMatch = _commandRegex.firstMatch(searchText);
    if (commandMatch != null) {
      final commandSearch = commandMatch[1]!.toLowerCase();
      for (final command in room.client.commands.keys) {
        if (command.contains(commandSearch)) {
          ret.add({'type': 'command', 'name': command});
        }

        if (ret.length > maxResults) return ret;
      }
    }
    final emojiMatch = _emojiRegex.firstMatch(searchText);
    if (emojiMatch != null) {
      final packSearch = emojiMatch[1];
      final emoteSearch = emojiMatch[2]!.toLowerCase();
      final emotePacks = room.getImagePacks(ImagePackUsage.emoticon);
      if (packSearch == null || packSearch.isEmpty) {
        for (final pack in emotePacks.entries) {
          for (final emote in pack.value.images.entries) {
            if (emote.key.toLowerCase().contains(emoteSearch)) {
              ret.add({
                'type': 'emote',
                'name': emote.key,
                'pack': pack.key,
                'pack_avatar_url': pack.value.pack.avatarUrl?.toString(),
                'pack_display_name': pack.value.pack.displayName ?? pack.key,
                'mxc': emote.value.url.toString(),
              });
            }
            if (ret.length > maxResults) {
              break;
            }
          }
          if (ret.length > maxResults) {
            break;
          }
        }
      } else if (emotePacks[packSearch] != null) {
        for (final emote in emotePacks[packSearch]!.images.entries) {
          if (emote.key.toLowerCase().contains(emoteSearch)) {
            ret.add({
              'type': 'emote',
              'name': emote.key,
              'pack': packSearch,
              'pack_avatar_url': emotePacks[packSearch]!.pack.avatarUrl
                  ?.toString(),
              'pack_display_name':
                  emotePacks[packSearch]!.pack.displayName ?? packSearch,
              'mxc': emote.value.url.toString(),
            });
          }
          if (ret.length > maxResults) {
            break;
          }
        }
      }

      // aside of emote packs, also propose normal (tm) unicode emojis
      // require at least 2 chars to avoid scanning all ~1600 emojis
      final remainingSlots = maxResults - ret.length;
      if (emoteSearch.length >= 2 && remainingSlots > 0) {
        final matchingUnicodeEmojis = <Emoji>[];
        for (final emoji in suggestionEmojis) {
          if (emoji.name.toLowerCase().contains(emoteSearch)) {
            matchingUnicodeEmojis.add(emoji);
          }
          if (matchingUnicodeEmojis.length >= remainingSlots * 3) break;
        }

        // sort by the index of the search term in the name in order to have
        // best matches first
        // (thanks for the hint by github.com/nextcloud/circles devs)
        matchingUnicodeEmojis.sort((a, b) {
          final indexA = a.name.indexOf(emoteSearch);
          final indexB = b.name.indexOf(emoteSearch);
          if (indexA == -1 || indexB == -1) {
            if (indexA == indexB) return 0;
            if (indexA == -1) {
              return 1;
            } else {
              return 0;
            }
          }
          return indexA.compareTo(indexB);
        });
        for (final emoji in matchingUnicodeEmojis) {
          ret.add({
            'type': 'emoji',
            'emoji': emoji.emoji,
            'label': emoji.name,
            'current_word': ':$emoteSearch',
          });
          if (ret.length > maxResults) {
            break;
          }
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
        if (ret.length > maxResults) {
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
        if (ret.length > maxResults) {
          break;
        }
      }
    }
    return ret;
  }

  Widget buildSuggestion(
    BuildContext context,
    Map<String, String?> suggestion,
    void Function(Map<String, String?>) onSelected,
    Client? client,
  ) {
    final theme = Theme.of(context);
    const size = 30.0;
    if (suggestion['type'] == 'command') {
      final command = suggestion['name']!;
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
      final label = suggestion['label']!;
      return Tooltip(
        message: label,
        waitDuration: const Duration(days: 1), // don't show on hover
        child: ListTile(
          onTap: () => onSelected(suggestion),
          leading: SizedBox.square(
            dimension: size,
            child: Text(
              suggestion['emoji']!,
              style: appleEmojiTextStyle.copyWith(fontSize: 16),
            ),
          ),
          title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      );
    }
    if (suggestion['type'] == 'emote') {
      return ListTile(
        onTap: () => onSelected(suggestion),
        leading: MxcImage(
          // ensure proper ordering ...
          key: ValueKey(suggestion['name']),
          uri: suggestion['mxc'] is String
              ? Uri.parse(suggestion['mxc'] ?? '')
              : null,
          width: size,
          height: size,
          isThumbnail: false,
        ),
        title: Row(
          crossAxisAlignment: .center,
          children: <Widget>[
            Text(suggestion['name']!),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: Opacity(
                  opacity: suggestion['pack_avatar_url'] != null ? 0.8 : 0.5,
                  child: suggestion['pack_avatar_url'] != null
                      ? Avatar(
                          mxContent: Uri.tryParse(
                            suggestion.tryGet<String>('pack_avatar_url') ?? '',
                          ),
                          name: suggestion.tryGet<String>('pack_display_name'),
                          size: size * 0.9,
                          client: client,
                        )
                      : Text(suggestion['pack_display_name']!),
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (suggestion['type'] == 'user' || suggestion['type'] == 'room') {
      final url = Uri.parse(suggestion['avatar_url'] ?? '');
      return ListTile(
        onTap: () => onSelected(suggestion),
        leading: Avatar(
          mxContent: url,
          name:
              suggestion.tryGet<String>('displayname') ??
              suggestion.tryGet<String>('mxid'),
          size: size,
          client: client,
        ),
        title: Text(suggestion['displayname'] ?? suggestion['mxid']!),
      );
    }
    return const SizedBox.shrink();
  }

  String insertSuggestion(Map<String, String?> suggestion) {
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
      insertText = '${suggestion['name']!} ';
      startText = replaceText.replaceAllMapped(
        _insertCommandRegex,
        (Match m) => '/$insertText',
      );
    }
    if (suggestion['type'] == 'emoji') {
      insertText = '${suggestion['emoji']!} ';
      startText = replaceText.replaceAllMapped(
        suggestion['current_word']!,
        (Match m) => insertText,
      );
    }
    if (suggestion['type'] == 'emote') {
      var isUnique = true;
      final insertEmote = suggestion['name'];
      final insertPack = suggestion['pack'];
      final emotePacks = room.getImagePacks(ImagePackUsage.emoticon);
      for (final pack in emotePacks.entries) {
        if (pack.key == insertPack) {
          continue;
        }
        for (final emote in pack.value.images.entries) {
          if (emote.key == insertEmote) {
            isUnique = false;
            break;
          }
        }
        if (!isUnique) {
          break;
        }
      }
      insertText = ':${isUnique ? '' : '${insertPack!}~'}$insertEmote: ';
      startText = replaceText.replaceAllMapped(
        _insertEmoteRegex,
        (Match m) => '${m[1]}$insertText',
      );
    }
    if (suggestion['type'] == 'user') {
      insertText = '${suggestion['mention']!} ';
      startText = replaceText.replaceAllMapped(
        _insertUserRegex,
        (Match m) => '${m[1]}$insertText',
      );
    }
    if (suggestion['type'] == 'room') {
      insertText = '${suggestion['mxid']!} ';
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
    return Autocomplete<Map<String, String?>>(
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
