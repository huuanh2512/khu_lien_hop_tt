import 'package:flutter/material.dart';
import 'package:neubrutalism_ui/neubrutalism_ui.dart';

import 'package:khu_lien_hop_tt/models/facility.dart';
import 'package:khu_lien_hop_tt/models/maintenance.dart';
import 'package:khu_lien_hop_tt/models/price_profile.dart';
import 'package:khu_lien_hop_tt/models/sport.dart';
import 'package:khu_lien_hop_tt/models/staff_booking.dart';
import 'package:khu_lien_hop_tt/models/staff_customer.dart';
import 'package:khu_lien_hop_tt/models/staff_facility.dart';
import 'package:khu_lien_hop_tt/services/api_service.dart';
import 'package:khu_lien_hop_tt/services/auth_service.dart';
import 'package:khu_lien_hop_tt/staff/staff_bookings_page.dart';
import 'package:khu_lien_hop_tt/staff/staff_customers_page.dart';
import 'package:khu_lien_hop_tt/staff/staff_invoices_page.dart';
import 'package:khu_lien_hop_tt/staff/staff_profile_page.dart';
import 'package:khu_lien_hop_tt/staff/staff_notifications_page.dart';
import 'package:khu_lien_hop_tt/widgets/neu_button.dart';
import 'package:khu_lien_hop_tt/widgets/neu_text.dart';
import 'package:khu_lien_hop_tt/widgets/neo_loading.dart';
import 'package:khu_lien_hop_tt/widgets/sports_gradient_background.dart';
import 'package:khu_lien_hop_tt/widgets/success_dialog.dart';

const Duration _kQuickBookingDefaultDuration = Duration(minutes: 60);
const List<int> _kQuickBookingDurationOptions = [60, 90, 120];

class StaffHomePage extends StatefulWidget {
  const StaffHomePage({super.key});

  @override
  State<StaffHomePage> createState() => _StaffHomePageState();
}

class _StaffHomePageState extends State<StaffHomePage> {
  final ApiService _api = ApiService();
  StaffFacilityData? _data;
  List<Sport> _sports = [];
  String? _selectedSportId;
  bool _loading = true;
  String? _error;
  Map<String, StaffBooking> _activeBookings = const {};
  Map<String, List<StaffBooking>> _dailySchedules = const {};
  int _currentIndex = 0;
  int _unreadNotificationCount = 0;
  bool _creatingQuickBooking = false;

  static const List<String> _courtStatusOrder = [
    'active',
    'inactive',
    'maintenance',
    'closed',
  ];
  static const Duration _switchDuration = Duration(milliseconds: 250);
  static const Map<String, String> _maintenanceStatusLabels = {
    'scheduled': 'Đã lên lịch',
    'active': 'Đang diễn ra',
    'completed': 'Đã hoàn thành',
    'cancelled': 'Đã hủy',
  };
  static const Set<String> _bookingActiveStatuses = {'confirmed', 'pending'};
  static const Duration _activeBookingLookBack = Duration(hours: 2);
  static const Duration _activeBookingLookAhead = Duration(hours: 24);

