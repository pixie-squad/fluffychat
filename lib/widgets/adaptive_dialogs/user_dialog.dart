import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/client_download_content_extension.dart';
import 'package:fluffychat/utils/client_manager.dart';
import 'package:fluffychat/utils/custom_emoji_catalog.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/file_selector.dart';
import 'package:fluffychat/utils/fluffy_share.dart';
import 'package:fluffychat/utils/name_gradients.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/profile_banner_style.dart';
import 'package:fluffychat/utils/profile_card_fields.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/custom_emoji_media.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:fluffychat/widgets/emoji_status_sticker_picker.dart';
import 'package:fluffychat/widgets/presence_builder.dart';

import '../../utils/url_launcher.dart';
import '../future_loading_dialog.dart';
import '../matrix.dart';
import '../image_crop_dialog.dart';
import '../mxc_image_viewer.dart';

enum UserDialogMode { view, edit }

class UserDialog extends StatefulWidget {
  static Future<void> show({
    required BuildContext context,
    required Profile profile,
    bool noProfileWarning = false,
  }) => showAdaptiveDialog(
    context: context,
    barrierDismissible: true,
    builder: (context) => UserDialog(
      profile,
      noProfileWarning: noProfileWarning,
      mode: UserDialogMode.view,
    ),
  );

  static Future<void> showEdit({
    required BuildContext context,
    required Profile profile,
    bool noProfileWarning = false,
  }) => showAdaptiveDialog(
    context: context,
    barrierDismissible: true,
    builder: (context) => UserDialog(
      profile,
      noProfileWarning: noProfileWarning,
      mode: UserDialogMode.edit,
    ),
  );

  final Profile profile;
  final bool noProfileWarning;
  final UserDialogMode mode;

  const UserDialog(
    this.profile, {
    this.noProfileWarning = false,
    this.mode = UserDialogMode.view,
    super.key,
  });

  @override
  State<UserDialog> createState() => _UserDialogState();
}

class _UserDialogState extends State<UserDialog> {
  late Profile _profile;
  ProfileCardFields _profileFields = const ProfileCardFields();
  bool _fieldsLoading = false;
  bool _copiedMxid = false;
  ProfileBannerStyle _bannerStyle = ProfileBannerStyle.fallback;
  int _bannerStyleRequestId = 0;
  int _displayNameStyleVersion = 0;

  Client get _client => Matrix.of(context).client;
  bool get _isEditMode => widget.mode == UserDialogMode.edit;

  bool get _isSelf => _profile.userId == _client.userID;

