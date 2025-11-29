import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user.dart';
import '../models/staff_profile.dart';
import '../models/user_profile.dart';
import 'api_service.dart';

class AuthService extends ChangeNotifier {
  static final AuthService instance = AuthService._internal();
  AuthService._internal() {
    ApiService.registerTokenProvider(() => getIdToken());
  }

  final _api = ApiService();
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  String? _token;
  AppUser? _user;

  static const String tokenStorageKey = 'auth_token';
  static const String userStorageKey = 'auth_user';
  static const String roleStorageKey = 'auth_role';

  String? get token => _token;
  AppUser? get currentUser => _user;
  bool get isLoggedIn => _token != null && _user != null;

  /// Đăng ký Firebase email/password và gửi email xác thực nếu cần
  Future<User?> signUpWithEmail(String email, String password) async {
    try {
      final cred = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = cred.user;
      if (user != null && !user.emailVerified) {
        await user.sendEmailVerification();
      }
      return user;
    } on FirebaseAuthException {
      rethrow;
    }
  }

  /// Đăng nhập Firebase email/password
  Future<User?> signInWithEmail(String email, String password) async {
    try {
      final cred = await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return cred.user;
    } on FirebaseAuthException {
      rethrow;
    }
  }

  /// Gửi lại email xác thực cho user hiện tại
  Future<void> sendVerificationEmail() async {
    final user = _firebaseAuth.currentUser;
    if (user != null && !user.emailVerified) {
      await user.sendEmailVerification();
    }
  }

  /// Reload user và trả về trạng thái email verified
  Future<bool> reloadAndCheckVerified() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return false;
    await user.reload();
    return _firebaseAuth.currentUser?.emailVerified ?? false;
  }

  /// Lấy Firebase ID token để gửi về backend
  Future<String?> getIdToken() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return null;
    return user.getIdToken(true);
  }

  /// Đăng xuất khỏi FirebaseAuth
  Future<void> signOut() async {
    await _firebaseAuth.signOut();
  }

  Future<void> applyFirebaseUserSession({
    required String token,
    required AppUser user,
  }) async {
    _token = token;
    _user = user;
    ApiService.setAuthToken(token);
    notifyListeners();
  }

  Future<void> persistSession() async {
    final token = _token;
    final user = _user;
    if (token == null || token.isEmpty || user == null) {
      await _clearStoredSession();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(tokenStorageKey, token);
    await prefs.setString(userStorageKey, jsonEncode(user.toJson()));
    await prefs.setString(roleStorageKey, user.role);
  }

  Future<void> login(String email, String password) async {
    final response = await _api.login(email: email, password: password);
    _applySession(response);
  }

  Future<void> register(
    String email,
    String password, {
    String? name,
    String? gender,
    DateTime? dateOfBirth,
    String? mainSportId,
  }) async {
    final response = await _api.register(
      email: email,
      password: password,
      name: name,
      gender: gender,
      dateOfBirth: dateOfBirth,
      mainSportId: mainSportId,
    );
    _applySession(response);
  }

  Future<void> logout() async {
    await _firebaseAuth.signOut();
    _resetSession();
    await _clearStoredSession();
  }

  void _applySession(Map<String, dynamic> payload) {
    final token = payload['token'] as String?;
    final rawUser = payload['user'] as Map<String, dynamic>?;
    if (token == null || token.isEmpty || rawUser == null) {
      _token = null;
      _user = null;
      ApiService.clearAuthToken();
      throw Exception('Dữ liệu đăng nhập không hợp lệ');
    }

    final user = AppUser.fromJson(rawUser);
    if (user.status != 'active') {
      _token = null;
      _user = null;
      ApiService.clearAuthToken();
      throw Exception('Tài khoản đang bị khóa hoặc không hoạt động');
    }

    _token = token;
    _user = user;
    ApiService.setAuthToken(token);
    notifyListeners();
  }

  Future<void> restoreSessionFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final storedToken = prefs.getString(tokenStorageKey);
    final storedUser = prefs.getString(userStorageKey);

    if (storedToken == null ||
        storedToken.isEmpty ||
        storedUser == null ||
        storedUser.isEmpty) {
      return;
    }

    try {
      final decoded = jsonDecode(storedUser);
      if (decoded is! Map<String, dynamic>) {
        _resetSession();
        await _clearStoredSession(prefs);
        return;
      }
      final user = AppUser.fromJson(decoded);
      if (user.status != 'active') {
        _resetSession();
        await _clearStoredSession(prefs);
        return;
      }
      _token = storedToken;
      _user = user;
      ApiService.setAuthToken(storedToken);
      notifyListeners();
    } catch (_) {
      _resetSession();
      await _clearStoredSession(prefs);
    }
  }

  Future<void> _clearStoredSession([SharedPreferences? prefs]) async {
    final storage = prefs ?? await SharedPreferences.getInstance();
    await storage.remove(tokenStorageKey);
    await storage.remove(userStorageKey);
    await storage.remove(roleStorageKey);
  }

  void _resetSession() {
    _token = null;
    _user = null;
    ApiService.clearAuthToken();
    notifyListeners();
  }

  void updateFromProfile(StaffProfile profile) {
    final current = _user;
    if (current == null) return;
    final updated = AppUser(
      id: profile.id?.isNotEmpty == true ? profile.id! : current.id,
      email: profile.email ?? current.email,
      name: profile.name,
      role: current.role,
      status: current.status,
      phone: profile.phone,
      facilityId: profile.facilityId ?? current.facilityId,
      dateOfBirth: current.dateOfBirth,
      gender: current.gender,
      mainSportId: current.mainSportId,
    );
    _user = updated;
    notifyListeners();
  }

  void updateFromUserProfile(UserProfile profile) {
    final current = _user;
    if (current == null) return;
    _user = AppUser(
      id: current.id,
      email: current.email,
      name: profile.name,
      role: current.role,
      status: current.status,
      phone: profile.phone,
      facilityId: current.facilityId,
      dateOfBirth: profile.dateOfBirth,
      gender: profile.gender,
      mainSportId: profile.mainSportId,
    );
    notifyListeners();
  }

  Future<AppUser> reloadCurrentUser() async {
    final refreshed = await _api.fetchCurrentUser();
    _user = refreshed;
    notifyListeners();
    await persistSession();
    return refreshed;
  }
}
