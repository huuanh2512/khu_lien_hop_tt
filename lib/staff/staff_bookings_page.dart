import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:khu_lien_hop_tt/models/staff_booking.dart';
import 'package:khu_lien_hop_tt/models/staff_facility.dart';
import 'package:khu_lien_hop_tt/models/sport.dart';
import 'package:khu_lien_hop_tt/screens/auth/login_page.dart';
import 'package:khu_lien_hop_tt/screens/verify_email_screen.dart';
import 'package:khu_lien_hop_tt/services/api_service.dart';
import 'package:khu_lien_hop_tt/utils/api_error_utils.dart';
import 'package:khu_lien_hop_tt/widgets/error_state_widget.dart';
import 'package:khu_lien_hop_tt/widgets/neu_button.dart';
import 'package:khu_lien_hop_tt/widgets/neu_text.dart';
import 'package:khu_lien_hop_tt/widgets/neo_loading.dart';
import 'package:khu_lien_hop_tt/widgets/sports_gradient_background.dart';
import 'package:khu_lien_hop_tt/widgets/success_dialog.dart';

enum _BookingStatusFilter {
  all,
  pending,
  confirmed,
  completed,
  cancelled,
  noShow,
}

const Map<_BookingStatusFilter, String> _statusFilterLabels = {
  _BookingStatusFilter.all: 'Tất cả',
  _BookingStatusFilter.pending: 'Chờ duyệt',
  _BookingStatusFilter.confirmed: 'Đã duyệt',
  _BookingStatusFilter.completed: 'Hoàn thành',
  _BookingStatusFilter.cancelled: 'Đã huỷ',
  _BookingStatusFilter.noShow: 'Vắng mặt',
};

const Map<String, String> _statusDisplayLabels = {
  'pending': 'Chờ duyệt',
  'confirmed': 'Đã duyệt',
  'completed': 'Hoàn thành',
  'cancelled': 'Đã huỷ',
  'no_show': 'Vắng mặt',
};

const Map<String, Color> _statusColors = {
  'pending': Color(0xFFFFC857),
  'confirmed': Color(0xFF3DD598),
  'completed': Color(0xFF23C552),
  'cancelled': Color(0xFFFF6B6B),
  'no_show': Color(0xFF7C5CFF),
};

class StaffBookingsPage extends StatefulWidget {
  const StaffBookingsPage({
    super.key,
    this.embedded = false,
    this.initialStatus,
    this.focusBookingId,
  });

  final bool embedded;
  final String? initialStatus;
  final String? focusBookingId;

  @override
  State<StaffBookingsPage> createState() => _StaffBookingsPageState();
}

class _StaffBookingsPageState extends State<StaffBookingsPage> {
  final ApiService _api = ApiService();
  final DateFormat _dateFormatter = DateFormat('dd/MM/yyyy', 'vi_VN');
  final DateFormat _weekdayFormatter = DateFormat('EEEE, dd/MM', 'vi_VN');
  final DateFormat _timeFormatter = DateFormat('HH:mm');
  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  bool _refreshing = false;
  bool _submittingStatus = false;
  bool _showSearch = false;
  bool _focusHandled = false;
  bool _filtersExpanded = false;
  ApiErrorDetails? _errorState;

  DateTime? _selectedDate = DateTime.now();
  late _BookingStatusFilter _statusFilter;
  String? _selectedCourtId;
  String? _selectedSportId;

  List<StaffBooking> _bookings = const [];
  List<StaffCourt> _courts = const [];
  List<Sport> _sports = const [];