  String get _displayname =>
      _profile.displayName ??
      _profile.userId.localpart ??
      L10n.of(context).user;

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
    _reloadProfileFields();
  }

  @override
  void didUpdateWidget(covariant UserDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.userId != widget.profile.userId) {
      _profile = widget.profile;
      _reloadProfileFields();
    }
  }

  Future<void> _reloadProfileFields() async {
    setState(() => _fieldsLoading = true);
    final fields = await loadProfileCardFields(_client, _profile.userId);
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

  Future<void> _reloadSelfProfile() async {
    if (!_isSelf) return;
    try {
      final profile = await _client.fetchOwnProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
      });
    } catch (_) {}
  }

  Future<void> _openEditProfile() async {
    if (!_isSelf || _isEditMode) return;
    await UserDialog.showEdit(
      context: context,
      profile: _profile,
      noProfileWarning: widget.noProfileWarning,
    );
    if (!mounted) return;
    await _reloadSelfProfile();
    await _reloadProfileFields();
    if (!mounted) return;
    setState(() {
      _displayNameStyleVersion++;
    });
  }

  Future<void> _setDisplaynameAction() async {
    if (!_isSelf || !_isEditMode) return;
    final input = await showTextInputDialog(
      useRootNavigator: false,
      context: context,
      title: L10n.of(context).editDisplayname,
      okLabel: L10n.of(context).ok,
      cancelLabel: L10n.of(context).cancel,
      initialText: _displayname,
    );
    if (input == null) return;

    final result = await showFutureLoadingDialog(
      context: context,
      future: () => _client.setProfileField(_client.userID!, 'displayname', {
        'displayname': input,
      }),
    );
    if (result.error != null) return;

    await _reloadSelfProfile();
  }

  Future<void> _setStatusAction({required String? initialText}) async {
    if (!_isSelf || !_isEditMode) return;
    final input = await showTextInputDialog(
      useRootNavigator: false,
      context: context,
      title: L10n.of(context).setStatus,
      message: L10n.of(context).leaveEmptyToClearStatus,
      okLabel: L10n.of(context).ok,
      cancelLabel: L10n.of(context).cancel,
      hintText: L10n.of(context).statusExampleMessage,
      maxLines: 6,
      minLines: 1,
      maxLength: 255,
      initialText: initialText,
    );
    if (input == null) return;
    await showFutureLoadingDialog(
      context: context,
      future: () => _client.setPresence(
        _client.userID!,
        PresenceType.online,
        statusMsg: input,
      ),
    );
  }

  Future<void> _setBioAction() async {
    if (!_isSelf || !_isEditMode) return;
    final input = await showTextInputDialog(
      useRootNavigator: false,
      context: context,
      title: L10n.of(context).profileBio,
      okLabel: L10n.of(context).ok,
      cancelLabel: L10n.of(context).cancel,
      maxLines: 6,
      minLines: 1,
      maxLength: 320,
      initialText: _profileFields.bio,
    );
    if (input == null) return;
    final trimmed = input.trim();
    final result = await showFutureLoadingDialog(
      context: context,
      future: () async {
        if (trimmed.isEmpty) {
          await _client.deleteProfileField(_client.userID!, profileBioField);
          return;
        }
        await _client.setProfileField(_client.userID!, profileBioField, {
          profileBioField: input,
        });
      },
    );
    if (result.error != null || !mounted) return;
    await _reloadProfileFields();
  }

  Room? _resolveFeaturedChannelRoom(String roomIdOrAlias) {
    if (!roomIdOrAlias.isValidMatrixId) return null;
    if (roomIdOrAlias.sigil == '#') {
      return _client.getRoomByAlias(roomIdOrAlias);
    }
    if (roomIdOrAlias.sigil == '!') {
      return _client.getRoomById(roomIdOrAlias);
    }
    return null;
  }

  FeaturedChannelProfileField _featuredChannelSnapshotFromRoom(
    Room room, {
    required String roomId,
  }) {
    final displayName = room.getLocalizedDisplayname().trim();
    final topic = room.topic.trim();
    final avatar = room.avatar;
    return FeaturedChannelProfileField(
      roomId: roomId,
      title: displayName.isEmpty ? null : displayName,
      subtitle: topic.isEmpty ? null : topic,
      avatarUrl: avatar?.scheme == 'mxc' ? avatar : null,
    );
  }

  FeaturedChannelProfileField? _featuredChannelForDisplay() {
    final featured = _profileFields.featuredChannel;
    if (featured == null) return null;
    final room = _resolveFeaturedChannelRoom(featured.roomId);
    if (room == null) return featured;
    final fallback = _featuredChannelSnapshotFromRoom(
      room,
      roomId: featured.roomId,
    );
    return FeaturedChannelProfileField(
      roomId: featured.roomId,
      title: featured.title ?? fallback.title,
      subtitle: featured.subtitle ?? fallback.subtitle,
      avatarUrl: featured.avatarUrl ?? fallback.avatarUrl,
    );
  }

  List<Room> _joinedPublicFeaturedChannelCandidates() {
    final candidates = _client.rooms.where((room) {
      if (room.membership != Membership.join) return false;
      if (room.isSpace || room.isDirectChat) return false;
      return room.joinRules == JoinRules.public ||
          room.canonicalAlias.isNotEmpty;
    }).toList();
    candidates.sort((a, b) {
      final aName = a.getLocalizedDisplayname().toLowerCase();
      final bName = b.getLocalizedDisplayname().toLowerCase();
      final byName = aName.compareTo(bName);
      if (byName != 0) return byName;
      return a.id.compareTo(b.id);
    });
    return candidates;
  }

  Future<void> _saveFeaturedChannel(
    FeaturedChannelProfileField featured,
  ) async {
    if (!_isSelf || !_isEditMode) return;
    final result = await showFutureLoadingDialog(
      context: context,
      future: () => _client.setProfileField(
        _client.userID!,
        profileFeaturedChannelField,
        {profileFeaturedChannelField: featured.toJson()},
      ),
    );
    if (result.error != null || !mounted) return;
    await _reloadProfileFields();
  }

  Future<void> _removeFeaturedChannel() async {
    if (!_isSelf || !_isEditMode) return;
    final result = await showFutureLoadingDialog(
      context: context,
      future: () => _client.deleteProfileField(
        _client.userID!,
        profileFeaturedChannelField,
      ),
    );
    if (result.error != null || !mounted) return;
    await _reloadProfileFields();
  }

  Future<void> _pickFeaturedChannelFromJoined() async {
    if (!_isSelf || !_isEditMode) return;
    final channels = _joinedPublicFeaturedChannelCandidates();
    if (channels.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No joined public channels found.')),
      );
      return;
    }

    final selectedRoom = await showModalActionPopup<Room>(
      context: context,
      title: L10n.of(context).profileFeaturedChannel,
      message: 'Joined public channels',
      cancelLabel: L10n.of(context).cancel,
      useRootNavigator: false,
      actions: channels.map((room) {
        final displayName = room.getLocalizedDisplayname().trim();
        return AdaptiveModalAction<Room>(
          label: displayName.isEmpty ? room.id : displayName,
          value: room,
          icon: const Icon(Icons.tag_outlined),
        );
      }).toList(),
    );
    if (selectedRoom == null) return;
    final roomId = selectedRoom.canonicalAlias.isNotEmpty
        ? selectedRoom.canonicalAlias
        : selectedRoom.id;
    await _saveFeaturedChannel(
      _featuredChannelSnapshotFromRoom(selectedRoom, roomId: roomId),
    );
  }

  Future<void> _setFeaturedChannelManual() async {
    if (!_isSelf || !_isEditMode) return;
    final input = await showTextInputDialog(
      useRootNavigator: false,
      context: context,
      title: L10n.of(context).profileFeaturedChannel,
      message: 'Use #alias:server, !room:server, or a matrix.to link.',
      okLabel: L10n.of(context).ok,
      cancelLabel: L10n.of(context).cancel,
      hintText: '#channel:example.org',
      initialText: _profileFields.featuredChannel?.roomId,
      autocorrect: false,
      validator: (value) => normalizeFeaturedChannelIdentifier(value) == null
          ? L10n.of(context).invalidInput
          : null,
    );
    if (input == null) return;
    final normalized = normalizeFeaturedChannelIdentifier(input);
    if (normalized == null) return;

    final room = _resolveFeaturedChannelRoom(normalized);
    final payload = room == null
        ? FeaturedChannelProfileField(roomId: normalized)
        : _featuredChannelSnapshotFromRoom(room, roomId: normalized);
    await _saveFeaturedChannel(payload);
  }

  Future<void> _showFeaturedChannelMenu() async {
    if (!_isSelf || !_isEditMode) return;
    final action = await showModalActionPopup<_FeaturedChannelAction>(
      context: context,
      title: L10n.of(context).profileFeaturedChannel,
      cancelLabel: L10n.of(context).cancel,
      useRootNavigator: false,
      actions: [
        AdaptiveModalAction(
          label: 'Choose from joined channels',
          icon: const Icon(Icons.list_alt_outlined),
          value: _FeaturedChannelAction.pickJoined,
          isDefaultAction: true,
        ),
        AdaptiveModalAction(
          label: 'Enter room alias or ID',
          icon: const Icon(Icons.edit_outlined),
          value: _FeaturedChannelAction.manual,
        ),
        if (_profileFields.featuredChannel != null)
          AdaptiveModalAction(
            label: L10n.of(context).remove,
            icon: const Icon(Icons.delete_outline),
            value: _FeaturedChannelAction.remove,
            isDestructive: true,
          ),
      ],
    );
    if (action == null) return;
    switch (action) {
      case _FeaturedChannelAction.pickJoined:
        await _pickFeaturedChannelFromJoined();
        return;
      case _FeaturedChannelAction.manual:
        await _setFeaturedChannelManual();
        return;
      case _FeaturedChannelAction.remove:
        await _removeFeaturedChannel();
        return;
    }
  }

  Future<void> _openFeaturedChannel() async {
    final featured = _profileFields.featuredChannel;
    if (featured == null) return;
    final normalized = normalizeFeaturedChannelIdentifier(featured.roomId);
    if (normalized == null) return;
    await UrlLauncher(
      context,
      'https://matrix.to/#/${Uri.encodeComponent(normalized)}',
    ).launchUrl();
    if (!mounted) return;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  Future<void> _setNameGradientAction() async {
    if (!_isSelf || !_isEditMode) return;
    final picked = await showGradientPicker(context);
    if (picked == null) return;
    if (!mounted) return;

    final colors = picked.colors.isEmpty
        ? null
        : picked.colors.map((c) => c.toARGB32()).toList();
    final value = colors == null
        ? null
        : picked.animated
        ? {'c': colors, 'a': true}
        : colors;
    final result = await showFutureLoadingDialog(
      context: context,
      future: () =>
          _client.setProfileField(_client.userID!, nameGradientField, {
            nameGradientField: value,
            if (value != null && picked.animated)
              nameGradientAnimatedField: true,
          }),
    );

    if (result.error != null || !mounted) return;
    gradientCache.invalidate(_client.userID!);
    setState(() {
      _displayNameStyleVersion++;
    });
  }

  Future<void> _setAvatarAction() async {
    if (!_isSelf || !_isEditMode) return;
    final actions = <AdaptiveModalAction<_ProfileAvatarAction>>[
      if (PlatformInfos.isMobile)
        AdaptiveModalAction(
          value: _ProfileAvatarAction.camera,
          label: L10n.of(context).openCamera,
          isDefaultAction: true,
          icon: const Icon(Icons.camera_alt_outlined),
        ),
      AdaptiveModalAction(
        value: _ProfileAvatarAction.file,
        label: L10n.of(context).openGallery,
        icon: const Icon(Icons.photo_outlined),
      ),
      if (_profile.avatarUrl != null)
        AdaptiveModalAction(
          value: _ProfileAvatarAction.remove,
          label: L10n.of(context).removeYourAvatar,
          isDestructive: true,
          icon: const Icon(Icons.delete_outlined),
        ),
    ];

    final action = actions.length == 1
        ? actions.single.value
        : await showModalActionPopup<_ProfileAvatarAction>(
            context: context,
            title: L10n.of(context).changeYourAvatar,
            cancelLabel: L10n.of(context).cancel,
            actions: actions,
            useRootNavigator: false,
          );
    if (action == null) return;

    if (action == _ProfileAvatarAction.remove) {
      final result = await showFutureLoadingDialog(
        context: context,
        future: () => _client.setAvatar(null),
      );
      if (result.error != null) return;
      await _reloadSelfProfile();
      return;
    }

    Uint8List rawBytes;
    if (PlatformInfos.isMobile) {
      final result = await ImagePicker().pickImage(
        source: action == _ProfileAvatarAction.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        imageQuality: 50,
      );
      if (result == null) return;
      rawBytes = await result.readAsBytes();
    } else {
      final result = await selectFiles(context, type: FileType.image);
      if (result.isEmpty) return;
      rawBytes = await result.first.readAsBytes();
    }

    if (!mounted) return;
    final croppedBytes = await showImageCropDialog(
      context: context,
      imageBytes: rawBytes,
    );
    if (croppedBytes == null || !mounted) return;

    final file = MatrixFile(bytes: croppedBytes, name: 'avatar.png');
    final success = await showFutureLoadingDialog(
      context: context,
      future: () => _client.setAvatar(file),
    );
    if (success.error != null) return;
    await _reloadSelfProfile();
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
    await Clipboard.setData(ClipboardData(text: _profile.userId));
    if (!mounted) return;
    setState(() => _copiedMxid = true);
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copiedMxid = false);
    });
  }

  Future<Room> _resolveDirectRoom() async {
    final client = _client;
    final existingDirectRoomId = client.getDirectChatFromUserId(
      _profile.userId,
    );
    final roomId =
        existingDirectRoomId ?? await client.startDirectChat(_profile.userId);

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
      future: () => _client.startDirectChat(_profile.userId),
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
      future: () => _client.reportUser(_profile.userId, reason),
    );
  }

  void _openBlockScreen() {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.go('/rooms/settings/security/ignorelist', extra: _profile.userId);
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
          'https://matrix.to/#/${_profile.userId}',
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

  Future<void> _pickStickerAsEmojiStatus() async {
    if (!_isSelf) return;

    ImagePackImageContent? selected;

    await showDialog(
      context: context,
      useRootNavigator: false,
      builder: (context) => Dialog(
        clipBehavior: Clip.hardEdge,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
          child: EmojiStatusStickerPicker(
            client: _client,
            onSelected: (sticker) {
              selected = sticker;
              Navigator.of(context).pop();
            },
          ),
        ),
      ),
    );

    if (selected == null || !mounted) return;

    await showFutureLoadingDialog(
      context: context,
      future: () async {
        await _client.setProfileField(
          _client.userID!,
          profileEmojiStatusField,
          {profileEmojiStatusField: selected!.url.toString()},
        );
        profileEmojiStatusCache.invalidate(_client.userID!);
      },
    );

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
          label: L10n.of(context).pickFromStickers,
          icon: const Icon(Icons.emoji_emotions_outlined),
          value: _EmojiStatusAction.pickSticker,
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
      case _EmojiStatusAction.pickSticker:
        await _pickStickerAsEmojiStatus();
        return;
      case _EmojiStatusAction.remove:
        await _removeEmojiStatus();
        return;
    }
  }

  Widget _buildEmojiStatusVisual(
    Uri uri, {
    required double size,
    required BoxFit fit,
  }) {
    final entry = CustomEmojiCatalog.fromClient(_client).resolveByMxc(uri);
    if (entry == null) {
      return MxcImage(
        uri: uri,
        width: size,
        height: size,
        fit: fit,
        isThumbnail: false,
      );
    }
    return CustomEmojiMedia(
      client: _client,
      fallbackMxc: uri,
      metadata: entry.metadata,
      fallbackEmoji: entry.primaryFallbackEmoji,
      width: size,
      height: size,
      fit: fit,
      isThumbnail: false,
    );
  }

  Widget _buildStatusPill({
    required String text,
    required Color background,
    required Color foreground,
    IconData? icon,
  }) {
    final borderColor = Color.lerp(foreground, background, 0.68) ?? foreground;
    final textStyle = TextStyle(
      color: foreground,
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
    );
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
            child: _PillMarqueeText(text: text, textStyle: textStyle),
          ),
        ],
      ),
    );
  }

  Widget _buildBioSection(BuildContext context) {
    final bio = _profileFields.bio;
    final theme = Theme.of(context);
    final isEditable = _isSelf && _isEditMode;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                L10n.of(context).profileBio,
                style: theme.textTheme.labelLarge,
              ),
            ),
            if (isEditable)
              Icon(
                Icons.edit_outlined,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
          ],
        ),
        if (bio == null || isEditable)
          Text(
            bio ?? '—',
            style: theme.textTheme.bodyMedium,
            maxLines: isEditable ? 4 : null,
            overflow: isEditable ? TextOverflow.ellipsis : null,
          )
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
    );

    final container = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: theme.colorScheme.surfaceContainerLow,
      ),
      child: content,
    );

    if (!isEditable) return container;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _setBioAction,
        child: container,
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
                  _profile.userId,
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

  Widget _buildNameGradientSection(BuildContext context) {
    if (!_isSelf || !_isEditMode) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _setNameGradientAction,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.gradient_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Name gradient', style: theme.textTheme.titleSmall),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeaturedChannelSection(BuildContext context) {
    final isEditable = _isSelf && _isEditMode;
    final featured = _featuredChannelForDisplay();
    final hasFeatured = featured != null;
    if (!hasFeatured && !isEditable) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final linkedRoom = hasFeatured
        ? _resolveFeaturedChannelRoom(featured.roomId)
        : null;
    final joinedMemberCount = linkedRoom == null
        ? 0
        : (linkedRoom.summary.mJoinedMemberCount ?? 0) +
              (linkedRoom.summary.mInvitedMemberCount ?? 0);
    final memberCountText = joinedMemberCount > 0
        ? L10n.of(context).countParticipants(joinedMemberCount)
        : null;
    final title = featured?.title ?? featured?.roomId ?? '—';
    final subtitle = featured?.subtitle;
    final content = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: theme.colorScheme.surfaceContainerLow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          Text(
            L10n.of(context).profileFeaturedChannel,
            style: theme.textTheme.labelLarge,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              spacing: 12,
              children: [
                Avatar(mxContent: featured?.avatarUrl, name: title, size: 52),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      if (memberCountText != null)
                        Text(
                          memberCountText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        )
                      else if (!hasFeatured && isEditable)
                        Text(
                          'Tap to set a featured channel',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(
                  isEditable && !hasFeatured
                      ? Icons.add_circle_outline
                      : Icons.chevron_right,
                  size: 22,
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final onTap = isEditable
        ? _showFeaturedChannelMenu
        : hasFeatured
        ? _openFeaturedChannel
        : null;
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: content,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final avatar = _profile.avatarUrl;
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
    final headerBottomPadding = (_isEditMode ? 22.0 : 12.0) * scale;
    final detailsTopPadding = (_isEditMode ? 18.0 : 10.0) * scale;

    return AlertDialog.adaptive(
      contentPadding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      content: PresenceBuilder(
        userId: _profile.userId,
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
          final statusPlaceholder =
              _isSelf && _isEditMode && statusText == null;
          final displayedStatusText =
              statusText ??
              (statusPlaceholder
                  ? L10n.of(context).statusExampleMessage
                  : null);
          final displayedStatusForeground = statusPlaceholder
              ? statusForeground.withAlpha(180)
              : statusForeground;
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
                    key: ValueKey(bannerUri),
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
                                  if (_isSelf && _isEditMode)
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
                                  if ((_isSelf && _isEditMode) ||
                                      (!_isSelf &&
                                          _profileFields.emojiStatusMxc !=
                                              null))
                                    _HeaderIconButton(
                                      tooltip: L10n.of(
                                        context,
                                      ).profileEmojiStatus,
                                      foreground: actionForeground,
                                      background: actionBackground,
                                      border: actionBorder,
                                      onTap: _isSelf && _isEditMode
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
                                              child: _buildEmojiStatusVisual(
                                                _profileFields.emojiStatusMxc!,
                                                size: 20,
                                                fit: BoxFit.cover,
                                              ),
                                            ),
                                    ),
                                  if (_isSelf && !_isEditMode)
                                    _HeaderIconButton(
                                      tooltip: L10n.of(context).edit,
                                      foreground: actionForeground,
                                      background: actionBackground,
                                      border: actionBorder,
                                      onTap: _openEditProfile,
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 18,
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
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Avatar(
                                mxContent: avatar,
                                name: _displayname,
                                size: avatarSize,
                                presenceUserId: _profile.userId,
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
                              if (_isSelf && _isEditMode)
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: SizedBox.square(
                                    dimension: 34,
                                    child: FloatingActionButton.small(
                                      heroTag: null,
                                      elevation: 2,
                                      onPressed: _setAvatarAction,
                                      child: const Icon(
                                        Icons.camera_alt_outlined,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          SizedBox(height: 14 * scale),
                          Material(
                            color: pillBackground,
                            borderRadius: BorderRadius.circular(999),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(999),
                              onTap: _isSelf && _isEditMode
                                  ? _setDisplaynameAction
                                  : null,
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 14 * scale,
                                  vertical: 9 * scale,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.transparent,
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
                                        key: ValueKey(
                                          '${_profile.userId}:$_displayNameStyleVersion',
                                        ),
                                        userId: _profile.userId,
                                        text: _displayname,
                                        client: _client,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color:
                                              namePillStyle.fallbackTextColor,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16 * scale,
                                        ),
                                      ),
                                    ),
                                    if (emojiStatusUri != null) ...[
                                      SizedBox(width: 6 * scale),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        child: _buildEmojiStatusVisual(
                                          emojiStatusUri,
                                          size: 16 * scale,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ],
                                    if (_isSelf && _isEditMode) ...[
                                      SizedBox(width: 6 * scale),
                                      Icon(
                                        Icons.edit_outlined,
                                        size: 16 * scale,
                                        color: namePillStyle.fallbackTextColor
                                            .withAlpha(200),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (displayedStatusText != null) ...[
                            SizedBox(height: 10 * scale),
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(999),
                                onTap: _isSelf && _isEditMode
                                    ? () => _setStatusAction(
                                        initialText: statusText ?? '',
                                      )
                                    : null,
                                child: _buildStatusPill(
                                  text: displayedStatusText,
                                  icon: _isSelf && _isEditMode
                                      ? Icons.edit_outlined
                                      : Icons.circle,
                                  background: pillBackground,
                                  foreground: displayedStatusForeground,
                                ),
                              ),
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
                          if (!_isEditMode) ...[
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
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          18 * scale,
                          detailsTopPadding,
                          18 * scale,
                          18 * scale,
                        ),
                        child: Column(
                          spacing: 12 * scale,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_isSelf && _isEditMode)
                              _buildNameGradientSection(context),
                            if ((_isSelf && _isEditMode) ||
                                _profileFields.featuredChannel != null)
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

class _PillMarqueeText extends StatefulWidget {
  final String text;
  final TextStyle textStyle;

  const _PillMarqueeText({required this.text, required this.textStyle});

  @override
  State<_PillMarqueeText> createState() => _PillMarqueeTextState();
}

class _PillMarqueeTextState extends State<_PillMarqueeText>
    with SingleTickerProviderStateMixin {
  static const _gap = 24.0;
  static const _pixelsPerSecond = 24.0;

  late final AnimationController _controller;
  double? _lastDistance;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _start(double distance) {
    if (_lastDistance == distance && _controller.isAnimating) return;
    _lastDistance = distance;
    final millis = math.max(1, (distance / _pixelsPerSecond * 1000).round());
    _controller
      ..duration = Duration(milliseconds: millis)
      ..repeat();
  }

  @override
  Widget build(BuildContext context) {
    final singleLineText = widget.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (singleLineText.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final textPainter = TextPainter(
          text: TextSpan(text: singleLineText, style: widget.textStyle),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout(maxWidth: double.infinity);
        final textWidth = textPainter.width;

        if (maxWidth.isInfinite || textWidth <= maxWidth) {
          _lastDistance = null;
          if (_controller.isAnimating) _controller.stop();
          return Text(
            singleLineText,
            maxLines: 1,
            softWrap: false,
            style: widget.textStyle,
          );
        }

        final distance = textWidth + _gap;
        _start(distance);

        return Semantics(
          label: singleLineText,
          child: SizedBox(
            width: maxWidth,
            child: ClipRect(
              child: ExcludeSemantics(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(-distance * _controller.value, 0),
                      child: child,
                    );
                  },
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    fit: OverflowBoxFit.deferToChild,
                    minWidth: 0,
                    maxWidth: double.infinity,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          singleLineText,
                          maxLines: 1,
                          softWrap: false,
                          style: widget.textStyle,
                        ),
                        const SizedBox(width: _gap),
                        Text(
                          singleLineText,
                          maxLines: 1,
                          softWrap: false,
                          style: widget.textStyle,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
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

enum _EmojiStatusAction { pickImage, pickSticker, remove }

enum _ProfileAvatarAction { camera, file, remove }

enum _FeaturedChannelAction { pickJoined, manual, remove }

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
