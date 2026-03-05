import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/events/message.dart';
import 'package:fluffychat/pages/chat/seen_by_row.dart';
import 'package:fluffychat/pages/chat/typing_indicators.dart';
import 'package:fluffychat/utils/account_config.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';
import 'package:fluffychat/utils/platform_infos.dart';

class ChatEventList extends StatelessWidget {
  final ChatController controller;

  const ChatEventList({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final timeline = controller.timeline;

    if (timeline == null) {
      return const Center(child: CupertinoActivityIndicator());
    }
    final theme = Theme.of(context);

    final colors = [theme.secondaryBubbleColor, theme.bubbleColor];
    final quickReactions = controller.quickReactionOptions;

    final horizontalPadding = FluffyThemes.isColumnMode(context) ? 8.0 : 0.0;

    final events = timeline.events.filterByVisibleInGui(
      threadId: controller.activeThreadId,
    );
    final animateInEventIndex = controller.animateInEventIndex;

    // create a map of eventId --> index to greatly improve performance of
    // ListView's findChildIndexCallback
    final thisEventsKeyMap = <String, int>{};
    for (var i = 0; i < events.length; i++) {
      thisEventsKeyMap[events[i].eventId] = i;
    }

    // Build album grouping maps.
    // albumGroupsBySender: senderId -> (albumId -> list of events)
    // albumEventsByAnchorId: eventId of the anchor event -> all album events
    // albumContinuationIds: eventIds of non-anchor events that should be hidden
    final albumGroupsBySender = <String, Map<String, List<Event>>>{};
    final albumEventsByAnchorId = <String, List<Event>>{};
    final albumContinuationIds = <String>{};
    for (final event in events) {
      final albumId = event.content.tryGet<String>('r.trd.album_id');
      if (albumId != null) {
        final senderAlbumGroups = albumGroupsBySender.putIfAbsent(
          event.senderId,
          () => {},
        );
        senderAlbumGroups.putIfAbsent(albumId, () => []);
        senderAlbumGroups[albumId]!.add(event);
      }
    }
    for (final senderAlbumGroups in albumGroupsBySender.values) {
      for (final albumEvents in senderAlbumGroups.values) {
        if (albumEvents.length < 2) continue;
        // Events list is reversed (newest first), so the last item is the
        // oldest (displayed first visually). That's our anchor.
        final anchor = albumEvents.last;
        albumEventsByAnchorId[anchor.eventId] = albumEvents;
        for (final event in albumEvents) {
          if (event.eventId != anchor.eventId) {
            albumContinuationIds.add(event.eventId);
          }
        }
      }
    }

    final hasWallpaper =
        controller.room.client.applicationAccountConfig.wallpaperUrl != null;

    final listView = ListView.custom(
      padding: EdgeInsets.only(
        top: 16,
        bottom: 8,
        left: horizontalPadding,
        right: horizontalPadding,
      ),
      reverse: true,
      controller: controller.scrollController,
      keyboardDismissBehavior: PlatformInfos.isIOS
          ? ScrollViewKeyboardDismissBehavior.onDrag
          : ScrollViewKeyboardDismissBehavior.manual,
      childrenDelegate: SliverChildBuilderDelegate(
        (BuildContext context, int i) {
          // Footer to display typing indicator and read receipts:
          if (i == 0) {
            if (timeline.canRequestFuture) {
              return Center(
                child: TextButton.icon(
                  onPressed: timeline.isRequestingFuture
                      ? null
                      : controller.requestFuture,
                  icon: timeline.isRequestingFuture
                      ? CircularProgressIndicator.adaptive(strokeWidth: 2)
                      : const Icon(Icons.arrow_downward_outlined),
                  label: Text(L10n.of(context).loadMore),
                ),
              );
            }
            return Column(
              mainAxisSize: .min,
              children: [
                SeenByRow(event: events.first),
                TypingIndicators(controller),
              ],
            );
          }

          // Request history button or progress indicator:
          if (i == events.length + 1) {
            if (controller.activeThreadId != null ||
                !timeline.canRequestHistory) {
              return const SizedBox.shrink();
            }
            return Builder(
              builder: (context) {
                final visibleIndex = timeline.events.lastIndexWhere(
                  (event) => !event.isCollapsedState && event.isVisibleInGui,
                );
                if (visibleIndex > timeline.events.length - 50) {
                  WidgetsBinding.instance.addPostFrameCallback(
                    controller.requestHistory,
                  );
                }
                return Center(
                  child: TextButton.icon(
                    onPressed: timeline.isRequestingHistory
                        ? null
                        : controller.requestHistory,
                    icon: timeline.isRequestingHistory
                        ? CircularProgressIndicator.adaptive(strokeWidth: 2)
                        : const Icon(Icons.arrow_upward_outlined),
                    label: Text(L10n.of(context).loadMore),
                  ),
                );
              },
            );
          }
          i--;

          // The message at this index:
          final event = events[i];
          final animateIn =
              animateInEventIndex != null &&
              timeline.events.length > animateInEventIndex &&
              event == timeline.events[animateInEventIndex];

          final nextEvent = i + 1 < events.length ? events[i + 1] : null;
          final previousEvent = i > 0 ? events[i - 1] : null;

          // Collapsed state event
          final canExpand =
              event.isCollapsedState &&
              nextEvent?.isCollapsedState == true &&
              previousEvent?.isCollapsedState != true;
          final isCollapsed =
              event.isCollapsedState &&
              previousEvent?.isCollapsedState == true &&
              !controller.expandedEventIds.contains(event.eventId);

          // Album grouping
          final isAlbumContinuation = albumContinuationIds.contains(
            event.eventId,
          );
          final albumEvents = albumEventsByAnchorId[event.eventId];

          return _MessageKeyRegistrar(
            eventId: event.eventId,
            controller: controller,
            child: AutoScrollTag(
              key: ValueKey(event.eventId),
              index: i,
              controller: controller.scrollController,
              child: Message(
                event,
                bigEmojis: controller.bigEmojis,
                animateIn: animateIn,
                resetAnimateIn: () {
                  controller.animateInEventIndex = null;
                },
                onSwipe: () => controller.replyAction(replyTo: event),
                onInfoTab: controller.showEventInfo,
                onMention: () => controller.sendController.text +=
                    '${event.senderFromMemoryOrFallback.mention} ',
                onOpenContextMenu: controller.openMessageContextMenu,
                onSendReaction: controller.sendReactionAction,
                onSendCustomReaction: controller.sendCustomReactionAction,
                highlightMarker:
                    controller.scrollToEventIdMarker == event.eventId,
                onSelect: controller.onSelectMessage,
                scrollToEventId: controller.scrollToEventId,
                longPressSelect: controller.selectedEvents.isNotEmpty,
                selected: controller.selectedEvents.any(
                  (e) => e.eventId == event.eventId,
                ),
                singleSelected:
                    controller.selectedEvents.singleOrNull?.eventId ==
                    event.eventId,
                onEdit: controller.editSelectedEventAction,
                timeline: timeline,
                displayReadMarker:
                    i > 0 && controller.readMarkerEventId == event.eventId,
                nextEvent: nextEvent,
                previousEvent: previousEvent,
                wallpaperMode: hasWallpaper,
                scrollController: controller.scrollController,
                colors: colors,
                isCollapsed: isCollapsed,
                enterThread: controller.activeThreadId == null
                    ? controller.enterThread
                    : null,
                onExpand: canExpand
                    ? () => controller.expandEventsFrom(
                        event,
                        !controller.expandedEventIds.contains(event.eventId),
                      )
                    : null,
                albumEvents: albumEvents,
                isAlbumContinuation: isAlbumContinuation,
                quickReactions: quickReactions,
              ),
            ),
          );
        },
        childCount: events.length + 2,
        findChildIndexCallback: (key) =>
            controller.findChildIndexCallback(key, thisEventsKeyMap),
      ),
    );

    return listView;
  }
}

class _MessageKeyRegistrar extends StatefulWidget {
  final String eventId;
  final ChatController controller;
  final Widget child;

  const _MessageKeyRegistrar({
    required this.eventId,
    required this.controller,
    required this.child,
  });

  @override
  State<_MessageKeyRegistrar> createState() => _MessageKeyRegistrarState();
}

class _MessageKeyRegistrarState extends State<_MessageKeyRegistrar> {
  final GlobalKey _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    widget.controller.registerMessageKey(widget.eventId, _key);
  }

  @override
  void didUpdateWidget(covariant _MessageKeyRegistrar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.eventId != widget.eventId) {
      oldWidget.controller.unregisterMessageKey(oldWidget.eventId);
      widget.controller.registerMessageKey(widget.eventId, _key);
    }
  }

  @override
  void dispose() {
    widget.controller.unregisterMessageKey(widget.eventId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(key: _key, child: widget.child);
  }
}
