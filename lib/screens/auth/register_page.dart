// Updated: chuyển sang Firebase Auth + email verify
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:neubrutalism_ui/neubrutalism_ui.dart';

import '../../models/sport.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../widgets/neu_button.dart';
import '../../widgets/neu_text.dart';
import '../verify_email_screen.dart';
import 'login_page.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final ApiService _api = ApiService();
  final AuthService _auth = AuthService.instance;
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  final _nameFocus = FocusNode();
  final _genderFocus = FocusNode();
  final _dobFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmPasswordFocus = FocusNode();
  final _mainSportFocus = FocusNode();
  final DateFormat _dateFormatter = DateFormat('dd/MM/yyyy');

  bool _loading = false;
  bool _buttonPressed = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _sportsLoading = true;

  String? _selectedGender;
  String? _selectedMainSportId;
  String? _sportsError;
  DateTime? _selectedDob;
  List<Sport> _sports = const [];

  @override
  void initState() {
    super.initState();
    _loadSports();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmPassCtrl.dispose();
    _dobCtrl.dispose();
    _nameFocus.dispose();
    _genderFocus.dispose();
    _dobFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmPasswordFocus.dispose();
    _mainSportFocus.dispose();
    super.dispose();
  }

  Future<void> _loadSports() async {
    setState(() {
      _sportsLoading = true;
      _sportsError = null;
    });
    try {
      final sports = await _api.getSports(includeCount: false);
      if (!mounted) return;
      setState(() {
        _sports = sports;
        _sportsLoading = false;
        if (_selectedMainSportId == null && sports.isNotEmpty) {
          _selectedMainSportId = sports.first.id;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sportsLoading = false;
        _sportsError = 'Không thể tải danh sách môn. Nhấn để thử lại.';
      });
    }
  }

  Future<void> _selectDob() async {
    final now = DateTime.now();
    final initialDate = _selectedDob ?? DateTime(now.year - 18, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(now.year - 70),
      lastDate: DateTime(now.year - 10, now.month, now.day),
    );
    if (picked != null) {
      setState(() {
        _selectedDob = picked;
        _dobCtrl.text = _dateFormatter.format(picked);
      });
    }
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    if (_passCtrl.text.trim() != _confirmPassCtrl.text.trim()) {
      _showMessage('Mật khẩu xác nhận không khớp.');
      return;
    }
    if (_selectedDob == null) {
      _showMessage('Vui lòng chọn ngày sinh của bạn.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _loading = true);

    try {
      final email = _emailCtrl.text.trim();
      final password = _passCtrl.text;
      final user = await _auth.signUpWithEmail(email, password);
      if (user == null) {
        throw Exception('Không tạo được tài khoản Firebase.');
      }

      await _auth.register(
        email,
        password,
        name: _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
        gender: _selectedGender,
        dateOfBirth: _selectedDob,
        mainSportId: _selectedMainSportId,
      );
      await _auth.persistSession();

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const VerifyEmailScreen()),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      _handleFirebaseError(e);
    } catch (err) {
      _showMessage('Không thể đăng ký: ${err.toString()}');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _handleFirebaseError(FirebaseAuthException e) {
    String message = 'Không thể đăng ký. Vui lòng thử lại.';
    switch (e.code) {
      case 'email-already-in-use':
        message = 'Email này đã được đăng ký.';
        break;
      case 'weak-password':
        message = 'Mật khẩu cần mạnh hơn.';
        break;
      default:
        message = e.message ?? message;
    }
    _showMessage(message);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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
              constraints: const BoxConstraints(maxWidth: 640),
              child: _buildAnimatedCard(
                colorScheme: colorScheme,
                child: Form(
                  key: _formKey,
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
                        'Tạo tài khoản mới',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: colorScheme.onSecondaryContainer,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Tham gia cộng đồng thể thao và quản lý lịch đặt sân chỉ trong vài bước. ',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSecondaryContainer.withValues(alpha: 0.9),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _sectionTitle(theme, 'Thông tin cá nhân'),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _nameCtrl,
                        focusNode: _nameFocus,
                        textInputAction: TextInputAction.next,
                        decoration: _fieldDecoration(
                          context,
                          label: 'Họ và tên',
                          icon: Icons.person_outline,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Vui lòng nhập họ tên.';
                          }
                          return null;
                        },
                        onEditingComplete: () =>
                            FocusScope.of(context).requestFocus(_genderFocus),
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        focusNode: _genderFocus,
                        initialValue: _selectedGender,
                        decoration: _fieldDecoration(
                          context,
                          label: 'Giới tính',
                          icon: Icons.wc,
                        ),
                        items: const [
                          DropdownMenuItem(value: 'male', child: Text('Nam')),
                          DropdownMenuItem(value: 'female', child: Text('Nữ')),
                          DropdownMenuItem(value: 'other', child: Text('Khác')),
                        ],
                        onChanged: (value) => setState(() => _selectedGender = value),
                        validator: (value) =>
                            value == null ? 'Vui lòng chọn giới tính' : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _dobCtrl,
                        focusNode: _dobFocus,
                        readOnly: true,
                        decoration: _fieldDecoration(
                          context,
                          label: 'Ngày sinh',
                          icon: Icons.cake_outlined,
                          suffix: const Icon(Icons.calendar_today),
                        ),
                        onTap: _loading ? null : _selectDob,
                        validator: (value) =>
                            (value == null || value.isEmpty)
                                ? 'Vui lòng chọn ngày sinh'
                                : null,
                      ),
                      const SizedBox(height: 24),
                      _sectionTitle(theme, 'Thông tin đăng nhập'),
                      const SizedBox(height: 12),
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
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _passCtrl,
                        focusNode: _passwordFocus,
                        obscureText: _obscurePassword,
                        decoration: _fieldDecoration(
                          context,
                          label: 'Mật khẩu',
                          icon: Icons.lock_outline,
                          suffix: IconButton(
                            onPressed: () => setState(() =>
                                _obscurePassword = !_obscurePassword),
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
                        onEditingComplete: () => FocusScope.of(context)
                            .requestFocus(_confirmPasswordFocus),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _confirmPassCtrl,
                        focusNode: _confirmPasswordFocus,
                        obscureText: _obscureConfirmPassword,
                        decoration: _fieldDecoration(
                          context,
                          label: 'Xác nhận mật khẩu',
                          icon: Icons.lock_reset,
                          suffix: IconButton(
                            onPressed: () => setState(() => _obscureConfirmPassword =
                                !_obscureConfirmPassword),
                            icon: Icon(
                              _obscureConfirmPassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Vui lòng nhập lại mật khẩu';
                          }
                          return null;
                        },
                        onFieldSubmitted: (_) => _loading ? null : _submit(),
                      ),
                      const SizedBox(height: 24),
                      _sectionTitle(theme, 'Thông tin thể thao'),
                      const SizedBox(height: 12),
                      _buildMainSportField(context),
                      const SizedBox(height: 24),
                      _buildPrimaryButton(colorScheme),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('Đã có tài khoản?',
                              style: theme.textTheme.bodyMedium),
                          TextButton(
                            onPressed: _loading ? null : _goToLogin,
                            child: const Text('Đăng nhập'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
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
            child: Icon(Icons.sports_handball, size: 38),
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

  Widget _sectionTitle(ThemeData theme, String text) {
    return NeuText(
      text,
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
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

  Widget _buildMainSportField(BuildContext context) {
    if (_sportsLoading) {
      return TextFormField(
        focusNode: _mainSportFocus,
        readOnly: true,
        decoration: _fieldDecoration(
          context,
          label: 'Môn thể thao chính',
          icon: Icons.sports_soccer,
          suffix: const Padding(
            padding: EdgeInsets.only(right: 12),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ).copyWith(hintText: 'Đang tải danh sách môn...'),
      );
    }

    if (_sportsError != null) {
      return TextFormField(
        focusNode: _mainSportFocus,
        readOnly: true,
        decoration: _fieldDecoration(
          context,
          label: 'Môn thể thao chính',
          icon: Icons.sports_soccer,
          suffix: IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSports,
          ),
        ).copyWith(errorText: _sportsError),
      );
    }

    if (_sports.isEmpty) {
      return TextFormField(
        focusNode: _mainSportFocus,
        readOnly: true,
        decoration: _fieldDecoration(
          context,
          label: 'Môn thể thao chính',
          icon: Icons.sports_soccer,
        ).copyWith(hintText: 'Chưa có môn thể thao nào được cấu hình'),
      );
    }

    return DropdownButtonFormField<String>(
      focusNode: _mainSportFocus,
      initialValue: _selectedMainSportId,
      decoration: _fieldDecoration(
        context,
        label: 'Môn thể thao chính',
        icon: Icons.sports_soccer,
      ),
      hint: const Text('Chọn môn yêu thích'),
      items: _sports
          .map(
            (sport) => DropdownMenuItem(
              value: sport.id,
              child: Text(sport.name),
            ),
          )
          .toList(growable: false),
      onChanged: (value) => setState(() => _selectedMainSportId = value),
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
            borderRadius: BorderRadius.circular(18),
            buttonColor: colorScheme.primary,
            shadowColor: Colors.black.withValues(alpha: 0.6),
            borderColor: Colors.black,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
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
                          'Đang tạo tài khoản...',
                          style: TextStyle(
                            color: colorScheme.onPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      'Đăng ký',
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

  void _goToLogin() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
    }
  }
}
