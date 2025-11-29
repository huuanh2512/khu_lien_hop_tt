import 'package:flutter/material.dart';
import 'package:khu_lien_hop_tt/models/audit_log.dart';
import 'package:khu_lien_hop_tt/services/api_service.dart';

class AuditLogsPage extends StatefulWidget {
  const AuditLogsPage({super.key});

  @override
  State<AuditLogsPage> createState() => _AuditLogsPageState();
}

class _AuditLogsPageState extends State<AuditLogsPage> {
  final _api = ApiService();
  final _actionCtrl = TextEditingController();
  final _resourceCtrl = TextEditingController();
  final _actorCtrl = TextEditingController();

  bool _loading = false;
  String? _error;
  int _limit = 100;
  List<AuditLog> _logs = const <AuditLog>[];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _actionCtrl.dispose();
    _resourceCtrl.dispose();
    _actorCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final action = _actionCtrl.text.trim().isEmpty
          ? null
          : _actionCtrl.text.trim();
      final resource = _resourceCtrl.text.trim().isEmpty
          ? null
          : _resourceCtrl.text.trim();
      final actorId = _actorCtrl.text.trim().isEmpty
          ? null
          : _actorCtrl.text.trim();
      final logs = await _api.adminGetAuditLogs(
        limit: _limit,
        action: action,
        resource: resource,
        actorId: actorId,
      );
      if (!mounted) return;
      setState(() {
        _logs = logs;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (showSpinner && mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _showDetails(AuditLog log) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          builder: (_, controller) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: ListView(
                controller: controller,
                children: [
                  Text(
                    '${log.action.toUpperCase()} · ${log.resource}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text('Thời gian: ${log.formattedTimestamp}'),
                  Text('Người thực hiện: ${log.describeActor()}'),
                  if (log.resourceId != null)
                    Text('Mã đối tượng: ${log.resourceId}'),
                  if (log.ip != null) Text('IP: ${log.ip}'),
                  if (log.userAgent != null)
                    Text('User-Agent: ${log.userAgent}'),
                  if (log.message != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('Ghi chú: ${log.message}'),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    'Payload',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  SelectableText(AuditLog.prettyJson(log.payload)),
                  const SizedBox(height: 16),
                  Text(
                    'Kết quả/Changes',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  SelectableText(AuditLog.prettyJson(log.changes)),
                  const SizedBox(height: 16),
                  Text(
                    'Metadata',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  SelectableText(AuditLog.prettyJson(log.metadata)),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lịch sử thao tác'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : () => _fetch(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _actionCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Lọc theo action',
                          hintText: 'vd: create, update',
                        ),
                        onSubmitted: (_) => _fetch(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _resourceCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Lọc theo resource',
                          hintText: 'vd: user, booking',
                        ),
                        onSubmitted: (_) => _fetch(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _actorCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Actor ID',
                          hintText: 'userId nếu có',
                        ),
                        onSubmitted: (_) => _fetch(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    DropdownButton<int>(
                      value: _limit,
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _limit = value);
                        _fetch();
                      },
                      items: const [50, 100, 200, 500]
                          .map(
                            (e) => DropdownMenuItem<int>(
                              value: e,
                              child: Text('Hiển thị $e'),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _loading ? null : () => _fetch(),
                      icon: const Icon(Icons.filter_alt),
                      label: const Text('Áp dụng'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_error != null) {
      return Center(child: Text('Lỗi: $_error'));
    }
    if (_loading && _logs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_logs.isEmpty) {
      return const Center(child: Text('Chưa có log nào phù hợp'));
    }
    return RefreshIndicator(
      onRefresh: () => _fetch(showSpinner: false),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _logs.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final log = _logs[index];
          final successIcon = log.success
              ? Icons.check_circle
              : Icons.error_outline;
          final successColor = log.success ? Colors.green : Colors.orange;
          return ListTile(
            leading: Icon(successIcon, color: successColor),
            title: Text('${log.action.toUpperCase()} · ${log.resource}'),
            subtitle: Text(
              '${log.formattedTimestamp}\nNgười thực hiện: ${log.describeActor()}',
            ),
            isThreeLine: true,
            onTap: () => _showDetails(log),
            trailing: const Icon(Icons.chevron_right),
          );
        },
      ),
    );
  }
}
