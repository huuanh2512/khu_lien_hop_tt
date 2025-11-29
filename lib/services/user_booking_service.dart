import 'package:dio/dio.dart';

import '../app_config.dart';
import '../models/court.dart';
import '../models/facility.dart';
import '../models/sport.dart';
import 'api_service.dart';

class FacilityWithCourts {
  final Facility facility;
  final List<Court> courts;

  const FacilityWithCourts({required this.facility, required this.courts});
}

class UserBookingService {
  final Dio _dio;

  UserBookingService({Dio? dio}) : _dio = dio ?? Dio(_defaultOptions()) {
    _dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) async {
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
    }));
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

  Future<List<Sport>> fetchSports() async {
    final res = await _dio.get('/api/sports', queryParameters: {'includeCount': 'false'});
    final data = res.data;
    if (data is! List) {
      throw Exception('Phản hồi dữ liệu môn thể thao không hợp lệ');
    }
    return data
        .whereType<Map<String, dynamic>>()
        .map(Sport.fromJson)
        .toList(growable: false);
  }

  Future<List<FacilityWithCourts>> fetchFacilitiesBySport(String sportId) async {
    final res = await _dio.get('/api/facilities');
    final facilitiesData = res.data;
    if (facilitiesData is! List) {
      throw Exception('Phản hồi cơ sở không hợp lệ');
    }
    final facilities = facilitiesData
        .whereType<Map<String, dynamic>>()
        .map(Facility.fromJson)
        .toList(growable: false);

    final futures = facilities.map((facility) async {
      final courtsRes = await _dio.get(
        '/api/facilities/${facility.id}/courts',
        queryParameters: {'sportId': sportId},
      );
      final courtsData = courtsRes.data;
      if (courtsData is! List) return null;
      final courts = courtsData
          .whereType<Map<String, dynamic>>()
          .map(Court.fromJson)
          .where((court) => court.status != 'deleted')
          .toList(growable: false);
      if (courts.isEmpty) return null;
      return FacilityWithCourts(facility: facility, courts: courts);
    }).toList(growable: false);

    final aggregates = await Future.wait(futures);
    return aggregates.whereType<FacilityWithCourts>().toList(growable: false);
  }

  Future<Map<String, dynamic>> quotePrice({
    required String facilityId,
    required String sportId,
    required String courtId,
    required DateTime start,
    required DateTime end,
    String currency = 'VND',
    String? userId,
  }) async {
    final payload = {
      'facilityId': facilityId,
      'sportId': sportId,
      'courtId': courtId,
      'start': start.toUtc().toIso8601String(),
      'end': end.toUtc().toIso8601String(),
      'currency': currency,
      if (userId != null) 'userId': userId,
    };
    final res = await _dio.post('/api/price/quote', data: payload);
    final data = res.data;
    if (data is! Map<String, dynamic>) {
      throw Exception('Phản hồi báo giá không hợp lệ');
    }
    return data;
  }

  Future<bool> checkAvailability({
    required String courtId,
    required DateTime start,
    required DateTime end,
  }) async {
    final res = await _dio.get(
      '/api/courts/$courtId/availability',
      queryParameters: {
        'start': start.toUtc().toIso8601String(),
        'end': end.toUtc().toIso8601String(),
      },
    );
    final data = res.data;
    if (data is! Map<String, dynamic>) {
      throw Exception('Phản hồi kiểm tra lịch không hợp lệ');
    }
    final available = data['available'];
    return available == true;
  }

  Future<Map<String, dynamic>> createBooking({
    required String customerId,
    required String facilityId,
    required String courtId,
    required String sportId,
    required DateTime start,
    required DateTime end,
    required String currency,
    required Map<String, dynamic> pricingSnapshot,
  }) async {
    final payload = {
      'customerId': customerId,
      'facilityId': facilityId,
      'courtId': courtId,
      'sportId': sportId,
      'start': start.toUtc().toIso8601String(),
      'end': end.toUtc().toIso8601String(),
      'currency': currency,
      'pricingSnapshot': pricingSnapshot,
      'status': 'pending',
    };
    final res = await _dio.post('/api/bookings', data: payload);
    final data = res.data;
    if (data is! Map<String, dynamic>) {
      throw Exception('Phản hồi đặt sân không hợp lệ');
    }
    return data;
  }
}
