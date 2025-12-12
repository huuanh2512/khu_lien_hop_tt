import 'package:flutter/material.dart';
import 'package:neubrutalism_ui/neubrutalism_ui.dart';

import 'package:khu_lien_hop_tt/models/staff_invoice.dart';
import 'package:khu_lien_hop_tt/services/api_service.dart';
import 'package:khu_lien_hop_tt/widgets/sports_gradient_background.dart';
import 'package:khu_lien_hop_tt/widgets/neu_button.dart';
import 'package:khu_lien_hop_tt/widgets/neo_loading.dart';
import 'package:khu_lien_hop_tt/widgets/success_dialog.dart';

const Map<String, String> _invoiceStatusLabels = {
  'all': 'Tất cả',
  'unpaid': 'Chưa thanh toán',
  'paid': 'Đã thanh toán',
  'refunded': 'Đã hoàn tiền',
  'void': 'Đã huỷ',
};

const Map<String, String> _paymentFilters = {
  'all': 'Tất cả phương thức',
  'cash': 'Tiền mặt',
  'bank_transfer': 'Chuyển khoản',
  'e_wallet': 'Ví điện tử',
};

enum _DateQuickFilter { all, today, last7Days, thisMonth, custom }

class StaffInvoicesPage extends StatefulWidget {
  const StaffInvoicesPage({
    super.key,
    this.embedded = false,
    this.initialStatusFilter,
  });

  final bool embedded;
  final String? initialStatusFilter;

  @override
  State<StaffInvoicesPage> createState() => _StaffInvoicesPageState();
}

