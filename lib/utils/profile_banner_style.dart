import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:image/image.dart' as image;

class ProfileBannerStyle {
  final Color foregroundColor;
  final Color overlayColor;
  final int overlayAlpha;
  final Color representativeBackground;
  final List<Color> backgroundSamples;

  const ProfileBannerStyle({
    required this.foregroundColor,
    required this.overlayColor,
    required this.overlayAlpha,
    required this.representativeBackground,
    required this.backgroundSamples,
  });

  static const fallback = ProfileBannerStyle(
    foregroundColor: Colors.white,
    overlayColor: Colors.black,
    overlayAlpha: 112,
    representativeBackground: Color(0xFF1E1E1E),
    backgroundSamples: [Color(0xFF1E1E1E)],
  );
}

List<Color> sampleProfileBannerColors(
  image.Image imageData, {
  int columns = 5,
  int rows = 3,
}) {
  if (columns <= 0 ||
      rows <= 0 ||
      imageData.width <= 0 ||
      imageData.height <= 0) {
    return const [];
  }

  final samples = <Color>[];
  for (var row = 0; row < rows; row++) {
    final y = (((row + 0.5) * imageData.height) / rows).floor().clamp(
      0,
      imageData.height - 1,
    );
    for (var column = 0; column < columns; column++) {
      final x = (((column + 0.5) * imageData.width) / columns).floor().clamp(
        0,
        imageData.width - 1,
      );
      final pixel = imageData.getPixel(x, y);
      samples.add(
        Color.fromARGB(
          pixel.a.toInt(),
          pixel.r.toInt(),
          pixel.g.toInt(),
          pixel.b.toInt(),
        ),
      );
    }
  }
  return samples;
}

ProfileBannerStyle resolveProfileBannerStyle(
  List<Color> samples, {
  double targetContrast = 4.2,
}) {
  final safeSamples = samples.isEmpty
      ? ProfileBannerStyle.fallback.backgroundSamples
      : samples;

  final whiteContrast = _minContrastForForeground(Colors.white, safeSamples);
  final blackContrast = _minContrastForForeground(Colors.black, safeSamples);

  final foregroundColor = blackContrast >= whiteContrast
      ? Colors.black
      : Colors.white;
  final overlayColor = foregroundColor == Colors.white
      ? Colors.black
      : Colors.white;

  var overlayAlpha = 0;
  var blendedSamples = safeSamples;
  var bestContrast = _minContrastForForeground(foregroundColor, blendedSamples);

  for (var alpha = 24; alpha <= 224; alpha += 4) {
    final candidateSamples = safeSamples
        .map(
          (sample) => Color.alphaBlend(overlayColor.withAlpha(alpha), sample),
        )
        .toList(growable: false);
    final candidateContrast = _minContrastForForeground(
      foregroundColor,
      candidateSamples,
    );
    if (candidateContrast > bestContrast) {
      bestContrast = candidateContrast;
      overlayAlpha = alpha;
      blendedSamples = candidateSamples;
    }
    if (candidateContrast >= targetContrast) {
      overlayAlpha = alpha;
      blendedSamples = candidateSamples;
      break;
    }
  }

  return ProfileBannerStyle(
    foregroundColor: foregroundColor,
    overlayColor: overlayColor,
    overlayAlpha: overlayAlpha,
    representativeBackground: _averageColor(blendedSamples),
    backgroundSamples: blendedSamples,
  );
}

ProfileBannerStyle resolveProfileBannerStyleFromBytes(
  Uint8List bytes, {
  int columns = 5,
  int rows = 3,
  double targetContrast = 4.2,
}) {
  image.Image? decodedImage;
  try {
    decodedImage = image.decodeImage(bytes);
  } catch (_) {
    return ProfileBannerStyle.fallback;
  }
  if (decodedImage == null) return ProfileBannerStyle.fallback;
  final samples = sampleProfileBannerColors(
    decodedImage,
    columns: columns,
    rows: rows,
  );
  return resolveProfileBannerStyle(samples, targetContrast: targetContrast);
}

double _minContrastForForeground(Color foreground, List<Color> backgrounds) {
  var minContrast = double.infinity;
  for (final background in backgrounds) {
    final contrast = _contrastRatio(foreground, background);
    if (contrast < minContrast) minContrast = contrast;
  }
  return minContrast;
}

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = firstLuminance > secondLuminance
      ? firstLuminance
      : secondLuminance;
  final darker = firstLuminance > secondLuminance
      ? secondLuminance
      : firstLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

Color _averageColor(List<Color> colors) {
  if (colors.isEmpty) {
    return ProfileBannerStyle.fallback.representativeBackground;
  }

  var alphaTotal = 0;
  var redTotal = 0;
  var greenTotal = 0;
  var blueTotal = 0;

  for (final color in colors) {
    final argb = color.toARGB32();
    alphaTotal += (argb >> 24) & 0xFF;
    redTotal += (argb >> 16) & 0xFF;
    greenTotal += (argb >> 8) & 0xFF;
    blueTotal += argb & 0xFF;
  }

  final count = colors.length;
  return Color.fromARGB(
    alphaTotal ~/ count,
    redTotal ~/ count,
    greenTotal ~/ count,
    blueTotal ~/ count,
  );
}
