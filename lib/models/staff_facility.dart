import 'court.dart';
import 'facility.dart';
import 'maintenance.dart';

List<String> _stringList(dynamic value) {
  if (value == null) return const [];
  if (value is List) {
    return value
        .map((item) => item == null ? '' : item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
  if (value is String) {
    final cleaned = value
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    return cleaned;
  }
  return const [];
}

class StaffCourt {
  final Court court;
  final List<String> amenities;
  final List<Maintenance> maintenance;

  const StaffCourt({
    required this.court,
    this.amenities = const [],
    this.maintenance = const [],
  });

  String get id => court.id;
  String get name => court.name;
  String? get status => court.status;
  String get facilityId => court.facilityId;

  factory StaffCourt.fromJson(Map<String, dynamic> json) {
    final maintenanceJson = json['maintenance'];
    final maintenanceList = maintenanceJson is List
        ? maintenanceJson
              .whereType<Map<String, dynamic>>()
              .map(Maintenance.fromJson)
              .toList()
        : <Maintenance>[];
    maintenanceList.sort((a, b) {
      final aStart = a.start ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bStart = b.start ?? DateTime.fromMillisecondsSinceEpoch(0);
      return aStart.compareTo(bStart);
    });

    return StaffCourt(
      court: Court.fromJson(json),
      amenities: _stringList(json['amenities']),
      maintenance: maintenanceList,
    );
  }
}

class StaffFacilityData {
  final Facility facility;
  final List<StaffCourt> courts;

  const StaffFacilityData({required this.facility, required this.courts});

  factory StaffFacilityData.fromJson(Map<String, dynamic> json) {
    final facilityJson = json['facility'] as Map<String, dynamic>?;
    if (facilityJson == null) {
      throw ArgumentError('Missing facility payload');
    }
    final courtsJson = json['courts'] as List? ?? const [];
    final courts = courtsJson
        .whereType<Map<String, dynamic>>()
        .map(StaffCourt.fromJson)
        .toList();
    courts.sort((a, b) => a.name.compareTo(b.name));
    return StaffFacilityData(
      facility: Facility.fromJson(facilityJson),
      courts: courts,
    );
  }
}
