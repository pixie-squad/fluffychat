import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/profile_card_fields.dart';
import 'package:fluffychat/widgets/mxc_image.dart';

class ProfileEmojiStatusIcon extends StatefulWidget {
  final String userId;
  final Client client;
  final double size;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final String? tooltip;
  final BorderRadius? borderRadius;
  final bool showPlaceholder;
  final Widget? placeholder;

  const ProfileEmojiStatusIcon({
    required this.userId,
    required this.client,
    this.size = 16,
    this.padding = EdgeInsets.zero,
    this.onTap,
    this.tooltip,
    this.borderRadius,
    this.showPlaceholder = false,
    this.placeholder,
    super.key,
  });

  @override
  State<ProfileEmojiStatusIcon> createState() => _ProfileEmojiStatusIconState();
}

class _ProfileEmojiStatusIconState extends State<ProfileEmojiStatusIcon> {
  late Future<Uri?> _future;

  @override
  void initState() {
    super.initState();
    _future = profileEmojiStatusCache.get(widget.client, widget.userId);
  }

  @override
  void didUpdateWidget(ProfileEmojiStatusIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId || oldWidget.client != widget.client) {
      _future = profileEmojiStatusCache.get(widget.client, widget.userId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final borderRadius =
        widget.borderRadius ?? BorderRadius.circular(widget.size / 2);

    return FutureBuilder<Uri?>(
      future: _future,
      initialData: profileEmojiStatusCache.getCached(widget.userId),
      builder: (context, snapshot) {
        final emojiUri = snapshot.data;
        if (emojiUri == null && !widget.showPlaceholder) {
          return const SizedBox.shrink();
        }

        final child = SizedBox(
          width: widget.size,
          height: widget.size,
          child: emojiUri == null
              ? widget.placeholder ?? const SizedBox.shrink()
              : ClipRRect(
                  borderRadius: borderRadius,
                  child: MxcImage(
                    uri: emojiUri,
                    width: widget.size,
                    height: widget.size,
                    fit: BoxFit.cover,
                    isThumbnail: true,
                  ),
                ),
        );

        final paddedChild = Padding(padding: widget.padding, child: child);
        Widget output = paddedChild;
        if (widget.onTap != null) {
          output = Material(
            color: Colors.transparent,
            borderRadius: borderRadius,
            child: InkWell(
              borderRadius: borderRadius,
              onTap: widget.onTap,
              child: paddedChild,
            ),
          );
        }

        final tooltipText = widget.tooltip ?? L10n.of(context).profileEmojiStatus;
        return Tooltip(message: tooltipText, child: output);
      },
    );
  }
}
