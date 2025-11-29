import '../utils/json_utils.dart';

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) {
    if (value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
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
  final text = value.toString();
  if (text.isEmpty) return null;
  return DateTime.tryParse(text);
}

class StaffCustomerBooking {
  final String? id;
  final DateTime? start;
  final DateTime? end;
  final String? status;
  final double total;
  final String currency;

  const StaffCustomerBooking({
    this.id,
    this.start,
    this.end,
    this.status,
    required this.total,
    required this.currency,
  });

  factory StaffCustomerBooking.fromJson(Map<String, dynamic> json) {
    final rawTotal = json['total'];
    double amount;
    if (rawTotal is num) {
      amount = rawTotal.toDouble();
    } else if (rawTotal is String) {
      amount = double.tryParse(rawTotal) ?? 0;
    } else {
      amount = 0;
    }
    return StaffCustomerBooking(
      id: JsonUtils.parseIdOrNull(json['id'] ?? json['_id']),
      start: _parseDate(json['start']),
      end: _parseDate(json['end']),
      status: json['status']?.toString(),
      total: amount,
      currency: (json['currency'] ?? 'VND').toString(),
    );
  }
}

class StaffCustomer {
  final String id;
  final String? name;
  final String? email;
  final String? phone;
  final DateTime? lastBookingAt;
  final int totalBookings;
  final List<StaffCustomerBooking> bookings;

  const StaffCustomer({
    required this.id,
    this.name,
    this.email,
    this.phone,
    this.lastBookingAt,
    required this.totalBookings,
    required this.bookings,
  });

  factory StaffCustomer.fromJson(Map<String, dynamic> json) {
  final List bookingsJson = json['bookings'] is List ? json['bookings'] as List : const [];
    return StaffCustomer(
      id: JsonUtils.parseId(json['id'] ?? json['_id']),
      name: json['name']?.toString(),
      email: json['email']?.toString(),
      phone: json['phone']?.toString(),
      lastBookingAt: _parseDate(json['lastBookingAt']),
      totalBookings: json['totalBookings'] is num ? (json['totalBookings'] as num).round() : bookingsJson.length,
    bookings: bookingsJson
      .whereType<Map<String, dynamic>>()
      .map(StaffCustomerBooking.fromJson)
      .toList(growable: false),
    );
  }

  String get displayName {
    if (name != null && name!.trim().isNotEmpty) return name!.trim();
    if (email != null && email!.trim().isNotEmpty) return email!.trim();
    return 'Khách hàng';
  }
}
