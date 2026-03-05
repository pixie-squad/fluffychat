import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:crop_your_image/crop_your_image.dart';

import 'package:fluffychat/l10n/l10n.dart';

/// Re-encodes image bytes to PNG via dart:ui (platform-native decoders),
/// so that package:image inside crop_your_image can always parse them.
Future<Uint8List> _ensureDecodable(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final byteData = await frame.image.toByteData(
    format: ui.ImageByteFormat.png,
  );
  frame.image.dispose();
  codec.dispose();
  return byteData!.buffer.asUint8List();
}

/// Shows a fullscreen crop editor for avatar images.
/// Returns cropped image bytes, or null if the user cancels.
Future<Uint8List?> showImageCropDialog({
  required BuildContext context,
  required Uint8List imageBytes,
}) {
  return Navigator.of(context).push<Uint8List>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _ImageCropDialog(imageBytes: imageBytes),
    ),
  );
}

class _ImageCropDialog extends StatefulWidget {
  final Uint8List imageBytes;

  const _ImageCropDialog({required this.imageBytes});

  @override
  State<_ImageCropDialog> createState() => _ImageCropDialogState();
}

class _ImageCropDialogState extends State<_ImageCropDialog> {
  final _controller = CropController();
  bool _cropping = false;
  Uint8List? _decodableBytes;

  @override
  void initState() {
    super.initState();
    _prepareImage();
  }

  Future<void> _prepareImage() async {
    try {
      final bytes = await _ensureDecodable(widget.imageBytes);
      if (mounted) setState(() => _decodableBytes = bytes);
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.of(context).oopsSomethingWentWrong)),
      );
    }
  }

  void _onConfirm() {
    setState(() => _cropping = true);
    _controller.cropCircle();
  }

  void _onCropped(CropResult result) {
    if (!mounted) return;
    switch (result) {
      case CropSuccess(:final croppedImage):
        Navigator.of(context).pop(croppedImage);
      case CropFailure():
        setState(() => _cropping = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.of(context).oopsSomethingWentWrong)),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final iconButtonStyle = IconButton.styleFrom(
      backgroundColor: Colors.black.withAlpha(200),
      foregroundColor: Colors.white,
    );
    final bytes = _decodableBytes;
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: IconButton(
          style: iconButtonStyle,
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: L10n.of(context).close,
        ),
        actions: [
          if (bytes != null)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: IconButton(
                style: iconButtonStyle,
                icon: _cropping
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check),
                onPressed: _cropping ? null : _onConfirm,
                tooltip: L10n.of(context).ok,
              ),
            ),
        ],
      ),
      body: bytes == null
          ? const Center(child: CircularProgressIndicator())
          : Crop(
              image: bytes,
              onCropped: _onCropped,
              controller: _controller,
              withCircleUi: true,
              interactive: true,
              fixCropRect: true,
              baseColor: Colors.black,
              maskColor: Colors.black.withAlpha(160),
              cornerDotBuilder: (_, _) => const SizedBox.shrink(),
              progressIndicator: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
    );
  }
}
