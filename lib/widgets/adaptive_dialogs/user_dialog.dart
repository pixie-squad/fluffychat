import 'dart:math' as math;

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
import 'package:fluffychat/utils/profile_banner_style.dart';
import 'package:fluffychat/utils/profile_card_fields.dart';
import 'package:fluffychat/utils/client_manager.dart';
import 'package:fluffychat/utils/client_download_content_extension.dart';
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
  ProfileCardFields _profileFields = const ProfileCardFields();
  bool _fieldsLoading = false;
  bool _copiedMxid = false;
  ProfileBannerStyle _bannerStyle = ProfileBannerStyle.fallback;
  int _bannerStyleRequestId = 0;

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
    _refreshBannerStyle(fields.bannerMxc);
  }

  Future<void> _refreshBannerStyle(Uri? bannerUri) async {
    final requestId = ++_bannerStyleRequestId;
    if (bannerUri == null) {
      if (!mounted || requestId != _bannerStyleRequestId) return;
      setState(() {
        _bannerStyle = ProfileBannerStyle.fallback;
      });
      return;
    }

    final style = await _resolveBannerStyle(bannerUri);
    if (!mounted || requestId != _bannerStyleRequestId) return;
    setState(() {
      _bannerStyle = style;
    });
  }

  Future<ProfileBannerStyle> _resolveBannerStyle(Uri bannerUri) async {
    try {
      final data = await _client.downloadMxcCached(
        bannerUri,
        width: 640,
        height: 320,
        isThumbnail: true,
      );
      return resolveProfileBannerStyleFromBytes(data);
    } catch (e, s) {
      Logs().d('Unable to resolve profile banner style', e, s);
      return ProfileBannerStyle.fallback;
    }
  }

  String _presenceDotTooltipText(CachedPresence presence) {
    if (presence.currentlyActive == true || presence.presence.isOnline) {
      return L10n.of(context).online;
    }
    final lastActiveTimestamp = presence.lastActiveTimestamp;
    if (lastActiveTimestamp != null) {
      return L10n.of(
        context,
      ).lastActiveAgo(lastActiveTimestamp.localizedTimeShort(context));
    }
    return L10n.of(context).offline;
  }

  String? _statusText(CachedPresence? presence) {
    final statusMsg = presence?.statusMsg?.trim();
    if (statusMsg == null || statusMsg.isEmpty) return null;
    return statusMsg;
  }

  Color _resolveMonochromeContrastForeground(
    Color background, {
    double targetContrast = 4.5,
  }) => _resolveReadableForeground(
    background: background,
    candidates: const [Colors.black, Colors.white],
    targetContrast: targetContrast,
  );

  _NamePillStyle _resolveNamePillStyle() {
    final colorScheme = Theme.of(context).colorScheme;
    final background = colorScheme.surfaceContainerHighest;
    return _NamePillStyle(
      background: background,
      border: colorScheme.outlineVariant,
      fallbackTextColor: _resolveMonochromeContrastForeground(background),
    );
  }

  double _contrastRatio(Color first, Color second) {
    final l1 = first.computeLuminance();
    final l2 = second.computeLuminance();
    final lighter = math.max(l1, l2);
    final darker = math.min(l1, l2);
    return (lighter + 0.05) / (darker + 0.05);
  }

  Color _resolveReadableForeground({
    required Color background,
    required List<Color> candidates,
    double targetContrast = 4.0,
  }) {
    if (candidates.isEmpty) return Colors.white;

    var bestColor = candidates.first;
    var bestContrast = _contrastRatio(bestColor, background);
    if (bestContrast >= targetContrast) return bestColor;

    for (var i = 1; i < candidates.length; i++) {
      final candidate = candidates[i];
      final contrast = _contrastRatio(candidate, background);
      if (contrast > bestContrast) {
        bestContrast = contrast;
        bestColor = candidate;
      }
      if (contrast >= targetContrast) return candidate;
    }

    return bestColor;
  }

  _ControlSurfaceStyle _resolveControlSurfaceStyle() {
    final colorScheme = Theme.of(context).colorScheme;
    final background = colorScheme.surfaceContainerHigh;
    return _ControlSurfaceStyle(
      foreground: _resolveMonochromeContrastForeground(background),
      background: background,
      border: colorScheme.outlineVariant,
    );
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

  Future<void> _showBackgroundAppearanceChooser() async {
    if (!_isSelf) return;

    final action = await showAdaptiveDialog<_BackgroundAppearanceAction>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog.adaptive(
          title: Text(
            '${L10n.of(context).profileBackgroundColor} / ${L10n.of(context).profileBanner}',
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => Navigator.of(
                    context,
                  ).pop(_BackgroundAppearanceAction.backgroundColor),
                  icon: const Icon(Icons.palette_outlined),
                  label: const Text('Choose a background color'),
                ),
                const SizedBox(height: 10),
                Text(
                  'or',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.tonalIcon(
                  onPressed: () => Navigator.of(
                    context,
                  ).pop(_BackgroundAppearanceAction.banner),
                  icon: const Icon(Icons.landscape_outlined),
                  label: const Text('Choose a banner'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(L10n.of(context).cancel),
            ),
          ],
        );
      },
    );

    if (action == null || !mounted) return;

    switch (action) {
      case _BackgroundAppearanceAction.backgroundColor:
        await _showBackgroundPicker();
        return;
      case _BackgroundAppearanceAction.banner:
        await _showBannerMenu();
        return;
    }
  }

  Future<void> _showBackgroundPicker() async {
    if (!_isSelf) return;

    final choice = await showAdaptiveDialog<_BackgroundColorChoice>(
      context: context,
      builder: (context) => _BackgroundColorPickerDialog(
        initialColor:
            _profileFields.backgroundColor ??
            Theme.of(context).colorScheme.surfaceContainer,
      ),
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
        await _client.deleteProfileField(_client.userID!, profileBannerField);
      },
    );

    if (!mounted) return;
    await _reloadProfileFields();
  }

  Future<void> _pickBannerImage() async {
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

        final uri = await _client.uploadContent(
          image.bytes,
          filename: image.name,
          contentType: image.mimeType,
        );

        await _client.setProfileField(_client.userID!, profileBannerField, {
          profileBannerField: uri.toString(),
        });
        await _client.deleteProfileField(
          _client.userID!,
          profileBackgroundColorField,
        );
      },
    );

    if (!mounted) return;
    await _reloadProfileFields();
  }

  Future<void> _removeBanner() async {
    if (!_isSelf) return;

    await showFutureLoadingDialog(
      context: context,
      future: () =>
          _client.deleteProfileField(_client.userID!, profileBannerField),
    );

    if (!mounted) return;
    await _reloadProfileFields();
  }

  Future<void> _showBannerMenu() async {
    if (!_isSelf) return;

    final action = await showModalActionPopup<_BannerAction>(
      context: context,
      title: L10n.of(context).profileBanner,
      cancelLabel: L10n.of(context).cancel,
      useRootNavigator: false,
      actions: [
        AdaptiveModalAction(
          label: L10n.of(context).profilePickImage,
          icon: const Icon(Icons.image_outlined),
          value: _BannerAction.pickImage,
          isDefaultAction: true,
        ),
        if (_profileFields.bannerMxc != null)
          AdaptiveModalAction(
            label: L10n.of(context).remove,
            icon: const Icon(Icons.delete_outline),
            value: _BannerAction.remove,
            isDestructive: true,
          ),
      ],
    );

    if (action == null) return;

    switch (action) {
      case _BannerAction.pickImage:
        await _pickBannerImage();
        return;
      case _BannerAction.remove:
        await _removeBanner();
        return;
    }
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
    final borderColor = Color.lerp(foreground, background, 0.68) ?? foreground;
    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor, width: 1.2),
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
    final maxDialogWidth = (screenSize.width - 24).clamp(320.0, 760.0);
    final targetDialogWidth = (screenSize.width * 0.35).clamp(320.0, 620.0);
    final dialogWidth = targetDialogWidth > maxDialogWidth
        ? maxDialogWidth
        : targetDialogWidth;

    final maxDialogHeight = (screenSize.height - 24).clamp(360.0, 1200.0);
    final targetDialogHeight = (screenSize.height * 0.8).clamp(420.0, 980.0);
    final dialogHeight = targetDialogHeight > maxDialogHeight
        ? maxDialogHeight
        : targetDialogHeight;

    final scale = (dialogWidth / 460).clamp(1.0, 1.35);
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
          final bannerUri = _profileFields.bannerMxc;
          final hasBanner = bannerUri != null;
          final headerColor = hasBanner
              ? _bannerStyle.representativeBackground
              : _profileFields.backgroundColor ??
                    theme.colorScheme.surfaceContainer;
          final headerOnColor = hasBanner
              ? _bannerStyle.foregroundColor
              : ThemeData.estimateBrightnessForColor(headerColor) ==
                    Brightness.dark
              ? Colors.white
              : Colors.black;
          final namePillStyle = _resolveNamePillStyle();
          final controlSurfaceStyle = _resolveControlSurfaceStyle();
          final pillBackground = namePillStyle.background;
          final statusForeground = _resolveMonochromeContrastForeground(
            pillBackground,
            targetContrast: 4.2,
          );
          final warningBackground = theme.colorScheme.errorContainer;
          final warningForeground = _resolveMonochromeContrastForeground(
            warningBackground,
            targetContrast: 4.2,
          );
          final actionForeground = controlSurfaceStyle.foreground;
          final actionBackground = controlSurfaceStyle.background;
          final actionBorder = controlSurfaceStyle.border;
          final bannerOverlayColor = _bannerStyle.overlayColor.withAlpha(
            _bannerStyle.overlayAlpha,
          );

          final statusText = _statusText(presence);
          final emojiStatusUri = _profileFields.emojiStatusMxc;

          return SizedBox(
            width: dialogWidth,
            height: dialogHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: headerColor),
                if (hasBanner)
                  MxcImage(
                    uri: bannerUri,
                    width: dialogWidth,
                    height: dialogHeight,
                    fit: BoxFit.cover,
                    isThumbnail: true,
                  ),
                if (hasBanner) ColoredBox(color: bannerOverlayColor),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
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
                                      tooltip:
                                          '${L10n.of(context).profileBackgroundColor} / ${L10n.of(context).profileBanner}',
                                      foreground: actionForeground,
                                      background: actionBackground,
                                      border: actionBorder,
                                      onTap: _showBackgroundAppearanceChooser,
                                      icon: Stack(
                                        clipBehavior: Clip.none,
                                        alignment: Alignment.center,
                                        children: [
                                          Icon(
                                            _profileFields.bannerMxc == null
                                                ? Icons.wallpaper_outlined
                                                : Icons.wallpaper,
                                            size: 18,
                                          ),
                                          if (_profileFields.bannerMxc ==
                                                  null &&
                                              _profileFields.backgroundColor !=
                                                  null)
                                            Positioned(
                                              right: -1,
                                              bottom: -1,
                                              child: Container(
                                                width: 8,
                                                height: 8,
                                                decoration: BoxDecoration(
                                                  color: _profileFields
                                                      .backgroundColor,
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: actionForeground,
                                                    width: 0.8,
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  if (_isSelf ||
                                      _profileFields.emojiStatusMxc != null)
                                    _HeaderIconButton(
                                      tooltip: L10n.of(
                                        context,
                                      ).profileEmojiStatus,
                                      foreground: actionForeground,
                                      background: actionBackground,
                                      border: actionBorder,
                                      onTap: _isSelf
                                          ? _showEmojiStatusMenu
                                          : null,
                                      icon:
                                          _profileFields.emojiStatusMxc == null
                                          ? const Icon(
                                              Icons.add_reaction_outlined,
                                              size: 18,
                                            )
                                          : ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                              child: MxcImage(
                                                uri: _profileFields
                                                    .emojiStatusMxc,
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
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
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
                            presenceTooltipBuilder: (_, dotPresence) =>
                                _presenceDotTooltipText(dotPresence),
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
                                color: namePillStyle.border,
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
                                      color: namePillStyle.fallbackTextColor,
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
                          if (statusText != null) ...[
                            SizedBox(height: 10 * scale),
                            _buildStatusPill(
                              text: statusText,
                              icon: Icons.circle,
                              background: pillBackground,
                              foreground: statusForeground,
                            ),
                          ],
                          if (widget.noProfileWarning) ...[
                            SizedBox(height: 10 * scale),
                            _buildStatusPill(
                              text: L10n.of(context).profileNotFound,
                              background: warningBackground,
                              foreground: warningForeground,
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
                                foreground: actionForeground,
                                background: actionBackground,
                                border: actionBorder,
                                onTap: _isSelf ? null : _openMessage,
                              ),
                              _ProfileActionButton(
                                label: L10n.of(context).profileActionMute,
                                icon: Icons.notifications_off_outlined,
                                foreground: actionForeground,
                                background: actionBackground,
                                border: actionBorder,
                                onTap: _isSelf ? null : _toggleMute,
                              ),
                              _ProfileActionButton(
                                label: L10n.of(context).profileActionCall,
                                icon: Icons.call_outlined,
                                foreground: actionForeground,
                                background: actionBackground,
                                border: actionBorder,
                                onTap: _isSelf ? null : _callAction,
                              ),
                              _ProfileActionButton(
                                label: L10n.of(context).more.toLowerCase(),
                                icon: Icons.more_horiz,
                                foreground: actionForeground,
                                background: actionBackground,
                                border: actionBorder,
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
  final Color border;
  final VoidCallback? onTap;

  const _ProfileActionButton({
    required this.icon,
    required this.label,
    required this.foreground,
    required this.background,
    required this.border,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final radius = BorderRadius.circular(AppConfig.borderRadius / 2);
    final effectiveForeground = enabled
        ? foreground
        : Color.lerp(foreground, background, 0.45) ?? foreground;
    return Expanded(
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: border, width: 1),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: effectiveForeground),
                const SizedBox(height: 5),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: effectiveForeground, fontSize: 12.5),
                ),
              ],
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
  final Color border;
  final VoidCallback? onTap;

  const _HeaderIconButton({
    required this.tooltip,
    required this.icon,
    required this.foreground,
    required this.background,
    required this.border,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveForeground = onTap == null
        ? Color.lerp(foreground, background, 0.4) ?? foreground
        : foreground;
    final content = IconTheme.merge(
      data: IconThemeData(color: effectiveForeground),
      child: SizedBox(width: 36, height: 36, child: Center(child: icon)),
    );
    final button = Material(
      color: background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: border, width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: content,
      ),
    );
    return Tooltip(message: tooltip, child: button);
  }
}

class _BackgroundColorPickerDialog extends StatefulWidget {
  final Color initialColor;

  const _BackgroundColorPickerDialog({required this.initialColor});

  @override
  State<_BackgroundColorPickerDialog> createState() =>
      _BackgroundColorPickerDialogState();
}

class _BackgroundColorPickerDialogState
    extends State<_BackgroundColorPickerDialog> {
  static const _pickerSize = 220.0;

  late double _hue;
  late double _saturation;
  late double _value;

  @override
  void initState() {
    super.initState();
    final hsv = HSVColor.fromColor(widget.initialColor.withAlpha(255));
    _hue = hsv.hue;
    _saturation = hsv.saturation;
    _value = hsv.value;
  }

  Color get _currentColor =>
      HSVColor.fromAHSV(1, _hue, _saturation, _value).toColor();

  void _updateColorFromOffset(Offset localPosition, double size) {
    if (size <= 0) return;
    final dx = localPosition.dx.clamp(0.0, size);
    final dy = localPosition.dy.clamp(0.0, size);
    setState(() {
      _saturation = dx / size;
      _value = 1 - (dy / size);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hueColor = HSVColor.fromAHSV(1, _hue, 1, 1).toColor();
    const pickerSize = _pickerSize;

    return AlertDialog.adaptive(
      title: Text(L10n.of(context).profileBackgroundColor),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.center,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _currentColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: theme.colorScheme.outline),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.center,
              child: GestureDetector(
                onTapDown: (details) =>
                    _updateColorFromOffset(details.localPosition, pickerSize),
                onPanDown: (details) =>
                    _updateColorFromOffset(details.localPosition, pickerSize),
                onPanUpdate: (details) =>
                    _updateColorFromOffset(details.localPosition, pickerSize),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: pickerSize,
                    height: pickerSize,
                    child: Stack(
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.white, hueColor],
                            ),
                          ),
                          child: const SizedBox.expand(),
                        ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black],
                            ),
                          ),
                          child: SizedBox.expand(),
                        ),
                        Positioned(
                          left:
                              (_saturation * pickerSize).clamp(
                                0.0,
                                pickerSize,
                              ) -
                              8,
                          top:
                              ((1 - _value) * pickerSize).clamp(
                                0.0,
                                pickerSize,
                              ) -
                              8,
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: const [
                                BoxShadow(color: Colors.black26, blurRadius: 4),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Slider(
              min: 0,
              max: 360,
              value: _hue,
              onChanged: (value) => setState(() => _hue = value),
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
        TextButton(
          onPressed: () => Navigator.of(
            context,
          ).pop(_BackgroundColorChoice(value: _currentColor.toARGB32())),
          child: Text(L10n.of(context).ok),
        ),
      ],
    );
  }
}

class _BackgroundColorChoice {
  final int? value;
  final bool remove;

  const _BackgroundColorChoice({this.value, this.remove = false});
}

enum _UserMoreAction { copy, share, report, block }

enum _BackgroundAppearanceAction { backgroundColor, banner }

enum _BannerAction { pickImage, remove }

enum _EmojiStatusAction { pickImage, remove }

class _NamePillStyle {
  final Color background;
  final Color border;
  final Color fallbackTextColor;

  const _NamePillStyle({
    required this.background,
    required this.border,
    required this.fallbackTextColor,
  });
}

class _ControlSurfaceStyle {
  final Color foreground;
  final Color background;
  final Color border;

  const _ControlSurfaceStyle({
    required this.foreground,
    required this.background,
    required this.border,
  });
}
