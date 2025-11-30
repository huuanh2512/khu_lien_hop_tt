import 'package:flutter/material.dart';
import 'package:khu_lien_hop_tt/widgets/neu_button.dart';
import 'package:neubrutalism_ui/neubrutalism_ui.dart';

class ErrorStateWidget extends StatelessWidget {
  const ErrorStateWidget({
    super.key,
    required this.onRetry,
    this.statusCode,
    this.message,
    this.onLogin,
    this.onVerifyEmail,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
  });

  final VoidCallback onRetry;
  final int? statusCode;
  final String? message;
  final VoidCallback? onLogin;
  final VoidCallback? onVerifyEmail;
  final EdgeInsetsGeometry padding;

  bool get _isUnauthenticated => statusCode == 401;

  bool get _isEmailNotVerified {
    if (statusCode != 403) return false;
    final lower = message?.toLowerCase() ?? '';
    return lower.contains('email not verified') || lower.contains('verify email');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentShadow = Colors.black.withValues(alpha: 0.8);
    final cardColor = const Color(0xFFFFF0D7);
    final iconBoxColor = const Color(0xFFFFD6E8);
    return Padding(
      padding: padding,
      child: NeuContainer(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        borderColor: Colors.black,
        borderWidth: 3,
        shadowBlurRadius: 0,
        shadowColor: accentShadow,
        offset: const Offset(6, 6),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: iconBoxColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.black, width: 3),
                  boxShadow: const [
                    BoxShadow(offset: Offset(4, 4), blurRadius: 0, color: Colors.black),
                  ],
                ),
                child: Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
              ),
              const SizedBox(height: 20),
              Text(
                'Không thể tải dữ liệu',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                ),
                textAlign: TextAlign.center,
              ),
              if (message != null) ...[
                const SizedBox(height: 10),
                Text(
                  statusCode != null ? '${statusCode!}: $message' : message!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade900,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              NeuButton(
                onPressed: onRetry,
                buttonWidth: double.infinity,
                buttonHeight: 52,
                buttonColor: const Color(0xFFBBF1E2),
                shadowColor: accentShadow,
                borderColor: Colors.black,
                borderRadius: BorderRadius.circular(18),
                borderWidth: 3,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.refresh, color: Colors.black),
                    const SizedBox(width: 8),
                    Text(
                      'Thử lại',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              if (_isUnauthenticated && onLogin != null)
                TextButton(
                  onPressed: onLogin,
                  child: const Text('Đăng nhập lại'),
                ),
              if (_isEmailNotVerified && onVerifyEmail != null)
                TextButton(
                  onPressed: onVerifyEmail,
                  child: const Text('Xác thực email'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
