import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:collection/collection.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:matrix/matrix.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat_view.dart';
import 'package:fluffychat/pages/chat/event_info_dialog.dart';
import 'package:fluffychat/pages/chat/start_poll_bottom_sheet.dart';
import 'package:fluffychat/pages/chat_details/chat_details.dart';
import 'package:fluffychat/utils/adaptive_bottom_sheet.dart';
import 'package:fluffychat/utils/custom_emoji_message_builder.dart';
import 'package:fluffychat/utils/custom_emoji_metadata.dart';
import 'package:fluffychat/utils/error_reporter.dart';
import 'package:fluffychat/utils/file_selector.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/event_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_file_extension.dart';
import 'package:fluffychat/utils/other_party_can_receive.dart';
import 'package:fluffychat/utils/resize_video.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/show_scaffold_dialog.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/composer_emoji_text_controller.dart';
import 'package:fluffychat/widgets/share_scaffold_dialog.dart';
import '../../utils/account_bundles.dart';
import '../../utils/localized_exception_extension.dart';
import 'events/custom_reaction_picker.dart';
import 'events/message_context_menu.dart';
import 'events/message_context_menu_logic.dart';
import 'send_file_dialog.dart';
import 'send_location_dialog.dart';

class ChatPage extends StatelessWidget {
  final String roomId;
  final List<ShareItem>? shareItems;
  final String? eventId;

  const ChatPage({
    super.key,
    required this.roomId,
    this.eventId,
    this.shareItems,
  });

  @override
  Widget build(BuildContext context) {
    final room = Matrix.of(context).client.getRoomById(roomId);
    if (room == null) {
      return Scaffold(
        appBar: AppBar(title: Text(L10n.of(context).oopsSomethingWentWrong)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(L10n.of(context).youAreNoLongerParticipatingInThisChat),
          ),
        ),
      );
    }

    return ChatPageWithRoom(
      key: Key('chat_page_${roomId}_$eventId'),
      room: room,
      shareItems: shareItems,
      eventId: eventId,
    );
  }
}

class ChatPageWithRoom extends StatefulWidget {
  final Room room;
  final List<ShareItem>? shareItems;
  final String? eventId;

  const ChatPageWithRoom({
    super.key,
    required this.room,
    this.shareItems,
    this.eventId,
  });

  @override
  ChatController createState() => ChatController();
}

