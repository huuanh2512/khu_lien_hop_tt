import 'package:flutter/material.dart';
import 'package:neubrutalism_ui/neubrutalism_ui.dart';

import 'package:khu_lien_hop_tt/models/booking.dart';
import 'package:khu_lien_hop_tt/widgets/neu_button.dart';
import 'package:khu_lien_hop_tt/services/api_service.dart';
import 'package:khu_lien_hop_tt/services/auth_service.dart';
import 'package:khu_lien_hop_tt/widgets/success_dialog.dart';

class BookingHistoryPage extends StatefulWidget {
  const BookingHistoryPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<BookingHistoryPage> createState() => _BookingHistoryPageState();
}

class _BookingHistoryPageState extends State<BookingHistoryPage> {
  final ApiService _api = ApiService();
  List<Booking> _bookings = const [];
  bool _loading = true;
  String? _error;
  final Set<String> _cancelling = <String>{};

  @override
  void initState() {
    super.initState();
    _loadBookings();
  }

  Future<void> _loadBookings() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bookings = await _api.getUserBookings();
      if (!mounted) return;
      setState(() {
        _bookings = bookings;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(e);
      });
    }
  }

  Future<void> _refresh() async {
    try {
      final bookings = await _api.getUserBookings();
      if (!mounted) return;
      setState(() => _bookings = bookings);
    } catch (e) {
      if (!mounted) return;
      await _showSnack(_friendlyError(e), isError: true);
    }
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    const prefix = 'Exception: ';
    return text.startsWith(prefix) ? text.substring(prefix.length) : text;
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

  bool _isUpcoming(Booking booking, DateTime now) {
    if (booking.status.toLowerCase() == 'cancelled') return false;
    return booking.end.isAfter(now);
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final yyyy = local.year.toString().padLeft(4, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$dd/$mm/$yyyy $hh:$min';
  }

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return 'Đang chờ';
      case 'confirmed':
        return 'Đã xác nhận';
      case 'completed':
        return 'Đã hoàn thành';
      case 'cancelled':
        return 'Đã hủy';
      case 'matched':
        return 'Đã ghép trận';
      default:
        return status;
    }
  }

  Color _statusColor(String status, ThemeData theme) {
    switch (status.toLowerCase()) {
      case 'pending':
        return theme.colorScheme.tertiary;
      case 'confirmed':
      case 'completed':
        return theme.colorScheme.primary;
      case 'cancelled':
        return theme.colorScheme.error;
      default:
        return theme.colorScheme.secondary;
    }
  }

  String _formatCurrency(double? total, String currency) {
    if (total == null) return '—';
    final rounded = total % 1 == 0
        ? total.toStringAsFixed(0)
        : total.toStringAsFixed(2);
    return '$rounded $currency';
  }

  bool _canCancel(Booking booking) => booking.status.toLowerCase() == 'pending';

  Future<void> _cancelBooking(Booking booking) async {
    if (!_canCancel(booking) || _cancelling.contains(booking.id)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Huỷ đặt sân'),
        content: Text(
          'Bạn chắc chắn muốn huỷ đặt sân tại ${booking.courtName ?? booking.courtId}?',
        ),
        actions: [
          NeuButton(
            onPressed: () => Navigator.of(context).pop(false),
            buttonHeight: 40,
            buttonWidth: 100,
            borderRadius: BorderRadius.circular(12),
            borderColor: Colors.black,
            buttonColor: Colors.white,
            shadowColor: Colors.black.withValues(alpha: 0.25),
            child: const Text(
              'Không',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          NeuButton(
            onPressed: () => Navigator.of(context).pop(true),
            buttonHeight: 40,
            buttonWidth: 120,
            borderRadius: BorderRadius.circular(12),
            borderColor: Colors.black,
            buttonColor: Colors.red.shade700,
            shadowColor: Colors.black.withValues(alpha: 0.35),
            child: const Text(
              'Huỷ đặt sân',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _cancelling.add(booking.id));
    try {
      await _api.cancelBooking(booking.id);
      if (!mounted) return;
      await _refresh();
      if (!mounted) return;
      await _showSnack('Đã huỷ đặt sân.');
    } catch (e) {
      if (!mounted) return;
      await _showSnack(_friendlyError(e), isError: true);
    } finally {
      if (mounted) {
        setState(() => _cancelling.remove(booking.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = AuthService.instance.currentUser;
    final mediaPadding = MediaQuery.of(context).padding;
    final headerTopPadding = mediaPadding.top + 16;
    final listBottomPadding = mediaPadding.bottom + 24;

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: NeuContainer(
            borderRadius: BorderRadius.circular(24),
            color: theme.colorScheme.surface,
            borderColor: Colors.black,
            borderWidth: 3,
            shadowColor: Colors.black.withValues(alpha: 0.25),
            offset: const Offset(8, 8),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'Không thể tải lịch sử đặt sân',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  NeuButton(
                    onPressed: _loadBookings,
                    buttonHeight: 48,
                    buttonWidth: 140,
                    borderRadius: BorderRadius.circular(16),
                    borderColor: Colors.black,
                    buttonColor: theme.colorScheme.primary,
                    shadowColor: Colors.black.withValues(alpha: 0.35),
                    child: const Text(
                      'Thử lại',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } else {
      final now = DateTime.now();
      final upcoming = _bookings.where((b) => _isUpcoming(b, now)).toList()
        ..sort((a, b) => a.start.compareTo(b.start));
      final history = _bookings.where((b) => !_isUpcoming(b, now)).toList()
        ..sort((a, b) => b.start.compareTo(a.start));

      final children = <Widget>[
        Text('Đặt sân sắp diễn ra', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (upcoming.isEmpty) _buildEmptyState('Không có đặt sân sắp diễn ra.'),
        ...upcoming.map(_buildBookingCard),
        const SizedBox(height: 24),
        Text('Lịch sử đặt sân', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (history.isEmpty) _buildEmptyState('Chưa có lịch sử đặt sân.'),
        ...history.map(_buildBookingCard),
      ];

      body = RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(16, 16, 16, listBottomPadding),
          children: children,
        ),
      );
    }

    if (widget.embedded) {
      return SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16, headerTopPadding, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Lịch sử đặt sân',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lịch sử đặt sân'),
        actions: [
          if (user != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: Text(
                  user.name?.isNotEmpty == true ? user.name! : user.email,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
        ],
      ),
      body: body,
    );
  }

  Widget _buildBookingCard(Booking booking) {
    final theme = Theme.of(context);
    final facility = booking.facilityName ?? booking.facilityId;
    final court = booking.courtName ?? booking.courtId;
    final sport = booking.sportName ?? booking.sportId;
    final statusLabel = _statusLabel(booking.status);
    final statusColor = _statusColor(booking.status, theme);
    final cancellable = _canCancel(booking);
    final isCancelling = _cancelling.contains(booking.id);
    
    // Determine pastel background based on status
    Color cardColor;
    switch (booking.status.toLowerCase()) {
      case 'confirmed':
        cardColor = const Color(0xFFE6F3FF); // light blue
        break;
      case 'completed':
        cardColor = const Color(0xFFE8F5E9); // light green
        break;
      case 'cancelled':
        cardColor = const Color(0xFFF8D7DA); // light red
        break;
      case 'pending':
      default:
        cardColor = const Color(0xFFFFF8DC); // cream
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: NeuContainer(
        borderRadius: BorderRadius.circular(20),
        color: cardColor,
        borderColor: Colors.black,
        borderWidth: 3,
        shadowColor: Colors.black.withValues(alpha: 0.25),
        offset: const Offset(5, 5),
        child: Padding(
          padding: const EdgeInsets.all(20),
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
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: theme.colorScheme.primary, width: 2),
                            ),
                            child: Icon(Icons.sports_tennis, size: 16, color: theme.colorScheme.primary),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              court,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.location_on, size: 16, color: Colors.black.withValues(alpha: 0.6)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Cơ sở: $facility',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.sports_handball, size: 16, color: Colors.black.withValues(alpha: 0.6)),
                          const SizedBox(width: 4),
                          Text(
                            'Môn: $sport',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: statusColor, width: 2),
                    boxShadow: const [
                      BoxShadow(color: Colors.black, offset: Offset(2, 2), blurRadius: 0),
                    ],
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInfoRow(Icons.play_arrow, 'Bắt đầu', _formatDate(booking.start)),
            const SizedBox(height: 6),
            _buildInfoRow(Icons.stop, 'Kết thúc', _formatDate(booking.end)),
            const SizedBox(height: 6),
            _buildInfoRow(
              Icons.payments,
              'Tổng chi phí',
              _formatCurrency(booking.total, booking.currency),
            ),
            if (cancellable) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: NeuButton(
                  onPressed: isCancelling ? null : () => _cancelBooking(booking),
                  buttonHeight: 40,
                  buttonWidth: 140,
                  borderRadius: BorderRadius.circular(12),
                  borderColor: Colors.black,
                  buttonColor: Colors.red.shade700,
                  shadowColor: Colors.black.withValues(alpha: 0.35),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isCancelling)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      else
                        const Icon(Icons.cancel_schedule_send_outlined, size: 18, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(
                        isCancelling ? 'Đang huỷ...' : 'Huỷ đặt sân',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.black.withValues(alpha: 0.6)),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(String message) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: NeuContainer(
        borderRadius: BorderRadius.circular(20),
        color: const Color(0xFFF5F5F5),
        borderColor: Colors.black,
        borderWidth: 2.5,
        shadowColor: Colors.black.withValues(alpha: 0.2),
        offset: const Offset(4, 4),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.black.withValues(alpha: 0.3), width: 2),
              ),
              child: const Icon(Icons.event_busy, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}
