import 'dart:convert';

class StaffNotification {
  StaffNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.createdAt,
    this.channel,
    this.priority,
    this.status,
    this.read = false,
    this.readAt,
    Map<String, dynamic>? metadata,
  }) : metadata = metadata == null
           ? const <String, dynamic>{}
           : Map.unmodifiable(metadata);

  factory StaffNotification.fromJson(Map<String, dynamic> json) {
    String? parseString(dynamic value) {
      if (value == null) return null;
      if (value is String) return value;
      return value.toString();
    }

    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(
          value,
          isUtc: true,
        ).toLocal();
      }
      if (value is String && value.isNotEmpty) {
        try {
          return DateTime.parse(value).toLocal();
        } catch (_) {
          return null;
        }
      }
      return null;
    }

    final status = parseString(json['status'])?.toLowerCase();
    final read = (json['read'] == true || json['isRead'] == true) || status == 'read';

    return StaffNotification(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Thông báo',
      message: json['message']?.toString() ?? '',
      channel: parseString(json['channel'])?.toLowerCase(),
      priority: parseString(json['priority'])?.toLowerCase(),
      status: status,
      read: read,
      createdAt: parseDate(json['createdAt']) ?? DateTime.now(),
      readAt: parseDate(json['readAt']),
      metadata: json['metadata'] is Map
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : json['data'] is Map
              ? Map<String, dynamic>.from(json['data'] as Map)
              : const <String, dynamic>{},
    );
  }

  final String id;
  final String title;
  final String message;
  final String? channel;
  final String? priority;
  final String? status;
  final bool read;
  final DateTime createdAt;
  final DateTime? readAt;
  final Map<String, dynamic> metadata;

  StaffNotification copyWith({
    String? title,
    String? message,
    String? channel,
    String? priority,
    String? status,
    bool? read,
    DateTime? createdAt,
    DateTime? readAt,
    Map<String, dynamic>? metadata,
  }) {
    return StaffNotification(
      id: id,
      title: title ?? this.title,
      message: message ?? this.message,
      channel: channel ?? this.channel,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      read: read ?? this.read,
      createdAt: createdAt ?? this.createdAt,
      readAt: readAt ?? this.readAt,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'message': message,
      if (channel != null) 'channel': channel,
  if (priority != null) 'priority': priority,
  if (status != null) 'status': status,
      'read': read,
      'createdAt': createdAt.toIso8601String(),
      if (readAt != null) 'readAt': readAt?.toIso8601String(),
      if (metadata.isNotEmpty) 'metadata': jsonDecode(jsonEncode(metadata)),
    };
  }
}