  @override
  void initState() {
    super.initState();
    _statusFilter = _resolveInitialStatus();
    _initialize();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  _BookingStatusFilter _resolveInitialStatus() {
    final provided = switch ((widget.initialStatus ?? '').toLowerCase()) {
      'pending' => _BookingStatusFilter.pending,
      'confirmed' => _BookingStatusFilter.confirmed,
      'completed' => _BookingStatusFilter.completed,
      'cancelled' => _BookingStatusFilter.cancelled,
      'no_show' => _BookingStatusFilter.noShow,
      'all' => _BookingStatusFilter.all,
      _ => null,
    };
    if (provided != null) return provided;
    if ((widget.focusBookingId ?? '').isNotEmpty) {
      return _BookingStatusFilter.all;
    }
    return _BookingStatusFilter.pending;
  }

  Future<void> _initialize() async {
    setState(() {
      _loading = true;
      _errorState = null;
    });
    try {
      await Future.wait([_fetchFacilityAndSports(), _fetchBookings()]);
    } catch (error) {
      if (mounted) {
        setState(() => _errorState = parseApiError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _fetchFacilityAndSports() async {
    try {
      final facility = await _api.staffGetFacility();
      final sports = await _api.staffGetSports();
      if (!mounted) return;
      setState(() {
        _courts = facility.courts;
        _sports = sports;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorState = parseApiError(error));
    }
  }

  Future<void> _fetchBookings() async {
    setState(() {
      _refreshing = true;
      if (_loading) _errorState = null;
    });
    try {
      final from = _selectedDate == null
          ? null
          : DateTime(
              _selectedDate!.year,
              _selectedDate!.month,
              _selectedDate!.day,
            );
      final to = _selectedDate == null
          ? null
          : DateTime(
              _selectedDate!.year,
              _selectedDate!.month,
              _selectedDate!.day,
              23,
              59,
              59,
            );
      final status = switch (_statusFilter) {
        _BookingStatusFilter.all => null,
        _BookingStatusFilter.pending => 'pending',
        _BookingStatusFilter.confirmed => 'confirmed',
        _BookingStatusFilter.completed => 'completed',
        _BookingStatusFilter.cancelled => 'cancelled',
        _BookingStatusFilter.noShow => 'no_show',
      };

      final bookings = await _api.staffGetBookings(
        status: status,
        from: from,
        to: to,
        limit: 150,
      );
      if (!mounted) return;
      setState(() {
        _bookings = bookings;
      });
      _maybeFocusBooking();
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorState = parseApiError(error));
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  Iterable<StaffBooking> get _filteredBookings {
    Iterable<StaffBooking> items = _bookings;
    if ((_selectedCourtId ?? '').isNotEmpty) {
      items = items.where(
        (booking) => booking.booking.courtId == _selectedCourtId,
      );
    }
    if ((_selectedSportId ?? '').isNotEmpty) {
      items = items.where(
        (booking) => booking.booking.sportId == _selectedSportId,
      );
    }
    final query = _searchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      items = items.where((booking) {
        final name = booking.customer?.name?.toLowerCase() ?? '';
        final phone = booking.customer?.phone?.toLowerCase() ?? '';
        final court = booking.court?.name?.toLowerCase() ?? '';
        return name.contains(query) ||
            phone.contains(query) ||
            court.contains(query);
      });
    }
    return items;
  }

  Map<String, int> get _statusMetrics {
    final metrics = <String, int>{
      'pending': 0,
      'confirmed': 0,
      'completed': 0,
      'cancelled': 0,
      'no_show': 0,
    };
    for (final booking in _bookings) {
      final key = booking.status == 'no_show' ? 'no_show' : booking.status;
      if (metrics.containsKey(key)) {
        metrics[key] = metrics[key]! + 1;
      }
    }
    return metrics;
  }

  String get _headerDateLabel {
    if (_selectedDate == null) return 'Tất cả ngày';
    final today = DateTime.now();
    final sameDay =
        today.year == _selectedDate!.year &&
        today.month == _selectedDate!.month &&
        today.day == _selectedDate!.day;
    if (sameDay) return 'Hôm nay · ${_weekdayFormatter.format(_selectedDate!)}';
    return _weekdayFormatter.format(_selectedDate!);
  }

  Future<void> _pickDate() async {
    final initial = _selectedDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: initial.subtract(const Duration(days: 120)),
      lastDate: initial.add(const Duration(days: 120)),
      locale: const Locale('vi'),
    );
    if (picked == null) return;
    setState(() => _selectedDate = picked);
    await _fetchBookings();
  }

  Future<void> _clearDate() async {
    setState(() => _selectedDate = null);
    await _fetchBookings();
  }

  Future<void> _refresh() => _fetchBookings();

  Future<void> _copyPhone(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: phone));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Đã sao chép $phone')));
  }

  Color _statusColor(String status) {
    return _statusColors[status] ?? Theme.of(context).colorScheme.primary;
  }

  Future<void> _openStatusSheet(StaffBooking booking) async {
    final allowedTargets = _availableStatusTargets(booking.status);
    final result = await showModalBottomSheet<_StatusUpdateResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (context) =>
          _StatusUpdateSheet(booking: booking, allowedStatuses: allowedTargets),
    );
    if (result == null) return;
    await _submitStatusChange(
      bookingId: booking.id,
      status: result.status,
      contactMethod: result.contactMethod,
      note: result.note,
    );
  }

  List<String> _availableStatusTargets(String currentStatus) {
    switch (currentStatus) {
      case 'pending':
        return const ['confirmed', 'cancelled'];
      case 'confirmed':
        return const ['completed', 'cancelled', 'no_show'];
      default:
        return const [];
    }
  }

  Future<void> _submitStatusChange({
    required String bookingId,
    required String status,
    String? contactMethod,
    String? note,
  }) async {
    if (_submittingStatus) return;
    setState(() => _submittingStatus = true);
    try {
      final updated = await _api.staffUpdateBookingStatus(
        bookingId,
        status: status,
        contactMethod: contactMethod,
        note: note,
      );
      if (!mounted) return;
      setState(() {
        _bookings = _bookings
            .map((booking) => booking.id == updated.id ? updated : booking)
            .toList(growable: false);
      });
      await showSuccessDialog(
        context,
        message: 'Đã cập nhật trạng thái thành công.',
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không thể cập nhật: $error'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _submittingStatus = false);
      }
    }
  }

  bool _canFreeCourt(StaffBooking booking) {
    if (booking.status != 'pending' && booking.status != 'confirmed') {
      return false;
    }
    return booking.start.isAfter(DateTime.now());
  }

  Future<void> _confirmFreeCourt(StaffBooking booking) async {
    if (!_canFreeCourt(booking)) return;
    final date = _dateFormatter.format(booking.start);
    final range =
        '${_timeFormatter.format(booking.start)} - ${_timeFormatter.format(booking.end)}';
    final courtName = booking.court?.name ?? 'sân';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Huỷ lượt đặt và mở sân?'),
        content: Text(
          'Bạn muốn huỷ lịch trên $courtName lúc $date ($range) để trống cho khách khác?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Để sau'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.delete_outline),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            label: const Text('Huỷ ngay'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _submitStatusChange(
      bookingId: booking.id,
      status: 'cancelled',
      note: 'Huỷ để trống sân cho khách khác',
    );
  }

  Future<void> _openCreateBookingSheet() async {
    final result = await showModalBottomSheet<_CreateBookingResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (context) => _CreateBookingSheet(
        sports: _sports,
        courts: _courts,
        initialDate: _selectedDate ?? DateTime.now(),
      ),
    );
    if (result == null) return;
    await _handleCreateBooking(result);
  }

  Future<void> _handleCreateBooking(_CreateBookingResult result) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: NeoLoadingCard(
          label: 'Đang tạo đặt sân...',
          width: 220,
          height: 180,
        ),
      ),
    );
    try {
      final booking = await _api.staffCreateBooking(
        sportId: result.sportId,
        courtId: result.courtId,
        start: result.start,
        end: result.end,
        customerName: result.customerName,
        customerPhone: result.customerPhone,
        customerEmail: result.customerEmail,
        contactMethod: result.contactMethod,
        note: result.staffNote,
        confirmNow: result.confirmImmediately,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      setState(() {
        _bookings = [booking, ..._bookings]
          ..sort((a, b) => a.start.compareTo(b.start));
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã tạo lượt đặt sân mới')));
    } catch (error) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Tạo đặt sân thất bại: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  void _maybeFocusBooking() {
    if (_focusHandled) return;
    final targetId = widget.focusBookingId;
    if (targetId == null || targetId.isEmpty) return;
    StaffBooking? booking;
    for (final item in _bookings) {
      if (item.id == targetId) {
        booking = item;
        break;
      }
    }
    if (booking == null) return;
    final focused = booking;
    _focusHandled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _openStatusSheet(focused);
    });
  }

  void _redirectToLogin(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  void _redirectToVerifyEmail(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const VerifyEmailScreen()));
  }

