import 'package:flutter/material.dart';

enum SportsBackgroundVariant { primary, staff, customer }

class SportsGradientBackground extends StatelessWidget {
  const SportsGradientBackground({
    super.key,
    required this.child,
    this.variant = SportsBackgroundVariant.primary,
    this.hideTopLeftAccent = false,
  });

  final Widget child;
  final SportsBackgroundVariant variant;
  final bool hideTopLeftAccent;

  static const Color _primaryBase = Color(0xFFFFF3B0);
  static const Color _primaryAccent = Color(0xFFFFC8DD);
  static const Color _staffBase = Color(0xFFA0E7E5);
  static const Color _staffAccent = Color(0xFFB8F2E6);
  static const Color _customerBase = Color(0xFFFFC8DD);
  static const Color _customerAccent = Color(0xFFBDE0FE);

  Color _backgroundColor(ColorScheme scheme) => switch (variant) {
        SportsBackgroundVariant.staff => _staffBase,
        SportsBackgroundVariant.customer => _customerBase,
        SportsBackgroundVariant.primary => _primaryBase,
      };

  Color _accentColor(ColorScheme scheme) => switch (variant) {
        SportsBackgroundVariant.staff => _staffAccent,
        SportsBackgroundVariant.customer => _customerAccent,
        SportsBackgroundVariant.primary => _primaryAccent,
      };

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final baseColor = _backgroundColor(colorScheme);
    final accentColor = _accentColor(colorScheme);
    final contrastColor = colorScheme.surfaceContainerHighest;

    return Container(
      color: baseColor,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (!hideTopLeftAccent)
            Positioned(
              top: -32,
              left: -24,
              child: _BrutalistShape(
                color: accentColor.withValues(alpha: 0.9),
                width: 180,
                height: 140,
                borderRadius: 28,
              ),
            ),
          Positioned(
            bottom: -28,
            right: -16,
            child: _BrutalistShape(
              color: contrastColor.withValues(alpha: 0.75),
              width: 140,
              height: 110,
              borderRadius: 20,
            ),
          ),
          Positioned(
            top: 80,
            right: 24,
            child: Opacity(
              opacity: 0.55,
              child: _BrutalistShape(
                color: accentColor.withValues(alpha: 0.8),
                width: 90,
                height: 90,
                borderRadius: 18,
              ),
            ),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class _BrutalistShape extends StatelessWidget {
  const _BrutalistShape({
    required this.color,
    required this.width,
    required this.height,
    required this.borderRadius,
  });

  final Color color;
  final double width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: Colors.black, width: 3),
        boxShadow: const [
          BoxShadow(color: Colors.black, offset: Offset(6, 6), blurRadius: 0),
        ],
      ),
    );
  }
}
