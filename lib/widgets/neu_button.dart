import 'package:flutter/material.dart';
import 'package:neubrutalism_ui/neubrutalism_ui.dart';

/// Lightweight public-facing wrapper around the private NeuButton
/// implementation from the neubrutalism_ui package. This keeps the
/// API available to the app even though the package does not export it.
class NeuButton extends StatefulWidget {
  const NeuButton({
    super.key,
    required this.child,
    this.onPressed,
    this.buttonColor,
    this.shadowColor,
    this.borderColor = Colors.black,
    this.borderRadius,
    this.buttonHeight = 52,
    this.buttonWidth = double.infinity,
    this.borderWidth = 3,
    this.offset = const Offset(6, 6),
    this.shadowBlurRadius = 0,
    this.enableAnimation = true,
    this.animationDuration = 140,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final Color? buttonColor;
  final Color? shadowColor;
  final Color borderColor;
  final BorderRadius? borderRadius;
  final double buttonHeight;
  final double buttonWidth;
  final double borderWidth;
  final Offset offset;
  final double shadowBlurRadius;
  final bool enableAnimation;
  final int animationDuration;

  @override
  State<NeuButton> createState() => _NeuButtonState();
}

class _NeuButtonState extends State<NeuButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.animationDuration),
    );
    _animation = Tween<Offset>(
      begin: Offset.zero,
      end: widget.enableAnimation ? widget.offset : Offset.zero,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (widget.onPressed == null) return;
    if (widget.enableAnimation) {
      await _controller.forward();
      widget.onPressed?.call();
      await _controller.reverse();
    } else {
      widget.onPressed?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveShadowOffset = widget.enableAnimation
        ? widget.offset - _animation.value
        : widget.offset;
    return SizedBox(
      width: widget.buttonWidth,
      height: widget.buttonHeight,
      child: GestureDetector(
        onTap: _handleTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedBuilder(
          animation: _animation,
          builder: (context, child) => Transform.translate(
            offset: widget.enableAnimation ? _animation.value : Offset.zero,
            child: child,
          ),
          child: NeuContainer(
            borderRadius: widget.borderRadius,
            color: widget.buttonColor ?? Theme.of(context).colorScheme.primary,
            borderColor: widget.borderColor,
            borderWidth: widget.borderWidth,
            shadowColor:
                widget.shadowColor ?? Colors.black.withValues(alpha: 0.6),
            shadowBlurRadius: widget.shadowBlurRadius,
            offset: effectiveShadowOffset,
            child: Center(child: widget.child),
          ),
        ),
      ),
    );
  }
}
