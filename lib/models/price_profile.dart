import '../utils/json_utils.dart';

class PriceProfile {
  final String id;
  final String? name;
  final String? facilityId;
  final String? sportId;
  final String? courtId;
  final String currency;
  final double baseRatePerHour;
  final double taxPercent;
  final bool active;

  const PriceProfile({
    required this.id,
    this.name,
    this.facilityId,
    this.sportId,
    this.courtId,
    required this.currency,
    required this.baseRatePerHour,
    required this.taxPercent,
    required this.active,
  });

  factory PriceProfile.fromJson(Map<String, dynamic> json) {
    double toDouble(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '0') ?? 0;
    return PriceProfile(
      id: JsonUtils.parseId(json['_id']),
      name: json['name']?.toString(),
      facilityId: JsonUtils.parseIdOrNull(json['facilityId']),
      sportId: JsonUtils.parseIdOrNull(json['sportId']),
      courtId: JsonUtils.parseIdOrNull(json['courtId']),
      currency: (json['currency'] ?? 'VND').toString(),
      baseRatePerHour: toDouble(json['baseRatePerHour']),
      taxPercent: toDouble(json['taxPercent']),
      active: json['active'] != false,
    );
  }
}
