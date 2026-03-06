import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';
import 'package:universal_html/html.dart' as html;
import 'package:video_player/video_player.dart';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/client_download_content_extension.dart';
import 'package:fluffychat/utils/custom_emoji_metadata.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/mxc_image.dart';

class CustomEmojiMedia extends StatefulWidget {
  final Client client;
  final Uri fallbackMxc;
  final CustomEmojiMeta metadata;
  final String? fallbackEmoji;
  final double width;
  final double height;
  final BoxFit fit;
  final bool? autoplay;
  final bool isThumbnail;
  final BorderRadius borderRadius;

  const CustomEmojiMedia({
    super.key,
    required this.client,
    required this.fallbackMxc,
    required this.metadata,
    required this.width,
    required this.height,
    this.fallbackEmoji,
    this.fit = BoxFit.contain,
    this.autoplay,
    this.isThumbnail = false,
    this.borderRadius = BorderRadius.zero,
  });

  @override
  State<CustomEmojiMedia> createState() => _CustomEmojiMediaState();
}

class _CustomEmojiMediaState extends State<CustomEmojiMedia> {
  int _sourceIndex = 0;

  List<CustomEmojiMediaSource> get _sources {
    final fromMeta = widget.metadata.media.prioritizedSources();
    if (fromMeta.isNotEmpty) {
      return fromMeta;
    }
    return [
      CustomEmojiMediaSource(
        kind: CustomEmojiMediaKind.image,
        url: widget.fallbackMxc,
      ),
    ];
  }

  bool get _autoplay => widget.autoplay ?? AppSettings.autoplayImages.value;

  bool _isSupported(CustomEmojiMediaKind kind) {
    if (kind == CustomEmojiMediaKind.webm || kind == CustomEmojiMediaKind.mp4) {
      return PlatformInfos.supportsVideoPlayer;
    }
    return true;
  }

  void _loadNextSource() {
    if (!mounted) return;
    setState(() {
      _sourceIndex++;
    });
  }

  @override
  Widget build(BuildContext context) {
    var anySkippedByPlatform = false;
    for (var i = _sourceIndex; i < _sources.length; i++) {
      final source = _sources[i];
      if (!_isSupported(source.kind)) {
        anySkippedByPlatform = true;
        continue;
      }

      final child = switch (source.kind) {
        CustomEmojiMediaKind.image => MxcImage(
          uri: source.url,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          animated: _autoplay,
          isThumbnail: widget.isThumbnail,
          borderRadius: widget.borderRadius,
          client: widget.client,
        ),
        CustomEmojiMediaKind.webm ||
        CustomEmojiMediaKind.mp4 => _LoopingVideoEmoji(
          client: widget.client,
          source: source,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          loop: widget.metadata.media.loop,
          autoplay: _autoplay,
          borderRadius: widget.borderRadius,
          onError: _loadNextSource,
        ),
        CustomEmojiMediaKind.lottieJson ||
        CustomEmojiMediaKind.lottieTgs => _LottieEmoji(
          client: widget.client,
          source: source,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          loop: widget.metadata.media.loop,
          autoplay: _autoplay,
          borderRadius: widget.borderRadius,
          onError: _loadNextSource,
        ),
      };

      return SizedBox(width: widget.width, height: widget.height, child: child);
    }

    // When sources were skipped because the platform lacks video support,
    // show a server-generated thumbnail instead of a text fallback.
    if (anySkippedByPlatform) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: MxcImage(
          uri: widget.fallbackMxc,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          isThumbnail: true,
          borderRadius: widget.borderRadius,
          client: widget.client,
        ),
      );
    }

    return _EmojiFallback(
      width: widget.width,
      height: widget.height,
      emoji: widget.fallbackEmoji,
    );
  }
}

class _LoopingVideoEmoji extends StatefulWidget {
  final Client client;
  final CustomEmojiMediaSource source;
  final double width;
  final double height;
  final BoxFit fit;
  final bool loop;
  final bool autoplay;
  final BorderRadius borderRadius;
  final VoidCallback onError;

  const _LoopingVideoEmoji({
    required this.client,
    required this.source,
    required this.width,
    required this.height,
    required this.fit,
    required this.loop,
    required this.autoplay,
    required this.borderRadius,
    required this.onError,
  });

