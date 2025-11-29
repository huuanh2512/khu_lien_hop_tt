import 'booking.dart';
import '../utils/json_utils.dart';

DateTime? _parseDate(dynamic value) {
  if (value is DateTime) return value.toLocal();
  if (value is String && value.isNotEmpty) {
    final parsed = DateTime.tryParse(value);
    return parsed?.toLocal();
  }
  if (value is Map && value[r'$date'] != null) {
    final raw = value[r'$date'];
    if (raw is String && raw.isNotEmpty) {
      final parsed = DateTime.tryParse(raw);
      return parsed?.toLocal();
    }
    if (raw is int) {
      return DateTime.fromMillisecondsSinceEpoch(raw).toLocal();
    }
  }
  return null;
}

class StaffBookingCustomer {
  final String? id;
  final String? name;
  final String? email;
  final String? phone;

  const StaffBookingCustomer({this.id, this.name, this.email, this.phone});

  factory StaffBookingCustomer.fromJson(Map<String, dynamic> json) {
    return StaffBookingCustomer(
      id: JsonUtils.parseIdOrNull(json['_id']),
      name: _trim(json['name']),
      email: _trim(json['email']),
      phone: _trim(json['phone']),
    );
  }

  static String? _trim(dynamic value) {
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    return null;
  }
}

class StaffBookingCourt {
  final String? id;
  final String? name;
  final String? code;

  const StaffBookingCourt({this.id, this.name, this.code});

  factory StaffBookingCourt.fromJson(Map<String, dynamic> json) {
    return StaffBookingCourt(
      id: JsonUtils.parseIdOrNull(json['_id']),
      name: StaffBookingCustomer._trim(json['name']),
      code: StaffBookingCustomer._trim(json['code']),
    );
  }
}

class StaffBookingSport {
  final String? id;
  final String? name;

  const StaffBookingSport({this.id, this.name});

  factory StaffBookingSport.fromJson(Map<String, dynamic> json) {
    return StaffBookingSport(
      id: JsonUtils.parseIdOrNull(json['_id']),
      name: StaffBookingCustomer._trim(json['name']),
    );
  }
}

class StaffBooking {
  final Booking booking;
  final StaffBookingCustomer? customer;
  final StaffBookingCourt? court;
  final StaffBookingSport? sport;
  final DateTime? confirmedAt;
  final String? confirmedBy;
  final String? confirmedVia;
  final String? confirmationNote;
  final DateTime? cancelledAt;
  final String? cancelledBy;
  final String? cancelledReason;
  final DateTime? completedAt;
  final String? completedBy;
  final String? preferredContactMethod;
  final String? staffNote;
  final String? createdBy;
  final String? createdByRole;
  final String? source;

  const StaffBooking({
    required this.booking,
    this.customer,
    this.court,
    this.sport,
    this.confirmedAt,
    this.confirmedBy,
    this.confirmedVia,
    this.confirmationNote,
    this.cancelledAt,
    this.cancelledBy,
    this.cancelledReason,
    this.completedAt,
    this.completedBy,
    this.preferredContactMethod,
    this.staffNote,
    this.createdBy,
    this.createdByRole,
    this.source,
  });

  String get id => booking.id;
  String get status => booking.status;
  DateTime get start => booking.start;
  DateTime get end => booking.end;

  factory StaffBooking.fromJson(Map<String, dynamic> json) {
    final customerJson = json['customer'];
    final courtJson = json['court'];
    final sportJson = json['sport'];

    return StaffBooking(
      booking: Booking.fromJson(json),
      customer: customerJson is Map<String, dynamic>
          ? StaffBookingCustomer.fromJson(customerJson)
          : null,
      court: courtJson is Map<String, dynamic>
          ? StaffBookingCourt.fromJson(courtJson)
          : null,
      sport: sportJson is Map<String, dynamic>
          ? StaffBookingSport.fromJson(sportJson)
          : null,
      confirmedAt: _parseDate(json['confirmedAt']),
      confirmedBy: JsonUtils.parseIdOrNull(json['confirmedBy']),
      confirmedVia: StaffBookingCustomer._trim(json['confirmedVia']),
      confirmationNote: StaffBookingCustomer._trim(json['confirmationNote']),
      cancelledAt: _parseDate(json['cancelledAt']),
      cancelledBy: JsonUtils.parseIdOrNull(json['cancelledBy']),
      cancelledReason: StaffBookingCustomer._trim(json['cancelledReason']),
      completedAt: _parseDate(json['completedAt']),
      completedBy: JsonUtils.parseIdOrNull(json['completedBy']),
      preferredContactMethod: StaffBookingCustomer._trim(json['preferredContactMethod']),
      staffNote: StaffBookingCustomer._trim(json['staffNote']),
      createdBy: JsonUtils.parseIdOrNull(json['createdBy']),
      createdByRole: StaffBookingCustomer._trim(json['createdByRole']),
      source: StaffBookingCustomer._trim(json['source']),
    );
  }
}
