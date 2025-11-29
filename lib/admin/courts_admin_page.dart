import 'package:flutter/material.dart';
import 'package:khu_lien_hop_tt/models/court.dart';
import 'package:khu_lien_hop_tt/models/facility.dart';
import 'package:khu_lien_hop_tt/models/sport.dart';
import 'package:khu_lien_hop_tt/services/api_service.dart';
import 'package:khu_lien_hop_tt/widgets/sports_gradient_background.dart';

class CourtsAdminPage extends StatefulWidget {
  const CourtsAdminPage({super.key});

  @override
  State<CourtsAdminPage> createState() => _CourtsAdminPageState();
}

class _CourtsAdminPageState extends State<CourtsAdminPage> {
  final _api = ApiService();
  bool _loading = false;
  String? _error;

  List<Facility> _facilities = const [];
  List<Sport> _sports = const [];
  List<Court> _courts = const [];

  Facility? _selectedFacility;
  String? _selectedSportId; // for creation/filter label only

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
      _selectedFacility = _facilities.isNotEmpty ? _facilities.first : null;
      if (_selectedFacility != null) {
        await _loadCourts();
      }
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
    if (_selectedFacility == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _api.adminGetCourtsByFacility(_selectedFacility!.id);
      setState(() => _courts = list);
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

  String sportName(String id) {
    final s = _sports
        .where((e) => e.id == id)
        .cast<Sport?>()
        .firstWhere((e) => e != null, orElse: () => null);
    return s?.name ?? id;
  }

  Future<void> _addOrEdit({Court? current}) async {
    final result = await showDialog<_CourtFormResult>(
      context: context,
      builder: (_) => _CourtDialog(
        sports: _sports,
        facility: _selectedFacility,
        initial: current,
        initialSportId: _selectedSportId,
      ),
    );
    if (result == null) return;
    setState(() => _loading = true);
    try {
      if (current == null) {
        await _api.adminCreateCourt(
          facilityId: _selectedFacility!.id,
          sportId: result.sportId,
          name: result.name,
          code: result.code?.isEmpty == true ? null : result.code,
          status: result.status,
        );
      } else {
        await _api.adminUpdateCourt(current.id, {
          'name': result.name,
          'code': result.code,
          'sportId': result.sportId,
          'status': result.status,
        });
      }
      await _loadCourts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(current == null ? 'Đã tạo sân' : 'Đã cập nhật sân'),
          ),
        );
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

  Future<void> _changeStatus(Court c, String status) async {
    setState(() => _loading = true);
    try {
      await _api.adminUpdateCourt(c.id, {'status': status});
      await _loadCourts();
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
          title: const Text('Quản lý Sân (Courts)'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loading ? null : _loadCourts,
            ),
          ],
        ),
        body: _buildBody(),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: (_loading || _selectedFacility == null)
              ? null
              : () => _addOrEdit(),
          icon: const Icon(Icons.add),
          label: const Text('Thêm sân'),
        ),
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
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<Facility>(
                  initialValue: _selectedFacility,
                  items: _facilities
                      .map(
                        (f) => DropdownMenuItem(value: f, child: Text(f.name)),
                      )
                      .toList(),
                  decoration: const InputDecoration(labelText: 'Chọn cơ sở'),
                  onChanged: (v) async {
                    setState(() {
                      _selectedFacility = v;
                      _selectedSportId = null;
                    });
                    await _loadCourts();
                  },
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 260,
                child: DropdownButtonFormField<String?>(
                  initialValue: _selectedSportId,
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
                  decoration: const InputDecoration(labelText: 'Lọc theo môn'),
                  onChanged: (v) => setState(() => _selectedSportId = v),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _courts.isEmpty
              ? const Center(child: Text('Chưa có sân nào'))
              : ListView.separated(
                  itemCount: _courts.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final c = _courts[i];
                    final isFilteredOut = _selectedSportId != null && c.sportId != _selectedSportId;
                    if (isFilteredOut) return const SizedBox.shrink();
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(c.name.isNotEmpty ? c.name[0].toUpperCase() : '?'),
                      ),
                      title: Text(c.name),
                      subtitle: Text(
                        [
                          if (c.code != null && c.code!.isNotEmpty) 'Mã: ${c.code}',
                          'Môn: ${sportName(c.sportId)}',
                          'Trạng thái: ${c.status}',
                        ].join(' · '),
                      ),
                      trailing: Wrap(
                        spacing: 8,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit),
                            tooltip: 'Sửa',
                            onPressed: _loading
                                ? null
                                : () => _addOrEdit(current: c),
                          ),
                          PopupMenuButton<String>(
                            tooltip: 'Đổi trạng thái',
                            onSelected: (v) => _changeStatus(c, v),
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'available',
                                child: Text('Available'),
                              ),
                              PopupMenuItem(
                                value: 'maintenance',
                                child: Text('Maintenance'),
                              ),
                              PopupMenuItem(
                                value: 'inactive',
                                child: Text('Inactive'),
                              ),
                            ],
                            child: const Icon(Icons.more_vert),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _CourtFormResult {
  final String sportId;
  final String name;
  final String? code;
  final String status;

  _CourtFormResult({
    required this.sportId,
    required this.name,
    this.code,
    required this.status,
  });
}

class _CourtDialog extends StatefulWidget {
  final List<Sport> sports;
  final Facility? facility;
  final Court? initial;
  final String? initialSportId;
  const _CourtDialog({
    required this.sports,
    required this.facility,
    this.initial,
    this.initialSportId,
  });

  @override
  State<_CourtDialog> createState() => _CourtDialogState();
}

class _CourtDialogState extends State<_CourtDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(
    text: widget.initial?.name ?? '',
  );
  late final TextEditingController _code = TextEditingController(
    text: widget.initial?.code ?? '',
  );
  String? _sportId;
  String _status = 'available';

  @override
  void initState() {
    super.initState();
    _sportId = widget.initial?.sportId ?? widget.initialSportId ?? (widget.sports.isNotEmpty ? widget.sports.first.id : null);
    _status = widget.initial?.status ?? 'available';
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Thêm sân mới' : 'Cập nhật sân'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.facility != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Cơ sở: ${widget.facility!.name}'),
              ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Tên sân'),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Nhập tên sân'
                  : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _code,
              decoration:
                  const InputDecoration(labelText: 'Mã sân (tuỳ chọn)'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _sportId,
              items: widget.sports
                  .map(
                    (s) => DropdownMenuItem(
                      value: s.id,
                      child: Text(s.name),
                    ),
                  )
                  .toList(),
              decoration: const InputDecoration(labelText: 'Môn'),
              onChanged: (v) => setState(() => _sportId = v),
              validator: (v) => v == null ? 'Chọn môn' : null,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _status,
              items: const [
                DropdownMenuItem(value: 'available', child: Text('Available')),
                DropdownMenuItem(value: 'maintenance', child: Text('Maintenance')),
                DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
              ],
              decoration: const InputDecoration(labelText: 'Trạng thái'),
              onChanged: (v) => setState(() => _status = v ?? 'available'),
            ),
          ],
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
              _CourtFormResult(
                sportId: _sportId!,
                name: _name.text.trim(),
                code: _code.text.trim().isEmpty ? null : _code.text.trim(),
                status: _status,
              ),
            );
          },
          child: const Text('Lưu'),
        ),
      ],
    );
  }
}
