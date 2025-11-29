import '../utils/json_utils.dart';

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is Map) {
    final rawDate = value[r'$date'] ?? value['date'];
    if (rawDate is String) {
      final parsed = DateTime.tryParse(rawDate);
      if (parsed != null) return parsed;
    }
    if (value['seconds'] is num) {
      final seconds = (value['seconds'] as num).toDouble();
      return DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round());
    }
  }
  if (value is String) {
    if (value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
  final text = value.toString();
  if (text.isEmpty) return null;
  return DateTime.tryParse(text);
}

class StaffProfileFacilityAddress {
  final String? line1;
  final String? ward;
  final String? district;
  final String? city;
  final String? province;
  final String? country;
  final String? postalCode;

  const StaffProfileFacilityAddress({
    this.line1,
    this.ward,
    this.district,
    this.city,
    this.province,
    this.country,
    this.postalCode,
  });

  factory StaffProfileFacilityAddress.fromJson(Map<String, dynamic> json) {
    return StaffProfileFacilityAddress(
      line1: json['line1']?.toString(),
      ward: json['ward']?.toString(),
      district: json['district']?.toString(),
      city: json['city']?.toString(),
      province: json['province']?.toString(),
      country: json['country']?.toString(),
      postalCode: json['postalCode']?.toString(),
    );
  }

  bool get isEmpty {
  return [line1, ward, district, city, province, country, postalCode]
    .whereType<String>()
    .where((value) => value.trim().isNotEmpty)
    .isEmpty;
  }
}

class StaffProfileOpeningHours {
  final String? open;
  final String? close;

  const StaffProfileOpeningHours({this.open, this.close});

  factory StaffProfileOpeningHours.fromJson(Map<String, dynamic> json) {
    final openValue = json['open']?.toString();
    final closeValue = json['close']?.toString();
    return StaffProfileOpeningHours(open: openValue, close: closeValue);
  }

  bool get isEmpty {
  final hasOpen = open != null && open!.trim().isNotEmpty;
  final hasClose = close != null && close!.trim().isNotEmpty;
  return !hasOpen && !hasClose;
  }
}

class StaffProfileFacilitySummary {
  final String? id;
  final String? name;
  final String? phone;
  final String? email;
  final StaffProfileOpeningHours? openingHours;
  final StaffProfileFacilityAddress? address;

  const StaffProfileFacilitySummary({
    this.id,
    this.name,
    this.phone,
    this.email,
    this.openingHours,
    this.address,
  });

  factory StaffProfileFacilitySummary.fromJson(Map<String, dynamic> json) {
    final opening = json['openingHours'];
    final address = json['address'];
    return StaffProfileFacilitySummary(
      id: JsonUtils.parseIdOrNull(json['id']),
      name: json['name']?.toString(),
      phone: json['phone']?.toString(),
      email: json['email']?.toString(),
      openingHours: opening is Map<String, dynamic>
          ? StaffProfileOpeningHours.fromJson(opening)
          : null,
      address: address is Map<String, dynamic>
          ? StaffProfileFacilityAddress.fromJson(address)
          : null,
    );
  }
}

class StaffProfile {
  final String? id;
  final String? name;
  final String? email;
  final String? phone;
  final String? role;
  final String? facilityId;
  final StaffProfileFacilitySummary? facility;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const StaffProfile({
    this.id,
    this.name,
    this.email,
    this.phone,
    this.role,
    this.facilityId,
    this.facility,
    this.createdAt,
    this.updatedAt,
  });

  factory StaffProfile.fromJson(Map<String, dynamic> json) {
    final facilityJson = json['facility'];
    return StaffProfile(
      id: JsonUtils.parseIdOrNull(json['id'] ?? json['_id']),
      name: json['name']?.toString(),
      email: json['email']?.toString(),
      phone: json['phone']?.toString(),
      role: json['role']?.toString(),
      facilityId: JsonUtils.parseIdOrNull(json['facilityId']),
      facility: facilityJson is Map<String, dynamic>
          ? StaffProfileFacilitySummary.fromJson(facilityJson)
          : null,
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
    );
  }

  StaffProfile copyWith({
    String? name,
    String? email,
    String? phone,
    StaffProfileFacilitySummary? facility,
    String? facilityId,
    DateTime? updatedAt,
  }) {
    return StaffProfile(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role,
      facilityId: facilityId ?? this.facilityId,
      facility: facility ?? this.facility,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
