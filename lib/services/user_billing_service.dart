import 'package:dio/dio.dart';

import '../app_config.dart';
import '../models/user_invoice.dart';
import '../models/user_payment.dart';
import 'api_service.dart';

class UserBillingService {
  final Dio _dio;

  UserBillingService({Dio? dio}) : _dio = dio ?? Dio(_defaultOptions()) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          try {
            final token = await ApiService.refreshAuthToken();
            if (token != null && token.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $token';
            } else {
              options.headers.remove('Authorization');
            }
          } catch (_) {
            final fallback = ApiService.authToken;
            if (fallback != null && fallback.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $fallback';
            } else {
              options.headers.remove('Authorization');
            }
          }
          return handler.next(options);
        },
      ),
    );
  }

  static BaseOptions _defaultOptions() {
    return BaseOptions(
      baseUrl: AppConfig.apiBase,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      contentType: 'application/json',
      responseType: ResponseType.json,
    );
  }

  Future<List<UserInvoice>> fetchInvoices() async {
    final res = await _dio.get('/api/user/invoices');
    final data = res.data;
    if (data is! List) {
      throw Exception('Phản hồi hoá đơn không hợp lệ');
    }
    return data
        .whereType<Map<String, dynamic>>()
        .map(UserInvoice.fromJson)
        .toList(growable: false);
  }

  Future<List<UserPayment>> fetchPayments({String? invoiceId}) async {
    final res = await _dio.get(
      '/api/user/payments',
      queryParameters: {if (invoiceId != null) 'invoiceId': invoiceId},
    );
    final data = res.data;
    if (data is! List) {
      throw Exception('Phản hồi lịch sử thanh toán không hợp lệ');
    }
    return data
        .whereType<Map<String, dynamic>>()
        .map(UserPayment.fromJson)
        .toList(growable: false);
  }

  Future<PayInvoiceResult> payInvoice(
    String invoiceId, {
    double? amount,
    String? method,
    String? provider,
    String? reference,
  }) async {
    final payload = <String, dynamic>{
      if (amount != null) 'amount': amount,
      if (method != null && method.trim().isNotEmpty) 'method': method.trim(),
      if (provider != null && provider.trim().isNotEmpty)
        'provider': provider.trim(),
      if (reference != null && reference.trim().isNotEmpty)
        'reference': reference.trim(),
    };

    final res = await _dio.post(
      '/api/user/invoices/$invoiceId/pay',
      data: payload.isEmpty ? null : payload,
    );
    final data = res.data;
    if (data is! Map<String, dynamic>) {
      throw Exception('Phản hồi thanh toán không hợp lệ');
    }

    final paymentJson = data['payment'];
    if (paymentJson is! Map<String, dynamic>) {
      throw Exception('Thiếu thông tin giao dịch thanh toán');
    }

    final payment = UserPayment.fromJson(paymentJson);
    final status = data['status']?.toString() ?? 'unpaid';
    final totalPaid = _parseDouble(data['totalPaid']);
    final outstanding = _parseDouble(data['outstanding']);

    return PayInvoiceResult(
      payment: payment,
      status: status,
      totalPaid: totalPaid,
      outstanding: outstanding,
    );
  }

  double _parseDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value.replaceAll(',', '.')) ?? 0;
    }
    return 0;
  }
}

class PayInvoiceResult {
  final UserPayment payment;
  final String status;
  final double totalPaid;
  final double outstanding;

  const PayInvoiceResult({
    required this.payment,
    required this.status,
    required this.totalPaid,
    required this.outstanding,
  });
}
