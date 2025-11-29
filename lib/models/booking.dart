import '../utils/json_utils.dart';

class Booking {
  final String id;
  final String customerId;
  final String facilityId;
  final String sportId;
  final String courtId;
  final String? facilityName;
  final String? courtName;
  final String? sportName;
  final DateTime start;
  final DateTime end;
  final String status; // pending | confirmed | cancelled | deleted
  final String currency;
  final double? total;
  final Map<String, dynamic>? pricingSnapshot;
  final List<String>? participants;
  final String? voucherId;

  const Booking({
    required this.id,
    required this.customerId,
    required this.facilityId,
    required this.sportId,
    required this.courtId,
  this.facilityName,
  this.courtName,
  this.sportName,
    required this.start,
    required this.end,
    required this.status,
    required this.currency,
    this.total,
    this.pricingSnapshot,
    this.participants,
    this.voucherId,
  });

  factory Booking.fromJson(Map<String, dynamic> json) {
    double? toDouble(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    DateTime toDT(dynamic v) {
      DateTime parsed;
      if (v is String && v.isNotEmpty) {
        parsed = DateTime.tryParse(v) ?? DateTime.fromMillisecondsSinceEpoch(0);
      } else if (v is DateTime) {
        parsed = v;
      } else if (v is int) {
        parsed = DateTime.fromMillisecondsSinceEpoch(v);
      } else {
        parsed = DateTime.fromMillisecondsSinceEpoch(0);
      }
      return parsed.toLocal();
    }

    final snapRaw = json['pricingSnapshot'];
    final Map<String, dynamic>? snap = snapRaw is Map<String, dynamic>
        ? snapRaw
        : (snapRaw is Map ? snapRaw.cast<String, dynamic>() : null);

    final List<String>? participants = (json['participants'] is List)
        ? (json['participants'] as List).map((e) => e.toString()).toList()
        : null;

    String? toOptString(dynamic v) {
      if (v == null) return null;
      final text = v.toString().trim();
      return text.isEmpty ? null : text;
    }

    return Booking(
      id: JsonUtils.parseId(json['_id']),
      customerId: JsonUtils.parseId(json['customerId']),
      facilityId: JsonUtils.parseId(json['facilityId']),
      sportId: JsonUtils.parseId(json['sportId']),
      courtId: JsonUtils.parseId(json['courtId']),
      facilityName: toOptString(json['facilityName'] ?? json['facility']?['name']),
      courtName: toOptString(json['courtName'] ?? json['court']?['name']),
      sportName: toOptString(json['sportName'] ?? json['sport']?['name']),
      start: toDT(json['start']),
      end: toDT(json['end']),
      status: (json['status'] ?? 'pending').toString(),
      currency: (json['currency'] ?? 'VND').toString(),
      total: toDouble(json['total'] ?? (snap?['total'])),
      pricingSnapshot: snap,
      participants: participants,
      voucherId: JsonUtils.parseIdOrNull(json['voucherId']),
    );
  }
}