class _StaffInvoicesPageState extends State<StaffInvoicesPage> {
  final ApiService _api = ApiService();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final Set<String> _busyInvoices = <String>{};

  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  String _statusFilter = 'all';
  String _paymentFilter = 'all';
  _DateQuickFilter _quickFilter = _DateQuickFilter.thisMonth;
  DateTime? _from;
  DateTime? _to;
  String _searchQuery = '';
  StaffInvoiceSummary _summary = const StaffInvoiceSummary();
  List<StaffInvoice> _invoices = const [];
  bool _filtersExpanded = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialStatusFilter != null) {
      _statusFilter = widget.initialStatusFilter!;
    }
    _applyQuickFilter(_quickFilter, triggerLoad: false);
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _load({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() => _refreshing = true);
    }
    try {
      final response = await _api.staffGetInvoices(
        status: _statusFilter == 'all' ? null : _statusFilter,
        from: _from,
        to: _to,
        limit: 200,
      );
      if (!mounted) return;
      setState(() {
        _summary = response.summary;
        _invoices = response.invoices;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  void _applyQuickFilter(_DateQuickFilter filter, {bool triggerLoad = true}) {
    final now = DateTime.now();
    DateTime? from;
    DateTime? to;
    switch (filter) {
      case _DateQuickFilter.today:
        from = _startOfDay(now);
        to = _startOfDay(now);
        break;
      case _DateQuickFilter.last7Days:
        to = _startOfDay(now);
        from = _startOfDay(now.subtract(const Duration(days: 6)));
        break;
      case _DateQuickFilter.thisMonth:
        final start = DateTime(now.year, now.month, 1);
        final end = DateTime(now.year, now.month + 1, 0);
        from = _startOfDay(start);
        to = _startOfDay(end);
        break;
      case _DateQuickFilter.all:
        from = null;
        to = null;
        break;
      case _DateQuickFilter.custom:
        from = _from;
        to = _to;
        break;
    }
    setState(() {
      _quickFilter = filter;
      _from = from;
      _to = to;
    });
    if (triggerLoad) _load();
  }

  DateTime _startOfDay(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final initialRange = _from != null && _to != null
        ? DateTimeRange(start: _from!, end: _to!)
        : DateTimeRange(start: now.subtract(const Duration(days: 6)), end: now);
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: initialRange,
    );
    if (range == null) return;
    setState(() {
      _from = _startOfDay(range.start);
      _to = _startOfDay(range.end);
      _quickFilter = _DateQuickFilter.custom;
    });
    _load();
  }

  void _clearDateRange() {
    if (_from == null && _to == null) return;
    setState(() {
      _from = null;
      _to = null;
      _quickFilter = _DateQuickFilter.all;
    });
    _load();
  }

  List<StaffInvoice> get _filteredInvoices {
    Iterable<StaffInvoice> data = _invoices;

    if (_paymentFilter != 'all') {
      data = data.where(
        (invoice) => _methodKeyForInvoice(invoice) == _paymentFilter,
      );
    }

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      data = data.where((invoice) {
        final customer = invoice.customer;
        final fields = [
          invoice.id,
          invoice.bookingId,
          customer?.name ?? '',
          customer?.phone ?? '',
          customer?.email ?? '',
        ];
        return fields.any((value) => value.toLowerCase().contains(query));
      });
    }

    return data.toList(growable: false);
  }

  String _methodKeyForInvoice(StaffInvoice invoice) {
    final latestPayment = invoice.payments.isNotEmpty
        ? invoice.payments.last
        : null;
    final method = latestPayment?.method.toLowerCase() ?? '';
    if (method.contains('cash') || method.contains('tiền')) return 'cash';
    if (method.contains('bank') ||
        method.contains('transfer') ||
        method.contains('chuyển')) {
      return 'bank_transfer';
    }
    if (method.contains('momo') ||
        method.contains('zalo') ||
        method.contains('wallet') ||
        method.contains('ví')) {
      return 'e_wallet';
    }
    return 'other';
  }

  String _paymentLabelForInvoice(StaffInvoice invoice) {
    if (invoice.payments.isEmpty) {
      return invoice.outstanding > 0 ? 'Chưa thanh toán' : 'Không xác định';
    }
    final key = _methodKeyForInvoice(invoice);
    switch (key) {
      case 'cash':
        return 'Tiền mặt';
      case 'bank_transfer':
        return 'Chuyển khoản';
      case 'e_wallet':
        return 'Ví điện tử';
      default:
        return invoice.payments.last.method;
    }
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    const prefix = 'Exception: ';
    return text.startsWith(prefix) ? text.substring(prefix.length) : text;
  }

  Future<bool> _performInvoiceAction(
    String invoiceId,
    Future<void> Function() action, {
    String? successMessage,
  }) async {
    setState(() => _busyInvoices.add(invoiceId));
    var succeeded = false;
    try {
      await action();
      succeeded = true;
      if (mounted && successMessage != null && successMessage.isNotEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } catch (e) {
      if (mounted) {
        final theme = Theme.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_friendlyError(e)),
            backgroundColor: theme.colorScheme.error,
          ),
        );
      }
      succeeded = false;
    } finally {
      if (mounted) {
        setState(() => _busyInvoices.remove(invoiceId));
      }
    }
    return succeeded;
  }

  Future<void> _sendReminder(StaffInvoice invoice) async {
    if (invoice.outstanding <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hoá đơn đã được thanh toán đầy đủ.')),
      );
      return;
    }

    final formatted = _formatCurrency(invoice.outstanding);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nhắc nhở khách thanh toán'),
        content: Text(
          'Gửi nhắc nhở khách hàng thanh toán số tiền còn lại $formatted cho hoá đơn ${invoice.id}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Gửi nhắc nhở'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    await _performInvoiceAction(invoice.id, () async {
      await _api.staffSendInvoiceReminder(invoice.id);
      await _load(showSpinner: false);
    }, successMessage: 'Đã gửi nhắc nhở tới khách hàng.');
  }

  Future<void> _markInvoicePaid(StaffInvoice invoice) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Đánh dấu đã thanh toán'),
        content: Text(
          'Xác nhận cập nhật hoá đơn ${invoice.id} sang trạng thái đã thanh toán?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final success = await _performInvoiceAction(invoice.id, () async {
      final updated = await _api.staffUpdateInvoiceStatus(
        invoice.id,
        status: 'paid',
        paid: true,
      );
      if (!mounted) return;
      _applyInvoiceUpdate(updated);
    });

    if (!mounted || !success) return;

    await showSuccessDialog(
      context,
      message: 'Đã cập nhật trạng thái hoá đơn thành công.',
    );
    await _load(showSpinner: false);
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '—';
    final local = value.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    final y = local.year.toString().padLeft(4, '0');
    return '$d/$m/$y';
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) return '—';
    final local = value.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    final y = local.year.toString().padLeft(4, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$d/$m/$y $hh:$mm';
  }

  String _formatCurrency(double value) {
    final negative = value < 0;
    final digits = value.abs().round().toString();
    final buffer = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i != 0 && (digits.length - i) % 3 == 0) {
        buffer.write('.');
      }
      buffer.write(digits[i]);
    }
    final text = buffer.isEmpty ? '0' : buffer.toString();
    return '${negative ? '-' : ''}$text ₫';
  }

  StaffInvoiceSummary _recalculateSummaryFromInvoices(
    List<StaffInvoice> invoices,
  ) {
    if (invoices.isEmpty) {
      return const StaffInvoiceSummary();
    }
    double totalInvoiced = 0;
    double totalPaid = 0;
    double totalOutstanding = 0;
    for (final invoice in invoices) {
      totalInvoiced += invoice.amount;
      totalPaid += invoice.totalPaid;
      totalOutstanding += invoice.outstanding;
    }
    return StaffInvoiceSummary(
      invoiceCount: invoices.length,
      totalInvoiced: totalInvoiced,
      totalPaid: totalPaid,
      totalOutstanding: totalOutstanding,
      totalRevenue: totalPaid,
    );
  }

  void _applyInvoiceUpdate(StaffInvoice updated) {
    final current = List<StaffInvoice>.from(_invoices);
    final index = current.indexWhere((item) => item.id == updated.id);
    if (index >= 0) {
      current[index] = updated;
    } else {
      current.insert(0, updated);
    }
    setState(() {
      _invoices = current;
      _summary = _recalculateSummaryFromInvoices(current);
    });
  }

  Color _statusColor(String status, ThemeData theme) {
    switch (status) {
      case 'paid':
        return theme.colorScheme.primary;
      case 'unpaid':
        return Colors.amber.shade700;
      case 'refunded':
        return theme.colorScheme.tertiary;
      case 'void':
        return theme.colorScheme.outline;
      default:
        return theme.colorScheme.primary;
    }
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      title: const Text('Quản lý hoá đơn'),
      centerTitle: false,
      elevation: 0,
      flexibleSpace: const SportsGradientBackground(
        variant: SportsBackgroundVariant.staff,
        child: SizedBox.expand(),
      ),
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      actions: [
        IconButton(
          tooltip: 'Tìm kiếm',
          icon: const Icon(Icons.search_rounded),
          onPressed: () =>
              FocusScope.of(context).requestFocus(_searchFocusNode),
        ),
        IconButton(
          tooltip: 'Làm mới',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loading ? null : () => _load(),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(24),
        child: Container(
          height: 24,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showProgress = _loading && !_refreshing;
    final filters = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showProgress) const LinearProgressIndicator(minHeight: 2),
        _buildFilterBar(),
        _buildSearchField(),
      ],
    );

    final content = Expanded(
      child: RefreshIndicator(
        onRefresh: () => _load(showSpinner: false),
        child: _buildContent(),
      ),
    );

    if (widget.embedded) {
      return SafeArea(top: false, child: Column(children: [filters, content]));
    }

    return SportsGradientBackground(
      variant: SportsBackgroundVariant.staff,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: _buildAppBar(context),
        body: Column(children: [filters, content]),
      ),
    );
  }

  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: NeuContainer(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFFFFF8DC),
        borderColor: Colors.black,
        borderWidth: 3,
        shadowColor: Colors.black.withValues(alpha: 0.3),
        offset: const Offset(6, 6),
        child: Column(
          children: [
            InkWell(
              onTap: () => setState(() => _filtersExpanded = !_filtersExpanded),
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.black, width: 2),
                      ),
                      child: const Icon(Icons.filter_list_rounded, size: 20),
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
                              color: Colors.black.withValues(alpha: 0.6),
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
                    const Divider(height: 1, thickness: 2, color: Colors.black),
                    const SizedBox(height: 16),
                    _FilterLabel(text: 'Khoảng thời gian'),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final filter in [
                            _DateQuickFilter.all,
                            _DateQuickFilter.today,
                            _DateQuickFilter.last7Days,
                            _DateQuickFilter.thisMonth,
                          ])
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(_quickLabel(filter)),
                                selected: _quickFilter == filter,
                                onSelected: (_) => _applyQuickFilter(filter),
                              ),
                            ),
                          OutlinedButton.icon(
                            onPressed: _pickDateRange,
                            icon: const Icon(Icons.date_range_rounded),
                            label: Text(
                              _quickFilter == _DateQuickFilter.custom &&
                                      _from != null &&
                                      _to != null
                                  ? '${_formatDate(_from)} - ${_formatDate(_to)}'
                                  : 'Chọn khoảng ngày',
                            ),
                          ),
                          if (_from != null || _to != null)
                            IconButton(
                              tooltip: 'Xoá lọc thời gian',
                              onPressed: _clearDateRange,
                              icon: const Icon(Icons.close_rounded),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _FilterLabel(text: 'Trạng thái hoá đơn'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _invoiceStatusLabels.entries
                          .map((entry) {
                            final selected = _statusFilter == entry.key;
                            return FilterChip(
                              label: Text(entry.value),
                              selected: selected,
                              onSelected: (_) {
                                if (!selected) {
                                  setState(() => _statusFilter = entry.key);
                                  _load();
                                }
                              },
                            );
                          })
                          .toList(growable: false),
                    ),
                    const SizedBox(height: 16),
                    _FilterLabel(text: 'Phương thức thanh toán'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _paymentFilters.entries
                          .map((entry) {
                            final selected = _paymentFilter == entry.key;
                            return FilterChip(
                              label: Text(entry.value),
                              selected: selected,
                              onSelected: (_) =>
                                  setState(() => _paymentFilter = entry.key),
                            );
                          })
                          .toList(growable: false),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _getFilterSummary() {
    final parts = <String>[];

    // Date filter
    if (_quickFilter == _DateQuickFilter.custom &&
        _from != null &&
        _to != null) {
      parts.add('${_formatDate(_from)} - ${_formatDate(_to)}');
    } else {
      parts.add(_quickLabel(_quickFilter));
    }

    // Status filter
    if (_statusFilter != 'all') {
      parts.add(_invoiceStatusLabels[_statusFilter] ?? _statusFilter);
    }

    // Payment filter
    if (_paymentFilter != 'all') {
      parts.add(_paymentFilters[_paymentFilter] ?? _paymentFilter);
    }

    return parts.join(' • ');
  }

  Widget _buildSearchField() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        decoration: InputDecoration(
          hintText: 'Tìm kiếm theo mã hoá đơn, tên khách hàng...',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 18,
          ),
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
            borderSide: BorderSide(color: theme.colorScheme.primary, width: 3),
          ),
        ),
        textInputAction: TextInputAction.search,
        onChanged: (value) => setState(() => _searchQuery = value.trim()),
      ),
    );
  }

  Widget _buildContent() {
    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 32),
          Icon(
            Icons.cloud_off_rounded,
            size: 64,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text(
            'Không thể tải dữ liệu. Vui lòng thử lại.',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _load, child: const Text('Thử lại')),
        ],
      );
    }

    final invoices = _filteredInvoices;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 24),
      children: [
        _SummaryCard(summary: _summary, formatCurrency: _formatCurrency),
        const SizedBox(height: 12),
        if (invoices.isEmpty) const _EmptyInvoicesState(),
        ...List.generate(invoices.length, (index) {
          final invoice = invoices[index];
          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.96, end: 1),
            duration: Duration(milliseconds: 250 + (index * 20)),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) => Transform.scale(
              scale: value,
              alignment: Alignment.topCenter,
              child: child,
            ),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _InvoiceCard(
                invoice: invoice,
                statusLabel:
                    _invoiceStatusLabels[invoice.status] ?? invoice.status,
                statusColor: _statusColor(invoice.status, Theme.of(context)),
                amountText: _formatCurrency(invoice.amount),
                issueDate: _formatDateTime(invoice.issuedAt),
                customerLine: _customerLine(invoice),
                paymentLabel: _paymentLabelForInvoice(invoice),
                outstandingText: _formatCurrency(invoice.outstanding),
                bookingInfo: _bookingLine(invoice),
                onTap: () => _showInvoiceDetail(invoice),
              ),
            ),
          );
        }),
      ],
    );
  }

  String _customerLine(StaffInvoice invoice) {
    final customer = invoice.customer;
    if (customer == null) return 'Khách hàng: Chưa cập nhật';
    final name = customer.name ?? customer.email ?? 'Không rõ';
    final phone = customer.phone ?? '';
    return phone.isEmpty ? 'Khách hàng: $name' : 'Khách hàng: $name • $phone';
  }

  String _bookingLine(StaffInvoice invoice) {
    final booking = invoice.booking;
    final court = invoice.court;
    final buffer = StringBuffer();
    if (court != null) {
      buffer.write('Sân: ${court.name ?? 'Không rõ'}');
      if (court.code != null && court.code!.isNotEmpty) {
        buffer.write(' (${court.code})');
      }
    }
    if (booking != null) {
      if (buffer.isNotEmpty) buffer.write(' • ');
      buffer.write(
        'Thời gian: ${_formatDateTime(booking.start)} - ${_formatDateTime(booking.end)}',
      );
    }
    return buffer.isEmpty ? 'Chưa có thông tin đặt sân' : buffer.toString();
  }

  Future<void> _showInvoiceDetail(StaffInvoice invoice) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final busy = _busyInvoices.contains(invoice.id);
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: _InvoiceDetailSheet(
            invoice: invoice,
            formatCurrency: _formatCurrency,
            formatDate: _formatDate,
            formatDateTime: _formatDateTime,
            paymentLabel: _paymentLabelForInvoice(invoice),
            statusLabel: _invoiceStatusLabels[invoice.status] ?? invoice.status,
            statusColor: _statusColor(invoice.status, Theme.of(context)),
            onMarkPaid: busy
                ? null
                : () {
                    Navigator.of(sheetContext).pop();
                    _markInvoicePaid(invoice);
                  },
            onSendReminder: busy ? null : () => _sendReminder(invoice),
            isBusy: busy,
          ),
        );
      },
    );
  }
}

