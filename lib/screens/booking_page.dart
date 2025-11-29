import 'package:flutter/material.dart';
import '../models/court.dart';
import '../services/api_service.dart';

class BookingPage extends StatefulWidget {
  final Court court;
  const BookingPage({super.key, required this.court});

  @override
  State<BookingPage> createState() => _BookingPageState();
}

class _BookingPageState extends State<BookingPage> {
  final _api = ApiService();
  DateTime _start = DateTime.now().add(const Duration(hours: 1));
  DateTime _end = DateTime.now().add(const Duration(hours: 2));
  Map<String, dynamic>? _quote;
  bool _loading = false;

  Future<void> _pickDateTime({required bool isStart}) async {
    final base = isStart ? _start : _end;
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );
    if (!mounted || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (!mounted || time == null) return;
    final chosen = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() {
      if (isStart) {
        _start = chosen;
        if (_end.isBefore(_start)) _end = _start.add(const Duration(hours: 1));
      } else {
        _end = chosen;
        if (_end.isBefore(_start)) _end = _start.add(const Duration(hours: 1));
      }
      _quote = null; // reset quote when time changes
    });
  }

  Future<void> _checkAndQuote() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _loading = true;
    });
    try {
      final available = await _api.checkAvailability(
        widget.court.id,
        _start,
        _end,
      );
      if (!available) {
        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Khung giờ đã có người đặt hoặc bảo trì'),
          ),
        );
        return;
      }
      // In real app, choose customerId from auth user. For demo, use a placeholder or require input.
      final quote = await _api.quotePrice(
        facilityId: widget.court.facilityId,
        sportId: widget.court.sportId,
        courtId: widget.court.id,
        start: _start,
        end: _end,
      );
      if (!mounted) return;
      setState(() {
        _quote = quote;
      });
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _createBooking() async {
    if (_quote == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Hãy báo giá trước')));
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _loading = true;
    });
    try {
      const demoCustomerId = '000000000000000000000000';
      final created = await _api.createBooking(
        customerId: demoCustomerId,
        facilityId: widget.court.facilityId,
        courtId: widget.court.id,
        sportId: widget.court.sportId,
        start: _start,
        end: _end,
        currency: (_quote!['currency'] ?? 'VND').toString(),
        pricingSnapshot: _quote!,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Đặt sân thành công: ${created['_id']}')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _pickDateTime(isStart: true),
                child: Text('Bắt đầu: ${_start.toLocal()}'.split('.').first),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () => _pickDateTime(isStart: false),
                child: Text('Kết thúc: ${_end.toLocal()}'.split('.').first),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _loading ? null : _checkAndQuote,
          icon: const Icon(Icons.calculate),
          label: const Text('Tính giá & Kiểm tra trống sân'),
        ),
        const SizedBox(height: 12),
        if (_quote != null) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Giá (/${(_quote!['durationMinutes'] ?? 0)} phút)'),
                  const SizedBox(height: 4),
                  Text('Đơn giá/h: ${_quote!['baseRatePerHour']}'),
                  Text('Tạm tính: ${_quote!['subtotal']}'),
                  Text('Giảm giá: ${_quote!['discount']}'),
                  Text('Thuế: ${_quote!['tax']}'),
                  Text(
                    'Tổng: ${_quote!['total']} ${_quote!['currency'] ?? ''}',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _loading ? null : _createBooking,
            icon: const Icon(Icons.check_circle),
            label: const Text('Tạo booking'),
          ),
        ],
      ],
    );
  }
}
