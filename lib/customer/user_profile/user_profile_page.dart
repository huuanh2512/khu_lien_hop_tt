import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:neubrutalism_ui/neubrutalism_ui.dart';

import '../../models/booking.dart';
import '../../widgets/neu_button.dart';
import '../../models/match_request.dart';
import '../../models/sport.dart';
import '../../models/user_invoice.dart';
import '../../models/user_profile.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/user_billing_service.dart';
import '../../widgets/success_dialog.dart';
import '../../screens/auth/login_page.dart';
import '../user_booking/booking_history_page.dart';
import '../user_finance/user_invoices_page.dart';

class UserProfilePage extends StatefulWidget {
  const UserProfilePage({
    super.key,
    this.embedded = false,
    this.onProfileChanged,
  });

  final bool embedded;
  final VoidCallback? onProfileChanged;

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  final _api = ApiService();
  final _billing = UserBillingService();
  final _auth = AuthService.instance;
  final _scrollController = ScrollController();

  UserProfile? _profile;
  List<Sport> _sports = const <Sport>[];
  List<Booking> _bookings = const <Booking>[];
  List<UserInvoice> _invoices = const <UserInvoice>[];
  List<MatchRequest> _matchRequests = const <MatchRequest>[];

  bool _loading = true;
  String? _error;

  // profile edit state
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _dobController = TextEditingController();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  String? _selectedGender;
  DateTime? _selectedDob;
  String? _selectedMainSportId;

