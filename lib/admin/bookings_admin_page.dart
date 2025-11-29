import 'package:flutter/material.dart';
import 'package:khu_lien_hop_tt/models/booking.dart';
import 'package:khu_lien_hop_tt/models/court.dart';
import 'package:khu_lien_hop_tt/models/facility.dart';
import 'package:khu_lien_hop_tt/models/sport.dart';
import 'package:khu_lien_hop_tt/models/user.dart';
import 'package:khu_lien_hop_tt/services/api_service.dart';
import 'package:khu_lien_hop_tt/widgets/sports_gradient_background.dart';

const Map<String, String> bookingStatusLabels = {
  'pending': 'Chờ xử lý',
  'confirmed': 'Đã xác nhận',
  'completed': 'Đã hoàn tất',
  'cancelled': 'Đã hủy',
  'no_show': 'Vắng mặt',
  'refunded': 'Đã hoàn tiền',
};

const List<String> bookingStatusOptions = [
  'pending',
  'confirmed',
  'completed',
  'cancelled',
  'no_show',
  'refunded',
];

String bookingStatusLabel(String status) =>
    bookingStatusLabels[status] ?? status;

class BookingsAdminPage extends StatefulWidget {
  const BookingsAdminPage({super.key});

  @override
  State<BookingsAdminPage> createState() => _BookingsAdminPageState();
}

class _BookingsAdminPageState extends State<BookingsAdminPage> {
  final _api = ApiService();
  bool _bootstrapping = false;
  bool _loading = false;
  String? _error;

  List<Booking> _bookings = const [];
  List<Facility> _facilities = const [];
  List<Sport> _sports = const [];
  List<AppUser> _users = const [];

  Map<String, Facility> _facilityById = const {};
  Map<String, Sport> _sportById = const {};
  Map<String, AppUser> _userById = const {};
  final Map<String, List<Court>> _courtsByFacility = {};
  final Map<String, Court> _courtById = {};

