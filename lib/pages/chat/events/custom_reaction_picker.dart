import 'package:flutter/material.dart';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/adaptive_bottom_sheet.dart';

Future<String?> showCustomReactionPicker(BuildContext context) {
  final theme = Theme.of(context);
  return showAdaptiveBottomSheet<String>(
    context: context,
    builder: (context) => Scaffold(
      appBar: AppBar(
        title: Text(L10n.of(context).customReaction),
        leading: CloseButton(onPressed: () => Navigator.of(context).pop(null)),
      ),
      body: SizedBox(
        height: double.infinity,
        child: EmojiPicker(
          onEmojiSelected: (_, emoji) => Navigator.of(context).pop(emoji.emoji),
          config: Config(
            locale: Localizations.localeOf(context),
            emojiViewConfig: const EmojiViewConfig(
              backgroundColor: Colors.transparent,
            ),
            bottomActionBarConfig: const BottomActionBarConfig(enabled: false),
            categoryViewConfig: CategoryViewConfig(
              initCategory: Category.SMILEYS,
              backspaceColor: theme.colorScheme.primary,
              iconColor: theme.colorScheme.primary.withAlpha(128),
              iconColorSelected: theme.colorScheme.primary,
              indicatorColor: theme.colorScheme.primary,
              backgroundColor: theme.colorScheme.surface,
            ),
            skinToneConfig: SkinToneConfig(
              dialogBackgroundColor: Color.lerp(
                theme.colorScheme.surface,
                theme.colorScheme.primaryContainer,
                0.75,
              )!,
              indicatorColor: theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    ),
  );
}