  void _toggleSearch() {
    setState(() {
      _showSearch = !_showSearch;
      if (!_showSearch) _searchController.clear();
    });
  }

  Widget _buildHeaderSection(BuildContext context) {
    final metrics = _statusMetrics;
    final cards = [
      _SummaryCard(
        title: 'Đang chờ',
        value: metrics['pending'] ?? 0,
        icon: Icons.schedule,
        color: _statusColors['pending']!,
      ),
      _SummaryCard(
        title: 'Đã duyệt',
        value: metrics['confirmed'] ?? 0,
        icon: Icons.verified,
        color: _statusColors['confirmed']!,
      ),
      _SummaryCard(
        title: 'Hoàn tất',
        value: metrics['completed'] ?? 0,
        icon: Icons.flag,
        color: _statusColors['completed']!,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
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
                      'Quản lý đặt sân',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    _NeuBadge(
                      label: _headerDateLabel,
                      color: Theme.of(context).colorScheme.primaryContainer,
                    ),
                  ],
                ),
              ),
              _HeaderIconButton(
                icon: _showSearch ? Icons.search_off : Icons.search,
                tooltip: _showSearch ? 'Đóng tìm kiếm' : 'Tìm kiếm',
                onPressed: _toggleSearch,
              ),
              const SizedBox(width: 10),
              _HeaderIconButton(
                icon: Icons.refresh,
                tooltip: 'Làm mới',
                onPressed: _refreshing ? null : _refresh,
                showLoader: _refreshing,
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 140,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemBuilder: (context, index) => cards[index],
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemCount: cards.length,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterSection(BuildContext context) {
    final theme = Theme.of(context);
    final pills = _BookingStatusFilter.values
        .map((filter) {
          final selected = _statusFilter == filter;
          return _FilterPill(
            label: _statusFilterLabels[filter]!,
            selected: selected,
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline,
            onTap: () {
              if (_statusFilter == filter) return;
              setState(() => _statusFilter = filter);
              _fetchBookings();
            },
          );
        })
        .toList(growable: false);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_showSearch)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _SearchField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
              ),
            ),
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: theme.dividerColor.withValues(alpha: 0.4),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                InkWell(
                  onTap: () =>
                      setState(() => _filtersExpanded = !_filtersExpanded),
                  borderRadius: BorderRadius.circular(22),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: theme.colorScheme.primary.withValues(
                                alpha: 0.3,
                              ),
                              width: 1,
                            ),
                          ),
                          child: Icon(
                            Icons.filter_list_rounded,
                            size: 20,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Bộ lọc',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _getFilterSummary(),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: 0.6,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          _filtersExpanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          size: 24,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_filtersExpanded)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: theme.dividerColor.withValues(alpha: 0.4),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _selectedDate == null
                                        ? 'Lọc theo ngày'
                                        : _dateFormatter.format(_selectedDate!),
                                    style: theme.textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _selectedDate == null
                                        ? 'Đang hiển thị mọi ngày'
                                        : _headerDateLabel,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.6),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.calendar_today, size: 18),
                              label: Text(
                                _selectedDate == null
                                    ? 'Chọn ngày'
                                    : 'Đổi ngày',
                              ),
                              onPressed: _pickDate,
                            ),
                            const SizedBox(width: 8),
                            if (_selectedDate != null)
                              IconButton.filledTonal(
                                tooltip: 'Bỏ lọc ngày',
                                icon: const Icon(Icons.close_rounded),
                                onPressed: _clearDate,
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(children: pills),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 12,
                          runSpacing: 10,
                          children: [
                            _FilterDropdown(
                              label: 'Môn thể thao',
                              value: _selectedSportId,
                              items: _sports
                                  .map(
                                    (sport) => DropdownMenuItem(
                                      value: sport.id,
                                      child: Text(sport.name),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                setState(() => _selectedSportId = value);
                              },
                              onClear: () =>
                                  setState(() => _selectedSportId = null),
                            ),
                            _FilterDropdown(
                              label: 'Sân',
                              value: _selectedCourtId,
                              items: _courts
                                  .map(
                                    (court) => DropdownMenuItem(
                                      value: court.id,
                                      child: Text(court.name),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                setState(() => _selectedCourtId = value);
                              },
                              onClear: () =>
                                  setState(() => _selectedCourtId = null),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Tổng ${_filteredBookings.length} lượt đặt',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 190,
                        child: NeuButton(
                          onPressed: _openCreateBookingSheet,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.add, color: Colors.black),
                              SizedBox(width: 8),
                              Text(
                                'Tạo lượt đặt',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w700,
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
        ],
      ),
    );
  }

  String _getFilterSummary() {
    final parts = <String>[];

    // Date filter
    if (_selectedDate != null) {
      parts.add(_dateFormatter.format(_selectedDate!));
    } else {
      parts.add('Tất cả ngày');
    }

    // Status filter
    parts.add(_statusFilterLabels[_statusFilter] ?? 'Tất cả');

    // Sport filter
    if (_selectedSportId != null) {
      final sport = _sports.cast<Sport?>().firstWhere(
        (s) => s?.id == _selectedSportId,
        orElse: () => null,
      );
      if (sport != null) {
        parts.add(sport.name);
      }
    }

    // Court filter
    if (_selectedCourtId != null) {
      final court = _courts.cast<StaffCourt?>().firstWhere(
        (c) => c?.id == _selectedCourtId,
        orElse: () => null,
      );
      if (court != null) {
        parts.add(court.name);
      }
    }

    return parts.join(' • ');
  }

  Widget _buildBookingsSliver() {
    if (_errorState != null) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: ErrorStateWidget(
          onRetry: _refresh,
          statusCode: _errorState?.statusCode,
          message: _errorState?.message,
          onLogin: _errorState?.isUnauthenticated == true
              ? () => _redirectToLogin(context)
              : null,
          onVerifyEmail: _errorState?.isEmailNotVerified == true
              ? () => _redirectToVerifyEmail(context)
              : null,
        ),
      );
    }

    if (_loading) {
      return SliverList.separated(
        itemCount: 6,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) => const _BookingSkeleton(),
      );
    }

    final items = _filteredBookings.toList(growable: false);
    if (items.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: _EmptyState(),
      );
    }

    return SliverList.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final booking = items[index];
        final canFree = _canFreeCourt(booking);
        return _BookingCard(
          booking: booking,
          statusLabel: _statusDisplayLabels[booking.status] ?? booking.status,
          statusColor: _statusColor(booking.status),
          onCall: () => _copyPhone(booking.customer?.phone),
          onFreeCourt: canFree ? () => _confirmFreeCourt(booking) : null,
          onTap: () => _openStatusSheet(booking),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _buildHeaderSection(context)),
        SliverToBoxAdapter(child: _buildFilterSection(context)),
        SliverPadding(
          padding: const EdgeInsets.only(left: 16, right: 16, bottom: 24),
          sliver: _buildBookingsSliver(),
        ),
      ],
    );

    final content = SportsGradientBackground(
      variant: SportsBackgroundVariant.staff,
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(onRefresh: _refresh, child: body),
      ),
    );

    if (widget.embedded) {
      return content;
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: content,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateBookingSheet,
        icon: const Icon(Icons.add_task_rounded),
        label: const Text('Tạo lượt đặt'),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final int value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 3),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 32),
          const Spacer(),
          Text(title, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text(
            '$value',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.onClear,
  });

  final String label;
  final String? value;
  final List<DropdownMenuItem<String?>> items;
  final ValueChanged<String?> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
        color: theme.colorScheme.surface,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                hint: Text(label),
                value: value,
                borderRadius: BorderRadius.circular(16),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Tất cả'),
                  ),
                  ...items,
                ],
                onChanged: (selected) {
                  if (selected == null) {
                    onClear();
                  } else {
                    onChanged(selected);
                  }
                },
              ),
            ),
            IconButton(
              tooltip: 'Xoá lọc',
              icon: const Icon(Icons.clear, size: 18),
              onPressed: value == null ? null : onClear,
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.15) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: color, width: selected ? 2.4 : 1.5),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? color.darken() : color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({
    required this.booking,
    required this.statusLabel,
    required this.statusColor,
    required this.onTap,
    required this.onCall,
    this.onFreeCourt,
  });

  final StaffBooking booking;
  final String statusLabel;
  final Color statusColor;
  final VoidCallback onTap;
  final VoidCallback onCall;
  final VoidCallback? onFreeCourt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customer = booking.customer;
    final court = booking.court;
    final timeRange =
        '${DateFormat('HH:mm').format(booking.start)} - ${DateFormat('HH:mm').format(booking.end)}';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.7),
          width: 2.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _StatusChip(label: statusLabel, color: statusColor),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Gọi khách',
                    icon: const Icon(Icons.call_outlined),
                    onPressed: onCall,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                customer?.name ?? 'Khách lẻ',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if ((customer?.phone ?? '').isNotEmpty)
                Text(customer!.phone!, style: theme.textTheme.bodyMedium),
              const Divider(height: 24),
              _InfoRow(
                icon: Icons.calendar_month,
                label: DateFormat(
                  'EEEE, dd/MM/yyyy',
                  'vi_VN',
                ).format(booking.start),
              ),
              _InfoRow(icon: Icons.schedule, label: timeRange),
              if (court != null)
                _InfoRow(icon: Icons.sports_tennis, label: court.name ?? 'Sân'),
              if (booking.booking.total != null)
                _InfoRow(
                  icon: Icons.payments,
                  label: NumberFormat.currency(
                    locale: 'vi_VN',
                    symbol: '₫',
                  ).format(booking.booking.total!),
                ),
              if (onFreeCourt != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: OutlinedButton.icon(
                    onPressed: onFreeCourt,
                    icon: const Icon(Icons.lock_open_rounded),
                    label: const Text('Huỷ & mở sân'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailBlock extends StatelessWidget {
  const _DetailBlock({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_rounded, size: 72, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'Chưa có lượt đặt nào',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Hãy thử thay đổi bộ lọc hoặc tạo lượt đặt mới cho khách.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookingSkeleton extends StatelessWidget {
  const _BookingSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget shimmerBox({double height = 14, double width = double.infinity}) {
      return Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              shimmerBox(height: 22, width: 90),
              const Spacer(),
              shimmerBox(height: 22, width: 60),
            ],
          ),
          const SizedBox(height: 8),
          shimmerBox(width: 160),
          const SizedBox(height: 6),
          shimmerBox(width: 120),
          const SizedBox(height: 12),
          const Divider(height: 24),
          const SizedBox(height: 8),
          shimmerBox(width: 200),
          const SizedBox(height: 6),
          shimmerBox(width: 150),
        ],
      ),
    );
  }
}

class _StatusUpdateResult {
  _StatusUpdateResult({required this.status, this.contactMethod, this.note});

  final String status;
  final String? contactMethod;
  final String? note;
}

class _StatusUpdateSheet extends StatefulWidget {
  const _StatusUpdateSheet({
    required this.booking,
    required this.allowedStatuses,
  });

  final StaffBooking booking;
  final List<String> allowedStatuses;

  @override
  State<_StatusUpdateSheet> createState() => _StatusUpdateSheetState();
}

class _StatusUpdateSheetState extends State<_StatusUpdateSheet> {
  String? _selectedStatus;
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.allowedStatuses.isNotEmpty) {
      _selectedStatus = widget.allowedStatuses.first;
    }
    final defaultChannel = widget.booking.preferredContactMethod;
    if (defaultChannel != null && defaultChannel.isNotEmpty) {
      _contactController.text = defaultChannel;
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasActions = widget.allowedStatuses.isNotEmpty;

    return DraggableScrollableSheet(
      expand: false,
      builder: (context, controller) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: ListView(
          controller: controller,
          children: [
            Center(
              child: Container(
                width: 50,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _buildBookingSummary(context),
            const SizedBox(height: 24),
            Text('Cập nhật trạng thái', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            if (!hasActions)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Lượt đặt này đã hoàn tất hoặc không còn trạng thái mới để cập nhật.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            if (hasActions) ...[
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: widget.allowedStatuses.map((status) {
                  final color =
                      _statusColor(status) ?? theme.colorScheme.primary;
                  return ChoiceChip(
                    label: Text(_statusDisplayLabels[status] ?? status),
                    selected: _selectedStatus == status,
                    selectedColor: color.withValues(alpha: 0.2),
                    onSelected: (_) => setState(() => _selectedStatus = status),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _contactController,
                decoration: const InputDecoration(
                  labelText: 'Kênh liên hệ (nếu có)',
                  prefixIcon: Icon(Icons.call_made),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Ghi chú thêm',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                icon: const Icon(Icons.check),
                onPressed: _selectedStatus == null
                    ? null
                    : () {
                        Navigator.of(context).pop(
                          _StatusUpdateResult(
                            status: _selectedStatus!,
                            contactMethod:
                                _contactController.text.trim().isEmpty
                                ? null
                                : _contactController.text.trim(),
                            note: _noteController.text.trim().isEmpty
                                ? null
                                : _noteController.text.trim(),
                          ),
                        );
                      },
                label: const Text('Xác nhận'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBookingSummary(BuildContext context) {
    final booking = widget.booking;
    final customer = booking.customer;
    final court = booking.court;
    final theme = Theme.of(context);
    final dateFormatter = DateFormat('EEEE, dd/MM/yyyy', 'vi_VN');
    final timeFormatter = DateFormat('HH:mm');
    final moneyFormatter = NumberFormat.currency(locale: 'vi_VN', symbol: '₫');
    final chips = <Widget>[
      _StatusChip(
        label: _statusDisplayLabels[booking.status] ?? booking.status,
        color: _statusColor(booking.status) ?? theme.colorScheme.primary,
      ),
      if ((booking.preferredContactMethod ?? '').isNotEmpty)
        _NeuBadge(
          label: booking.preferredContactMethod!.toUpperCase(),
          color: theme.colorScheme.primaryContainer,
        ),
    ];

    final List<Widget> detailSections = [
      _DetailBlock(
        title: 'Chi tiết thời gian',
        children: [
          _DetailRow(label: 'Ngày', value: dateFormatter.format(booking.start)),
          _DetailRow(
            label: 'Khung giờ',
            value:
                '${timeFormatter.format(booking.start)} - ${timeFormatter.format(booking.end)}',
          ),
          _DetailRow(
            label: 'Thời lượng',
            value: '${booking.end.difference(booking.start).inMinutes} phút',
          ),
        ],
      ),
    ];

    final hasCourtInfo =
        court != null ||
        booking.sport != null ||
        (booking.staffNote != null && booking.staffNote!.isNotEmpty);
    if (hasCourtInfo) {
      detailSections.add(const SizedBox(height: 16));
      detailSections.add(
        _DetailBlock(
          title: 'Sân & dịch vụ',
          children: [
            if (court != null)
              _DetailRow(label: 'Sân', value: court.name ?? '—'),
            if (booking.sport?.name != null)
              _DetailRow(label: 'Môn', value: booking.sport!.name!),
            if ((booking.staffNote ?? '').isNotEmpty)
              _DetailRow(label: 'Ghi chú nhân viên', value: booking.staffNote!),
          ],
        ),
      );
    }

    final total = booking.booking.total;
    if (total != null) {
      detailSections.add(const SizedBox(height: 16));
      detailSections.add(
        _DetailBlock(
          title: 'Thanh toán',
          children: [
            _DetailRow(
              label: 'Thành tiền',
              value: moneyFormatter.format(total),
            ),
          ],
        ),
      );
    }

    return Column(
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
                    customer?.name ?? 'Khách lẻ',
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(customer?.phone ?? '—'),
                ],
              ),
            ),
            Wrap(spacing: 8, runSpacing: 8, children: chips),
          ],
        ),
        const SizedBox(height: 24),
        ...detailSections,
      ],
    );
  }

  Color? _statusColor(String status) => _statusColors[status];
}

class _CreateBookingResult {
  _CreateBookingResult({
    required this.sportId,
    required this.courtId,
    required this.start,
    required this.end,
    required this.customerName,
    required this.customerPhone,
    required this.customerEmail,
    required this.contactMethod,
    required this.staffNote,
    required this.confirmImmediately,
  });

  final String sportId;
  final String courtId;
  final DateTime start;
  final DateTime end;
  final String customerName;
  final String customerPhone;
  final String? customerEmail;
  final String? contactMethod;
  final String? staffNote;
  final bool confirmImmediately;
}

class _CreateBookingSheet extends StatefulWidget {
  const _CreateBookingSheet({
    required this.sports,
    required this.courts,
    required this.initialDate,
  });

  final List<Sport> sports;
  final List<StaffCourt> courts;
  final DateTime initialDate;

  @override
  State<_CreateBookingSheet> createState() => _CreateBookingSheetState();
}

class _CreateBookingSheetState extends State<_CreateBookingSheet> {
  late DateTime _selectedDate = widget.initialDate;
  final _formKey = GlobalKey<FormState>();
  String? _sportsId;
  String? _courtId;
  TimeOfDay _startTime = const TimeOfDay(hour: 6, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 7, minute: 0);
  bool _confirmNow = true;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _contactController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      builder: (context, controller) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Form(
          key: _formKey,
          child: ListView(
            controller: controller,
            children: [
              Center(
                child: Container(
                  width: 60,
                  height: 6,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              Text(
                'Tạo lượt đặt mới',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _sportsId,
                decoration: const InputDecoration(labelText: 'Môn thể thao'),
                items: widget.sports
                    .map(
                      (sport) => DropdownMenuItem(
                        value: sport.id,
                        child: Text(sport.name),
                      ),
                    )
                    .toList(),
                validator: (value) => value == null ? 'Chọn môn' : null,
                onChanged: (value) => setState(() => _sportsId = value),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _courtId,
                decoration: const InputDecoration(labelText: 'Chọn sân'),
                items: widget.courts
                    .map(
                      (court) => DropdownMenuItem(
                        value: court.id,
                        child: Text(court.name),
                      ),
                    )
                    .toList(),
                validator: (value) => value == null ? 'Chọn sân' : null,
                onChanged: (value) => setState(() => _courtId = value),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Ngày: ${DateFormat('dd/MM/yyyy').format(_selectedDate)}',
                ),
                subtitle: const Text('Chạm để đổi ngày'),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    firstDate: DateTime.now().subtract(const Duration(days: 1)),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    initialDate: _selectedDate,
                  );
                  if (picked != null) setState(() => _selectedDate = picked);
                },
              ),
              Row(
                children: [
                  Expanded(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Bắt đầu ${_startTime.format(context)}'),
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: _startTime,
                        );
                        if (picked != null) setState(() => _startTime = picked);
                      },
                    ),
                  ),
                  Expanded(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Kết thúc ${_endTime.format(context)}'),
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: _endTime,
                        );
                        if (picked != null) setState(() => _endTime = picked);
                      },
                    ),
                  ),
                ],
              ),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Tên khách hàng'),
                validator: (value) =>
                    value == null || value.isEmpty ? 'Nhập tên' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(labelText: 'Số điện thoại'),
                validator: (value) => value == null || value.isEmpty
                    ? 'Nhập số điện thoại'
                    : null,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email (tuỳ chọn)',
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _contactController,
                decoration: const InputDecoration(
                  labelText: 'Kênh liên hệ (tuỳ chọn)',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _noteController,
                decoration: const InputDecoration(labelText: 'Ghi chú'),
                minLines: 2,
                maxLines: 4,
              ),
              SwitchListTile.adaptive(
                value: _confirmNow,
                onChanged: (value) => setState(() => _confirmNow = value),
                title: const Text('Xác nhận ngay cho khách'),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Tạo lượt đặt'),
                onPressed: () {
                  if (!_formKey.currentState!.validate()) return;
                  final start = DateTime(
                    _selectedDate.year,
                    _selectedDate.month,
                    _selectedDate.day,
                    _startTime.hour,
                    _startTime.minute,
                  );
                  final end = DateTime(
                    _selectedDate.year,
                    _selectedDate.month,
                    _selectedDate.day,
                    _endTime.hour,
                    _endTime.minute,
                  );
                  Navigator.of(context).pop(
                    _CreateBookingResult(
                      sportId: _sportsId!,
                      courtId: _courtId!,
                      start: start,
                      end: end,
                      customerName: _nameController.text.trim(),
                      customerPhone: _phoneController.text.trim(),
                      customerEmail: _emailController.text.trim().isEmpty
                          ? null
                          : _emailController.text.trim(),
                      contactMethod: _contactController.text.trim().isEmpty
                          ? null
                          : _contactController.text.trim(),
                      staffNote: _noteController.text.trim().isEmpty
                          ? null
                          : _noteController.text.trim(),
                      confirmImmediately: _confirmNow,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: 'Tìm khách, số điện thoại, sân...',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(28)),
        filled: true,
      ),
      onChanged: onChanged,
    );
  }
}

class _NeuBadge extends StatelessWidget {
  const _NeuBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.showLoader = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool showLoader;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white,
          border: Border.all(color: Colors.black, width: 2),
        ),
        child: IconButton(
          onPressed: onPressed,
          icon: showLoader
              ? const NeoLoadingDot(size: 18, fillColor: Colors.white)
              : Icon(icon),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color, width: 2),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }
}

extension _ColorDarkener on Color {
  Color darken([double amount = 0.1]) {
    final hsl = HSLColor.fromColor(this);
    final adjusted = hsl.withLightness(
      (hsl.lightness - amount).clamp(0.0, 1.0),
    );
    return adjusted.toColor();
  }
}
