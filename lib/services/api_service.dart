import 'dart:convert';

import 'package:dio/dio.dart';
import '../models/sport.dart';
import '../models/facility.dart';
import '../models/court.dart';
import '../models/price_profile.dart';
import '../models/user.dart';
import '../models/booking.dart';
import '../models/audit_log.dart';
import '../models/maintenance.dart';
import '../models/staff_facility.dart';
import '../models/staff_booking.dart';
import '../models/staff_invoice.dart';
import '../models/staff_profile.dart';
import '../models/staff_customer.dart';
import '../models/match_request.dart';
import '../models/user_profile.dart';
import '../models/staff_notification.dart';
import '../models/user_invoice.dart';

class ApiService {
  ApiService({String? baseUrl})
    : baseUrl = baseUrl ?? _defaultBaseUrl,
      _dio = Dio(
        BaseOptions(
          baseUrl: baseUrl ?? _defaultBaseUrl,
          responseType: ResponseType.json,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 10),
          validateStatus: (_) => true,
        ),
      ) {
    _dio.options.headers.putIfAbsent('Accept', () => 'application/json');
    _dio.interceptors.removeWhere((it) => it is _AuthInterceptor);
    _dio.interceptors.add(_AuthInterceptor());
  }

  static const String _defaultBaseUrl = 'https://khu-lien-hop-tt.onrender.com';

  final Dio _dio;
  final String baseUrl;

  static String _authToken = '';
  static Future<String?> Function()? _tokenProvider;

  static void setAuthToken(String token) {
    _authToken = token.trim();
  }

  static String? get authToken => _authToken.isEmpty ? null : _authToken;

  static void clearAuthToken() {
    _authToken = '';
  }

  static void registerTokenProvider(Future<String?> Function() provider) {
    _tokenProvider = provider;
  }

  static Future<String?> refreshAuthToken() async {
    if (_tokenProvider == null) {
      return authToken;
    }
    try {
      final token = await _tokenProvider!.call();
      if (token != null && token.isNotEmpty) {
        setAuthToken(token);
        return token;
      }
      clearAuthToken();
      return null;
    } catch (_) {
      return authToken;
    }
  }

  Future<_Response> _request(
    String method,
    Object path, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    try {
      final url = path is Uri ? path.toString() : path.toString();
      final response = await _dio.request<dynamic>(
        url,
        data: body,
        options: Options(method: method, headers: headers),
      );
      return _mapResponse(response);
    } on DioException catch (error) {
      throw Exception(_errorMessage(error));
    }
  }

  Future<_Response> _get(Object path, {Map<String, String>? headers}) =>
      _request('GET', path, headers: headers);

  Future<_Response> _post(
    Object path, {
    Map<String, String>? headers,
    Object? body,
  }) => _request('POST', path, headers: headers, body: body);

  Future<_Response> _put(
    Object path, {
    Map<String, String>? headers,
    Object? body,
  }) => _request('PUT', path, headers: headers, body: body);

  Future<_Response> _patch(
    Object path, {
    Map<String, String>? headers,
    Object? body,
  }) => _request('PATCH', path, headers: headers, body: body);

  Future<_Response> _delete(
    Object path, {
    Map<String, String>? headers,
    Object? body,
  }) => _request('DELETE', path, headers: headers, body: body);

  _Response _mapResponse(Response<dynamic> response) {
    final code = response.statusCode ?? 500;
    final body = _stringifyBody(response.data);
    return _Response(code, body);
  }

  String _stringifyBody(dynamic data) {
    if (data == null) return '';
    if (data is String) return data;
    try {
      return jsonEncode(data);
    } catch (_) {
      return data.toString();
    }
  }

  String _errorMessage(DioException error) {
    final buffer = StringBuffer();
    final status = error.response?.statusCode;
    if (status != null) {
      buffer.write('HTTP $status');
    } else {
      buffer.write('Network error');
    }
    final data = _stringifyBody(error.response?.data);
    if (data.trim().isNotEmpty) {
      buffer.write(': $data');
    } else if (error.message != null) {
      buffer.write(': ${error.message}');
    }
    return buffer.toString();
  }

  Map<String, String> _headers({bool json = false}) {
    final headers = <String, String>{};
    if (json) headers['Content-Type'] = 'application/json';
    final token = authToken;
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<List<Sport>> getSports({bool includeCount = true}) async {
    final uri = Uri.parse(
      '$baseUrl/api/sports',
    ).replace(queryParameters: {if (includeCount) 'includeCount': 'true'});
    final res = await _get(uri, headers: _headers());
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final List data = jsonDecode(res.body) as List;
    return data.map((e) => Sport.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Facility>> getFacilities() async {
    final res = await _get(
      Uri.parse('$baseUrl/api/facilities'),
      headers: _headers(),
    );
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final List data = jsonDecode(res.body) as List;
    return data
        .map((e) => Facility.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Court>> getCourtsByFacility(
    String facilityId, {
    String? sportId,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/api/facilities/$facilityId/courts',
    ).replace(queryParameters: {if (sportId != null) 'sportId': sportId});
    final res = await _get(uri, headers: _headers());
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final List data = jsonDecode(res.body) as List;
    return data.map((e) => Court.fromJson(e as Map<String, dynamic>)).toList();
  }

  // --- Customer APIs ---
  Future<UserProfile> getUserProfile() async {
    final res = await _get(
      Uri.parse('$baseUrl/api/user/profile'),
      headers: _headers(),
    );
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return UserProfile.fromJson(data);
  }

  Future<UserProfile> updateUserProfile({
    String? name,
    String? phone,
    List<String>? sportsPreferences,
    String? gender,
    DateTime? dateOfBirth,
    bool includeDateOfBirth = false,
    String? mainSportId,
    bool includeMainSportId = false,
  }) async {
    final payload = <String, dynamic>{
      if (name != null) 'name': name,
      if (phone != null) 'phone': phone,
      if (sportsPreferences != null) 'sportsPreferences': sportsPreferences,
      if (gender != null) 'gender': gender,
      if (includeDateOfBirth) 'dateOfBirth': dateOfBirth?.toIso8601String(),
      if (includeMainSportId)
        'mainSportId': mainSportId
      else if (mainSportId != null)
        'mainSportId': mainSportId,
    };

    final res = await _put(
      Uri.parse('$baseUrl/api/user/profile'),
      headers: _headers(json: true),
      body: jsonEncode(payload),
    );
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return UserProfile.fromJson(data);
  }

  Future<void> updateUserPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final payload = {
      'currentPassword': currentPassword,
      'newPassword': newPassword,
    };
    final res = await _put(
      Uri.parse('$baseUrl/api/user/password'),
      headers: _headers(json: true),
      body: jsonEncode(payload),
    );
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
  }

  Future<MatchRequest> createMatchRequest({
    required String sportId,
    required DateTime desiredStart,
    required DateTime desiredEnd,
    int? skillMin,
    int? skillMax,
    String? facilityId,
    String? courtId,
    int? participantLimit,
    int? teamSize,
    String? notes,
  }) async {
    final skillRange = <String, int>{
      if (skillMin != null) 'min': skillMin,
      if (skillMax != null) 'max': skillMax,
    };
    final payload = <String, dynamic>{
      'sportId': sportId,
      'desiredStart': desiredStart.toIso8601String(),
      'desiredEnd': desiredEnd.toIso8601String(),
      if (skillRange.isNotEmpty) 'skillRange': skillRange,
      if (facilityId != null && facilityId.isNotEmpty) 'facilityId': facilityId,
      if (courtId != null && courtId.isNotEmpty) 'courtId': courtId,
      if (participantLimit != null && participantLimit > 0)
        'participantLimit': participantLimit,
      if (teamSize != null && teamSize > 0) 'teamSize': teamSize,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    };

    final res = await _post(
      Uri.parse('$baseUrl/api/match_requests'),
      headers: _headers(json: true),
      body: jsonEncode(payload),
    );
    if (res.statusCode != 201) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return MatchRequest.fromJson(data);
  }

  Future<List<MatchRequest>> getMatchRequests({
    String? status,
    String? sportId,
    int limit = 20,
  }) async {
    final query = <String, String>{
      if (status != null && status.trim().isNotEmpty) 'status': status.trim(),
      if (sportId != null && sportId.trim().isNotEmpty)
        'sportId': sportId.trim(),
      if (limit > 0) 'limit': limit.toString(),
    };

    final uri = Uri.parse(
      '$baseUrl/api/match_requests',
    ).replace(queryParameters: query.isEmpty ? null : query);
    final res = await _get(uri, headers: _headers());
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final List data = jsonDecode(res.body) as List;
    return data
        .map((item) => MatchRequest.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<MatchRequest> joinMatchRequest(String id, {String? team}) async {
    final payload = <String, dynamic>{
      if (team != null && team.trim().isNotEmpty) 'team': team.trim(),
    };

    final res = await _put(
      Uri.parse('$baseUrl/api/match_requests/$id/join'),
      headers: _headers(json: true),
      body: jsonEncode(payload),
    );
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return MatchRequest.fromJson(data);
  }

  Future<MatchRequest> cancelMatchRequest(String id) async {
    final res = await _put(
      Uri.parse('$baseUrl/api/match_requests/$id/cancel'),
      headers: _headers(json: true),
      body: jsonEncode({}),
    );
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return MatchRequest.fromJson(data);
  }

  Future<List<Booking>> getUserBookings({String? status}) async {
    final query = <String, String>{
      if (status != null && status.trim().isNotEmpty) 'status': status.trim(),
    };
    final uri = Uri.parse(
      '$baseUrl/api/user/bookings',
    ).replace(queryParameters: query.isEmpty ? null : query);
    final res = await _get(uri, headers: _headers());
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final body = res.body.trim();
    if (body.isEmpty) return const [];
    final List data = jsonDecode(body) as List;
    return data
        .map((e) => Booking.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Booking>> getUserUpcomingBookings() async {
    final res = await _get(
      Uri.parse('$baseUrl/api/user/bookings/upcoming'),
      headers: _headers(),
    );
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final body = res.body.trim();
    if (body.isEmpty) return const [];
    final List data = jsonDecode(body) as List;
    return data
        .map((e) => Booking.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<UserInvoice>> getUserInvoices({String? status, int? limit}) async {
    final query = <String, String>{
      if (status != null && status.trim().isNotEmpty) 'status': status.trim(),
      if (limit != null && limit > 0) 'limit': limit.toString(),
    };
    final uri = Uri.parse(
      '$baseUrl/api/user/invoices',
    ).replace(queryParameters: query.isEmpty ? null : query);
    final res = await _get(uri, headers: _headers());
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final body = res.body.trim();
    if (body.isEmpty) return const [];
    final List data = jsonDecode(body) as List;
    return data
        .whereType<Map<String, dynamic>>()
        .map(UserInvoice.fromJson)
        .toList(growable: false);
  }

  Future<Booking?> cancelBooking(String bookingId) async {
    final res = await _put(
      Uri.parse('$baseUrl/api/bookings/$bookingId/cancel'),
      headers: _headers(json: true),
      body: jsonEncode({}),
    );
    if (res.statusCode == 200) {
      final body = res.body.trim();
      if (body.isEmpty) return null;
      final data = jsonDecode(body);
      if (data is Map<String, dynamic>) {
        return Booking.fromJson(data);
      }
      return null;
    }
    if (res.statusCode == 204) {
      return null;
    }
    throw Exception('HTTP ${res.statusCode}: ${res.body}');
  }

  // --- Admin APIs ---
  Future<List<Sport>> adminGetSports({bool includeInactive = true}) async {
    final uri = Uri.parse('$baseUrl/api/admin/sports').replace(
      queryParameters: {if (includeInactive) 'includeInactive': 'true'},
    );
    final res = await _get(uri, headers: _headers());
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final List data = jsonDecode(res.body) as List;
    return data.map((e) => Sport.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Sport> adminCreateSport({
    required String name,
    required String code,
    required int teamSize,
    bool active = true,
  }) async {
    final res = await _post(
      Uri.parse('$baseUrl/api/admin/sports'),
      headers: _headers(json: true),
      body: jsonEncode({
        'name': name,
        'code': code,
        'teamSize': teamSize,
        'active': active,
      }),
    );
    if (res.statusCode != 201) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    return Sport.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<Sport> adminUpdateSport(
    String id,
    Map<String, dynamic> updates,
  ) async {
    final res = await _put(
      Uri.parse('$baseUrl/api/admin/sports/$id'),
      headers: _headers(json: true),
      body: jsonEncode(updates),
    );
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    return Sport.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<void> adminDeleteSport(String id) async {
    final res = await _delete(
      Uri.parse('$baseUrl/api/admin/sports/$id'),
      headers: _headers(),
    );
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
  }

  Future<List<Court>> adminGetCourtsByFacility(String facilityId) async {
    final res = await _get(
      Uri.parse('$baseUrl/api/admin/facilities/$facilityId/courts'),
      headers: _headers(),
    );
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final List data = jsonDecode(res.body) as List;
    return data.map((e) => Court.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Map<String, dynamic>> adminCreateFacility({
    required String name,
    String timeZone = 'Asia/Ho_Chi_Minh',
    bool active = true,
    Map<String, dynamic>? address,
  }) async {
    final res = await _post(
      Uri.parse('$baseUrl/api/admin/facilities'),
      headers: _headers(json: true),
      body: jsonEncode({
        'name': name,
        'timeZone': timeZone,
        'active': active,
        if (address != null) 'address': address,
      }),
    );
    if (res.statusCode != 201) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<Facility>> adminGetFacilities({
    bool includeInactive = true,
  }) async {
    final uri = Uri.parse('$baseUrl/api/admin/facilities').replace(
      queryParameters: {if (includeInactive) 'includeInactive': 'true'},
    );
    final res = await _get(uri, headers: _headers());
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final List data = jsonDecode(res.body) as List;
    return data
        .map((e) => Facility.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Facility> adminUpdateFacility(
    String id,
    Map<String, dynamic> updates,
  ) async {
    final res = await _put(
      Uri.parse('$baseUrl/api/admin/facilities/$id'),
      headers: _headers(json: true),
      body: jsonEncode(updates),
    );
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    return Facility.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<void> adminDeleteFacility(String id) async {
    final res = await _delete(
      Uri.parse('$baseUrl/api/admin/facilities/$id'),
      headers: _headers(),
    );
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
  }

  Future<Court> adminCreateCourt({
    required String facilityId,
    required String sportId,
    required String name,
    String? code,
    String status = 'active',
  }) async {
    final res = await _post(
      Uri.parse('$baseUrl/api/admin/courts'),
      headers: _headers(json: true),
      body: jsonEncode({
        'facilityId': facilityId,
        'sportId': sportId,
        'name': name,
        if (code != null) 'code': code,
        'status': status,
      }),
    );
    if (res.statusCode != 201) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    return Court.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<Court> adminUpdateCourt(
    String id,
    Map<String, dynamic> updates,
  ) async {
    final res = await _put(
      Uri.parse('$baseUrl/api/admin/courts/$id'),
      headers: _headers(json: true),
      body: jsonEncode(updates),
    );
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    return Court.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<void> adminDeleteCourt(String id) async {
    final res = await _delete(
      Uri.parse('$baseUrl/api/admin/courts/$id'),
      headers: _headers(),
    );
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
  }

  // --- Staff APIs ---
  Future<StaffFacilityData> staffGetFacility() async {
    final res = await _get(
      Uri.parse('$baseUrl/api/staff/facility'),
      headers: _headers(),
    );
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return StaffFacilityData.fromJson(data);
  }

  Future<StaffProfile> staffGetProfile() async {
    final res = await _get(
      Uri.parse('$baseUrl/api/staff/profile'),
      headers: _headers(),
    );
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return StaffProfile.fromJson(data);
  }

  Future<StaffProfile> staffUpdateProfile({
    String? name,
    String? email,
    String? phone,
  }) async {
    final payload = <String, dynamic>{};
    if (name != null) payload['name'] = name;
    if (email != null) payload['email'] = email;
    if (phone != null) payload['phone'] = phone;
    if (payload.isEmpty) {
      throw Exception('KhÃ´ng cÃ³ dá»¯ liá»‡u cáº§n cáº­p nháº­t');
    }
    final res = await _put(
      Uri.parse('$baseUrl/api/staff/profile'),
      headers: _headers(json: true),
      body: jsonEncode(payload),
    );
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return StaffProfile.fromJson(data);
  }

  Future<void> staffChangePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final res = await _post(
      Uri.parse('$baseUrl/api/staff/profile/change-password'),
      headers: _headers(json: true),
      body: jsonEncode({
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
  }

  Future<void> staffReportIssue({
    required String subject,
    String? description,
    String severity = 'medium',
  }) async {
    final payload = <String, dynamic>{
      'subject': subject,
      'severity': severity.trim().toLowerCase(),
    };
    if (description != null) payload['description'] = description;
    final res = await _post(
      Uri.parse('$baseUrl/api/staff/issues'),
      headers: _headers(json: true),
      body: jsonEncode(payload),
    );
    if (res.statusCode != 201) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
  }

  Future<List<StaffCustomer>> staffGetCustomers({int limit = 50}) async {
    final uri = Uri.parse(
      '$baseUrl/api/staff/customers',
    ).replace(queryParameters: {'limit': limit.toString()});
    final res = await _get(uri, headers: _headers());
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final List items = data['customers'] is List
        ? data['customers'] as List
        : const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(StaffCustomer.fromJson)
        .toList(growable: false);
  }

  Future<void> staffSendCustomerMessage({
    required String customerId,
    required String message,
    String? subject,
  }) async {
    final cleanMessage = message.trim();
    if (cleanMessage.isEmpty) {
      throw Exception('Ná»™i dung khÃ´ng Ä‘Æ°á»£c Ä‘á»ƒ trá»‘ng');
    }
    final payload = <String, dynamic>{'message': cleanMessage};
    if (subject != null && subject.trim().isNotEmpty) {
      payload['subject'] = subject.trim();
    }
    final res = await _post(
      Uri.parse('$baseUrl/api/staff/customers/$customerId/messages'),
      headers: _headers(json: true),
      body: jsonEncode(payload),
    );
    if (res.statusCode != 201) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
  }

  Future<Facility> staffUpdateFacility(Map<String, dynamic> updates) async {
    if (updates.isEmpty) {
      throw Exception('KhÃ´ng cÃ³ dá»¯ liá»‡u cáº§n cáº­p nháº­t');
    }
    final res = await _put(
      Uri.parse('$baseUrl/api/staff/facility'),
      headers: _headers(json: true),
      body: jsonEncode(updates),
    );
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return Facility.fromJson(data);
  }

  Future<Maintenance> staffCreateMaintenance({
    required String courtId,
    required DateTime start,
    required DateTime end,
    String? reason,
  }) async {
    final payload = <String, dynamic>{
      'start': start.toIso8601String(),
      'end': end.toIso8601String(),
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    };
    final res = await _post(
      Uri.parse('$baseUrl/api/staff/courts/$courtId/maintenance'),
      headers: _headers(json: true),
      body: jsonEncode(payload),
    );
    if (res.statusCode != 201) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return Maintenance.fromJson(data);
  }

  Future<Maintenance> staffUpdateMaintenance(
    String id, {
    DateTime? start,
    DateTime? end,
    String? reason,
    String? status,
  }) async {
    final payload = <String, dynamic>{};
    if (start != null) payload['start'] = start.toIso8601String();
    if (end != null) payload['end'] = end.toIso8601String();
    if (reason != null) payload['reason'] = reason;
    if (status != null && status.trim().isNotEmpty) {
      payload['status'] = status.trim();
    }
    if (payload.isEmpty) {
      throw Exception('KhÃ´ng cÃ³ thay Ä‘á»•i nÃ o Ä‘Æ°á»£c gá»­i lÃªn');
    }
    final res = await _put(
      Uri.parse('$baseUrl/api/staff/maintenance/$id'),
      headers: _headers(json: true),
      body: jsonEncode(payload),
    );
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return Maintenance.fromJson(data);
  }

  Future<Maintenance> staffMaintenanceAction(String id, String action) async {
    final clean = action.trim();
    if (clean.isEmpty) {
      throw Exception('Thiáº¿u loáº¡i thao tÃ¡c');
    }
    final res = await _post(
      Uri.parse('$baseUrl/api/staff/maintenance/$id/action'),
      headers: _headers(json: true),
      body: jsonEncode({'action': clean}),
    );
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return Maintenance.fromJson(data);
  }

  Future<List<Sport>> staffGetSports({bool includeInactive = false}) async {
    final uri = Uri.parse('$baseUrl/api/staff/sports').replace(
      queryParameters: {if (includeInactive) 'includeInactive': 'true'},
    );
    final res = await _get(uri, headers: _headers());
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final List data = jsonDecode(res.body) as List;
    return data.map((e) => Sport.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Sport> staffCreateSport({
    required String name,
    required String code,
    required int teamSize,
    bool active = true,
  }) async {
    final res = await _post(
      Uri.parse('$baseUrl/api/staff/sports'),
      headers: _headers(json: true),
      body: jsonEncode({
        'name': name,
        'code': code,
        'teamSize': teamSize,
        'active': active,
      }),
    );
    if (res.statusCode != 201) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    return Sport.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<List<StaffBooking>> staffGetBookings({
    String? status,
    DateTime? from,
    DateTime? to,
    int limit = 100,
  }) async {
    final query = <String, String>{};
    final cleanStatus = status?.trim();
    if (cleanStatus != null && cleanStatus.isNotEmpty) {
      query['status'] = cleanStatus;
    }
    if (from != null) {
      query['from'] = from.toIso8601String();
    }
    if (to != null) {
      query['to'] = to.toIso8601String();
    }
    final safeLimit = limit < 1 ? 1 : (limit > 200 ? 200 : limit);
    query['limit'] = safeLimit.toString();

    final uri = Uri.parse(
      '$baseUrl/api/staff/bookings',
    ).replace(queryParameters: query.isEmpty ? null : query);
    final res = await _get(uri, headers: _headers());
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final List data = jsonDecode(res.body) as List;
    return data
        .map((e) => StaffBooking.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<StaffBooking> staffCreateBooking({
    String? customerId,
    String? customerName,
    String? customerPhone,
    String? customerEmail,
    required String sportId,
    required String courtId,
    required DateTime start,
    required DateTime end,
    bool confirmNow = true,
    String? contactMethod,
    String? note,
    String currency = 'VND',
    List<String>? participantIds,
  }) async {
    final payload = <String, dynamic>{
      'sportId': sportId,
      'courtId': courtId,
      'start': start.toUtc().toIso8601String(),
      'end': end.toUtc().toIso8601String(),
      'currency': currency,
      'confirm': confirmNow,
    };
    if (customerId != null && customerId.trim().isNotEmpty) {
      payload['customerId'] = customerId.trim();
    }
    final customer = <String, String>{};
    if (customerName != null && customerName.trim().isNotEmpty) {
      customer['name'] = customerName.trim();
    }
    if (customerPhone != null && customerPhone.trim().isNotEmpty) {
      customer['phone'] = customerPhone.trim();
    }
    if (customerEmail != null && customerEmail.trim().isNotEmpty) {
      customer['email'] = customerEmail.trim();
    }
    if (customer.isNotEmpty) {
      payload['customer'] = customer;
    }
    if (contactMethod != null && contactMethod.trim().isNotEmpty) {
      payload['contactMethod'] = contactMethod.trim();
    }
    if (note != null && note.trim().isNotEmpty) {
      payload['note'] = note.trim();
    }
    if (participantIds != null && participantIds.isNotEmpty) {
      payload['participants'] = participantIds;
    }

    final res = await _post(
      Uri.parse('$baseUrl/api/staff/bookings'),
      headers: _headers(json: true),
      body: jsonEncode(payload),
    );
    if (res.statusCode != 201) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final data = jsonDecode(res.body);
    if (data is Map<String, dynamic>) {
      return StaffBooking.fromJson(data);
    }
    throw Exception('Unexpected response: ${res.body}');
  }

  Future<StaffInvoiceResponse> staffGetInvoices({
    String? status,
    DateTime? from,
    DateTime? to,
    int limit = 100,
  }) async {
    final query = <String, String>{};
    final cleanStatus = status?.trim();
    if (cleanStatus != null && cleanStatus.isNotEmpty) {
      query['status'] = cleanStatus;
    }
    if (from != null) {
      query['from'] = from.toIso8601String();
    }
    if (to != null) {
      query['to'] = to.toIso8601String();
    }
    if (limit > 0) {
      query['limit'] = limit.toString();
    }

    final uri = Uri.parse(
      '$baseUrl/api/staff/invoices',
    ).replace(queryParameters: query.isEmpty ? null : query);
    final res = await _get(uri, headers: _headers());
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return StaffInvoiceResponse.fromJson(data);
  }

  Future<List<StaffNotification>> staffGetNotifications({
    int limit = 50,
    bool unreadOnly = false,
    String? channel,
    String? priority,
  }) async {
    final query = <String, String>{};
    if (limit > 0) query['limit'] = limit.toString();
    if (unreadOnly) query['status'] = 'unread';
    final cleanChannel = channel?.trim();
    if (cleanChannel != null && cleanChannel.isNotEmpty) {
      query['channel'] = cleanChannel;
    }
    final cleanPriority = priority?.trim();
    if (cleanPriority != null && cleanPriority.isNotEmpty) {
      query['priority'] = cleanPriority;
    }

    final uri = Uri.parse(
      '$baseUrl/api/staff/notifications',
    ).replace(queryParameters: query.isEmpty ? null : query);
    final res = await _get(uri, headers: _headers());
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final body = res.body.trim();
    if (body.isEmpty) return const [];
    final List data = jsonDecode(body) as List;
    return data
        .map((item) => StaffNotification.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<void> staffMarkNotificationRead(String notificationId) async {
    final res = await _post(
      Uri.parse('$baseUrl/api/staff/notifications/$notificationId/read'),
      headers: _headers(json: true),
    );
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
  }

  Future<void> staffMarkAllNotificationsRead() async {
    final res = await _post(
      Uri.parse('$baseUrl/api/staff/notifications/mark-all-read'),
      headers: _headers(json: true),
    );
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
  }

  Future<StaffBooking> staffUpdateBookingStatus(
    String bookingId, {
    required String status,
    String? contactMethod,
    String? note,
  }) async {
    final payload = <String, dynamic>{
      'status': status,
      if (contactMethod != null && contactMethod.trim().isNotEmpty)
        'contactMethod': contactMethod.trim(),
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    };

    final res = await _patch(
      Uri.parse('$baseUrl/api/staff/bookings/$bookingId/status'),
      headers: _headers(json: true),
      body: jsonEncode(payload),
    );
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final data = jsonDecode(res.body);
    if (data is Map<String, dynamic>) {
      return StaffBooking.fromJson(data);
    }
    throw Exception('Unexpected response: ${res.body}');
  }

  Future<StaffInvoice> staffSendInvoiceReminder(
    String invoiceId, {
    String? note,
  }) async {
    final payload = <String, dynamic>{
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    };

    final res = await _post(
      Uri.parse('$baseUrl/api/staff/invoices/$invoiceId/remind'),
      headers: _headers(json: true),
      body: jsonEncode(payload),
    );
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final invoiceJson = body['invoice'];
    if (invoiceJson is Map<String, dynamic>) {
      return StaffInvoice.fromJson(invoiceJson);
    }
    throw Exception(
      'KhÃ´ng nháº­n Ä‘Æ°á»£c dá»¯ liá»‡u hoÃ¡ Ä‘Æ¡n cáº­p nháº­t',
    );
  }

  Future<StaffInvoice> staffUpdateInvoiceStatus(
    String invoiceId, {
    required String status,
    bool? paid,
    DateTime? paidAt,
  }) async {
    final payload = <String, dynamic>{
      'status': status,
      if (paid != null) 'paid': paid,
      if (paidAt != null) 'paidAt': paidAt.toUtc().toIso8601String(),
    };

    final res = await _patch(
      Uri.parse('$baseUrl/api/staff/invoices/$invoiceId/status'),
      headers: _headers(json: true),
      body: jsonEncode(payload),
    );
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final invoiceJson = body['invoice'];
    if (invoiceJson is Map<String, dynamic>) {
      return StaffInvoice.fromJson(invoiceJson);
    }
    throw Exception(
      'KhÃ´ng nháº­n Ä‘Æ°á»£c dá»¯ liá»‡u hoÃ¡ Ä‘Æ¡n cáº­p nháº­t',
    );
  }

  Future<Sport?> staffUpdateSport(
    String id,
    Map<String, dynamic> updates,
  ) async {
    final res = await _put(
      Uri.parse('$baseUrl/api/staff/sports/$id'),
      headers: _headers(json: true),
      body: jsonEncode(updates),
    );
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final body = res.body.trim();
    if (body.isEmpty) return null;
    return Sport.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  Future<void> staffDeleteSport(String id) async {
    final res = await _delete(
      Uri.parse('$baseUrl/api/staff/sports/$id'),
      headers: _headers(),
    );
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
  }

  Future<Court> staffCreateCourt({
    required String name,
    required String sportId,
    String? code,
    String status = 'active',
  }) async {
    final payload = <String, dynamic>{
      'name': name,
      'sportId': sportId,
      if (code != null) 'code': code,
      'status': status,
    };
    final res = await _post(
      Uri.parse('$baseUrl/api/staff/courts'),
      headers: _headers(json: true),
      body: jsonEncode(payload),
    );
    if (res.statusCode != 201) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final body = res.body.trim();
    if (body.isEmpty) {
      throw Exception('MÃ¡y chá»§ khÃ´ng tráº£ vá» dá»¯ liá»‡u sÃ¢n má»›i');
    }
    return Court.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  Future<Court?> staffUpdateCourt(
    String id,
    Map<String, dynamic> updates,
  ) async {
    final res = await _put(
      Uri.parse('$baseUrl/api/staff/courts/$id'),
      headers: _headers(json: true),
      body: jsonEncode(updates),
    );
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final body = res.body.trim();
    if (body.isEmpty) return null;
    return Court.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  Future<void> staffDeleteCourt(String id) async {
    final res = await _delete(
      Uri.parse('$baseUrl/api/staff/courts/$id'),
      headers: _headers(),
    );
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
  }

  Future<List<PriceProfile>> adminGetPriceProfiles({
    String? facilityId,
    String? sportId,
    String? courtId,
  }) async {
    final uri = Uri.parse('$baseUrl/api/admin/price-profiles').replace(
      queryParameters: {
        if (facilityId != null) 'facilityId': facilityId,
        if (sportId != null) 'sportId': sportId,
        if (courtId != null) 'courtId': courtId,
      },
    );
    final res = await _get(uri, headers: _headers());
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final List data = jsonDecode(res.body) as List;
    return data
        .map((e) => PriceProfile.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<PriceProfile>> staffGetPriceProfiles({
    String? facilityId,
    String? sportId,
    String? courtId,
  }) async {
    final uri = Uri.parse('$baseUrl/api/staff/price-profiles').replace(
      queryParameters: {
        if (facilityId != null) 'facilityId': facilityId,
        if (sportId != null) 'sportId': sportId,
        if (courtId != null) 'courtId': courtId,
      },
    );
    final res = await _get(uri, headers: _headers());
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final List data = jsonDecode(res.body) as List;
    return data
        .map((e) => PriceProfile.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> adminUpsertPriceProfile(
    Map<String, dynamic> payload,
  ) async {
    final res = await _post(
      Uri.parse('$baseUrl/api/admin/price-profiles/upsert'),
      headers: _headers(json: true),
      body: jsonEncode(payload),
    );
    if (res.statusCode != 200) {
      // Try to parse error details from server response
      String errorMsg = 'HTTP ${res.statusCode}';
      try {
        final errBody = jsonDecode(res.body) as Map<String, dynamic>;
        if (errBody['message'] != null) {
          errorMsg += ': ${errBody['message']}';
        }
        if (errBody['errInfo'] != null) {
          errorMsg += '\nDetails: ${errBody['errInfo']}';
        }
      } catch (_) {
        errorMsg += ': ${res.body}';
      }
      throw Exception(errorMsg);
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> staffUpsertPriceProfile(
    Map<String, dynamic> payload,
  ) async {
    final res = await _post(
      Uri.parse('$baseUrl/api/staff/price-profiles/upsert'),
      headers: _headers(json: true),
      body: jsonEncode(payload),
    );
    if (res.statusCode != 200) {
      String errorMsg = 'HTTP ${res.statusCode}';
      try {
        final errBody = jsonDecode(res.body) as Map<String, dynamic>;
        final error = errBody['error'] ?? errBody['message'];
        if (error != null) {
          errorMsg += ': $error';
        }
        if (errBody['errInfo'] != null) {
          errorMsg += '\nDetails: ${errBody['errInfo']}';
        }
      } catch (_) {
        errorMsg += ': ${res.body}';
      }
      throw Exception(errorMsg);
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // Raw fetch for price profiles (includes rules etc.)
  Future<List<Map<String, dynamic>>> adminGetPriceProfilesRaw({
    String? facilityId,
    String? sportId,
    String? courtId,
  }) async {
    final uri = Uri.parse('$baseUrl/api/admin/price-profiles').replace(
      queryParameters: {
        if (facilityId != null) 'facilityId': facilityId,
        if (sportId != null) 'sportId': sportId,
        if (courtId != null) 'courtId': courtId,
      },
    );
    final res = await _get(uri, headers: _headers());
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final List data = jsonDecode(res.body) as List;
    return data.cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> staffGetPriceProfilesRaw({
    String? facilityId,
    String? sportId,
    String? courtId,
  }) async {
    final uri = Uri.parse('$baseUrl/api/staff/price-profiles').replace(
      queryParameters: {
        if (facilityId != null) 'facilityId': facilityId,
        if (sportId != null) 'sportId': sportId,
        if (courtId != null) 'courtId': courtId,
      },
    );
    final res = await _get(uri, headers: _headers());
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final List data = jsonDecode(res.body) as List;
    return data.cast<Map<String, dynamic>>();
  }

  // --- Auth APIs ---
  // --- Users (admin) ---
  Future<List<AppUser>> adminGetUsers({
    String? role,
    String? status,
    String? q,
  }) async {
    final uri = Uri.parse('$baseUrl/api/admin/users').replace(
      queryParameters: {
        if (role != null && role.isNotEmpty) 'role': role,
        if (status != null && status.isNotEmpty) 'status': status,
        if (q != null && q.isNotEmpty) 'q': q,
      },
    );
    final res = await _get(uri, headers: _headers());
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final List data = jsonDecode(res.body) as List;
    return data
        .map((e) => AppUser.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> adminCreateUser({
    required String email,
    required String password,
    String? name,
    String role = 'customer',
    String status = 'active',
    String? facilityId,
    String? gender,
    DateTime? dateOfBirth,
    String? mainSportId,
    String? phone,
  }) async {
    final res = await _post(
      Uri.parse('$baseUrl/api/admin/users'),
      headers: _headers(json: true),
      body: jsonEncode({
        'email': email,
        'password': password,
        if (name != null) 'name': name,
        'role': role,
        'status': status,
        if (facilityId != null) 'facilityId': facilityId,
        if (gender != null) 'gender': gender,
        if (dateOfBirth != null) 'dateOfBirth': dateOfBirth.toIso8601String(),
        if (mainSportId != null) 'mainSportId': mainSportId,
        if (phone != null) 'phone': phone,
      }),
    );
    if (res.statusCode != 201) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<AppUser> adminUpdateUser(
    String id, {
    String? name,
    String? phone,
    String? role,
    String? status,
    String? facilityId,
    String? gender,
    DateTime? dateOfBirth,
    String? mainSportId,
    String? resetPassword,
  }) async {
    final payload = <String, dynamic>{};
    if (name != null) payload['name'] = name;
    if (phone != null) payload['phone'] = phone;
    if (role != null) payload['role'] = role;
    if (status != null) payload['status'] = status;
    if (facilityId != null) payload['facilityId'] = facilityId;
    if (gender != null) payload['gender'] = gender;
    if (dateOfBirth != null) {
      payload['dateOfBirth'] = dateOfBirth.toIso8601String();
    }
    if (mainSportId != null) payload['mainSportId'] = mainSportId;
    if (resetPassword != null && resetPassword.isNotEmpty) {
      payload['resetPassword'] = resetPassword;
    }

    if (payload.isEmpty) {
      throw Exception('Không có thay đổi nào được gửi lên');
    }

    final res = await _put(
      Uri.parse('$baseUrl/api/admin/users/$id'),
      headers: _headers(json: true),
      body: jsonEncode(payload),
    );
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    return AppUser.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<void> adminDeleteUser(String id) async {
    final res = await _delete(
      Uri.parse('$baseUrl/api/admin/users/$id'),
      headers: _headers(),
    );
    if (res.statusCode == 200 || res.statusCode == 404) {
      // Treat 404 as success because the record is already gone on the server.
      return;
    }
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
  }

  Future<List<AuditLog>> adminGetAuditLogs({
    int limit = 100,
    String? action,
    String? resource,
    String? actorId,
    DateTime? since,
    DateTime? until,
  }) async {
    final query = <String, String>{'limit': limit.toString()};
    if (action != null && action.isNotEmpty) query['action'] = action;
    if (resource != null && resource.isNotEmpty) query['resource'] = resource;
    if (actorId != null && actorId.isNotEmpty) query['actorId'] = actorId;
    if (since != null) query['since'] = since.toIso8601String();
    if (until != null) query['until'] = until.toIso8601String();
    final uri = Uri.parse(
      '$baseUrl/api/admin/audit-logs',
    ).replace(queryParameters: query);
    final res = await _get(uri, headers: _headers());
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final List data = jsonDecode(res.body) as List;
    return data
        .map((e) => AuditLog.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final res = await _post(
      Uri.parse('$baseUrl/api/auth/login'),
      headers: _headers(json: true),
      body: jsonEncode({'email': email, 'password': password}),
    );
    if (res.statusCode != 200) {
      try {
        final err = jsonDecode(res.body) as Map<String, dynamic>;
        throw Exception(err['error'] ?? 'HTTP ${res.statusCode}');
      } catch (_) {
        throw Exception('HTTP ${res.statusCode}: ${res.body}');
      }
    }
    return jsonDecode(res.body) as Map<String, dynamic>; // { token, user }
  }

  Future<AppUser> registerFirebaseUser({
    required String idToken,
    String? name,
    String? gender,
    DateTime? dateOfBirth,
    String? mainSportId,
  }) async {
    final payload = <String, dynamic>{
      'idToken': idToken,
      if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      if (gender != null && gender.trim().isNotEmpty) 'gender': gender.trim(),
      if (dateOfBirth != null) 'dateOfBirth': dateOfBirth.toIso8601String(),
      if (mainSportId != null && mainSportId.trim().isNotEmpty)
        'mainSportId': mainSportId.trim(),
    };

    final res = await _post(
      Uri.parse('$baseUrl/api/auth/register-firebase'),
      headers: _headers(json: true),
      body: jsonEncode(payload),
    );

    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }

    final body = res.body.trim();
    if (body.isEmpty) {
      throw Exception('Máy chủ không trả về thông tin người dùng');
    }

    final data = jsonDecode(body);
    final userJson = data is Map<String, dynamic>
        ? (data['user'] is Map<String, dynamic>
            ? data['user'] as Map<String, dynamic>
            : data)
        : <String, dynamic>{};
    if (userJson.isEmpty) {
      throw Exception('Thiếu dữ liệu người dùng sau khi đăng ký');
    }
    return AppUser.fromJson(userJson);
  }

  Future<AppUser> fetchCurrentUser() async {
    final res = await _get(
      Uri.parse('$baseUrl/api/auth/me'),
      headers: _headers(),
    );
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }

    final body = res.body.trim();
    if (body.isEmpty) {
      throw Exception('Không nhận được dữ liệu người dùng');
    }
    final data = jsonDecode(body);
    final userJson = data is Map<String, dynamic>
        ? (data['user'] is Map<String, dynamic>
            ? data['user'] as Map<String, dynamic>
            : data)
        : <String, dynamic>{};
    if (userJson.isEmpty) {
      throw Exception('Thiếu dữ liệu người dùng từ API');
    }
    return AppUser.fromJson(userJson);
  }

  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    String? name,
    String? gender,
    DateTime? dateOfBirth,
    String? mainSportId,
  }) async {
    final res = await _post(
      Uri.parse('$baseUrl/api/auth/register'),
      headers: _headers(json: true),
      body: jsonEncode({
        'email': email,
        'password': password,
        if (name != null) 'name': name,
        if (gender != null) 'gender': gender,
        if (dateOfBirth != null) 'dateOfBirth': dateOfBirth.toIso8601String(),
        if (mainSportId != null) 'mainSportId': mainSportId,
      }),
    );
    if (res.statusCode != 201) {
      try {
        final err = jsonDecode(res.body) as Map<String, dynamic>;
        throw Exception(err['error'] ?? 'HTTP ${res.statusCode}');
      } catch (_) {
        throw Exception('HTTP ${res.statusCode}: ${res.body}');
      }
    }
    return jsonDecode(res.body) as Map<String, dynamic>; // { token, user }
  }

  Future<bool> checkAvailability(
    String courtId,
    DateTime start,
    DateTime end,
  ) async {
    final uri = Uri.parse('$baseUrl/api/courts/$courtId/availability').replace(
      queryParameters: {
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
      },
    );
    final res = await _get(uri, headers: _headers());
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    return map['available'] == true;
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
    final res = await _post(
      Uri.parse('$baseUrl/api/price/quote'),
      headers: _headers(json: true),
      body: jsonEncode({
        'facilityId': facilityId,
        'sportId': sportId,
        'courtId': courtId,
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        'currency': currency,
        if (userId != null) 'userId': userId,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
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
    List<String>? participants,
    String? voucherId,
    String status = 'pending',
  }) async {
    final res = await _post(
      Uri.parse('$baseUrl/api/bookings'),
      headers: _headers(json: true),
      body: jsonEncode({
        'customerId': customerId,
        'facilityId': facilityId,
        'courtId': courtId,
        'sportId': sportId,
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        'status': status,
        'participants': participants ?? [],
        if (voucherId != null) 'voucherId': voucherId,
        'currency': currency,
        'pricingSnapshot': pricingSnapshot,
      }),
    );
    if (res.statusCode != 201) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // --- Admin Bookings ---
  Future<List<Booking>> adminGetBookings({
    String? facilityId,
    String? courtId,
    String? sportId,
    String? userId,
    String? status,
    DateTime? from,
    DateTime? to,
    bool includeDeleted = false,
  }) async {
    final uri = Uri.parse('$baseUrl/api/admin/bookings').replace(
      queryParameters: {
        if (facilityId != null) 'facilityId': facilityId,
        if (courtId != null) 'courtId': courtId,
        if (sportId != null) 'sportId': sportId,
        if (userId != null) 'userId': userId,
        if (status != null) 'status': status,
        if (from != null) 'from': from.toIso8601String(),
        if (to != null) 'to': to.toIso8601String(),
        if (includeDeleted) 'includeDeleted': 'true',
      },
    );
    final res = await _get(uri, headers: _headers());
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final List data = jsonDecode(res.body) as List;
    return data
        .map((e) => Booking.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> adminUpdateBooking(
    String id,
    Map<String, dynamic> updates,
  ) async {
    final res = await _put(
      Uri.parse('$baseUrl/api/admin/bookings/$id'),
      headers: _headers(json: true),
      body: jsonEncode(updates),
    );
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> adminDeleteBooking(String id) async {
    final res = await _delete(
      Uri.parse('$baseUrl/api/admin/bookings/$id'),
      headers: _headers(),
    );
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
  }
}

class _AuthInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    ApiService.refreshAuthToken().then((token) {
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      } else {
        options.headers.remove('Authorization');
      }
      handler.next(options);
    }).catchError((error, stackTrace) {
      final fallback = ApiService.authToken;
      if (fallback != null && fallback.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $fallback';
      } else {
        options.headers.remove('Authorization');
      }
      handler.next(options);
    });
  }
}

class _Response {
  const _Response(this.statusCode, this.body);

  final int statusCode;
  final String body;
}
