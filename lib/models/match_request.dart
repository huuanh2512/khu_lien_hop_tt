import '../utils/json_utils.dart';

class MatchRequest {
  final String id;
  final String sportId;
  final String? sportName;
  final String? facilityId;
  final String? facilityName;
  final String? courtId;
  final String? courtName;
  final DateTime? desiredStart;
  final DateTime? desiredEnd;
  final int? skillMin;
  final int? skillMax;
  final String status;
  final String visibility;
  final String? creatorId;
  final List<String> participants;
  final int participantCount;
  final int? participantLimit;
  final int? teamSize;
  final bool isCreator;
  final bool hasJoined;
  final List<String> teamA;
  final List<String> teamB;
  final String? myTeam;
  final int? teamLimit;
  final String? notes;
  final String? bookingId;
  final String? bookingStatus;
  final DateTime? bookingStart;
  final DateTime? bookingEnd;
  final DateTime? cancelledAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const MatchRequest({
    required this.id,
    required this.sportId,
    this.sportName,
    this.facilityId,
    this.facilityName,
    this.courtId,
    this.courtName,
    this.desiredStart,
    this.desiredEnd,
    this.skillMin,
    this.skillMax,
    required this.status,
    required this.visibility,
    this.creatorId,
    this.participants = const [],
    this.participantCount = 0,
    this.participantLimit,
    this.teamSize,
    this.isCreator = false,
    this.hasJoined = false,
    this.teamA = const <String>[],
    this.teamB = const <String>[],
    this.myTeam,
    this.teamLimit,
    this.notes,
    this.bookingId,
    this.bookingStatus,
    this.bookingStart,
    this.bookingEnd,
    this.cancelledAt,
    this.createdAt,
    this.updatedAt,
  });

  factory MatchRequest.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic value) {
      if (value is DateTime) return value;
      if (value is String && value.isNotEmpty) {
        return DateTime.tryParse(value);
      }
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value);
      }
      return null;
    }

    final participantsRaw = json['participants'];
    final participants = <String>[];
    if (participantsRaw is List) {
      for (final item in participantsRaw) {
        final id = JsonUtils.parseId(item);
        if (id.isNotEmpty) participants.add(id);
      }
    }

    final skillRange = json['skillRange'];
    int? parseSkill(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) return parsed;
      }
      return null;
    }

    final status = (json['status'] ?? 'open').toString();
    final visibility = (json['visibility'] ?? 'public').toString();

    int? parseCount(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value);
      return null;
    }

    List<String> parseTeam(dynamic value) {
      final members = <String>[];
      if (value is List) {
        for (final item in value) {
          final id = JsonUtils.parseId(item);
          if (id.isNotEmpty) members.add(id);
        }
      } else if (value is Map<String, dynamic>) {
        final nested = value['members'];
        if (nested is List) {
          for (final item in nested) {
            final id = JsonUtils.parseId(item);
            if (id.isNotEmpty) members.add(id);
          }
        }
      }
      return members;
    }

    final teamsRaw = json['teams'];
    List<String> teamA = const [];
    List<String> teamB = const [];
    if (teamsRaw is Map<String, dynamic>) {
      teamA = parseTeam(teamsRaw['teamA']);
      teamB = parseTeam(teamsRaw['teamB']);
    }

    final participantSet = <String>{...participants, ...teamA, ...teamB};
    final participantList = participantSet.toList(growable: false);

    String? normalizeTeam(dynamic rawTeam) {
      if (rawTeam is String) {
        final trimmed = rawTeam.trim();
        if (trimmed.isEmpty) return null;
        final normalized = trimmed.toLowerCase();
        const aliasesA = {'teama', 'team a', 'team_a', 'team-a', 'a', 'team1'};
        const aliasesB = {'teamb', 'team b', 'team_b', 'team-b', 'b', 'team2'};
        if (aliasesA.contains(normalized)) return 'teamA';
        if (aliasesB.contains(normalized)) return 'teamB';
        if (trimmed == 'teamA' || trimmed == 'teamB') return trimmed;
      } else if (rawTeam is Map<String, dynamic>) {
        return normalizeTeam(rawTeam['value']);
      }
      return null;
    }

    final myTeam = normalizeTeam(json['myTeam']);

    final participantCount =
        parseCount(json['participantCount']) ?? participantList.length;

    return MatchRequest(
      id: JsonUtils.parseId(json['id'] ?? json['_id']),
      sportId: JsonUtils.parseId(json['sportId']),
      sportName: json['sportName']?.toString(),
      facilityId: JsonUtils.parseIdOrNull(json['facilityId']),
      facilityName: json['facilityName']?.toString(),
      courtId: JsonUtils.parseIdOrNull(json['courtId']),
      courtName: json['courtName']?.toString(),
      desiredStart: parseDate(json['desiredStart']),
      desiredEnd: parseDate(json['desiredEnd']),
      skillMin: parseSkill(
        skillRange is Map<String, dynamic>
            ? skillRange['min']
            : json['skillMin'],
      ),
      skillMax: parseSkill(
        skillRange is Map<String, dynamic>
            ? skillRange['max']
            : json['skillMax'],
      ),
      status: status,
      visibility: visibility,
      creatorId: JsonUtils.parseId(json['creatorId']),
      participants: participantList,
      participantCount: participantCount,
      participantLimit: parseCount(json['participantLimit']),
      teamSize: parseCount(json['teamSize']),
      isCreator: json['isCreator'] == true,
      hasJoined: json['hasJoined'] == true || (myTeam != null),
      teamA: teamA,
      teamB: teamB,
      myTeam: myTeam,
      teamLimit: parseCount(json['teamLimit']),
      notes: json['notes']?.toString(),
      bookingId: JsonUtils.parseIdOrNull(json['bookingId']),
      bookingStatus: json['bookingStatus']?.toString(),
      bookingStart: parseDate(json['bookingStart']),
      bookingEnd: parseDate(json['bookingEnd']),
      cancelledAt: parseDate(json['cancelledAt']),
      createdAt: parseDate(json['createdAt']),
      updatedAt: parseDate(json['updatedAt']),
    );
  }
}
