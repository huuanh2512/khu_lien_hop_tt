import '../utils/json_utils.dart';

class UserInvoice {
  final String id;
  final double amount;
  final String currency;
  final String status;
  final DateTime issuedAt;
  final DateTime? dueAt;
  final String? description;
  final String? facilityName;
  final String? courtName;
  final String? bookingId;

  const UserInvoice({
    required this.id,
    required this.amount,
    required this.currency,
    required this.status,
    required this.issuedAt,
    this.dueAt,
    this.description,
    this.facilityName,
    this.courtName,
    this.bookingId,
  });

  factory UserInvoice.fromJson(Map<String, dynamic> json) {
    return UserInvoice(
      id: JsonUtils.parseId(json['_id'] ?? json['id']),
      amount: _toDouble(json['amount']),
      currency: (json['currency'] ?? 'VND').toString(),
      status: (json['status'] ?? 'pending').toString(),
      issuedAt:
          DateTime.tryParse(json['issuedAt']?.toString() ?? '') ??
          DateTime.now(),
      dueAt: json['dueAt'] != null
          ? DateTime.tryParse(json['dueAt'].toString())
          : null,
      description: json['description']?.toString(),
      facilityName: json['facilityName']?.toString(),
      courtName: json['courtName']?.toString(),
      bookingId: JsonUtils.parseIdOrNull(json['bookingId']),
    );
  }

  UserInvoice copyWith({
    String? status,
    String? description,
    String? facilityName,
    String? courtName,
    String? bookingId,
  }) {
    return UserInvoice(
      id: id,
      amount: amount,
      currency: currency,
      status: status ?? this.status,
      issuedAt: issuedAt,
      dueAt: dueAt,
      description: description ?? this.description,
      facilityName: facilityName ?? this.facilityName,
      courtName: courtName ?? this.courtName,
      bookingId: bookingId ?? this.bookingId,
    );
  }
}

double _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.replaceAll(',', '.')) ?? 0;
  return 0;
}