  @override
  State<_LoopingVideoEmoji> createState() => _LoopingVideoEmojiState();
}

class _LoopingVideoEmojiState extends State<_LoopingVideoEmoji> {
  VideoPlayerController? _controller;
  String? _webObjectUrl;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _LoopingVideoEmoji oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source.url != widget.source.url ||
        oldWidget.autoplay != widget.autoplay ||
        oldWidget.loop != widget.loop) {
      _disposeController();
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final bytes = await widget.client.downloadMxcCached(
        widget.source.url,
        isThumbnail: false,
      );

      late VideoPlayerController controller;
      if (kIsWeb) {
        final blob = html.Blob([bytes], widget.source.mimetype ?? 'video/mp4');
        _webObjectUrl = html.Url.createObjectUrlFromBlob(blob);
        controller = VideoPlayerController.networkUrl(
          Uri.parse(_webObjectUrl!),
        );
      } else {
        final tempDir = await getTemporaryDirectory();
        final ext = widget.source.kind == CustomEmojiMediaKind.webm
            ? 'webm'
            : 'mp4';
        final file = File(
          '${tempDir.path}/emoji_${widget.source.url.pathSegments.last}.$ext',
        );
        if (await file.exists() == false) {
          await file.writeAsBytes(bytes);
        }
        controller = VideoPlayerController.file(file);
      }

      await controller.initialize();
      // Stickers/custom emoji media must stay silent even if the container
      // carries an audio stream.
      await controller.setVolume(0);
      await controller.setLooping(widget.loop);
      if (widget.autoplay) {
        await controller.play();
        await controller.setVolume(0);
      }

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
      });
    } catch (_) {
      widget.onError();
    }
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  Future<void> _disposeController() async {
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
    final webObjectUrl = _webObjectUrl;
    if (webObjectUrl != null) {
      html.Url.revokeObjectUrl(webObjectUrl);
      _webObjectUrl = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }

    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: FittedBox(
        fit: widget.fit,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: max(controller.value.size.width, 1),
          height: max(controller.value.size.height, 1),
          child: VideoPlayer(controller),
        ),
      ),
    );
  }
}

class _LottieEmoji extends StatefulWidget {
  final Client client;
  final CustomEmojiMediaSource source;
  final double width;
  final double height;
  final BoxFit fit;
  final bool loop;
  final bool autoplay;
  final BorderRadius borderRadius;
  final VoidCallback onError;

  const _LottieEmoji({
    required this.client,
    required this.source,
    required this.width,
    required this.height,
    required this.fit,
    required this.loop,
    required this.autoplay,
    required this.borderRadius,
    required this.onError,
  });

  @override
  State<_LottieEmoji> createState() => _LottieEmojiState();
}

class _LottieEmojiState extends State<_LottieEmoji> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _LottieEmoji oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source.url != widget.source.url) {
      _bytes = null;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final bytes = await widget.client.downloadMxcCached(
        widget.source.url,
        isThumbnail: false,
      );

      final payload = widget.source.kind == CustomEmojiMediaKind.lottieTgs
          ? Uint8List.fromList(GZipDecoder().decodeBytes(bytes))
          : bytes;

      if (!mounted) return;
      setState(() {
        _bytes = payload;
      });
    } catch (_) {
      widget.onError();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes == null) {
      return const SizedBox.shrink();
    }

    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: Lottie.memory(
        bytes,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        repeat: widget.loop,
        animate: widget.autoplay,
        errorBuilder: (context, error, stackTrace) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onError();
          });
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

class _EmojiFallback extends StatelessWidget {
  final double width;
  final double height;
  final String? emoji;

  const _EmojiFallback({
    required this.width,
    required this.height,
    required this.emoji,
  });

  @override
  Widget build(BuildContext context) {
    final renderEmoji = (emoji == null || emoji!.isEmpty) ? '�' : emoji!;
    return SizedBox(
      width: width,
      height: height,
      child: Center(
        child: Text(
          renderEmoji,
          style: TextStyle(fontSize: min(width, height) * 0.9),
          maxLines: 1,
        ),
      ),
    );
  }
}
