import 'package:flutter/material.dart';
import 'package:khu_lien_hop_tt/models/facility.dart';
import 'package:khu_lien_hop_tt/models/sport.dart';
import 'package:khu_lien_hop_tt/models/user.dart';
import 'package:khu_lien_hop_tt/services/api_service.dart';

class UsersPage extends StatefulWidget {
  const UsersPage({super.key});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  final _api = ApiService();
  bool _loading = false;
  String? _error;

  List<AppUser> _users = const [];
  List<Facility> _facilities = const [];
  List<Sport> _sports = const [];
  String? _role; // admin|staff|customer
  String? _status; // active|blocked|deleted
  final _qCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _qCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.adminGetUsers(
          role: _role,
          status: _status,
          q: _qCtrl.text.trim().isEmpty ? null : _qCtrl.text.trim(),
        ),
        _api.adminGetFacilities(includeInactive: true),
        _api.adminGetSports(includeInactive: true),
      ]);
      setState(() {
        _users = results[0] as List<AppUser>;
        _facilities = results[1] as List<Facility>;
        _sports = results[2] as List<Sport>;
      });
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

  Future<void> _createOrEdit({AppUser? current}) async {
    final result = await showDialog<_UserFormResult>(
      context: context,
      builder: (_) => _UserDialog(
        initial: current,
        facilities: _facilities,
        sports: _sports,
      ),
    );
    if (result == null) return;
    setState(() => _loading = true);
    try {
      if (current == null) {
        final created = await _api.adminCreateUser(
          email: result.email!,
          password: result.password!,
          name: result.name,
          role: result.role,
          status: result.status,
          facilityId: result.facilityId,
          phone: result.phone,
          gender: result.role == 'customer' ? result.gender : null,
          dateOfBirth:
              result.role == 'customer' ? result.dateOfBirth : null,
          mainSportId:
              result.role == 'customer' ? result.mainSportId : null,
        );
        final createdUser = AppUser.fromJson(created);
        setState(() {
          _users = [createdUser, ..._users];
        });
        await _load();
      } else {
        final updated = await _api.adminUpdateUser(
          current.id,
          name: result.name,
          phone: result.phone,
          role: result.role,
          status: result.status,
          resetPassword: result.password,
          facilityId: result.facilityId,
          gender: result.role == 'customer' ? result.gender : null,
          dateOfBirth:
              result.role == 'customer' ? result.dateOfBirth : null,
          mainSportId:
              result.role == 'customer' ? result.mainSportId : null,
        );
        setState(() {
          _users = [
            for (final u in _users)
              if (u.id == updated.id) updated else u,
          ];
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              current == null ? 'Đã tạo người dùng' : 'Đã cập nhật người dùng',
            ),
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

  Future<void> _delete(AppUser u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Xoá người dùng'),
        content: Text('Đánh dấu xoá người dùng ${u.email}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _loading = true);
    try {
      await _api.adminDeleteUser(u.id);
      setState(() {
        _users = [
          for (final user in _users)
            if (user.id != u.id) user,
        ];
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã xoá ${u.email}')),
        );
      }
      if (mounted) await _load();
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
        title: const Text('Người dùng (Users)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : () => _createOrEdit(),
        icon: const Icon(Icons.person_add),
        label: const Text('Thêm người dùng'),
      ),
      body: _buildBody(),
    );
  }

  String? _sportName(String? sportId) {
    if (sportId == null || sportId.isEmpty) return null;
    try {
      final sport = _sports.firstWhere((s) => s.id == sportId);
      return sport.name;
    } catch (_) {
      return sportId;
    }
  }

  String _formatGender(String? gender) {
    switch ((gender ?? '').toLowerCase()) {
      case 'male':
        return 'Nam';
      case 'female':
        return 'Nữ';
      case 'other':
        return 'Khác';
      default:
        return 'Không rõ';
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Không rõ';
    final local = date.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    return '$day/$month/${local.year}';
  }

  Widget _buildBody() {
    if (_loading && _users.isEmpty) {
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
                child: TextField(
                  controller: _qCtrl,
                  decoration: InputDecoration(
                    labelText: 'Tìm theo email/tên/điện thoại',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: _load,
                    ),
                  ),
                  onSubmitted: (_) => _load(),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 160,
                child: DropdownButtonFormField<String?>(
                  initialValue: _role,
                  items: const [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Tất cả vai trò'),
                    ),
                    DropdownMenuItem<String?>(
                      value: 'customer',
                      child: Text('Customer'),
                    ),
                    DropdownMenuItem<String?>(
                      value: 'staff',
                      child: Text('Staff'),
                    ),
                    DropdownMenuItem<String?>(
                      value: 'admin',
                      child: Text('Admin'),
                    ),
                  ],
                  decoration: const InputDecoration(labelText: 'Vai trò'),
                  onChanged: (v) {
                    setState(() => _role = v);
                    _load();
                  },
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 160,
                child: DropdownButtonFormField<String?>(
                  initialValue: _status,
                  items: const [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Tất cả trạng thái'),
                    ),
                    DropdownMenuItem<String?>(
                      value: 'active',
                      child: Text('Active'),
                    ),
                    DropdownMenuItem<String?>(
                      value: 'blocked',
                      child: Text('Blocked'),
                    ),
                    DropdownMenuItem<String?>(
                      value: 'deleted',
                      child: Text('Deleted'),
                    ),
                  ],
                  decoration: const InputDecoration(labelText: 'Trạng thái'),
                  onChanged: (v) {
                    setState(() => _status = v);
                    _load();
                  },
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _users.isEmpty
              ? const Center(child: Text('Chưa có người dùng'))
              : ListView.separated(
                  itemCount: _users.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final u = _users[i];
                    final facilityName =
                        (u.role == 'staff' && u.facilityId != null)
                            ? _facilities
                                .firstWhere(
                                  (f) => f.id == u.facilityId,
                                  orElse: () =>
                                      const Facility(id: '', name: ''),
                                )
                                .name
                            : null;
                    final lines = <String>[
                      'Email: ${u.email}',
                      if (u.phone != null && u.phone!.isNotEmpty)
                        'Điện thoại: ${u.phone}',
                    ];
                    final baseLine = StringBuffer(
                      'Vai trò: ${u.role} · Trạng thái: ${u.status}',
                    );
                    if (facilityName != null && facilityName.isNotEmpty) {
                      baseLine.write(' · Cơ sở: $facilityName');
                    }
                    lines.add(baseLine.toString());
                    if (u.role == 'customer') {
                      lines.add('Giới tính: ${_formatGender(u.gender)}');
                      lines.add('Ngày sinh: ${_formatDate(u.dateOfBirth)}');
                      final sportLabel = _sportName(u.mainSportId) ?? 'Không rõ';
                      lines.add('Môn chính: $sportLabel');
                    }
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          u.email.isNotEmpty
                              ? u.email[0].toUpperCase()
                              : '?',
                        ),
                      ),
                      title: Text(
                        u.name?.isNotEmpty == true ? u.name! : u.email,
                      ),
                      subtitle: Text(lines.join('\n')),
                      isThreeLine: true,
                      trailing: Wrap(
                        spacing: 8,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit),
                            tooltip: 'Sửa',
                            onPressed: _loading
                                ? null
                                : () => _createOrEdit(current: u),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Đánh dấu xoá',
                            onPressed: _loading ? null : () => _delete(u),
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

class _UserFormResult {
  final String? email; // required when creating
  final String? password; // required when creating; when editing = optional reset
  final String? name;
  final String role;
  final String status;
  final String? facilityId; // required when role=staff
  final String? phone;
  final String? gender;
  final DateTime? dateOfBirth;
  final String? mainSportId;

  _UserFormResult({
    this.email,
    this.password,
    this.name,
    required this.role,
    required this.status,
    this.facilityId,
    this.phone,
    this.gender,
    this.dateOfBirth,
    this.mainSportId,
  });
}

class _UserDialog extends StatefulWidget {
  final AppUser? initial;
  final List<Facility> facilities;
  final List<Sport> sports;
  const _UserDialog({
    this.initial,
    required this.facilities,
    required this.sports,
  });

  @override
  State<_UserDialog> createState() => _UserDialogState();
}

class _UserDialogState extends State<_UserDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _email = TextEditingController(
    text: widget.initial?.email ?? '',
  );
  late final TextEditingController _password = TextEditingController();
  late final TextEditingController _name = TextEditingController(
    text: widget.initial?.name ?? '',
  );
  late final TextEditingController _phone = TextEditingController(
    text: widget.initial?.phone ?? '',
  );
  late final TextEditingController _dateOfBirthText = TextEditingController();
  String _role = 'customer';
  String _status = 'active';
  String? _facilityId; // when role=staff
  String? _gender; // when role=customer
  DateTime? _dateOfBirth; // when role=customer
  String? _mainSportId; // when role=customer

  @override
  void initState() {
    super.initState();
    _role = widget.initial?.role ?? 'customer';
    _status = widget.initial?.status ?? 'active';
    _facilityId = widget.initial?.facilityId;
    _gender = widget.initial?.gender;
    _dateOfBirth = widget.initial?.dateOfBirth;
    _mainSportId = widget.initial?.mainSportId;
    _syncDobText();
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    _phone.dispose();
    _dateOfBirthText.dispose();
    super.dispose();
  }

  void _syncDobText() {
    if (_dateOfBirth == null) {
      _dateOfBirthText.text = '';
      return;
    }
    final date = _dateOfBirth!.toLocal();
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    _dateOfBirthText.text = '$day/$month/${date.year}';
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = _dateOfBirth ?? DateTime(now.year - 20, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) {
      setState(() {
        _dateOfBirth = picked;
        _syncDobText();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCreate = widget.initial == null;
    return AlertDialog(
      title: Text(isCreate ? 'Thêm người dùng' : 'Sửa người dùng'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _email,
                enabled: isCreate,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (v) => isCreate && (v == null || v.trim().isEmpty)
                    ? 'Nhập email'
                    : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _password,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: isCreate
                      ? 'Mật khẩu (>=6 ký tự)'
                      : 'Đặt lại mật khẩu (tùy chọn)',
                ),
                validator: (v) {
                  if (!isCreate) return null; // only required when creating
                  return (v == null || v.length < 6)
                      ? 'Mật khẩu tối thiểu 6 ký tự'
                      : null;
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Tên hiển thị (tuỳ chọn)',
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Số điện thoại (tuỳ chọn)',
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _role,
                items: const [
                  DropdownMenuItem(value: 'customer', child: Text('Customer')),
                  DropdownMenuItem(value: 'staff', child: Text('Staff')),
                  DropdownMenuItem(value: 'admin', child: Text('Admin')),
                ],
                decoration: const InputDecoration(labelText: 'Vai trò'),
                onChanged: (v) {
                  final nextRole = v ?? 'customer';
                  setState(() {
                    _role = nextRole;
                    if (nextRole != 'staff') {
                      _facilityId = null;
                    }
                    if (nextRole != 'customer') {
                      _gender = null;
                      _dateOfBirth = null;
                      _mainSportId = null;
                      _syncDobText();
                    }
                  });
                },
              ),
              const SizedBox(height: 8),
              if (_role == 'staff')
                DropdownButtonFormField<String?>(
                  initialValue: _facilityId,
                  items: [
                    ...widget.facilities.map(
                      (f) => DropdownMenuItem<String?>(
                        value: f.id,
                        child: Text(f.name),
                      ),
                    ),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Cơ sở (bắt buộc với Staff)',
                  ),
                  onChanged: (v) => setState(() => _facilityId = v),
                  validator: (v) {
                    if (_role == 'staff' && (v == null || v.isEmpty)) {
                      return 'Chọn cơ sở cho Staff';
                    }
                    return null;
                  },
                ),
              if (_role == 'staff') const SizedBox(height: 8),
              if (_role == 'customer') ...[
                DropdownButtonFormField<String?>(
                  initialValue: _gender,
                  decoration: const InputDecoration(labelText: 'Giới tính'),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: const Text('Không rõ'),
                    ),
                    DropdownMenuItem<String?>(
                      value: 'male',
                      child: const Text('Nam'),
                    ),
                    DropdownMenuItem<String?>(
                      value: 'female',
                      child: const Text('Nữ'),
                    ),
                    DropdownMenuItem<String?>(
                      value: 'other',
                      child: const Text('Khác'),
                    ),
                  ],
                  onChanged: (v) => setState(() => _gender = v),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _dateOfBirthText,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: 'Ngày sinh (DD/MM/YYYY)',
                    hintText: 'Chọn ngày sinh',
                    suffixIcon: _dateOfBirth == null
                        ? null
                        : IconButton(
                            tooltip: 'Xoá ngày sinh',
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              setState(() {
                                _dateOfBirth = null;
                                _syncDobText();
                              });
                            },
                          ),
                  ),
                  onTap: _pickDate,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  initialValue: _mainSportId,
                  decoration:
                      const InputDecoration(labelText: 'Môn thể thao chính'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Không rõ'),
                    ),
                    ...widget.sports.map(
                      (s) => DropdownMenuItem<String?>(
                        value: s.id,
                        child: Text(s.name),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _mainSportId = v),
                ),
                const SizedBox(height: 8),
              ],
              DropdownButtonFormField<String>(
                initialValue: _status,
                items: const [
                  DropdownMenuItem(value: 'active', child: Text('Active')),
                  DropdownMenuItem(value: 'blocked', child: Text('Blocked')),
                  DropdownMenuItem(value: 'deleted', child: Text('Deleted')),
                ],
                decoration: const InputDecoration(labelText: 'Trạng thái'),
                onChanged: (v) => setState(() => _status = v ?? 'active'),
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
              _UserFormResult(
                email: isCreate ? _email.text.trim() : null,
                password: _password.text.trim().isEmpty
                    ? null
                    : _password.text.trim(),
                name: _name.text.trim().isEmpty ? null : _name.text.trim(),
                role: _role,
                status: _status,
                facilityId: _role == 'staff' ? _facilityId : null,
                phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
                gender: _role == 'customer' ? _gender : null,
                dateOfBirth: _role == 'customer' ? _dateOfBirth : null,
                mainSportId: _role == 'customer' ? _mainSportId : null,
              ),
            );
          },
          child: Text(isCreate ? 'Thêm' : 'Lưu'),
        ),
      ],
    );
  }
}
