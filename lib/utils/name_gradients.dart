import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

const String nameGradientField = 'r.trd.name_gradient';
const String nameGradientAnimatedField = 'r.trd.name_gradient_animated';

const List<List<Color>> nameGradients = [
  [Color(0xFFFF6B6B), Color(0xFFFF8E53)], // Sunset
  [Color(0xFF667eea), Color(0xFF764ba2)], // Purple haze
  [Color(0xFF00c6ff), Color(0xFF0072ff)], // Ocean
  [Color(0xFFf857a6), Color(0xFFFF5858)], // Pink fire
  [Color(0xFF11998e), Color(0xFF38ef7d)], // Emerald
  [Color(0xFFfc5c7d), Color(0xFF6a82fb)], // Pink blue
  [Color(0xFFf2994a), Color(0xFFf2c94c)], // Gold
  [Color(0xFF8E2DE2), Color(0xFF4A00E0)], // Violet
  [Color(0xFF56CCF2), Color(0xFF2F80ED)], // Sky
  [Color(0xFFFF512F), Color(0xFFDD2476)], // Blood orange
  [Color(0xFFED4264), Color(0xFFFFEDBC)], // Rose gold
  [Color(0xFFee0979), Color(0xFFff6a00)], // Hot sunset
];

/// Result returned from [showGradientPicker].
/// [colors] is empty to signal "remove gradient", non-empty for a chosen gradient.
class GradientPickerResult {
  final List<Color> colors;
  final bool animated;

  const GradientPickerResult({required this.colors, this.animated = false});
}

class _GradientCache {
  final Map<String, List<Color>?> _colorCache = {};
  final Map<String, bool> _animatedCache = {};

  bool has(String userId) => _colorCache.containsKey(userId);

  (List<Color>?, bool) getCached(String userId) =>
      (_colorCache[userId], _animatedCache[userId] ?? false);

  Future<(List<Color>?, bool)> get(Client client, String userId) async {
    if (_colorCache.containsKey(userId)) {
      return (_colorCache[userId], _animatedCache[userId] ?? false);
    }
    try {
      final data = await client.getProfileField(userId, nameGradientField);
      final raw = data[nameGradientField];
      List<Color>? colors;
      var animated = false;
      if (raw is Map) {
        // New format: {'c': [argb,...], 'a': true}
        final c = raw['c'];
        if (c is List) {
          colors = c.map((v) => Color((v as num).toInt())).toList();
        }
        animated = raw['a'] == true;
      } else if (raw is List) {
        colors = raw.map((v) => Color((v as num).toInt())).toList();
        // Fallback: check separate key (servers that preserve extra keys)
        animated = data[nameGradientAnimatedField] == true;
      } else if (raw is num) {
        // Legacy preset index
        final idx = raw.toInt();
        if (idx >= 0 && idx < nameGradients.length) {
          colors = nameGradients[idx];
        }
      }
      _colorCache[userId] = colors;
      _animatedCache[userId] = animated;
      return (colors, animated);
    } catch (_) {
      _colorCache[userId] = null;
      _animatedCache[userId] = false;
      return (null, false);
    }
  }

  void invalidate(String userId) {
    _colorCache.remove(userId);
    _animatedCache.remove(userId);
  }
}

final gradientCache = _GradientCache();

/// Builds a [LinearGradient] that scrolls continuously for animation.
///
/// Creates a seamless loop by appending the first color, then shifts the
/// gradient via [begin]/[end] alignment using [TileMode.repeated].
/// [t] is the animation value from 0.0 to 1.0 (one full cycle).
LinearGradient _scrollingGradient(List<Color> colors, double t) {
  final loop = [...colors, colors.first];
  // Pattern width in alignment units (widget spans 2.0 from -1 to 1).
  final pw = 2.0 * (loop.length - 1) / (colors.length - 1);
  final offset = t * pw;
  return LinearGradient(
    colors: loop,
    begin: Alignment(-1.0 + offset, 0),
    end: Alignment(-1.0 + pw + offset, 0),
    tileMode: TileMode.repeated,
  );
}

class GradientDisplayName extends StatefulWidget {
  final String userId;
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final Client client;
  final ValueChanged<List<Color>?>? onGradientColorsChanged;

  const GradientDisplayName({
    required this.userId,
    required this.text,
    required this.client,
    this.style,
    this.maxLines,
    this.overflow,
    this.onGradientColorsChanged,
    super.key,
  });

  @override
  State<GradientDisplayName> createState() => _GradientDisplayNameState();
}

class _GradientDisplayNameState extends State<GradientDisplayName>
    with SingleTickerProviderStateMixin {
  List<Color>? _colors;
  bool _animated = false;
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    );
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(GradientDisplayName old) {
    super.didUpdateWidget(old);
    if (old.userId != widget.userId) {
      _load();
    } else if (old.onGradientColorsChanged != widget.onGradientColorsChanged) {
      _notifyGradientColorsChanged(_colors);
    }
  }

  void _updateAnimation() {
    final shouldAnimate =
        _animated && _colors != null && (_colors?.length ?? 0) >= 2;
    if (shouldAnimate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!shouldAnimate && _controller.isAnimating) {
      _controller.stop();
    }
  }

  void _load() {
    if (gradientCache.has(widget.userId)) {
      final (colors, animated) = gradientCache.getCached(widget.userId);
      _colors = colors;
      _animated = animated;
      _updateAnimation();
      _notifyGradientColorsChanged(colors);
    } else {
      gradientCache.get(widget.client, widget.userId).then((result) {
        if (!mounted) return;
        final (colors, animated) = result;
        setState(() {
          _colors = colors;
          _animated = animated;
        });
        _updateAnimation();
        _notifyGradientColorsChanged(colors);
      });
    }
  }

  void _notifyGradientColorsChanged(List<Color>? colors) {
    final callback = widget.onGradientColorsChanged;
    if (callback == null) return;
    final value = colors == null || colors.length < 2
        ? null
        : List<Color>.unmodifiable(colors);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.onGradientColorsChanged != callback) return;
      callback(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Text(
      widget.text,
      style: widget.style,
      maxLines: widget.maxLines,
      overflow: widget.overflow,
    );
    final colors = _colors;
    if (colors == null || colors.length < 2) return text;

    if (!_animated) {
      return ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) =>
            LinearGradient(colors: colors).createShader(bounds),
        child: text,
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) =>
              _scrollingGradient(colors, _controller.value)
                  .createShader(bounds),
          child: child,
        );
      },
      child: text,
    );
  }
}

