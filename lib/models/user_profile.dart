import '../utils/json_utils.dart';

class UserProfile {
  final String id;
  final String email;
  final String? name;
  final String? phone;
  final List<String> sportsPreferences;
  final String membershipTier;
  final DateTime? membershipExpiresAt;
  final String? gender;
  final DateTime? dateOfBirth;
  final String? mainSportId;

  const UserProfile({
    required this.id,
    required this.email,
    this.name,
    this.phone,
    this.sportsPreferences = const [],
    this.membershipTier = 'silver',
    this.membershipExpiresAt,
    this.gender,
    this.dateOfBirth,
    this.mainSportId,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final prefsRaw = json['sportsPreferences'];
    final prefs = <String>[];
    if (prefsRaw is List) {
      for (final item in prefsRaw) {
        final value = item?.toString();
        if (value != null && value.isNotEmpty) {
          prefs.add(value);
        }
      }
    }

    DateTime? expires;
    final expiryRaw = json['membershipExpiresAt'];
    if (expiryRaw is String && expiryRaw.isNotEmpty) {
      expires = DateTime.tryParse(expiryRaw);
    } else if (expiryRaw is int) {
      expires = DateTime.fromMillisecondsSinceEpoch(expiryRaw);
    }

    DateTime? dob;
    final dobRaw = json['dateOfBirth'];
    if (dobRaw is String && dobRaw.isNotEmpty) {
      dob = DateTime.tryParse(dobRaw);
    } else if (dobRaw is int) {
      dob = DateTime.fromMillisecondsSinceEpoch(dobRaw);
    } else if (dobRaw is Map) {
      final raw = dobRaw[r'$date'] ?? dobRaw['date'];
      if (raw is String) {
        dob = DateTime.tryParse(raw);
      }
    }

    return UserProfile(
      id: JsonUtils.parseId(json['_id'] ?? json['id']),
      email: (json['email'] ?? '').toString(),
      name: json['name']?.toString(),
      phone: json['phone']?.toString(),
      sportsPreferences: prefs,
      membershipTier: (json['membershipTier'] ?? 'silver')
          .toString()
          .trim()
          .toLowerCase(),
      membershipExpiresAt: expires,
      gender: json['gender']?.toString().trim().toLowerCase(),
      dateOfBirth: dob,
      mainSportId: JsonUtils.parseIdOrNull(json['mainSportId']),
    );
  }
}
