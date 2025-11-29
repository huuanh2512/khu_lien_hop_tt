class StaffInvoicePayment {
  final String id;
  final String provider;
  final String method;
  final double amount;
  final String? currency;
  final String status;
  final String? txnRef;
  final DateTime? createdAt;

  StaffInvoicePayment({
    required this.id,
    required this.provider,
    required this.method,
    required this.amount,
    required this.status,
    this.currency,
    this.txnRef,
    this.createdAt,
  });

  factory StaffInvoicePayment.fromJson(Map<String, dynamic> json) {
    return StaffInvoicePayment(
      id: _asString(json['_id']),
      provider: _asString(json['provider']),
      method: _asString(json['method']),
      amount: _asDouble(json['amount']),
      status: _asString(json['status']),
      currency: _asOptionalString(json['currency']),
      txnRef: _asOptionalString(json['txnRef']),
      createdAt: _asDate(json['createdAt']),
    );
  }
}

class StaffInvoiceBookingInfo {
  final String id;
  final DateTime? start;
  final DateTime? end;
  final String? status;
  final String? courtId;
  final String? sportId;

  StaffInvoiceBookingInfo({
    required this.id,
    this.start,
    this.end,
    this.status,
    this.courtId,
    this.sportId,
  });

  factory StaffInvoiceBookingInfo.fromJson(Map<String, dynamic> json) {
    return StaffInvoiceBookingInfo(
      id: _asString(json['_id']),
      start: _asDate(json['start']),
      end: _asDate(json['end']),
      status: _asOptionalString(json['status']),
      courtId: _asOptionalString(json['courtId']),
      sportId: _asOptionalString(json['sportId']),
    );
  }
}

class StaffInvoiceCustomerInfo {
  final String id;
  final String? name;
  final String? email;
  final String? phone;

  StaffInvoiceCustomerInfo({
    required this.id,
    this.name,
    this.email,
    this.phone,
  });

  factory StaffInvoiceCustomerInfo.fromJson(Map<String, dynamic> json) {
    return StaffInvoiceCustomerInfo(
      id: _asString(json['_id']),
      name: _asOptionalString(json['name']),
      email: _asOptionalString(json['email']),
      phone: _asOptionalString(json['phone']),
    );
  }
}

class StaffInvoiceCourtInfo {
  final String id;
  final String? name;
  final String? code;

  StaffInvoiceCourtInfo({
    required this.id,
    this.name,
    this.code,
  });

  factory StaffInvoiceCourtInfo.fromJson(Map<String, dynamic> json) {
    return StaffInvoiceCourtInfo(
      id: _asString(json['_id']),
      name: _asOptionalString(json['name']),
      code: _asOptionalString(json['code']),
    );
  }
}

class StaffInvoice {
  final String id;
  final String bookingId;
  final double amount;
  final String currency;
  final String status;
  final DateTime? issuedAt;
  final double totalPaid;
  final double outstanding;
  final DateTime? lastPaymentAt;
  final StaffInvoiceBookingInfo? booking;
  final StaffInvoiceCustomerInfo? customer;
  final StaffInvoiceCourtInfo? court;
  final List<StaffInvoicePayment> payments;

  StaffInvoice({
    required this.id,
    required this.bookingId,
    required this.amount,
    required this.currency,
    required this.status,
    required this.totalPaid,
    required this.outstanding,
    this.issuedAt,
    this.lastPaymentAt,
    this.booking,
    this.customer,
    this.court,
    this.payments = const [],
  });

  factory StaffInvoice.fromJson(Map<String, dynamic> json) {
    final paymentsJson = json['payments'];
    return StaffInvoice(
      id: _asString(json['_id']),
      bookingId: _asString(json['bookingId']),
      amount: _asDouble(json['amount']),
      currency: _asString(json['currency']),
      status: _asString(json['status']),
      issuedAt: _asDate(json['issuedAt']),
      totalPaid: _asDouble(json['totalPaid']),
      outstanding: _asDouble(json['outstanding']),
      lastPaymentAt: _asDate(json['lastPaymentAt']),
      booking: json['booking'] is Map<String, dynamic>
          ? StaffInvoiceBookingInfo.fromJson(json['booking'] as Map<String, dynamic>)
          : null,
      customer: json['customer'] is Map<String, dynamic>
          ? StaffInvoiceCustomerInfo.fromJson(json['customer'] as Map<String, dynamic>)
          : null,
      court: json['court'] is Map<String, dynamic>
          ? StaffInvoiceCourtInfo.fromJson(json['court'] as Map<String, dynamic>)
          : null,
      payments: paymentsJson is List
          ? paymentsJson
              .whereType<Map<String, dynamic>>()
              .map(StaffInvoicePayment.fromJson)
              .toList(growable: false)
          : const [],
    );
  }
}

class StaffInvoiceSummary {
  final int invoiceCount;
  final double totalInvoiced;
  final double totalPaid;
  final double totalOutstanding;
  final double totalRevenue;

  const StaffInvoiceSummary({
    this.invoiceCount = 0,
    this.totalInvoiced = 0,
    this.totalPaid = 0,
    this.totalOutstanding = 0,
    this.totalRevenue = 0,
  });

  factory StaffInvoiceSummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const StaffInvoiceSummary();
    }
    return StaffInvoiceSummary(
      invoiceCount: _asInt(json['invoiceCount']),
      totalInvoiced: _asDouble(json['totalInvoiced']),
      totalPaid: _asDouble(json['totalPaid']),
      totalOutstanding: _asDouble(json['totalOutstanding']),
      totalRevenue: _asDouble(json['totalRevenue']),
    );
  }
}

class StaffInvoiceResponse {
  final List<StaffInvoice> invoices;
  final StaffInvoiceSummary summary;

  StaffInvoiceResponse({
    required this.invoices,
    required this.summary,
  });

  factory StaffInvoiceResponse.fromJson(Map<String, dynamic> json) {
    final invoicesJson = json['invoices'];
    return StaffInvoiceResponse(
      invoices: invoicesJson is List
          ? invoicesJson
              .whereType<Map<String, dynamic>>()
              .map(StaffInvoice.fromJson)
              .toList(growable: false)
          : const [],
      summary: StaffInvoiceSummary.fromJson(json['summary'] as Map<String, dynamic>?),
    );
  }
}

String _asString(Object? value) => value?.toString() ?? '';

String? _asOptionalString(Object? value) {
  if (value == null) return null;
  final text = value.toString();
  return text.isEmpty ? null : text;
}

double _asDouble(Object? value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

int _asInt(Object? value) {
  if (value == null) return 0;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}

DateTime? _asDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  try {
    return DateTime.parse(value.toString());
  } catch (_) {
    return null;
  }
}
