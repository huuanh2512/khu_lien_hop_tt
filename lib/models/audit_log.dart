import 'dart:convert';

class AuditActor {
  final String? id;
  final String? role;

  const AuditActor({this.id, this.role});

  factory AuditActor.fromJson(Map<String, dynamic> json) {
    return AuditActor(
      id: json['id']?.toString(),
      role: json['role']?.toString(),
    );
  }
}

class AuditLog {
  final String id;
  final String action;
  final String resource;
  final String? resourceId;
  final bool success;
  final String? message;
  final AuditActor? actor;
  final DateTime? createdAt;
  final dynamic payload;
  final dynamic changes;
  final dynamic metadata;
  final String? ip;
  final String? userAgent;

  AuditLog({
    required this.id,
    required this.action,
    required this.resource,
    this.resourceId,
    required this.success,
    this.message,
    this.actor,
    this.createdAt,
    this.payload,
    this.changes,
    this.metadata,
    this.ip,
    this.userAgent,
  });

  factory AuditLog.fromJson(Map<String, dynamic> json) {
    return AuditLog(
      id: json['_id']?.toString() ?? '',
      action: json['action']?.toString() ?? 'unknown',
      resource: json['resource']?.toString() ?? 'unknown',
      resourceId: json['resourceId']?.toString(),
      success: json['success'] != false,
      message: json['message']?.toString(),
      actor: (json['actor'] is Map<String, dynamic>)
          ? AuditActor.fromJson(json['actor'] as Map<String, dynamic>)
          : null,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
      payload: json['payload'],
      changes: json['changes'],
      metadata: json['metadata'],
      ip: json['ip']?.toString(),
      userAgent: json['userAgent']?.toString(),
    );
  }

  String get formattedTimestamp {
    final ts = createdAt;
    if (ts == null) return '';
    return ts.toLocal().toString();
  }

  String describeActor() {
    if (actor == null) return 'Không rõ';
    final parts = <String>[];
    if (actor!.id != null && actor!.id!.isNotEmpty) parts.add(actor!.id!);
    if (actor!.role != null && actor!.role!.isNotEmpty) parts.add(actor!.role!);
    return parts.isEmpty ? 'Không rõ' : parts.join(' · ');
  }

  static String prettyJson(dynamic data) {
    if (data == null) return '—';
    try {
      return const JsonEncoder.withIndent('  ').convert(data);
    } catch (_) {
      return data.toString();
    }
  }
}
