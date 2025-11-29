import '../utils/json_utils.dart';

class AppUser {
  final String id;
  final String email;
  final String? name;
  final String role; // admin | staff | customer
  final String status; // active | blocked | deleted
  final String? phone;
  final String? facilityId; // required when role=staff
  final DateTime? dateOfBirth; // customer only
  final String? gender; // customer only
  final String? mainSportId; // customer only

  const AppUser({
    required this.id,
    required this.email,
    this.name,
    required this.role,
    required this.status,
    this.phone,
    this.facilityId,
    this.dateOfBirth,
    this.gender,
    this.mainSportId,
  });

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) {
      if (value.trim().isEmpty) return null;
      return DateTime.tryParse(value.trim());
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is Map) {
      final raw = value[r'$date'] ?? value['date'] ?? value['value'];
      if (raw is String) {
        final parsed = DateTime.tryParse(raw);
        if (parsed != null) return parsed;
      }
      if (value['seconds'] is num) {
        final seconds = (value['seconds'] as num).toDouble();
        return DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round());
      }
    }
    return null;
  }

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: JsonUtils.parseId(json['_id'] ?? json['id']),
      email: (json['email'] ?? '').toString(),
      name: json['name']?.toString(),
      role: (json['role'] ?? 'customer').toString().trim().toLowerCase(),
      status: (json['status'] ?? 'active').toString().trim().toLowerCase(),
      phone: json['phone']?.toString(),
      facilityId: JsonUtils.parseIdOrNull(json['facilityId']),
      dateOfBirth: _parseDate(json['dateOfBirth']),
      gender: json['gender']?.toString().trim().toLowerCase(),
      mainSportId: JsonUtils.parseIdOrNull(json['mainSportId']),
    );
  }

  AppUser copyWith({
    String? id,
    String? email,
    String? name,
    String? role,
    String? status,
    String? phone,
    String? facilityId,
    DateTime? dateOfBirth,
    String? gender,
    String? mainSportId,
  }) {
    return AppUser(
      id: id ?? this.id,
      email: email ?? this.email,
      name: name ?? this.name,
      role: role ?? this.role,
      status: status ?? this.status,
      phone: phone ?? this.phone,
      facilityId: facilityId ?? this.facilityId,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      gender: gender ?? this.gender,
      mainSportId: mainSportId ?? this.mainSportId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'email': email,
      'name': name,
      'role': role,
      'status': status,
      'phone': phone,
      'facilityId': facilityId,
      'dateOfBirth': dateOfBirth?.toIso8601String(),
      'gender': gender,
      'mainSportId': mainSportId,
    };
  }
}
