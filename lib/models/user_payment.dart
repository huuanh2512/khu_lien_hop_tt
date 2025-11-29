import '../utils/json_utils.dart';

class UserPayment {
  final String id;
  final String invoiceId;
  final double amount;
  final String currency;
  final String status;
  final String? method;
  final String? provider;
  final DateTime processedAt;
  final String? reference;

  const UserPayment({
    required this.id,
    required this.invoiceId,
    required this.amount,
    required this.currency,
    required this.status,
    required this.processedAt,
    this.method,
    this.provider,
    this.reference,
  });

  factory UserPayment.fromJson(Map<String, dynamic> json) {
    return UserPayment(
      id: JsonUtils.parseId(json['_id'] ?? json['id']),
      invoiceId: JsonUtils.parseId(json['invoiceId'] ?? json['invoice'] ?? ''),
      amount: _toDouble(json['amount']),
      currency: (json['currency'] ?? 'VND').toString(),
      status: (json['status'] ?? 'pending').toString(),
      method: json['method']?.toString(),
      provider: json['provider']?.toString(),
      processedAt:
          DateTime.tryParse(json['processedAt']?.toString() ?? '') ??
          DateTime.now(),
      reference: json['reference']?.toString(),
    );
  }

  UserPayment copyWith({String? status, String? provider}) {
    return UserPayment(
      id: id,
      invoiceId: invoiceId,
      amount: amount,
      currency: currency,
      status: status ?? this.status,
      processedAt: processedAt,
      method: method,
      provider: provider ?? this.provider,
      reference: reference,
    );
  }
}

double _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.replaceAll(',', '.')) ?? 0;
  return 0;
}
