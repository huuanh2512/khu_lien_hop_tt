import 'package:flutter/material.dart';

/// Lightweight replacement for the (currently missing) NeuText widget from
/// the neubrutalism_ui package. Provides punchy typography for headings.
class NeuText extends StatelessWidget {
  const NeuText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
  });

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: -0.5,
    );
    return Text(
      text,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: maxLines == null ? TextOverflow.visible : TextOverflow.ellipsis,
      style: baseStyle?.merge(style) ?? style,
    );
  }
}
