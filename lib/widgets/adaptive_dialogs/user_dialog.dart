import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/file_selector.dart';
import 'package:fluffychat/utils/fluffy_share.dart';
import 'package:fluffychat/utils/name_gradients.dart';
import 'package:fluffychat/utils/profile_card_fields.dart';
import 'package:fluffychat/utils/client_manager.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:fluffychat/widgets/presence_builder.dart';

import '../../utils/url_launcher.dart';
import '../future_loading_dialog.dart';
import '../matrix.dart';
import '../mxc_image_viewer.dart';

class UserDialog extends StatefulWidget {
  static Future<void> show({
    required BuildContext context,
    required Profile profile,
    bool noProfileWarning = false,
  }) => showAdaptiveDialog(
    context: context,
    barrierDismissible: true,
    builder: (context) =>
        UserDialog(profile, noProfileWarning: noProfileWarning),
  );

  final Profile profile;
  final bool noProfileWarning;

  const UserDialog(this.profile, {this.noProfileWarning = false, super.key});

  @override
  State<UserDialog> createState() => _UserDialogState();
}

class _UserDialogState extends State<UserDialog> {
  static const List<Color> _backgroundPresets = [
    Color(0xFF8A8246),
    Color(0xFF866D35),
    Color(0xFF6E7A5E),
    Color(0xFF4E5F72),
    Color(0xFF6E5A78),
    Color(0xFF7F4E4E),
    Color(0xFF474747),
    Color(0xFF2E2E2E),
  ];

  ProfileCardFields _profileFields = const ProfileCardFields();
  bool _fieldsLoading = false;
  bool _copiedMxid = false;

  Client get _client => Matrix.of(context).client;

  bool get _isSelf => widget.profile.userId == _client.userID;

  String get _displayname =>
      widget.profile.displayName ??
      widget.profile.userId.localpart ??
      L10n.of(context).user;

  @override
  void initState() {
    super.initState();
    _reloadProfileFields();
  }

  Future<void> _reloadProfileFields() async {
    setState(() => _fieldsLoading = true);
    final fields = await loadProfileCardFields(_client, widget.profile.userId);
    if (!mounted) return;
    setState(() {
      _profileFields = fields;
      _fieldsLoading = false;
    });
  }

  String? _presenceActivityText(CachedPresence? presence) {
    final lastActiveTimestamp = presence?.lastActiveTimestamp;
    if (presence?.currentlyActive == true) {
      return L10n.of(context).currentlyActive;
    }
    if (lastActiveTimestamp != null) {
      return L10n.of(
        context,
      ).lastActiveAgo(lastActiveTimestamp.localizedTimeShort(context));
    }
    return null;
  }

  String? _statusText(CachedPresence? presence) {
    final statusMsg = presence?.statusMsg?.trim();
    if (statusMsg == null || statusMsg.isEmpty) return null;
    return statusMsg;
  }