class _FilterLabel extends StatelessWidget {
  const _FilterLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary, required this.formatCurrency});

  final StaffInvoiceSummary summary;
  final String Function(double) formatCurrency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NeuContainer(
      borderRadius: BorderRadius.circular(24),
      color: const Color(0xFFE6F7FF),
      borderColor: Colors.black,
      borderWidth: 3,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      offset: const Offset(8, 8),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tổng quan doanh thu',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Tổng hoá đơn', style: theme.textTheme.bodySmall),
                      const SizedBox(height: 4),
                      Text(
                        '${summary.invoiceCount}',
                        style: theme.textTheme.headlineSmall,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tổng tiền phát hành',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formatCurrency(summary.totalInvoiced),
                        style: theme.textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _SummaryInfoTile(
                  label: 'Đã thu',
                  value: formatCurrency(summary.totalPaid),
                  color: theme.colorScheme.primary,
                ),
                _SummaryInfoTile(
                  label: 'Còn lại',
                  value: formatCurrency(summary.totalOutstanding),
                  color: Colors.amber.shade700,
                ),
                _SummaryInfoTile(
                  label: 'Doanh thu',
                  value: formatCurrency(summary.totalRevenue),
                  color: theme.colorScheme.secondary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryInfoTile extends StatelessWidget {
  const _SummaryInfoTile({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return NeuContainer(
      borderRadius: BorderRadius.circular(16),
      color: Colors.white,
      borderColor: color,
      borderWidth: 2,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      offset: const Offset(4, 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({
    required this.invoice,
    required this.statusLabel,
    required this.statusColor,
    required this.amountText,
    required this.issueDate,
    required this.customerLine,
    required this.paymentLabel,
    required this.outstandingText,
    required this.bookingInfo,
    required this.onTap,
  });

  final StaffInvoice invoice;
  final String statusLabel;
  final Color statusColor;
  final String amountText;
  final String issueDate;
  final String customerLine;
  final String paymentLabel;
  final String outstandingText;
  final String bookingInfo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardColor = _pastelColorForStatus(invoice.status);
    return NeuContainer(
      borderRadius: BorderRadius.circular(24),
      color: cardColor,
      borderColor: Colors.black,
      borderWidth: 3,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      offset: const Offset(6, 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.black, width: 2),
                    ),
                    child: const Icon(Icons.receipt_long_rounded),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          invoice.id,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(customerLine, style: theme.textTheme.bodyMedium),
                        const SizedBox(height: 4),
                        Text(
                          'Ngày lập: $issueDate',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  _buildStatusChip(statusLabel, statusColor),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Tổng tiền', style: theme.textTheme.bodySmall),
                        const SizedBox(height: 4),
                        Text(amountText, style: theme.textTheme.titleMedium),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Còn lại', style: theme.textTheme.bodySmall),
                        const SizedBox(height: 4),
                        Text(
                          outstandingText,
                          style: theme.textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Phương thức: $paymentLabel',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Text(bookingInfo, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }

  Color _pastelColorForStatus(String status) {
    switch (status) {
      case 'paid':
        return const Color(0xFFE6F7E6);
      case 'unpaid':
        return const Color(0xFFFFF8DC);
      case 'refunded':
        return const Color(0xFFE6E6FA);
      case 'void':
        return const Color(0xFFF5F5F5);
      default:
        return const Color(0xFFFFFFFF);
    }
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
        style: TextStyle(fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

class _EmptyInvoicesState extends StatelessWidget {
  const _EmptyInvoicesState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: NeuContainer(
        borderRadius: BorderRadius.circular(24),
        color: theme.colorScheme.surface,
        borderColor: Colors.black,
        borderWidth: 3,
        shadowColor: Colors.black.withValues(alpha: 0.25),
        offset: const Offset(8, 8),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(
                Icons.receipt_long_outlined,
                size: 72,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(
                'Không tìm thấy hoá đơn nào.',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Hãy thử điều chỉnh bộ lọc hoặc kéo xuống để tải lại dữ liệu.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InvoiceDetailSheet extends StatelessWidget {
  const _InvoiceDetailSheet({
    required this.invoice,
    required this.formatCurrency,
    required this.formatDate,
    required this.formatDateTime,
    required this.paymentLabel,
    required this.statusLabel,
    required this.statusColor,
    required this.onMarkPaid,
    required this.onSendReminder,
    required this.isBusy,
  });

  final StaffInvoice invoice;
  final String Function(double) formatCurrency;
  final String Function(DateTime?) formatDate;
  final String Function(DateTime?) formatDateTime;
  final String paymentLabel;
  final String statusLabel;
  final Color statusColor;
  final VoidCallback? onMarkPaid;
  final VoidCallback? onSendReminder;
  final bool isBusy;

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
        style: TextStyle(fontWeight: FontWeight.w700, color: color),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.5,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          children: [
            Center(
              child: Container(
                width: 48,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hoá đơn ${invoice.id}',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text('Ngày lập: ${formatDateTime(invoice.issuedAt)}'),
                    ],
                  ),
                ),
                _buildStatusChip(statusLabel, statusColor),
              ],
            ),
            const SizedBox(height: 24),
            _DetailSection(
              title: 'Thông tin khách hàng',
              rows: [
                _DetailRow(
                  label: 'Họ tên',
                  value: invoice.customer?.name ?? 'Chưa cập nhật',
                ),
                _DetailRow(
                  label: 'Số điện thoại',
                  value: invoice.customer?.phone ?? '—',
                ),
                _DetailRow(
                  label: 'Email',
                  value: invoice.customer?.email ?? '—',
                ),
              ],
            ),
            _DetailSection(
              title: 'Chi tiết đặt sân / dịch vụ',
              rows: [
                _DetailRow(label: 'Mã đặt sân', value: invoice.bookingId),
                _DetailRow(label: 'Thời gian', value: _bookingTime(invoice)),
                _DetailRow(label: 'Sân', value: _courtInfo(invoice)),
              ],
            ),
            _DetailSection(
              title: 'Thanh toán',
              rows: [
                _DetailRow(
                  label: 'Tổng tiền',
                  value: formatCurrency(invoice.amount),
                ),
                _DetailRow(
                  label: 'Đã thu',
                  value: formatCurrency(invoice.totalPaid),
                ),
                _DetailRow(
                  label: 'Còn lại',
                  value: formatCurrency(invoice.outstanding),
                ),
                _DetailRow(label: 'Phương thức', value: paymentLabel),
              ],
            ),
            if (invoice.payments.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Lịch sử thanh toán', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              ...invoice.payments.map(
                (payment) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: NeuContainer(
                    borderRadius: BorderRadius.circular(16),
                    color: Colors.white,
                    borderColor: Colors.black,
                    borderWidth: 2,
                    shadowColor: Colors.black.withValues(alpha: 0.15),
                    offset: const Offset(4, 4),
                    child: ListTile(
                      title: Text(
                        '${payment.provider} - ${payment.method}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        'Thời gian: ${formatDateTime(payment.createdAt)}',
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            formatCurrency(payment.amount),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            payment.status,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                if (invoice.status != 'paid' && invoice.outstanding > 0)
                  SizedBox(
                    height: 48,
                    child: NeuButton(
                      onPressed: isBusy ? null : onMarkPaid,
                      buttonHeight: 48,
                      buttonWidth: double.infinity,
                      borderRadius: BorderRadius.circular(16),
                      borderColor: Colors.black,
                      buttonColor: theme.colorScheme.primary,
                      shadowColor: Colors.black.withValues(alpha: 0.35),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isBusy)
                            const NeoLoadingDot(
                              size: 18,
                              fillColor: Colors.white,
                            )
                          else
                            const Icon(
                              Icons.verified_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          const SizedBox(width: 8),
                          Text(
                            isBusy ? 'Đang xử lý...' : 'Xác nhận đã thanh toán',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (invoice.outstanding > 0)
                  SizedBox(
                    height: 48,
                    child: NeuButton(
                      onPressed: isBusy ? null : onSendReminder,
                      buttonHeight: 48,
                      buttonWidth: double.infinity,
                      borderRadius: BorderRadius.circular(16),
                      borderColor: Colors.black,
                      buttonColor: theme.colorScheme.secondaryContainer,
                      shadowColor: Colors.black.withValues(alpha: 0.35),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.notifications_active_outlined,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Nhắc nhở thanh toán',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Đóng'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _bookingTime(StaffInvoice invoice) {
    final booking = invoice.booking;
    if (booking == null) return '—';
    return '${formatDateTime(booking.start)} - ${formatDateTime(booking.end)}';
  }

  String _courtInfo(StaffInvoice invoice) {
    final court = invoice.court;
    if (court == null) return '—';
    if (court.code != null && court.code!.isNotEmpty) {
      return '${court.name ?? 'Không rõ'} (${court.code})';
    }
    return court.name ?? 'Không rõ';
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.rows});

  final String title;
  final List<_DetailRow> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...rows,
        const SizedBox(height: 16),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

String _quickLabel(_DateQuickFilter filter) {
  switch (filter) {
    case _DateQuickFilter.all:
      return 'Tất cả';
    case _DateQuickFilter.today:
      return 'Hôm nay';
    case _DateQuickFilter.last7Days:
      return '7 ngày gần đây';
    case _DateQuickFilter.thisMonth:
      return 'Tháng này';
    case _DateQuickFilter.custom:
      return 'Tuỳ chỉnh';
  }
}
