import 'package:flutter/material.dart';
import 'package:neubrutalism_ui/neubrutalism_ui.dart';

import '../widgets/neu_button.dart';
import '../widgets/neo_loading.dart';
import '../models/staff_facility.dart';
import '../models/staff_profile.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../widgets/success_dialog.dart';
import '../screens/auth/login_page.dart';
import 'staff_notifications_page.dart';

class StaffProfilePage extends StatefulWidget {
  const StaffProfilePage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<StaffProfilePage> createState() => _StaffProfilePageState();
}

class _StaffProfilePageState extends State<StaffProfilePage> {
  final _api = ApiService();
  final _auth = AuthService.instance;
  final _scrollController = ScrollController();

  StaffProfile? _profile;
  StaffFacilityData? _facilityData;

  bool _loading = true;
  String? _error;
  bool _compactHeader = false;

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _pwdCurrentController = TextEditingController();
  final _pwdNewController = TextEditingController();
  final _pwdConfirmController = TextEditingController();

  bool _savingProfile = false;
  bool _changingPassword = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _loadData();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _pwdCurrentController.dispose();
    _pwdNewController.dispose();
    _pwdConfirmController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    final collapsed =
        _scrollController.hasClients && _scrollController.offset > 40.0;
    if (collapsed != _compactHeader) {
      setState(() => _compactHeader = collapsed);
    }
  }

  Future<void> _loadData({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final results = await Future.wait([
        _api.staffGetProfile(),
        _api.staffGetFacility(),
      ]);

      final profile = results[0] as StaffProfile;
      final facility = results[1] as StaffFacilityData;

      if (!mounted) return;
      setState(() {
        _profile = profile;
        _facilityData = facility;
        _loading = false;
        _error = null;
      });
      _applyProfile(profile);
      _auth.updateFromProfile(profile);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(error);
        _loading = false;
      });
    }
  }

  void _applyProfile(StaffProfile profile) {
    _nameController.text = profile.name ?? '';
    _emailController.text = profile.email ?? '';
    _phoneController.text = profile.phone ?? '';
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.startsWith('Exception: ')) {
      return text.substring('Exception: '.length);
    }
    return text;
  }

  Future<void> _refresh() => _loadData(showSpinner: false);

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    setState(() => _savingProfile = true);
    try {
      final updated = await _api.staffUpdateProfile(
        name: name.isEmpty ? null : name,
        email: email.isEmpty ? null : email,
        phone: phone.isEmpty ? null : phone,
      );
      if (!mounted) return;
      _applyProfile(updated);
      setState(() => _profile = updated);
      await showSuccessDialog(
        context,
        title: 'Đã lưu hồ sơ',
        message: 'Thông tin nhân viên đã được cập nhật.',
      );
    } catch (error) {
      if (!mounted) return;
      _showSnackBar(_friendlyError(error));
    } finally {
      if (mounted) {
        setState(() => _savingProfile = false);
      }
    }
  }

  Future<void> _changePassword(String current, String next) async {
    setState(() => _changingPassword = true);
    try {
      await _api.staffChangePassword(
        currentPassword: current,
        newPassword: next,
      );
      if (!mounted) return;
      await showSuccessDialog(
        context,
        title: 'Đổi mật khẩu thành công',
        message: 'Bạn có thể đăng nhập lại với mật khẩu mới.',
      );
    } catch (error) {
      if (!mounted) return;
      _showSnackBar(_friendlyError(error));
    } finally {
      if (mounted) {
        setState(() => _changingPassword = false);
      }
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _openEditProfileSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final padding = MediaQuery.of(context).viewInsets;
        return Padding(
          padding: EdgeInsets.only(bottom: padding.bottom + 16, left: 16, right: 16),
          child: _EditProfileForm(
            nameController: _nameController,
            emailController: _emailController,
            phoneController: _phoneController,
            onSubmit: () {
              Navigator.of(context).pop();
              _saveProfile();
            },
            saving: _savingProfile,
          ),
        );
      },
    );
  }

  void _openPasswordSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final padding = MediaQuery.of(context).viewInsets;
        return Padding(
          padding: EdgeInsets.only(bottom: padding.bottom + 16, left: 16, right: 16),
          child: _PasswordForm(
            currentController: _pwdCurrentController,
            newController: _pwdNewController,
            confirmController: _pwdConfirmController,
            saving: _changingPassword,
            onSubmit: () {
              final current = _pwdCurrentController.text.trim();
              final next = _pwdNewController.text.trim();
              final confirm = _pwdConfirmController.text.trim();
              if (current.isEmpty || next.isEmpty || confirm.isEmpty) {
                _showSnackBar('Vui lòng điền đầy đủ thông tin.');
                return;
              }
              if (next != confirm) {
                _showSnackBar('Mật khẩu mới không khớp.');
                return;
              }
              Navigator.of(context).pop();
              _changePassword(current, next);
            },
          ),
        );
      },
    );
  }

  Future<void> _logout() async {
    await AuthService.instance.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaPadding = MediaQuery.of(context).padding;
    final slivers = <Widget>[
      _buildHeader(mediaPadding),
      if (_loading)
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: NeoLoadingCard(
              label: 'Đang tải hồ sơ...',
              width: 260,
            ),
          ),
        )
      else if (_error != null)
        SliverFillRemaining(
          hasScrollBody: false,
          child: _ErrorState(message: _error!, onRetry: _loadData),
        )
      else ...[        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          sliver: SliverToBoxAdapter(child: _buildSettingsCard(context)),
        ),
      ],
      SliverPadding(padding: EdgeInsets.only(bottom: mediaPadding.bottom + 24)),
    ];

    final scrollView = RefreshIndicator(
      onRefresh: _refresh,
      edgeOffset: widget.embedded ? 0 : mediaPadding.top,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: slivers,
      ),
    );

    if (widget.embedded) {
      return SafeArea(top: false, bottom: false, child: scrollView);
    }
    return Scaffold(body: SafeArea(child: scrollView));
  }

  SliverAppBar _buildHeader(EdgeInsets padding) {
    final theme = Theme.of(context);
    final profile = _profile;
    final name = profile?.name?.trim().isNotEmpty == true
        ? profile!.name!
        : 'Nhân viên';
    final email = profile?.email ?? 'Chưa cập nhật';
    final phone = profile?.phone ?? '---';
    final facilityName = _facilityData?.facility.name ??
        profile?.facility?.name ??
        'Chưa gán cơ sở';
    final colorScheme = theme.colorScheme;
    final expandedHeight = widget.embedded ? 220.0 : 260.0;

    return SliverAppBar(
      expandedHeight: expandedHeight,
      backgroundColor: colorScheme.surface,
      pinned: true,
      automaticallyImplyLeading: !widget.embedded,
      title: AnimatedOpacity(
        opacity: _compactHeader ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: Text(name, overflow: TextOverflow.ellipsis),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          children: [
            // Pastel gradient background
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFFE8F5E9), // light green
                    Color(0xFFE6F3FF), // light blue
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            // Decorative brutalist accent shape
            Positioned(
              top: padding.top + 70,
              right: -30,
              child: Transform.rotate(
                angle: -0.2,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8DC).withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.black, width: 2),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black,
                        offset: Offset(4, 4),
                        blurRadius: 0,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Main header content
            Padding(
              padding: EdgeInsets.fromLTRB(16, padding.top + 24, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  NeuContainer(
                    color: Colors.white,
                    borderColor: Colors.black,
                    borderWidth: 3,
                    borderRadius: BorderRadius.circular(20),
                    shadowColor: Colors.black.withValues(alpha: 0.3),
                    offset: const Offset(6, 6),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Avatar
                          Hero(
                            tag: 'profile-avatar',
                            child: Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFE5E5),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.black, width: 3),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black,
                                    offset: Offset(5, 5),
                                    blurRadius: 0,
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  name.characters.first.toUpperCase(),
                                  style: theme.textTheme.headlineMedium?.copyWith(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Info column
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  email,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: Colors.grey[700],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  phone,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                // Role & facility badges
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    NeuContainer(
                                      color: const Color(0xFFE6F3FF),
                                      borderColor: Colors.black,
                                      borderWidth: 2,
                                      borderRadius: BorderRadius.circular(16),
                                      shadowColor: Colors.black.withValues(alpha: 0.25),
                                      offset: const Offset(3, 3),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.badge,
                                              size: 16,
                                              color: colorScheme.primary,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              'Staff',
                                              style: theme.textTheme.labelLarge?.copyWith(
                                                color: colorScheme.primary,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    NeuContainer(
                                      color: const Color(0xFFFFF8DC),
                                      borderColor: Colors.black,
                                      borderWidth: 2,
                                      borderRadius: BorderRadius.circular(16),
                                      shadowColor: Colors.black.withValues(alpha: 0.25),
                                      offset: const Offset(3, 3),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.business,
                                              size: 14,
                                              color: colorScheme.primary,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              facilityName,
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                color: colorScheme.primary,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsCard(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return NeuContainer(
      borderRadius: BorderRadius.circular(24),
      color: scheme.surface,
      borderColor: Colors.black,
      borderWidth: 3,
      shadowColor: Colors.black.withValues(alpha:0.25),
      offset: const Offset(6, 6),
      child: Column(
        children: [
          _SettingsTile(
            icon: Icons.person_outline,
            title: 'Thông tin cá nhân',
            subtitle: 'Chỉnh sửa họ tên, email, số điện thoại',
            onTap: _openEditProfileSheet,
          ),
          const Divider(height: 1),
          _SettingsTile(
            icon: Icons.lock_reset,
            title: 'Đổi mật khẩu',
            subtitle: 'Bảo vệ tài khoản của bạn',
            onTap: _openPasswordSheet,
          ),
          const Divider(height: 1),
          _SettingsTile(
            icon: Icons.notifications_active_outlined,
            title: 'Thông báo',
            subtitle: 'Xem và đánh dấu đã đọc',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => StaffNotificationsPage()),
              );
            },
          ),
          const Divider(height: 1),
          _SettingsTile(
            icon: Icons.logout,
            title: 'Đăng xuất',
            subtitle: 'Kết thúc ca làm việc',
            iconColor: scheme.error,
            titleColor: scheme.error,
            onTap: _logout,
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor,
    this.titleColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: iconColor ?? theme.colorScheme.primary,
            width: 2,
          ),
        ),
        child: Icon(icon, color: iconColor ?? theme.colorScheme.primary, size: 20),
      ),
      title: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          color: titleColor,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
      ),
      trailing: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.black, width: 2),
        ),
        child: const Icon(Icons.chevron_right, size: 20),
      ),
      onTap: onTap,
    );
  }
}

class _EditProfileForm extends StatelessWidget {
  const _EditProfileForm({
    required this.nameController,
    required this.emailController,
    required this.phoneController,
    required this.onSubmit,
    required this.saving,
  });

  final TextEditingController nameController;
  final TextEditingController emailController;
  final TextEditingController phoneController;
  final VoidCallback onSubmit;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Cập nhật hồ sơ',
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: nameController,
          decoration: InputDecoration(
            labelText: 'Họ và tên',
            labelStyle: const TextStyle(fontWeight: FontWeight.w600),
            prefixIcon: const Icon(Icons.person_outline),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.black, width: 2.4),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.black, width: 2.4),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.black, width: 3),
            ),
            filled: true,
            fillColor: Colors.white,
          ),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: emailController,
          decoration: InputDecoration(
            labelText: 'Email',
            labelStyle: const TextStyle(fontWeight: FontWeight.w600),
            prefixIcon: const Icon(Icons.email_outlined),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.black, width: 2.4),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.black, width: 2.4),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.black, width: 3),
            ),
            filled: true,
            fillColor: Colors.white,
          ),
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: phoneController,
          decoration: InputDecoration(
            labelText: 'Số điện thoại',
            labelStyle: const TextStyle(fontWeight: FontWeight.w600),
            prefixIcon: const Icon(Icons.phone_outlined),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.black, width: 2.4),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.black, width: 2.4),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.black, width: 3),
            ),
            filled: true,
            fillColor: Colors.white,
          ),
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 24),
        NeuButton(
          onPressed: saving ? null : onSubmit,
          buttonHeight: 56,
          buttonWidth: double.infinity,
          borderRadius: BorderRadius.circular(16),
          borderColor: Colors.black,
          buttonColor: theme.colorScheme.primary,
          shadowColor: Colors.black.withValues(alpha:0.35),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (saving)
                const NeoLoadingDot(
                  size: 18,
                  fillColor: Colors.white,
                )
              else
                const Icon(Icons.save_outlined, color: Colors.white),
              const SizedBox(width: 12),
              Text(
                saving ? 'Đang lưu...' : 'Lưu thay đổi',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PasswordForm extends StatefulWidget {
  const _PasswordForm({
    required this.currentController,
    required this.newController,
    required this.confirmController,
    required this.onSubmit,
    required this.saving,
  });

  final TextEditingController currentController;
  final TextEditingController newController;
  final TextEditingController confirmController;
  final VoidCallback onSubmit;
  final bool saving;

  @override
  State<_PasswordForm> createState() => _PasswordFormState();
}

class _PasswordFormState extends State<_PasswordForm> {
  bool _showCurrent = false;
  bool _showNew = false;
  bool _showConfirm = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Đổi mật khẩu',
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: widget.currentController,
          obscureText: !_showCurrent,
          decoration: InputDecoration(
            labelText: 'Mật khẩu hiện tại',
            labelStyle: const TextStyle(fontWeight: FontWeight.w600),
            prefixIcon: const Icon(Icons.lock_clock_outlined),
            suffixIcon: IconButton(
              onPressed: () => setState(() => _showCurrent = !_showCurrent),
              icon: Icon(_showCurrent ? Icons.visibility_off : Icons.visibility),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.black, width: 2.4),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.black, width: 2.4),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.black, width: 3),
            ),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: widget.newController,
          obscureText: !_showNew,
          decoration: InputDecoration(
            labelText: 'Mật khẩu mới',
            labelStyle: const TextStyle(fontWeight: FontWeight.w600),
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              onPressed: () => setState(() => _showNew = !_showNew),
              icon: Icon(_showNew ? Icons.visibility_off : Icons.visibility),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.black, width: 2.4),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.black, width: 2.4),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.black, width: 3),
            ),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: widget.confirmController,
          obscureText: !_showConfirm,
          decoration: InputDecoration(
            labelText: 'Xác nhận mật khẩu mới',
            labelStyle: const TextStyle(fontWeight: FontWeight.w600),
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              onPressed: () => setState(() => _showConfirm = !_showConfirm),
              icon: Icon(_showConfirm ? Icons.visibility_off : Icons.visibility),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.black, width: 2.4),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.black, width: 2.4),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.black, width: 3),
            ),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        const SizedBox(height: 24),
        NeuButton(
          onPressed: widget.saving ? null : widget.onSubmit,
          buttonHeight: 56,
          buttonWidth: double.infinity,
          borderRadius: BorderRadius.circular(16),
          borderColor: Colors.black,
          buttonColor: theme.colorScheme.primary,
          shadowColor: Colors.black.withValues(alpha:0.35),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.saving)
                const NeoLoadingDot(
                  size: 18,
                  fillColor: Colors.white,
                )
              else
                const Icon(Icons.vpn_key_outlined, color: Colors.white),
              const SizedBox(width: 12),
              Text(
                widget.saving ? 'Đang đổi...' : 'Cập nhật mật khẩu',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: NeuContainer(
        borderRadius: BorderRadius.circular(24),
        color: theme.colorScheme.surface,
        borderColor: Colors.black,
        borderWidth: 3,
        shadowColor: Colors.black.withValues(alpha:0.25),
        offset: const Offset(8, 8),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 56),
              const SizedBox(height: 16),
              Text(
                'Không thể tải hồ sơ',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              NeuButton(
                onPressed: onRetry,
                buttonHeight: 48,
                buttonWidth: 160,
                borderRadius: BorderRadius.circular(16),
                borderColor: Colors.black,
                buttonColor: theme.colorScheme.primary,
                shadowColor: Colors.black.withValues(alpha:0.35),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.refresh, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      'Thử lại',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
