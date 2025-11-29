import 'package:flutter/material.dart';
import 'package:neubrutalism_ui/neubrutalism_ui.dart';

import 'package:khu_lien_hop_tt/models/court.dart';
import 'package:khu_lien_hop_tt/models/facility.dart';
import 'package:khu_lien_hop_tt/models/sport.dart';
import 'package:khu_lien_hop_tt/services/user_booking_service.dart';
import 'package:khu_lien_hop_tt/widgets/neu_button.dart';

import 'package:khu_lien_hop_tt/customer/user_booking/booking_confirmation_page.dart';

class BookingSchedulerPage extends StatefulWidget {
  final Sport sport;
  final Facility facility;
  final Court court;

  const BookingSchedulerPage({
    super.key,
    required this.sport,
    required this.facility,
    required this.court,
  });

  @override
  State<BookingSchedulerPage> createState() => _BookingSchedulerPageState();
}

class _BookingSchedulerPageState extends State<BookingSchedulerPage> {
  static const List<Duration> _durationOptions = <Duration>[
    Duration(minutes: 60),
    Duration(minutes: 90),
    Duration(minutes: 120),
    Duration(minutes: 180),
  ];

  final UserBookingService _service = UserBookingService();
  late DateTime _start;
  Duration _duration = const Duration(minutes: 60);
  bool _checking = false;
  bool? _available;
  String? _error;
  Map<String, dynamic>? _quote;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _start = DateTime(now.year, now.month, now.day, now.hour + 1);
  }

  DateTime get _end => _start.add(_duration);

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (picked == null) return;
    setState(() {
      _start = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _start.hour,
        _start.minute,
      );
      _clearQuote();
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_start),
    );
    if (picked == null) return;
    setState(() {
      _start = DateTime(
        _start.year,
        _start.month,
        _start.day,
        picked.hour,
        picked.minute,
      );
      _clearQuote();
    });
  }

  Future<void> _checkAvailabilityAndQuote() async {
    if (_checking) return;
    final now = DateTime.now();
    if (_start.isBefore(now)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng chọn thời gian trong tương lai.'),
        ),
      );
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
      _available = null;
    });
    try {
      final available = await _service.checkAvailability(
        courtId: widget.court.id,
        start: _start,
        end: _end,
      );
      if (!mounted) return;
      if (!available) {
        setState(() {
          _available = false;
          _quote = null;
        });
        return;
      }
      final quote = await _service.quotePrice(
        facilityId: widget.facility.id,
        sportId: widget.sport.id,
        courtId: widget.court.id,
        start: _start,
        end: _end,
      );
      if (!mounted) return;
      setState(() {
        _available = true;
        _quote = quote;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _available = null;
        _quote = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _checking = false;
        });
      }
    }
  }

  Future<void> _goToConfirmation() async {
    if (_quote == null) return;
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BookingConfirmationPage(
          sport: widget.sport,
          facility: widget.facility,
          court: widget.court,
          start: _start,
          end: _end,
          quote: Map<String, dynamic>.from(_quote!),
        ),
      ),
    );
    if (!mounted) return;
    if (result == true) {
      Navigator.of(context).pop(true);
    }
  }

  void _clearQuote() {
    _available = null;
    _quote = null;
    _error = null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Đặt lịch - ${widget.sport.name}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildInfoCard(context),
          const SizedBox(height: 16),
          _buildDateTimeCard(context),
          const SizedBox(height: 16),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8D7DA),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFDC3545), width: 2),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0xFFDC3545),
                      offset: Offset(3, 3),
                      blurRadius: 0,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error, color: Color(0xFFDC3545)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: Color(0xFFDC3545),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          NeuButton(
            buttonHeight: 48,
            buttonWidth: double.infinity,
            borderRadius: BorderRadius.circular(12),
            buttonColor: _checking ? Colors.grey : Theme.of(context).colorScheme.primary,
            onPressed: _checking ? () {} : _checkAvailabilityAndQuote,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.query_stats, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  _checking ? 'Đang kiểm tra...' : 'Kiểm tra & báo giá',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          if (_checking)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_available == false) ...[
            const SizedBox(height: 16),
            _buildAvailabilityBanner(context, available: false),
          ],
          if (_available == true && _quote != null) ...[
            const SizedBox(height: 16),
            _buildAvailabilityBanner(context, available: true),
            const SizedBox(height: 16),
            _buildQuoteCard(context),
            const SizedBox(height: 16),
            NeuButton(
              buttonHeight: 56,
              buttonWidth: double.infinity,
              borderRadius: BorderRadius.circular(12),
              buttonColor: Theme.of(context).colorScheme.primary,
              onPressed: _checking ? () {} : _goToConfirmation,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Text(
                    'Tiếp tục xác nhận',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward, color: Colors.white),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context) {
    final address = _formatAddress(widget.facility.address);
    return NeuContainer(
      color: const Color(0xFFE6F3FF),
      borderColor: Colors.black,
      borderWidth: 3,
      borderRadius: BorderRadius.circular(16),
      shadowColor: Colors.black.withValues(alpha: 0.25),
      offset: const Offset(6, 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.black, width: 2),
                  ),
                  child: const Icon(Icons.sports_tennis, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.facility.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              ],
            ),
            if (address != null) ...[const SizedBox(height: 8), Text(address)],
            const SizedBox(height: 12),
            Text('Sân: ${widget.court.name}'),
            if ((widget.court.code ?? '').isNotEmpty)
              Text('Mã sân: ${widget.court.code}'),
            const SizedBox(height: 12),
            Text('Môn: ${widget.sport.name}'),
          ],
        ),
      ),
    );
  }

  Widget _buildDateTimeCard(BuildContext context) {
    final end = _end;
    return NeuContainer(
      color: const Color(0xFFFFF8DC),
      borderColor: Colors.black,
      borderWidth: 3,
      borderRadius: BorderRadius.circular(16),
      shadowColor: Colors.black.withValues(alpha: 0.25),
      offset: const Offset(6, 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.black, width: 2),
                  ),
                  child: const Icon(Icons.schedule, size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  'Thời gian đặt sân',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildBrutalistButton(
                    context,
                    icon: Icons.event,
                    label: 'Ngày: ${_formatDate(_start)}',
                    onPressed: _pickDate,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildBrutalistButton(
                    context,
                    icon: Icons.access_time,
                    label: 'Giờ: ${_formatTime(_start)}',
                    onPressed: _pickTime,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black, width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black,
                    offset: Offset(3, 3),
                    blurRadius: 0,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Thời lượng',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonHideUnderline(
                    child: DropdownButton<Duration>(
                      value: _duration,
                      isExpanded: true,
                      items: _durationOptions
                          .map(
                            (duration) => DropdownMenuItem<Duration>(
                              value: duration,
                              child: Text(_formatDuration(duration)),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _duration = value;
                          _clearQuote();
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Kết thúc: ${_formatDate(end)} ${_formatTime(end)}',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvailabilityBanner(
    BuildContext context, {
    required bool available,
  }) {
    final bg = available ? const Color(0xFFE8F5E9) : const Color(0xFFF8D7DA);
    final borderColor = available ? const Color(0xFF4CAF50) : const Color(0xFFDC3545);
    final icon = available ? Icons.check_circle : Icons.error;
    final text = available ? 'Khung giờ còn trống' : 'Khung giờ không khả dụng';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 3),
        boxShadow: [
          BoxShadow(
            color: borderColor.withValues(alpha: 0.3),
            offset: const Offset(4, 4),
            blurRadius: 0,
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: borderColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: borderColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuoteCard(BuildContext context) {
    final currency = (_quote!['currency'] ?? 'VND').toString();
    final durationMinutes = _quote!['durationMinutes'] ?? _duration.inMinutes;
    final baseRate = _formatMoney(_quote!['baseRatePerHour'], currency);
    final subtotal = _formatMoney(_quote!['subtotal'], currency);
    final discount = _formatMoney(_quote!['discount'], currency);
    final tax = _formatMoney(_quote!['tax'], currency);
    final total = _formatMoney(_quote!['total'], currency);
    final discountValue = _toDouble(_quote!['discount']) ?? 0;

    String? ruleText;
    final rule = _quote!['ruleApplied'];
    if (rule is Map && rule.isNotEmpty) {
      if (rule['name'] != null) {
        ruleText = rule['name'].toString();
      } else if (rule['label'] != null) {
        ruleText = rule['label'].toString();
      }
    }

    return NeuContainer(
      color: const Color(0xFFE8F5E9),
      borderColor: Colors.black,
      borderWidth: 3,
      borderRadius: BorderRadius.circular(16),
      shadowColor: Colors.black.withValues(alpha: 0.25),
      offset: const Offset(6, 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.black, width: 2),
                  ),
                  child: const Icon(Icons.receipt_long, size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  'Báo giá dự kiến',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildQuoteRow(context, 'Thời lượng', '$durationMinutes phút'),
            _buildQuoteRow(context, 'Đơn giá/giờ', baseRate),
            _buildQuoteRow(context, 'Tạm tính', subtotal),
            if (discountValue > 0)
              _buildQuoteRow(context, 'Giảm giá', discount),
            _buildQuoteRow(context, 'Thuế', tax),
            const SizedBox(height: 12),
            Container(
              height: 2,
              decoration: BoxDecoration(
                color: Colors.black,
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black,
                    offset: Offset(2, 2),
                    blurRadius: 0,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _buildQuoteRow(context, 'Tổng thanh toán', total, emphasized: true),
            if (ruleText != null && ruleText.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.black, width: 2),
                ),
                child: Text(
                  'Áp dụng bảng giá: $ruleText',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQuoteRow(
    BuildContext context,
    String label,
    String value, {
    bool emphasized = false,
  }) {
    final style = emphasized
        ? Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)
        : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: style),
        ],
      ),
    );
  }

  String? _formatAddress(FacilityAddress address) {
    final parts = <String>[
      if ((address.line1 ?? '').trim().isNotEmpty) address.line1!.trim(),
      if ((address.ward ?? '').trim().isNotEmpty) address.ward!.trim(),
      if ((address.district ?? '').trim().isNotEmpty) address.district!.trim(),
      if ((address.city ?? '').trim().isNotEmpty) address.city!.trim(),
      if ((address.province ?? '').trim().isNotEmpty) address.province!.trim(),
      if ((address.country ?? '').trim().isNotEmpty) address.country!.trim(),
    ];
    if (parts.isEmpty) return null;
    return parts.join(', ');
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    return '$day/$month/${local.year}';
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    if (minutes == 0) {
      return '$hours giờ';
    }
    return '$hours giờ ${minutes.toString().padLeft(2, '0')} phút';
  }

  String _formatMoney(dynamic value, String currency) {
    final amount = _toDouble(value);
    if (amount == null) return '--';
    final hasFraction = amount.truncateToDouble() != amount;
    final digits = hasFraction
        ? amount.toStringAsFixed(2)
        : amount.toStringAsFixed(0);
    final parts = digits.split('.');
    final whole = _groupDigits(parts[0]);
    final decimal = parts.length > 1 ? '.${parts[1]}' : '';
    return '$whole$decimal $currency';
  }

  double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.replaceAll(',', '.'));
    return null;
  }

  String _groupDigits(String raw) {
    final negative = raw.startsWith('-');
    final digits = negative ? raw.substring(1) : raw;
    final buffer = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      final char = digits[digits.length - 1 - i];
      if (i != 0 && i % 3 == 0) buffer.write('.');
      buffer.write(char);
    }
    final grouped = buffer.toString().split('').reversed.join();
    return negative ? '-$grouped' : grouped;
  }

  Widget _buildBrutalistButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black, width: 2),
          boxShadow: const [
            BoxShadow(
              color: Colors.black,
              offset: Offset(3, 3),
              blurRadius: 0,
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
