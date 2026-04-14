import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/vault_provider.dart';
import '../services/thumbnail_service.dart';

/// Image widget that loads a JPEG thumbnail for [sourcePath] via
/// [ThumbnailService]. Generation runs on a background isolate, so scrolling
/// through long photo lists never blocks the UI thread.
///
/// Use this anywhere you'd normally put `Image.file(...)` for a vault photo.
class ThumbnailImage extends ConsumerWidget {
  final String sourcePath;
  final double? width;
  final double? height;
  final BoxFit fit;
  final int maxSize;
  final Widget? placeholder;
  final BorderRadius? borderRadius;

  const ThumbnailImage({
    super.key,
    required this.sourcePath,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.maxSize = 256,
    this.placeholder,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vaultPath = ref.watch(vaultPathProvider);
    if (vaultPath == null) return _fallback();

    return FutureBuilder<String?>(
      future: ThumbnailService.getOrCreate(
        vaultPath: vaultPath,
        sourcePath: sourcePath,
        maxSize: maxSize,
      ),
      builder: (context, snap) {
        if (!snap.hasData) return _fallback();
        final path = snap.data;
        if (path == null) return _fallback();
        final img = Image.file(
          File(path),
          width: width,
          height: height,
          fit: fit,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _fallback(),
        );
        return borderRadius != null
            ? ClipRRect(borderRadius: borderRadius!, child: img)
            : img;
      },
    );
  }

  Widget _fallback() {
    return placeholder ??
        Container(
          width: width,
          height: height,
          color: Colors.black12,
          child: const Icon(Icons.image_outlined, color: Colors.black26),
        );
  }
}
