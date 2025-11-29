import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:neubrutalism_ui/neubrutalism_ui.dart';

import 'package:khu_lien_hop_tt/screens/auth/login_page.dart';

import '../customer/customer_home_page.dart';
import '../services/auth_service.dart';
import '../widgets/neu_button.dart';
import '../widgets/neu_text.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final AuthService _authService = AuthService.instance;
  bool _sending = false;
  bool _checking = false;
  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _resendCooldown = 60);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCooldown <= 1) {
        timer.cancel();
        setState(() => _resendCooldown = 0);
      } else {
        setState(() => _resendCooldown -= 1);
      }
    });
  }

  Future<void> _sendVerificationEmail() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);
    _startCooldown();
    try {
      await _authService.sendVerificationEmail();
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Đã gửi lại email xác thực.')),
      );
    } catch (err) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Không thể gửi email xác thực: $err')),
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _checkVerification() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _checking = true);
    try {
      final verified = await _authService.reloadAndCheckVerified();
      if (!mounted) return;
      if (verified) {
        navigator.pushReplacement(
          MaterialPageRoute(builder: (_) => const CustomerHomePage()),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Email của bạn vẫn chưa được xác thực.'),
          ),
        );
      }
    } catch (err) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Không thể kiểm tra trạng thái: $err')),
      );
    } finally {
      if (mounted) {
        setState(() => _checking = false);
      }
    }
  }

  Future<void> _backToLogin() async {
    final navigator = Navigator.of(context);
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final email = _authService.currentUser?.email ?? 'email của bạn';

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildAnimatedIllustration(colorScheme),
                  const SizedBox(height: 20),
                  NeuText(
                    'Xác minh email của bạn',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: colorScheme.onSecondaryContainer,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Chúng tôi đã gửi hướng dẫn tới $email. Vui lòng kiểm tra hộp thư hoặc mục spam.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSecondaryContainer.withValues(alpha: 0.9),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildInfoCard(theme, colorScheme, email),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedIllustration(ColorScheme colorScheme) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.9, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, (1 - value) * 30),
          child: Transform.scale(scale: value, child: child),
        );
      },
      child: NeuContainer(
        width: 128,
        height: 128,
        borderRadius: BorderRadius.circular(48),
        color: colorScheme.secondaryContainer,
        borderColor: Colors.black,
        shadowColor: Colors.black.withValues(alpha: 0.4),
        offset: const Offset(8, 8),
        child: const Center(
          child: Icon(Icons.mark_email_unread_outlined, size: 48),
        ),
      ),
    );
  }

  Widget _buildInfoCard(ThemeData theme, ColorScheme colorScheme, String email) {
    return NeuContainer(
      borderRadius: BorderRadius.circular(28),
      color: colorScheme.secondaryContainer,
      borderColor: Colors.black,
      shadowColor: Colors.black.withValues(alpha: 0.4),
      offset: const Offset(8, 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NeuText(
              'Chưa nhận được email?',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Hãy đảm bảo rằng địa chỉ $email chính xác. Bạn có thể yêu cầu gửi lại email xác minh hoặc kiểm tra trạng thái bất kỳ lúc nào.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            _buildPrimaryButton(colorScheme),
            const SizedBox(height: 12),
            _buildSecondaryButton(colorScheme),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.center,
              child: TextButton(
                onPressed: _backToLogin,
                child: const Text(
                  '← Quay về đăng nhập',
                  style: TextStyle(fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrimaryButton(ColorScheme colorScheme) {
    return NeuButton(
      buttonHeight: 54,
      buttonColor: colorScheme.primary,
      borderRadius: BorderRadius.circular(18),
      onPressed: _checking ? null : _checkVerification,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: _checking
            ? Row(
                key: const ValueKey('checking'),
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor: AlwaysStoppedAnimation<Color>(colorScheme.onPrimary),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Đang kiểm tra...',
                    style: TextStyle(
                      color: colorScheme.onPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              )
            : Text(
                'Tôi đã xác thực',
                key: const ValueKey('verify'),
                style: TextStyle(
                  color: colorScheme.onPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }

  Widget _buildSecondaryButton(ColorScheme colorScheme) {
    return NeuButton(
      buttonHeight: 52,
      buttonColor: colorScheme.tertiaryContainer,
      borderRadius: BorderRadius.circular(18),
      onPressed: (_sending || _resendCooldown > 0) ? null : _sendVerificationEmail,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: _sending
            ? Row(
                key: const ValueKey('sending'),
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        colorScheme.onTertiaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Đang gửi...',
                    style: TextStyle(
                      color: colorScheme.onTertiaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              )
            : Text(
                _resendCooldown > 0
                    ? 'Gửi lại sau ${_resendCooldown}s'
                    : 'Gửi lại email xác thực',
                key: ValueKey(_resendCooldown),
                style: TextStyle(
                  color: colorScheme.onTertiaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}