  Future<void> _copyMxid() async {
    await Clipboard.setData(ClipboardData(text: widget.profile.userId));
    if (!mounted) return;
    setState(() => _copiedMxid = true);
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copiedMxid = false);
    });
  }

  Future<Room> _resolveDirectRoom() async {
    final client = _client;
    final existingDirectRoomId = client.getDirectChatFromUserId(
      widget.profile.userId,
    );
    final roomId =
        existingDirectRoomId ??
        await client.startDirectChat(widget.profile.userId);

    var room = client.getRoomById(roomId);
    if (room == null) {
      await client.waitForRoomInSync(roomId);
      room = client.getRoomById(roomId);
    }
    if (room == null) {
      throw Exception('Direct chat not found: $roomId');
    }
    return room;
  }

  Future<void> _openMessage() async {
    if (_isSelf) return;
    final router = GoRouter.of(context);
    final roomIdResult = await showFutureLoadingDialog<String>(
      context: context,
      future: () => _client.startDirectChat(widget.profile.userId),
    );
    final roomId = roomIdResult.result;
    if (roomId == null || !mounted) return;
    Navigator.of(context).pop();
    router.go('/rooms/$roomId');
  }

  Future<void> _toggleMute() async {
    if (_isSelf) return;
    await showFutureLoadingDialog(
      context: context,
      future: () async {
        final room = await _resolveDirectRoom();
        await room.setPushRuleState(
          room.pushRuleState == PushRuleState.notify
              ? PushRuleState.mentionsOnly
              : PushRuleState.notify,
        );
      },
    );
  }

  Future<void> _callAction() async {
    if (_isSelf) return;
    final voipPlugin = Matrix.of(context).voipPlugin;
    if (voipPlugin == null) return;

    final callType = await showModalActionPopup<CallType>(
      context: context,
      title: L10n.of(context).warning,
      message: L10n.of(context).videoCallsBetaWarning,
      cancelLabel: L10n.of(context).cancel,
      actions: [
        AdaptiveModalAction(
          label: L10n.of(context).voiceCall,
          icon: const Icon(Icons.phone_outlined),
          value: CallType.kVoice,
        ),
        AdaptiveModalAction(
          label: L10n.of(context).videoCall,
          icon: const Icon(Icons.video_call_outlined),
          value: CallType.kVideo,
        ),
      ],
    );

    if (callType == null) return;

    await showFutureLoadingDialog(
      context: context,
      future: () async {
        final room = await _resolveDirectRoom();
        await voipPlugin.voip.inviteToCall(room, callType);
      },
    );
  }

  Future<void> _reportUser() async {
    final reason = await showTextInputDialog(
      context: context,
      title: L10n.of(context).whyDoYouWantToReportThis,
      okLabel: L10n.of(context).report,
      cancelLabel: L10n.of(context).cancel,
      hintText: L10n.of(context).reason,
    );
    if (reason == null || reason.isEmpty) return;
    if (!mounted) return;

    await showFutureLoadingDialog(
      context: context,
      future: () => _client.reportUser(widget.profile.userId, reason),
    );
  }

  void _openBlockScreen() {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.go(
      '/rooms/settings/security/ignorelist',
      extra: widget.profile.userId,
    );
  }

  Future<void> _openMoreMenu() async {
    final actions = <AdaptiveModalAction<_UserMoreAction>>[
      AdaptiveModalAction(
        label: L10n.of(context).copy,
        value: _UserMoreAction.copy,
        icon: const Icon(Icons.copy_outlined),
      ),
      AdaptiveModalAction(
        label: L10n.of(context).share,
        value: _UserMoreAction.share,
        icon: Icon(Icons.adaptive.share_outlined),
      ),
      if (!_isSelf)
        AdaptiveModalAction(
          label: L10n.of(context).report,
          value: _UserMoreAction.report,
          icon: const Icon(Icons.gavel_outlined),
        ),
      if (!_isSelf)
        AdaptiveModalAction(
          label: L10n.of(context).block,
          value: _UserMoreAction.block,
          icon: const Icon(Icons.block_outlined),
          isDestructive: true,
        ),
    ];

    final action = await showModalActionPopup<_UserMoreAction>(
      context: context,
      title: L10n.of(context).more,
      cancelLabel: L10n.of(context).cancel,
      actions: actions,
      useRootNavigator: false,
    );

    if (!mounted || action == null) return;

    switch (action) {
      case _UserMoreAction.copy:
        await _copyMxid();
        return;
      case _UserMoreAction.share:
        await FluffyShare.share(
          'https://matrix.to/#/${widget.profile.userId}',
          context,
        );
        return;
      case _UserMoreAction.report:
        await _reportUser();
        return;
      case _UserMoreAction.block:
        _openBlockScreen();
        return;
    }
  }

  Future<void> _showBackgroundPicker() async {
    if (!_isSelf) return;

    final choice = await showAdaptiveDialog<_BackgroundColorChoice>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog.adaptive(
          title: Text(L10n.of(context).profileBackgroundColor),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final color in _backgroundPresets)
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => Navigator.of(
                      context,
                    ).pop(_BackgroundColorChoice(value: color.toARGB32())),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(color: theme.colorScheme.outline),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(L10n.of(context).cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(
                context,
              ).pop(const _BackgroundColorChoice(remove: true)),
              child: Text(
                L10n.of(context).remove,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          ],
        );
      },
    );

    if (choice == null) return;

    await showFutureLoadingDialog(
      context: context,
      future: () async {
        if (choice.remove) {
          await _client.deleteProfileField(
            _client.userID!,
            profileBackgroundColorField,
          );
          return;
        }

        await _client.setProfileField(
          _client.userID!,
          profileBackgroundColorField,
          {profileBackgroundColorField: choice.value},
        );
      },
    );

    if (!mounted) return;
    await _reloadProfileFields();
  }

  Future<void> _pickEmojiStatusImage() async {
    if (!_isSelf) return;

    final selected = await selectFiles(context, type: FileType.image);
    if (selected.isEmpty) return;

    await showFutureLoadingDialog(
      context: context,
      future: () async {
        final picked = selected.first;
        final image = MatrixImageFile(
          bytes: await picked.readAsBytes(),
          name: picked.name,
        );

        final resized = await image.generateThumbnail(
          dimension: 256,
          nativeImplementations: ClientManager.nativeImplementations,
        );

        if (resized == null) {
          throw Exception('Unable to resize image to 256x256');
        }

        final uri = await _client.uploadContent(
          resized.bytes,
          filename: resized.name,
          contentType: resized.mimeType,
        );

        await _client.setProfileField(
          _client.userID!,
          profileEmojiStatusField,
          {profileEmojiStatusField: uri.toString()},
        );
        profileEmojiStatusCache.invalidate(_client.userID!);
      },
    );

    if (!mounted) return;
    await _reloadProfileFields();
  }

  Future<void> _removeEmojiStatus() async {
    if (!_isSelf) return;

    await showFutureLoadingDialog(
      context: context,
      future: () =>
          _client.deleteProfileField(_client.userID!, profileEmojiStatusField),
    );
    profileEmojiStatusCache.invalidate(_client.userID!);

    if (!mounted) return;
    await _reloadProfileFields();
  }

  Future<void> _showEmojiStatusMenu() async {
    if (!_isSelf) return;

    final action = await showModalActionPopup<_EmojiStatusAction>(
      context: context,
      title: L10n.of(context).profileEmojiStatus,
      cancelLabel: L10n.of(context).cancel,
      useRootNavigator: false,
      actions: [
        AdaptiveModalAction(
          label: L10n.of(context).profilePickImage,
          icon: const Icon(Icons.image_outlined),
          value: _EmojiStatusAction.pickImage,
          isDefaultAction: true,
        ),
        AdaptiveModalAction(
          label: L10n.of(context).remove,
          icon: const Icon(Icons.delete_outline),
          value: _EmojiStatusAction.remove,
          isDestructive: true,
        ),
      ],
    );

    if (action == null) return;

    switch (action) {
      case _EmojiStatusAction.pickImage:
        await _pickEmojiStatusImage();
        return;
      case _EmojiStatusAction.remove:
        await _removeEmojiStatus();
        return;
    }
  }

  Widget _buildStatusPill({
    required String text,
    required Color background,
    required Color foreground,
    IconData? icon,
  }) {
    final borderColor = Color.alphaBlend(
      foreground.withAlpha(100),
      background,
    );
    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(22),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBioSection(BuildContext context) {
    final bio = _profileFields.bio;
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: theme.colorScheme.surfaceContainerLow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Text(L10n.of(context).profileBio, style: theme.textTheme.labelLarge),
          if (bio == null)
            Text('—', style: theme.textTheme.bodyMedium)
          else
            SelectableLinkify(
              text: bio,
              textScaleFactor: MediaQuery.textScalerOf(context).scale(1),
              textAlign: TextAlign.start,
              options: const LinkifyOptions(humanize: false),
              linkStyle: TextStyle(
                color: theme.colorScheme.primary,
                decoration: TextDecoration.underline,
                decorationColor: theme.colorScheme.primary,
              ),
              onOpen: (url) => UrlLauncher(context, url.url).launchUrl(),
            ),
        ],
      ),
    );
  }

  Widget _buildUsernameSection(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: theme.colorScheme.surfaceContainerLow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Text(L10n.of(context).username, style: theme.textTheme.labelLarge),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  widget.profile.userId,
                  maxLines: 1,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              IconButton(
                onPressed: _copyMxid,
                icon: Icon(
                  _copiedMxid ? Icons.check_circle : Icons.copy_outlined,
                  color: _copiedMxid ? Colors.green : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturedChannelSection(BuildContext context) {
    final featured = _profileFields.featuredChannel;
    if (featured == null) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: theme.colorScheme.surfaceContainerLow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          Text(
            L10n.of(context).profileFeaturedChannel,
            style: theme.textTheme.labelLarge,
          ),
          Row(
            spacing: 10,
            children: [
              Avatar(
                mxContent: featured.avatarUrl,
                name: featured.title ?? featured.roomId,
                size: 44,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      featured.title ?? featured.roomId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    if (featured.subtitle != null)
                      Text(
                        featured.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final avatar = widget.profile.avatarUrl;
    final screenSize = MediaQuery.sizeOf(context);
    final maxDialogWidth = (screenSize.width - 24).clamp(320.0, 760.0).toDouble();
    final targetDialogWidth = (screenSize.width * 0.35)
        .clamp(320.0, 620.0)
        .toDouble();
    final dialogWidth = targetDialogWidth > maxDialogWidth
        ? maxDialogWidth
        : targetDialogWidth;

    final maxDialogHeight = (screenSize.height - 24)
        .clamp(360.0, 1200.0)
        .toDouble();
    final targetDialogHeight = (screenSize.height * 0.8)
        .clamp(420.0, 980.0)
        .toDouble();
    final dialogHeight = targetDialogHeight > maxDialogHeight
        ? maxDialogHeight
        : targetDialogHeight;

    final scale = (dialogWidth / 460).clamp(1.0, 1.35).toDouble();
    final avatarSize = 96.0 * scale;
    final headerTopPadding = 14.0 * scale;
    final headerHorizontalPadding = 18.0 * scale;
    final headerBottomPadding = 22.0 * scale;

    return AlertDialog.adaptive(
      contentPadding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      content: PresenceBuilder(
        userId: widget.profile.userId,
        client: _client,
        builder: (context, presence) {
          final headerColor =
              _profileFields.backgroundColor ??
              theme.colorScheme.surfaceContainer;
          final headerOnColor =
              ThemeData.estimateBrightnessForColor(headerColor) ==
                  Brightness.dark
              ? Colors.white
              : Colors.black;

          final pillBackground = Color.alphaBlend(
            headerOnColor.withAlpha(82),
            headerColor,
          );
          final actionBackground = Color.alphaBlend(
            headerOnColor.withAlpha(52),
            headerColor,
          );

          final presenceActivityText = _presenceActivityText(presence);
          final statusText = _statusText(presence);
          final emojiStatusUri = _profileFields.emojiStatusMxc;

          return SizedBox(
            width: dialogWidth,
            height: dialogHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  color: headerColor,
                  padding: EdgeInsets.fromLTRB(
                    headerHorizontalPadding,
                    headerTopPadding,
                    headerHorizontalPadding,
                    headerBottomPadding,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Row(
                            spacing: 8,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_isSelf)
                                _HeaderIconButton(
                                  tooltip: L10n.of(context).profileBackgroundColor,
                                  foreground: headerOnColor,
                                  background: actionBackground,
                                  onTap: _showBackgroundPicker,
                                  icon: Stack(
                                    clipBehavior: Clip.none,
                                    alignment: Alignment.center,
                                    children: [
                                      const Icon(Icons.palette_outlined, size: 18),
                                      if (_profileFields.backgroundColor != null)
                                        Positioned(
                                          right: -1,
                                          bottom: -1,
                                          child: Container(
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              color: _profileFields.backgroundColor,
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: headerOnColor,
                                                width: 0.8,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              if (_isSelf || _profileFields.emojiStatusMxc != null)
                                _HeaderIconButton(
                                  tooltip: L10n.of(context).profileEmojiStatus,
                                  foreground: headerOnColor,
                                  background: actionBackground,
                                  onTap: _isSelf ? _showEmojiStatusMenu : null,
                                  icon: _profileFields.emojiStatusMxc == null
                                      ? const Icon(Icons.add_reaction_outlined, size: 18)
                                      : ClipRRect(
                                          borderRadius: BorderRadius.circular(999),
                                          child: MxcImage(
                                            uri: _profileFields.emojiStatusMxc,
                                            width: 20,
                                            height: 20,
                                            fit: BoxFit.cover,
                                            isThumbnail: true,
                                          ),
                                        ),
                                ),
                              if (_fieldsLoading)
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator.adaptive(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      headerOnColor,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const Spacer(),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: Icon(Icons.close, color: headerOnColor),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Avatar(
                        mxContent: avatar,
                        name: _displayname,
                        size: avatarSize,
                        presenceUserId: widget.profile.userId,
                        presenceBackgroundColor: headerColor,
                        showOfflinePresenceDot: true,
                        showPresenceTooltip: true,
                        onTap: avatar != null
                            ? () => showDialog(
                                context: context,
                                builder: (_) => MxcImageViewer(avatar),
                              )
                            : null,
                      ),
                      SizedBox(height: 14 * scale),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 14 * scale,
                          vertical: 9 * scale,
                        ),
                        decoration: BoxDecoration(
                          color: pillBackground,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: headerOnColor.withAlpha(112),
                            width: 1.1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: GradientDisplayName(
                                userId: widget.profile.userId,
                                text: _displayname,
                                client: _client,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: headerOnColor,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16 * scale,
                                ),
                              ),
                            ),
                            if (emojiStatusUri != null) ...[
                              SizedBox(width: 6 * scale),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: MxcImage(
                                  uri: emojiStatusUri,
                                  width: 16 * scale,
                                  height: 16 * scale,
                                  fit: BoxFit.cover,
                                  isThumbnail: true,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (presenceActivityText != null)
                        Padding(
                          padding: EdgeInsets.only(top: 4 * scale),
                          child: Text(
                            presenceActivityText,
                            style: TextStyle(
                              color: headerOnColor.withAlpha(140),
                              fontSize: 12 * scale,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      if (statusText != null) ...[
                        SizedBox(height: 10 * scale),
                        _buildStatusPill(
                          text: statusText,
                          icon: Icons.circle,
                          background: pillBackground,
                          foreground: headerOnColor,
                        ),
                      ],
                      if (widget.noProfileWarning) ...[
                        SizedBox(height: 10 * scale),
                        _buildStatusPill(
                          text: L10n.of(context).profileNotFound,
                          background: Colors.red.withAlpha(48),
                          foreground: headerOnColor,
                          icon: Icons.warning_amber_outlined,
                        ),
                      ],
                      SizedBox(height: 14 * scale),
                      Row(
                        spacing: 10 * scale,
                        children: [
                          _ProfileActionButton(
                            label: L10n.of(context).profileActionMessage,
                            icon: Icons.chat_bubble_outline,
                            foreground: headerOnColor,
                            background: actionBackground,
                            onTap: _isSelf ? null : _openMessage,
                          ),
                          _ProfileActionButton(
                            label: L10n.of(context).profileActionMute,
                            icon: Icons.notifications_off_outlined,
                            foreground: headerOnColor,
                            background: actionBackground,
                            onTap: _isSelf ? null : _toggleMute,
                          ),
                          _ProfileActionButton(
                            label: L10n.of(context).profileActionCall,
                            icon: Icons.call_outlined,
                            foreground: headerOnColor,
                            background: actionBackground,
                            onTap: _isSelf ? null : _callAction,
                          ),
                          _ProfileActionButton(
                            label: L10n.of(context).more.toLowerCase(),
                            icon: Icons.more_horiz,
                            foreground: headerOnColor,
                            background: actionBackground,
                            onTap: _openMoreMenu,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(18 * scale),
                    child: Column(
                      spacing: 12 * scale,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_profileFields.featuredChannel != null)
                          _buildFeaturedChannelSection(context),
                        _buildBioSection(context),
                        _buildUsernameSection(context),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ProfileActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color foreground;
  final Color background;
  final VoidCallback? onTap;

  const _ProfileActionButton({
    required this.icon,
    required this.label,
    required this.foreground,
    required this.background,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Expanded(
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(AppConfig.borderRadius / 2),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppConfig.borderRadius / 2),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: foreground),
                  const SizedBox(height: 5),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: foreground, fontSize: 12.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final String tooltip;
  final Widget icon;
  final Color foreground;
  final Color background;
  final VoidCallback? onTap;

  const _HeaderIconButton({
    required this.tooltip,
    required this.icon,
    required this.foreground,
    required this.background,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = IconTheme.merge(
      data: IconThemeData(color: foreground),
      child: SizedBox(width: 36, height: 36, child: Center(child: icon)),
    );
    final button = Opacity(
      opacity: onTap == null ? 0.7 : 1,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: content,
        ),
      ),
    );
    return Tooltip(message: tooltip, child: button);
  }
}

class _BackgroundColorChoice {
  final int? value;
  final bool remove;

  const _BackgroundColorChoice({this.value, this.remove = false});
}

enum _UserMoreAction { copy, share, report, block }

enum _EmojiStatusAction { pickImage, remove }