  Widget _brutalistPanel({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(20),
    Color? color,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return NeuContainer(
      borderRadius: BorderRadius.circular(20),
      color: color ?? scheme.surface,
      borderColor: Colors.black,
      borderWidth: 3,
      shadowColor: Colors.black.withValues(alpha: 0.35),
      offset: const Offset(8, 8),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final now = DateTime.now();
      final facilityFuture = _api.staffGetFacility();
      final sportsFuture = _api.staffGetSports(includeInactive: true);
      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));
      final bookingsFuture = _api.staffGetBookings(
        from: startOfDay.subtract(_activeBookingLookBack).toUtc(),
        to: endOfDay.add(_activeBookingLookAhead).toUtc(),
        limit: 400,
      );
      final notificationsFuture = _api.staffGetNotifications(limit: 50);
      final data = await facilityFuture;
      final sports = await sportsFuture;
      final bookings = await bookingsFuture;
      final notifications = await notificationsFuture;
      if (!mounted) return;
      final sortedSports = [...sports]
        ..sort((a, b) => a.name.compareTo(b.name));
      final previousSelection = _selectedSportId;
      final activeBookings = _deriveActiveBookings(bookings, now);
      final schedules = _deriveDailySchedules(bookings, startOfDay, endOfDay);
      final unreadNotifications = notifications
          .where((notification) => !notification.read)
          .length;
      setState(() {
        _data = data;
        _sports = sortedSports;
        _selectedSportId =
            (previousSelection != null &&
                sortedSports.any((sport) => sport.id == previousSelection))
            ? previousSelection
            : null;
        _activeBookings = activeBookings;
        _dailySchedules = schedules;
        _unreadNotificationCount = unreadNotifications;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(e);
        _loading = false;
      });
    }
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.startsWith('Exception: ')) {
      return text.substring('Exception: '.length);
    }
    return text;
  }

  Future<void> _showSnack(String message, {bool isError = false}) async {
    if (!mounted) return;
    if (isError) {
      final theme = Theme.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: theme.colorScheme.error,
        ),
      );
      return;
    }

    await showSuccessDialog(
      context,
      message: message,
    );
  }

  void _setSportFilter(String? sportId) {
    if (_selectedSportId == sportId) return;
    setState(() {
      _selectedSportId = sportId;
    });
  }

  Map<String, StaffBooking> _deriveActiveBookings(
    List<StaffBooking> bookings,
    DateTime now,
  ) {
    final result = <String, StaffBooking>{};
    for (final booking in bookings) {
      final status = booking.status.toLowerCase();
      if (!_bookingActiveStatuses.contains(status)) continue;

      final start = booking.start.toLocal();
      final end = booking.end.toLocal();
      if (now.isBefore(start) || !now.isBefore(end)) continue;

      final courtId = booking.court?.id ?? booking.booking.courtId;
      if (courtId.isEmpty) continue;

      final existing = result[courtId];
      if (existing == null || existing.end.toLocal().isAfter(end)) {
        result[courtId] = booking;
      }
    }
    return result;
  }

  Map<String, List<StaffBooking>> _deriveDailySchedules(
    List<StaffBooking> bookings,
    DateTime startOfDay,
    DateTime endOfDay,
  ) {
    final map = <String, List<StaffBooking>>{};
    for (final booking in bookings) {
      final start = booking.start;
      if (start.isBefore(startOfDay) || start.isAfter(endOfDay)) {
        continue;
      }
      final courtId = booking.court?.id ?? booking.booking.courtId;
      if (courtId.isEmpty) continue;
      map.putIfAbsent(courtId, () => []).add(booking);
    }
    for (final entry in map.entries) {
      entry.value.sort((a, b) => a.start.compareTo(b.start));
    }
    return map;
  }

  Future<void> _handleCourtTap(StaffCourt court) async {
    final status = (court.status ?? 'active').toLowerCase();
    if (status != 'active') {
      await _showSnack('Sân đang tạm ngưng, không thể đặt nhanh.', isError: true);
      return;
    }
    if (_activeBookings.containsKey(court.id)) {
      await _showSnack('Sân đang có lượt đặt, hãy chọn sân khác.', isError: true);
      return;
    }
    await _showQuickBookingSheet(court);
  }

  DateTimeRange _nextQuickBookingSlot() {
    final now = DateTime.now();
    final alignedMinute = now.minute >= 30 ? 30 : 0;
    var start = DateTime(now.year, now.month, now.day, now.hour, alignedMinute);
    if (!start.isAfter(now)) {
      start = start.add(const Duration(minutes: 30));
    }
    final end = start.add(_kQuickBookingDefaultDuration);
    return DateTimeRange(start: start, end: end);
  }

  Future<void> _showQuickBookingSheet(StaffCourt court) async {
    final slot = _nextQuickBookingSlot();
    final result = await showModalBottomSheet<_QuickBookingResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (context) => _QuickBookingSheet(
        court: court,
        initialSlot: slot,
        fetchCustomers: () => _api.staffGetCustomers(limit: 100),
      ),
    );
    if (result == null || !mounted) return;
    final selectedSlot = result.slot;
    if (!selectedSlot.start.isAfter(DateTime.now())) {
      await _showSnack('Khung giờ này đã trôi qua, vui lòng thử lại.', isError: true);
      return;
    }
    await _createQuickBooking(
      court: court,
      slot: selectedSlot,
      existingCustomer: result.customer,
      customerName: result.customerName,
      customerPhone: result.customerPhone,
      customerEmail: result.customerEmail,
    );
  }

  Future<void> _createQuickBooking({
    required StaffCourt court,
    required DateTimeRange slot,
    StaffCustomer? existingCustomer,
    String? customerName,
    String? customerPhone,
    String? customerEmail,
  }) async {
    final normalizedName = customerName?.trim();
    final normalizedPhone = customerPhone?.trim();
    final normalizedEmail = customerEmail?.trim();
    if (_creatingQuickBooking) return;
    setState(() => _creatingQuickBooking = true);
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const Center(
        child: NeoLoadingCard(
          label: 'Đang xử lý...',
          width: 220,
          height: 180,
        ),
      ),
    );
    try {
      var booking = await _api.staffCreateBooking(
        customerId: existingCustomer?.id,
        customerName: existingCustomer == null ? normalizedName : null,
        customerPhone: existingCustomer == null ? normalizedPhone : null,
        customerEmail: existingCustomer == null ? normalizedEmail : null,
        sportId: court.court.sportId,
        courtId: court.id,
        start: slot.start,
        end: slot.end,
        confirmNow: false,
        note: 'Đặt nhanh từ trang chủ',
      );
      String? invoiceError;
      try {
        booking = await _api.staffUpdateBookingStatus(
          booking.id,
          status: 'confirmed',
          note: 'Xác nhận tự động từ đặt nhanh',
        );
      } catch (error) {
        invoiceError = _friendlyError(error);
      }
      if (navigator.mounted) {
        navigator.pop();
      }
      if (!mounted) return;
      await _load(showSpinner: false);
        final customerLabel = existingCustomer?.displayName ??
          (normalizedName?.isNotEmpty == true
            ? normalizedName!
            : (normalizedPhone?.isNotEmpty == true
              ? normalizedPhone!
                  : 'khách hàng'));
      if (invoiceError != null) {
        await _showSnack(
          'Đã đặt nhanh ${court.name} cho $customerLabel nhưng chưa thêm vào hoá đơn: $invoiceError',
          isError: true,
        );
      } else {
        await _showSnack(
          'Đã đặt nhanh ${court.name} cho $customerLabel và thêm vào hoá đơn',
        );
      }
    } catch (error) {
      if (navigator.mounted) {
        navigator.pop();
      }
      if (mounted) {
        await _showSnack(_friendlyError(error), isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _creatingQuickBooking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;
    final greeting = user?.name?.isNotEmpty == true
        ? user!.name!
        : (user?.email ?? 'Nhân viên');
    final notificationsCount = _unreadNotificationCount;

    return SportsGradientBackground(
      variant: SportsBackgroundVariant.staff,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: false,
        body: SafeArea(
          top: true,
          bottom: false,
          child: IndexedStack(
            index: _currentIndex,
            children: [
              _buildOverviewTab(greeting),
              StaffNotificationsPage(
                embedded: true,
                onUnreadCountChanged: (count) {
                  if (!mounted) return;
                  setState(() => _unreadNotificationCount = count);
                },
              ),
              const StaffBookingsPage(embedded: true),
              const StaffInvoicesPage(embedded: true),
              const StaffCustomersPage(embedded: true),
              const StaffProfilePage(embedded: true),
            ],
          ),
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFE8F5E9),
            border: const Border(
              top: BorderSide(color: Colors.black, width: 3),
            ),
            boxShadow: const [
              BoxShadow(
                color: Colors.black,
                offset: Offset(0, -4),
                blurRadius: 0,
              ),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: BottomNavigationBar(
                type: BottomNavigationBarType.fixed,
                backgroundColor: Colors.transparent,
                elevation: 0,
                currentIndex: _currentIndex,
                onTap: (index) {
                  if (_currentIndex == index) {
                    if (index == 0 && !_loading) {
                      _load(showSpinner: false);
                    }
                    return;
                  }
                  setState(() => _currentIndex = index);
                },
                selectedItemColor: Colors.black,
                unselectedItemColor: Colors.black54,
                selectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 10,
                ),
                selectedIconTheme: const IconThemeData(
                  size: 26,
                ),
                unselectedIconTheme: const IconThemeData(
                  size: 24,
                ),
                items: [
                  const BottomNavigationBarItem(
                    icon: Icon(Icons.dashboard_outlined),
                    activeIcon: Icon(Icons.dashboard),
                    label: 'Tổng quan',
                  ),
                  BottomNavigationBarItem(
                    icon: notificationsCount > 0
                        ? Badge.count(
                            count: notificationsCount,
                            child: const Icon(Icons.notifications_none_outlined),
                          )
                        : const Icon(Icons.notifications_none_outlined),
                    activeIcon: notificationsCount > 0
                        ? Badge.count(
                            count: notificationsCount,
                            child: const Icon(Icons.notifications),
                          )
                        : const Icon(Icons.notifications),
                    label: 'Thông báo',
                  ),
                  const BottomNavigationBarItem(
                    icon: Icon(Icons.event_note_outlined),
                    activeIcon: Icon(Icons.event_note),
                    label: 'Đặt sân',
                  ),
                  const BottomNavigationBarItem(
                    icon: Icon(Icons.receipt_long_outlined),
                    activeIcon: Icon(Icons.receipt_long),
                    label: 'Hoá đơn',
                  ),
                  const BottomNavigationBarItem(
                    icon: Icon(Icons.people_alt_outlined),
                    activeIcon: Icon(Icons.people_alt),
                    label: 'Khách hàng',
                  ),
                  const BottomNavigationBarItem(
                    icon: Icon(Icons.person_outline),
                    activeIcon: Icon(Icons.person),
                    label: 'Hồ sơ',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }



  Widget _buildOverviewTab(String greetingName) {
    if (_loading) {
      return const Center(
        child: NeoLoadingCard(
          label: 'Đang tải dữ liệu...',
          width: 260,
        ),
      );
    }
    if (_error != null) {
      return _buildErrorView(_error!);
    }
    if (_data == null) {
      return _buildEmptyView(greetingName);
    }
    return RefreshIndicator(
      onRefresh: () => _load(showSpinner: false),
      child: ListView(
        padding: const EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 24,
        ),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _buildFacilityCard(_data!.facility, greetingName),
          const SizedBox(height: 16),
          _buildCourtsSection(_data!.courts),
        ],
      ),
    );
  }

  Widget _buildErrorView(String message) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: _brutalistPanel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              NeuText(
                'Không thể tải dữ liệu',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              NeuButton(
                onPressed: _load,
                buttonHeight: 50,
                buttonColor: theme.colorScheme.primary,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.refresh, color: Colors.black),
                    SizedBox(width: 8),
                    Text(
                      'Thử lại',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
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

  Widget _buildEmptyView(String name) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: _brutalistPanel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              NeuText(
                'Xin chào, $name',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Chưa có dữ liệu cơ sở nào được phân công cho tài khoản của bạn.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              NeuButton(
                onPressed: _load,
                buttonHeight: 50,
                buttonColor: theme.colorScheme.secondary,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.refresh, color: Colors.black),
                    SizedBox(width: 8),
                    Text(
                      'Tải lại',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
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

  Widget _buildFacilityCard(Facility facility, String greetingName) {
    final theme = Theme.of(context);
    final addressText = _formatAddress(facility);
    final opening = facility.openingHours;
    final open = opening?['open']?.toString();
    final close = opening?['close']?.toString();

    return _brutalistPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NeuText(
            'Xin chào, $greetingName',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    NeuText(
                      facility.name,
                      style: theme.textTheme.titleLarge,
                    ),
                    if (facility.status != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Trạng thái: ${_courtStatusLabel(facility.status)}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(
                width: 150,
                child: NeuButton(
                  onPressed: () => _editFacility(facility),
                  buttonHeight: 46,
                  buttonWidth: double.infinity,
                  buttonColor: theme.colorScheme.secondary,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.edit_outlined, color: Colors.black),
                      SizedBox(width: 6),
                      Text(
                        'Chỉnh sửa',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (facility.description != null && facility.description!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(facility.description!),
            ),
          if (addressText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.location_on_outlined, size: 18),
                  const SizedBox(width: 6),
                  Expanded(child: Text(addressText)),
                ],
              ),
            ),
          if (open != null || close != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  const Icon(Icons.schedule, size: 18),
                  const SizedBox(width: 6),
                  Text('Giờ mở cửa: ${open ?? '...'} - ${close ?? '...'}'),
                ],
              ),
            ),
          if (facility.phone != null && facility.phone!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  const Icon(Icons.phone_outlined, size: 18),
                  const SizedBox(width: 6),
                  Text(facility.phone!),
                ],
              ),
            ),
          if (facility.email != null && facility.email!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  const Icon(Icons.mail_outline, size: 18),
                  const SizedBox(width: 6),
                  Text(facility.email!),
                ],
              ),
            ),
          if (facility.amenities.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: facility.amenities
                    .map(
                      (item) => Chip(
                        label: Text(item),
                        side: const BorderSide(color: Colors.black, width: 1.5),
                        backgroundColor: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.8),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCourtsSection(List<StaffCourt> courts) {
    final theme = Theme.of(context);
    final hasSports = _sports.isNotEmpty;
    final selectedKey = _selectedSportId ?? '__all__';
    final filteredCourts = _selectedSportId == null
        ? courts
        : courts
              .where((court) => court.court.sportId == _selectedSportId)
              .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _brutalistPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: NeuText(
                      'Danh sách sân',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  NeuButton(
                    onPressed: hasSports ? _showCreateCourtDialog : null,
                    buttonHeight: 46,
                    buttonWidth: 150,
                    buttonColor: theme.colorScheme.primary,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.add_circle_outline, color: Colors.black),
                        SizedBox(width: 6),
                        Text(
                          'Thêm sân',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (!hasSports)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Không có môn thể thao nào để gán cho sân. Hãy liên hệ quản trị viên.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              if (hasSports) _buildSportFilter(selectedKey),
              const SizedBox(height: 12),
              AnimatedSwitcher(
                duration: _switchDuration,
                transitionBuilder: (child, animation) {
                  final curved = CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOut,
                    reverseCurve: Curves.easeIn,
                  );
                  return FadeTransition(
                    opacity: curved,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.05, 0),
                        end: Offset.zero,
                      ).animate(curved),
                      child: child,
                    ),
                  );
                },
                child: filteredCourts.isEmpty
                    ? NeuContainer(
                        key: ValueKey('empty-$selectedKey'),
                        borderRadius: BorderRadius.circular(16),
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderColor: Colors.black,
                        borderWidth: 2,
                        shadowColor: Colors.black.withValues(alpha: 0.25),
                        offset: const Offset(4, 4),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                courts.isEmpty
                                    ? 'Chưa có sân nào được cấu hình cho cơ sở này.'
                                    : 'Không có sân nào thuộc môn thể thao đã chọn.',
                              ),
                              if (courts.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    'Hãy chọn môn khác hoặc thêm sân mới.',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      )
                    : Column(
                        key: ValueKey('list-$selectedKey'),
                        children: filteredCourts
                            .map(_buildCourtCard)
                            .toList(growable: false),
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildSportFilter(String selectedKey) {
    if (_sports.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final isAllSelected = _selectedSportId == null;
    final chips = <Widget>[
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: const Text('Tất cả'),
          selected: isAllSelected,
          onSelected: (_) => _setSportFilter(null),
          selectedColor: theme.colorScheme.primary,
          backgroundColor: theme.colorScheme.surface,
          side: const BorderSide(color: Colors.black, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          labelStyle: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: isAllSelected
                ? Colors.black
                : theme.colorScheme.onSurface,
          ),
        ),
      ),
    ];

    for (final sport in _sports) {
      final isSelected = _selectedSportId == sport.id;
      chips.add(
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(sport.name),
            selected: isSelected,
            onSelected: (_) => _setSportFilter(sport.id),
            selectedColor: theme.colorScheme.secondary,
            backgroundColor: theme.colorScheme.surface,
            side: const BorderSide(color: Colors.black, width: 1.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            labelStyle: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: isSelected
                  ? Colors.black
                  : theme.colorScheme.onSurface,
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      key: ValueKey('filter-$selectedKey'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: chips),
    );
  }

  Widget _buildCourtCard(StaffCourt court) {
    final theme = Theme.of(context);
    final courtStatus = court.status;
    final isDeleted = courtStatus == 'deleted';
    final sportName = _sportName(court.court.sportId);
    final activeBooking = _activeBookings[court.id];
    final isInUse = activeBooking != null;
    final dailySchedule = _dailySchedules[court.id] ?? const [];
    final statusChip = Chip(
      label: Text(_courtStatusLabel(courtStatus)),
      backgroundColor: _courtStatusColor(courtStatus).withValues(alpha: 0.15),
      labelStyle: TextStyle(
        color: _courtStatusColor(courtStatus),
        fontWeight: FontWeight.w700,
      ),
      side: const BorderSide(color: Colors.black, width: 1.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
    final statusChips = Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        statusChip,
        if (isInUse)
          Chip(
            label: const Text('Đang sử dụng'),
            backgroundColor: theme.colorScheme.secondaryContainer,
            labelStyle: TextStyle(
              color: theme.colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.w600,
            ),
            side: const BorderSide(color: Colors.black, width: 1.2),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
      ],
    );
    final activeCustomer = activeBooking?.customer;
    final occupant =
        activeCustomer?.name ?? activeCustomer?.phone ?? activeCustomer?.email;
    final activeRange = activeBooking != null
        ? _formatTimeRangeShort(activeBooking.start, activeBooking.end)
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => _handleCourtTap(court),
        child: _brutalistPanel(
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
                        NeuText(
                          court.name,
                          style: theme.textTheme.titleMedium,
                        ),
                        if (sportName != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text('Môn: $sportName'),
                          ),
                        if (court.court.code != null &&
                            court.court.code!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text('Mã sân: ${court.court.code}'),
                          ),
                      ],
                    ),
                  ),
                  statusChips,
                  const SizedBox(width: 4),
                  PopupMenuButton<String>(
                    tooltip: 'Tuỳ chọn sân',
                    onSelected: (value) {
                      switch (value) {
                        case 'edit':
                          _showEditCourtDialog(court);
                          break;
                        case 'delete':
                          _confirmDeleteCourt(court);
                          break;
                      }
                    },
                    itemBuilder: (context) {
                      final items = <PopupMenuEntry<String>>[
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('Chỉnh sửa sân'),
                        ),
                      ];
                      if (!isDeleted) {
                        items.add(
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Xóa sân'),
                          ),
                        );
                      }
                      return items;
                    },
                    icon: const Icon(Icons.more_vert),
                  ),
                ],
              ),
              if (court.amenities.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: court.amenities
                        .map(
                          (item) => Chip(
                            label: Text(item),
                            side: const BorderSide(color: Colors.black, width: 1.2),
                            backgroundColor: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.6),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
              const SizedBox(height: 16),
              if (isInUse)
                NeuContainer(
                  width: double.infinity,
                  borderRadius: BorderRadius.circular(16),
                  color: theme.colorScheme.secondaryContainer,
                  borderColor: Colors.black,
                  borderWidth: 2,
                  shadowColor: Colors.black.withValues(alpha: 0.25),
                  offset: const Offset(4, 4),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.schedule,
                              size: 18,
                              color: theme.colorScheme.onSecondaryContainer,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Sân đang có lịch đặt',
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: theme.colorScheme.onSecondaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        if (activeRange != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text('Khung giờ: $activeRange'),
                          ),
                        if (occupant != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('Khách: $occupant'),
                          ),
                      ],
                    ),
                  ),
                ),
              if (dailySchedule.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: _CourtDailySchedule(schedule: dailySchedule),
                ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Bảo trì', style: theme.textTheme.titleSmall),
                  NeuButton(
                    onPressed: () => _showCreateMaintenanceDialog(court),
                    buttonHeight: 44,
                    buttonWidth: 150,
                    buttonColor: theme.colorScheme.secondary,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.add_circle_outline, color: Colors.black),
                        SizedBox(width: 6),
                        Text(
                          'Thêm lịch',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (court.maintenance.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Chưa có lịch bảo trì nào.'),
                )
              else
                ...court.maintenance.map((m) => _buildMaintenanceTile(court, m)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMaintenanceTile(StaffCourt court, Maintenance maintenance) {
    final theme = Theme.of(context);
    final status = maintenance.status;
    final statusLabel = _maintenanceStatusLabels[status] ?? 'Chưa rõ';
    final statusColor = _maintenanceStatusColor(status);
    final subtitle = _formatMaintenanceRange(maintenance);
    final reason =
        (maintenance.reason != null && maintenance.reason!.trim().isNotEmpty)
        ? maintenance.reason!
        : 'Không có ghi chú';
    final finalized = status == 'completed' || status == 'cancelled';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: NeuContainer(
        borderRadius: BorderRadius.circular(16),
        color: theme.colorScheme.surfaceContainerHighest,
        borderColor: Colors.black,
        borderWidth: 2,
        shadowColor: Colors.black.withValues(alpha: 0.25),
        offset: const Offset(4, 4),
        child: Material(
          color: Colors.transparent,
          child: ListTile(
            onTap: finalized
                ? null
                : () => _showEditMaintenanceDialog(court, maintenance),
            leading: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.black, width: 1.2),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(color: statusColor, fontWeight: FontWeight.w700),
              ),
            ),
            title: Text(reason),
            subtitle: Text(subtitle),
            trailing: PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'edit':
                    _showEditMaintenanceDialog(court, maintenance);
                    break;
                  case 'end':
                    _performMaintenanceAction(maintenance, 'end');
                    break;
                  case 'cancel':
                    _performMaintenanceAction(maintenance, 'cancel');
                    break;
                }
              },
              itemBuilder: (context) {
                final items = <PopupMenuEntry<String>>[
                  const PopupMenuItem(value: 'edit', child: Text('Chỉnh sửa')),
                ];
                if (!finalized) {
                  items.addAll(const [
                    PopupMenuItem(value: 'end', child: Text('Đánh dấu hoàn thành')),
                    PopupMenuItem(value: 'cancel', child: Text('Hủy lịch này')),
                  ]);
                }
                return items;
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _performMaintenanceAction(
    Maintenance maintenance,
    String action,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        child: NeuContainer(
          borderRadius: BorderRadius.circular(24),
          borderColor: Colors.black,
          borderWidth: 3,
          offset: const Offset(6, 6),
          shadowColor: Colors.black,
          color: action == 'end' ? const Color(0xFFE8F5E9) : const Color(0xFFFFE5E5),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.black, width: 3),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black,
                            offset: Offset(3, 3),
                            blurRadius: 0,
                          ),
                        ],
                      ),
                      child: Icon(
                        action == 'end' ? Icons.check_circle : Icons.cancel,
                        size: 28,
                        color: action == 'end' ? Colors.green : Colors.red,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'XÁC NHẬN THAO TÁC',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  action == 'end'
                      ? 'Bạn muốn đánh dấu lịch bảo trì này là hoàn thành?'
                      : 'Bạn muốn hủy lịch bảo trì này?',
                  style: const TextStyle(fontSize: 15),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: NeuButton(
                        buttonColor: const Color(0xFFF5F5F5),
                        buttonHeight: 44,
                        borderRadius: BorderRadius.circular(12),
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Không', style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: NeuButton(
                        buttonColor: action == 'end' ? const Color(0xFF4CAF50) : const Color(0xFFFF6B6B),
                        buttonHeight: 44,
                        borderRadius: BorderRadius.circular(12),
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Đồng ý', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (confirm != true) return;

    try {
      await _api.staffMaintenanceAction(maintenance.id, action);
      if (!mounted) return;
      await _load(showSpinner: false);
      await _showSnack('Đã cập nhật lịch bảo trì');
    } catch (e) {
      _showSnack(_friendlyError(e), isError: true);
    }
  }

  Future<void> _showCreateCourtDialog() async {
    if (_sports.isEmpty) {
      _showSnack(
        'Không thể tạo sân vì chưa có môn thể thao nào được cấu hình.',
        isError: true,
      );
      return;
    }

    final defaultSportId = _defaultSportId();
    if (defaultSportId == null) {
      _showSnack(
        'Không thể xác định môn thể thao mặc định. Vui lòng thử lại sau.',
        isError: true,
      );
      return;
    }

    final nameController = TextEditingController();
    final codeController = TextEditingController();
    final priceController = TextEditingController();
    final taxController = TextEditingController();
    String selectedSport = defaultSportId;
    String status = 'active';
    String? error;
    bool priceActive = true;
    const priceCurrency = 'VND';

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> submit() async {
              final name = nameController.text.trim();
              final code = codeController.text.trim();
              if (name.isEmpty) {
                setModalState(() {
                  error = 'Tên sân không được để trống';
                });
                return;
              }
              if (selectedSport.isEmpty) {
                setModalState(() {
                  error = 'Vui lòng chọn môn thể thao';
                });
                return;
              }

              final baseRate = _parseNumber(priceController.text);
              if (baseRate == null || baseRate <= 0) {
                setModalState(() {
                  error = 'Giá cơ bản/giờ phải lớn hơn 0';
                });
                return;
              }
              final taxValue = _parseNumber(taxController.text) ?? 0;
              if (taxValue < 0 || taxValue > 100) {
                setModalState(() {
                  error = 'Thuế phải nằm trong khoảng 0-100%';
                });
                return;
              }
              error = null;
              Navigator.of(dialogContext).pop({
                'court': {
                  'name': name,
                  'sportId': selectedSport,
                  'status': status,
                  if (code.isNotEmpty) 'code': code,
                },
                'price': {
                  'sportId': selectedSport,
                  'currency': priceCurrency,
                  'baseRatePerHour': baseRate,
                  'taxPercent': taxValue,
                  'active': priceActive,
                },
              });
            }

            return Dialog(
              child: NeuContainer(
                borderRadius: BorderRadius.circular(24),
                borderColor: Colors.black,
                borderWidth: 3,
                offset: const Offset(6, 6),
                shadowColor: Colors.black,
                color: const Color(0xFFFFF8DC),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'THÊM SÂN MỚI',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 24),
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(color: Colors.black, width: 2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: TextField(
                                  controller: nameController,
                                  decoration: const InputDecoration(
                                    labelText: 'Tên sân',
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.all(16),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(color: Colors.black, width: 2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: TextField(
                                  controller: codeController,
                                  decoration: const InputDecoration(
                                    labelText: 'Mã sân (tuỳ chọn)',
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.all(16),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(color: Colors.black, width: 2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: DropdownButtonFormField<String>(
                                  initialValue: selectedSport,
                                  decoration: const InputDecoration(
                                    labelText: 'Môn thể thao',
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  ),
                                  items: _sports
                                      .map(
                                        (sport) => DropdownMenuItem(
                                          value: sport.id,
                                          child: Text(sport.name),
                                        ),
                                      )
                                      .toList(growable: false),
                                  onChanged: (value) {
                                    if (value == null) return;
                                    setModalState(() => selectedSport = value);
                                  },
                                ),
                              ),
                              const SizedBox(height: 16),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(color: Colors.black, width: 2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: DropdownButtonFormField<String>(
                                  initialValue: _courtStatusOrder.contains(status)
                                      ? status
                                      : 'active',
                                  decoration: const InputDecoration(
                                    labelText: 'Trạng thái',
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  ),
                                  items: _courtStatusOrder
                                      .map(
                                        (value) => DropdownMenuItem(
                                          value: value,
                                          child: Text(_courtStatusLabel(value)),
                                        ),
                                      )
                                      .toList(growable: false),
                                  onChanged: (value) {
                                    if (value == null) return;
                                    setModalState(() => status = value);
                                  },
                                ),
                              ),
                              const SizedBox(height: 20),
                              const Text(
                                'THÔNG TIN GIÁ',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(color: Colors.black, width: 2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: TextField(
                                  controller: priceController,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: 'Giá cơ bản/giờ ($priceCurrency)',
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.all(16),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(color: Colors.black, width: 2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: TextField(
                                  controller: taxController,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Thuế % (0-100, tuỳ chọn)',
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.all(16),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF5F5F5),
                                  border: Border.all(color: Colors.black, width: 2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: SwitchListTile.adaptive(
                                  value: priceActive,
                                  onChanged: (value) =>
                                      setModalState(() => priceActive = value),
                                  title: const Text('Bảng giá đang kích hoạt'),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                              if (error != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFE5E5),
                                      border: Border.all(color: Colors.red, width: 2),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      error!,
                                      style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: NeuButton(
                              buttonColor: const Color(0xFFF5F5F5),
                              buttonHeight: 44,
                              borderRadius: BorderRadius.circular(12),
                              onPressed: () => Navigator.of(dialogContext).pop(null),
                              child: const Text('Hủy', style: TextStyle(fontWeight: FontWeight.w600)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: NeuButton(
                              buttonColor: const Color(0xFF4CAF50),
                              buttonHeight: 44,
                              borderRadius: BorderRadius.circular(12),
                              onPressed: submit,
                              child: const Text('Tạo sân', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      nameController.dispose();
      codeController.dispose();
      priceController.dispose();
      taxController.dispose();
    });

    if (result != null) {
      final courtPayload = (result['court'] as Map<String, dynamic>?) ?? const {};
      final pricePayload = result['price'] as Map<String, dynamic>?;
      if (courtPayload.isEmpty) {
        _showSnack('Thiếu dữ liệu sân mới', isError: true);
        return;
      }
      try {
        final createdCourt = await _api.staffCreateCourt(
          name: courtPayload['name'] as String,
          sportId: courtPayload['sportId'] as String,
          code: courtPayload['code'] as String?,
          status: courtPayload['status'] as String? ?? 'active',
        );

        String? priceError;
        if (pricePayload != null) {
          final payload = Map<String, dynamic>.from(pricePayload)
            ..['facilityId'] = createdCourt.facilityId
            ..['sportId'] = courtPayload['sportId']
            ..['courtId'] = createdCourt.id;
          try {
            await _api.staffUpsertPriceProfile(payload);
          } catch (e) {
            priceError = _friendlyError(e);
          }
        }
        if (!mounted) return;
        await _load(showSpinner: false);
        if (priceError != null) {
          await _showSnack(
            'Đã tạo sân nhưng chưa lưu bảng giá: $priceError',
            isError: true,
          );
        } else if (pricePayload != null) {
          await _showSnack('Đã tạo sân mới và lưu bảng giá');
        } else {
          await _showSnack('Đã tạo sân mới');
        }
      } catch (e) {
        _showSnack(_friendlyError(e), isError: true);
      }
    }
  }

  Future<void> _showEditCourtDialog(StaffCourt court) async {
    if (_sports.isEmpty) {
      _showSnack(
        'Không thể chỉnh sửa vì thiếu danh sách môn thể thao.',
        isError: true,
      );
      return;
    }

    final defaultSportId = _defaultSportId();
    var selectedSport = _sports.any((sport) => sport.id == court.court.sportId)
        ? court.court.sportId
        : defaultSportId;
    if ((selectedSport?.isEmpty ?? true)) {
      _showSnack(
        'Không tìm thấy môn thể thao phù hợp để chỉnh sửa.',
        isError: true,
      );
      return;
    }

    final nameController = TextEditingController(text: court.name);
    final codeController = TextEditingController(text: court.court.code ?? '');
    final currentStatus = court.status;
    String status =
        (currentStatus != null && _courtStatusOrder.contains(currentStatus))
        ? currentStatus
        : 'active';
    String? error;

    PriceProfile? priceProfile;
    String? priceLoadError;
    try {
      final prices = await _api.staffGetPriceProfiles(
        facilityId: court.facilityId,
        courtId: court.id,
      );
      if (prices.isNotEmpty) {
        priceProfile = prices.firstWhere(
          (profile) => profile.courtId == court.id,
          orElse: () => prices.first,
        );
      }
    } catch (e) {
      priceLoadError = _friendlyError(e);
    }

    if (!mounted) return;

    final priceController = TextEditingController(
      text: priceProfile == null
          ? ''
          : _formatNumberInput(priceProfile.baseRatePerHour),
    );
    final taxController = TextEditingController(
      text: priceProfile == null || priceProfile.taxPercent <= 0
          ? ''
          : _formatNumberInput(priceProfile.taxPercent),
    );
    bool priceActive = priceProfile?.active ?? true;
    bool updatePrice = priceProfile != null;
    final priceCurrency = priceProfile?.currency ?? 'VND';

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> submit() async {
              final name = nameController.text.trim();
              final code = codeController.text.trim();
              if (name.isEmpty) {
                setModalState(() {
                  error = 'Tên sân không được để trống';
                });
                return;
              }
              final chosenSportId = selectedSport;
              if (chosenSportId == null || chosenSportId.isEmpty) {
                setModalState(() {
                  error = 'Vui lòng chọn môn thể thao';
                });
                return;
              }

              final updates = <String, dynamic>{};
              if (name != court.name) updates['name'] = name;
              if (code != (court.court.code ?? '')) updates['code'] = code;
              if (chosenSportId != court.court.sportId) {
                updates['sportId'] = chosenSportId;
              }
              final originalStatus = court.status ?? 'active';
              if (status != originalStatus) updates['status'] = status;

              Map<String, dynamic>? pricePayload;
              if (updatePrice) {
                final baseRate = _parseNumber(priceController.text);
                if (baseRate == null || baseRate <= 0) {
                  setModalState(() {
                    error = 'Giá cơ bản/giờ phải lớn hơn 0';
                  });
                  return;
                }
                final taxValue = _parseNumber(taxController.text) ?? 0;
                if (taxValue < 0 || taxValue > 100) {
                  setModalState(() {
                    error = 'Thuế phải nằm trong khoảng 0-100%';
                  });
                  return;
                }
                final prevRate = priceProfile?.baseRatePerHour;
                final prevTax = priceProfile?.taxPercent ?? 0;
                final prevActive = priceProfile?.active ?? true;
                final prevSport = priceProfile?.sportId ?? court.court.sportId;
                final bool priceChanged =
                    priceProfile == null ||
                    (baseRate - (prevRate ?? 0)).abs() > 0.0001 ||
                    (taxValue - prevTax).abs() > 0.0001 ||
                    priceActive != prevActive ||
                    (prevSport != chosenSportId);
                if (priceChanged) {
                  pricePayload = {
                    'facilityId': court.facilityId,
                    'sportId': chosenSportId,
                    'courtId': court.id,
                    'currency': priceCurrency,
                    'baseRatePerHour': baseRate,
                    'taxPercent': taxValue,
                    'active': priceActive,
                  };
                }
              }

              if (updates.isEmpty && pricePayload == null) {
                setModalState(() {
                  error = 'Không có thay đổi nào được gửi lên.';
                });
                return;
              }

              error = null;
              final payload = <String, dynamic>{};
              if (updates.isNotEmpty) payload['court'] = updates;
              if (pricePayload != null) payload['price'] = pricePayload;
              Navigator.of(dialogContext).pop(payload);
            }

            return Dialog(
              child: NeuContainer(
                borderRadius: BorderRadius.circular(24),
                borderColor: Colors.black,
                borderWidth: 3,
                offset: const Offset(6, 6),
                shadowColor: Colors.black,
                color: const Color(0xFFE6F3FF),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'CHỈNH SỬA ${court.name.toUpperCase()}',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(color: Colors.black, width: 2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: TextField(
                                  controller: nameController,
                                  decoration: const InputDecoration(
                                    labelText: 'Tên sân',
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.all(16),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(color: Colors.black, width: 2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: TextField(
                                  controller: codeController,
                                  decoration: const InputDecoration(
                                    labelText: 'Mã sân (tuỳ chọn)',
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.all(16),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(color: Colors.black, width: 2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: DropdownButtonFormField<String>(
                                  initialValue: selectedSport,
                                  decoration: const InputDecoration(
                                    labelText: 'Môn thể thao',
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  ),
                                  items: _sports
                                      .map(
                                        (sport) => DropdownMenuItem(
                                          value: sport.id,
                                          child: Text(sport.name),
                                        ),
                                      )
                                      .toList(growable: false),
                                  onChanged: (value) {
                                    if (value == null) return;
                                    setModalState(() => selectedSport = value);
                                  },
                                ),
                              ),
                              const SizedBox(height: 16),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(color: Colors.black, width: 2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: DropdownButtonFormField<String>(
                                  initialValue: _courtStatusOrder.contains(status)
                                      ? status
                                      : 'active',
                                  decoration: const InputDecoration(
                                    labelText: 'Trạng thái',
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  ),
                                  items: _courtStatusOrder
                                      .map(
                                        (value) => DropdownMenuItem(
                                          value: value,
                                          child: Text(_courtStatusLabel(value)),
                                        ),
                                      )
                                      .toList(growable: false),
                                  onChanged: (value) {
                                    if (value == null) return;
                                    setModalState(() => status = value);
                                  },
                                ),
                              ),
                              const SizedBox(height: 20),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF5F5F5),
                                  border: Border.all(color: Colors.black, width: 2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: SwitchListTile.adaptive(
                                  value: updatePrice,
                                  onChanged: (value) =>
                                      setModalState(() => updatePrice = value),
                                  title: const Text('Cập nhật bảng giá cho sân này', style: TextStyle(fontWeight: FontWeight.w600)),
                                  subtitle: priceLoadError != null
                                      ? Text(
                                          'Không tải được giá: $priceLoadError',
                                          style: const TextStyle(color: Colors.red),
                                        )
                                        : Text(
                                          priceProfile == null
                                            ? 'Chưa có bảng giá riêng cho sân này'
                                            : 'Giá hiện tại: ${_formatPricePreview(priceProfile)}',
                                        ),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                              if (updatePrice) ...[
                                const SizedBox(height: 16),
                                const Text(
                                  'THÔNG TIN GIÁ',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    border: Border.all(color: Colors.black, width: 2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: TextField(
                                    controller: priceController,
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      labelText: 'Giá cơ bản/giờ ($priceCurrency)',
                                      border: InputBorder.none,
                                      contentPadding: const EdgeInsets.all(16),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    border: Border.all(color: Colors.black, width: 2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: TextField(
                                    controller: taxController,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'Thuế % (0-100)',
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.all(16),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF5F5F5),
                                    border: Border.all(color: Colors.black, width: 2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: SwitchListTile.adaptive(
                                    value: priceActive,
                                    onChanged: (value) =>
                                        setModalState(() => priceActive = value),
                                    title: const Text('Bảng giá đang kích hoạt'),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              ],
                              if (error != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFE5E5),
                                      border: Border.all(color: Colors.red, width: 2),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      error!,
                                      style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: NeuButton(
                              buttonColor: const Color(0xFFF5F5F5),
                              buttonHeight: 44,
                              borderRadius: BorderRadius.circular(12),
                              onPressed: () => Navigator.of(dialogContext).pop(null),
                              child: const Text('Hủy', style: TextStyle(fontWeight: FontWeight.w600)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: NeuButton(
                              buttonColor: const Color(0xFF4CAF50),
                              buttonHeight: 44,
                              borderRadius: BorderRadius.circular(12),
                              onPressed: submit,
                              child: const Text('Lưu', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      nameController.dispose();
      codeController.dispose();
      priceController.dispose();
      taxController.dispose();
    });

    if (result != null && result.isNotEmpty) {
      try {
        Map<String, dynamic> courtUpdates = const {};
        Map<String, dynamic>? pricePayload;
        if (result.containsKey('court') || result.containsKey('price')) {
          final rawCourt = result['court'];
          if (rawCourt is Map<String, dynamic>) {
            courtUpdates = Map<String, dynamic>.from(rawCourt);
          }
          final rawPrice = result['price'];
          if (rawPrice is Map<String, dynamic>) {
            pricePayload = Map<String, dynamic>.from(rawPrice);
          }
        } else {
          courtUpdates = Map<String, dynamic>.from(result);
        }

        if (courtUpdates.isNotEmpty) {
          await _api.staffUpdateCourt(court.id, courtUpdates);
        }
        if (pricePayload != null) {
          await _api.staffUpsertPriceProfile(pricePayload);
        }
        if (!mounted) return;
        await _load(showSpinner: false);
        final sections = <String>[
          if (courtUpdates.isNotEmpty) 'thông tin sân',
          if (pricePayload != null) 'giá',
        ];
        final summary = sections.isEmpty
            ? 'thông tin'
            : sections.join(' và ');
        await _showSnack('Đã cập nhật $summary');
      } catch (e) {
        _showSnack(_friendlyError(e), isError: true);
      }
    }
  }

  Future<void> _confirmDeleteCourt(StaffCourt court) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        child: NeuContainer(
          borderRadius: BorderRadius.circular(24),
          borderColor: Colors.black,
          borderWidth: 3,
          offset: const Offset(6, 6),
          shadowColor: Colors.black,
          color: const Color(0xFFFFE5E5),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.black, width: 3),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black,
                            offset: Offset(3, 3),
                            blurRadius: 0,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.warning, size: 28, color: Colors.red),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'XÓA SÂN',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'Bạn có chắc chắn muốn xóa sân "${court.name}"? Việc này sẽ tạm ngưng đặt lịch cho sân.',
                  style: const TextStyle(fontSize: 15),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: NeuButton(
                        buttonColor: const Color(0xFFF5F5F5),
                        buttonHeight: 44,
                        borderRadius: BorderRadius.circular(12),
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Hủy', style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: NeuButton(
                        buttonColor: const Color(0xFFFF6B6B),
                        buttonHeight: 44,
                        borderRadius: BorderRadius.circular(12),
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Xóa', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirm != true) return;

    try {
      await _api.staffDeleteCourt(court.id);
      if (!mounted) return;
      await _load(showSpinner: false);
  await _showSnack('Đã xóa sân khỏi danh sách');
    } catch (e) {
      _showSnack(_friendlyError(e), isError: true);
    }
  }

  Future<void> _showCreateMaintenanceDialog(StaffCourt court) async {
    final reasonController = TextEditingController();
    DateTime? start = DateTime.now().add(const Duration(hours: 1));
    start = DateTime(start.year, start.month, start.day, start.hour, 0);
    DateTime? end = start.add(const Duration(hours: 2));
    bool saving = false;
    String? error;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: !saving,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> pickStart() async {
              final picked = await _pickDateTime(start ?? DateTime.now());
              if (picked != null) {
                setModalState(() {
                  start = picked;
                  if (end != null && !start!.isBefore(end!)) {
                    end = start!.add(const Duration(hours: 1));
                  }
                });
              }
            }

            Future<void> pickEnd() async {
              final initial =
                  end ??
                  (start ?? DateTime.now()).add(const Duration(hours: 1));
              final picked = await _pickDateTime(initial);
              if (picked != null) {
                setModalState(() {
                  end = picked;
                });
              }
            }

            Future<void> submit() async {
              if (saving) return;
              if (start == null || end == null) {
                setModalState(() {
                  error = 'Vui lòng chọn thời gian bắt đầu và kết thúc';
                });
                return;
              }
              if (!start!.isBefore(end!)) {
                setModalState(() {
                  error = 'Thời gian bắt đầu phải nhỏ hơn thời gian kết thúc';
                });
                return;
              }
              setModalState(() {
                saving = true;
                error = null;
              });
              try {
                await _api.staffCreateMaintenance(
                  courtId: court.id,
                  start: start!,
                  end: end!,
                  reason: reasonController.text.trim().isEmpty
                      ? null
                      : reasonController.text.trim(),
                );
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop(true);
                }
              } catch (e) {
                setModalState(() {
                  saving = false;
                  error = _friendlyError(e);
                });
              }
            }

            return Dialog(
              child: NeuContainer(
                borderRadius: BorderRadius.circular(24),
                borderColor: Colors.black,
                borderWidth: 3,
                offset: const Offset(6, 6),
                shadowColor: Colors.black,
                color: const Color(0xFFFFFAF0),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFE5CC),
                              border: Border.all(color: Colors.black, width: 3),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black,
                                  offset: Offset(3, 3),
                                  blurRadius: 0,
                                ),
                              ],
                            ),
                            child: const Icon(Icons.build, size: 28, color: Colors.orange),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'THÊM BẢO TRÌ\n${court.name}',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, height: 1.2),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(color: Colors.black, width: 2),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black,
                                      offset: Offset(3, 3),
                                      blurRadius: 0,
                                    ),
                                  ],
                                ),
                                child: Column(
                                  children: [
                                    InkWell(
                                      onTap: pickStart,
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFE8F5E9),
                                              border: Border.all(color: Colors.black, width: 2),
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: const Icon(Icons.calendar_today, size: 20),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                const Text('Thời gian bắt đầu', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                                const SizedBox(height: 4),
                                                Text(_formatDateTime(start), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                                              ],
                                            ),
                                          ),
                                          const Icon(Icons.edit_outlined),
                                        ],
                                      ),
                                    ),
                                    const Divider(height: 24, color: Colors.black),
                                    InkWell(
                                      onTap: pickEnd,
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFFFE5CC),
                                              border: Border.all(color: Colors.black, width: 2),
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: const Icon(Icons.calendar_today, size: 20),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                const Text('Thời gian kết thúc', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                                const SizedBox(height: 4),
                                                Text(_formatDateTime(end), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                                              ],
                                            ),
                                          ),
                                          const Icon(Icons.edit_outlined),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(color: Colors.black, width: 2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: TextField(
                                  controller: reasonController,
                                  decoration: const InputDecoration(
                                    labelText: 'Ghi chú (tuỳ chọn)',
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.all(16),
                                  ),
                                  minLines: 1,
                                  maxLines: 3,
                                ),
                              ),
                              if (error != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFE5E5),
                                      border: Border.all(color: Colors.red, width: 2),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      error!,
                                      style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: NeuButton(
                              buttonColor: const Color(0xFFF5F5F5),
                              buttonHeight: 44,
                              borderRadius: BorderRadius.circular(12),
                              onPressed: saving
                                  ? null
                                  : () => Navigator.of(dialogContext).pop(false),
                              child: const Text('Hủy', style: TextStyle(fontWeight: FontWeight.w600)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: NeuButton(
                              buttonColor: const Color(0xFF4CAF50),
                              buttonHeight: 44,
                              borderRadius: BorderRadius.circular(12),
                              onPressed: saving ? null : submit,
                              child: saving
                                  ? const NeoLoadingDot(
                                      size: 16,
                                      fillColor: Colors.white,
                                    )
                                  : const Text('Lưu', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reasonController.dispose();
    });

    if (result == true) {
      await _load(showSpinner: false);
      await _showSnack('Đã tạo lịch bảo trì mới');
    }
  }

  Future<void> _showEditMaintenanceDialog(
    StaffCourt court,
    Maintenance maintenance,
  ) async {
    final reasonController = TextEditingController(
      text: maintenance.reason ?? '',
    );
    DateTime? start = maintenance.start?.toLocal();
    DateTime? end = maintenance.end?.toLocal();
    String status = maintenance.status ?? 'scheduled';
    bool saving = false;
    String? error;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: !saving,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> pickStart() async {
              final initial = start ?? DateTime.now();
              final picked = await _pickDateTime(initial);
              if (picked != null) {
                setModalState(() {
                  start = picked;
                  if (end != null && !start!.isBefore(end!)) {
                    end = start!.add(const Duration(hours: 1));
                  }
                });
              }
            }

            Future<void> pickEnd() async {
              final initial =
                  end ??
                  (start ?? DateTime.now()).add(const Duration(hours: 1));
              final picked = await _pickDateTime(initial);
              if (picked != null) {
                setModalState(() {
                  end = picked;
                });
              }
            }

            Future<void> submit() async {
              if (saving) return;
              if (start != null && end != null && !start!.isBefore(end!)) {
                setModalState(() {
                  error = 'Thời gian bắt đầu phải nhỏ hơn thời gian kết thúc';
                });
                return;
              }
              setModalState(() {
                saving = true;
                error = null;
              });
              try {
                await _api.staffUpdateMaintenance(
                  maintenance.id,
                  start: start,
                  end: end,
                  reason: reasonController.text,
                  status: status,
                );
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop(true);
                }
              } catch (e) {
                setModalState(() {
                  saving = false;
                  error = _friendlyError(e);
                });
              }
            }

            return Dialog(
              child: NeuContainer(
                borderRadius: BorderRadius.circular(24),
                borderColor: Colors.black,
                borderWidth: 3,
                offset: const Offset(6, 6),
                shadowColor: Colors.black,
                color: const Color(0xFFE6F3FF),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F5E9),
                              border: Border.all(color: Colors.black, width: 3),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black,
                                  offset: Offset(3, 3),
                                  blurRadius: 0,
                                ),
                              ],
                            ),
                            child: const Icon(Icons.edit, size: 28, color: Colors.blue),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'CHỈNH SỬA BẢO TRÌ\n${court.name}',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, height: 1.2),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(color: Colors.black, width: 2),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black,
                                      offset: Offset(3, 3),
                                      blurRadius: 0,
                                    ),
                                  ],
                                ),
                                child: Column(
                                  children: [
                                    InkWell(
                                      onTap: pickStart,
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFE8F5E9),
                                              border: Border.all(color: Colors.black, width: 2),
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: const Icon(Icons.calendar_today, size: 20),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                const Text('Thời gian bắt đầu', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                                const SizedBox(height: 4),
                                                Text(_formatDateTime(start), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                                              ],
                                            ),
                                          ),
                                          const Icon(Icons.edit_outlined),
                                        ],
                                      ),
                                    ),
                                    const Divider(height: 24, color: Colors.black),
                                    InkWell(
                                      onTap: pickEnd,
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFFFE5CC),
                                              border: Border.all(color: Colors.black, width: 2),
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: const Icon(Icons.calendar_today, size: 20),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                const Text('Thời gian kết thúc', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                                const SizedBox(height: 4),
                                                Text(_formatDateTime(end), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                                              ],
                                            ),
                                          ),
                                          const Icon(Icons.edit_outlined),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(color: Colors.black, width: 2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: DropdownButtonFormField<String>(
                                  initialValue: _maintenanceStatusLabels.containsKey(status)
                                      ? status
                                      : 'scheduled',
                                  decoration: const InputDecoration(
                                    labelText: 'Trạng thái',
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  ),
                                  items: _maintenanceStatusLabels.entries
                                      .map(
                                        (entry) => DropdownMenuItem(
                                          value: entry.key,
                                          child: Text(entry.value),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: saving
                                      ? null
                                      : (value) =>
                                            setModalState(() => status = value ?? status),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(color: Colors.black, width: 2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: TextField(
                                  controller: reasonController,
                                  decoration: const InputDecoration(
                                    labelText: 'Ghi chú',
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.all(16),
                                  ),
                                  minLines: 1,
                                  maxLines: 4,
                                ),
                              ),
                              if (error != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFE5E5),
                                      border: Border.all(color: Colors.red, width: 2),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      error!,
                                      style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: NeuButton(
                              buttonColor: const Color(0xFFF5F5F5),
                              buttonHeight: 44,
                              borderRadius: BorderRadius.circular(12),
                              onPressed: saving
                                  ? null
                                  : () => Navigator.of(dialogContext).pop(false),
                              child: const Text('Hủy', style: TextStyle(fontWeight: FontWeight.w600)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: NeuButton(
                              buttonColor: const Color(0xFF4CAF50),
                              buttonHeight: 44,
                              borderRadius: BorderRadius.circular(12),
                              onPressed: saving ? null : submit,
                              child: saving
                                  ? const NeoLoadingDot(
                                      size: 16,
                                      fillColor: Colors.white,
                                    )
                                  : const Text('Lưu', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reasonController.dispose();
    });

    if (result == true) {
      await _load(showSpinner: false);
      await _showSnack('Đã cập nhật lịch bảo trì');
    }
  }

  Future<void> _editFacility(Facility facility) async {
    final opening = facility.openingHours ?? const {};
    final openController = TextEditingController(
      text: opening['open']?.toString() ?? '',
    );
    final closeController = TextEditingController(
      text: opening['close']?.toString() ?? '',
    );
    final amenitiesController = TextEditingController(
      text: facility.amenities.join(', '),
    );
    final descriptionController = TextEditingController(
      text: facility.description ?? '',
    );
    bool saving = false;
    String? error;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: !saving,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> submit() async {
              if (saving) return;
              final open = openController.text.trim();
              final close = closeController.text.trim();
              final amenities = amenitiesController.text
                  .split(',')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList();
              final description = descriptionController.text.trim();

              final updates = <String, dynamic>{
                'openingHours': (open.isNotEmpty || close.isNotEmpty)
                    ? {
                        if (open.isNotEmpty) 'open': open,
                        if (close.isNotEmpty) 'close': close,
                      }
                    : null,
                'amenities': amenities,
                'description': description.isEmpty ? null : description,
              };

              if (updates.values.every(
                (value) => value == null || (value is List && value.isEmpty),
              )) {
                setModalState(() {
                  error = 'Vui lòng nhập thông tin cần cập nhật.';
                });
                return;
              }

              setModalState(() {
                saving = true;
                error = null;
              });

              try {
                await _api.staffUpdateFacility(updates);
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop(true);
                }
              } catch (e) {
                setModalState(() {
                  saving = false;
                  error = _friendlyError(e);
                });
              }
            }

            return AlertDialog(
              title: Text('Chỉnh sửa ${facility.name}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: openController,
                            decoration: const InputDecoration(
                              labelText: 'Giờ mở cửa (ví dụ 06:00)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: closeController,
                            decoration: const InputDecoration(
                              labelText: 'Giờ đóng cửa (ví dụ 22:00)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: amenitiesController,
                      decoration: const InputDecoration(
                        labelText: 'Tiện ích (phân tách bằng dấu phẩy)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Mô tả khu liên hợp',
                        border: OutlineInputBorder(),
                      ),
                      minLines: 2,
                      maxLines: 4,
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Hủy'),
                ),
                FilledButton(
                  onPressed: saving ? null : submit,
                  child: saving
                      ? const NeoLoadingDot(size: 16, fillColor: Colors.white)
                      : const Text('Lưu thay đổi'),
                ),
              ],
            );
          },
        );
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      openController.dispose();
      closeController.dispose();
      amenitiesController.dispose();
      descriptionController.dispose();
    });

    if (result == true) {
      await _load(showSpinner: false);
      await _showSnack('Đã cập nhật thông tin khu');
    }
  }

  Sport? _findSport(String? sportId) {
    if (sportId == null) return null;
    try {
      return _sports.firstWhere((sport) => sport.id == sportId);
    } catch (_) {
      return null;
    }
  }

  String? _sportName(String? sportId) => _findSport(sportId)?.name;

  String? _defaultSportId() {
    if (_sports.isEmpty) return null;
    for (final sport in _sports) {
      if (sport.active != false) return sport.id;
    }
    return _sports.first.id;
  }

  String _formatTime(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    final local = value.toLocal();
    return '${two(local.hour)}:${two(local.minute)}';
  }

  String _formatTimeRangeShort(DateTime start, DateTime end) {
    return '${_formatTime(start)} → ${_formatTime(end)}';
  }

  String _formatAddress(Facility facility) {
    final parts = [
      facility.address.line1,
      facility.address.ward,
      facility.address.district,
      facility.address.city,
      facility.address.province,
      facility.address.country,
    ];
    return parts
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .join(', ');
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) return 'Chưa thiết lập';
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
  }

  String _formatMaintenanceRange(Maintenance maintenance) {
    final start = _formatDateTime(maintenance.start);
    final end = _formatDateTime(maintenance.end);
    return '$start → $end';
  }

  String _formatNumberInput(double value) {
    final normalized = double.parse(value.toStringAsFixed(6));
    if ((normalized - normalized.roundToDouble()).abs() < 0.0001) {
      return normalized.toStringAsFixed(0);
    }
    final scaled = normalized * 10;
    if ((scaled - scaled.roundToDouble()).abs() < 0.0001) {
      return normalized.toStringAsFixed(1);
    }
    return normalized.toStringAsFixed(2);
  }

  double? _parseNumber(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    var normalized = trimmed.replaceAll(' ', '');
    if (normalized.contains(',') && !normalized.contains('.')) {
      normalized = normalized.replaceAll(',', '.');
    } else {
      normalized = normalized.replaceAll(',', '');
    }
    return double.tryParse(normalized);
  }

  String _formatPricePreview(PriceProfile profile) {
    final base = _formatNumberInput(profile.baseRatePerHour);
    final buffer = StringBuffer('$base ${profile.currency}');
    if (profile.taxPercent > 0) {
      buffer.write(' · Thuế ${_formatNumberInput(profile.taxPercent)}%');
    }
    buffer.write(' · ${profile.active ? 'Đang dùng' : 'Đang tắt'}');
    return buffer.toString();
  }

  String _courtStatusLabel(String? status) {
    switch (status) {
      case 'active':
        return 'Đang mở';
      case 'maintenance':
        return 'Đang bảo trì';
      case 'inactive':
        return 'Tạm ngưng';
      case 'closed':
        return 'Ngưng hoạt động';
      case 'deleted':
        return 'Đã xoá';
      default:
        return 'Chưa rõ';
    }
  }

  Color _courtStatusColor(String? status) {
    final scheme = Theme.of(context).colorScheme;
    switch (status) {
      case 'active':
        return scheme.primary;
      case 'maintenance':
        return scheme.tertiary;
      case 'inactive':
        return scheme.outline;
      case 'closed':
        return scheme.outlineVariant;
      case 'deleted':
        return scheme.error;
      default:
        return scheme.outlineVariant;
    }
  }

  Color _maintenanceStatusColor(String? status) {
    final scheme = Theme.of(context).colorScheme;
    switch (status) {
      case 'scheduled':
        return scheme.primary;
      case 'active':
        return scheme.tertiary;
      case 'completed':
        return scheme.secondary;
      case 'cancelled':
        return scheme.error;
      default:
        return scheme.outline;
    }
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null) return null;
    if (!mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }
}

class _CourtDailySchedule extends StatelessWidget {
  const _CourtDailySchedule({required this.schedule});

  final List<StaffBooking> schedule;

  @override
  Widget build(BuildContext context) {
    if (schedule.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NeuText(
          'Lịch trong ngày',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 6),
        ...schedule.map((booking) => _CourtScheduleTile(booking: booking)),
      ],
    );
  }
}

class _CourtScheduleTile extends StatelessWidget {
  const _CourtScheduleTile({required this.booking});

  final StaffBooking booking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fallbackId = booking.booking.customerId;
    final fallbackSuffix = fallbackId.length > 6
        ? fallbackId.substring(fallbackId.length - 6)
        : fallbackId;
    final customerName =
        booking.customer?.name ??
        booking.customer?.phone ??
        booking.customer?.email ??
        (fallbackSuffix.isNotEmpty ? 'Khách #$fallbackSuffix' : 'Khách');
    final range = _formatRange(booking.start, booking.end);
    final statusLabel = _statusLabels[booking.status] ?? booking.status;
    final statusColor = _statusColor(booking.status, theme.colorScheme);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: NeuContainer(
        borderRadius: BorderRadius.circular(14),
        color: theme.colorScheme.surfaceContainerHighest,
        borderColor: Colors.black,
        borderWidth: 2,
        shadowColor: Colors.black.withValues(alpha: 0.2),
        offset: const Offset(3, 3),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      range,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(customerName, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black, width: 1.2),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatRange(DateTime start, DateTime end) {
    String two(int value) => value.toString().padLeft(2, '0');
    final localStart = start.toLocal();
    final localEnd = end.toLocal();
    final datePart =
        '${two(localStart.day)}/${two(localStart.month)}/${localStart.year}';
    final startPart = '${two(localStart.hour)}:${two(localStart.minute)}';
    final endPart = '${two(localEnd.hour)}:${two(localEnd.minute)}';
    return '$datePart $startPart → $endPart';
  }

  static const Map<String, String> _statusLabels = {
    'pending': 'Chờ xác nhận',
    'confirmed': 'Đã xác nhận',
    'completed': 'Hoàn tất',
    'cancelled': 'Đã hủy',
  };

  static Color _statusColor(String status, ColorScheme scheme) {
    switch (status) {
      case 'confirmed':
        return Colors.green.shade700;
      case 'completed':
        return scheme.primary;
      case 'cancelled':
        return scheme.error;
      case 'pending':
      default:
        return scheme.secondary;
    }
  }
}

class _QuickBookingSheet extends StatefulWidget {
  const _QuickBookingSheet({
    required this.court,
    required this.initialSlot,
    required this.fetchCustomers,
  });

  final StaffCourt court;
  final DateTimeRange initialSlot;
  final Future<List<StaffCustomer>> Function() fetchCustomers;

  @override
  State<_QuickBookingSheet> createState() => _QuickBookingSheetState();
}

enum _QuickBookingMode { existing, newCustomer }

class _QuickBookingSheetState extends State<_QuickBookingSheet> {
  List<StaffCustomer> _customers = const [];
  bool _loading = true;
  String? _error;
  String _query = '';
  _QuickBookingMode _mode = _QuickBookingMode.existing;
  StaffCustomer? _selectedCustomer;
  late DateTime _start;
  late int _durationMinutes;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  String? _formError;

  @override
  void initState() {
    super.initState();
    _start = widget.initialSlot.start;
    final defaultDuration = widget.initialSlot.duration.inMinutes;
    _durationMinutes =
      defaultDuration > 0 ? defaultDuration : _kQuickBookingDefaultDuration.inMinutes;
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.fetchCustomers();
      if (!mounted) return;
      setState(() => _customers = items);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  List<StaffCustomer> get _filteredCustomers {
    final keyword = _query.trim().toLowerCase();
    if (keyword.isEmpty) return _customers;
    return _customers.where((customer) {
      final name = (customer.name ?? '').toLowerCase();
      final phone = (customer.phone ?? '').toLowerCase();
      final email = (customer.email ?? '').toLowerCase();
      return name.contains(keyword) || phone.contains(keyword) || email.contains(keyword);
    }).toList(growable: false);
  }

  DateTimeRange get _currentSlot =>
      DateTimeRange(start: _start, end: _start.add(Duration(minutes: _durationMinutes)));

  bool get _canSubmit {
    if (_mode == _QuickBookingMode.existing) {
      return _selectedCustomer != null;
    }
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();
    return name.isNotEmpty || phone.isNotEmpty || email.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final height = MediaQuery.of(context).size.height * 0.9;
    return SafeArea(
      child: Container(
        height: height,
        decoration: const BoxDecoration(
          color: Color(0xFFFFF8DC),
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          border: Border(
            top: BorderSide(color: Colors.black, width: 3),
            left: BorderSide(color: Colors.black, width: 3),
            right: BorderSide(color: Colors.black, width: 3),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black,
              offset: Offset(0, -6),
              blurRadius: 0,
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                child: Container(
                  width: 50,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE6F3FF),
                      border: Border.all(color: Colors.black, width: 3),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black,
                          offset: Offset(3, 3),
                          blurRadius: 0,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.flash_on, size: 24, color: Colors.blue),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'ĐẶT NHANH · ${widget.court.name.toUpperCase()}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildSlotCard(theme),
              const SizedBox(height: 16),
              _buildModeToggle(theme),
              const SizedBox(height: 16),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _mode == _QuickBookingMode.existing
                      ? _buildExistingCustomers(theme)
                      : _buildNewCustomerForm(theme),
                ),
              ),
              if (_formError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFE5E5),
                      border: Border.all(color: Colors.red, width: 2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _formError!,
                      style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: NeuButton(
                  buttonColor: _canSubmit ? const Color(0xFF4CAF50) : const Color(0xFFF5F5F5),
                  buttonHeight: 48,
                  borderRadius: BorderRadius.circular(14),
                  onPressed: _canSubmit ? _submit : null,
                  child: Text(
                    'ĐẶT SÂN & THÊM VÀO HOÁ ĐƠN',
                    style: TextStyle(
                      color: _canSubmit ? Colors.white : Colors.grey,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSlotCard(ThemeData theme) {
    final slot = _currentSlot;
    return NeuContainer(
      borderRadius: BorderRadius.circular(16),
      borderColor: Colors.black,
      borderWidth: 3,
      offset: const Offset(4, 4),
      shadowColor: Colors.black,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    border: Border.all(color: Colors.black, width: 2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.schedule, size: 20),
                ),
                const SizedBox(width: 10),
                const Text('KHUNG GIỜ', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _pickStart,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  border: Border.all(color: Colors.black, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Thời gian bắt đầu', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text(_formatDateTime(slot.start), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                    const Icon(Icons.edit_outlined),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Thời lượng:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _kQuickBookingDurationOptions.map((minutes) {
                final selected = _durationMinutes == minutes;
                return InkWell(
                  onTap: () => setState(() => _durationMinutes = minutes),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected ? const Color(0xFF4CAF50) : Colors.white,
                      border: Border.all(color: Colors.black, width: 2),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: selected ? const [
                        BoxShadow(
                          color: Colors.black,
                          offset: Offset(2, 2),
                          blurRadius: 0,
                        ),
                      ] : null,
                    ),
                    child: Text(
                      '$minutes phút',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                );
              }).toList(growable: false),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFE5CC),
                border: Border.all(color: Colors.black, width: 2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('Kết thúc: ${_formatTime(slot.end)}', style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeToggle(ThemeData theme) {
    return Row(
      children: _QuickBookingMode.values.map((mode) {
        final selected = _mode == mode;
        final label = mode == _QuickBookingMode.existing ? 'KHÁCH HIỆN CÓ' : 'KHÁCH MỚI';
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: mode == _QuickBookingMode.existing ? 8 : 0),
            child: NeuButton(
              buttonColor: selected ? const Color(0xFF4CAF50) : Colors.white,
              buttonHeight: 44,
              borderRadius: BorderRadius.circular(12),
              onPressed: () {
                setState(() {
                  _mode = mode;
                  _formError = null;
                });
              },
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: selected ? Colors.white : Colors.black,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildExistingCustomers(ThemeData theme) {
    if (_loading) {
      return const Center(
        child: NeoLoadingCard(
          label: 'Đang tải khách hàng...',
          width: 240,
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFE5E5),
                border: Border.all(color: Colors.red, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 12),
                  const Text('Không thể tải danh sách khách hàng', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            NeuButton(
              buttonColor: const Color(0xFF4CAF50),
              buttonHeight: 44,
              borderRadius: BorderRadius.circular(12),
              onPressed: _load,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text('Thử lại', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final customers = _filteredCustomers;
    if (customers.isEmpty && _query.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                border: Border.all(color: Colors.black, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                children: [
                  Icon(Icons.people_outline, size: 48),
                  SizedBox(height: 12),
                  Text('Chưa có khách hàng nào', style: TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.black, width: 2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Tìm khách theo tên, SĐT hoặc email',
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(16),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        const SizedBox(height: 16),
        if (customers.isEmpty && _query.isNotEmpty)
          Expanded(
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  border: Border.all(color: Colors.black, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('Không tìm thấy khách hàng phù hợp', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              itemBuilder: (context, index) {
                final customer = customers[index];
                final subtitle = _subtitleFor(customer);
                final selected = _selectedCustomer?.id == customer.id;
                return InkWell(
                  onTap: () {
                    setState(() {
                      _selectedCustomer = customer;
                      _formError = null;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: selected ? const Color(0xFFE8F5E9) : Colors.white,
                      border: Border.all(color: Colors.black, width: selected ? 3 : 2),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: selected ? const [
                        BoxShadow(
                          color: Colors.black,
                          offset: Offset(3, 3),
                          blurRadius: 0,
                        ),
                      ] : null,
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: selected ? const Color(0xFF4CAF50) : Colors.white,
                            border: Border.all(color: Colors.black, width: 2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            selected ? Icons.check : Icons.person,
                            size: 18,
                            color: selected ? Colors.white : Colors.black,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                customer.displayName,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                              ),
                              if (subtitle != null) ...[
                                const SizedBox(height: 4),
                                Text(subtitle, style: const TextStyle(fontSize: 12)),
                              ],
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE6F3FF),
                            border: Border.all(color: Colors.black, width: 1.5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${customer.totalBookings} lượt',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemCount: customers.length,
            ),
          ),
      ],
    );
  }

  Widget _buildNewCustomerForm(ThemeData theme) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.black, width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Tên khách hàng',
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(16),
              ),
              onChanged: (_) => setState(() => _formError = null),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.black, width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Số điện thoại',
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(16),
              ),
              onChanged: (_) => setState(() => _formError = null),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.black, width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email (tuỳ chọn)',
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(16),
              ),
              onChanged: (_) => setState(() => _formError = null),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFE6F3FF),
              border: Border.all(color: Colors.black, width: 2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Có thể để trống email nhưng cần ít nhất tên hoặc số điện thoại.',
                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickStart() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_start),
    );
    if (time == null) return;
    setState(() {
      _start = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  String _formatDateTime(DateTime value) {
    String two(int v) => v.toString().padLeft(2, '0');
    final local = value.toLocal();
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
  }

  String _formatTime(DateTime value) {
    String two(int v) => v.toString().padLeft(2, '0');
    final local = value.toLocal();
    return '${two(local.hour)}:${two(local.minute)}';
  }

  String? _subtitleFor(StaffCustomer customer) {
    final phone = customer.phone?.trim();
    final email = customer.email?.trim();
    if (phone != null && phone.isNotEmpty && email != null && email.isNotEmpty) {
      return '$phone · $email';
    }
    if (phone != null && phone.isNotEmpty) {
      return phone;
    }
    if (email != null && email.isNotEmpty) {
      return email;
    }
    return null;
  }

  void _submit() {
    final now = DateTime.now();
    if (!_currentSlot.start.isAfter(now)) {
      setState(() => _formError = 'Khung giờ phải nằm trong tương lai.');
      return;
    }
    if (_mode == _QuickBookingMode.existing && _selectedCustomer == null) {
      setState(() => _formError = 'Vui lòng chọn khách hàng.');
      return;
    }
    if (_mode == _QuickBookingMode.newCustomer) {
      final name = _nameController.text.trim();
      final phone = _phoneController.text.trim();
      final email = _emailController.text.trim();
      if (name.isEmpty && phone.isEmpty && email.isEmpty) {
        setState(() => _formError = 'Cần ít nhất tên hoặc số điện thoại.');
        return;
      }
    }
    setState(() => _formError = null);
    Navigator.of(context).pop(
      _QuickBookingResult(
        customer: _mode == _QuickBookingMode.existing ? _selectedCustomer : null,
        slot: _currentSlot,
        customerName:
            _mode == _QuickBookingMode.newCustomer ? _nameController.text.trim() : null,
        customerPhone:
            _mode == _QuickBookingMode.newCustomer ? _phoneController.text.trim() : null,
        customerEmail:
            _mode == _QuickBookingMode.newCustomer ? _emailController.text.trim() : null,
      ),
    );
  }
}

class _QuickBookingResult {
  const _QuickBookingResult({
    required this.slot,
    this.customer,
    this.customerName,
    this.customerPhone,
    this.customerEmail,
  });

  final DateTimeRange slot;
  final StaffCustomer? customer;
  final String? customerName;
  final String? customerPhone;
  final String? customerEmail;
}
