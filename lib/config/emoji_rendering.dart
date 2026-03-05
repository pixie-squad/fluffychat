import 'package:flutter/material.dart';

const String emojiFontFamily = 'AppleColorEmoji';

const List<String> emojiFallbackFamilies = [
  emojiFontFamily,
  'Apple Color Emoji',
  'Segoe UI Emoji',
  'Segoe UI Symbol',
  'Noto Color Emoji',
  'Noto Emoji',
  'Android Emoji',
];

const TextStyle appleEmojiTextStyle = TextStyle(
  fontFamily: emojiFontFamily,
  fontFamilyFallback: emojiFallbackFamilies,
);