  String? _filterFacilityId;
  String? _filterUserId;
  String? _filterStatus;
  DateTimeRange? _filterRange;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _bootstrapping = true;
      _error = null;
    });
    try {
      final facilities = await _api.adminGetFacilities(includeInactive: true);
      final sports = await _api.adminGetSports(includeInactive: true);
      final users = await _api.adminGetUsers();
      _facilities = facilities;
      _sports = sports;
      _users = users;
      _rebuildIndexes();
      await _loadBookings();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _bootstrapping = false);
      }
    }
  }

  void _rebuildIndexes() {
    _facilityById = {for (final f in _facilities) f.id: f};
    _sportById = {for (final s in _sports) s.id: s};
    _userById = {for (final u in _users) u.id: u};
  }

  Future<void> _loadBookings() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bookings = await _api.adminGetBookings(
        facilityId: _filterFacilityId,
        userId: _filterUserId,
        status: _filterStatus,
        from: _filterRange?.start,
        to: _filterRange?.end,
        includeDeleted: _filterStatus == 'cancelled',
      );
      if (!mounted) return;
      setState(() => _bookings = bookings);
      final facilityIds = {for (final b in bookings) b.facilityId};
      await Future.wait(facilityIds.map(_ensureCourtsLoaded));
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<List<Court>> _ensureCourtsLoaded(String facilityId) async {
    if (_courtsByFacility.containsKey(facilityId)) {
      return _courtsByFacility[facilityId]!;
    }
    final courts = await _api.adminGetCourtsByFacility(facilityId);
    _courtsByFacility[facilityId] = courts;
    for (final c in courts) {
      _courtById[c.id] = c;
    }
    return courts;
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final initial =
        _filterRange ??
        DateTimeRange(
          start: now.subtract(const Duration(days: 7)),
          end: now.add(const Duration(days: 7)),
        );
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: initial,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (!mounted || picked == null) return;
    setState(() => _filterRange = picked);
    await _loadBookings();
  }

  void _clearFilters() {
    setState(() {
      _filterFacilityId = null;
      _filterUserId = null;
      _filterStatus = null;
      _filterRange = null;
    });
    _loadBookings();
  }

  String _facilityName(String id) => _facilityById[id]?.name ?? id;
  String _sportName(String id) => _sportById[id]?.name ?? id;
  String _courtName(String id) => _courtById[id]?.name ?? id;
  String _userName(String id) {
    final u = _userById[id];
    if (u == null) return id;
    if ((u.name ?? '').isNotEmpty) return u.name!;
    return u.email;
  }

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
  }

  String _formatMoney(double? amount, String currency) {
    if (amount == null) return '---';
    final val = amount.toStringAsFixed(0);
    final buffer = StringBuffer();
    for (int i = 0; i < val.length; i++) {
      final char = val[val.length - 1 - i];
      if (i != 0 && i % 3 == 0) buffer.write('.');
      buffer.write(char);
    }
    final formatted = buffer.toString().split('').reversed.join();
    return '$formatted $currency';
  }

  Future<void> _createBooking() async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<_BookingFormResult>(
      context: context,
      builder: (_) => _BookingDialog(
        facilities: _facilities,
        sports: _sports,
        users: _users,
        loadCourts: _ensureCourtsLoaded,
      ),
    );
    if (!mounted || result == null) return;
    setState(() => _loading = true);
    try {
      final quote = await _api.quotePrice(
        facilityId: result.facilityId,
        sportId: result.sportId,
        courtId: result.courtId,
        start: result.start,
        end: result.end,
        currency: result.currency,
        userId: result.customerId,
      );
      await _api.createBooking(
        customerId: result.customerId,
        facilityId: result.facilityId,
        courtId: result.courtId,
        sportId: result.sportId,
        start: result.start,
        end: result.end,
        currency: result.currency,
        pricingSnapshot: quote,
        participants: result.participants,
        voucherId: result.voucherId,
        status: result.status,
      );
      await _loadBookings();
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Đã tạo đặt sân')));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editBooking(Booking booking) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<_BookingFormResult>(
      context: context,
      builder: (_) => _BookingDialog(
        facilities: _facilities,
        sports: _sports,
        users: _users,
        loadCourts: _ensureCourtsLoaded,
        initial: booking,
      ),
    );
    if (!mounted || result == null) return;
    setState(() => _loading = true);
    try {
      final payload = {
        'customerId': result.customerId,
        'facilityId': result.facilityId,
        'courtId': result.courtId,
        'sportId': result.sportId,
        'start': result.start.toIso8601String(),
        'end': result.end.toIso8601String(),
        'status': result.status,
        'currency': result.currency,
        'participants': result.participants,
        'voucherId': result.voucherId ?? '',
      };
      await _api.adminUpdateBooking(booking.id, payload);
      await _loadBookings();
      if (!mounted) return;
      messenger
          .showSnackBar(const SnackBar(content: Text('Đã cập nhật đặt sân')));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteBooking(Booking booking) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Huỷ đặt sân'),
        content: Text(
          'Đánh dấu xoá đặt sân của ${_userName(booking.customerId)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    if (!mounted || ok != true) return;

    setState(() => _loading = true);
    try {
      await _api.adminDeleteBooking(booking.id);
      await _loadBookings();
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Đã xoá đặt sân')));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SportsGradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Quản lý Đặt sân'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Làm mới',
              onPressed: _loading ? null : _loadBookings,
            ),
          ],
        ),
        body: Column(
          children: [
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            _buildFilters(),
            const Divider(height: 1),
            Expanded(child: _buildBody()),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _loading || _bootstrapping ? null : _createBooking,
          icon: const Icon(Icons.add),
          label: const Text('Tạo đặt sân'),
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 260,
            child: DropdownButtonFormField<String?>(
              initialValue: _filterFacilityId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Cơ sở'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Tất cả cơ sở'),
                ),
                ..._facilities.map(
                  (f) => DropdownMenuItem(
                    value: f.id,
                    child: Text(f.name, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
              onChanged: (v) async {
                setState(() => _filterFacilityId = v);
                await _loadBookings();
              },
            ),
          ),
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<String?>(
              initialValue: _filterUserId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Người dùng'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Tất cả người dùng'),
                ),
                ..._users.map(
                  (u) => DropdownMenuItem(
                    value: u.id,
                    child: Text(_labelUser(u), overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
              onChanged: (v) async {
                setState(() => _filterUserId = v);
                await _loadBookings();
              },
            ),
          ),
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<String?>(
              initialValue: _filterStatus,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Trạng thái'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Tất cả trạng thái'),
                ),
                ...bookingStatusOptions.map(
                  (s) => DropdownMenuItem<String?>(
                    value: s,
                    child: Text(
                      bookingStatusLabel(s),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              onChanged: (v) async {
                setState(() => _filterStatus = v);
                await _loadBookings();
              },
            ),
          ),
          OutlinedButton.icon(
            onPressed: _pickRange,
            icon: const Icon(Icons.date_range),
            label: Text(
              _filterRange == null
                  ? 'Khoảng ngày'
                  : '${_formatDate(_filterRange!.start)} → ${_formatDate(_filterRange!.end)}',
            ),
          ),
          if (_filterFacilityId != null ||
              _filterStatus != null ||
              _filterUserId != null ||
              _filterRange != null)
            TextButton.icon(
              onPressed: _clearFilters,
              icon: const Icon(Icons.clear),
              label: const Text('Bỏ lọc'),
            ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year}';
  }

  static String _labelUser(AppUser u) {
    if ((u.name ?? '').isNotEmpty) {
      return '${u.name} (${u.email})';
    }
    return u.email;
  }

  Widget _buildBody() {
    if (_bootstrapping) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                color: Colors.redAccent,
                size: 32,
              ),
              const SizedBox(height: 8),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _loadBookings,
                icon: const Icon(Icons.refresh),
                label: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      );
    }
    if (_bookings.isEmpty) {
      return const Center(child: Text('Chưa có đặt sân phù hợp.'));
    }
    return RefreshIndicator(
      onRefresh: _loadBookings,
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: _bookings.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, index) {
          final b = _bookings[index];
          return ListTile(
            title: Text(
              '${_formatDateTime(b.start)} → ${_formatDateTime(b.end)}',
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Khách: ${_userName(b.customerId)}'),
                Text(
                  'Cơ sở: ${_facilityName(b.facilityId)} · Sân: ${_courtName(b.courtId)} · Môn: ${_sportName(b.sportId)}',
                ),
                Text(
                  'Trạng thái: ${bookingStatusLabel(b.status)} · Tổng: ${_formatMoney(b.total, b.currency)}',
                ),
              ],
            ),
            isThreeLine: true,
            trailing: Wrap(
              spacing: 8,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit),
                  tooltip: 'Sửa',
                  onPressed: _loading ? null : () => _editBooking(b),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Xoá',
                  onPressed: _loading ? null : () => _deleteBooking(b),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BookingFormResult {
  final String customerId;
  final String facilityId;
  final String sportId;
  final String courtId;
  final DateTime start;
  final DateTime end;
  final String status;
  final String currency;
  final List<String> participants;
  final String? voucherId;

  const _BookingFormResult({
    required this.customerId,
    required this.facilityId,
    required this.sportId,
    required this.courtId,
    required this.start,
    required this.end,
    required this.status,
    required this.currency,
    this.participants = const [],
    this.voucherId,
  });
}

class _BookingDialog extends StatefulWidget {
  final List<AppUser> users;
  final List<Facility> facilities;
  final List<Sport> sports;
  final Future<List<Court>> Function(String facilityId) loadCourts;
  final Booking? initial;

  const _BookingDialog({
    required this.users,
    required this.facilities,
    required this.sports,
    required this.loadCourts,
    this.initial,
  });

  @override
  State<_BookingDialog> createState() => _BookingDialogState();
}

class _BookingDialogState extends State<_BookingDialog> {
  final _formKey = GlobalKey<FormState>();
  String? _customerId;
  String? _facilityId;
  String? _sportId;
  String? _courtId;
  String _status = 'pending';
  String _currency = 'VND';
  DateTime? _start;
  DateTime? _end;
  final TextEditingController _voucher = TextEditingController();
  final TextEditingController _participantsController = TextEditingController();
  bool _loadingCourts = false;
  List<Court> _courts = const [];

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _customerId =
        initial?.customerId ??
        (widget.users.isNotEmpty ? widget.users.first.id : null);
    _facilityId =
        initial?.facilityId ??
        (widget.facilities.isNotEmpty ? widget.facilities.first.id : null);
    _sportId =
        initial?.sportId ??
        (widget.sports.isNotEmpty ? widget.sports.first.id : null);
    _courtId = initial?.courtId;
    _status = initial?.status ?? 'pending';
    _currency = initial?.currency ?? 'VND';
    _start = initial?.start;
    _end = initial?.end;
    if (initial?.voucherId != null) _voucher.text = initial!.voucherId!;
    if (initial?.participants?.isNotEmpty == true) {
      _participantsController.text = initial!.participants!.join(',');
    }
    if (_facilityId != null) {
      _loadCourtsForFacility(_facilityId!, selectExisting: true);
    }
  }

  @override
  void dispose() {
    _voucher.dispose();
    _participantsController.dispose();
    super.dispose();
  }

  Future<void> _loadCourtsForFacility(
    String facilityId, {
    bool selectExisting = false,
  }) async {
    setState(() => _loadingCourts = true);
    try {
      final courts = await widget.loadCourts(facilityId);
      if (!mounted) return;
      setState(() {
        _courts = courts;
        final filtered = _filteredCourts();
        if (selectExisting) {
          if (_courtId != null && filtered.every((c) => c.id != _courtId)) {
            _courtId = filtered.isNotEmpty ? filtered.first.id : null;
          } else if (_courtId == null && filtered.isNotEmpty) {
            _courtId = filtered.first.id;
          }
        } else {
          _courtId = filtered.isNotEmpty ? filtered.first.id : null;
        }
      });
    } finally {
      if (mounted) setState(() => _loadingCourts = false);
    }
  }

  List<Court> _filteredCourts() {
    if (_sportId == null) return _courts;
    return _courts.where((c) => c.sportId == _sportId).toList();
  }

  Future<void> _pickDateTime({required bool isStart}) async {
    final current = isStart ? _start : _end;
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: (current ?? now).toLocal(),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (!mounted || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime((current ?? now).toLocal()),
    );
    if (!mounted || time == null) return;
    final combined = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() {
      if (isStart) {
        _start = combined;
      } else {
        _end = combined;
      }
    });
  }

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return 'Chọn thời gian';
    final local = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Tạo đặt sân' : 'Cập nhật đặt sân'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _customerId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Người dùng'),
                  items: widget.users
                      .map(
                        (u) => DropdownMenuItem(
                          value: u.id,
                          child: Text(
                            _BookingsAdminPageState._labelUser(u),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Chọn người dùng' : null,
                  onChanged: (v) => setState(() => _customerId = v),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _facilityId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Cơ sở'),
                  items: widget.facilities
                      .map(
                        (f) => DropdownMenuItem(
                          value: f.id,
                          child: Text(f.name, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Chọn cơ sở' : null,
                  onChanged: (v) {
                    setState(() {
                      _facilityId = v;
                    });
                    if (v != null) _loadCourtsForFacility(v);
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _sportId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Môn'),
                  items: widget.sports
                      .map(
                        (s) => DropdownMenuItem(
                          value: s.id,
                          child: Text(s.name, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Chọn môn' : null,
                  onChanged: (v) {
                    setState(() => _sportId = v);
                    final filtered = _filteredCourts();
                    if (_courtId != null &&
                        filtered.every((c) => c.id != _courtId)) {
                      setState(
                        () => _courtId = filtered.isNotEmpty
                            ? filtered.first.id
                            : null,
                      );
                    }
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _courtId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: _loadingCourts ? 'Đang tải sân...' : 'Sân',
                  ),
                  items: _filteredCourts()
                      .map(
                        (c) => DropdownMenuItem(
                          value: c.id,
                          child: Text(c.name, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Chọn sân' : null,
                  onChanged: (v) => setState(() => _courtId = v),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickDateTime(isStart: true),
                        icon: const Icon(Icons.play_arrow),
                        label: Text('Bắt đầu: ${_formatDateTime(_start)}'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickDateTime(isStart: false),
                        icon: const Icon(Icons.stop),
                        label: Text('Kết thúc: ${_formatDateTime(_end)}'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: 'Trạng thái'),
                  items: bookingStatusOptions
                      .map(
                        (s) => DropdownMenuItem(
                          value: s,
                          child: Text(bookingStatusLabel(s)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _status = v ?? 'pending'),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  initialValue: _currency,
                  decoration: const InputDecoration(labelText: 'Tiền tệ'),
                  textCapitalization: TextCapitalization.characters,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Nhập tiền tệ' : null,
                  onChanged: (v) => _currency = v.trim().toUpperCase(),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _voucher,
                  decoration: const InputDecoration(
                    labelText: 'Voucher ID (tuỳ chọn)',
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _participantsController,
                  decoration: const InputDecoration(
                    labelText: 'Người tham gia (IDs, cách nhau dấu phẩy)',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Huỷ'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.initial == null ? 'Tạo' : 'Lưu'),
        ),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_start == null || _end == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chọn thời gian bắt đầu/kết thúc')),
      );
      return;
    }
    if (!_start!.isBefore(_end!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thời gian bắt đầu phải trước kết thúc')),
      );
      return;
    }
    final participants = _participantsController.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    Navigator.pop(
      context,
      _BookingFormResult(
        customerId: _customerId!,
        facilityId: _facilityId!,
        sportId: _sportId!,
        courtId: _courtId!,
        start: _start!,
        end: _end!,
        status: _status,
        currency: _currency,
        participants: participants,
        voucherId: _voucher.text.trim().isEmpty ? null : _voucher.text.trim(),
      ),
    );
  }
}
