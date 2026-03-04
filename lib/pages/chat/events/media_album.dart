import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/pages/image_viewer/image_viewer.dart';
import 'package:fluffychat/widgets/blur_hash.dart';
import 'package:fluffychat/widgets/mxc_image.dart';

class MediaAlbum extends StatelessWidget {
  final List<Event> events;
  final Timeline? timeline;
  final BorderRadius borderRadius;

  const MediaAlbum({
    required this.events,
    required this.borderRadius,
    this.timeline,
    super.key,
  });

  static const double _maxWidth = 300.0;
  static const double _gap = 2.0;

  int get _crossAxisCount {
    final count = events.length;
    if (count <= 2) return 2;
    return 3;
  }

  @override
  Widget build(BuildContext context) {
    final visibleEvents =
        events.where((e) => !e.redacted).toList();

    if (visibleEvents.isEmpty) return const SizedBox.shrink();
    if (visibleEvents.length == 1) {
      return _AlbumItem(
        event: visibleEvents.first,
        timeline: timeline,
        borderRadius: borderRadius,
        width: _maxWidth,
        height: _maxWidth,
      );
    }

    final crossAxisCount = _crossAxisCount;
    final rows = (visibleEvents.length / crossAxisCount).ceil();
    final totalGapWidth = _gap * (crossAxisCount - 1);
    final cellSize = (_maxWidth - totalGapWidth) / crossAxisCount;
    final totalHeight = rows * cellSize + (rows - 1) * _gap;

    return Material(
      clipBehavior: Clip.hardEdge,
      borderRadius: borderRadius,
      color: Colors.transparent,
      child: SizedBox(
        width: _maxWidth,
        height: totalHeight,
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: _gap,
            crossAxisSpacing: _gap,
          ),
          itemCount: visibleEvents.length,
          itemBuilder: (context, index) {
            final event = visibleEvents[index];
            // Calculate corner radii: only the outer corners of the grid get
            // the album's border radius, inner corners are sharp.
            final isTop = index < crossAxisCount;
            final isBottom =
                index >= visibleEvents.length - crossAxisCount ||
                index >=
                    (rows - 1) * crossAxisCount;
            final isLeft = index % crossAxisCount == 0;
            final isRight = index % crossAxisCount == crossAxisCount - 1 ||
                index == visibleEvents.length - 1;

            final itemRadius = BorderRadius.only(
              topLeft: isTop && isLeft
                  ? borderRadius.topLeft
                  : Radius.zero,
              topRight: isTop && isRight
                  ? borderRadius.topRight
                  : Radius.zero,
              bottomLeft: isBottom && isLeft
                  ? borderRadius.bottomLeft
                  : Radius.zero,
              bottomRight: isBottom && isRight
                  ? borderRadius.bottomRight
                  : Radius.zero,
            );

            return _AlbumItem(
              event: event,
              timeline: timeline,
              borderRadius: itemRadius,
              width: cellSize,
              height: cellSize,
            );
          },
        ),
      ),
    );
  }
}

class _AlbumItem extends StatelessWidget {
  final Event event;
  final Timeline? timeline;
  final BorderRadius borderRadius;
  final double width;
  final double height;

  const _AlbumItem({
    required this.event,
    required this.borderRadius,
    required this.width,
    required this.height,
    this.timeline,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isVideo = event.messageType == MessageTypes.Video;

    final blurHashString =
        event.infoMap.tryGet<String>('xyz.amorgan.blurhash') ??
        'LEHV6nWB2yk8pyo0adR*.7kCMdnj';

    return Material(
      clipBehavior: Clip.hardEdge,
      borderRadius: borderRadius,
      color: theme.colorScheme.surfaceContainerHigh,
      child: InkWell(
        borderRadius: borderRadius,
        onTap: () => showDialog(
          context: context,
          builder: (_) => ImageViewer(
            event,
            timeline: timeline,
            outerContext: context,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            MxcImage(
              event: event,
              width: width,
              height: height,
              fit: BoxFit.cover,
              isThumbnail: true,
              placeholder: (_) => BlurHash(
                blurhash: blurHashString,
                width: width,
                height: height,
                fit: BoxFit.cover,
              ),
            ),
            if (isVideo)
              Center(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(8),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
