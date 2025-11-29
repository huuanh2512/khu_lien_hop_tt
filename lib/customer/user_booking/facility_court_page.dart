import 'package:flutter/material.dart';
import 'package:neubrutalism_ui/neubrutalism_ui.dart';

import 'package:khu_lien_hop_tt/models/court.dart';
import 'package:khu_lien_hop_tt/models/facility.dart';
import 'package:khu_lien_hop_tt/models/sport.dart';
import 'package:khu_lien_hop_tt/services/user_booking_service.dart';
import 'package:khu_lien_hop_tt/widgets/success_dialog.dart';
import 'package:khu_lien_hop_tt/widgets/neu_button.dart';

import 'package:khu_lien_hop_tt/customer/user_booking/booking_scheduler_page.dart';

class FacilityCourtSelectionPage extends StatefulWidget {
  final Sport sport;
  const FacilityCourtSelectionPage({super.key, required this.sport});

  @override
  State<FacilityCourtSelectionPage> createState() =>
      _FacilityCourtSelectionPageState();
}

class _FacilityCourtSelectionPageState
    extends State<FacilityCourtSelectionPage> {
  final UserBookingService _service = UserBookingService();
  List<FacilityWithCourts> _facilities = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFacilities();
  }

  Future<void> _loadFacilities() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _service.fetchFacilitiesBySport(widget.sport.id);
      if (!mounted) return;
      setState(() {
        _facilities = items;
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
    return Scaffold(
      appBar: AppBar(title: Text('Chọn cơ sở - ${widget.sport.name}')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: NeuContainer(
            color: const Color(0xFFF8D7DA),
            borderColor: const Color(0xFFDC3545),
            borderWidth: 3,
            borderRadius: BorderRadius.circular(16),
            shadowColor: Colors.black.withValues(alpha: 0.25),
            offset: const Offset(6, 6),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Color(0xFFDC3545)),
                  const SizedBox(height: 12),
                  Text(
                    'Không thể tải danh sách cơ sở',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  NeuButton(
                    buttonHeight: 48,
                    buttonWidth: 140,
                    borderRadius: BorderRadius.circular(12),
                    buttonColor: Theme.of(context).colorScheme.primary,
                    onPressed: _loadFacilities,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.refresh, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Thử lại',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    if (_facilities.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: NeuContainer(
            color: const Color(0xFFF5F5F5),
            borderColor: Colors.black,
            borderWidth: 3,
            borderRadius: BorderRadius.circular(16),
            shadowColor: Colors.black.withValues(alpha: 0.25),
            offset: const Offset(6, 6),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.sentiment_dissatisfied, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'Không tìm thấy cơ sở nào có sân cho môn ${widget.sport.name}.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 16),
                  NeuButton(
                    buttonHeight: 48,
                    buttonWidth: 140,
                    borderRadius: BorderRadius.circular(12),
                    buttonColor: Colors.white,
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.arrow_back, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Quay lại',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadFacilities,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _facilities.length,
        itemBuilder: (context, index) {
          final item = _facilities[index];
          return _FacilityTile(
            facility: item.facility,
            courts: item.courts,
            onCourtTap: (court) => _openScheduler(item.facility, court),
          );
        },
      ),
    );
  }

  Future<void> _openScheduler(Facility facility, Court court) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BookingSchedulerPage(
          sport: widget.sport,
          facility: facility,
          court: court,
        ),
      ),
    );
    if (!mounted) return;
    if (result == true) {
      await _showSnack('Đặt sân thành công');
    }
  }
}

class _FacilityTile extends StatefulWidget {
  final Facility facility;
  final List<Court> courts;
  final ValueChanged<Court> onCourtTap;

  const _FacilityTile({
    required this.facility,
    required this.courts,
    required this.onCourtTap,
  });

  @override
  State<_FacilityTile> createState() => _FacilityTileState();
}

class _FacilityTileState extends State<_FacilityTile> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final addressText = _formatAddress(widget.facility.address);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: NeuContainer(
        color: const Color(0xFFE6F3FF),
        borderColor: Colors.black,
        borderWidth: 3,
        borderRadius: BorderRadius.circular(16),
        shadowColor: Colors.black.withValues(alpha: 0.25),
        offset: const Offset(6, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => setState(() => _isExpanded = !_isExpanded),
              borderRadius: BorderRadius.circular(13),
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
                      child: const Icon(Icons.location_on, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.facility.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (addressText != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              addressText,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[700],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      _isExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 24,
                    ),
                  ],
                ),
              ),
            ),
            if (_isExpanded) ...[
              Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 16),
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
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: widget.courts
                      .map((court) => _buildCourtCard(context, court))
                      .toList(growable: false),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCourtCard(BuildContext context, Court court) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => widget.onCourtTap(court),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
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
              const Icon(Icons.sports_tennis, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      court.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    if (court.code != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Mã sân: ${court.code}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 20),
            ],
          ),
        ),
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
      if ((address.postalCode ?? '').trim().isNotEmpty)
        address.postalCode!.trim(),
    ];
    if (parts.isEmpty) return null;
    return parts.join(', ');
  }
}
