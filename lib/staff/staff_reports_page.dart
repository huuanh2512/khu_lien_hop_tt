import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:neubrutalism_ui/neubrutalism_ui.dart';

import 'package:khu_lien_hop_tt/services/api_service.dart';
import 'package:khu_lien_hop_tt/widgets/error_state_widget.dart';
import 'package:khu_lien_hop_tt/widgets/neo_loading.dart';
import 'package:khu_lien_hop_tt/widgets/neu_button.dart';
import 'package:khu_lien_hop_tt/widgets/neu_text.dart';
import 'staff_invoices_page.dart';

/// Neo-brutalist "Báo cáo thống kê" page for staff.
class StaffReportsPage extends StatefulWidget {
  const StaffReportsPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<StaffReportsPage> createState() => _StaffReportsPageState();
}

enum _RangeOption { days7, days30, custom }

class _StaffReportsPageState extends State<StaffReportsPage> {
  final ApiService _api = ApiService();

  _RangeOption _rangeOption = _RangeOption.days7;
  late DateTimeRange _range;

  bool _loading = true;
  String? _error;

  // Cached data
  Map<String, dynamic>? _summary;
  List<dynamic>? _revenueDaily;
  List<dynamic>? _peakHours;
  List<dynamic>? _topCourts;
  Map<String, dynamic>? _cancellations;

  static const _pastelYellow = Color(0xFFFFF4C7);
  static const _pastelMint = Color(0xFFBBF1E2);
  static const _pastelPink = Color(0xFFFFD6E8);
  static const _pastelBlue = Color(0xFFE0EDFF);
  static const _pastelOrange = Color(0xFFFFF0D7);
  static const _pastelPurple = Color(0xFFE8DAFF);

  @override
  void initState() {
    super.initState();
    _range = _computeRange(_rangeOption);
    _load();
  }

