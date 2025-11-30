import 'package:flutter/material.dart';
import 'package:khu_lien_hop_tt/widgets/neu_button.dart';
import 'package:neubrutalism_ui/neubrutalism_ui.dart';

Future<void> showSuccessDialog(
  BuildContext context, {
  String title = 'Thành công',
  required String message,
  String actionLabel = 'Đóng',
  Duration animationDuration = const Duration(milliseconds: 220),
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'success_dialog',
    transitionDuration: animationDuration,
    pageBuilder: (context, animation, secondaryAnimation) {
      return const SizedBox.shrink();
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInBack,
      );
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: curved,
          child: _SuccessDialog(
            title: title,
            message: message,
            actionLabel: actionLabel,
          ),
        ),
      );
    },
  );
}

class _SuccessDialog extends StatelessWidget {
  const _SuccessDialog({
    required this.title,
    required this.message,
    required this.actionLabel,
  });

  final String title;
  final String message;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dialogColor = const Color(0xFFFFF4C7);
    final iconBackdrop = const Color(0xFFBBF1E2);
    final accentShadow = Colors.black.withValues(alpha: 0.8);
    final buttonColor = const Color(0xFFFFD6E8);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Material(
          color: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: NeuContainer(
              color: dialogColor,
              borderRadius: BorderRadius.circular(26),
              borderColor: Colors.black,
              borderWidth: 3,
              shadowColor: accentShadow,
              shadowBlurRadius: 0,
              offset: const Offset(6, 6),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: iconBackdrop,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: Colors.black, width: 3),
                        boxShadow: const [
                          BoxShadow(offset: Offset(4, 4), blurRadius: 0, color: Colors.black),
                        ],
                      ),
                      child: Icon(
                        Icons.check_rounded,
                        size: 48,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Column(
                      children: [
                        Text(
                          title,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Container(
                          width: 72,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      message,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(height: 1.5, color: Colors.grey.shade900),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    NeuButton(
                      onPressed: () => Navigator.of(context).pop(),
                      buttonWidth: double.infinity,
                      buttonHeight: 54,
                      borderRadius: BorderRadius.circular(18),
                      buttonColor: buttonColor,
                      shadowColor: accentShadow,
                      borderColor: Colors.black,
                      borderWidth: 3,
                      child: Text(
                        actionLabel,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
