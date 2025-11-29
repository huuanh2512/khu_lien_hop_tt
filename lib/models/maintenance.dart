import '../utils/json_utils.dart';

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    return parsed;
  }
  if (value is Map<String, dynamic>) {
    final iso = value[r'$date'] ?? value['date'];
    if (iso is String) return DateTime.tryParse(iso);
  }
  return null;
}

class Maintenance {
  final String id;
  final String facilityId;
  final String courtId;
  final String? status;
  final DateTime? start;
  final DateTime? end;
  final String? reason;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Maintenance({
    required this.id,
    required this.facilityId,
    required this.courtId,
    this.status,
    this.start,
    this.end,
    this.reason,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  factory Maintenance.fromJson(Map<String, dynamic> json) {
    return Maintenance(
      id: JsonUtils.parseId(json['_id']),
      facilityId: JsonUtils.parseId(json['facilityId']),
      courtId: JsonUtils.parseId(json['courtId']),
      status: json['status']?.toString(),
      start: _parseDate(json['start']),
      end: _parseDate(json['end']),
      reason: json['reason']?.toString(),
      createdBy: json['createdBy'] != null
          ? JsonUtils.parseId(json['createdBy'])
          : null,
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
    );
  }
}
