import 'package:flutter/material.dart';

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
    return Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 56, color: theme.colorScheme.error),
          const SizedBox(height: 16),
          Text(
            'Không thể tải dữ liệu',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(
              statusCode != null ? '${statusCode!}: $message' : message!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Thử lại'),
          ),
          const SizedBox(height: 8),
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
    );
  }
}
