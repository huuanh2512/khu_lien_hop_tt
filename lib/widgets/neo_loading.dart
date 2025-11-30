import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:neubrutalism_ui/neubrutalism_ui.dart';

/// Neo-brutalist loading card for fullscreen or section-level loading states.
class NeoLoadingCard extends StatefulWidget {
  const NeoLoadingCard({
    super.key,
    this.label = 'Đang tải...',
    this.backgroundColor,
    this.shadowColor,
    this.width,
    this.height,
    this.showIcon = true,
  });

  final String label;
  final Color? backgroundColor;
  final Color? shadowColor;
  final double? width;
  final double? height;
  final bool showIcon;

  @override
  State<NeoLoadingCard> createState() => _NeoLoadingCardState();
}

class _NeoLoadingCardState extends State<NeoLoadingCard>
    with SingleTickerProviderStateMixin {
  static const _palette = [
    Color(0xFFFFF4C7),
    Color(0xFFBBF1E2),
    Color(0xFFFFD6E8),
    Color(0xFFE0EDFF),
  ];

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  late final Animation<double> _scale = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOutCubic,
  );

  Color _resolveBackground() {
    if (widget.backgroundColor != null) return widget.backgroundColor!;
    final index = widget.label.hashCode.abs() % _palette.length;
    return _palette[index];
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final block = NeuContainer(
      color: _resolveBackground(),
      borderRadius: BorderRadius.circular(26),
      borderColor: Colors.black,
      borderWidth: 3,
      shadowColor: widget.shadowColor ?? Colors.black.withValues(alpha: 0.8),
      shadowBlurRadius: 0,
      offset: const Offset(6, 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final t = math.sin(_controller.value * math.pi);
                return Transform.translate(
                  offset: Offset(0, (1 - t) * 4),
                  child: Transform.scale(
                    scale: 0.92 + t * 0.08,
                    child: Column(
                      children: [
                        if (widget.showIcon)
                          const Icon(Icons.bolt, color: Colors.black, size: 28),
                        Container(
                          margin: const EdgeInsets.only(top: 12),
                          height: 10,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            Text(
              widget.label,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800, color: Colors.black),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Transform.scale(
          scale: 0.96 + _scale.value * 0.04,
          child: child,
        ),
        child: block,
      ),
    );
  }
}

/// Compact brutalist loader for inline use (e.g. buttons).
class NeoLoadingDot extends StatefulWidget {
  const NeoLoadingDot({
    super.key,
    this.size = 18,
    this.fillColor = Colors.white,
    this.borderColor = Colors.black,
    this.shadowColor,
  });

  final double size;
  final Color fillColor;
  final Color borderColor;
  final Color? shadowColor;

  @override
  State<NeoLoadingDot> createState() => _NeoLoadingDotState();
}

class _NeoLoadingDotState extends State<NeoLoadingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shadow = widget.shadowColor ?? Colors.black.withValues(alpha: 0.65);
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) {
        final scale = 0.85 + _curve.value * 0.15;
        return Transform.scale(
          scale: scale,
          child: child,
        );
      },
      child: NeuContainer(
        color: widget.fillColor,
        borderRadius: BorderRadius.circular(widget.size / 3),
        borderColor: widget.borderColor,
        borderWidth: 2,
        shadowColor: shadow,
        shadowBlurRadius: 0,
        offset: const Offset(3, 3),
        child: SizedBox(width: widget.size, height: widget.size),
      ),
    );
  }
}
