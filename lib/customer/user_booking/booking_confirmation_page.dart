import 'package:flutter/material.dart';
import 'package:neubrutalism_ui/neubrutalism_ui.dart';

import 'package:khu_lien_hop_tt/models/court.dart';
import 'package:khu_lien_hop_tt/widgets/neu_button.dart';
import 'package:khu_lien_hop_tt/models/facility.dart';
import 'package:khu_lien_hop_tt/models/sport.dart';
import 'package:khu_lien_hop_tt/services/auth_service.dart';
import 'package:khu_lien_hop_tt/services/user_booking_service.dart';
import 'package:khu_lien_hop_tt/widgets/success_dialog.dart';

class BookingConfirmationPage extends StatefulWidget {
  final Sport sport;
  final Facility facility;
  final Court court;
  final DateTime start;
  final DateTime end;
  final Map<String, dynamic> quote;

  const BookingConfirmationPage({
    super.key,
    required this.sport,
    required this.facility,
    required this.court,
    required this.start,
    required this.end,
    required this.quote,
  });

  @override
  State<BookingConfirmationPage> createState() =>
      _BookingConfirmationPageState();
}

class _BookingConfirmationPageState extends State<BookingConfirmationPage>
    with SingleTickerProviderStateMixin {
  static final RegExp _objectIdPattern = RegExp(r'^[0-9a-fA-F]{24}$');
  final UserBookingService _service = UserBookingService();
  bool _submitting = false;
  String? _error;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
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

  Future<void> _confirmBooking() async {
    if (_submitting) return;
    var user = AuthService.instance.currentUser;
    if (user == null) {
      await _showSnack('Vui lòng đăng nhập để đặt sân.', isError: true);
      return;
    }

    if (!_isValidObjectId(user.id)) {
      try {
        user = await AuthService.instance.reloadCurrentUser();
      } catch (_) {
        await _showSnack(
          'Không thể đồng bộ tài khoản. Vui lòng đăng xuất và đăng nhập lại.',
          isError: true,
        );
        return;
      }
      if (!_isValidObjectId(user.id)) {
        await _showSnack(
          'Tài khoản chưa được đồng bộ với hệ thống. Vui lòng đăng xuất và đăng nhập lại.',
          isError: true,
        );
        return;
      }
    }

    final customerId = user.id;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await _service.createBooking(
        customerId: customerId,
        facilityId: widget.facility.id,
        courtId: widget.court.id,
        sportId: widget.sport.id,
        start: widget.start,
        end: widget.end,
        currency: (widget.quote['currency'] ?? 'VND').toString(),
        pricingSnapshot: widget.quote,
      );
      if (!mounted) return;
      setState(() => _submitting = false);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Xác nhận đặt sân')),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildSummaryCard(context),
              const SizedBox(height: 16),
              _buildPricingCard(context),
              const SizedBox(height: 24),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: NeuContainer(
                    borderRadius: BorderRadius.circular(16),
                    color: theme.colorScheme.errorContainer,
                    borderColor: Colors.black,
                    borderWidth: 2.5,
                    shadowColor: Colors.black.withValues(alpha: 0.25),
                    offset: const Offset(4, 4),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: theme.colorScheme.error),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: theme.colorScheme.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              NeuButton(
                onPressed: _submitting ? null : _confirmBooking,
                buttonHeight: 56,
                buttonWidth: double.infinity,
                borderRadius: BorderRadius.circular(16),
                borderColor: Colors.black,
                buttonColor: theme.colorScheme.primary,
                shadowColor: Colors.black.withValues(alpha: 0.35),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_submitting)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    else
                      const Icon(Icons.check_circle, color: Colors.white),
                    const SizedBox(width: 12),
                    Text(
                      _submitting ? 'Đang xử lý...' : 'Xác nhận đặt sân',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              NeuButton(
                onPressed: _submitting
                    ? null
                    : () => Navigator.of(context).maybePop(),
                buttonHeight: 48,
                buttonWidth: double.infinity,
                borderRadius: BorderRadius.circular(16),
                borderColor: Colors.black,
                buttonColor: Colors.white,
                shadowColor: Colors.black.withValues(alpha: 0.25),
                child: const Text(
                  'Quay lại',
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context) {
    final theme = Theme.of(context);
    final address = _formatAddress(widget.facility.address);
    final duration = widget.end.difference(widget.start);
    return NeuContainer(
      borderRadius: BorderRadius.circular(24),
      color: const Color(0xFFE6F3FF),
      borderColor: Colors.black,
      borderWidth: 3,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      offset: const Offset(6, 6),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.colorScheme.primary, width: 2),
                  ),
                  child: Icon(Icons.stadium, color: theme.colorScheme.primary, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.facility.name,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (address != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          address,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInfoSection(Icons.sports_tennis, 'Sân', widget.court.name),
            if ((widget.court.code ?? '').isNotEmpty)
              _buildInfoSection(Icons.qr_code, 'Mã sân', widget.court.code!),
            _buildInfoSection(Icons.sports_handball, 'Môn', widget.sport.name),
            _buildInfoSection(Icons.play_arrow, 'Bắt đầu', _formatDateTime(widget.start)),
            _buildInfoSection(Icons.stop, 'Kết thúc', _formatDateTime(widget.end)),
            _buildInfoSection(Icons.timer, 'Thời lượng', _formatDuration(duration)),
          ],
        ),
      ),
    );
  }

  Widget _buildPricingCard(BuildContext context) {
    final theme = Theme.of(context);
    final currency = (widget.quote['currency'] ?? 'VND').toString();
    final durationMinutes =
        widget.quote['durationMinutes'] ??
        widget.end.difference(widget.start).inMinutes;
    final baseRate = _formatMoney(widget.quote['baseRatePerHour'], currency);
    final subtotal = _formatMoney(widget.quote['subtotal'], currency);
    final discount = _formatMoney(widget.quote['discount'], currency);
    final discountValue = _toDouble(widget.quote['discount']) ?? 0;
    final tax = _formatMoney(widget.quote['tax'], currency);
    final total = _formatMoney(widget.quote['total'], currency);

    String? ruleText;
    final rule = widget.quote['ruleApplied'];
    if (rule is Map && rule.isNotEmpty) {
      if (rule['name'] != null) {
        ruleText = rule['name'].toString();
      } else if (rule['label'] != null) {
        ruleText = rule['label'].toString();
      }
    }

    return NeuContainer(
      borderRadius: BorderRadius.circular(24),
      color: const Color(0xFFFFF8DC),
      borderColor: Colors.black,
      borderWidth: 3,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      offset: const Offset(6, 6),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade700, width: 2),
                  ),
                  child: Icon(Icons.payments, color: Colors.orange.shade700, size: 24),
                ),
                const SizedBox(width: 12),
                Text(
                  'Chi phí dự kiến',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildSummaryRow('Thời lượng', '$durationMinutes phút'),
            _buildSummaryRow('Đơn giá/giờ', baseRate),
            _buildSummaryRow('Tạm tính', subtotal),
            if (discountValue > 0) _buildSummaryRow('Giảm giá', discount),
            _buildSummaryRow('Thuế', tax),
            const Divider(height: 24, thickness: 2, color: Colors.black),
            _buildSummaryRow('Tổng thanh toán', total, emphasized: true),
            if (ruleText != null && ruleText.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black, width: 2),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.local_offer, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Áp dụng bảng giá: $ruleText',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoSection(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.black.withValues(alpha: 0.6)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text(value, textAlign: TextAlign.right, style: style),
          ),
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

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/${local.year} $hour:$minute';
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

  bool _isValidObjectId(String? value) {
    if (value == null) return false;
    final trimmed = value.trim();
    if (trimmed.length != 24) return false;
    return _objectIdPattern.hasMatch(trimmed);
  }
}
