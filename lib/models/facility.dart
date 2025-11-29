import '../utils/json_utils.dart';

List<String> _stringList(dynamic value) {
  if (value == null) return const [];
  if (value is List) {
    return value
        .map((item) => item == null ? '' : item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
  if (value is String) {
    return value
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
  }
  return const [];
}

Map<String, dynamic>? _mapOrNull(dynamic value) {
  if (value == null) return null;
  if (value is Map<String, dynamic>) return value;
  return null;
}

class FacilityAddress {
  final String? line1;
  final String? ward;
  final String? district;
  final String? city;
  final String? province;
  final String? country;
  final String? postalCode;
  final double? lat;
  final double? lng;

  const FacilityAddress({
    this.line1,
    this.ward,
    this.district,
    this.city,
    this.province,
    this.country,
    this.postalCode,
    this.lat,
    this.lng,
  });

  factory FacilityAddress.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const FacilityAddress();
    double? toDouble(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    return FacilityAddress(
      line1: json['line1']?.toString(),
      ward: json['ward']?.toString(),
      district: json['district']?.toString(),
      city: json['city']?.toString(),
      province: json['province']?.toString(),
      country: json['country']?.toString(),
      postalCode: json['postalCode']?.toString(),
      lat: toDouble(json['lat']),
      lng: toDouble(json['lng']),
    );
  }

  Map<String, dynamic> toJson() => {
    if (line1 != null && line1!.isNotEmpty) 'line1': line1,
    if (ward != null && ward!.isNotEmpty) 'ward': ward,
    if (district != null && district!.isNotEmpty) 'district': district,
    if (city != null && city!.isNotEmpty) 'city': city,
    if (province != null && province!.isNotEmpty) 'province': province,
    if (country != null && country!.isNotEmpty) 'country': country,
    if (postalCode != null && postalCode!.isNotEmpty) 'postalCode': postalCode,
    if (lat != null) 'lat': lat,
    if (lng != null) 'lng': lng,
  };
}

class Facility {
  final String id;
  final String name;
  final String? timeZone;
  final FacilityAddress address;
  final String? description;
  final List<String> amenities;
  final Map<String, dynamic>? openingHours;
  final List<String> images;
  final String? phone;
  final String? email;
  final String? website;
  final String? note;
  final String? status;

  const Facility({
    required this.id,
    required this.name,
    this.timeZone,
    this.address = const FacilityAddress(),
    this.description,
    this.amenities = const [],
    this.openingHours,
    this.images = const [],
    this.phone,
    this.email,
    this.website,
    this.note,
    this.status,
  });

  factory Facility.fromJson(Map<String, dynamic> json) {
    return Facility(
      id: JsonUtils.parseId(json['_id']),
      name: (json['name'] ?? '').toString(),
      timeZone: json['timeZone']?.toString(),
      address: FacilityAddress.fromJson(
        json['address'] as Map<String, dynamic>?,
      ),
      description: json['description']?.toString(),
      amenities: _stringList(json['amenities']),
      openingHours: _mapOrNull(json['openingHours']),
      images: _stringList(json['images']),
      phone: json['phone']?.toString(),
      email: json['email']?.toString(),
      website: json['website']?.toString(),
      note: json['note']?.toString(),
      status: json['status']?.toString(),
    );
  }
}
