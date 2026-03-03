import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

const String nameGradientField = 'r.trd.name_gradient';

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

class _GradientCache {
  final Map<String, List<Color>?> _cache = {};

  bool has(String userId) => _cache.containsKey(userId);

  List<Color>? getCached(String userId) => _cache[userId];

  Future<List<Color>?> get(Client client, String userId) async {
    if (_cache.containsKey(userId)) return _cache[userId];
    try {
      final data = await client.getProfileField(userId, nameGradientField);
      final raw = data[nameGradientField];
      List<Color>? colors;
      if (raw is List) {
        colors = raw.map((v) => Color((v as num).toInt())).toList();
      } else if (raw is num) {
        // Legacy preset index
        final idx = raw.toInt();
        if (idx >= 0 && idx < nameGradients.length) {
          colors = nameGradients[idx];
        }
      }
      _cache[userId] = colors;
      return colors;
    } catch (_) {
      _cache[userId] = null;
      return null;
    }
  }

  void invalidate(String userId) => _cache.remove(userId);
}

final gradientCache = _GradientCache();

class GradientDisplayName extends StatefulWidget {
  final String userId;
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final Client client;

  const GradientDisplayName({
    required this.userId,
    required this.text,
    required this.client,
    this.style,
    this.maxLines,
    this.overflow,
    super.key,
  });

  @override
  State<GradientDisplayName> createState() => _GradientDisplayNameState();
}

class _GradientDisplayNameState extends State<GradientDisplayName> {
  List<Color>? _colors;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(GradientDisplayName old) {
    super.didUpdateWidget(old);
    if (old.userId != widget.userId) _load();
  }

  void _load() {
    if (gradientCache.has(widget.userId)) {
      _colors = gradientCache.getCached(widget.userId);
    } else {
      gradientCache.get(widget.client, widget.userId).then((colors) {
        if (mounted) setState(() => _colors = colors);
      });
    }
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
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) =>
          LinearGradient(colors: colors).createShader(bounds),
      child: text,
    );
  }
}

/// Returns `null` if dismissed, empty list to clear, or a list of colors.
Future<List<Color>?> showGradientPicker(BuildContext context) {
  return showDialog<List<Color>>(
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
  List<Color> _colors = [const Color(0xFFFF1744), const Color(0xFF448AFF)];
  int _selectedStop = 0;

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

  Widget _buildPresets() => AlertDialog(
        title: const Text('Name gradient'), // TODO: l10n
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionChip(
              label: const Text('None'),
              onPressed: () => Navigator.pop(context, <Color>[]),
            ),
            ActionChip(
              label: const Text('Custom'),
              onPressed: () => setState(() => _customMode = true),
            ),
            for (var i = 0; i < nameGradients.length; i++)
              InkWell(
                onTap: () => Navigator.pop(context, nameGradients[i]),
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
      );

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
          Container(
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
          const SizedBox(height: 16),
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
          onPressed: () =>
              Navigator.pop(context, List<Color>.from(_colors)),
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    );
  }
}
