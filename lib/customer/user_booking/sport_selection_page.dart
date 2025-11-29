import 'package:flutter/material.dart';
import 'package:neubrutalism_ui/neubrutalism_ui.dart';

import 'package:khu_lien_hop_tt/models/sport.dart';
import 'package:khu_lien_hop_tt/services/user_booking_service.dart';
import 'package:khu_lien_hop_tt/widgets/neu_button.dart';

import 'package:khu_lien_hop_tt/customer/user_booking/facility_court_page.dart';

class UserBookingSportSelectionPage extends StatefulWidget {
  const UserBookingSportSelectionPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<UserBookingSportSelectionPage> createState() => _UserBookingSportSelectionPageState();
}

class _UserBookingSportSelectionPageState extends State<UserBookingSportSelectionPage> {
  final UserBookingService _service = UserBookingService();
  List<Sport> _sports = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSports();
  }

  Future<void> _loadSports() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sports = await _service.fetchSports();
      if (!mounted) return;
      setState(() {
        _sports = sports;
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
    if (widget.embedded) {
      return SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Chọn môn thể thao',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Làm mới',
                    onPressed: _loading ? null : _loadSports,
                    icon: const Icon(Icons.refresh),
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
        title: const Text('Chọn môn thể thao'),
        actions: [
          IconButton(
            tooltip: 'Làm mới',
            onPressed: _loading ? null : _loadSports,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: body,
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
                    'Không thể tải danh sách môn thể thao',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  NeuButton(
                    buttonHeight: 48,
                    buttonWidth: 140,
                    borderRadius: BorderRadius.circular(12),
                    buttonColor: Theme.of(context).colorScheme.primary,
                    onPressed: _loadSports,
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
    if (_sports.isEmpty) {
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
                children: const [
                  Icon(Icons.sports, size: 48),
                  SizedBox(height: 12),
                  Text(
                    'Chưa có môn thể thao nào khả dụng.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadSports,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _sports.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final sport = _sports[index];
          final colors = [
            const Color(0xFFE6F3FF), // Light blue
            const Color(0xFFE8F5E9), // Light green
            const Color(0xFFFFF8DC), // Cream
            const Color(0xFFFFE5E5), // Light pink
            const Color(0xFFF3E5F5), // Light purple
          ];
          final color = colors[index % colors.length];
          
          return InkWell(
            onTap: () => _openFacilities(context, sport),
            borderRadius: BorderRadius.circular(13),
            child: NeuContainer(
              color: color,
              borderColor: Colors.black,
              borderWidth: 3,
              borderRadius: BorderRadius.circular(16),
              shadowColor: Colors.black.withValues(alpha: 0.25),
              offset: const Offset(5, 5),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
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
                      child: const Icon(
                        Icons.sports_tennis,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sport.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.black, width: 1.5),
                            ),
                            child: Text(
                              sport.code.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.chevron_right,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openFacilities(BuildContext context, Sport sport) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FacilityCourtSelectionPage(sport: sport),
      ),
    );
  }
}
