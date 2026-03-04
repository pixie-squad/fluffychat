import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';

import 'message_context_menu_logic.dart';

enum MessageContextAction {
  reply,
  copy,
  forward,
  replyInThread,
  select,
  edit,
  redact,
  report,
}

sealed class MessageContextMenuResult {
  const MessageContextMenuResult();
}

class MessageContextMenuActionResult extends MessageContextMenuResult {
  final MessageContextAction action;

  const MessageContextMenuActionResult(this.action);
}

class MessageContextMenuQuickReactionResult extends MessageContextMenuResult {
  final String reactionKey;

  const MessageContextMenuQuickReactionResult(this.reactionKey);
}

class MessageContextMenuCustomReactionResult extends MessageContextMenuResult {
  const MessageContextMenuCustomReactionResult();
}

Future<MessageContextMenuResult?> showMessageContextMenu({
  required BuildContext context,
  required Offset globalPosition,
  required MessageContextActionAvailability availability,
  required List<String> quickReactions,
  required Set<String> sentReactions,
}) {
  final overlay = Navigator.of(context).overlay?.context.findRenderObject();
  if (overlay is! RenderBox) {
    return Future.value(null);
  }
  final localPosition = _clampToOverlayBounds(
    overlay.globalToLocal(globalPosition),
    overlay.size,
  );
  final position = RelativeRect.fromLTRB(
    localPosition.dx,
    localPosition.dy,
    overlay.size.width,
    overlay.size.height,
  );

  final l10n = L10n.of(context);
  final theme = Theme.of(context);
  final errorColor = theme.colorScheme.error;

  final items = <PopupMenuEntry<MessageContextMenuResult>>[
    _QuickReactionsEntry(
      quickReactions: quickReactions,
      sentReactions: sentReactions,
      customReactionTooltip: l10n.customReaction,
    ),
    const PopupMenuDivider(height: 1),
    _menuActionEntry(
      action: MessageContextAction.reply,
      enabled: availability.reply,
      icon: Icons.reply_outlined,
      label: l10n.reply,
    ),
    _menuActionEntry(
      action: MessageContextAction.copy,
      enabled: availability.copy,
      icon: Icons.copy_outlined,
      label: l10n.copyToClipboard,
    ),
    _menuActionEntry(
      action: MessageContextAction.forward,
      enabled: availability.forward,
      icon: Icons.forward_outlined,
      label: l10n.forward,
    ),
    _menuActionEntry(
      action: MessageContextAction.replyInThread,
      enabled: availability.replyInThread,
      icon: Icons.message_outlined,
      label: l10n.replyInThread,
    ),
    _menuActionEntry(
      action: MessageContextAction.select,
      enabled: availability.select,
      icon: Icons.check_circle_outlined,
      label: l10n.select,
    ),
    if (availability.edit)
      _menuActionEntry(
        action: MessageContextAction.edit,
        enabled: true,
        icon: Icons.edit_outlined,
        label: l10n.edit,
      ),
    if (availability.redact)
      _menuActionEntry(
        action: MessageContextAction.redact,
        enabled: true,
        icon: Icons.delete_outlined,
        label: l10n.redactMessage,
        color: errorColor,
      ),
    _menuActionEntry(
      action: MessageContextAction.report,
      enabled: availability.report,
      icon: Icons.report_gmailerrorred_outlined,
      label: l10n.reportMessage,
      color: errorColor,
    ),
  ];

  return showMenu<MessageContextMenuResult>(
    context: context,
    position: position,
    popUpAnimationStyle: const AnimationStyle(
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
      duration: Duration(milliseconds: 220),
    ),
    items: items,
  );
}

Offset _clampToOverlayBounds(Offset position, Size overlaySize) {
  final maxDx = overlaySize.width > 1 ? overlaySize.width - 1 : 0.0;
  final maxDy = overlaySize.height > 1 ? overlaySize.height - 1 : 0.0;
  return Offset(
    _clampDouble(position.dx, 0.0, maxDx),
    _clampDouble(position.dy, 0.0, maxDy),
  );
}

double _clampDouble(double value, double min, double max) {
  if (value < min) return min;
  if (value > max) return max;
  return value;
}

PopupMenuItem<MessageContextMenuResult> _menuActionEntry({
  required MessageContextAction action,
  required bool enabled,
  required IconData icon,
  required String label,
  Color? color,
}) => PopupMenuItem<MessageContextMenuResult>(
  enabled: enabled,
  value: MessageContextMenuActionResult(action),
  child: Row(
    children: [
      Icon(icon, color: color),
      const SizedBox(width: 12),
      Text(label, style: color == null ? null : TextStyle(color: color)),
    ],
  ),
);

class _QuickReactionsEntry extends PopupMenuEntry<MessageContextMenuResult> {
  final List<String> quickReactions;
  final Set<String> sentReactions;
  final String customReactionTooltip;

  const _QuickReactionsEntry({
    required this.quickReactions,
    required this.sentReactions,
    required this.customReactionTooltip,
  });

  @override
  double get height => 44;

  @override
  bool represents(MessageContextMenuResult? value) => false;

  @override
  State<_QuickReactionsEntry> createState() => _QuickReactionsEntryState();
}

class _QuickReactionsEntryState extends State<_QuickReactionsEntry> {
  @override
  Widget build(BuildContext context) {
    final reactions = widget.quickReactions.take(6).toList(growable: false);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
      child: SizedBox(
        height: 40,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...reactions.map(
              (reaction) => IconButton(
                constraints: const BoxConstraints.tightFor(
                  width: 36,
                  height: 36,
                ),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                onPressed: widget.sentReactions.contains(reaction)
                    ? null
                    : () => Navigator.of(
                        context,
                      ).pop(MessageContextMenuQuickReactionResult(reaction)),
                icon: Opacity(
                  opacity: widget.sentReactions.contains(reaction) ? 0.33 : 1,
                  child: Text(
                    reaction,
                    style: const TextStyle(fontSize: 20),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
            IconButton(
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.keyboard_arrow_down_outlined),
              tooltip: widget.customReactionTooltip,
              onPressed: () => Navigator.of(
                context,
              ).pop(const MessageContextMenuCustomReactionResult()),
            ),
          ],
        ),
      ),
    );
  }
}
