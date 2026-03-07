import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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

class CustomEmojiAnimatedRenderBudget {
  static int get maxActive {
    if (_maxActiveOverrideForTests != null) return _maxActiveOverrideForTests!;
    if (PlatformInfos.isAndroid) return 30;
    if (PlatformInfos.isIOS) return 45;
    if (PlatformInfos.isWeb) return 45;
    return 75; // desktop
  }

  static final Set<Object> _owners = <Object>{};

  CustomEmojiAnimatedRenderBudget._();

  static bool tryAcquire(Object owner) {
    if (_owners.contains(owner)) return true;
    if (_owners.length >= maxActive) return false;
    _owners.add(owner);
    return true;
  }

  static void release(Object owner) {
    _owners.remove(owner);
  }

  @visibleForTesting
  static int get activeCountForTests => _owners.length;

  @visibleForTesting
  static int? _maxActiveOverrideForTests;

  @visibleForTesting
  static void resetForTests({int? maxActiveOverride}) {
    _owners.clear();
    _maxActiveOverrideForTests = maxActiveOverride;
  }
}

class _LottieCompositionCache {
  static final Map<String, LottieComposition> _cache = {};
  static final Map<String, Future<LottieComposition>> _pending = {};

  static Future<LottieComposition> getOrParse(
    String key,
    Uint8List bytes,
  ) async {
    if (_cache[key] case final cached?) return cached;
    if (_pending[key] case final pending?) return pending;
    final future = Future(() => LottieComposition.parseJsonBytes(bytes));
    _pending[key] = future;
    try {
      final comp = await future;
      _cache[key] = comp;
      return comp;
    } finally {
      _pending.remove(key);
    }
  }

  @visibleForTesting
  static void resetForTests() {
    _cache.clear();
    _pending.clear();
  }
}

class AnimationJankMonitor {
  static final instance = AnimationJankMonitor._();
  AnimationJankMonitor._();

  bool _listening = false;

  /// 1.0 = full speed, 0.75/0.5/0.25 = degraded, 0.0 = stopped.
  double _scale = 1.0;
  double get scale => _scale;

  DateTime _lastDegradeTime = DateTime(2000);

  /// Only frames slower than this count as jank. 50 ms ≈ <20 fps
  static const _jankThresholdMs = 50;

  /// Rolling window size
  static const _windowSize = 60;

  /// Degrade when more than N of the window is janky
  static const _degradeRatio = 0.5;

  /// Recover when less than N % of the window is janky.
  static const _recoverRatio = 0.10;

  /// Cooldown between degradation / recovery steps.
  static const _lingerDuration = Duration(seconds: 5);

  static const _step = 0.25;

  final _window = List<bool>.filled(_windowSize, false);
  int _windowIndex = 0;
  int _jankCount = 0;
  final Map<AnimationController, bool> _tracked = {};

  void ensureListening() {
    if (_listening) return;
    _listening = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void track(AnimationController controller, {required bool loop}) {
    _tracked[controller] = loop;
  }

  void untrack(AnimationController controller) {
    _tracked.remove(controller);
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      final isJank = timing.totalSpan.inMilliseconds > _jankThresholdMs;
      if (_window[_windowIndex]) _jankCount--;
      _window[_windowIndex] = isJank;
      if (isJank) _jankCount++;
      _windowIndex = (_windowIndex + 1) % _windowSize;
    }

    final ratio = _jankCount / _windowSize;
    final now = DateTime.now();
    final cooldownElapsed = now.difference(_lastDegradeTime) >= _lingerDuration;

    if (ratio >= _degradeRatio && _scale > 0 && cooldownElapsed) {
      _scale = (_scale - _step).clamp(0.0, 1.0);
      _lastDegradeTime = now;
      if (_scale <= 0) _pauseAll();
    } else if (ratio <= _recoverRatio && _scale < 1.0 && cooldownElapsed) {
      final wasStopped = _scale <= 0;
      _scale = (_scale + _step).clamp(0.0, 1.0);
      _lastDegradeTime = now;
      if (wasStopped && _scale > 0) _resumeAll();
    }
  }

  void _pauseAll() {
    for (final controller in _tracked.keys) {
      if (controller.isAnimating) controller.stop(canceled: false);
    }
  }

  void _resumeAll() {
    for (final entry in _tracked.entries) {
      if (entry.key.isAnimating) continue;
      if (entry.value) {
        entry.key.repeat();
      } else {
        entry.key.forward();
      }
    }
  }

  FrameRate adaptRate(FrameRate base) {
    if (_scale >= 1.0) return base;
    final fps =
        (base.framesPerSecond * _scale).clamp(1.0, base.framesPerSecond);
    return FrameRate(fps);
  }

