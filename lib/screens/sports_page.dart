import 'package:flutter/material.dart';
import '../models/sport.dart';
import '../services/api_service.dart';

/// Sports management page (CRUD)
class SportsPage extends StatefulWidget {
  const SportsPage({super.key});

  @override
  State<SportsPage> createState() => _SportsPageState();
}

class _SportsPageState extends State<SportsPage> {
  final _api = ApiService();
  bool _loading = false;
  List<Sport> _items = const [];
  String? _error;

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
      final data = await _api.adminGetSports(includeInactive: true);
      setState(() => _items = data);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addOrEdit({Sport? current}) async {
    final result = await showDialog<_SportFormResult>(
      context: context,
      builder: (_) => _SportDialog(initial: current),
    );
    if (result == null) return;
    setState(() => _loading = true);
    try {
      if (current == null) {
        await _api.adminCreateSport(
          name: result.name,
          code: result.code,
          teamSize: result.teamSize,
          active: true,
        );
      } else {
        await _api.adminUpdateSport(current.id, {
          'name': result.name,
          'code': result.code,
          'teamSize': result.teamSize,
        });
      }
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(current == null ? 'Đã thêm môn' : 'Đã cập nhật'),
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

  Future<void> _delete(Sport s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Xoá môn thể thao'),
        content: Text('Bạn có chắc muốn xoá "${s.name}"?'),
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
      await _api.adminDeleteSport(s.id);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã xoá')));
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
        title: const Text('Môn thể thao'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
            tooltip: 'Làm mới',
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : () => _addOrEdit(),
        icon: const Icon(Icons.add),
        label: const Text('Thêm môn'),
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
              const Icon(
                Icons.error_outline,
                color: Colors.redAccent,
                size: 32,
              ),
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
    if (_items.isEmpty) {
      return const Center(child: Text('Chưa có môn thể thao nào.'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final s = _items[index];
          return ListTile(
            title: Text(s.name),
            subtitle: Text(
              'Mã: ${s.code}${s.teamSize != null ? ' • Đội: ${s.teamSize}' : ''}${s.courtCount != null ? ' • Sân: ${s.courtCount}' : ''}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Sửa',
                  icon: const Icon(Icons.edit),
                  onPressed: _loading ? null : () => _addOrEdit(current: s),
                ),
                IconButton(
                  tooltip: 'Xoá',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _loading ? null : () => _delete(s),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SportFormResult {
  final String name;
  final String code;
  final int teamSize;
  _SportFormResult(this.name, this.code, this.teamSize);
}

class _SportDialog extends StatefulWidget {
  final Sport? initial;
  const _SportDialog({this.initial});

  @override
  State<_SportDialog> createState() => _SportDialogState();
}

class _SportDialogState extends State<_SportDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(
    text: widget.initial?.name ?? '',
  );
  late final TextEditingController _code = TextEditingController(
    text: widget.initial?.code ?? '',
  );
  late final TextEditingController _teamSize = TextEditingController(
    text: (widget.initial?.teamSize ?? 2).toString(),
  );

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _teamSize.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.initial == null ? 'Thêm môn thể thao' : 'Sửa môn thể thao',
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Tên'),
                autofocus: true,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Nhập tên' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _code,
                decoration: const InputDecoration(
                  labelText: 'Mã (ví dụ: FB, BD, ... )',
                ),
                textCapitalization: TextCapitalization.characters,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Nhập mã' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _teamSize,
                decoration: const InputDecoration(labelText: 'Số người/đội'),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Nhập số người/đội';
                  final n = int.tryParse(v);
                  if (n == null || n <= 0) return 'Giá trị không hợp lệ';
                  return null;
                },
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
            final n = int.parse(_teamSize.text);
            Navigator.pop(
              context,
              _SportFormResult(
                _name.text.trim(),
                _code.text.trim().toUpperCase(),
                n,
              ),
            );
          },
          child: Text(widget.initial == null ? 'Thêm' : 'Lưu'),
        ),
      ],
    );
  }
}
