import '../utils/json_utils.dart';

class Sport {
  final String id;
  final String name;
  final String code;
  final int? teamSize;
  final int? courtCount;
  final bool? active;

  const Sport({
    required this.id,
    required this.name,
    required this.code,
    this.teamSize,
    this.courtCount,
    this.active,
  });

  factory Sport.fromJson(Map<String, dynamic> json) {
    return Sport(
      id: JsonUtils.parseId(json['_id']),
      name: (json['name'] ?? '').toString(),
      code: (json['code'] ?? '').toString(),
      teamSize: json['teamSize'] is int
          ? json['teamSize'] as int
          : (json['teamSize'] is num
                ? (json['teamSize'] as num).toInt()
                : null),
      courtCount: json['courtCount'] is int
          ? json['courtCount'] as int
          : (json['courtCount'] is num
                ? (json['courtCount'] as num).toInt()
                : null),
      active: json['active'] is bool ? json['active'] as bool : null,
    );
  }
}