class ChatController extends State<ChatPageWithRoom>
    with WidgetsBindingObserver {
  Room get room => sendingClient.getRoomById(roomId) ?? widget.room;

  late Client sendingClient;

  Timeline? timeline;

  String? activeThreadId;

  late final Set<String> bigEmojis;

  late final String readMarkerEventId;

  String get roomId => widget.room.id;

  final AutoScrollController scrollController = AutoScrollController();

  late final FocusNode inputFocus;

  Timer? typingCoolDown;
  Timer? typingTimeout;
  bool currentlyTyping = false;
  bool dragging = false;

  void onDragEntered(_) => setState(() => dragging = true);

  void onDragExited(_) => setState(() => dragging = false);

  Future<void> onDragDone(DropDoneDetails details) async {
    setState(() => dragging = false);
    if (details.files.isEmpty) return;
    addPendingMedia(details.files);
  }

  bool get canSaveSelectedEvent =>
      selectedEvents.length == 1 &&
      {
        MessageTypes.Video,
        MessageTypes.Image,
        MessageTypes.Sticker,
        MessageTypes.Audio,
        MessageTypes.File,
      }.contains(selectedEvents.single.messageType);

  void saveSelectedEvent(BuildContext context) =>
      selectedEvents.single.saveFile(context);

  List<Event> selectedEvents = [];

  // Drag-select support
  final Map<String, GlobalKey> messageKeys = {};

  void registerMessageKey(String eventId, GlobalKey key) {
    messageKeys[eventId] = key;
  }

  void unregisterMessageKey(String eventId) {
    messageKeys.remove(eventId);
  }

  String? hitTestEventAt(double globalY) {
    for (final entry in messageKeys.entries) {
      final renderObj = entry.value.currentContext?.findRenderObject();
      if (renderObj is RenderBox && renderObj.attached) {
        final topLeft = renderObj.localToGlobal(Offset.zero);
        final bottom = topLeft.dy + renderObj.size.height;
        if (globalY >= topLeft.dy && globalY <= bottom) {
          return entry.key;
        }
      }
    }
    return null;
  }

  Event? eventById(String eventId) {
    return timeline?.events.firstWhereOrNull((e) => e.eventId == eventId);
  }

  static const String _reactionUsageStoreKey = 'chat.fluffy.reaction_usage.v1';

  final Set<String> unfolded = {};

  Event? replyEvent;

  Event? editEvent;

  bool _scrolledUp = false;

  bool get showScrollDownButton =>
      _scrolledUp || timeline?.allowNewEvent == false;

  bool get selectMode => selectedEvents.isNotEmpty;

  final int _loadHistoryCount = 100;

  String pendingText = '';

  bool showEmojiPicker = false;

  /// Media files pending to be sent inline with the next message.
  List<XFile> pendingMediaFiles = [];

  bool _allFilesAreMedia(List<XFile> files) {
    return files.every((file) {
      final mimeType = file.mimeType ?? lookupMimeType(file.name);
      return mimeType != null &&
          (mimeType.startsWith('image') || mimeType.startsWith('video'));
    });
  }

  void addPendingMedia(List<XFile> files) {
    if (files.isEmpty) return;
    if (!_allFilesAreMedia(files)) {
      _showSendFileDialog(files);
      return;
    }
    // Cancel edit mode when adding media (can't edit with attachments)
    if (editEvent != null) {
      cancelReplyEventAction();
    }
    setState(() {
      pendingMediaFiles = [...pendingMediaFiles, ...files];
    });
  }

  void removePendingMedia(int index) {
    setState(() {
      pendingMediaFiles = List.of(pendingMediaFiles)..removeAt(index);
    });
  }

  void clearPendingMedia() {
    setState(() {
      pendingMediaFiles = [];
    });
  }

  void _showSendFileDialog(List<XFile> files) {
    showAdaptiveDialog(
      context: context,
      builder: (c) => SendFileDialog(
        files: files,
        room: room,
        outerContext: context,
        threadRootEventId: activeThreadId,
        threadLastEventId: threadLastEventId,
      ),
    );
  }

  Map<String, int> _readReactionUsage() {
    final raw = AppSettings.store.getString(_reactionUsageStoreKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return {};
      return decoded.map((key, value) {
        final count = value is int ? value : int.tryParse('$value') ?? 0;
        return MapEntry(key, count);
      });
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeReactionUsage(Map<String, int> usage) =>
      AppSettings.store.setString(_reactionUsageStoreKey, jsonEncode(usage));

  Future<void> _incrementReactionUsage(String reactionKey) async {
    final key = reactionKey.trim();
    if (key.isEmpty) return;
    final usage = _readReactionUsage();
    usage[key] = (usage[key] ?? 0) + 1;
    await _writeReactionUsage(usage);
  }

  List<String> get quickReactionOptions => rankQuickReactions(
    _readReactionUsage(),
    fallbackReactions: [...AppConfig.defaultReactions, '👌'],
  );

  String? get threadLastEventId {
    final threadId = activeThreadId;
    if (threadId == null) return null;
    return timeline?.events
        .filterByVisibleInGui(threadId: threadId)
        .firstOrNull
        ?.eventId;
  }

  void enterThread(String eventId) => setState(() {
    activeThreadId = eventId;
    selectedEvents.clear();
  });

  void closeThread() => setState(() {
    activeThreadId = null;
    selectedEvents.clear();
  });

  Future<void> recreateChat() async {
    final room = this.room;
    final userId = room.directChatMatrixID;
    if (userId == null) {
      throw Exception(
        'Try to recreate a room with is not a DM room. This should not be possible from the UI!',
      );
    }
    await showFutureLoadingDialog(
      context: context,
      future: () => room.invite(userId),
    );
  }

  Future<void> leaveChat() async {
    final success = await showFutureLoadingDialog(
      context: context,
      future: room.leave,
    );
    if (success.error != null) return;
    context.go('/rooms');
  }

  Future<void> requestHistory([_]) async {
    Logs().v('Requesting history...');
    await timeline?.requestHistory(historyCount: _loadHistoryCount);
  }

  Future<void> requestFuture() async {
    final timeline = this.timeline;
    if (timeline == null) return;
    Logs().v('Requesting future...');

    final mostRecentEvent = timeline.events.filterByVisibleInGui().firstOrNull;

    await timeline.requestFuture(historyCount: _loadHistoryCount);

    if (mostRecentEvent != null) {
      setReadMarker(eventId: mostRecentEvent.eventId);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final index = timeline.events.filterByVisibleInGui().indexOf(
          mostRecentEvent,
        );
        if (index >= 0) {
          scrollController.scrollToIndex(
            index,
            preferPosition: AutoScrollPosition.begin,
          );
        }
      });
    }
  }

  void _updateScrollController() {
    if (!mounted) {
      return;
    }
    if (!scrollController.hasClients) return;
    if (timeline?.allowNewEvent == false ||
        scrollController.position.pixels > 0 && _scrolledUp == false) {
      setState(() => _scrolledUp = true);
    } else if (scrollController.position.pixels <= 0 && _scrolledUp == true) {
      setState(() => _scrolledUp = false);
      setReadMarker();
    }
  }

  void _loadDraft() {
    final prefs = Matrix.of(context).store;
    final draft = prefs.getString('draft_$roomId');
    if (draft != null && draft.isNotEmpty) {
      sendController.text = draft;
    }
  }

  void _shareItems([_]) {
    final shareItems = widget.shareItems;
    if (shareItems == null || shareItems.isEmpty) return;
    if (!room.otherPartyCanReceiveMessages) {
      final theme = Theme.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: theme.colorScheme.errorContainer,
          closeIconColor: theme.colorScheme.onErrorContainer,
          content: Text(
            L10n.of(context).otherPartyNotLoggedIn,
            style: TextStyle(color: theme.colorScheme.onErrorContainer),
          ),
          showCloseIcon: true,
        ),
      );
      return;
    }
    for (final item in shareItems) {
      if (item is FileShareItem) continue;
      if (item is TextShareItem) room.sendTextEvent(item.value);
      if (item is ContentShareItem) room.sendEvent(item.value);
    }
    final files = shareItems
        .whereType<FileShareItem>()
        .map((item) => item.value)
        .toList();
    if (files.isEmpty) return;
    addPendingMedia(files);
  }

  bool _isPasting = false;

  KeyEventResult _customEnterKeyHandling(FocusNode node, KeyEvent evt) {
    if (evt is KeyDownEvent &&
        evt.logicalKey == LogicalKeyboardKey.keyV &&
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed)) {
      _handleClipboardPaste();
      return KeyEventResult.ignored;
    }

    if (!HardwareKeyboard.instance.isShiftPressed &&
        evt.logicalKey.keyLabel == 'Enter' &&
        AppSettings.sendOnEnter.value) {
      if (evt is KeyDownEvent) {
        send();
      }
      return KeyEventResult.handled;
    } else if (evt.logicalKey.keyLabel == 'Enter' && evt is KeyDownEvent) {
      final currentLineNum =
          sendController.text
              .substring(0, sendController.selection.baseOffset)
              .split('\n')
              .length -
          1;
      final currentLine = sendController.text.split('\n')[currentLineNum];

      for (final pattern in [
        '- [ ] ',
        '- [x] ',
        '* [ ] ',
        '* [x] ',
        '- ',
        '* ',
        '+ ',
      ]) {
        if (currentLine.startsWith(pattern)) {
          if (currentLine == pattern) {
            return KeyEventResult.ignored;
          }
          sendController.text += '\n$pattern';
          return KeyEventResult.handled;
        }
      }

      return KeyEventResult.ignored;
    } else {
      return KeyEventResult.ignored;
    }
  }

  Future<void> _handleClipboardPaste() async {
    if (PlatformInfos.isMobile || _isPasting) return;
    _isPasting = true;
    try {
      final imageBytes = await Pasteboard.image;
      if (imageBytes != null && mounted) {
        await sendImageFromClipBoard(imageBytes);
      }
    } finally {
      _isPasting = false;
    }
  }

  @override
  void initState() {
    inputFocus = FocusNode(onKeyEvent: _customEnterKeyHandling);
    sendController = ComposerEmojiTextController(
      room: widget.room,
      client: widget.room.client,
    );

    scrollController.addListener(_updateScrollController);
    inputFocus.addListener(_inputFocusListener);

    _loadDraft();
    WidgetsBinding.instance.addPostFrameCallback(_shareItems);
    super.initState();
    _displayChatDetailsColumn = ValueNotifier(
      AppSettings.displayChatDetailsColumn.value,
    );

    bigEmojis = defaultEmojiSet.fold(
      <String>{},
      (emojis, category) => {
        ...emojis,
        ...(category.emoji.map((emoji) => emoji.emoji)),
      },
    );

    sendingClient = Matrix.of(context).client;
    sendController.updateRoomAndClient(room: room, client: sendingClient);
    final lastEventThreadId =
        room.lastEvent?.relationshipType == RelationshipTypes.thread
        ? room.lastEvent?.relationshipEventId
        : null;
    readMarkerEventId = room.hasNewMessages
        ? lastEventThreadId ?? room.fullyRead
        : '';
    WidgetsBinding.instance.addObserver(this);
    _tryLoadTimeline();
  }

  final Set<String> expandedEventIds = {};

  void expandEventsFrom(Event event, bool expand) {
    final events = timeline!.events.filterByVisibleInGui(
      threadId: activeThreadId,
    );
    final start = events.indexOf(event);
    setState(() {
      for (var i = start; i < events.length; i++) {
        final event = events[i];
        if (!event.isCollapsedState) return;
        if (expand) {
          expandedEventIds.add(event.eventId);
        } else {
          expandedEventIds.remove(event.eventId);
        }
      }
    });
  }

  Future<void> _tryLoadTimeline() async {
    final initialEventId = widget.eventId;
    loadTimelineFuture = _getTimeline();
    try {
      await loadTimelineFuture;
      // We launched the chat with a given initial event ID:
      if (initialEventId != null) {
        scrollToEventId(initialEventId);
        return;
      }

      var readMarkerEventIndex = readMarkerEventId.isEmpty
          ? -1
          : timeline!.events
                .filterByVisibleInGui(
                  exceptionEventId: readMarkerEventId,
                  threadId: activeThreadId,
                )
                .indexWhere((e) => e.eventId == readMarkerEventId);

      // Read marker is existing but not found in first events. Try a single
      // requestHistory call before opening timeline on event context:
      if (readMarkerEventId.isNotEmpty && readMarkerEventIndex == -1) {
        await timeline?.requestHistory(historyCount: _loadHistoryCount);
        readMarkerEventIndex = timeline!.events
            .filterByVisibleInGui(
              exceptionEventId: readMarkerEventId,
              threadId: activeThreadId,
            )
            .indexWhere((e) => e.eventId == readMarkerEventId);
      }

      if (readMarkerEventIndex > 1) {
        Logs().v('Scroll up to visible event', readMarkerEventId);
        scrollToEventId(readMarkerEventId, highlightEvent: false);
        return;
      } else if (readMarkerEventId.isNotEmpty && readMarkerEventIndex == -1) {
        _showScrollUpMaterialBanner(readMarkerEventId);
      }

      // Mark room as read on first visit if requirements are fulfilled
      setReadMarker();

      if (!mounted) return;
    } catch (e, s) {
      ErrorReporter(context, 'Unable to load timeline').onErrorCallback(e, s);
      rethrow;
    }
  }

  String? scrollUpBannerEventId;

  void discardScrollUpBannerEventId() => setState(() {
    scrollUpBannerEventId = null;
  });

  void _showScrollUpMaterialBanner(String eventId) => setState(() {
    scrollUpBannerEventId = eventId;
  });

  void updateView() {
    if (!mounted) return;
    sendController.refreshCatalog();
    setReadMarker();
    setState(() {});
  }

  Future<void>? loadTimelineFuture;

  int? animateInEventIndex;

  void onInsert(int i) {
    // setState will be called by updateView() anyway
    if (timeline?.allowNewEvent == true) animateInEventIndex = i;
  }

  Future<void> _getTimeline({String? eventContextId}) async {
    await Matrix.of(context).client.roomsLoading;
    await Matrix.of(context).client.accountDataLoading;
    if (eventContextId != null &&
        (!eventContextId.isValidMatrixId || eventContextId.sigil != '\$')) {
      eventContextId = null;
    }
    try {
      timeline?.cancelSubscriptions();
      timeline = await room.getTimeline(
        onUpdate: updateView,
        eventContextId: eventContextId,
        onInsert: onInsert,
      );
    } catch (e, s) {
      Logs().w('Unable to load timeline on event ID $eventContextId', e, s);
      if (!mounted) return;
      timeline = await room.getTimeline(
        onUpdate: updateView,
        onInsert: onInsert,
      );
      if (!mounted) return;
      if (e is TimeoutException || e is IOException) {
        _showScrollUpMaterialBanner(eventContextId!);
      }
    }
    timeline!.requestKeys(onlineKeyBackupOnly: false);
    if (room.markedUnread) room.markUnread(false);

    return;
  }

  String? scrollToEventIdMarker;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (!mounted) return;
    setReadMarker();
  }

  Future<void>? _setReadMarkerFuture;

  void setReadMarker({String? eventId}) {
    if (eventId?.isValidMatrixId == false) return;
    if (_setReadMarkerFuture != null) return;
    if (_scrolledUp) return;
    if (scrollUpBannerEventId != null) return;

    if (eventId == null &&
        !room.hasNewMessages &&
        room.notificationCount == 0) {
      return;
    }

    // Do not send read markers when app is not in foreground
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }

    final timeline = this.timeline;
    if (timeline == null || timeline.events.isEmpty) return;

    Logs().d('Set read marker...', eventId);
    // ignore: unawaited_futures
    _setReadMarkerFuture = timeline
        .setReadMarker(
          eventId: eventId,
          public: AppSettings.sendPublicReadReceipts.value,
        )
        .then((_) {
          _setReadMarkerFuture = null;
        });
    if (eventId == null || eventId == timeline.room.lastEvent?.eventId) {
      Matrix.of(context).backgroundPush?.cancelNotification(roomId);
    }
  }

  @override
  void dispose() {
    timeline?.cancelSubscriptions();
    timeline = null;
    inputFocus.removeListener(_inputFocusListener);
    sendController.dispose();
    super.dispose();
  }

  late final ComposerEmojiTextController sendController;

  void setSendingClient(Client c) {
    // first cancel typing with the old sending client
    if (currentlyTyping) {
      // no need to have the setting typing to false be blocking
      typingCoolDown?.cancel();
      typingCoolDown = null;
      room.setTyping(false);
      currentlyTyping = false;
    }
    // then cancel the old timeline
    // fixes bug with read reciepts and quick switching
    loadTimelineFuture = _getTimeline(eventContextId: room.fullyRead).onError(
      ErrorReporter(
        context,
        'Unable to load timeline after changing sending Client',
      ).onErrorCallback,
    );
    final controllerRoom = c.getRoomById(roomId) ?? widget.room;
    sendController.updateRoomAndClient(room: controllerRoom, client: c);

    // then set the new sending client
    setState(() => sendingClient = c);
  }

  void setActiveClient(Client c) => setState(() {
    Matrix.of(context).setActiveClient(c);
  });

  Future<void> send() async {
    final hasText = sendController.text.trim().isNotEmpty;
    final hasMedia = pendingMediaFiles.isNotEmpty;

    if (!hasText && !hasMedia) return;

    _storeInputTimeoutTimer?.cancel();
    final prefs = Matrix.of(context).store;
    prefs.remove('draft_$roomId');

    if (!hasMedia) {
      await _sendTextOnly();
      return;
    }

    await _sendMediaFiles();
  }

  Future<void> _sendTextOnly() async {
    final sourceText = sendController.text;
    final commandMatch = RegExp(r'^\/(\w+)').firstMatch(sourceText);

    var useCommandPath = false;
    if (commandMatch != null) {
      final commandName = commandMatch[1]!.toLowerCase();
      if (sendingClient.commands.keys.contains(commandName)) {
        useCommandPath = true;
      } else {
        final l10n = L10n.of(context);
        final dialogResult = await showOkCancelAlertDialog(
          context: context,
          title: l10n.commandInvalid,
          message: l10n.commandMissing(commandMatch[0]!),
          okLabel: l10n.sendAsText,
          cancelLabel: l10n.cancel,
        );
        if (dialogResult == OkCancelResult.cancel) return;
      }
    }

    if (useCommandPath) {
      // ignore: unawaited_futures
      room.sendTextEvent(
        sourceText,
        inReplyTo: replyEvent,
        editEventId: editEvent?.eventId,
        parseCommands: true,
        threadRootEventId: activeThreadId,
      );
    } else {
      final built = buildCustomEmojiMessage(
        room: room,
        sourceBody: sourceText,
        inReplyTo: replyEvent,
      );
      // ignore: unawaited_futures
      room.sendEvent(
        built.content,
        inReplyTo: replyEvent,
        editEventId: editEvent?.eventId,
        threadRootEventId: activeThreadId,
        threadLastEventId: threadLastEventId,
      );
    }
    _resetInputState();
  }

  static const int _maxAlbumSize = 10;
  static const int _minSizeToCompress = 20 * 1000;

  static String _generateAlbumId() {
    final random = Random();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final suffix = random.nextInt(1 << 32).toRadixString(36);
    return '$timestamp-$suffix';
  }

  Future<void> _sendMediaFiles() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final l10n = L10n.of(context);
    final captionText = sendController.text.trim();
    final files = List<XFile>.of(pendingMediaFiles);
    final reply = replyEvent;
    final compress = AppSettings.compressMedia.value;
    final groupAlbum = AppSettings.groupAsAlbum.value;

    // Clear state immediately so user sees input reset
    _resetInputState();
    setState(() => pendingMediaFiles = []);

    try {
      if (!room.otherPartyCanReceiveMessages) {
        throw OtherPartyCanNotReceiveMessages();
      }
      scaffoldMessenger.showLoadingSnackBar(l10n.prepareSendingAttachment);
      final clientConfig = await room.client.getConfig();
      final maxUploadSize = clientConfig.mUploadSize ?? 100 * 1000 * 1000;

      final allMedia = files.every((file) {
        final mimeType = file.mimeType ?? lookupMimeType(file.name);
        return mimeType != null &&
            (mimeType.startsWith('image') || mimeType.startsWith('video'));
      });
      final useAlbum = files.length > 1 && allMedia && groupAlbum;
      final albumIds = <int, String>{};
      if (useAlbum) {
        for (var i = 0; i < files.length; i++) {
          final chunkIndex = i ~/ _maxAlbumSize;
          albumIds.putIfAbsent(chunkIndex, _generateAlbumId);
        }
      }

      for (var fileIndex = 0; fileIndex < files.length; fileIndex++) {
        final xfile = files[fileIndex];
        final MatrixFile file;
        MatrixImageFile? thumbnail;
        final length = await xfile.length();
        final mimeType = xfile.mimeType ?? lookupMimeType(xfile.path);

        // Generate video thumbnail
        if (PlatformInfos.isMobile &&
            mimeType != null &&
            mimeType.startsWith('video')) {
          scaffoldMessenger.showLoadingSnackBar(l10n.generatingVideoThumbnail);
          thumbnail = await xfile.getVideoThumbnail();
        }

        // Video compression
        if (PlatformInfos.isMobile &&
            mimeType != null &&
            mimeType.startsWith('video')) {
          scaffoldMessenger.showLoadingSnackBar(l10n.compressVideo);
          file = await xfile.getVideoInfo(
            compress: length > _minSizeToCompress && compress,
          );
        } else {
          if (length > maxUploadSize) {
            throw FileTooBigMatrixException(length, maxUploadSize);
          }
          file = MatrixFile(
            bytes: await xfile.readAsBytes(),
            name: xfile.name,
            mimeType: mimeType,
          ).detectFileType;
        }

        if (file.bytes.length > maxUploadSize) {
          throw FileTooBigMatrixException(length, maxUploadSize);
        }

        if (files.length > 1) {
          scaffoldMessenger.showLoadingSnackBar(
            l10n.sendingAttachmentCountOfCount(fileIndex + 1, files.length),
          );
        }

        final extraContent = <String, Object?>{};

        // Caption: assign to the last file in the batch
        if (captionText.isNotEmpty && fileIndex == files.length - 1) {
          extraContent['body'] = captionText;
        }

        if (useAlbum) {
          final chunkIndex = fileIndex ~/ _maxAlbumSize;
          extraContent['r.trd.album_id'] = albumIds[chunkIndex];
        }

        try {
          await room.sendFileEvent(
            file,
            thumbnail: thumbnail,
            shrinkImageMaxDimension: compress ? 1600 : null,
            extraContent: extraContent.isEmpty ? null : extraContent,
            inReplyTo: fileIndex == 0 ? reply : null,
            threadRootEventId: activeThreadId,
            threadLastEventId: threadLastEventId,
          );
        } on MatrixException catch (e) {
          final retryAfterMs = e.retryAfterMs;
          if (e.error != MatrixError.M_LIMIT_EXCEEDED || retryAfterMs == null) {
            rethrow;
          }
          final retryAfterDuration = Duration(
            milliseconds: retryAfterMs + 1000,
          );
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text(
                l10n.serverLimitReached(retryAfterDuration.inSeconds),
              ),
            ),
          );
          await Future.delayed(retryAfterDuration);
          scaffoldMessenger.showLoadingSnackBar(l10n.sendingAttachment);
          await room.sendFileEvent(
            file,
            thumbnail: thumbnail,
            shrinkImageMaxDimension: compress ? 1600 : null,
            extraContent: extraContent.isEmpty ? null : extraContent,
            inReplyTo: fileIndex == 0 ? reply : null,
            threadRootEventId: activeThreadId,
            threadLastEventId: threadLastEventId,
          );
        }
      }
      scaffoldMessenger.clearSnackBars();
    } catch (e) {
      scaffoldMessenger.clearSnackBars();
      final theme = Theme.of(context);
      scaffoldMessenger.showSnackBar(
        SnackBar(
          backgroundColor: theme.colorScheme.errorContainer,
          closeIconColor: theme.colorScheme.onErrorContainer,
          content: Text(
            e.toLocalizedString(context),
            style: TextStyle(color: theme.colorScheme.onErrorContainer),
          ),
          duration: const Duration(seconds: 30),
          showCloseIcon: true,
        ),
      );
    }
  }

  void _resetInputState() {
    sendController.value = TextEditingValue(
      text: pendingText,
      selection: const TextSelection.collapsed(offset: 0),
    );
    setState(() {
      sendController.text = pendingText;
      _inputTextIsEmpty = pendingText.isEmpty;
      replyEvent = null;
      editEvent = null;
      pendingText = '';
    });
  }

  Future<void> sendFileAction({FileType type = FileType.any}) async {
    final files = await selectFiles(context, allowMultiple: true, type: type);
    if (files.isEmpty) return;
    addPendingMedia(files);
  }

  Future<void> sendImageFromClipBoard(Uint8List? image) async {
    if (image == null) return;
    addPendingMedia([
      XFile.fromData(
        image,
        name: 'clipboard-image.png',
        path: 'clipboard-image.png',
        mimeType: 'image/png',
      ),
    ]);
  }

  Future<void> openCameraAction() async {
    // Make sure the textfield is unfocused before opening the camera
    FocusScope.of(context).requestFocus(FocusNode());
    final file = await ImagePicker().pickImage(source: ImageSource.camera);
    if (file == null) return;
    addPendingMedia([file]);
  }

  Future<void> openVideoCameraAction() async {
    // Make sure the textfield is unfocused before opening the camera
    FocusScope.of(context).requestFocus(FocusNode());
    final file = await ImagePicker().pickVideo(
      source: ImageSource.camera,
      maxDuration: const Duration(minutes: 1),
    );
    if (file == null) return;
    addPendingMedia([file]);
  }

  Future<void> onVoiceMessageSend(
    String path,
    int duration,
    List<int> waveform,
    String? fileName,
  ) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final audioFile = XFile(path);

    final bytesResult = await showFutureLoadingDialog(
      context: context,
      future: audioFile.readAsBytes,
    );
    final bytes = bytesResult.result;
    if (bytes == null) return;

    final file = MatrixAudioFile(
      bytes: bytes,
      name: fileName ?? audioFile.path,
    );

    room
        .sendFileEvent(
          file,
          inReplyTo: replyEvent,
          threadRootEventId: activeThreadId,
          extraContent: {
            'info': {...file.info, 'duration': duration},
            'org.matrix.msc3245.voice': {},
            'org.matrix.msc1767.audio': {
              'duration': duration,
              'waveform': waveform,
            },
          },
        )
        .catchError((e) {
          scaffoldMessenger.showSnackBar(
            SnackBar(content: Text((e as Object).toLocalizedString(context))),
          );
          return null;
        });
    setState(() {
      replyEvent = null;
    });
    return;
  }

  void hideEmojiPicker() {
    setState(() => showEmojiPicker = false);
  }

  void emojiPickerAction() {
    if (showEmojiPicker) {
      inputFocus.requestFocus();
    } else {
      inputFocus.unfocus();
    }
    setState(() => showEmojiPicker = !showEmojiPicker);
  }

  void _inputFocusListener() {
    if (showEmojiPicker && inputFocus.hasFocus) {
      setState(() => showEmojiPicker = false);
    }
  }

  Future<void> sendLocationAction() async {
    await showAdaptiveDialog(
      context: context,
      builder: (c) => SendLocationDialog(room: room),
    );
  }

  String _getEventString(List<Event> events) {
    if (events.isEmpty) return '';
    if (events.length == 1) {
      return events.first
          .getDisplayEvent(timeline!)
          .calcLocalizedBodyFallback(MatrixLocals(L10n.of(context)));
    }
    return events
        .map(
          (event) => event
              .getDisplayEvent(timeline!)
              .calcLocalizedBodyFallback(
                MatrixLocals(L10n.of(context)),
                withSenderNamePrefix: true,
              ),
        )
        .join('\n\n');
  }

  void _copyEventsToClipboard(
    List<Event> events, {
    required bool clearSelection,
  }) {
    if (events.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _getEventString(events)));
    setState(() {
      showEmojiPicker = false;
      if (clearSelection) {
        selectedEvents.clear();
      }
    });
  }

  void copyEventsAction() =>
      _copyEventsToClipboard(selectedEvents, clearSelection: true);

  void copySingleEventAction(Event event) =>
      _copyEventsToClipboard([event], clearSelection: false);

  Future<void> _reportEventAction(
    Event event, {
    required bool clearSelection,
  }) async {
    final score = await showModalActionPopup<int>(
      context: context,
      title: L10n.of(context).reportMessage,
      message: L10n.of(context).howOffensiveIsThisContent,
      cancelLabel: L10n.of(context).cancel,
      actions: [
        AdaptiveModalAction(
          value: -100,
          label: L10n.of(context).extremeOffensive,
        ),
        AdaptiveModalAction(value: -50, label: L10n.of(context).offensive),
        AdaptiveModalAction(value: 0, label: L10n.of(context).inoffensive),
      ],
    );
    if (score == null) return;
    final reason = await showTextInputDialog(
      context: context,
      title: L10n.of(context).whyDoYouWantToReportThis,
      okLabel: L10n.of(context).ok,
      cancelLabel: L10n.of(context).cancel,
      hintText: L10n.of(context).reason,
    );
    if (reason == null || reason.isEmpty) return;
    final result = await showFutureLoadingDialog(
      context: context,
      future: () => Matrix.of(context).client.reportEvent(
        event.roomId!,
        event.eventId,
        reason: reason,
        score: score,
      ),
    );
    if (result.error != null) return;
    setState(() {
      showEmojiPicker = false;
      if (clearSelection) {
        selectedEvents.clear();
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(L10n.of(context).contentHasBeenReported)),
    );
  }

  Future<void> reportEventAction([Event? event]) async {
    final target = event ?? selectedEvents.single;
    await _reportEventAction(target, clearSelection: event == null);
  }

  Future<void> deleteErrorEventsAction() async {
    try {
      if (selectedEvents.any((event) => event.status != EventStatus.error)) {
        throw Exception(
          'Tried to delete failed to send events but one event is not failed to sent',
        );
      }
      for (final event in selectedEvents) {
        await event.cancelSend();
      }
      setState(selectedEvents.clear);
    } catch (e, s) {
      ErrorReporter(
        context,
        'Error while delete error events action',
      ).onErrorCallback(e, s);
    }
  }

  Future<void> _redactEvents(
    List<Event> events, {
    required bool clearSelection,
  }) async {
    if (events.isEmpty) return;
    final reasonInput = events.any((event) => event.status.isSent)
        ? await showTextInputDialog(
            context: context,
            title: L10n.of(context).redactMessage,
            message: L10n.of(context).redactMessageDescription,
            isDestructive: true,
            hintText: L10n.of(context).optionalRedactReason,
            maxLength: 255,
            maxLines: 3,
            minLines: 1,
            okLabel: L10n.of(context).remove,
            cancelLabel: L10n.of(context).cancel,
          )
        : null;
    if (reasonInput == null) return;
    final reason = reasonInput.isEmpty ? null : reasonInput;
    await showFutureLoadingDialog(
      context: context,
      futureWithProgress: (onProgress) async {
        final count = events.length;
        for (final (i, event) in events.indexed) {
          onProgress(i / count);
          if (event.status.isSent) {
            if (event.canRedact) {
              await event.redactEvent(reason: reason);
            } else {
              final client = currentRoomBundle.firstWhere(
                (cl) => event.senderId == cl!.userID,
                orElse: () => null,
              );
              if (client == null) {
                return;
              }
              final room = client.getRoomById(roomId)!;
              await Event.fromJson(
                event.toJson(),
                room,
              ).redactEvent(reason: reason);
            }
          } else {
            await event.cancelSend();
          }
        }
      },
    );
    setState(() {
      showEmojiPicker = false;
      if (clearSelection) {
        selectedEvents.clear();
      }
    });
  }

  Future<void> redactEventsAction() async =>
      _redactEvents(selectedEvents, clearSelection: true);

  Future<void> redactSingleEventAction(Event event) async =>
      _redactEvents([event], clearSelection: false);

  List<Client?> get currentRoomBundle {
    final clients = Matrix.of(context).currentBundle!;
    clients.removeWhere((c) => c!.getRoomById(roomId) == null);
    return clients;
  }

  bool _isOwnEvent(Event event) =>
      currentRoomBundle.any((cl) => event.senderId == cl!.userID);

  bool _canRedactEvent(Event event) {
    if (isArchived || !event.status.isSent) return false;
    if (event.canRedact) return true;
    final clients = Matrix.of(context).currentBundle;
    return clients?.any((cl) => event.senderId == cl!.userID) ?? false;
  }

  bool _canEditEvent(Event event) {
    if (isArchived || !event.status.isSent) {
      return false;
    }
    return _isOwnEvent(event);
  }

  bool get canRedactSelectedEvents {
    if (selectedEvents.isEmpty) return false;
    return selectedEvents.every(_canRedactEvent);
  }

  bool get canPinSelectedEvents {
    if (isArchived ||
        !room.canChangeStateEvent(EventTypes.RoomPinnedEvents) ||
        selectedEvents.length != 1 ||
        !selectedEvents.single.status.isSent ||
        activeThreadId != null) {
      return false;
    }
    return true;
  }

  bool get canEditSelectedEvents {
    if (selectedEvents.length != 1) return false;
    return _canEditEvent(selectedEvents.first);
  }

  Future<void> _forwardEvents(
    List<Event> events, {
    required bool clearSelection,
  }) async {
    if (events.isEmpty) return;
    final timeline = this.timeline;
    if (timeline == null) return;

    final forwardEvents = List<Event>.from(
      events,
    ).map((event) => event.getDisplayEvent(timeline)).toList();

    await showScaffoldDialog(
      context: context,
      builder: (context) => ShareScaffoldDialog(
        items: forwardEvents
            .map((event) => ContentShareItem(event.content))
            .toList(),
      ),
    );
    if (!mounted) return;
    if (clearSelection) {
      setState(() => selectedEvents.clear());
    }
  }

  Future<void> forwardEventsAction() async =>
      _forwardEvents(selectedEvents, clearSelection: true);

  Future<void> forwardSingleEventAction(Event event) async =>
      _forwardEvents([event], clearSelection: false);

  void sendAgainAction() {
    final event = selectedEvents.first;
    if (event.status.isError) {
      event.sendAgain();
    }
    final allEditEvents = event
        .aggregatedEvents(timeline!, RelationshipTypes.edit)
        .where((e) => e.status.isError);
    for (final e in allEditEvents) {
      e.sendAgain();
    }
    setState(() => selectedEvents.clear());
  }

  void replyAction({Event? replyTo}) {
    setState(() {
      replyEvent = replyTo ?? selectedEvents.first;
      selectedEvents.clear();
    });
    inputFocus.requestFocus();
  }

  Set<String> _sentReactionsForEvent(Event event) {
    final timeline = this.timeline;
    if (timeline == null) return {};
    return event
        .aggregatedEvents(timeline, RelationshipTypes.reaction)
        .where(
          (reactionEvent) =>
              reactionEvent.senderId == reactionEvent.room.client.userID &&
              reactionEvent.type == EventTypes.Reaction,
        )
        .map(
          (reactionEvent) => reactionEvent.content
              .tryGetMap<String, Object?>('m.relates_to')
              ?.tryGet<String>('key'),
        )
        .whereType<String>()
        .toSet();
  }

  Future<void> sendReactionAction(
    Event event,
    String reactionKey,
    Set<String> sentReactions,
  ) async {
    final key = reactionKey.trim();
    if (key.isEmpty || sentReactions.contains(key)) return;
    await event.room.sendReaction(event.eventId, key);
    await _incrementReactionUsage(key);
  }

  Future<void> sendCustomReactionAction(
    Event event,
    Set<String> sentReactions,
  ) async {
    final emoji = await showCustomReactionPicker(context);
    if (emoji == null || emoji.isEmpty || sentReactions.contains(emoji)) return;
    await sendReactionAction(event, emoji, sentReactions);
  }

  Future<void> openMessageContextMenu(
    Event event,
    Offset globalPosition,
  ) async {
    final availability = resolveMessageContextActionAvailability(
      isSent: event.status.isSent,
      isError: event.status.isError,
      isRedacted: event.redacted,
      isOwnEvent: _isOwnEvent(event),
      isArchived: isArchived,
      canRedact: _canRedactEvent(event),
      roomCanSendDefaultMessages: room.canSendDefaultMessages,
      hasActiveThread: activeThreadId != null,
    );
    final sentReactions = _sentReactionsForEvent(event);
    final result = await showMessageContextMenu(
      context: context,
      globalPosition: globalPosition,
      availability: availability,
      quickReactions: quickReactionOptions,
      sentReactions: sentReactions,
    );

    if (result == null || !mounted) return;

    switch (result) {
      case MessageContextMenuActionResult(:final action):
        switch (action) {
          case MessageContextAction.reply:
            replyAction(replyTo: event);
            return;
          case MessageContextAction.copy:
            copySingleEventAction(event);
            return;
          case MessageContextAction.forward:
            await forwardSingleEventAction(event);
            return;
          case MessageContextAction.replyInThread:
            enterThread(event.eventId);
            return;
          case MessageContextAction.select:
            onSelectMessage(event);
            return;
          case MessageContextAction.edit:
            editSingleEventAction(event);
            return;
          case MessageContextAction.redact:
            await redactSingleEventAction(event);
            return;
          case MessageContextAction.report:
            await reportEventAction(event);
            return;
        }
      case MessageContextMenuQuickReactionResult(:final reactionKey):
        await sendReactionAction(event, reactionKey, sentReactions);
        return;
      case MessageContextMenuCustomReactionResult():
        await sendCustomReactionAction(event, sentReactions);
        return;
    }
  }

  Future<void> scrollToEventId(
    String eventId, {
    bool highlightEvent = true,
  }) async {
    final foundEvent = timeline!.events.firstWhereOrNull(
      (event) => event.eventId == eventId,
    );

    final eventIndex = foundEvent == null
        ? -1
        : timeline!.events
              .filterByVisibleInGui(
                exceptionEventId: eventId,
                threadId: activeThreadId,
              )
              .indexOf(foundEvent);

    if (eventIndex == -1) {
      setState(() {
        timeline = null;
        _scrolledUp = false;
        loadTimelineFuture = _getTimeline(eventContextId: eventId).onError(
          ErrorReporter(
            context,
            'Unable to load timeline after scroll to ID',
          ).onErrorCallback,
        );
      });
      await loadTimelineFuture;
      WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
        scrollToEventId(eventId);
      });
      return;
    }
    if (highlightEvent) {
      setState(() {
        scrollToEventIdMarker = eventId;
      });
    }
    await scrollController.scrollToIndex(
      eventIndex + 1,
      duration: FluffyThemes.animationDuration,
      preferPosition: AutoScrollPosition.middle,
    );
    _updateScrollController();
  }

  Future<void> scrollDown() async {
    if (!timeline!.allowNewEvent) {
      setState(() {
        timeline = null;
        _scrolledUp = false;
        loadTimelineFuture = _getTimeline().onError(
          ErrorReporter(
            context,
            'Unable to load timeline after scroll down',
          ).onErrorCallback,
        );
      });
      await loadTimelineFuture;
    }
    scrollController.jumpTo(0);
  }

  void onEmojiSelected(_, Emoji? emoji) {
    typeEmoji(emoji);
    onInputBarChanged(sendController.text);
  }

  void typeEmoji(Emoji? emoji) {
    if (emoji == null) return;
    final text = sendController.text;
    final selection = sendController.selection;
    final newText = sendController.text.isEmpty
        ? emoji.emoji
        : text.replaceRange(selection.start, selection.end, emoji.emoji);
    sendController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        // don't forget an UTF-8 combined emoji might have a length > 1
        offset: selection.baseOffset + emoji.emoji.length,
      ),
    );
  }

  void typeCustomEmojiShortcode(
    String shortcode, {
    bool addTrailingSpace = true,
  }) {
    if (shortcode.isEmpty) return;
    final selection = sendController.selection;
    final text = sendController.text;
    final replacement = addTrailingSpace ? '$shortcode ' : shortcode;
    final start = selection.start >= 0 ? selection.start : text.length;
    final end = selection.end >= 0 ? selection.end : text.length;
    final newText = text.replaceRange(start, end, replacement);
    sendController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + replacement.length),
    );
  }

  void emojiPickerBackspace() {
    sendController
      ..text = sendController.text.characters.skipLast(1).toString()
      ..selection = TextSelection.fromPosition(
        TextPosition(offset: sendController.text.length),
      );
  }

  void clearSelectedEvents() => setState(() {
    selectedEvents.clear();
    showEmojiPicker = false;
  });

  void clearSingleSelectedEvent() {
    if (selectedEvents.length <= 1) {
      clearSelectedEvents();
    }
  }

  void _editEventAction(Event event, {required bool clearSelection}) {
    final client = currentRoomBundle.firstWhere(
      (cl) => event.senderId == cl!.userID,
      orElse: () => null,
    );
    if (client == null) {
      return;
    }
    setSendingClient(client);
    setState(() {
      pendingText = sendController.text;
      editEvent = event;
      final displayEvent = editEvent!.getDisplayEvent(timeline!);
      final sourceBody =
          displayEvent.content.tryGet<String>(customEmojiSourceBodyKey) ??
          displayEvent.content
              .tryGetMap<String, Object?>('m.new_content')
              ?.tryGet<String>(customEmojiSourceBodyKey);
      sendController.text = (sourceBody != null && sourceBody.isNotEmpty)
          ? sourceBody
          : displayEvent.calcLocalizedBodyFallback(
              MatrixLocals(L10n.of(context)),
              withSenderNamePrefix: false,
              hideReply: true,
            );
      if (clearSelection) {
        selectedEvents.clear();
      }
    });
    inputFocus.requestFocus();
  }

  void editSelectedEventAction() {
    if (selectedEvents.length != 1) return;
    _editEventAction(selectedEvents.first, clearSelection: true);
  }

  void editSingleEventAction(Event event) =>
      _editEventAction(event, clearSelection: false);

  Future<void> goToNewRoomAction() async {
    final result = await showFutureLoadingDialog(
      context: context,
      future: () async {
        final users = await room.requestParticipants(
          [Membership.join, Membership.leave],
          true,
          false,
        );
        users.sort((a, b) => a.powerLevel.compareTo(b.powerLevel));
        final via = users
            .map((user) => user.id.domain)
            .whereType<String>()
            .toSet()
            .take(10)
            .toList();
        return room.client.joinRoom(
          room
              .getState(EventTypes.RoomTombstone)!
              .parsedTombstoneContent
              .replacementRoom,
          via: via,
        );
      },
    );
    if (result.error != null) return;
    if (!mounted) return;
    context.go('/rooms/${result.result!}');

    await showFutureLoadingDialog(context: context, future: room.leave);
  }

  void onSelectMessage(Event event) {
    if (!event.redacted) {
      if (selectedEvents.contains(event)) {
        setState(() => selectedEvents.remove(event));
      } else {
        setState(() => selectedEvents.add(event));
      }
      selectedEvents.sort(
        (a, b) => a.originServerTs.compareTo(b.originServerTs),
      );
    }
  }

  int? findChildIndexCallback(Key key, Map<String, int> thisEventsKeyMap) {
    // this method is called very often. As such, it has to be optimized for speed.
    if (key is! ValueKey) {
      return null;
    }
    final eventId = key.value;
    if (eventId is! String) {
      return null;
    }
    // first fetch the last index the event was at
    final index = thisEventsKeyMap[eventId];
    if (index == null) {
      return null;
    }
    // we need to +1 as 0 is the typing thing at the bottom
    return index + 1;
  }

  void onInputBarSubmitted(String _) {
    send();
    FocusScope.of(context).requestFocus(inputFocus);
  }

  void onAddPopupMenuButtonSelected(AddPopupMenuActions choice) {
    room.client.getConfig();

    switch (choice) {
      case AddPopupMenuActions.image:
        sendFileAction(type: FileType.image);
        return;
      case AddPopupMenuActions.video:
        sendFileAction(type: FileType.video);
        return;
      case AddPopupMenuActions.file:
        sendFileAction();
        return;
      case AddPopupMenuActions.poll:
        showAdaptiveBottomSheet(
          context: context,
          builder: (context) => StartPollBottomSheet(room: room),
        );
        return;
      case AddPopupMenuActions.photoCamera:
        openCameraAction();
        return;
      case AddPopupMenuActions.videoCamera:
        openVideoCameraAction();
        return;
      case AddPopupMenuActions.location:
        sendLocationAction();
        return;
    }
  }

  Future<void> unpinEvent(String eventId) async {
    final response = await showOkCancelAlertDialog(
      context: context,
      title: L10n.of(context).unpin,
      message: L10n.of(context).confirmEventUnpin,
      okLabel: L10n.of(context).unpin,
      cancelLabel: L10n.of(context).cancel,
    );
    if (response == OkCancelResult.ok) {
      final events = room.pinnedEventIds
        ..removeWhere((oldEvent) => oldEvent == eventId);
      showFutureLoadingDialog(
        context: context,
        future: () => room.setPinnedEvents(events),
      );
    }
  }

  void pinEvent() {
    final pinnedEventIds = room.pinnedEventIds;
    final selectedEventIds = selectedEvents.map((e) => e.eventId).toSet();
    final unpin =
        selectedEventIds.length == 1 &&
        pinnedEventIds.contains(selectedEventIds.single);
    if (unpin) {
      pinnedEventIds.removeWhere(selectedEventIds.contains);
    } else {
      pinnedEventIds.addAll(selectedEventIds);
    }
    showFutureLoadingDialog(
      context: context,
      future: () => room.setPinnedEvents(pinnedEventIds),
    );
  }

  Timer? _storeInputTimeoutTimer;
  static const Duration _storeInputTimeout = Duration(milliseconds: 500);

  void onInputBarChanged(String text) {
    if (_inputTextIsEmpty != text.isEmpty) {
      setState(() {
        _inputTextIsEmpty = text.isEmpty;
      });
    }

    _storeInputTimeoutTimer?.cancel();
    _storeInputTimeoutTimer = Timer(_storeInputTimeout, () async {
      final prefs = Matrix.of(context).store;
      await prefs.setString('draft_$roomId', text);
    });
    if (text.endsWith(' ') && Matrix.of(context).hasComplexBundles) {
      final clients = currentRoomBundle;
      for (final client in clients) {
        final prefix = client!.sendPrefix;
        if ((prefix.isNotEmpty) &&
            text.toLowerCase() == '${prefix.toLowerCase()} ') {
          setSendingClient(client);
          setState(() {
            sendController.clear();
          });
          return;
        }
      }
    }
    if (AppSettings.sendTypingNotifications.value) {
      typingCoolDown?.cancel();
      typingCoolDown = Timer(const Duration(seconds: 2), () {
        typingCoolDown = null;
        currentlyTyping = false;
        room.setTyping(false);
      });
      typingTimeout ??= Timer(const Duration(seconds: 30), () {
        typingTimeout = null;
        currentlyTyping = false;
      });
      if (!currentlyTyping) {
        currentlyTyping = true;
        room.setTyping(
          true,
          timeout: const Duration(seconds: 30).inMilliseconds,
        );
      }
    }
  }

  bool _inputTextIsEmpty = true;

  bool get isArchived =>
      {Membership.leave, Membership.ban}.contains(room.membership);

  void showEventInfo([Event? event]) =>
      (event ?? selectedEvents.single).showInfoDialog(context);

  Future<void> onPhoneButtonTap() async {
    // VoIP required Android SDK 21
    if (PlatformInfos.isAndroid) {
      DeviceInfoPlugin().androidInfo.then((value) {
        if (value.version.sdkInt < 21) {
          Navigator.pop(context);
          showOkAlertDialog(
            context: context,
            title: L10n.of(context).unsupportedAndroidVersion,
            message: L10n.of(context).unsupportedAndroidVersionLong,
            okLabel: L10n.of(context).close,
          );
        }
      });
    }
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

    final voipPlugin = Matrix.of(context).voipPlugin;
    try {
      await voipPlugin!.voip.inviteToCall(room, callType);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toLocalizedString(context))));
    }
  }

  void cancelReplyEventAction() => setState(() {
    if (editEvent != null) {
      sendController.text = pendingText;
      pendingText = '';
    }
    replyEvent = null;
    editEvent = null;
  });

  late final ValueNotifier<bool> _displayChatDetailsColumn;

  Future<void> toggleDisplayChatDetailsColumn() async {
    await AppSettings.displayChatDetailsColumn.setItem(
      !_displayChatDetailsColumn.value,
    );
    _displayChatDetailsColumn.value = !_displayChatDetailsColumn.value;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: ChatView(this)),
        ValueListenableBuilder(
          valueListenable: _displayChatDetailsColumn,
          builder: (context, displayChatDetailsColumn, _) =>
              !FluffyThemes.isThreeColumnMode(context) ||
                  room.membership != Membership.join ||
                  !displayChatDetailsColumn
              ? const SizedBox(height: double.infinity, width: 0)
              : Container(
                  width: FluffyThemes.columnWidth,
                  clipBehavior: Clip.hardEdge,
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(width: 1, color: theme.dividerColor),
                    ),
                  ),
                  child: ChatDetails(
                    roomId: roomId,
                    embeddedCloseButton: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: toggleDisplayChatDetailsColumn,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

enum AddPopupMenuActions {
  image,
  video,
  file,
  poll,
  photoCamera,
  videoCamera,
  location,
}
