import 'package:flutter/material.dart';
import 'package:neubrutalism_ui/neubrutalism_ui.dart';

import 'package:khu_lien_hop_tt/models/staff_customer.dart';
import 'package:khu_lien_hop_tt/services/api_service.dart';
import 'package:khu_lien_hop_tt/widgets/sports_gradient_background.dart';
import 'package:khu_lien_hop_tt/widgets/success_dialog.dart';
import 'package:khu_lien_hop_tt/widgets/neu_button.dart';
import 'package:khu_lien_hop_tt/widgets/neo_loading.dart';

class StaffCustomersPage extends StatefulWidget {
  const StaffCustomersPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<StaffCustomersPage> createState() => _StaffCustomersPageState();
}

class _StaffCustomersPageState extends State<StaffCustomersPage> {
  final ApiService _api = ApiService();
  List<StaffCustomer> _customers = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  Future<void> _loadCustomers({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final customers = await _api.staffGetCustomers(limit: 100);
      if (!mounted) return;
      setState(() {
        _customers = customers;
        _loading = false;
        _error = null;
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

  @override
  Widget build(BuildContext context) {
    final body = _buildBody();
    final mediaPadding = MediaQuery.of(context).padding;
    final headerTopPadding = mediaPadding.top + 16;
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
                      'Khách hàng đã đặt sân',
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

    return SportsGradientBackground(
      variant: SportsBackgroundVariant.staff,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Khách hàng đã đặt sân')),
        body: body,
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: NeoLoadingCard(
          label: 'Đang tải khách hàng...',
          width: 260,
        ),
      );
    }
    if (_error != null) {
      return _buildErrorView(_error!);
    }
    if (_customers.isEmpty) {
      return _buildEmptyView();
    }
    return RefreshIndicator(
      onRefresh: () => _loadCustomers(showSpinner: false),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 24,
        ),
        itemCount: _customers.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _buildSearchFilterSection(),
            );
          }
          final customer = _customers[index - 1];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildCustomerCard(customer),
          );
        },
      ),
    );
  }

  Widget _buildSearchFilterSection() {
    final theme = Theme.of(context);
    return NeuContainer(
      borderRadius: BorderRadius.circular(28),
      color: theme.colorScheme.surface,
      borderColor: Colors.black,
      borderWidth: 3,
      offset: const Offset(10, 10),
      shadowColor: Colors.black.withValues(alpha:0.3),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tìm kiếm & bộ lọc',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: InputDecoration(
                hintText: 'Nhập tên, số điện thoại hoặc email...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(color: Colors.black, width: 2.4),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(color: Colors.black, width: 2.4),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide:
                      BorderSide(color: theme.colorScheme.primary, width: 3),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildFilterChip(
                  'Tất cả khách hàng',
                  icon: Icons.all_inclusive,
                  active: true,
                ),
                _buildFilterChip('Khách VIP', icon: Icons.star_rate_rounded),
                _buildFilterChip(
                  'Khách thân thiết',
                  icon: Icons.favorite_outline,
                ),
                _buildFilterChip(
                  'Có ghi chú gần đây',
                  icon: Icons.chat_bubble_outline,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView(String message) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: NeuContainer(
          borderRadius: BorderRadius.circular(24),
          color: theme.colorScheme.surface,
          borderColor: Colors.black,
          borderWidth: 3,
          offset: const Offset(8, 8),
          shadowColor: Colors.black.withValues(alpha:0.25),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 16),
                Text(
                  'Không thể tải danh sách khách hàng',
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                _buildActionButton(
                  label: 'Thử lại',
                  icon: Icons.refresh,
                  onPressed: _loadCustomers,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyView() {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
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
                const Icon(Icons.people_outline, size: 48),
                const SizedBox(height: 16),
                Text(
                  'Chưa có khách hàng nào đặt sân tại cơ sở của bạn',
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                _buildActionButton(
                  label: 'Tải lại',
                  icon: Icons.refresh,
                  onPressed: _loadCustomers,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCustomerCard(StaffCustomer customer) {
    final theme = Theme.of(context);
    final tierColor = _customerTierColor(customer);
    final tierLabel = _customerTierLabel(customer);
    return NeuContainer(
      borderRadius: BorderRadius.circular(24),
      color: theme.colorScheme.surface,
      borderColor: Colors.black,
      borderWidth: 3,
      shadowColor: Colors.black.withValues(alpha:0.25),
      offset: const Offset(8, 8),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: tierColor.withValues(alpha:0.04),
        ),
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
                      Text(
                        customer.displayName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.mail_outline, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              customer.email ?? 'Chưa cập nhật email',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                      if (customer.phone != null &&
                          customer.phone!.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.call_outlined, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                customer.phone!,
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _buildStatusChip(tierLabel, tierColor),
                    const SizedBox(height: 12),
                    _buildActionButton(
                      label: 'Gửi ghi chú',
                      icon: Icons.chat_bubble_outline,
                      onPressed: () => _sendMessage(customer),
                      width: 168,
                      height: 46,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(thickness: 1.2),
            const SizedBox(height: 12),
            _buildInfoRow(
              'Lần đặt gần nhất',
              _formatDate(customer.lastBookingAt),
            ),
            const SizedBox(height: 4),
            _buildInfoRow('Tổng số lần đặt', customer.totalBookings.toString()),
            if (customer.bookings.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Lịch sử đặt sân', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              ...customer.bookings.map(_buildBookingRow),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    );
  }

  Widget _buildBookingRow(StaffCustomerBooking booking) {
    final status = booking.status ?? 'unknown';
    final statusColor = _statusColor(status);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: NeuContainer(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white,
        borderColor: Colors.black,
        borderWidth: 2,
        shadowColor: Colors.black.withValues(alpha:0.15),
        offset: const Offset(4, 4),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: statusColor.withValues(alpha:0.06),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _formatDateTimeRange(booking.start, booking.end),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  _buildStatusChip(_statusLabel(status), statusColor),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Tổng tiền: ${_formatCurrency(booking.total, booking.currency)}',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(
    String label, {
    IconData? icon,
    bool active = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final background = active ? scheme.primaryContainer : Colors.white;
    return NeuContainer(
      borderRadius: BorderRadius.circular(18),
      color: background,
      borderColor: Colors.black,
      borderWidth: 2,
      shadowColor: Colors.black.withValues(alpha:0.2),
      offset: const Offset(4, 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: Colors.black),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required VoidCallback? onPressed,
    IconData? icon,
    double? width,
    double height = 52,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return NeuButton(
      onPressed: onPressed,
      buttonHeight: height,
      buttonWidth: width ?? double.infinity,
      borderRadius: BorderRadius.circular(16),
      borderColor: Colors.black,
      buttonColor: scheme.secondaryContainer,
      shadowColor: Colors.black.withValues(alpha:0.35),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.black, size: 18),
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.white,
        border: Border.all(color: color, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black, offset: Offset(2, 2), blurRadius: 0),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  String _customerTierLabel(StaffCustomer customer) {
    if (customer.totalBookings >= 10) return 'Khách VIP';
    if (customer.totalBookings >= 5) return 'Khách thân thiết';
    if (customer.totalBookings >= 1) return 'Khách mới';
    return 'Tiềm năng';
  }

  Color _customerTierColor(StaffCustomer customer) {
    if (customer.totalBookings >= 10) return const Color(0xFF23C552);
    if (customer.totalBookings >= 5) return const Color(0xFFFFA447);
    if (customer.totalBookings >= 1) return const Color(0xFF1DA1F2);
    return const Color(0xFF9B5DE5);
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'confirmed':
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'pending':
        return Colors.orange;
      default:
        return Colors.blueGrey;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'confirmed':
        return 'Đã xác nhận';
      case 'completed':
        return 'Hoàn thành';
      case 'cancelled':
        return 'Đã hủy';
      case 'pending':
        return 'Chờ xử lý';
      default:
        return status;
    }
  }

  String _formatDate(DateTime? value) {
    if (value == null) return 'Không rõ';
    return '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
  }

  String _formatDateTimeRange(DateTime? start, DateTime? end) {
    if (start == null) return 'Không rõ thời gian';
    final startText =
        '${start.day.toString().padLeft(2, '0')}/${start.month.toString().padLeft(2, '0')}/${start.year} ${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
    if (end == null) return startText;
    final endText =
        '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';
    return '$startText - $endText';
  }

  String _formatCurrency(double amount, String currency) {
    final rounded = amount.toStringAsFixed(0);
    return '$rounded $currency';
  }

  Future<void> _sendMessage(StaffCustomer customer) async {
    final success = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return _SendCustomerMessageSheet(
          customer: customer,
          onSubmit: (subject, message) async {
            await _api.staffSendCustomerMessage(
              customerId: customer.id,
              subject: subject,
              message: message,
            );
          },
        );
      },
    );
    if (success == true) {
      await _showSnack('Đã gửi ghi chú tới khách hàng');
    }
  }
}

class _SendCustomerMessageSheet extends StatefulWidget {
  final StaffCustomer customer;
  final Future<void> Function(String subject, String message) onSubmit;

  const _SendCustomerMessageSheet({
    required this.customer,
    required this.onSubmit,
  });

  @override
  State<_SendCustomerMessageSheet> createState() =>
      _SendCustomerMessageSheetState();
}

class _SendCustomerMessageSheetState extends State<_SendCustomerMessageSheet> {
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: NeuContainer(
            borderRadius: BorderRadius.circular(28),
            color: Theme.of(context).colorScheme.surface,
            borderColor: Colors.black,
            borderWidth: 3,
            offset: const Offset(8, 8),
            shadowColor: Colors.black.withValues(alpha:0.25),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Gửi ghi chú cho ${widget.customer.displayName}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _subjectController,
                    decoration: _brutalistInputDecoration(
                      'Tiêu đề (tùy chọn)',
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _messageController,
                    decoration: _brutalistInputDecoration('Nội dung'),
                    maxLines: 6,
                    minLines: 4,
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  NeuButton(
                    onPressed: _submitting ? null : _submit,
                    buttonHeight: 52,
                    buttonWidth: double.infinity,
                    borderRadius: BorderRadius.circular(18),
                    borderColor: Colors.black,
                    buttonColor: Theme.of(context).colorScheme.primary,
                    shadowColor: Colors.black.withValues(alpha:0.35),
                    child: _submitting
                        ? const NeoLoadingDot(size: 18, fillColor: Colors.white)
                        : const Text(
                            'Gửi',
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
      ),
    );
  }

  InputDecoration _brutalistInputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Colors.black, width: 2.4),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Colors.black, width: 2.4),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Colors.black, width: 3),
      ),
    );
  }

  Future<void> _submit() async {
    final subject = _subjectController.text.trim();
    final message = _messageController.text.trim();
    if (message.isEmpty) {
      setState(() {
        _error = 'Nội dung không được để trống';
      });
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onSubmit(subject, message);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }
}