  bool _savingProfile = false;
  bool _savingPassword = false;
  bool _notifEnabled = true;
  bool _reminderEnabled = true;
  bool _compactHeader = false;
  int _activitySegment = 0; // 0 booking, 1 invoices, 2 matches

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
    _phoneController.dispose();
    _dobController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadData({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final results = await Future.wait([
        _api.getUserProfile(),
        _api.getSports(includeCount: false),
        _api.getUserBookings(),
        _api.getUserInvoices(limit: 20),
        _api.getMatchRequests(limit: 20),
        _billing.fetchInvoices(),
      ]);

      final profile = results[0] as UserProfile;
      final sports = results[1] as List<Sport>;
      final bookings = results[2] as List<Booking>;
      final invoicesFromApi = results[3] as List<UserInvoice>;
      final matchRequests = results[4] as List<MatchRequest>;
      final billingInvoices = results[5] as List<UserInvoice>;

      final mergedInvoices = _mergeInvoices(invoicesFromApi, billingInvoices);

      if (!mounted) return;

      setState(() {
        _profile = profile;
        _sports = sports;
        _bookings = bookings;
        _invoices = mergedInvoices;
        _matchRequests = matchRequests;
        _loading = false;
      });
      _applyProfile(profile);
      widget.onProfileChanged?.call();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(error);
        _loading = false;
      });
    }
  }

  void _handleScroll() {
    final collapsed = _scrollController.hasClients &&
        _scrollController.offset > 32.0;
    if (collapsed != _compactHeader) {
      setState(() => _compactHeader = collapsed);
    }
  }

  void _applyProfile(UserProfile profile) {
    _nameController.text = profile.name ?? '';
    _phoneController.text = profile.phone ?? '';
    _selectedGender = profile.gender;
    _selectedMainSportId = profile.mainSportId;
    final dob = profile.dateOfBirth;
    if (dob != null) {
      final localDob = dob.toLocal();
      _selectedDob = DateTime(localDob.year, localDob.month, localDob.day);
    } else {
      _selectedDob = null;
    }
    _dobController.text = _selectedDob != null
        ? DateFormat('dd/MM/yyyy').format(_selectedDob!)
        : '';
  }

  List<UserInvoice> _mergeInvoices(
    List<UserInvoice> api,
    List<UserInvoice> billing,
  ) {
    if (api.isEmpty) return billing;
    if (billing.isEmpty) return api;
    final map = <String, UserInvoice>{
      for (final invoice in api) invoice.id: invoice,
    };
    for (final invoice in billing) {
      map.putIfAbsent(invoice.id, () => invoice);
    }
    final merged = map.values.toList(growable: false)
      ..sort((a, b) => b.issuedAt.compareTo(a.issuedAt));
    return merged;
  }

  String _friendlyError(Object error) {
    return error is Exception
        ? error.toString().replaceFirst('Exception: ', '')
        : 'Đã xảy ra lỗi không xác định';
  }

  Future<void> _onRefresh() => _loadData(showLoading: false);

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final initial = _selectedDob ?? DateTime(now.year - 20, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1960),
      lastDate: DateTime(now.year - 10),
      helpText: 'Ngày sinh',
    );
    if (picked != null) {
      final normalized = DateTime(picked.year, picked.month, picked.day);
      setState(() {
        _selectedDob = normalized;
        _dobController.text = DateFormat('dd/MM/yyyy').format(normalized);
      });
    }
  }

  Future<void> _saveProfile() async {
    final profile = _profile;
    if (profile == null) return;
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    setState(() => _savingProfile = true);
    try {
      final updated = await _api.updateUserProfile(
        name: name.isEmpty ? null : name,
        phone: phone.isEmpty ? null : phone,
        gender: _selectedGender,
        dateOfBirth: _selectedDob == null
            ? null
            : DateTime.utc(
                _selectedDob!.year,
                _selectedDob!.month,
                _selectedDob!.day,
              ),
        includeDateOfBirth: true,
        mainSportId: _selectedMainSportId,
        includeMainSportId: true,
      );
      _applyProfile(updated);
      setState(() => _profile = updated);
      _auth.updateFromUserProfile(updated);
      widget.onProfileChanged?.call();
      if (mounted) {
        await showSuccessDialog(
          context,
          title: 'Đã lưu hồ sơ',
          message: 'Thông tin cá nhân của bạn đã được cập nhật.',
        );
      }
    } catch (error) {
      if (!mounted) return;
      _showSnackBar(_friendlyError(error));
    } finally {
      if (mounted) {
        setState(() => _savingProfile = false);
      }
    }
  }

  Future<void> _changePassword() async {
    final current = _currentPasswordController.text.trim();
    final next = _newPasswordController.text.trim();
    final confirm = _confirmPasswordController.text.trim();
    if (current.isEmpty || next.isEmpty || confirm.isEmpty) {
      _showSnackBar('Vui lòng điền đầy đủ thông tin mật khẩu');
      return;
    }
    if (next != confirm) {
      _showSnackBar('Mật khẩu mới không trùng khớp');
      return;
    }
    setState(() => _savingPassword = true);
    try {
      await _api.updateUserPassword(
        currentPassword: current,
        newPassword: next,
      );
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      if (mounted) {
        await showSuccessDialog(
          context,
          title: 'Đổi mật khẩu thành công',
          message: 'Bạn có thể đăng nhập với mật khẩu mới ngay bây giờ.',
        );
      }
    } catch (error) {
      if (!mounted) return;
      _showSnackBar(_friendlyError(error));
    } finally {
      if (mounted) {
        setState(() => _savingPassword = false);
      }
    }
  }

  void _showSnackBar(String message) {
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
          padding: EdgeInsets.only(bottom: padding.bottom + 16),
          child: _ProfileForm(
            nameController: _nameController,
            phoneController: _phoneController,
            dobController: _dobController,
            selectedGender: _selectedGender,
            selectedDob: _selectedDob,
            selectedSport: _selectedMainSportId,
            sports: _sports,
            onGenderChanged: (value) => setState(() => _selectedGender = value),
            onSportChanged: (value) => setState(() => _selectedMainSportId = value),
            onPickDob: _pickDateOfBirth,
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
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final padding = MediaQuery.of(context).viewInsets;
        return Padding(
          padding: EdgeInsets.only(bottom: padding.bottom + 16),
          child: _PasswordForm(
            currentController: _currentPasswordController,
            newController: _newPasswordController,
            confirmController: _confirmPasswordController,
            onSubmit: () {
              Navigator.of(context).pop();
              _changePassword();
            },
            saving: _savingPassword,
          ),
        );
      },
    );
  }

  void _handleLogout() async {
    await AuthService.instance.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  void _openInvoicesPage() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const UserInvoicesPage()),
    );
  }

  void _openBookingHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BookingHistoryPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaPadding = MediaQuery.of(context).padding;
    final slivers = <Widget>[
      _buildHeader(theme, mediaPadding),
      if (_loading)
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        )
      else if (_error != null)
        SliverFillRemaining(
          hasScrollBody: false,
          child: _ErrorState(message: _error!, onRetry: _loadData),
        )
      else
        ..._buildContent(theme, mediaPadding),
      SliverPadding(padding: EdgeInsets.only(bottom: mediaPadding.bottom + 24)),
    ];

    final scrollView = RefreshIndicator(
      onRefresh: _onRefresh,
      edgeOffset: widget.embedded ? 0 : mediaPadding.top,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        slivers: slivers,
      ),
    );

    if (widget.embedded) {
      return SafeArea(
        top: false,
        bottom: false,
        child: scrollView,
      );
    }

    return Scaffold(body: SafeArea(child: scrollView));
  }

  List<Widget> _buildContent(ThemeData theme, EdgeInsets mediaPadding) {
    final contentPadding = EdgeInsets.fromLTRB(16, 12, 16, 0);
    return [
      SliverPadding(
        padding: contentPadding,
        sliver: SliverToBoxAdapter(child: _buildQuickActionsCard(theme)),
      ),
      SliverPadding(
        padding: contentPadding,
        sliver: SliverToBoxAdapter(child: _buildStatsGrid(theme)),
      ),
      SliverPadding(
        padding: contentPadding,
        sliver: SliverToBoxAdapter(child: _buildPersonalInfoCard(theme)),
      ),
      SliverPadding(
        padding: contentPadding,
        sliver: SliverToBoxAdapter(child: _buildSportsCard(theme)),
      ),
      SliverPadding(
        padding: contentPadding,
        sliver: SliverToBoxAdapter(child: _buildActivityCard(theme)),
      ),
      SliverPadding(
        padding: contentPadding,
        sliver: SliverToBoxAdapter(child: _buildSettingsCard(theme)),
      ),
    ];
  }

  Widget _buildHeader(ThemeData theme, EdgeInsets padding) {
    final profile = _profile;
    final name = profile?.name ?? 'Khách hàng';
    final email = profile?.email ?? _auth.currentUser?.email ?? '';
    final tier = profile?.membershipTier ?? 'silver';
    final expires = profile?.membershipExpiresAt;
    final colorScheme = theme.colorScheme;
    final expandedHeight = widget.embedded ? 220.0 : 260.0;

    return SliverAppBar(
      expandedHeight: expandedHeight,
      backgroundColor: colorScheme.surface,
      pinned: true,
      floating: false,
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
                    Color(0xFFFFE5E5), // light pink
                    Color(0xFFE6F3FF), // light blue
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            // Decorative brutalist accent shape
            Positioned(
              top: padding.top + 60,
              right: -20,
              child: Transform.rotate(
                angle: 0.15,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8DC).withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(20),
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
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE6F3FF),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.black, width: 3),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black,
                                  offset: Offset(4, 4),
                                  blurRadius: 0,
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                name.isEmpty ? 'KH' : name.characters.first.toUpperCase(),
                                style: theme.textTheme.headlineMedium?.copyWith(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.w900,
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
                                const SizedBox(height: 8),
                                // Membership badge
                                Row(
                                  children: [
                                    NeuContainer(
                                      color: const Color(0xFFFFF8DC),
                                      borderColor: Colors.black,
                                      borderWidth: 2,
                                      borderRadius: BorderRadius.circular(12),
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
                                              Icons.workspace_premium,
                                              size: 16,
                                              color: colorScheme.primary,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              tier.toUpperCase(),
                                              style: theme.textTheme.labelLarge?.copyWith(
                                                color: colorScheme.primary,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (expires != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Hết hạn: ${DateFormat('dd/MM/yyyy').format(expires)}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: Colors.grey[600],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionsCard(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    return NeuContainer(
      borderRadius: BorderRadius.circular(24),
      color: const Color(0xFFFFF8DC),
      borderColor: Colors.black,
      borderWidth: 3,
      shadowColor: Colors.black.withValues(alpha:0.25),
      offset: const Offset(6, 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tác vụ nhanh',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                NeuButton(
                  onPressed: _openEditProfileSheet,
                  buttonHeight: 40,
                  buttonWidth: 135,
                  borderRadius: BorderRadius.circular(12),
                  borderColor: Colors.black,
                  buttonColor: Colors.white,
                  shadowColor: Colors.black.withValues(alpha:0.3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit_outlined, size: 18, color: colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        'Chỉnh sửa',
                        style: TextStyle(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                NeuButton(
                  onPressed: _openBookingHistory,
                  buttonHeight: 40,
                  buttonWidth: 170,
                  borderRadius: BorderRadius.circular(12),
                  borderColor: Colors.black,
                  buttonColor: Colors.white,
                  shadowColor: Colors.black.withValues(alpha:0.3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.calendar_month_outlined, size: 18, color: colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        'Lịch sử đặt sân',
                        style: TextStyle(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                NeuButton(
                  onPressed: _openInvoicesPage,
                  buttonHeight: 40,
                  buttonWidth: 160,
                  borderRadius: BorderRadius.circular(12),
                  borderColor: Colors.black,
                  buttonColor: Colors.white,
                  shadowColor: Colors.black.withValues(alpha:0.3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.receipt_long_outlined, size: 18, color: colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        'Hoá đơn của tôi',
                        style: TextStyle(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid(ThemeData theme) {
    final metrics = _buildMetrics();
    return NeuContainer(
      borderRadius: BorderRadius.circular(24),
      color: const Color(0xFFE6F3FF),
      borderColor: Colors.black,
      borderWidth: 3,
      shadowColor: Colors.black.withValues(alpha:0.25),
      offset: const Offset(6, 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Chỉ số vận động',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 520;
                final columns = isWide ? 4 : 2;
                return Wrap(
                  runSpacing: 12,
                  spacing: 12,
                  children: [
                    for (final metric in metrics)
                      SizedBox(
                        width: (constraints.maxWidth - (columns - 1) * 12) /
                            columns,
                        child: _MetricTile(metric: metric),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  List<_Metric> _buildMetrics() {
    final now = DateTime.now();
    final upcoming = _bookings
        .where((booking) => booking.end.toLocal().isAfter(now))
        .length;
    final totalHours = _bookings.fold<double>(0, (sum, booking) {
      final minutes = booking.end.difference(booking.start).inMinutes;
      return sum + minutes / 60.0;
    });
    final energy = math.min(100, (totalHours * 8).round());
    final unpaidInvoices = _invoices
        .where((invoice) => invoice.status.toLowerCase() != 'paid')
        .length;
    final matchesJoined = _matchRequests.where((mr) => mr.hasJoined).length;

    return [
      _Metric(
        label: 'Lịch sắp tới',
        value: upcoming.toString(),
        icon: Icons.event_available,
        trend: upcoming > 2 ? '+ Nhiều' : 'Ổn định',
      ),
      _Metric(
        label: 'Giờ vận động',
        value: totalHours.toStringAsFixed(1),
        icon: Icons.access_time,
        trend: '${energy.toString()}% năng lượng',
      ),
      _Metric(
        label: 'Hoá đơn chưa trả',
        value: unpaidInvoices.toString(),
        icon: Icons.receipt_long,
        trend: unpaidInvoices == 0 ? 'Đã thanh toán' : 'Cần xử lý',
      ),
      _Metric(
        label: 'Trận đã tham gia',
        value: matchesJoined.toString(),
        icon: Icons.groups,
        trend: matchesJoined > 0 ? 'Rất tích cực' : 'Bắt đầu ngay',
      ),
    ];
  }

  Widget _buildPersonalInfoCard(ThemeData theme) {
    final profile = _profile;
    if (profile == null) return const SizedBox.shrink();
    final infoItems = [
      _InfoRow(
        icon: Icons.badge_outlined,
        label: 'Họ và tên',
        value: profile.name ?? 'Chưa cập nhật',
      ),
      _InfoRow(
        icon: Icons.email_outlined,
        label: 'Email',
        value: profile.email,
      ),
      _InfoRow(
        icon: Icons.phone_outlined,
        label: 'Số điện thoại',
        value: profile.phone ?? 'Chưa cập nhật',
      ),
      _InfoRow(
        icon: Icons.cake_outlined,
        label: 'Ngày sinh',
        value: profile.dateOfBirth == null
            ? 'Chưa cung cấp'
            : DateFormat('dd/MM/yyyy', 'vi').format(
                profile.dateOfBirth!.toLocal(),
              ),
      ),
      _InfoRow(
        icon: _genderIcon(profile.gender),
        label: 'Giới tính',
        value: _genderLabel(profile.gender),
      ),
    ];

    return NeuContainer(
      borderRadius: BorderRadius.circular(24),
      color: const Color(0xFFFFE6F0),
      borderColor: Colors.black,
      borderWidth: 3,
      shadowColor: Colors.black.withValues(alpha:0.25),
      offset: const Offset(6, 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Thông tin cá nhân',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Chỉnh sửa',
                  onPressed: _openEditProfileSheet,
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...infoItems.map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: item,
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildSportsCard(ThemeData theme) {
    final mainSport = _sports.firstWhere(
      (sport) => sport.id == _selectedMainSportId,
      orElse: () => const Sport(id: '', name: 'Chưa chọn', code: ''),
    );

    return NeuContainer(
      borderRadius: BorderRadius.circular(24),
      color: const Color(0xFFE8F5E9),
      borderColor: Colors.black,
      borderWidth: 3,
      shadowColor: Colors.black.withValues(alpha:0.25),
      offset: const Offset(6, 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Môn thể thao',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.sports_martial_arts, color: theme.colorScheme.primary),
              title: const Text('Môn chính'),
              subtitle: Text(mainSport.name),
              trailing: IconButton(
                onPressed: _openEditProfileSheet,
                icon: const Icon(Icons.swap_horiz_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityCard(ThemeData theme) {
    final tabs = <int, String>{0: 'Đặt sân', 1: 'Hoá đơn', 2: 'Ghép trận'};
    final activityItems = _activityItems();
    return NeuContainer(
      borderRadius: BorderRadius.circular(24),
      color: const Color(0xFFF3E5F5),
      borderColor: Colors.black,
      borderWidth: 3,
      shadowColor: Colors.black.withValues(alpha:0.25),
      offset: const Offset(6, 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hoạt động gần đây',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Những lần đặt sân, thanh toán, ghép trận bạn vừa thực hiện',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Xem tất cả',
                  onPressed: () {
                    if (_activitySegment == 0) {
                      _openBookingHistory();
                    } else if (_activitySegment == 1) {
                      _openInvoicesPage();
                    }
                  },
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<int>(
              segments: tabs.entries
                  .map(
                    (entry) => ButtonSegment<int>(
                      value: entry.key,
                      label: Text(entry.value),
                      icon: Icon(entry.key == 0
                          ? Icons.calendar_month
                          : entry.key == 1
                              ? Icons.receipt_long
                              : Icons.people_alt_outlined),
                    ),
                  )
                  .toList(),
              selected: <int>{_activitySegment},
              onSelectionChanged: (selection) {
                setState(() => _activitySegment = selection.first);
              },
            ),
            const SizedBox(height: 16),
            if (activityItems.isEmpty)
              _buildEmptyActivityState(theme)
            else
              ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: activityItems.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final item = activityItems[index];
                  return NeuContainer(
                    borderRadius: BorderRadius.circular(16),
                    color: Colors.white,
                    borderColor: Colors.black,
                    borderWidth: 2,
                    shadowColor: Colors.black.withValues(alpha:0.2),
                    offset: const Offset(3, 3),
                    child: InkWell(
                      onTap: item.onTap,
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                        child: Row(
                          children: [
                            _buildActivityIcon(theme, item.icon),
                            const SizedBox(width: 12),
                            Expanded(child: _buildActivityTexts(theme, item)),
                            const SizedBox(width: 8),
                            _buildActivityStatusChip(theme, item.status),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  List<_RecentActivityItem> _activityItems() {
    switch (_activitySegment) {
      case 0:
        final sortedBookings = [..._bookings]
          ..sort((a, b) => b.start.compareTo(a.start));
        return sortedBookings.take(5).map((booking) {
          final sportName = booking.sportName ?? 'môn thể thao';
          final details = [
            if (booking.courtName != null && booking.courtName!.isNotEmpty)
              'Sân ${booking.courtName}',
            if (booking.facilityName != null && booking.facilityName!.isNotEmpty)
              booking.facilityName!,
          ].join(' - ');
          return _RecentActivityItem(
            icon: Icons.sports_tennis,
            title: 'Đặt sân $sportName',
            timeText: _formatActivityTime(booking.start),
            detail: details.isEmpty ? null : details,
            status: booking.status,
            onTap: null,
          );
        }).toList();
      case 1:
        final sortedInvoices = [..._invoices]
          ..sort((a, b) => b.issuedAt.compareTo(a.issuedAt));
        return sortedInvoices.take(5).map((invoice) {
          final amountText = _formatCurrency(invoice.amount, invoice.currency);
          final description = invoice.description?.trim();
          return _RecentActivityItem(
            icon: Icons.receipt_long,
            title: description?.isNotEmpty == true ? description! : 'Thanh toán hoá đơn',
            timeText: _formatActivityTime(invoice.issuedAt),
            detail: 'Số tiền: $amountText',
            status: invoice.status,
            onTap: null,
          );
        }).toList();
      default:
        final sortedMatches = [..._matchRequests]
          ..sort((a, b) =>
              (b.createdAt ?? DateTime.now()).compareTo(a.createdAt ?? DateTime.now()));
        return sortedMatches.take(5).map((match) {
          final sportLabel = match.sportName?.trim();
          final time = match.desiredStart ?? match.createdAt ?? DateTime.now();
          final skillLabel = _formatSkillRange(match.skillMin, match.skillMax);
          final description = 'Môn: ${match.sportName ?? 'Đang cập nhật'}'
              '${skillLabel != null ? ' - Trình độ: $skillLabel' : ''}';
          return _RecentActivityItem(
            icon: Icons.groups_2,
            title: sportLabel == null || sportLabel.isEmpty
                ? 'Yêu cầu ghép trận'
                : 'Yêu cầu ghép trận $sportLabel',
            timeText: _formatActivityTime(time),
            detail: description,
            status: match.status,
            onTap: null,
          );
        }).toList();
    }
  }

  Widget _buildEmptyActivityState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.history_toggle_off, size: 40, color: theme.colorScheme.outline),
          const SizedBox(height: 8),
          Text(
            'Chưa có hoạt động nào gần đây',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'Hãy đặt sân hoặc tham gia trận đấu để xem lịch sử ở đây.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildActivityIcon(ThemeData theme, IconData icon) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.primary, width: 2),
      ),
      child: Icon(icon, size: 20, color: theme.colorScheme.primary),
    );
  }

  Widget _buildActivityTexts(ThemeData theme, _RecentActivityItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.title,
          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(
          item.timeText,
          style: theme.textTheme.bodySmall,
        ),
        if (item.detail != null && item.detail!.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            item.detail!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  Widget _buildActivityStatusChip(ThemeData theme, String status) {
    final label = _getActivityStatusLabel(status);
    final color = _getActivityStatusColor(theme, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black, offset: Offset(2, 2), blurRadius: 0),
        ],
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _formatActivityTime(DateTime dateTime) {
    final formatter = DateFormat('dd/MM/yyyy HH:mm');
    return formatter.format(dateTime.toLocal());
  }

  String? _formatSkillRange(int? min, int? max) {
    if (min == null && max == null) return null;
    if (min != null && max != null) return '$min–$max';
    return (min ?? max).toString();
  }

  String _formatCurrency(double amount, String currency) {
    final upperCurrency = currency.toUpperCase();
    if (upperCurrency == 'VND') {
      final formatter = NumberFormat.currency(locale: 'vi_VN', symbol: '', decimalDigits: 0);
      final formatted = formatter.format(amount);
      return '${formatted.trim()} đ';
    }
    final formatter = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '$upperCurrency ',
      decimalDigits: amount % 1 == 0 ? 0 : 2,
    );
    return formatter.format(amount);
  }

  String _getActivityStatusLabel(String? status) {
    final normalized = status?.toLowerCase();
    switch (normalized) {
      case 'pending':
        return 'Đang chờ';
      case 'confirmed':
        return 'Đã xác nhận';
      case 'completed':
        return 'Đã hoàn thành';
      case 'cancelled':
        return 'Đã huỷ';
      case 'failed':
        return 'Thất bại';
      case 'paid':
        return 'Đã thanh toán';
      case 'unpaid':
        return 'Chưa thanh toán';
      case 'open':
        return 'Đang mở';
      case 'full':
        return 'Đã đủ người';
      case 'closed':
        return 'Đã đóng';
      default:
        return status ?? 'Không xác định';
    }
  }

  Color _getActivityStatusColor(ThemeData theme, String? status) {
    final normalized = status?.toLowerCase() ?? '';
    if (normalized == 'pending' || normalized == 'open' || normalized == 'unpaid') {
      return Colors.orange;
    }
    if (normalized == 'confirmed' || normalized == 'completed' || normalized == 'paid') {
      return Colors.green;
    }
    if (normalized == 'cancelled' || normalized == 'failed') {
      return theme.colorScheme.error;
    }
    if (normalized == 'full' || normalized == 'closed') {
      return theme.colorScheme.outline;
    }
    return theme.colorScheme.primary;
  }

  Widget _buildSettingsCard(ThemeData theme) {
    return NeuContainer(
      borderRadius: BorderRadius.circular(24),
      color: theme.colorScheme.surface,
      borderColor: Colors.black,
      borderWidth: 3,
      shadowColor: Colors.black.withValues(alpha:0.25),
      offset: const Offset(6, 6),
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('Nhận thông báo đẩy'),
            subtitle: const Text('Cập nhật nhanh về lịch đặt sân và ưu đãi'),
            value: _notifEnabled,
            onChanged: (value) => setState(() => _notifEnabled = value),
          ),
          SwitchListTile(
            title: const Text('Nhắc lịch trước giờ chơi'),
            value: _reminderEnabled,
            onChanged: (value) => setState(() => _reminderEnabled = value),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Đổi mật khẩu'),
            onTap: _openPasswordSheet,
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Đăng xuất'),
            textColor: theme.colorScheme.error,
            iconColor: theme.colorScheme.error,
            onTap: _handleLogout,
          ),
        ],
      ),
    );
  }

  String _genderLabel(String? gender) {
    switch (gender) {
      case 'male':
        return 'Nam';
      case 'female':
        return 'Nữ';
      case 'other':
        return 'Khác';
      default:
        return 'Chưa cung cấp';
    }
  }

  IconData _genderIcon(String? gender) {
    switch (gender) {
      case 'male':
        return Icons.male;
      case 'female':
        return Icons.female;
      case 'other':
        return Icons.wc;
      default:
        return Icons.transgender;
    }
  }
}

class _Metric {
  const _Metric({
    required this.label,
    required this.value,
    required this.icon,
    required this.trend,
  });

  final String label;
  final String value;
  final IconData icon;
  final String trend;
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.metric});

  final _Metric metric;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return NeuContainer(
      borderRadius: BorderRadius.circular(18),
      color: Colors.white,
      borderColor: Colors.black,
      borderWidth: 2.5,
      shadowColor: Colors.black.withValues(alpha:0.25),
      offset: const Offset(4, 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.primary, width: 2),
              ),
              child: Icon(metric.icon, color: scheme.primary, size: 20),
            ),
            const SizedBox(height: 8),
            Text(
              metric.value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              metric.label,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            Text(
              metric.trend,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: theme.textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecentActivityItem {
  const _RecentActivityItem({
    required this.icon,
    required this.title,
    required this.timeText,
    this.detail,
    required this.status,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String timeText;
  final String? detail;
  final String status;
  final VoidCallback? onTap;
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
              Text(
                message,
                textAlign: TextAlign.center,
              ),
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

class _ProfileForm extends StatelessWidget {
  const _ProfileForm({
    required this.nameController,
    required this.phoneController,
    required this.dobController,
    required this.selectedGender,
    required this.selectedDob,
    required this.selectedSport,
    required this.sports,
    required this.onGenderChanged,
    required this.onSportChanged,
    required this.onPickDob,
    required this.onSubmit,
    required this.saving,
  });

  final TextEditingController nameController;
  final TextEditingController phoneController;
  final TextEditingController dobController;
  final String? selectedGender;
  final DateTime? selectedDob;
  final String? selectedSport;
  final List<Sport> sports;
  final ValueChanged<String?> onGenderChanged;
  final ValueChanged<String?> onSportChanged;
  final VoidCallback onPickDob;
  final VoidCallback onSubmit;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
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
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            value: selectedGender,
            decoration: InputDecoration(
              labelText: 'Giới tính',
              labelStyle: const TextStyle(fontWeight: FontWeight.w600),
              prefixIcon: const Icon(Icons.wc),
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
            items: const [
              DropdownMenuItem(value: null, child: Text('Chưa chọn')),
              DropdownMenuItem(value: 'male', child: Text('Nam')),
              DropdownMenuItem(value: 'female', child: Text('Nữ')),
              DropdownMenuItem(value: 'other', child: Text('Khác')),
            ],
            onChanged: onGenderChanged,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: dobController,
            decoration: InputDecoration(
              labelText: 'Ngày sinh',
              labelStyle: const TextStyle(fontWeight: FontWeight.w600),
              prefixIcon: const Icon(Icons.cake_outlined),
              suffixIcon: IconButton(
                icon: const Icon(Icons.calendar_today),
                onPressed: onPickDob,
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
            readOnly: true,
            onTap: onPickDob,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            value: selectedSport,
            decoration: InputDecoration(
              labelText: 'Môn thể thao chính',
              labelStyle: const TextStyle(fontWeight: FontWeight.w600),
              prefixIcon: const Icon(Icons.sports_handball),
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
            items: [
              const DropdownMenuItem(value: null, child: Text('Chưa chọn')),
              ...sports.map(
                (sport) => DropdownMenuItem(
                  value: sport.id,
                  child: Text(sport.name),
                ),
              ),
            ],
            onChanged: onSportChanged,
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
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
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
      ),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Đổi mật khẩu',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
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
            buttonColor: Theme.of(context).colorScheme.primary,
            shadowColor: Colors.black.withValues(alpha:0.35),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.saving)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
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
      ),
    );
  }
}
