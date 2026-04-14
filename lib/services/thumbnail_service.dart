import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// Generates and caches JPEG thumbnails on a background isolate so the UI
/// thread never decodes full-size photos during list scrolling.
///
/// Thumbnails live in `<vault>/cache/thumbs/<hash>.jpg`. The hash encodes
/// the source path plus its modified-timestamp so edits automatically
/// invalidate the cache. The cache dir is safe to delete at any time.
class ThumbnailService {
  ThumbnailService._();

  static const _thumbDirName = 'cache/thumbs';
  static const _defaultMaxSize = 256;
  static const _jpegQuality = 80;

  /// Returns the absolute path to a cached thumbnail for [sourcePath],
  /// generating it on a background isolate if missing. `null` if the source
  /// does not exist or decoding fails.
  ///
  /// [sourcePath] may be absolute or relative to [vaultPath] (photos live in
  /// `<vault>/photos/...` per the vault-portability rule).
  static Future<String?> getOrCreate({
    required String vaultPath,
    required String sourcePath,
    int maxSize = _defaultMaxSize,
  }) async {
    final absoluteSource =
        p.isAbsolute(sourcePath) ? sourcePath : p.join(vaultPath, sourcePath);
    final srcFile = File(absoluteSource);
    if (!srcFile.existsSync()) return null;

    final cacheDir = Directory(p.join(vaultPath, _thumbDirName));
    if (!cacheDir.existsSync()) {
      cacheDir.createSync(recursive: true);
    }

    final stat = srcFile.statSync();
    final keyInput =
        '$absoluteSource|${stat.modified.millisecondsSinceEpoch}|$maxSize';
    final hash = sha1.convert(utf8.encode(keyInput)).toString();
    final thumbPath = p.join(cacheDir.path, '$hash.jpg');

    if (File(thumbPath).existsSync()) return thumbPath;

    return compute(
      _generateThumbnail,
      _ThumbArgs(absoluteSource, thumbPath, maxSize),
    );
  }

  /// Removes every cached thumbnail for a vault. Safe to call any time —
  /// thumbnails regenerate lazily on next access.
  static Future<void> clearCache(String vaultPath) async {
    final dir = Directory(p.join(vaultPath, _thumbDirName));
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  }
}

/// Isolate entry-point. Must be a top-level / static function so it can be
/// sent across the isolate boundary. Returns the written thumb path or null.
String? _generateThumbnail(_ThumbArgs args) {
  try {
    final bytes = File(args.source).readAsBytesSync();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    // Preserve aspect ratio — only downscale if the longer side exceeds the
    // target, otherwise copy as-is (still re-encoded to JPEG to normalise).
    final longSide =
        decoded.width > decoded.height ? decoded.width : decoded.height;
    final resized = longSide > args.maxSize
        ? img.copyResize(
            decoded,
            width: decoded.width >= decoded.height ? args.maxSize : null,
            height: decoded.height > decoded.width ? args.maxSize : null,
          )
        : decoded;

    File(args.thumb).writeAsBytesSync(
      img.encodeJpg(resized, quality: ThumbnailService._jpegQuality),
    );
    return args.thumb;
  } catch (_) {
    return null;
  }
}

class _ThumbArgs {
  final String source;
  final String thumb;
  final int maxSize;
  const _ThumbArgs(this.source, this.thumb, this.maxSize);
}
