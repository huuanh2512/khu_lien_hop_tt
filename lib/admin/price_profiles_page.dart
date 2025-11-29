import 'package:flutter/material.dart';
import 'package:khu_lien_hop_tt/models/court.dart';
import 'package:khu_lien_hop_tt/models/facility.dart';
import 'package:khu_lien_hop_tt/models/price_profile.dart';
import 'package:khu_lien_hop_tt/models/sport.dart';
import 'package:khu_lien_hop_tt/services/api_service.dart';
import 'package:khu_lien_hop_tt/widgets/sports_gradient_background.dart';

class PriceProfilesPage extends StatefulWidget {
  const PriceProfilesPage({super.key});

  @override
  State<PriceProfilesPage> createState() => _PriceProfilesPageState();
}

class _ProfileFormResult {
  final String? facilityId;
  final String? sportId;
  final String? courtId;
  final double baseRatePerHour;
  final double? taxPercent;
  final bool? active;

  _ProfileFormResult({
    required this.facilityId,
    required this.sportId,
    required this.courtId,
    required this.baseRatePerHour,
    this.taxPercent,
    this.active,
  });

  Map<String, dynamic> toPayload() => {
    if (facilityId != null) 'facilityId': facilityId,
    if (sportId != null) 'sportId': sportId,
    if (courtId != null) 'courtId': courtId,
    'currency': 'VND',
    'baseRatePerHour': baseRatePerHour,
    if (taxPercent != null) 'taxPercent': taxPercent,
    if (active != null) 'active': active,
    'rules': const <Map<String, dynamic>>[],
  };
}

class _ProfileDialog extends StatefulWidget {
  final String? facilityId;
  final String? sportId;
  final String? courtId;
  final PriceProfile? initial;
  const _ProfileDialog({
    this.facilityId,
    this.sportId,
    this.courtId,
    this.initial,
  });

  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _baseRate = TextEditingController(
    text: (widget.initial?.baseRatePerHour ?? 0).toString(),
  );
  late final TextEditingController _tax = TextEditingController(
    text: (() {
      final value = widget.initial?.taxPercent;
      return value == null ? '' : value.toString();
    })(),
  );
  late bool _active = widget.initial?.active ?? true;

  @override
  void dispose() {
    _baseRate.dispose();
    _tax.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Thêm/Cập nhật bảng giá'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _baseRate,
                decoration: const InputDecoration(
                  labelText: 'Giá cơ bản/giờ (VND)',
                ),
                keyboardType: TextInputType.number,
                validator: (v) =>
                    (double.tryParse(v ?? '') == null) ? 'Nhập số' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _tax,
                decoration: const InputDecoration(
                  labelText: 'Thuế % (tuỳ chọn)',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                value: _active,
                onChanged: (v) => setState(() => _active = v),
                title: const Text('Kích hoạt'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Huỷ'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              _ProfileFormResult(
                facilityId: widget.facilityId,
                sportId: widget.sportId,
                courtId: widget.courtId,
                baseRatePerHour: double.parse(_baseRate.text.trim()),
                taxPercent: _tax.text.trim().isEmpty
                    ? null
                    : double.tryParse(_tax.text.trim()),
                active: _active,
              ),
            );
          },
          child: const Text('Lưu'),
        ),
      ],
    );
  }
}

class _PriceProfilesPageState extends State<PriceProfilesPage> {
  final _api = ApiService();
  bool _loading = false;
  String? _error;

  List<Facility> _facilities = const [];
  List<Sport> _sports = const [];
  List<Court> _courts = const [];
  List<PriceProfile> _profiles = const [];

  Facility? _facility;
  String? _sportId;
  String? _courtId;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.adminGetFacilities(includeInactive: true),
        _api.adminGetSports(includeInactive: true),
      ]);
      _facilities = results[0] as List<Facility>;
      _sports = results[1] as List<Sport>;
      _facility = _facilities.isNotEmpty ? _facilities.first : null;
      if (_facility != null) {
        await _loadCourts();
      }
      await _loadProfiles();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadCourts() async {
    if (_facility == null) return;
    try {
      final list = await _api.adminGetCourtsByFacility(_facility!.id);
      setState(() => _courts = list);
    } catch (_) {}
  }

  Future<void> _loadProfiles() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _api.adminGetPriceProfiles(
        facilityId: _facility?.id,
        sportId: _sportId,
        courtId: _courtId,
      );
      setState(() => _profiles = list);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _openUpsert([PriceProfile? current]) async {
    final result = await showDialog<_ProfileFormResult>(
      context: context,
      builder: (_) => _ProfileDialog(
        facilityId: _facility?.id,
        sportId: _sportId,
        courtId: _courtId,
        initial: current,
      ),
    );
    if (result == null) return;
    setState(() => _loading = true);
    try {
      final payload = result.toPayload();
      await _api.adminUpsertPriceProfile(payload);
      await _loadProfiles();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã lưu bảng giá')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SportsGradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Bảng giá (Price Profiles)'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loading ? null : _loadProfiles,
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _loading ? null : () => _openUpsert(),
          icon: const Icon(Icons.add),
          label: const Text('Thêm/Upsert'),
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _facilities.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) return Center(child: Text('Lỗi: $_error'));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<Facility>(
                      initialValue: _facility,
                      items: _facilities
                          .map(
                            (f) =>
                                DropdownMenuItem(value: f, child: Text(f.name)),
                          )
                          .toList(),
                      decoration: const InputDecoration(labelText: 'Cơ sở'),
                      onChanged: (v) async {
                        setState(() {
                          _facility = v;
                          _courtId = null;
                        });
                        await _loadCourts();
                        await _loadProfiles();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      initialValue: _sportId,
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Tất cả môn'),
                        ),
                        ..._sports.map(
                          (s) => DropdownMenuItem<String?>(
                            value: s.id,
                            child: Text(s.name),
                          ),
                        ),
                      ],
                      decoration: const InputDecoration(labelText: 'Môn'),
                      onChanged: (v) async {
                        setState(() {
                          _sportId = v;
                          _courtId = null;
                        });
                        await _loadProfiles();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                initialValue: _courtId,
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Tất cả sân'),
                  ),
                  ..._courts.map(
                    (c) => DropdownMenuItem<String?>(
                      value: c.id,
                      child: Text(c.name),
                    ),
                  ),
                ],
                decoration: const InputDecoration(
                  labelText: 'Sân (nếu muốn giới hạn)',
                ),
                onChanged: (v) async {
                  setState(() => _courtId = v);
                  await _loadProfiles();
                },
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _profiles.isEmpty
              ? const Center(child: Text('Chưa có bảng giá'))
              : ListView.separated(
                  itemCount: _profiles.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final p = _profiles[i];
                    return ListTile(
                      title: Text(
                        p.name ?? 'Profile ${p.id.substring(p.id.length - 6)}',
                      ),
                      subtitle: Text(
                        'Base: ${p.baseRatePerHour.toStringAsFixed(2)} ${p.currency} · Thuế: ${p.taxPercent.toStringAsFixed(2)}% · ${p.active ? 'Active' : 'Inactive'}',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => _openUpsert(p),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
