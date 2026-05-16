import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_provider.dart';

/// Drop-in Text replacement that respects the global auto-size-text setting.
///
/// When [AppSettingsData.autoSizeText] is enabled, font size scales down by up
/// to [AppSettingsData.maxSizeReduction] × 2pt before clipping.
/// When disabled, behaves identically to a plain [Text].
class AdaptiveText extends ConsumerWidget {
  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  const AdaptiveText(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).valueOrNull;
    final autoSize = settings?.autoSizeText ?? false;

    if (!autoSize) {
      return Text(
        data,
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow ?? (maxLines != null ? TextOverflow.ellipsis : null),
      );
    }

    final steps = settings?.maxSizeReduction ?? 2;
    final baseFontSize =
        style?.fontSize ?? DefaultTextStyle.of(context).style.fontSize ?? 14.0;
    final minFontSize = (baseFontSize - steps * 2).clamp(8.0, baseFontSize);

    return AutoSizeText(
      data,
      style: style,
      textAlign: textAlign,
      maxLines: maxLines ?? 1,
      minFontSize: minFontSize,
      overflow: overflow ?? TextOverflow.ellipsis,
    );
  }
}
