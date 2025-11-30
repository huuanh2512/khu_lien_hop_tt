// Updated: chuyển sang Firebase Auth + email verify
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:neubrutalism_ui/neubrutalism_ui.dart';

import '../../customer/customer_home_page.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../staff/staff_home_page.dart';
import '../verify_email_screen.dart';
import '../../main.dart' show AdminDashboardPage;
import '../../widgets/neu_button.dart';
import '../../widgets/neu_text.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final ApiService _api = ApiService();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  bool _buttonPressed = false;
  String? _errorMessage;
  Timer? _errorTimer;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _errorTimer?.cancel();
    super.dispose();
  }

  void _clearErrorMessage() {
    if (_errorMessage == null) return;
    _errorTimer?.cancel();
    _errorTimer = null;
    setState(() => _errorMessage = null);
  }

  void _setErrorMessage(String? message) {
    _errorTimer?.cancel();
    if (!mounted) return;
    setState(() => _errorMessage = message);
    if (message != null) {
      _errorTimer = Timer(const Duration(seconds: 5), () {
        if (!mounted) return;
        setState(() => _errorMessage = null);
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    _setErrorMessage(null);
    try {
      final auth = AuthService.instance;
      final firebaseUser = await auth.signInWithEmail(
        _emailCtrl.text.trim(),
        _passCtrl.text,
      );
      if (firebaseUser == null) {
        throw Exception('Không tìm thấy thông tin người dùng Firebase');
      }

      try {
        await firebaseUser.reload();
      } catch (_) {
        // Bỏ qua lỗi reload, dùng trạng thái hiện tại.
      }
      final refreshedUser = FirebaseAuth.instance.currentUser;
      final bool emailVerified =
          refreshedUser?.emailVerified ?? firebaseUser.emailVerified;

      final token = await auth.getIdToken();
      if (token == null || token.isEmpty) {
        throw Exception('Không lấy được Firebase ID token');
      }

      ApiService.setAuthToken(token);
      final appUser = await _api.fetchCurrentUser();

      await auth.applyFirebaseUserSession(
        token: token,
        user: appUser,
        isCustomerVerified: emailVerified,
      );
      await auth.persistSession();

      if (!mounted) return;
      Widget destination;
      if (appUser.role == 'admin') {
        destination = const AdminDashboardPage();
      } else if (appUser.role == 'staff') {
        destination = const StaffHomePage();
      } else if (appUser.role == 'customer' && !emailVerified) {
        destination = const VerifyEmailScreen();
      } else {
        destination = const CustomerHomePage();
      }

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => destination),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      var message = 'Đăng nhập thất bại. Vui lòng thử lại sau.';
      final code = e.code.toLowerCase();
      if (code == 'invalid-credential' || code == 'user-not-found' || code == 'wrong-password') {
        _setErrorMessage('Email hoặc mật khẩu không đúng.');
        return;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đăng nhập thất bại. Vui lòng thử lại sau.')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: _buildAnimatedCard(
                colorScheme: colorScheme,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Hero(
                        tag: 'auth-brand',
                        child: _buildLogoHeader(theme),
                      ),
                    ),
                    const SizedBox(height: 20),
                    NeuText(
                      'Chào mừng trở lại',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: colorScheme.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Đăng nhập để tiếp tục hành trình thể thao của bạn.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextFormField(
                            controller: _emailCtrl,
                            focusNode: _emailFocus,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            decoration: _fieldDecoration(
                              context,
                              label: 'Email',
                              icon: Icons.mail_outline,
                            ),
                            validator: (value) {
                              final input = value?.trim() ?? '';
                              if (input.isEmpty || !input.contains('@')) {
                                return 'Vui lòng nhập email hợp lệ';
                              }
                              return null;
                            },
                            onEditingComplete: () =>
                                FocusScope.of(context).requestFocus(_passwordFocus),
                            onChanged: (_) => _clearErrorMessage(),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _passCtrl,
                            focusNode: _passwordFocus,
                            obscureText: _obscurePassword,
                            decoration: _fieldDecoration(
                              context,
                              label: 'Mật khẩu',
                              icon: Icons.lock_outline,
                              suffix: IconButton(
                                onPressed: () =>
                                    setState(() => _obscurePassword = !_obscurePassword),
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().length < 6) {
                                return 'Mật khẩu phải có ít nhất 6 ký tự';
                              }
                              return null;
                            },
                            onFieldSubmitted: (_) => _loading ? null : _submit(),
                            onChanged: (_) => _clearErrorMessage(),
                          ),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _loading
                                  ? null
                                  : () => ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Liên hệ nhân viên để hỗ trợ đặt lại mật khẩu.',
                                          ),
                                        ),
                                      ),
                              child: const Text('Quên mật khẩu?'),
                            ),
                          ),
                          _buildInlineErrorMessage(),
                          const SizedBox(height: 16),
                          _buildPrimaryButton(colorScheme),
                          const SizedBox(height: 18),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('Chưa có tài khoản?',
                                  style: theme.textTheme.bodyMedium),
                              TextButton(
                                onPressed: _loading
                                    ? null
                                    : () => Navigator.of(context).pushNamed('/register'),
                                child: const Text('Đăng ký ngay'),
                              ),
                            ],
                          ),
                        ],
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

  Widget _buildInlineErrorMessage() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: _errorMessage == null
          ? const SizedBox.shrink()
          : Container(
              key: const ValueKey('login-error-card'),
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline, size: 20, color: Colors.redAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _errorMessage ?? 'Email hoặc mật khẩu không đúng.',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.redAccent,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Vui lòng kiểm tra lại thông tin và thử lại.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildLogoHeader(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        NeuContainer(
          width: 82,
          height: 82,
          borderRadius: BorderRadius.circular(28),
          color: colorScheme.primaryContainer,
          borderColor: Colors.black,
          shadowColor: Colors.black.withValues(alpha: 0.4),
          child: const Center(
            child: Icon(Icons.sports_soccer, size: 38),
          ),
        ),
        const SizedBox(height: 12),
        NeuText(
          'Khu Liên Hợp Thể Thao',
          style: theme.textTheme.titleMedium?.copyWith(
            color: colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildAnimatedCard({
    required Widget child,
    required ColorScheme colorScheme,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.92, end: 1),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (context, value, childWidget) {
        return Opacity(
          opacity: value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 36),
            child: Transform.scale(
              scale: value,
              child: NeuContainer(
                borderRadius: BorderRadius.circular(28),
                color: colorScheme.secondaryContainer,
                borderColor: Colors.black,
                shadowColor: Colors.black.withValues(alpha: 0.4),
                offset: const Offset(8, 8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
                  child: childWidget,
                ),
              ),
            ),
          ),
        );
      },
      child: child,
    );
  }

  InputDecoration _fieldDecoration(
    BuildContext context, {
    required String label,
    required IconData icon,
    Widget? suffix,
  }) {
    final theme = Theme.of(context);
    final fill = theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6);
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      suffixIcon: suffix,
      filled: true,
      fillColor: fill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: theme.colorScheme.primary),
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
    );
  }

  Widget _buildPrimaryButton(ColorScheme colorScheme) {
    return Listener(
      onPointerDown: (_) => _setButtonPressed(true),
      onPointerUp: (_) => _setButtonPressed(false),
      onPointerCancel: (_) => _setButtonPressed(false),
      child: AnimatedScale(
        scale: _buttonPressed && !_loading ? 0.97 : 1,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        child: SizedBox(
          width: double.infinity,
          child: NeuButton(
            enableAnimation: !_loading,
            onPressed: _loading ? null : _submit,
            buttonHeight: 56,
            buttonWidth: double.infinity,
            borderRadius: BorderRadius.circular(18),
            buttonColor: colorScheme.primary,
            shadowColor: Colors.black.withValues(alpha: 0.6),
            borderColor: Colors.black,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: animation, child: child),
              ),
              child: _loading
                  ? Row(
                      key: const ValueKey('loading'),
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
                          'Đang đăng nhập...',
                          style: TextStyle(
                            color: colorScheme.onPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      'Đăng nhập',
                      key: const ValueKey('label'),
                      style: TextStyle(
                        color: colorScheme.onPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  void _setButtonPressed(bool value) {
    if (_buttonPressed == value) return;
    setState(() => _buttonPressed = value);
  }
}