  @visibleForTesting
  static void resetForTests() {
    instance._scale = 1.0;
    instance._jankCount = 0;
    instance._windowIndex = 0;
    instance._window.fillRange(0, _windowSize, false);
    instance._lastDegradeTime = DateTime(2000);
    instance._tracked.clear();
    instance._listening = false;
  }
}

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

  bool _isAnimatedSource(CustomEmojiMediaKind kind) =>
      kind == CustomEmojiMediaKind.webm ||
      kind == CustomEmojiMediaKind.mp4 ||
      kind == CustomEmojiMediaKind.lottieJson ||
      kind == CustomEmojiMediaKind.lottieTgs;

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

  void _releaseAnimatedRenderSlot() {
    CustomEmojiAnimatedRenderBudget.release(this);
  }

  @override
  void dispose() {
    _releaseAnimatedRenderSlot();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var anySkippedByPlatform = false;
    var anySkippedByBudget = false;
    CustomEmojiMediaSource? selectedSource;
    for (var i = _sourceIndex; i < _sources.length; i++) {
      final source = _sources[i];
      if (!_isSupported(source.kind)) {
        anySkippedByPlatform = true;
        continue;
      }

      final needsAnimatedSlot = _autoplay && _isAnimatedSource(source.kind);
      if (needsAnimatedSlot &&
          !CustomEmojiAnimatedRenderBudget.tryAcquire(this)) {
        anySkippedByBudget = true;
        continue;
      }

      selectedSource = source;
      if (!needsAnimatedSlot) {
        _releaseAnimatedRenderSlot();
      }
      break;
    }

    if (selectedSource != null) {
      final child = switch (selectedSource.kind) {
        CustomEmojiMediaKind.image => MxcImage(
          uri: selectedSource.url,
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
          source: selectedSource,
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
          source: selectedSource,
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

    _releaseAnimatedRenderSlot();

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

    if (anySkippedByBudget) {
      return _EmojiFallback(
        width: widget.width,
        height: widget.height,
        emoji: widget.fallbackEmoji,
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tickerEnabled = TickerMode.of(context);
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (!tickerEnabled && controller.value.isPlaying) {
      controller.pause();
    } else if (tickerEnabled && widget.autoplay && !controller.value.isPlaying) {
      controller.play();
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

class _LottieEmojiState extends State<_LottieEmoji>
    with TickerProviderStateMixin {
  LottieComposition? _composition;
  AnimationController? _controller;

  static FrameRate get _emojiFrameRate =>
      PlatformInfos.isMobile ? const FrameRate(15) : const FrameRate(24);

  /// Staggers animation start so not all emojis rasterize frame 0
  /// simultaneously. Spreads warmup cost across multiple display frames.
  static int _staggerCounter = 0;

  @override
  void initState() {
    super.initState();
    AnimationJankMonitor.instance.ensureListening();
    _load();
  }

  @override
  void didUpdateWidget(covariant _LottieEmoji oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source.url != widget.source.url) {
      _disposeController();
      _composition = null;
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

      final composition = await _LottieCompositionCache.getOrParse(
        widget.source.url.toString(),
        payload,
      );

      if (!mounted) return;

      final monitor = AnimationJankMonitor.instance;
      final controller = AnimationController(
        vsync: this,
        duration: composition.duration,
      );
      monitor.track(controller, loop: widget.loop);

      // Only start if the jank monitor hasn't fully throttled animations.
      if (widget.autoplay && monitor.scale > 0) {
        // Stagger start offset so rasterization warmup is spread across
        // multiple display frames instead of all hitting frame 0 together.
        final offset = (_staggerCounter++ % 7) / 7.0;
        if (widget.loop) {
          // Set value BEFORE repeat — value setter calls stop() internally.
          controller.value = offset;
          controller.repeat();
        } else {
          controller.forward(from: offset);
        }
      }

      setState(() {
        _composition = composition;
        _controller = controller;
      });
    } catch (_) {
      widget.onError();
    }
  }

  void _disposeController() {
    final controller = _controller;
    if (controller != null) {
      AnimationJankMonitor.instance.untrack(controller);
      controller.dispose();
    }
    _controller = null;
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final composition = _composition;
    final controller = _controller;
    if (composition == null || controller == null) {
      return const SizedBox.shrink();
    }

    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: Lottie(
        composition: composition,
        controller: controller,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        frameRate: AnimationJankMonitor.instance.adaptRate(_emojiFrameRate),
        renderCache: RenderCache.raster,
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