  DateTimeRange _computeRange(_RangeOption option) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 23, 59, 59);
    switch (option) {
      case _RangeOption.days7:
        return DateTimeRange(
          start: today.subtract(const Duration(days: 6)),
          end: today,
        );
      case _RangeOption.days30:
        return DateTimeRange(
          start: today.subtract(const Duration(days: 29)),
          end: today,
        );
      case _RangeOption.custom:
        return _range;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final from = _range.start;
      final to = _range.end;

      final results = await Future.wait([
        _api.staffGetReportSummary(from: from, to: to),
        _api.staffGetRevenueDaily(from: from, to: to),
        _api.staffGetPeakHours(from: from, to: to),
        _api.staffGetTopCourts(from: from, to: to, limit: 5),
        _api.staffGetCancellations(from: from, to: to),
      ]);

      if (!mounted) return;
      setState(() {
        _summary = results[0] as Map<String, dynamic>;
        _revenueDaily = results[1] as List<dynamic>;
        _peakHours = results[2] as List<dynamic>;
        _topCourts = results[3] as List<dynamic>;
        _cancellations = results[4] as Map<String, dynamic>;
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

  void _onRangeChanged(_RangeOption option) {
    if (_rangeOption == option && option != _RangeOption.custom) return;
    setState(() {
      _rangeOption = option;
      _range = _computeRange(option);
    });
    _load();
  }

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _range,
      locale: const Locale('vi', 'VN'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: Colors.black,
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      setState(() {
        _rangeOption = _RangeOption.custom;
        _range = DateTimeRange(
          start: picked.start,
          end: DateTime(
            picked.end.year,
            picked.end.month,
            picked.end.day,
            23,
            59,
            59,
          ),
        );
      });
      _load();
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat('dd/MM').format(date);
  }

  String _formatCurrency(num value) {
    final formatter = NumberFormat('#,###', 'vi_VN');
    return '${formatter.format(value)}đ';
  }

  String _formatNumber(num value) {
    final formatter = NumberFormat('#,###', 'vi_VN');
    return formatter.format(value);
  }

  String _formatPercent(num value) {
    return '${(value * 100).toStringAsFixed(1)}%';
  }

  @override
  Widget build(BuildContext context) {
    final content = _loading
        ? _buildLoading()
        : _error != null
            ? _buildError()
            : _buildContent();

    if (widget.embedded) {
      return content;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Báo cáo thống kê'),
        backgroundColor: _pastelMint,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SafeArea(child: content),
    );
  }

  Widget _buildLoading() {
    if (widget.embedded) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: NeoLoadingCard(
          label: 'Đang tải báo cáo...',
          width: 260,
        ),
      );
    }
    return const Center(
      child: NeoLoadingCard(
        label: 'Đang tải báo cáo...',
        width: 260,
      ),
    );
  }

  Widget _buildError() {
    if (widget.embedded) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: ErrorStateWidget(
          onRetry: _load,
          message: _error,
        ),
      );
    }
    return Center(
      child: ErrorStateWidget(
        onRetry: _load,
        message: _error,
      ),
    );
  }

  Widget _buildContent() {
    final children = [
      _buildHeader(),
      const SizedBox(height: 20),
      _buildKpiGrid(),
      const SizedBox(height: 24),
      _buildRevenueChart(),
      const SizedBox(height: 24),
      _buildPeakHoursChart(),
      const SizedBox(height: 24),
      _buildTopCourtsSection(),
      const SizedBox(height: 24),
      _buildRevenueBySportSection(),
      const SizedBox(height: 24),
      _buildCancellationsSection(),
      const SizedBox(height: 32),
    ];

    // When embedded, use ListView to allow scrolling
    if (widget.embedded) {
      return ListView(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        children: children,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        children: children,
      ),
    );
  }

  Widget _buildHeader() {
    final rangeLabel = _rangeOption == _RangeOption.days7
        ? '7 ngày'
        : _rangeOption == _RangeOption.days30
            ? '30 ngày'
            : 'Tuỳ chọn';
    final dateDisplay =
        '$rangeLabel: ${_formatDate(_range.start)} → ${_formatDate(_range.end)}';

    return NeuContainer(
      borderRadius: BorderRadius.circular(20),
      color: _pastelYellow,
      borderColor: Colors.black,
      borderWidth: 3,
      shadowColor: Colors.black.withValues(alpha: 0.35),
      offset: const Offset(6, 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bar_chart, size: 28, color: Colors.black),
                const SizedBox(width: 10),
                Expanded(
                  child: NeuText(
                    'Báo cáo thống kê',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              dateDisplay,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildRangeChip('7 ngày', _RangeOption.days7),
                _buildRangeChip('30 ngày', _RangeOption.days30),
                _buildRangeChip('Tuỳ chọn', _RangeOption.custom, onTap: _pickCustomRange),
                const SizedBox(width: 8),
                NeuButton(
                  onPressed: _load,
                  buttonHeight: 40,
                  buttonWidth: 110,
                  buttonColor: _pastelMint,
                  borderRadius: BorderRadius.circular(12),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.refresh, size: 18, color: Colors.black),
                      SizedBox(width: 6),
                      Text(
                        'Làm mới',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.black,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRangeChip(String label, _RangeOption option, {VoidCallback? onTap}) {
    final isSelected = _rangeOption == option;
    return GestureDetector(
      onTap: onTap ?? () => _onRangeChanged(option),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.black : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black, width: 2),
          boxShadow: isSelected
              ? null
              : const [
                  BoxShadow(
                    color: Colors.black,
                    offset: Offset(3, 3),
                    blurRadius: 0,
                  ),
                ],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: isSelected ? Colors.white : Colors.black,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildKpiGrid() {
    final kpis = _summary?['kpis'] as Map<String, dynamic>? ?? {};
    final revenueTotal = (kpis['revenueTotal'] as num?) ?? 0;
    final bookingsTotal = (kpis['bookingsTotal'] as num?) ?? 0;
    final cancelRate = (kpis['cancelRate'] as num?) ?? 0;
    final unpaidCount = (kpis['unpaidInvoicesCount'] as num?) ?? 0;
    final unpaidAmount = (kpis['unpaidAmountTotal'] as num?) ?? 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 400 ? 2 : 1;
        return GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: crossAxisCount == 2 ? 1.5 : 2.5,
          children: [
            _buildKpiCard(
              icon: Icons.attach_money,
              label: 'Doanh thu',
              value: _formatCurrency(revenueTotal),
              color: _pastelMint,
            ),
            _buildKpiCard(
              icon: Icons.calendar_today,
              label: 'Lượt đặt sân',
              value: _formatNumber(bookingsTotal),
              color: _pastelBlue,
            ),
            _buildKpiCard(
              icon: Icons.cancel_outlined,
              label: 'Tỉ lệ huỷ',
              value: _formatPercent(cancelRate),
              color: _pastelPink,
            ),
            _buildKpiCard(
              icon: Icons.receipt_long,
              label: 'Hoá đơn chưa TT',
              value: '$unpaidCount (${_formatCurrency(unpaidAmount)})',
              color: _pastelOrange,
              onTap: unpaidCount > 0
                  ? () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const StaffInvoicesPage(
                            initialStatusFilter: 'unpaid',
                          ),
                        ),
                      );
                    }
                  : null,
            ),
          ],
        );
      },
    );
  }

  Widget _buildKpiCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    VoidCallback? onTap,
  }) {
    final card = NeuContainer(
      borderRadius: BorderRadius.circular(16),
      color: color,
      borderColor: Colors.black,
      borderWidth: 3,
      shadowColor: Colors.black.withValues(alpha: 0.35),
      offset: const Offset(6, 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(icon, size: 22, color: Colors.black),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (onTap != null)
                  const Icon(Icons.chevron_right, size: 18, color: Colors.black54),
              ],
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                  color: Colors.black,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: card,
      );
    }
    return card;
  }

  Widget _buildRevenueChart() {
    final data = _revenueDaily ?? [];
    if (data.isEmpty) {
      return _buildEmptySection('Doanh thu theo ngày', 'Chưa có dữ liệu');
    }

    final maxRevenue = data.fold<num>(
      0,
      (max, item) => ((item['revenue'] as num?) ?? 0) > max ? (item['revenue'] as num? ?? 0) : max,
    );

    return _buildSection(
      title: 'Doanh thu theo ngày',
      icon: Icons.trending_up,
      color: _pastelMint,
      child: Column(
        children: data.map((item) {
          final date = item['date']?.toString() ?? '';
          final revenue = (item['revenue'] as num?) ?? 0;
          final count = (item['bookingsCount'] as num?) ?? 0;
          final fraction = maxRevenue > 0 ? revenue / maxRevenue : 0.0;

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 55,
                  child: Text(
                    _formatDateShort(date),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: _buildBar(fraction, _pastelMint),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 80,
                  child: Text(
                    _formatCurrency(revenue),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 30,
                  child: Text(
                    '(${count.toInt()})',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPeakHoursChart() {
    final data = _peakHours ?? [];
    if (data.isEmpty) {
      return _buildEmptySection('Giờ cao điểm', 'Chưa có dữ liệu');
    }

    final maxCount = data.fold<num>(
      0,
      (max, item) => ((item['bookingsCount'] as num?) ?? 0) > max ? (item['bookingsCount'] as num? ?? 0) : max,
    );

    return _buildSection(
      title: 'Giờ cao điểm',
      icon: Icons.access_time,
      color: _pastelBlue,
      child: Column(
        children: data.map((item) {
          final hour = (item['hour'] as num?)?.toInt() ?? 0;
          final count = (item['bookingsCount'] as num?) ?? 0;
          final fraction = maxCount > 0 ? count / maxCount : 0.0;

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 50,
                  child: Text(
                    '${hour.toString().padLeft(2, '0')}:00',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: _buildBar(fraction.toDouble(), _pastelBlue),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 40,
                  child: Text(
                    '${count.toInt()} lượt',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBar(double fraction, Color color) {
    return Container(
      height: 20,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.black, width: 1.5),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: fraction.clamp(0.02, 1.0),
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }

  Widget _buildTopCourtsSection() {
    final data = _topCourts ?? [];
    if (data.isEmpty) {
      return _buildEmptySection('Top sân được đặt nhiều', 'Chưa có dữ liệu');
    }

    return _buildSection(
      title: 'Top sân được đặt nhiều',
      icon: Icons.emoji_events,
      color: _pastelPurple,
      child: Column(
        children: data.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value as Map<String, dynamic>;
          return _buildTopCourtItem(index + 1, item);
        }).toList(),
      ),
    );
  }

  Widget _buildTopCourtItem(int rank, Map<String, dynamic> item) {
    final courtName = item['courtName']?.toString() ?? 'Không rõ';
    final facilityName = item['facilityName']?.toString() ?? '';
    final bookingsCount = (item['bookingsCount'] as num?)?.toInt() ?? 0;
    final revenue = (item['revenue'] as num?) ?? 0;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
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
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: rank == 1
                  ? const Color(0xFFFFD700)
                  : rank == 2
                      ? const Color(0xFFC0C0C0)
                      : rank == 3
                          ? const Color(0xFFCD7F32)
                          : _pastelBlue,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black, width: 2),
            ),
            child: Center(
              child: Text(
                '$rank',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: Colors.black,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  courtName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                if (facilityName.isNotEmpty)
                  Text(
                    facilityName,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                    ),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$bookingsCount lượt',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              Text(
                _formatCurrency(revenue),
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.black54,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRevenueBySportSection() {
    final breakdown = _summary?['breakdown'] as Map<String, dynamic>? ?? {};
    final data = breakdown['revenueBySport'] as List<dynamic>? ?? [];
    if (data.isEmpty) {
      return _buildEmptySection('Doanh thu theo môn', 'Chưa có dữ liệu');
    }

    return _buildSection(
      title: 'Doanh thu theo môn',
      icon: Icons.sports_soccer,
      color: _pastelPink,
      child: Column(
        children: data.map((item) {
          final map = item as Map<String, dynamic>;
          final sportName = map['sportName']?.toString() ?? 'Không rõ';
          final revenue = (map['revenue'] as num?) ?? 0;
          final count = (map['count'] as num?)?.toInt() ?? 0;

          return Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.black, width: 2),
            ),
            child: Row(
              children: [
                const Icon(Icons.sports, size: 20, color: Colors.black54),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    sportName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatCurrency(revenue),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      '$count lượt',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ---- Cancellation Analytics Section ----

  static const _roleLabels = {
    'staff': 'Nhân viên',
    'customer': 'Khách hàng',
    'system': 'Hệ thống',
    'unknown': 'Không rõ',
  };

  Widget _buildCancellationsSection() {
    final data = _cancellations;
    if (data == null || data.isEmpty) {
      return _buildEmptySection('Phân tích huỷ', 'Chưa có dữ liệu');
    }

    final byRole = (data['byRole'] as List<dynamic>?) ?? [];
    final byReason = (data['byReason'] as List<dynamic>?) ?? [];
    final byCourt = (data['byCourt'] as List<dynamic>?) ?? [];

    // Calculate totals
    final totalCancelled = byRole.fold<int>(
      0,
      (sum, item) => sum + ((item['count'] as num?)?.toInt() ?? 0),
    );

    // Get summary cancellations data for cancel rate and top active courts
    final cancellationsFromSummary =
        _summary?['cancellations'] as Map<String, dynamic>? ?? {};
    final cancelRate = (cancellationsFromSummary['cancelRate'] as num?) ?? 0;
    final topActiveCourts =
        (cancellationsFromSummary['topActiveCourts'] as List<dynamic>?) ?? [];

    // System cancelled count
    final systemCancelled = byRole
        .where((item) => item['_id'] == 'system')
        .fold<int>(0, (sum, item) => sum + ((item['count'] as num?)?.toInt() ?? 0));

    return NeuContainer(
      borderRadius: BorderRadius.circular(20),
      color: _pastelOrange,
      borderColor: Colors.black,
      borderWidth: 3,
      shadowColor: Colors.black.withValues(alpha: 0.35),
      offset: const Offset(6, 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _pastelPink,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.black, width: 2),
                  ),
                  child: const Icon(Icons.cancel_outlined, size: 20, color: Colors.black),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Phân tích huỷ',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // KPI Row
            _buildCancellationKpiRow(totalCancelled, cancelRate, systemCancelled),
            const SizedBox(height: 16),

            // By Role chips
            if (byRole.isNotEmpty) ...[  
              const Text(
                'Huỷ bởi',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              const SizedBox(height: 8),
              _buildByRoleChips(byRole),
              const SizedBox(height: 16),
            ],

            // Top Reasons
            if (byReason.isNotEmpty) ...[  
              const Text(
                'Lý do huỷ hàng đầu',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              const SizedBox(height: 8),
              _buildTopReasonsList(byReason.take(5).toList()),
              const SizedBox(height: 16),
            ],

            // Courts comparison
            if (byCourt.isNotEmpty || topActiveCourts.isNotEmpty)
              _buildCourtsComparison(byCourt, topActiveCourts),
          ],
        ),
      ),
    );
  }

  Widget _buildCancellationKpiRow(int totalCancelled, num cancelRate, int systemCancelled) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _buildMiniKpi(
          icon: Icons.block,
          label: 'Số lượt huỷ',
          value: _formatNumber(totalCancelled),
          color: _pastelPink,
        ),
        _buildMiniKpi(
          icon: Icons.percent,
          label: 'Tỉ lệ huỷ',
          value: _formatPercent(cancelRate),
          color: _pastelYellow,
        ),
        _buildMiniKpi(
          icon: Icons.smart_toy,
          label: 'Huỷ bởi hệ thống',
          value: _formatNumber(systemCancelled),
          color: _pastelBlue,
        ),
      ],
    );
  }

  Widget _buildMiniKpi({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color,
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
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Colors.black),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.black,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildByRoleChips(List<dynamic> byRole) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: byRole.map((item) {
        final role = item['_id']?.toString() ?? 'unknown';
        final count = (item['count'] as num?)?.toInt() ?? 0;
        final label = _roleLabels[role] ?? role;

        Color chipColor;
        switch (role) {
          case 'customer':
            chipColor = _pastelBlue;
            break;
          case 'staff':
            chipColor = _pastelMint;
            break;
          case 'system':
            chipColor = _pastelPurple;
            break;
          default:
            chipColor = Colors.grey.shade200;
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: chipColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.black, width: 2),
            boxShadow: const [
              BoxShadow(
                color: Colors.black,
                offset: Offset(2, 2),
                blurRadius: 0,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: Colors.black,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.black, width: 1.5),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: Colors.black,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTopReasonsList(List<dynamic> reasons) {
    return Column(
      children: reasons.asMap().entries.map((entry) {
        final index = entry.key;
        final item = entry.value as Map<String, dynamic>;
        final reasonText = item['reasonText']?.toString() ?? item['_id']?.toString() ?? 'Không rõ';
        final count = (item['count'] as num?)?.toInt() ?? 0;

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.black, width: 2),
          ),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: _pastelPink,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black, width: 1.5),
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  reasonText,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _pastelOrange,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.black, width: 1.5),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: Colors.black,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCourtsComparison(List<dynamic> cancelledCourts, List<dynamic> activeCourts) {
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black, width: 2),
            ),
            child: TabBar(
              labelColor: Colors.white,
              unselectedLabelColor: Colors.black,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              indicator: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(10),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(text: 'Sân hoạt động nhiều'),
                Tab(text: 'Sân huỷ nhiều'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: TabBarView(
              children: [
                _buildCourtsListView(activeCourts, isActive: true),
                _buildCourtsListView(cancelledCourts, isActive: false),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCourtsListView(List<dynamic> courts, {required bool isActive}) {
    if (courts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 32, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(
              'Chưa có dữ liệu',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ),
      );
    }

    // Sort cancelled courts by cancelledCount descending
    final sortedCourts = List<dynamic>.from(courts);
    if (!isActive) {
      sortedCourts.sort((a, b) {
        final countA = (a['cancelledCount'] as num?)?.toInt() ?? 0;
        final countB = (b['cancelledCount'] as num?)?.toInt() ?? 0;
        return countB.compareTo(countA);
      });
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: sortedCourts.length.clamp(0, 5),
      itemBuilder: (context, index) {
        final item = sortedCourts[index] as Map<String, dynamic>;
        final courtName = item['courtName']?.toString() ?? 'Không rõ';
        final facilityName = item['facilityName']?.toString() ?? '';
        final bookingsCount = (item['bookingsCount'] as num?)?.toInt() ?? 0;
        final cancelledCount = (item['cancelledCount'] as num?)?.toInt() ?? 0;
        final cancelRate = (item['cancelRate'] as num?) ?? 0;

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.black, width: 2),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: isActive ? _pastelMint : _pastelPink,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black, width: 1.5),
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      courtName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (facilityName.isNotEmpty)
                      Text(
                        facilityName,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.black54,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    isActive ? '$bookingsCount lượt' : '$cancelledCount huỷ',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    isActive ? '' : 'Tỉ lệ: ${_formatPercent(cancelRate)}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required Color color,
    required Widget child,
  }) {
    return NeuContainer(
      borderRadius: BorderRadius.circular(20),
      color: Colors.white,
      borderColor: Colors.black,
      borderWidth: 3,
      shadowColor: Colors.black.withValues(alpha: 0.35),
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
                    color: color,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.black, width: 2),
                  ),
                  child: Icon(icon, size: 20, color: Colors.black),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildEmptySection(String title, String message) {
    return NeuContainer(
      borderRadius: BorderRadius.circular(20),
      color: Colors.grey.shade100,
      borderColor: Colors.black,
      borderWidth: 3,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      offset: const Offset(4, 4),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 10),
            Icon(Icons.inbox_outlined, size: 36, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateShort(String isoOrYMD) {
    try {
      final date = DateTime.parse(isoOrYMD);
      return DateFormat('dd/MM').format(date);
    } catch (_) {
      return isoOrYMD.length > 5 ? isoOrYMD.substring(5) : isoOrYMD;
    }
  }
}
