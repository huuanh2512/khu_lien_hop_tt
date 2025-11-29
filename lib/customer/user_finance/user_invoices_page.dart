import 'package:flutter/material.dart';
import 'package:neubrutalism_ui/neubrutalism_ui.dart';

import 'package:khu_lien_hop_tt/models/user_invoice.dart';
import 'package:khu_lien_hop_tt/widgets/neu_button.dart';
import 'package:khu_lien_hop_tt/models/user_payment.dart';
import 'package:khu_lien_hop_tt/services/user_billing_service.dart';
import 'package:khu_lien_hop_tt/widgets/success_dialog.dart';

class UserInvoicesPage extends StatefulWidget {
  const UserInvoicesPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<UserInvoicesPage> createState() => _UserInvoicesPageState();
}

class _UserInvoicesPageState extends State<UserInvoicesPage> {
  final UserBillingService _billing = UserBillingService();
  List<UserInvoice> _invoices = const [];
  Map<String, List<UserPayment>> _paymentsByInvoice = const {};
  final Set<String> _payingInvoices = <String>{};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final invoices = await _billing.fetchInvoices();
      final payments = await _billing.fetchPayments();
      final mapped = <String, List<UserPayment>>{};
      for (final payment in payments) {
        mapped
            .putIfAbsent(payment.invoiceId, () => <UserPayment>[])
            .add(payment);
      }
      if (!mounted) return;
      setState(() {
        _invoices = invoices;
        _paymentsByInvoice = mapped;
        _payingInvoices.clear();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
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
                      'Hoá đơn & Thanh toán',
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
        title: const Text('Hoá đơn & Thanh toán'),
      ),
      body: body,
    );
  }

  Widget _buildBody() {
    final mediaPadding = MediaQuery.of(context).padding;
    final listBottomPadding = mediaPadding.bottom + 24;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: NeuContainer(
            borderRadius: BorderRadius.circular(24),
            color: Theme.of(context).colorScheme.surface,
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
                    'Không thể tải dữ liệu hoá đơn',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  NeuButton(
                    onPressed: _loadData,
                    buttonHeight: 48,
                    buttonWidth: 140,
                    borderRadius: BorderRadius.circular(16),
                    borderColor: Colors.black,
                    buttonColor: Theme.of(context).colorScheme.primary,
                    shadowColor: Colors.black.withValues(alpha:0.35),
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
    }
    if (_invoices.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: NeuContainer(
            borderRadius: BorderRadius.circular(24),
            color: Theme.of(context).colorScheme.surface,
            borderColor: Colors.black,
            borderWidth: 3,
            shadowColor: Colors.black.withValues(alpha:0.25),
            offset: const Offset(8, 8),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.receipt_long, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'Bạn chưa có hoá đơn nào.',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Những lần đặt sân hoàn tất sẽ xuất hiện tại đây.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 16, 16, listBottomPadding),
        itemCount: _invoices.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final invoice = _invoices[index];
          final payments = _paymentsByInvoice[invoice.id] ?? const [];
          final statusNormalized = invoice.status.toLowerCase();
          Color cardColor;
          switch (statusNormalized) {
            case 'paid':
            case 'succeeded':
              cardColor = const Color(0xFFD4EDDA);
              break;
            case 'failed':
            case 'overdue':
              cardColor = const Color(0xFFF8D7DA);
              break;
            default:
              cardColor = const Color(0xFFFFF3CD);
          }
          return NeuContainer(
            borderRadius: BorderRadius.circular(20),
            color: cardColor,
            borderColor: Colors.black,
            borderWidth: 3,
            shadowColor: Colors.black.withValues(alpha:0.25),
            offset: const Offset(5, 5),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => _openInvoiceDetail(invoice),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _formatMoney(invoice.amount, invoice.currency),
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        _buildStatusChip(invoice.status),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.calendar_today, size: 16, color: Colors.black.withValues(alpha:0.6)),
                        const SizedBox(width: 6),
                        Text(
                          'Ngày lập: ${_formatDate(invoice.issuedAt)}',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    if (invoice.dueAt != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.event, size: 16, color: Colors.black.withValues(alpha:0.6)),
                          const SizedBox(width: 6),
                          Text(
                            'Đến hạn: ${_formatDate(invoice.dueAt!)}',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ],
                    if ((invoice.facilityName ?? '').isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.location_on, size: 16, color: Colors.black.withValues(alpha:0.6)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Địa điểm: ${invoice.facilityName}',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if ((invoice.courtName ?? '').isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.sports_tennis, size: 16, color: Colors.black.withValues(alpha:0.6)),
                          const SizedBox(width: 6),
                          Text(
                            'Sân: ${invoice.courtName}',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ],
                    if (invoice.description != null &&
                        invoice.description!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        invoice.description!,
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ],
                    if (payments.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.payment, size: 16, color: Colors.black.withValues(alpha:0.6)),
                          const SizedBox(width: 6),
                          Text(
                            'Thanh toán: ${payments.length} lần',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    final normalized = status.toLowerCase();
    Color borderColor;
    String label;
    switch (normalized) {
      case 'paid':
      case 'succeeded':
        borderColor = Colors.green.shade700;
        label = 'Đã thanh toán';
        break;
      case 'failed':
      case 'overdue':
        borderColor = Colors.red.shade700;
        label = normalized == 'failed' ? 'Thanh toán thất bại' : 'Quá hạn';
        break;
      case 'pending':
      default:
        borderColor = Colors.orange.shade700;
        label = 'Chờ thanh toán';
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black, offset: Offset(2, 2), blurRadius: 0),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(
          color: borderColor,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  void _openInvoiceDetail(UserInvoice invoice) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (context, controller) {
            return StatefulBuilder(
              builder: (context, setSheetState) {
                final refreshedInvoice = _invoices.firstWhere(
                  (item) => item.id == invoice.id,
                  orElse: () => invoice,
                );
                final payments =
                    _paymentsByInvoice[refreshedInvoice.id] ?? const [];
                final isPaying = _payingInvoices.contains(refreshedInvoice.id);
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.outlineVariant,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      Text(
                        'Chi tiết hoá đơn',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      _buildInvoiceSummary(refreshedInvoice),
                      const SizedBox(height: 16),
                      Text(
                        'Lịch sử thanh toán',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: payments.isEmpty
                            ? const Center(
                                child: Text(
                                  'Chưa có thanh toán nào cho hoá đơn này.',
                                ),
                              )
                            : ListView.separated(
                                controller: controller,
                                itemBuilder: (context, index) {
                                  final payment = payments[index];
                                  return ListTile(
                                    leading: Icon(
                                      payment.status == 'succeeded'
                                          ? Icons.check_circle
                                          : payment.status == 'failed'
                                          ? Icons.error
                                          : Icons.hourglass_top,
                                      color: _paymentStatusColor(
                                        payment.status,
                                      ),
                                    ),
                                    title: Text(
                                      _formatMoney(
                                        payment.amount,
                                        payment.currency,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Thời gian: ${_formatDateTime(payment.processedAt)}',
                                        ),
                                        if ((payment.method ?? '').isNotEmpty)
                                          Text(
                                            'Phương thức: ${payment.method}',
                                          ),
                                        if ((payment.reference ?? '')
                                            .isNotEmpty)
                                          Text(
                                            'Mã tham chiếu: ${payment.reference}',
                                          ),
                                      ],
                                    ),
                                    trailing: _buildPaymentStatusChip(
                                      payment.status,
                                    ),
                                  );
                                },
                                separatorBuilder: (_, __) => const Divider(),
                                itemCount: payments.length,
                              ),
                      ),
                      const SizedBox(height: 12),
                      if (refreshedInvoice.status.toLowerCase() != 'paid')
                        NeuButton(
                          onPressed: isPaying
                              ? null
                              : () => _payInvoice(
                                  refreshedInvoice,
                                  setSheetState: setSheetState,
                                ),
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
                              if (isPaying)
                                const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              else
                                const Icon(Icons.payment, color: Colors.white),
                              const SizedBox(width: 12),
                              Text(
                                isPaying
                                    ? 'Đang thanh toán...'
                                    : 'Thanh toán ngay',
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
              },
            );
          },
        );
      },
    );
  }

  Widget _buildInvoiceSummary(UserInvoice invoice) {
    return NeuContainer(
      borderRadius: BorderRadius.circular(20),
      color: const Color(0xFFF0F8FF),
      borderColor: Colors.black,
      borderWidth: 2.5,
      shadowColor: Colors.black.withValues(alpha:0.25),
      offset: const Offset(5, 5),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Số tiền: ${_formatMoney(invoice.amount, invoice.currency)}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text('Ngày lập: ${_formatDateTime(invoice.issuedAt)}'),
            if (invoice.dueAt != null)
              Text('Hạn thanh toán: ${_formatDateTime(invoice.dueAt!)}'),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Trạng thái: '),
                _buildStatusChip(invoice.status),
              ],
            ),
            if ((invoice.facilityName ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Cơ sở: ${invoice.facilityName}'),
              ),
            if ((invoice.courtName ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Sân: ${invoice.courtName}'),
              ),
            if ((invoice.description ?? '').isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(invoice.description!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentStatusChip(String status) {
    final normalized = status.toLowerCase();
    String label;
    Color borderColor;
    switch (normalized) {
      case 'succeeded':
        label = 'Thành công';
        borderColor = Colors.green.shade700;
        break;
      case 'failed':
        label = 'Thất bại';
        borderColor = Colors.red.shade700;
        break;
      default:
        label = 'Đang xử lý';
        borderColor = Colors.orange.shade700;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black, offset: Offset(2, 2), blurRadius: 0),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(
          color: borderColor,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Future<void> _payInvoice(
    UserInvoice invoice, {
    required void Function(void Function()) setSheetState,
  }) async {
    if (_payingInvoices.contains(invoice.id)) return;

    setState(() => _payingInvoices.add(invoice.id));
    setSheetState(() {});

    try {
      final result = await _billing.payInvoice(invoice.id);
      if (!mounted) return;

      setState(() {
        final payments = List<UserPayment>.from(
          _paymentsByInvoice[invoice.id] ?? const [],
        );
        payments.insert(0, result.payment);
        _paymentsByInvoice = {..._paymentsByInvoice, invoice.id: payments};

        final idx = _invoices.indexWhere((item) => item.id == invoice.id);
        if (idx != -1) {
          final updated = _invoices[idx].copyWith(status: result.status);
          final next = List<UserInvoice>.from(_invoices);
          next[idx] = updated;
          _invoices = next;
        }
      });

      setSheetState(() {});

      final currency = result.payment.currency;
      final amountText = _formatMoney(result.payment.amount, currency);
      final message = result.status.toLowerCase() == 'paid'
          ? 'Thanh toán thành công'
          : 'Đã ghi nhận thanh toán $amountText';
      await _showSnack(message);
    } catch (error) {
      if (!mounted) return;
      setSheetState(() {});
      await _showSnack(
        'Thanh toán thất bại: ${_friendlyError(error)}',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _payingInvoices.remove(invoice.id));
      }
      setSheetState(() {});
    }
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    const prefix = 'Exception: ';
    if (text.startsWith(prefix)) return text.substring(prefix.length);
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

  String _formatMoney(double value, String currency) {
    final hasFraction = value.truncateToDouble() != value;
    final digits = hasFraction
        ? value.toStringAsFixed(2)
        : value.toStringAsFixed(0);
    final parts = digits.split('.');
    final grouped = _groupDigits(parts[0]);
    final decimal = parts.length > 1 ? '.${parts[1]}' : '';
    return '$grouped$decimal $currency';
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

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    return '$day/$month/${local.year}';
  }

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/${local.year} $hour:$minute';
  }

  Color _paymentStatusColor(String status) {
    final normalized = status.toLowerCase();
    if (normalized == 'succeeded') {
      return Theme.of(context).colorScheme.primary;
    }
    if (normalized == 'failed') {
      return Theme.of(context).colorScheme.error;
    }
    return Theme.of(context).colorScheme.outline;
  }
}