/// Returns `null` if dismissed, a [GradientPickerResult] with empty [colors] to
/// clear, or a [GradientPickerResult] with the chosen colors (and animated flag).
Future<GradientPickerResult?> showGradientPicker(BuildContext context) {
  return showDialog<GradientPickerResult>(
    context: context,
    builder: (context) => const _GradientPickerDialog(),
  );
}

class _GradientPickerDialog extends StatefulWidget {
  const _GradientPickerDialog();

  @override
  State<_GradientPickerDialog> createState() => _GradientPickerDialogState();
}

class _GradientPickerDialogState extends State<_GradientPickerDialog> {
  bool _customMode = false;
  final List<Color> _colors = [const Color(0xFFFF1744), const Color(0xFF448AFF)];
  int _selectedStop = 0;
  bool _animated = false;

  static const _palette = [
    Color(0xFFFF1744),
    Color(0xFFFF4081),
    Color(0xFFE040FB),
    Color(0xFF7C4DFF),
    Color(0xFF536DFE),
    Color(0xFF448AFF),
    Color(0xFF40C4FF),
    Color(0xFF18FFFF),
    Color(0xFF64FFDA),
    Color(0xFF69F0AE),
    Color(0xFFB2FF59),
    Color(0xFFEEFF41),
    Color(0xFFFFFF00),
    Color(0xFFFFD740),
    Color(0xFFFFAB40),
    Color(0xFFFF6E40),
    Color(0xFF795548),
    Color(0xFF9E9E9E),
    Color(0xFFFFFFFF),
    Color(0xFF000000),
  ];

  @override
  Widget build(BuildContext context) {
    return _customMode ? _buildCustom() : _buildPresets();
  }

  Widget _buildAnimatedSwitch() => SwitchListTile.adaptive(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        title: const Text('Animate'), // TODO: l10n
        value: _animated,
        onChanged: (v) => setState(() => _animated = v),
      );

  Widget _buildPresets() {
    final presetColors = _colors;
    return AlertDialog(
      title: const Text('Name gradient'), // TODO: l10n
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                label: const Text('None'),
                onPressed: () => Navigator.pop(
                  context,
                  const GradientPickerResult(colors: []),
                ),
              ),
              ActionChip(
                label: const Text('Custom'),
                onPressed: () => setState(() => _customMode = true),
              ),
              for (var i = 0; i < nameGradients.length; i++)
                InkWell(
                  onTap: () => Navigator.pop(
                    context,
                    GradientPickerResult(
                      colors: nameGradients[i],
                      animated: _animated,
                    ),
                  ),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 48,
                    height: 32,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: LinearGradient(colors: nameGradients[i]),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _buildAnimatedPreview(presetColors),
          _buildAnimatedSwitch(),
        ],
      ),
    );
  }

  Widget _buildAnimatedPreview(List<Color> colors) {
    if (!_animated || colors.length < 2) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: _AnimatedGradientPreview(colors: colors),
    );
  }

  Widget _buildCustom() {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => setState(() => _customMode = false),
          ),
          const Text('Custom gradient'), // TODO: l10n
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _animated
              ? _AnimatedGradientPreview(colors: _colors)
              : Container(
                  height: 32,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    gradient: LinearGradient(colors: _colors),
                  ),
                ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < _colors.length; i++)
                GestureDetector(
                  onTap: () => setState(() => _selectedStop = i),
                  child: Container(
                    width: 32,
                    height: 32,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _colors[i],
                      border: Border.all(
                        color: i == _selectedStop
                            ? theme.colorScheme.primary
                            : theme.dividerColor,
                        width: i == _selectedStop ? 3 : 1,
                      ),
                    ),
                  ),
                ),
              if (_colors.length < 6)
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, size: 20),
                  onPressed: () => setState(() {
                    _colors.add(const Color(0xFFFFFFFF));
                    _selectedStop = _colors.length - 1;
                  }),
                ),
              if (_colors.length > 2)
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                  onPressed: () => setState(() {
                    _colors.removeAt(_selectedStop);
                    if (_selectedStop >= _colors.length) {
                      _selectedStop = _colors.length - 1;
                    }
                  }),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _buildAnimatedSwitch(),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final color in _palette)
                GestureDetector(
                  onTap: () =>
                      setState(() => _colors[_selectedStop] = color),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color,
                      border: Border.all(color: theme.dividerColor),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            GradientPickerResult(
              colors: List<Color>.from(_colors),
              animated: _animated,
            ),
          ),
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    );
  }
}

/// Small animated gradient preview strip shown in the picker when animate is on.
class _AnimatedGradientPreview extends StatefulWidget {
  final List<Color> colors;

  const _AnimatedGradientPreview({required this.colors});


  @override
  State<_AnimatedGradientPreview> createState() =>
      _AnimatedGradientPreviewState();
}

class _AnimatedGradientPreviewState extends State<_AnimatedGradientPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          height: 32,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            gradient: _scrollingGradient(widget.colors, _controller.value),
          ),
        );
      },
    );
  }
}

