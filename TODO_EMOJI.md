# Emoji/Sticker Overhaul TODO

## Scope
- [x] Requirements/UX decisions locked.
- [x] Codebase discovery completed.
- [x] File-level implementation map completed.
- [x] Implement animated custom emoji/sticker support for `WEBM`, `MP4`, `Lottie (.json/.tgs)` with loop + fallback.
- [x] Keep unsupported clients on first fallback emoji in plaintext bodies.
- [x] Preserve existing command, mention, reply, and thread behavior.

## Data Model
- [x] Add/verify `lottie` dependency in `pubspec.yaml`.
- [x] Add `lib/utils/custom_emoji_metadata.dart` for `im.fluffychat.meta` and `im.fluffychat.order` parse/write helpers.
- [x] Add `lib/utils/custom_emoji_catalog.dart` to index canonical shortcode, aliases, fallback emojis, media sources, pack/order metadata.
- [x] Preserve unknown keys and legacy compatibility for existing `im.ponies.*` packs.

## Composer
- [x] Add `lib/widgets/composer_emoji_text_controller.dart` with inline widget spans for resolved custom shortcode tokens.
- [x] Wire composer controller in `lib/pages/chat/chat.dart`.
- [x] Upgrade `lib/pages/chat/input_bar.dart` suggestions: global fuzzy custom-emoji trigger + alias/emoji search + ranking.
- [x] Keep `/`, `@`, `#` behaviors unchanged priority.
- [x] Update suggestion UI to show canonical name, alias hit, pack indicator, and media preview.
- [x] Add `lib/utils/custom_emoji_message_builder.dart`.
- [x] Send non-command text through fallback-body + formatted-body builder and include `im.fluffychat.source_body`.
- [x] Keep command-prefixed messages on `sendTextEvent(parseCommands: true)` path.
- [x] Prefill edit input from `im.fluffychat.source_body` when present.

## Picker
- [x] Add `lib/widgets/custom_emoji_media.dart` unified renderer with autoplay + fallback handling.
- [x] Integrate media renderer in sticker picker dialogs and emoji status picker.
- [x] Integrate media renderer in settings emote previews.
- [x] Integrate media renderer in message reactions.
- [x] Integrate media renderer in HTML message `<img data-mx-emoticon>` rendering.
- [x] Overhaul `lib/pages/chat/chat_emoji_picker.dart` to include pack category bar in emoji tab.
- [x] Keep Unicode emoji categories and sticker tab behavior available.
- [x] Apply pack ordering and item ordering in picker surfaces.

## Settings/Share
- [x] Extend settings emote item editor with aliases, fallback emojis, and per-item order fields.
- [x] Add media source type/kind editing support in emote settings.
- [x] Update upload/import to accept image/video/lottie source files.
- [x] Persist typed media source descriptors in metadata.
- [x] Add “Share pack to room” action (room-state `im.ponies.room_emotes` with slugified state key).
- [x] Ensure shared packs appear in recipient room picker automatically.

## Tests
- [x] Add `test/custom_emoji_metadata_test.dart`.
- [x] Add `test/custom_emoji_catalog_test.dart`.
- [ ] Add `test/custom_emoji_message_builder_test.dart`.
- [ ] Add `test/composer_inline_custom_emoji_test.dart`.
- [ ] Add `test/input_bar_custom_emoji_suggestions_test.dart`.
- [ ] Add `test/chat_emoji_picker_pack_categories_test.dart`.
- [ ] Add `test/custom_emoji_media_fallback_test.dart`.
- [ ] Add `test/custom_emoji_media_autoplay_test.dart`.
- [ ] Run focused tests for new utilities and widget behavior.

## Rollout
- [ ] Manually verify animated media send/receive in mixed-client room.
- [ ] Manually verify unsupported media fallback to first fallback emoji.
- [ ] Manually verify pack share to room and recipient picker visibility.
- [ ] Manually verify edit round-trip preserves shortcode source text.
