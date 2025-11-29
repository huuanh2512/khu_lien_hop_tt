import 'package:flutter/material.dart';
import '../models/facility.dart';
import '../services/api_service.dart';
import '../models/user.dart';

class FacilitiesPage extends StatefulWidget {
  const FacilitiesPage({super.key});

  @override
  State<FacilitiesPage> createState() => _FacilitiesPageState();
}

class _FacilitiesPageState extends State<FacilitiesPage> {
  final _api = ApiService();
  bool _loading = false;
  List<Facility> _items = const [];
  String? _error;
  Map<String, AppUser> _staffByFacility = const {};
  List<AppUser> _staffList = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.adminGetFacilities(includeInactive: true),
        _api.adminGetUsers(role: 'staff'),
      ]);
      final facilities = results[0] as List<Facility>;
      final staff = results[1] as List<AppUser>;
      final map = <String, AppUser>{};
      for (final u in staff) {
        if (u.facilityId != null && u.facilityId!.isNotEmpty) {
          map[u.facilityId!] = u;
        }
      }
      setState(() {
        _items = facilities;
        _staffByFacility = map;
        _staffList = staff;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addOrEdit({Facility? current}) async {
    final r = await showDialog<_FacilityFormResult>(
      context: context,
      builder: (_) => _FacilityDialog(initial: current, staffList: _staffList),
    );
    if (r == null) return;
    setState(() => _loading = true);
    try {
      final address = {
        if (r.line1 != null) 'line1': r.line1,
        if (r.ward != null) 'ward': r.ward,
        if (r.district != null) 'district': r.district,
        if (r.city != null) 'city': r.city,
        if (r.province != null) 'province': r.province,
      };
      if (current == null) {
        final created = await _api.adminCreateFacility(
          name: r.name,
          active: true,
          address: address.isEmpty ? null : address,
        );
        final newId = (created['_id'] ?? '').toString();
        if (r.staffUserId != null && r.staffUserId!.isNotEmpty) {
          await _api.adminUpdateUser(
            r.staffUserId!,
            role: 'staff',
            facilityId: newId,
          );
        }
      } else {
        final updates = {
          'name': r.name,
          if (address.isNotEmpty) 'address': address,
        };
        await _api.adminUpdateFacility(current.id, updates);
      }
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(current == null ? 'Đã tạo cơ sở' : 'Đã cập nhật'),
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

  Future<void> _delete(Facility fac) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Xoá cơ sở'),
        content: Text('Thiết lập cơ sở "${fac.name}" thành không hoạt động?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _loading = true);
    try {
      await _api.adminDeleteFacility(fac.id);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã cập nhật trạng thái')));
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Khu liên hợp (Facilities)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : () => _addOrEdit(),
        icon: const Icon(Icons.add_business),
        label: const Text('Thêm cơ sở'),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent),
              const SizedBox(height: 8),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) return const Center(child: Text('Chưa có cơ sở nào.'));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final f = _items[i];
          final staff = _staffByFacility[f.id];
          return ListTile(
            leading: const Icon(Icons.location_city),
            title: Text(f.name),
            subtitle: Text(_subtitleForFacility(f, staff)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.badge_outlined),
                  tooltip: 'Gán/Đổi nhân sự',
                  onPressed: _loading ? null : () => _assignStaff(f),
                ),
                IconButton(
                  icon: const Icon(Icons.edit),
                  tooltip: 'Sửa',
                  onPressed: _loading ? null : () => _addOrEdit(current: f),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Đặt không hoạt động',
                  onPressed: _loading ? null : () => _delete(f),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _assignStaff(Facility f) async {
    final current = _staffByFacility[f.id];
    final result = await showDialog<_AssignStaffResult>(
      context: context,
      builder: (_) => _AssignStaffDialog(
        facility: f,
        staffList: _staffList,
        currentStaffId: current?.id,
      ),
    );
    if (result == null) return;
    setState(() => _loading = true);
    try {
      // If selecting none: demote current staff to customer to safely unassign
      if (result.userId == null) {
        if (current != null) {
          await _api.adminUpdateUser(
            current.id,
            role: 'customer',
            facilityId: '',
          );
        }
      } else {
        // Try assign the selected user first. If conflict, unassign previous then retry once.
        Future<void> assignSelected() async {
          await _api.adminUpdateUser(
            result.userId!,
            role: 'staff',
            facilityId: f.id,
          );
        }

        try {
          await assignSelected();
        } catch (e) {
          final msg = e.toString();
          final isConflict =
              msg.contains('409') || msg.contains('Duplicate key');
          if (isConflict && current != null && current.id != result.userId) {
            // Demote previous to free the facility, then retry
            await _api.adminUpdateUser(
              current.id,
              role: 'customer',
              facilityId: '',
            );
            await assignSelected();
          } else {
            rethrow;
          }
        }
      }
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã cập nhật nhân sự')));
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
}

class _FacilityFormResult {
  final String name;
  final String? staffUserId; // only used on create
  final String? line1;
  final String? ward;
  final String? district;
  final String? city;
  final String? province;
  _FacilityFormResult(
    this.name, {
    this.staffUserId,
    this.line1,
    this.ward,
    this.district,
    this.city,
    this.province,
  });
}

class _FacilityDialog extends StatefulWidget {
  final Facility? initial;
  final List<AppUser> staffList;
  const _FacilityDialog({this.initial, required this.staffList});

  @override
  State<_FacilityDialog> createState() => _FacilityDialogState();
}

class _FacilityDialogState extends State<_FacilityDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(
    text: widget.initial?.name ?? '',
  );
  // Address controllers
  late final TextEditingController _line1 = TextEditingController(
    text: widget.initial?.address.line1 ?? '',
  );
  late final TextEditingController _ward = TextEditingController(
    text: widget.initial?.address.ward ?? '',
  );
  late final TextEditingController _district = TextEditingController(
    text: widget.initial?.address.district ?? '',
  );
  late final TextEditingController _city = TextEditingController(
    text: widget.initial?.address.city ?? '',
  );
  late final TextEditingController _province = TextEditingController(
    text: widget.initial?.address.province ?? '',
  );
  String? _selectedStaffId; // only when creating

  @override
  void dispose() {
    _name.dispose();
    _line1.dispose();
    _ward.dispose();
    _district.dispose();
    _city.dispose();
    _province.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Thêm cơ sở' : 'Sửa cơ sở'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Tên cơ sở'),
                autofocus: true,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Nhập tên' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _line1,
                decoration: const InputDecoration(
                  labelText: 'Địa chỉ (Số nhà, đường)',
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _ward,
                      decoration: const InputDecoration(labelText: 'Phường/Xã'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _district,
                      decoration: const InputDecoration(
                        labelText: 'Quận/Huyện',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _city,
                      decoration: const InputDecoration(labelText: 'Thành phố'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _province,
                      decoration: const InputDecoration(labelText: 'Tỉnh'),
                    ),
                  ),
                ],
              ),
              if (widget.initial == null) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: _selectedStaffId,
                  decoration: const InputDecoration(
                    labelText: 'Chọn nhân sự (tuỳ chọn)',
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('— Không ai —'),
                    ),
                    ...widget.staffList.map(
                      (u) => DropdownMenuItem<String?>(
                        value: u.id,
                        child: Text(
                          u.name?.isNotEmpty == true
                              ? '${u.name} (${u.email})'
                              : u.email,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _selectedStaffId = v),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Múi giờ mặc định: Asia/Ho_Chi_Minh',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
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
              _FacilityFormResult(
                _name.text.trim(),
                staffUserId: _selectedStaffId,
                line1: _line1.text.trim().isEmpty ? null : _line1.text.trim(),
                ward: _ward.text.trim().isEmpty ? null : _ward.text.trim(),
                district: _district.text.trim().isEmpty
                    ? null
                    : _district.text.trim(),
                city: _city.text.trim().isEmpty ? null : _city.text.trim(),
                province: _province.text.trim().isEmpty
                    ? null
                    : _province.text.trim(),
              ),
            );
          },
          child: Text(widget.initial == null ? 'Thêm' : 'Lưu'),
        ),
      ],
    );
  }
}

String _formatSubtitle(Facility f) {
  final parts = <String>[];
  if (f.timeZone != null && f.timeZone!.isNotEmpty) parts.add(f.timeZone!);
  final a = f.address;
  final addr = <String?>[a.line1, a.ward, a.district, a.city, a.province]
      .where((e) => e != null && e.trim().isNotEmpty)
      .map((e) => e!.trim())
      .join(', ');
  if (addr.isNotEmpty) parts.add(addr);
  return parts.isEmpty ? '' : parts.join(' · ');
}

String _subtitleForFacility(Facility f, AppUser? staff) {
  final base = _formatSubtitle(f);
  final staffText = staff == null
      ? 'Chưa gán'
      : (staff.name?.isNotEmpty == true ? staff.name! : staff.email);
  return base.isEmpty ? 'Nhân sự: $staffText' : '$base · Nhân sự: $staffText';
}

class _AssignStaffResult {
  final String? userId; // null = unassign
  const _AssignStaffResult(this.userId);
}

class _AssignStaffDialog extends StatefulWidget {
  final Facility facility;
  final List<AppUser> staffList;
  final String? currentStaffId;
  const _AssignStaffDialog({
    required this.facility,
    required this.staffList,
    this.currentStaffId,
  });

  @override
  State<_AssignStaffDialog> createState() => _AssignStaffDialogState();
}

class _AssignStaffDialogState extends State<_AssignStaffDialog> {
  String? _selectedId; // null means unassign

  @override
  void initState() {
    super.initState();
    _selectedId = widget.currentStaffId; // preselect current staff
  }

  @override
  Widget build(BuildContext context) {
    final items = <DropdownMenuItem<String?>>[
      const DropdownMenuItem<String?>(value: null, child: Text('— Không ai —')),
      ...widget.staffList.map((u) {
        final label = u.name?.isNotEmpty == true
            ? '${u.name} (${u.email})'
            : u.email;
        final tag =
            (u.facilityId != null &&
                u.facilityId!.isNotEmpty &&
                u.facilityId != widget.facility.id)
            ? ' • đang gán cơ sở khác'
            : '';
        return DropdownMenuItem<String?>(
          value: u.id,
          child: Text('$label$tag'),
        );
      }),
    ];
    return AlertDialog(
      title: Text('Gán/Đổi nhân sự cho "${widget.facility.name}"'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String?>(
            initialValue: _selectedId,
            items: items,
            decoration: const InputDecoration(labelText: 'Chọn nhân sự'),
            onChanged: (v) => setState(() => _selectedId = v),
          ),
          const SizedBox(height: 8),
          const Text(
            'Lưu ý: mỗi cơ sở chỉ có 1 nhân sự. Nếu chọn nhân sự đang gán cho cơ sở khác, họ sẽ được chuyển sang cơ sở này.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Huỷ'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, _AssignStaffResult(_selectedId)),
          child: const Text('Lưu'),
        ),
      ],
    );
  }
}
