import 'dart:async';

import 'package:flutter/material.dart';
import 'package:neubrutalism_ui/neubrutalism_ui.dart';

import 'package:khu_lien_hop_tt/models/court.dart';
import 'package:khu_lien_hop_tt/models/facility.dart';
import 'package:khu_lien_hop_tt/models/match_request.dart';
import 'package:khu_lien_hop_tt/models/sport.dart';
import 'package:khu_lien_hop_tt/screens/auth/login_page.dart';
import 'package:khu_lien_hop_tt/screens/verify_email_screen.dart';
import 'package:khu_lien_hop_tt/services/api_service.dart';
import 'package:khu_lien_hop_tt/services/auth_service.dart';
import 'package:khu_lien_hop_tt/utils/api_error_utils.dart';
import 'package:khu_lien_hop_tt/widgets/error_state_widget.dart';
import 'package:khu_lien_hop_tt/widgets/success_dialog.dart';
import 'package:khu_lien_hop_tt/widgets/neu_button.dart';
import 'package:khu_lien_hop_tt/widgets/neo_loading.dart';

class _TeamVariantOption {
  final String id;
  final String label;
  final int teamSizePerSide;
  final int? totalParticipants;

  const _TeamVariantOption({
    required this.id,
    required this.label,
    required this.teamSizePerSide,
    this.totalParticipants,
  });
}

class _AutoCancelProcessResult {
  final List<MatchRequest> requests;
  final Set<String> autoCancelledIds;

  const _AutoCancelProcessResult({
    required this.requests,
    required this.autoCancelledIds,
  });
}

class MatchRequestsPage extends StatefulWidget {
  const MatchRequestsPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<MatchRequestsPage> createState() => _MatchRequestsPageState();
}

class _MatchRequestsPageState extends State<MatchRequestsPage> {
  final ApiService _api = ApiService();
  final TextEditingController _notesController = TextEditingController();
  static const List<_TeamVariantOption> _footballVariants = [
    _TeamVariantOption(
      id: 'football-5',
      label: 'Sân 5 (5v5)',
      teamSizePerSide: 5,
      totalParticipants: 10,
    ),
    _TeamVariantOption(
      id: 'football-7',
      label: 'Sân 7 (7v7)',
      teamSizePerSide: 7,
      totalParticipants: 14,
    ),
    _TeamVariantOption(
      id: 'football-11',
      label: 'Sân 11 (11v11)',
      teamSizePerSide: 11,
      totalParticipants: 22,
    ),
  ];
  static const List<_TeamVariantOption> _badmintonVariants = [
    _TeamVariantOption(
      id: 'badminton-singles',
      label: 'Đánh đơn (1v1)',
      teamSizePerSide: 1,
      totalParticipants: 2,
    ),
    _TeamVariantOption(
      id: 'badminton-doubles',
      label: 'Đánh đôi (2v2)',
      teamSizePerSide: 2,
      totalParticipants: 4,
    ),
  ];
  static const List<_TeamVariantOption> _tennisVariants = [
    _TeamVariantOption(
      id: 'tennis-singles',
      label: 'Single (1v1)',
      teamSizePerSide: 1,
      totalParticipants: 2,
    ),
    _TeamVariantOption(
      id: 'tennis-doubles',
      label: 'Double (2v2)',
      teamSizePerSide: 2,
      totalParticipants: 4,
    ),
  ];
  static const List<_TeamVariantOption> _tableTennisVariants = [
    _TeamVariantOption(
      id: 'table-tennis-singles',
      label: 'Đơn (1v1)',
      teamSizePerSide: 1,
      totalParticipants: 2,
    ),
    _TeamVariantOption(
      id: 'table-tennis-doubles',
      label: 'Đôi (2v2)',
      teamSizePerSide: 2,
      totalParticipants: 4,
    ),
  ];
  static const List<_TeamVariantOption> _basketballVariants = [
    _TeamVariantOption(
      id: 'basketball-3',
      label: '3v3 nửa sân',
      teamSizePerSide: 3,
      totalParticipants: 6,
    ),
    _TeamVariantOption(
      id: 'basketball-5',
      label: '5v5 toàn sân',
      teamSizePerSide: 5,
      totalParticipants: 10,
    ),
  ];
  static const List<_TeamVariantOption> _volleyballVariants = [
    _TeamVariantOption(
      id: 'volleyball-2',
      label: 'Sân 2v2',
      teamSizePerSide: 2,
      totalParticipants: 4,
    ),
    _TeamVariantOption(
      id: 'volleyball-4',
      label: 'Sân 4v4',
      teamSizePerSide: 4,
      totalParticipants: 8,
    ),
    _TeamVariantOption(
      id: 'volleyball-6',
      label: 'Sân 6v6',
      teamSizePerSide: 6,
      totalParticipants: 12,
    ),
  ];

  List<Sport> _sports = const [];
  List<Facility> _facilities = const [];
  List<Court> _courts = const [];
  List<MatchRequest> _requests = const [];
  String? _selectedSport;
  String? _selectedFacility;
  String? _selectedCourt;
  RangeValues _skillRange = const RangeValues(30, 70);
  DateTime? _desiredStart;
  int _desiredDurationHours = 2;
  int _participantLimit = 2;
  int _teamSizePerSide = 1;
  String _matchMode = 'solo';
  final TextEditingController _teamNameController = TextEditingController();
  bool _loading = true;
  bool _submitting = false;
  bool _loadingCourts = false;
  ApiErrorDetails? _error;
  final Set<String> _joining = <String>{};
  final Set<String> _cancelling = <String>{};
  final Set<String> _autoCancelledRequestIds = <String>{};
  Timer? _autoCancelTicker;
  String? _filterSportId;
  bool _filterOnlyOpen = true;
  bool _filterOnlyMine = false;
  String? _selectedVariantId;

  bool get _isTeamMode => _matchMode == 'team';

  @override
  void initState() {
    super.initState();
    _desiredStart = _roundToNextHour(
      DateTime.now().add(const Duration(hours: 1)),
    );
    _load();
    _startAutoCancelTicker();
  }

  @override
  void dispose() {
    _autoCancelTicker?.cancel();
    _notesController.dispose();
    _teamNameController.dispose();
    super.dispose();
  }

  DateTime _roundToNextHour(DateTime value) {
    final nextHour = value.add(Duration(hours: value.minute > 0 ? 1 : 0));
    return DateTime(nextHour.year, nextHour.month, nextHour.day, nextHour.hour);
  }

  DateTime? _computeEndForStart(DateTime? start, [int? overrideHours]) {
    if (start == null) return null;
    final hours = overrideHours ?? _desiredDurationHours;
    return start.add(Duration(hours: hours));
  }

  void _startAutoCancelTicker() {
    _autoCancelTicker?.cancel();
    _autoCancelTicker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      final result = _autoCancelExpiredRequests(_requests);
      if (_shouldUpdateAutoCancelled(result.autoCancelledIds)) {
        setState(() => _updateAutoCancelledTracking(result.autoCancelledIds));
      }
    });
  }

  bool _shouldUpdateAutoCancelled(Set<String> next) {
    if (_autoCancelledRequestIds.length != next.length) return true;
    for (final id in next) {
      if (!_autoCancelledRequestIds.contains(id)) return true;
    }
    for (final id in _autoCancelledRequestIds) {
      if (!next.contains(id)) return true;
    }
    return false;
  }

  _AutoCancelProcessResult _autoCancelExpiredRequests(
    List<MatchRequest> requests,
  ) {
    final nowUtc = DateTime.now().toUtc();
    final cancelledIds = <String>{};
    for (final request in requests) {
      if (_shouldAutoCancelRequest(request, nowUtc)) {
        cancelledIds.add(request.id);
      }
    }
    return _AutoCancelProcessResult(
      requests: requests,
      autoCancelledIds: cancelledIds,
    );
  }

  bool _shouldAutoCancelRequest(MatchRequest request, DateTime nowUtc) {
    if (request.status.toLowerCase() != 'open') return false;
    final desiredStart = request.desiredStart;
    if (desiredStart == null) return false;
    final startUtc = desiredStart.toUtc();
    if (nowUtc.isBefore(startUtc)) return false;
    final required = _requiredParticipantsForRequest(request);
    final current = request.participantCount;
    return current < required;
  }

  int _requiredParticipantsForRequest(MatchRequest request) {
    final teamSize = request.teamSize ?? 0;
    if (teamSize > 0) {
      final total = teamSize * 2;
      return total < 2 ? 2 : total;
    }
    final limit = request.participantLimit ?? 0;
    if (limit >= 2) return limit;
    return 2;
  }

  void _updateAutoCancelledTracking(Set<String> ids) {
    _autoCancelledRequestIds
      ..clear()
      ..addAll(ids);
  }

  Sport? _getSportById(String? id) {
    if (id == null) return null;
    for (final sport in _sports) {
      if (sport.id == id) return sport;
    }
    return null;
  }

  bool _isPickleballSportById(String? id) {
    final sport = _getSportById(id);
    if (sport == null) return false;
    return _isPickleballSport(sport);
  }

  int _defaultLimitForSport(String? sportId) {
    final sport = _getSportById(sportId);
    final maxForSport = _maxParticipantsForSport(sportId);
    final size = sport?.teamSize ?? 0;
    var suggested = size > 0 ? size * 2 : 4;
    if (suggested < 2) suggested = 2;
    if (suggested > maxForSport) suggested = maxForSport;
    return suggested;
  }

  int _defaultTeamSizeForSport(String? sportId) {
    final sport = _getSportById(sportId);
    final size = sport?.teamSize ?? 0;
    if (sport != null && _isPickleballSport(sport)) {
      if (size <= 0) return 2;
      if (size < 1) return 1;
      if (size > 2) return 2;
      return size;
    }
    if (size <= 0) return 1;
    if (size > 20) return 20;
    return size;
  }

  int _maxParticipantsForSport(String? sportId) {
    final sport = _getSportById(sportId);
    if (sport == null) return 20;
    final size = sport.teamSize ?? 0;
    var total = size > 0 ? size * 2 : 20;
    if (total < 2) total = 2;
    if (total > 24) total = 24;
    return total;
  }

  int _maxTeamSizeForSport(String? sportId) {
    final sport = _getSportById(sportId);
    if (sport != null && _isPickleballSport(sport)) {
      return 2;
    }
    var size = sport?.teamSize ?? 0;
    if (size <= 0) {
      size = (_maxParticipantsForSport(sportId) / 2).floor();
    }
    if (size < 1) size = 1;
    if (size > 12) size = 12;
    return size;
  }

  int _minTeamSizeForMode({
    required bool isTeamMode,
    required String? sportId,
  }) {
    if (!isTeamMode) return 1;
    return _isPickleballSportById(sportId) ? 1 : 2;
  }

  int _maxTeamSizeForMode({
    required bool isTeamMode,
    required String? sportId,
  }) {
    final rawMax = _maxTeamSizeForSport(sportId);
    if (!isTeamMode) return rawMax;
    if (_isPickleballSportById(sportId)) return rawMax;
    return rawMax < 2 ? 2 : rawMax;
  }

  List<int> _teamSizeOptionsForCurrentSport() {
    final minSize = _minTeamSizeForMode(
      isTeamMode: _isTeamMode,
      sportId: _selectedSport,
    );
    final maxSize = _maxTeamSizeForMode(
      isTeamMode: _isTeamMode,
      sportId: _selectedSport,
    );
    final effectiveMax = maxSize < minSize ? minSize : maxSize;
    final count = (effectiveMax - minSize) + 1;
    return List<int>.generate(count, (index) => minSize + index);
  }

  List<int> _teamModeSizeOptions() {
    if (_isPickleballSportById(_selectedSport)) {
      return const [1, 2];
    }
    final minSize = _minTeamSizeForMode(isTeamMode: true, sportId: _selectedSport);
    final variants = _variantOptionsForCurrentSport()
        .map((variant) => variant.teamSizePerSide)
        .where((value) => value >= minSize)
        .toSet()
        .toList()
      ..sort();
    if (variants.isNotEmpty) return variants;
    final defaultSize = _defaultTeamSizeForSport(_selectedSport);
    final fallback = <int>{defaultSize, minSize, 3, 5, 7};
    final normalized = fallback.where((value) => value >= minSize && value <= 12).toList()
      ..sort();
    return normalized;
  }

  bool _hasTeamDetails(TeamInfo? info) {
    if (info == null) return false;
    return !info.isEmpty;
  }

  void _setMatchMode(String mode) {
    if (_matchMode == mode) return;
    setState(() {
      _matchMode = mode;
      if (_isTeamMode) {
        final minTeamSize = _minTeamSizeForMode(isTeamMode: true, sportId: _selectedSport);
        final maxTeamSize = _maxTeamSizeForMode(isTeamMode: true, sportId: _selectedSport);
        final defaultSize = _defaultTeamSizeForSport(_selectedSport);
        var nextSize = _teamSizePerSide;
        if (nextSize < minTeamSize) {
          nextSize = defaultSize < minTeamSize ? minTeamSize : defaultSize;
        }
        if (nextSize > maxTeamSize) {
          nextSize = maxTeamSize;
        }
        _teamSizePerSide = nextSize;
      }
      if (!_isTeamMode) {
        _teamNameController.clear();
      }
    });
  }

  List<int> _participantOptionsForCurrentSport() {
    final maxForSport = _maxParticipantsForSport(_selectedSport);
    var minRequired = _teamSizePerSide * 2;
    if (minRequired < 2) minRequired = 2;
    if (minRequired > maxForSport) {
      minRequired = maxForSport;
    }
    var count = (maxForSport - minRequired) + 1;
    if (count <= 0) count = 1;
    return List<int>.generate(count, (index) => minRequired + index);
  }

  List<_TeamVariantOption> _variantOptionsForCurrentSport() {
    final sport = _getSportById(_selectedSport);
    if (sport == null) return const [];
    if (_isFootballSport(sport)) return _footballVariants;
    if (_isBadmintonSport(sport)) return _badmintonVariants;
    if (_isTennisSport(sport)) return _tennisVariants;
    if (_isTableTennisSport(sport)) return _tableTennisVariants;
    if (_isBasketballSport(sport)) return _basketballVariants;
    if (_isVolleyballSport(sport)) return _volleyballVariants;
    return const [];
  }

  bool _matchesSportKeywords(Sport sport, List<String> keywords) {
    final code = sport.code.toLowerCase();
    final name = sport.name.toLowerCase();
    for (final keyword in keywords) {
      if (keyword.isEmpty) continue;
      if (code.contains(keyword) || name.contains(keyword)) {
        return true;
      }
    }
    return false;
  }

  bool _isFootballSport(Sport sport) {
    return _matchesSportKeywords(
      sport,
      ['football', 'soccer', 'bóng đá', 'bong da', 'futsal'],
    );
  }

  bool _isBadmintonSport(Sport sport) {
    return _matchesSportKeywords(
      sport,
      ['badminton', 'cầu lông', 'cau long'],
    );
  }

  bool _isTennisSport(Sport sport) {
    return _matchesSportKeywords(
      sport,
      ['tennis'],
    );
  }

  bool _isTableTennisSport(Sport sport) {
    return _matchesSportKeywords(
      sport,
      ['table tennis', 'pingpong', 'ping pong', 'bóng bàn', 'bong ban'],
    );
  }

  bool _isBasketballSport(Sport sport) {
    return _matchesSportKeywords(
      sport,
      ['basketball', 'bóng rổ', 'bong ro'],
    );
  }

  bool _isVolleyballSport(Sport sport) {
    return _matchesSportKeywords(
      sport,
      ['volleyball', 'bóng chuyền', 'bong chuyen'],
    );
  }

  bool _isPickleballSport(Sport sport) {
    return _matchesSportKeywords(
      sport,
      ['pickleball', 'pickle ball'],
    );
  }

  void _applyVariantOption(_TeamVariantOption variant) {
    var nextTeamSize = variant.teamSizePerSide;
    final maxTeamSize = _maxTeamSizeForSport(_selectedSport);
    if (nextTeamSize > maxTeamSize) {
      nextTeamSize = maxTeamSize;
    }
    if (nextTeamSize < 1) {
      nextTeamSize = 1;
    }

    final minParticipants = nextTeamSize * 2;
    final maxParticipants = _maxParticipantsForSport(_selectedSport);
    var nextParticipants = variant.totalParticipants ?? minParticipants;
    if (nextParticipants < minParticipants) {
      nextParticipants = minParticipants;
    }
    if (nextParticipants > maxParticipants) {
      nextParticipants = maxParticipants;
    }

    _teamSizePerSide = nextTeamSize;
    _participantLimit = nextParticipants;
    _selectedVariantId = variant.id;
  }

  Future<void> _loadCourtsForFacility(String? facilityId) async {
    if (!mounted) return;
    if (facilityId == null || facilityId.isEmpty) {
      setState(() {
        _courts = const [];
        _selectedCourt = null;
      });
      return;
    }

    setState(() {
      _loadingCourts = true;
    });

    try {
      final courts = await _api.getCourtsByFacility(
        facilityId,
        sportId: _selectedSport,
      );
      if (!mounted) return;
      setState(() {
        _courts = courts;
        if (_selectedCourt != null &&
            courts.any((court) => court.id == _selectedCourt)) {
          // keep current selection
        } else {
          _selectedCourt = courts.isNotEmpty ? courts.first.id : null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _courts = const [];
        _selectedCourt = null;
      });
      if (!mounted) return;
      await _showSnack(_friendlyError(e), isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _loadingCourts = false;
        });
      }
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sportsFuture = _api.getSports(includeCount: false);
      final facilitiesFuture = _api.getFacilities();
      final requestsFuture = _api.getMatchRequests(limit: 50);

      final sports = await sportsFuture;
      final facilities = await facilitiesFuture;
      final requests = await requestsFuture;
      final processedRequests = _autoCancelExpiredRequests(requests);
      if (!mounted) return;
      final previousSport = _selectedSport;
      final nextSport =
          (previousSport != null &&
              sports.any((sport) => sport.id == previousSport))
          ? previousSport
          : (sports.isNotEmpty ? sports.first.id : null);

      final previousFacility = _selectedFacility;
      final nextFacility =
          (previousFacility != null &&
              facilities.any((facility) => facility.id == previousFacility))
          ? previousFacility
          : (facilities.isNotEmpty ? facilities.first.id : null);

      final defaultLimit = _defaultLimitForSport(nextSport);
      var nextLimit = _participantLimit;
      if (previousSport != nextSport || nextLimit < 2 || nextLimit > 20) {
        nextLimit = defaultLimit;
      }
      final defaultTeamSize = _defaultTeamSizeForSport(nextSport);
      var nextTeamSize = _teamSizePerSide;
      if (previousSport != nextSport || nextTeamSize < 1 || nextTeamSize > 20) {
        nextTeamSize = defaultTeamSize;
      }
      final maxTeamSizeForSport = _maxTeamSizeForMode(
        isTeamMode: _matchMode == 'team',
        sportId: nextSport,
      );
      if (nextTeamSize > maxTeamSizeForSport) {
        nextTeamSize = maxTeamSizeForSport;
      }
      if (nextTeamSize < 1) {
        nextTeamSize = 1;
      }
      if (_matchMode == 'team') {
        final minTeamSize = _minTeamSizeForMode(
          isTeamMode: true,
          sportId: nextSport,
        );
        if (nextTeamSize < minTeamSize) {
          nextTeamSize = minTeamSize;
        }
      }
      if (nextLimit < nextTeamSize * 2) {
        nextLimit = nextTeamSize * 2;
      }
      final maxLimitForSport = _maxParticipantsForSport(nextSport);
      if (nextLimit > maxLimitForSport) {
        nextLimit = maxLimitForSport;
      }
      final nextFilterSport =
          (_filterSportId != null &&
                  sports.any((sport) => sport.id == _filterSportId))
              ? _filterSportId
              : null;
      setState(() {
        _sports = sports;
        _facilities = facilities;
        _selectedSport = nextSport;
        _selectedFacility = nextFacility;
        _participantLimit = nextLimit;
        _teamSizePerSide = nextTeamSize;
        _requests = processedRequests.requests;
        _loading = false;
        _filterSportId = nextFilterSport;
        _selectedVariantId = null;
        _updateAutoCancelledTracking(processedRequests.autoCancelledIds);
      });
      if (!mounted) return;
      await _loadCourtsForFacility(nextFacility);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = parseApiError(e);
        _loading = false;
      });
    }
  }

  Future<void> _refreshRequests() async {
    try {
      final requests = await _api.getMatchRequests(limit: 50);
      if (!mounted) return;
      final processed = _autoCancelExpiredRequests(requests);
      setState(() {
        _requests = processed.requests;
        _updateAutoCancelledTracking(processed.autoCancelledIds);
      });
    } catch (e) {
      if (!mounted) return;
      await _showSnack(_friendlyError(e), isError: true);
    }
  }

  Future<void> _joinRequest(
    MatchRequest request, {
    required String team,
  }) async {
    final prefix = '${request.id}::';
    if (_joining.any((value) => value.startsWith(prefix))) return;
    final joinKey = '$prefix$team';
    setState(() => _joining.add(joinKey));
    try {
      final updated = await _api.joinMatchRequest(request.id, team: team);
      if (!mounted) return;
      final nextRequests = _requests
          .map((item) => item.id == updated.id ? updated : item)
          .toList();
      setState(() {
        _joining.remove(joinKey);
        _requests = nextRequests;
        _updateAutoCancelledTracking(
          _autoCancelExpiredRequests(nextRequests).autoCancelledIds,
        );
      });
      if (!mounted) return;
      await _showSnack('Đã tham gia lời mời.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _joining.remove(joinKey));
      if (!mounted) return;
      await _showSnack(_friendlyError(e), isError: true);
    }
  }

  Future<String?> _promptGuestTeamName() async {
    final controller = TextEditingController();
    String? errorText;
    try {
      final result = await showDialog<String>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('Nhập tên đội của bạn'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      hintText: 'Ví dụ: Warriors Community',
                      errorText: errorText,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Huỷ'),
                ),
                FilledButton(
                  onPressed: () {
                    final value = controller.text.trim();
                    if (value.length < 3) {
                      setLocalState(() {
                        errorText = 'Tên đội cần tối thiểu 3 ký tự.';
                      });
                      return;
                    }
                    Navigator.of(context).pop(value);
                  },
                  child: const Text('Xác nhận'),
                ),
              ],
            );
          },
        ),
      );
      return result?.trim().isEmpty ?? true ? null : result?.trim();
    } finally {
      controller.dispose();
    }
  }

  Future<void> _joinTeamMatch(MatchRequest request) async {
    final joinKey = '${request.id}::guestTeam';
    if (_joining.contains(joinKey)) return;
    final teamName = await _promptGuestTeamName();
    if (!mounted || teamName == null) return;
    setState(() => _joining.add(joinKey));
    try {
      final updated = await _api.joinMatchRequest(
        request.id,
        mode: 'team',
        teamName: teamName,
      );
      if (!mounted) return;
      final nextRequests = _requests
          .map((item) => item.id == updated.id ? updated : item)
          .toList();
      setState(() {
        _joining.remove(joinKey);
        _requests = nextRequests;
        _updateAutoCancelledTracking(
          _autoCancelExpiredRequests(nextRequests).autoCancelledIds,
        );
      });
      if (!mounted) return;
      await _showSnack('Đã nhận lời mời cho đội của bạn.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _joining.remove(joinKey));
      if (!mounted) return;
      await _showSnack(_friendlyError(e), isError: true);
    }
  }

  Future<void> _cancelRequest(MatchRequest request) async {
    if (_cancelling.contains(request.id)) return;
    setState(() => _cancelling.add(request.id));
    try {
      final updated = await _api.cancelMatchRequest(request.id);
      if (!mounted) return;
      final nextRequests = _requests
          .map((item) => item.id == updated.id ? updated : item)
          .toList();
      setState(() {
        _cancelling.remove(request.id);
        _requests = nextRequests;
        _updateAutoCancelledTracking(
          _autoCancelExpiredRequests(nextRequests).autoCancelledIds,
        );
      });
      if (!mounted) return;
      await _showSnack('Đã hủy lời mời thi đấu.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _cancelling.remove(request.id));
      if (!mounted) return;
      await _showSnack(_friendlyError(e), isError: true);
    }
  }

  Future<void> _pickDesiredDate() async {
    final now = DateTime.now();
    final base = _desiredStart ?? _roundToNextHour(now);
    final firstDate = DateTime(now.year, now.month, now.day);
    final initialDate = DateTime(base.year, base.month, base.day);
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate.isBefore(firstDate) ? firstDate : initialDate,
      firstDate: firstDate,
      lastDate: firstDate.add(const Duration(days: 60)),
    );
    if (pickedDate == null || !mounted) return;

    setState(() {
      final startTime = TimeOfDay.fromDateTime(base);
      _desiredStart = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        startTime.hour,
        startTime.minute,
      );
    });
  }

  Future<void> _pickDesiredStart() async {
    final now = DateTime.now();
    final base = _desiredStart ?? _roundToNextHour(now);
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (pickedTime == null) return;
    if (!mounted) return;
    final result = DateTime(
      base.year,
      base.month,
      base.day,
      pickedTime.hour,
      pickedTime.minute,
    );
    setState(() => _desiredStart = result);
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) return '—';
    final local = value.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    final y = local.year.toString().padLeft(4, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$d/$m/$y $hh:$mm';
  }

  String _formatDateOnly(DateTime? value) {
    if (value == null) return 'Chưa chọn';
    final local = value.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    final y = local.year.toString();
    return '$d/$m/$y';
  }

  String _formatTimeOnly(DateTime? value) {
    if (value == null) return '--:--';
    final local = value.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  void _selectDuration(int hours) {
    var normalized = hours;
    if (normalized < 1) normalized = 1;
    if (normalized > 3) normalized = 3;
    if (normalized == _desiredDurationHours) return;
    setState(() => _desiredDurationHours = normalized);
  }

  String _buildDesiredRangeSummary() {
    final start = _desiredStart;
    final end = _computeEndForStart(start);
    if (start == null || end == null) {
      return 'Chưa chọn thời gian cụ thể';
    }
    final localStart = start.toLocal();
    final localEnd = end.toLocal();
    final durationLabel = '$_desiredDurationHours giờ';
    return '${_formatDayMonth(localStart)} • ${_formatTimeOnly(localStart)} - ${_formatTimeOnly(localEnd)} ($durationLabel)';
  }

  String _formatDayMonth(DateTime value) {
    const weekdayNames = <int, String>{
      DateTime.monday: 'Thứ hai',
      DateTime.tuesday: 'Thứ ba',
      DateTime.wednesday: 'Thứ tư',
      DateTime.thursday: 'Thứ năm',
      DateTime.friday: 'Thứ sáu',
      DateTime.saturday: 'Thứ bảy',
      DateTime.sunday: 'Chủ nhật',
    };
    final weekday = weekdayNames[value.weekday] ?? 'Ngày';
    final d = value.day.toString().padLeft(2, '0');
    final m = value.month.toString().padLeft(2, '0');
    return '$weekday, $d/$m';
  }

  String _formatDurationLabel(Duration duration) {
    if (duration.inMinutes <= 0) return '';
    final hours = duration.inMinutes ~/ 60;
    final minutes = duration.inMinutes % 60;
    if (minutes == 0) {
      return '$hours giờ';
    }
    if (hours == 0) {
      return '$minutes phút';
    }
    return '$hours giờ $minutes phút';
  }

  String _formatRangeForCard(MatchRequest request) {
    final start = request.desiredStart;
    final end = request.desiredEnd;
    if (start == null) return 'Chưa rõ thời gian thi đấu';
    final localStart = start.toLocal();
    final buffer = StringBuffer()
      ..write('${_formatDayMonth(localStart)} • ${_formatTimeOnly(localStart)}');
    if (end != null && end.isAfter(start)) {
      final localEnd = end.toLocal();
      buffer
        ..write(' - ${_formatTimeOnly(localEnd)}')
        ..write(' (${_formatDurationLabel(localEnd.difference(localStart))})');
    }
    return buffer.toString();
  }

  Future<void> _submitRequest() async {
    if (_submitting) return;
    final sportId = _selectedSport;
    if (sportId == null) {
      await _showSnack('Vui lòng chọn môn thể thao.', isError: true);
      return;
    }
    final facilityId = _selectedFacility;
    if (facilityId == null || facilityId.isEmpty) {
      await _showSnack('Vui lòng chọn cơ sở.', isError: true);
      return;
    }
    final courtId = _selectedCourt;
    if (courtId == null || courtId.isEmpty) {
      await _showSnack('Vui lòng chọn sân.', isError: true);
      return;
    }
    final start = _desiredStart;
    final end = _computeEndForStart(start);
    if (start == null || end == null || !start.isBefore(end)) {
      await _showSnack('Vui lòng chọn thời gian hợp lệ.', isError: true);
      return;
    }

    final bool isTeamMode = _isTeamMode;
    final teamSize = _teamSizePerSide;
    final minTeamSize = _minTeamSizeForMode(
      isTeamMode: isTeamMode,
      sportId: sportId,
    );
    final maxTeamSize = _maxTeamSizeForMode(
      isTeamMode: isTeamMode,
      sportId: sportId,
    );
    if (teamSize < minTeamSize || teamSize > maxTeamSize) {
      await _showSnack('Vui lòng chọn số người phù hợp cho mỗi đội.', isError: true);
      return;
    }

    var participantLimit = _participantLimit;
    if (isTeamMode) {
      participantLimit = teamSize * 2;
    } else {
      final minimumParticipants = teamSize * 2;
      if (participantLimit < minimumParticipants) {
        participantLimit = minimumParticipants;
      }
      if (participantLimit < 2) participantLimit = 2;
      final maxParticipants = _maxParticipantsForSport(sportId);
      if (participantLimit > maxParticipants) {
        participantLimit = maxParticipants;
      }
    }

    final hostTeamName = _teamNameController.text.trim();

    setState(() => _submitting = true);
    try {
      final request = await _api.createMatchRequest(
        sportId: sportId,
        desiredStart: start,
        desiredEnd: end,
        skillMin: _skillRange.start.round(),
        skillMax: _skillRange.end.round(),
        facilityId: facilityId,
        courtId: courtId,
        participantLimit: isTeamMode ? null : participantLimit,
        teamSize: teamSize,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        mode: isTeamMode ? 'team' : 'solo',
        teamName: isTeamMode && hostTeamName.isNotEmpty ? hostTeamName : null,
      );
      if (!mounted) return;
      final nextRequests = [request, ..._requests];
      setState(() {
        _submitting = false;
        _notesController.clear();
        if (isTeamMode) {
          _teamNameController.clear();
        }
        _requests = nextRequests;
        _updateAutoCancelledTracking(
          _autoCancelExpiredRequests(nextRequests).autoCancelledIds,
        );
      });
      if (!mounted) return;
      await _showSnack('Đã tạo lời mời thi đấu.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      if (!mounted) return;
      await _showSnack(_friendlyError(e), isError: true);
    }
  }

  Widget _buildTeamSnapshot({
    required String label,
    required int count,
    int? limit,
    required bool selected,
  }) {
    final theme = Theme.of(context);
    final bgColor = selected
      ? const Color(0xFFE6F3FF)
      : const Color(0xFFF5F5F5);
    final borderWidth = selected ? 3 : 2;
    final capacityText = limit != null ? '$count/$limit' : '$count';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black, width: borderWidth.toDouble()),
        boxShadow: selected
            ? const [
                BoxShadow(
                  color: Colors.black,
                  offset: Offset(3, 3),
                  blurRadius: 0,
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.groups_outlined, size: 18, color: Colors.black87),
              const SizedBox(width: 6),
              Text(
                capacityText,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTeamModeSummary(
    MatchRequest request, {
    String? perTeamBadge,
  }) {
    final hostName = request.hostTeam?.teamName?.trim();
    final guestInfo = request.guestTeam;
    final hasGuestTeam = _hasTeamDetails(guestInfo);
    final guestName = guestInfo?.teamName?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTeamModeTile(
          title: 'Đội chủ nhà',
          subtitle: hostName?.isNotEmpty == true
              ? hostName!
              : 'Chủ sân chưa đặt tên đội',
          icon: Icons.flag_circle,
          highlight: true,
          badge: perTeamBadge,
        ),
        const SizedBox(height: 10),
        _buildTeamModeTile(
          title: 'Đội khách',
          subtitle: hasGuestTeam
              ? (guestName?.isNotEmpty == true
                  ? guestName!
                  : 'Đội khách đã xác nhận')
              : 'Chưa có đội khách nhận lời',
          icon: hasGuestTeam
              ? Icons.military_tech
              : Icons.hourglass_bottom,
          highlight: hasGuestTeam,
          pending: !hasGuestTeam,
          badge: perTeamBadge,
        ),
      ],
    );
  }

  Widget _buildTeamModeTile({
    required String title,
    required String subtitle,
    required IconData icon,
    String? badge,
    bool highlight = false,
    bool pending = false,
  }) {
    final theme = Theme.of(context);
    final bgColor = highlight
        ? const Color(0xFFE8F5E9)
        : pending
            ? const Color(0xFFFFF8E1)
            : Colors.white;
    final borderColor = pending
        ? const Color(0xFFFFA726)
        : (highlight ? const Color(0xFF4CAF50) : Colors.black);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Colors.black,
            offset: Offset(3, 3),
            blurRadius: 0,
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: 2),
            ),
            child: Icon(icon, color: borderColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (badge != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: highlight
                    ? const Color(0xFFE1F5FE)
                    : const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor, width: 2),
              ),
              child: Text(
                badge,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTeamActionButton({
    required MatchRequest request,
    required String team,
    required String label,
    required bool enabled,
    required bool loading,
    required IconData icon,
    bool primary = true,
  }) {
    final theme = Theme.of(context);
    final buttonColor = primary
        ? (enabled ? theme.colorScheme.primary : Colors.grey)
        : (enabled ? Colors.white : Colors.grey[300]!);
    final textColor = primary ? Colors.white : Colors.black;

    return NeuButton(
      buttonHeight: 40,
      borderRadius: BorderRadius.circular(12),
      buttonColor: buttonColor,
      onPressed: enabled ? () => _joinRequest(request, team: team) : () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              NeoLoadingDot(
                size: 18,
                fillColor: textColor,
                borderColor: Colors.black,
                shadowColor: Colors.black.withValues(alpha: 0.55),
              )
            else
              Icon(icon, size: 18, color: textColor),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                loading ? 'Đang xử lý...' : label,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _friendlyError(Object error) {
    final message = error.toString().trim();
    const prefix = 'Exception: ';
    if (message.startsWith(prefix)) {
      return message.substring(prefix.length).trim();
    }
    return message.isEmpty ? 'Có lỗi xảy ra. Vui lòng thử lại.' : message;
  }

  Future<void> _showSnack(String message, {bool isError = false}) async {
    if (!mounted) return;
    if (isError) {
      final theme = Theme.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: theme.colorScheme.error,
        ),
      );
      return;
    }

    await showSuccessDialog(
      context,
      message: message,
    );
  }

  void _redirectToLogin(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  void _redirectToVerifyEmail(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const VerifyEmailScreen()),
    );
  }

  List<MatchRequest> get _filteredRequests {
    return _requests.where((request) {
      if (_filterSportId != null && request.sportId != _filterSportId) {
        return false;
      }
      if (_filterOnlyOpen) {
        final statusLower = request.status.toLowerCase();
        final isOpen =
            statusLower == 'open' && !_autoCancelledRequestIds.contains(request.id);
        final hasSpace = request.participantLimit == null ||
            request.participantCount < request.participantLimit!;
        if (!(isOpen && hasSpace)) return false;
      }
      if (_filterOnlyMine && !request.isCreator) {
        return false;
      }
      return true;
    }).toList(growable: false);
  }

  Future<void> _showSportSelectionSheet() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        decoration: const BoxDecoration(
          color: Color(0xFFFFFAF0),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(color: Colors.black, width: 3),
            left: BorderSide(color: Colors.black, width: 3),
            right: BorderSide(color: Colors.black, width: 3),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black,
              offset: Offset(0, -6),
              blurRadius: 0,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.black, width: 2),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFE5CC),
                      border: Border.all(color: Colors.black, width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.sports_outlined, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'CHỌN MÔN THỂ THAO',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.all(16),
                itemCount: _sports.length,
                itemBuilder: (context, index) {
                  final sport = _sports[index];
                  final isSelected = sport.id == _selectedSport;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      onTap: () => Navigator.pop(context, sport.id),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF4CAF50)
                              : const Color(0xFFFFFFFF),
                          border: Border.all(
                            color: Colors.black,
                            width: isSelected ? 3 : 2,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black,
                              offset: const Offset(4, 4),
                              blurRadius: 0,
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                sport.name,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                  color: isSelected ? Colors.white : Colors.black,
                                ),
                              ),
                            ),
                            if (isSelected)
                              const Icon(
                                Icons.check_circle,
                                color: Colors.white,
                                size: 24,
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    if (selected != null && mounted) {
      setState(() {
        _selectedSport = selected;
        _selectedVariantId = null;
        final teamSize = _defaultTeamSizeForSport(selected);
        _teamSizePerSide = teamSize;
        var proposedLimit = _defaultLimitForSport(selected);
        final minRequired = teamSize * 2;
        final maxForSport = _maxParticipantsForSport(selected);
        if (proposedLimit < minRequired) {
          proposedLimit = minRequired;
        }
        if (proposedLimit > maxForSport) {
          proposedLimit = maxForSport;
        }
        _participantLimit = proposedLimit;
      });
      _loadCourtsForFacility(_selectedFacility);
    }
  }

  Future<void> _showFacilitySelectionSheet() async {
    if (_facilities.isEmpty) return;
    
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        decoration: const BoxDecoration(
          color: Color(0xFFE6F3FF),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(color: Colors.black, width: 3),
            left: BorderSide(color: Colors.black, width: 3),
            right: BorderSide(color: Colors.black, width: 3),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black,
              offset: Offset(0, -6),
              blurRadius: 0,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.black, width: 2),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF80CBC4),
                      border: Border.all(color: Colors.black, width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.location_on_outlined, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'CHỌN CƠ SỞ',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.all(16),
                itemCount: _facilities.length,
                itemBuilder: (context, index) {
                  final facility = _facilities[index];
                  final isSelected = facility.id == _selectedFacility;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      onTap: () => Navigator.pop(context, facility.id),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF4CAF50)
                              : const Color(0xFFFFFFFF),
                          border: Border.all(
                            color: Colors.black,
                            width: isSelected ? 3 : 2,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black,
                              offset: const Offset(4, 4),
                              blurRadius: 0,
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                facility.name,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                  color: isSelected ? Colors.white : Colors.black,
                                ),
                              ),
                            ),
                            if (isSelected)
                              const Icon(
                                Icons.check_circle,
                                color: Colors.white,
                                size: 24,
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    if (selected != null && mounted) {
      setState(() => _selectedFacility = selected);
      _loadCourtsForFacility(selected);
    }
  }

  Future<void> _showCourtSelectionSheet() async {
    if (_courts.isEmpty) return;
    
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        decoration: const BoxDecoration(
          color: Color(0xFFE8F5E9),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(color: Colors.black, width: 3),
            left: BorderSide(color: Colors.black, width: 3),
            right: BorderSide(color: Colors.black, width: 3),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black,
              offset: Offset(0, -6),
              blurRadius: 0,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.black, width: 2),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4CAF50),
                      border: Border.all(color: Colors.black, width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.sports_tennis_outlined, size: 24, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Row(
                      children: [
                        const Text(
                          'CHỌN SÂN',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                        if (_loadingCourts) ...[
                          const SizedBox(width: 12),
                          const NeoLoadingDot(size: 20, fillColor: Colors.white),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.all(16),
                itemCount: _courts.length,
                itemBuilder: (context, index) {
                  final court = _courts[index];
                  final isSelected = court.id == _selectedCourt;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      onTap: () => Navigator.pop(context, court.id),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF4CAF50)
                              : const Color(0xFFFFFFFF),
                          border: Border.all(
                            color: Colors.black,
                            width: isSelected ? 3 : 2,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black,
                              offset: const Offset(4, 4),
                              blurRadius: 0,
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                court.name,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                  color: isSelected ? Colors.white : Colors.black,
                                ),
                              ),
                            ),
                            if (isSelected)
                              const Icon(
                                Icons.check_circle,
                                color: Colors.white,
                                size: 24,
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    if (selected != null && mounted) {
      setState(() => _selectedCourt = selected);
    }
  }

  Future<void> _showParticipantLimitSheet() async {
    final participantOptions = _participantOptionsForCurrentSport();
    
    final selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        decoration: const BoxDecoration(
          color: Color(0xFFFFFAF0),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(color: Colors.black, width: 3),
            left: BorderSide(color: Colors.black, width: 3),
            right: BorderSide(color: Colors.black, width: 3),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black,
              offset: Offset(0, -6),
              blurRadius: 0,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.black, width: 2),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFE5CC),
                      border: Border.all(color: Colors.black, width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.groups_outlined, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'GIỚI HẠN NGƯỜI THAM GIA',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.all(16),
                itemCount: participantOptions.length,
                itemBuilder: (context, index) {
                  final value = participantOptions[index];
                  final isSelected = value == _participantLimit;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      onTap: () => Navigator.pop(context, value),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF4CAF50)
                              : const Color(0xFFFFFFFF),
                          border: Border.all(
                            color: Colors.black,
                            width: isSelected ? 3 : 2,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black,
                              offset: const Offset(4, 4),
                              blurRadius: 0,
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '$value người',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                  color: isSelected ? Colors.white : Colors.black,
                                ),
                              ),
                            ),
                            if (isSelected)
                              const Icon(
                                Icons.check_circle,
                                color: Colors.white,
                                size: 24,
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    if (selected != null && mounted) {
      setState(() {
        _participantLimit = selected;
        _selectedVariantId = null;
        if (_participantLimit < _teamSizePerSide * 2) {
          _participantLimit = _teamSizePerSide * 2;
        }
        final maxForSport = _maxParticipantsForSport(_selectedSport);
        if (_participantLimit > maxForSport) {
          _participantLimit = maxForSport;
        }
      });
    }
  }

  Future<void> _showTeamSizeSheet() async {
    final teamSizeOptions = _teamSizeOptionsForCurrentSport();
    
    final selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        decoration: const BoxDecoration(
          color: Color(0xFFFFE5E5),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(color: Colors.black, width: 3),
            left: BorderSide(color: Colors.black, width: 3),
            right: BorderSide(color: Colors.black, width: 3),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black,
              offset: Offset(0, -6),
              blurRadius: 0,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.black, width: 2),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B6B),
                      border: Border.all(color: Colors.black, width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.group_add_outlined, size: 24, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'SỐ NGƯỜI MỖI BÊN',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.all(16),
                itemCount: teamSizeOptions.length,
                itemBuilder: (context, index) {
                  final value = teamSizeOptions[index];
                  final isSelected = value == _teamSizePerSide;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      onTap: () => Navigator.pop(context, value),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF4CAF50)
                              : const Color(0xFFFFFFFF),
                          border: Border.all(
                            color: Colors.black,
                            width: isSelected ? 3 : 2,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black,
                              offset: const Offset(4, 4),
                              blurRadius: 0,
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '$value người mỗi đội',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                  color: isSelected ? Colors.white : Colors.black,
                                ),
                              ),
                            ),
                            if (isSelected)
                              const Icon(
                                Icons.check_circle,
                                color: Colors.white,
                                size: 24,
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    if (selected != null && mounted) {
      setState(() {
        var nextSize = selected;
        final minTeamSize = _minTeamSizeForMode(
          isTeamMode: _isTeamMode,
          sportId: _selectedSport,
        );
        if (nextSize < minTeamSize) {
          nextSize = minTeamSize;
        }
        final maxTeamSize = _maxTeamSizeForMode(
          isTeamMode: _isTeamMode,
          sportId: _selectedSport,
        );
        if (nextSize > maxTeamSize) {
          nextSize = maxTeamSize;
        }
        _teamSizePerSide = nextSize;
        _selectedVariantId = null;
        if (_participantLimit < nextSize * 2) {
          _participantLimit = nextSize * 2;
        }
        final maxForSport = _maxParticipantsForSport(_selectedSport);
        if (_participantLimit > maxForSport) {
          _participantLimit = maxForSport;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaPadding = MediaQuery.of(context).padding;
    final headerTopPadding = mediaPadding.top + 16;
    final listBottomPadding = mediaPadding.bottom + 24;
    final visibleRequests = _filteredRequests;
    final filteredByFilters = visibleRequests.isEmpty && _requests.isNotEmpty;

    Widget body;
    if (_loading) {
      body = const Center(
        child: NeoLoadingCard(
          label: 'Đang tải lời mời...',
          width: 260,
        ),
      );
    } else if (_error != null) {
      body = Center(
        child: ErrorStateWidget(
          statusCode: _error!.statusCode,
          message: _error!.message,
          onRetry: () => _load(),
          onLogin: () => _redirectToLogin(context),
          onVerifyEmail: () => _redirectToVerifyEmail(context),
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _refreshRequests,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(16, 16, 16, listBottomPadding),
          children: [
            _buildCreateCard(theme),
            const SizedBox(height: 16),
            Text('Lời mời gần bạn', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Tham gia trận đấu phù hợp với bạn.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: (theme.textTheme.bodySmall?.color ??
                        theme.colorScheme.onSurfaceVariant)
                    .withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 12),
            _buildFilterBar(theme),
            const SizedBox(height: 12),
            if (visibleRequests.isEmpty)
              _buildEmptyState(
                theme,
                filteredByFilters: filteredByFilters,
              )
            else
              ...visibleRequests.map(_buildRequestCard),
          ],
        ),
      );
    }

    if (widget.embedded) {
      return SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16, headerTopPadding, 16, 8),
              child: Text(
                'Tìm đối thủ thi đấu',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Tìm đối thủ thi đấu')),
      body: body,
    );
  }

  Widget _buildCreateCard(ThemeData theme) {
    final isLoggedIn = AuthService.instance.isLoggedIn;
    final variantOptions =
        _isTeamMode ? const <_TeamVariantOption>[] : _variantOptionsForCurrentSport();
    final disableParticipantLimit = _isTeamMode;
    return NeuContainer(
      color: const Color(0xFFFFFAF0),
      borderColor: Colors.black,
      borderWidth: 3,
      borderRadius: BorderRadius.circular(20),
      shadowColor: Colors.black,
      offset: const Offset(6, 6),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE6F3FF),
                    border: Border.all(color: Colors.black, width: 3),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black,
                        offset: Offset(4, 4),
                        blurRadius: 0,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.handshake_outlined,
                    color: Colors.black,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tạo lời mời thi đấu',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Chọn môn, sân và thời gian để tìm đối thủ phù hợp',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'MÔN & ĐỊA ĐIỂM',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _showSportSelectionSheet,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE5CC),
                  border: Border.all(color: Colors.black, width: 2),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black,
                      offset: Offset(4, 4),
                      blurRadius: 0,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.sports_outlined, color: Colors.black54),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Môn thể thao',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black.withValues(alpha: 0.6),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _selectedSport != null
                                ? _sports.firstWhere((s) => s.id == _selectedSport).name
                                : 'Chọn môn thể thao',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: _selectedSport != null ? Colors.black : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down, color: Colors.black),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _facilities.isEmpty ? null : _showFacilitySelectionSheet,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE6F3FF),
                  border: Border.all(color: Colors.black, width: 2),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black,
                      offset: Offset(4, 4),
                      blurRadius: 0,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on_outlined, color: Colors.black54),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Cơ sở',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black.withValues(alpha: 0.6),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _selectedFacility != null
                                ? _facilities.firstWhere((f) => f.id == _selectedFacility).name
                                : 'Chọn cơ sở',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: _selectedFacility != null ? Colors.black : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down, color: Colors.black),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _courts.isEmpty ? null : _showCourtSelectionSheet,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  border: Border.all(color: Colors.black, width: 2),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black,
                      offset: Offset(4, 4),
                      blurRadius: 0,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.sports_tennis_outlined, color: Colors.black54),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sân',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black.withValues(alpha: 0.6),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _selectedCourt != null
                                ? _courts.firstWhere((c) => c.id == _selectedCourt).name
                                : 'Chọn sân',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: _selectedCourt != null ? Colors.black : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_loadingCourts)
                      const Padding(
                        padding: EdgeInsets.all(8),
                        child: NeoLoadingDot(size: 20, fillColor: Colors.white),
                      )
                    else
                      const Icon(Icons.arrow_drop_down, color: Colors.black),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'THỜI GIAN MONG MUỐN',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            _buildDesiredTimeButton(),
            const SizedBox(height: 20),
            Text(
              'KIỂU GHÉP TRẬN',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            _buildMatchModeSelector(),
            const SizedBox(height: 16),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeInBack,
              child: _isTeamMode
                  ? _buildTeamModeExtras(theme)
                  : const SizedBox.shrink(),
            ),
            if (_isTeamMode) const SizedBox(height: 12),
            const SizedBox(height: 20),
            Text(
              'TRÌNH ĐỘ & SỐ NGƯỜI',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            RangeSlider(
              values: _skillRange,
              min: 0,
              max: 100,
              divisions: 20,
              labels: RangeLabels(
                _skillRange.start.round().toString(),
                _skillRange.end.round().toString(),
              ),
              onChanged: (values) => setState(() => _skillRange = values),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Trình độ: ${_skillRange.start.round()} - ${_skillRange.end.round()}',
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  _isTeamMode
                      ? 'Đội vs đội • $_teamSizePerSide người/đội'
                      : 'Số người: $_participantLimit tổng, $_teamSizePerSide mỗi bên',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            if (variantOptions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Chọn nhanh loại sân', style: theme.textTheme.bodySmall),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: variantOptions
                    .map(
                      (variant) => ChoiceChip(
                        label: Text(variant.label),
                        selected: _selectedVariantId == variant.id,
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              _applyVariantOption(variant);
                            } else {
                              _selectedVariantId = null;
                            }
                          });
                        },
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 12),
            InkWell(
              onTap: disableParticipantLimit ? null : _showParticipantLimitSheet,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: disableParticipantLimit
                      ? const Color(0xFFE0E0E0)
                      : const Color(0xFFFFFAF0),
                  border: Border.all(color: Colors.black, width: 2),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black,
                      offset: Offset(4, 4),
                      blurRadius: 0,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.groups_outlined, color: Colors.black54),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            disableParticipantLimit
                                ? 'Giới hạn người tham gia (khóa)'
                                : 'Giới hạn người tham gia',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black.withValues(alpha: 0.6),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            disableParticipantLimit
                                ? '${_teamSizePerSide * 2} người (cố định theo cỡ đội)'
                                : '$_participantLimit người',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      disableParticipantLimit
                          ? Icons.lock_outline
                          : Icons.arrow_drop_down,
                      color: Colors.black,
                    ),
                  ],
                ),
              ),
            ),
            if (_isTeamMode)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text(
                  'Tổng số người được tự tính theo 2 đội, bạn không cần điều chỉnh mục này.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _showTeamSizeSheet,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE5E5),
                  border: Border.all(color: Colors.black, width: 2),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black,
                      offset: Offset(4, 4),
                      blurRadius: 0,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.group_add_outlined, color: Colors.black54),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Số người mỗi bên',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black.withValues(alpha: 0.6),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$_teamSizePerSide người mỗi đội',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down, color: Colors.black),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tổng tối thiểu ${_teamSizePerSide * 2} người cho hai đội.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Text('Ghi chú thêm (tùy chọn)', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            TextFormField(
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                alignLabelWithHint: true,
                hintText: 'Ví dụ: Ưu tiên người chơi vui vẻ, trình độ trung bình...',
                prefixIcon: Icon(Icons.sticky_note_2_outlined),
              ),
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: NeuButton(
                buttonHeight: 48,
                buttonWidth: 200,
                borderRadius: BorderRadius.circular(12),
                buttonColor: (!isLoggedIn || _submitting) 
                    ? Colors.grey 
                    : theme.colorScheme.primary,
                onPressed: (!isLoggedIn || _submitting) ? () {} : _submitRequest,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_submitting)
                      const NeoLoadingDot(
                        size: 18,
                        fillColor: Colors.white,
                      )
                    else
                      const Icon(Icons.send_outlined, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      !isLoggedIn
                          ? 'Đăng nhập để tạo'
                          : _submitting
                              ? 'Đang gửi...'
                              : 'Tạo lời mời',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesiredTimeButton() {
    final theme = Theme.of(context);
    final start = _desiredStart;
    final dateText = _formatDateOnly(start);
    final startText = start != null ? _formatTimeOnly(start) : 'Chưa chọn';
    final summary = _buildDesiredRangeSummary();

    Widget buildPickerCard({
      required String title,
      required String value,
      required IconData icon,
      required VoidCallback onTap,
    }) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black, width: 3),
            boxShadow: const [
              BoxShadow(
                color: Colors.black,
                offset: Offset(4, 4),
                blurRadius: 0,
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  border: Border.all(color: Colors.black, width: 2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Colors.black87, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.bodySmall),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.black54),
            ],
          ),
        ),
      );
    }

    Widget buildDurationChip(int hours) {
      final selected = _desiredDurationHours == hours;
      final label = '$hours giờ';
      return Expanded(
        child: GestureDetector(
          onTap: () => _selectDuration(hours),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFF1E88E5) : const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.black, width: 3),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black,
                  offset: Offset(3, 3),
                  blurRadius: 0,
                ),
              ],
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : Colors.black,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.black, width: 3),
            boxShadow: const [
              BoxShadow(
                color: Colors.black,
                offset: Offset(4, 4),
                blurRadius: 0,
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black, width: 2),
                ),
                child: const Icon(Icons.schedule_outlined, color: Colors.black87),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Khung giờ dự kiến',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      summary,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        buildPickerCard(
          title: 'Ngày thi đấu',
          value: dateText,
          icon: Icons.calendar_month_outlined,
          onTap: _pickDesiredDate,
        ),
        const SizedBox(height: 12),
        buildPickerCard(
          title: 'Giờ bắt đầu',
          value: startText,
          icon: Icons.schedule,
          onTap: _pickDesiredStart,
        ),
        const SizedBox(height: 12),
        Text('Thời lượng trận đấu', style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        Row(
          children: [
            buildDurationChip(1),
            const SizedBox(width: 10),
            buildDurationChip(2),
            const SizedBox(width: 10),
            buildDurationChip(3),
          ],
        ),
      ],
    );
  }

  Widget _buildFilterBar(ThemeData theme) {
    final chips = <Widget>[];
    final seenSportIds = <String>{};
    if (_sports.isNotEmpty) {
      for (final sport in _sports) {
        seenSportIds.add(sport.id);
        chips.add(
          ChoiceChip(
            label: Text(sport.name),
            selected: _filterSportId == sport.id,
            onSelected: (selected) => setState(
              () => _filterSportId = selected ? sport.id : null,
            ),
          ),
        );
      }
    } else {
      for (final request in _requests) {
        if (seenSportIds.add(request.sportId)) {
          chips.add(
            ChoiceChip(
              label: Text(request.sportName ?? 'Môn khác'),
              selected: _filterSportId == request.sportId,
              onSelected: (selected) => setState(
                () => _filterSportId = selected ? request.sportId : null,
              ),
            ),
          );
        }
      }
    }
    return NeuContainer(
      color: const Color(0xFFFFFFFF),
      borderColor: Colors.black,
      borderWidth: 3,
      borderRadius: BorderRadius.circular(18),
      shadowColor: Colors.black,
      offset: const Offset(5, 5),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'BỘ LỌC NHANH',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _filterSportId == null && !_filterOnlyMine && _filterOnlyOpen
                  ? null
                  : () => setState(() {
                        _filterSportId = null;
                        _filterOnlyOpen = true;
                        _filterOnlyMine = false;
                      }),
              icon: const Icon(Icons.filter_alt_off_outlined),
              label: const Text('Đặt lại'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('Tất cả môn'),
                selected: _filterSportId == null,
                onSelected: (selected) => setState(
                  () => _filterSportId = null,
                ),
              ),
              const SizedBox(width: 8),
              ...chips.map((chip) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: chip,
              )),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilterChip(
              avatar: Icon(
                Icons.event_available,
                size: 18,
                color: _filterOnlyOpen
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.primary,
              ),
              label: const Text('Còn chỗ trống'),
              selected: _filterOnlyOpen,
              onSelected: (value) => setState(() => _filterOnlyOpen = value),
            ),
            FilterChip(
              avatar: Icon(
                Icons.person_outline,
                size: 18,
                color: _filterOnlyMine
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.primary,
              ),
              label: const Text('Lời mời của tôi'),
              selected: _filterOnlyMine,
              onSelected: AuthService.instance.isLoggedIn
                  ? (value) => setState(() => _filterOnlyMine = value)
                  : null,
            ),
          ],
        ),
      ],
        ),
      ),
    );
  }

  Widget _buildMatchModeSelector() {
    final theme = Theme.of(context);

    Widget buildOption({
      required String value,
      required String title,
      required String description,
      required IconData icon,
    }) {
      final selected = _matchMode == value;
      final bgColor = selected ? const Color(0xFF141E30) : Colors.white;
      final textColor = selected ? Colors.white : Colors.black87;
      final accent = selected ? const Color(0xFFFFD54F) : Colors.black;

      return InkWell(
        onTap: () => _setMatchMode(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.black, width: 3),
            boxShadow: const [
              BoxShadow(
                color: Colors.black,
                offset: Offset(4, 4),
                blurRadius: 0,
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.15)
                      : Colors.black.withValues(alpha: 0.05),
                  border: Border.all(color: accent, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      softWrap: true,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: textColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        softWrap: true,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: textColor.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (selected)
                Icon(
                  Icons.check_circle,
                  color: accent,
                  size: 24,
                ),
            ],
          ),
        ),
      );
    }

    Widget buildSoloOption() => buildOption(
          value: 'solo',
          title: 'Ghép người lẻ',
          description: 'Tự động xếp hai đội từ người lẻ.',
          icon: Icons.person_add_alt,
        );

    Widget buildTeamOption() => buildOption(
          value: 'team',
          title: 'Đội vs đội',
          description: 'Tạo lời mời cho cả đội.',
          icon: Icons.sports_martial_arts,
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 360;
        if (isCompact) {
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: constraints.maxWidth,
                child: buildSoloOption(),
              ),
              SizedBox(
                width: constraints.maxWidth,
                child: buildTeamOption(),
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: buildSoloOption()),
            const SizedBox(width: 12),
            Expanded(child: buildTeamOption()),
          ],
        );
      },
    );
  }

  Widget _buildTeamModeExtras(ThemeData theme) {
    final quickSizes = _teamModeSizeOptions();

    Widget buildSizeChip(int size) {
      final selected = _teamSizePerSide == size;
      return ChoiceChip(
        label: Text('$size người/đội'),
        selected: selected,
        onSelected: (_) {
          setState(() {
            _teamSizePerSide = size;
            _participantLimit = size * 2;
            _selectedVariantId = null;
          });
        },
      );
    }

    return Container(
      key: const ValueKey('team-mode-extras'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE6F4FF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black, width: 3),
        boxShadow: const [
          BoxShadow(
            color: Colors.black,
            offset: Offset(4, 4),
            blurRadius: 0,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Thông tin đội của bạn',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _teamNameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Tên đội chủ nhà',
              hintText: 'Ví dụ: Khu Liên Hợp All Stars',
              prefixIcon: Icon(Icons.emoji_events_outlined),
            ),
          ),
          const SizedBox(height: 12),
          if (quickSizes.isNotEmpty) ...[
            Text(
              'Chọn nhanh cỡ đội phổ biến',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: quickSizes.map(buildSizeChip).toList(),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              const Icon(Icons.info_outline, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Tên đội sẽ hiển thị cho đối thủ và được dùng khi xác nhận trận đấu.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, {required bool filteredByFilters}) {
    final icon = filteredByFilters
        ? Icons.filter_alt_off_outlined
        : Icons.sports_kabaddi_outlined;
    final headline = filteredByFilters
        ? 'Không có lời mời phù hợp với bộ lọc hiện tại.'
        : 'Chưa có lời mời nào đang mở.';
    final subtitle = filteredByFilters
        ? 'Hãy thử điều chỉnh bộ lọc ở trên để xem thêm lựa chọn.'
        : 'Hãy trở thành người đầu tiên tạo lời mời thi đấu hôm nay!';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text(
            headline,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
          ),
          if (filteredByFilters) ...[
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () => setState(() {
                _filterSportId = null;
                _filterOnlyOpen = true;
                _filterOnlyMine = false;
              }),
              icon: const Icon(Icons.refresh),
              label: const Text('Xoá bộ lọc'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRequestCard(MatchRequest request) {
    final theme = Theme.of(context);
    final isOwn = request.isCreator;
    final statusLower = request.status.toLowerCase();
    final autoCancelled = _autoCancelledRequestIds.contains(request.id);
    final isCancelled = autoCancelled || statusLower == 'cancelled';
    final isOpen = statusLower == 'open' && !autoCancelled;
    final sportLabel = (request.sportName?.trim().isNotEmpty ?? false)
      ? request.sportName!.trim()
      : 'Môn thể thao (chưa xác định)';
    final facilityLabel = (request.facilityName?.trim().isNotEmpty ?? false)
      ? request.facilityName!.trim()
      : '(chưa rõ)';
    final courtLabel = (request.courtName?.trim().isNotEmpty ?? false)
      ? request.courtName!.trim()
      : '(chưa rõ)';
    final hasBookingWindow =
        request.bookingStart != null && request.bookingEnd != null;
    final bool isTeamModeRequest = request.mode.toLowerCase() == 'team';
    final bool guestTeamReady = _hasTeamDetails(request.guestTeam);
    final int inferredTeamSize = request.teamSize ??
      (request.participantLimit != null
        ? (request.participantLimit! ~/ 2)
        : 0);
    final String? perTeamBadge = inferredTeamSize > 0
      ? '$inferredTeamSize người/đội'
      : null;

    final int teamACount = request.teamA.length;
    final int teamBCount = request.teamB.length;
    final int? teamLimit = request.teamLimit;
    final String teamACounter = teamLimit != null
        ? '$teamACount/$teamLimit'
        : '$teamACount';
    final String teamBCounter = teamLimit != null
        ? '$teamBCount/$teamLimit'
        : '$teamBCount';

    final String joinPrefix = '${request.id}::';
    final bool joiningGuestTeam = _joining.contains('${request.id}::guestTeam');
    final bool joiningTeamA = _joining.contains('${request.id}::teamA');
    final bool joiningTeamB = _joining.contains('${request.id}::teamB');
    final bool joinInProgress = _joining.any(
      (value) => value.startsWith(joinPrefix),
    );
    final bool cancelling = _cancelling.contains(request.id);

    final bool matchFull = isTeamModeRequest
      ? guestTeamReady
      : request.participantLimit != null &&
        request.participantCount >= request.participantLimit!;
    final bool teamAFull = teamLimit != null && teamACount >= teamLimit;
    final bool teamBFull = teamLimit != null && teamBCount >= teamLimit;
    final String? myTeam = request.myTeam;
    final String participantText = isTeamModeRequest
      ? (guestTeamReady
        ? 'Đã có 2 đội${perTeamBadge != null ? ' ($perTeamBadge)' : ''}'
        : 'Còn thiếu đội khách${perTeamBadge != null ? ' ($perTeamBadge)' : ''}')
      : (request.participantLimit != null
        ? '${request.participantCount}/${request.participantLimit} người'
        : '${request.participantCount} người');
    final actions = <Widget>[];
    final timeRangeText = _formatRangeForCard(request);

    if (isOwn) {
      actions.add(
        Chip(
          avatar: Icon(
            isCancelled ? Icons.cancel_outlined : Icons.verified_user,
            size: 18,
          ),
          label: Text(isCancelled ? 'Bạn đã hủy lời mời' : 'Lời mời của bạn'),
        ),
      );

      if (!isCancelled && isOpen) {
        actions.add(
          NeuButton(
            buttonHeight: 40,
            buttonWidth: 140,
            borderRadius: BorderRadius.circular(12),
            buttonColor: cancelling ? Colors.grey : const Color(0xFFDC3545),
            onPressed: cancelling ? () {} : () => _cancelRequest(request),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (cancelling)
                  const NeoLoadingDot(
                    size: 18,
                    fillColor: Colors.white,
                  )
                else
                  const Icon(Icons.cancel_schedule_send_outlined, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  cancelling ? 'Đang hủy...' : 'Hủy lời mời',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    if (isTeamModeRequest) {
      if (myTeam != null && !isCancelled) {
        actions.add(
          Chip(
            avatar: const Icon(Icons.military_tech, size: 18),
            label: Text(
              myTeam == 'teamA'
                  ? 'Đội bạn giữ sân (Team chủ)'
                  : 'Đội bạn là đội khách',
            ),
          ),
        );
      }

      if (isCancelled) {
        actions.add(
          Chip(
            avatar: Icon(
              autoCancelled
                  ? Icons.schedule_send_outlined
                  : Icons.cancel_outlined,
              size: 18,
            ),
            label: Text(
              autoCancelled
                  ? 'Tự hủy do thiếu đội'
                  : 'Lời mời đã hủy',
            ),
          ),
        );
      } else if (!isOpen) {
        actions.add(
          Chip(
            avatar: const Icon(Icons.sports_score_outlined, size: 18),
            label: const Text('Lời mời đã đóng'),
          ),
        );
      } else if (matchFull) {
        actions.add(
          Chip(
            avatar: const Icon(Icons.handshake_outlined, size: 18),
            label: const Text('Đã có đội khách'),
          ),
        );
      } else {
        actions.add(
          Chip(
            avatar: const Icon(Icons.hourglass_bottom, size: 18),
            label: const Text('Đang chờ đội khách'),
          ),
        );

        if (!isOwn) {
          actions.add(
            NeuButton(
              buttonHeight: 44,
              borderRadius: BorderRadius.circular(14),
              buttonColor: joiningGuestTeam
                  ? Colors.grey
                  : theme.colorScheme.primary,
              onPressed:
                  joiningGuestTeam ? () {} : () => _joinTeamMatch(request),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (joiningGuestTeam)
                      NeoLoadingDot(
                        size: 18,
                        fillColor: Colors.white,
                        borderColor: Colors.black,
                        shadowColor: Colors.black.withValues(alpha: 0.55),
                      )
                    else
                      const Icon(
                        Icons.sports_martial_arts,
                        size: 18,
                        color: Colors.white,
                      ),
                    const SizedBox(width: 8),
                    Text(
                      joiningGuestTeam
                          ? 'Đang gửi...'
                          : 'Thách đấu bằng đội bạn',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
      }
    } else if (myTeam != null && !isCancelled) {
      actions.add(
        Chip(
          avatar: const Icon(Icons.handshake, size: 18),
          label: Text(
            myTeam == 'teamA' ? 'Bạn đang ở Team A' : 'Bạn đang ở Team B',
          ),
        ),
      );

      final otherTeam = myTeam == 'teamA' ? 'teamB' : 'teamA';
      final bool otherFull = otherTeam == 'teamA' ? teamAFull : teamBFull;
      final bool otherJoining = otherTeam == 'teamA'
          ? joiningTeamA
          : joiningTeamB;
      final bool canSwitch =
          isOpen && !isCancelled && !otherFull && !joinInProgress;
      final String otherLabel = otherTeam == 'teamA'
          ? (otherFull ? 'Team A đã đủ' : 'Chuyển sang Team A')
          : (otherFull ? 'Team B đã đủ' : 'Chuyển sang Team B');

      actions.add(
        _buildTeamActionButton(
          request: request,
          team: otherTeam,
          label: otherLabel,
          enabled: canSwitch,
          loading: otherJoining,
          icon: Icons.swap_horiz,
          primary: false,
        ),
      );
    } else if (isCancelled) {
      actions.add(
        Chip(
          avatar: Icon(
            autoCancelled
                ? Icons.schedule_send_outlined
                : Icons.cancel_outlined,
            size: 18,
          ),
          label: Text(
            autoCancelled
                ? 'Tự hủy do thiếu người'
                : 'Lời mời đã hủy',
          ),
        ),
      );
    } else if (!isOpen) {
      actions.add(
        Chip(
          avatar: const Icon(Icons.sports_score_outlined, size: 18),
          label: const Text('Lời mời đã đóng'),
        ),
      );
    } else if (matchFull) {
      actions.add(
        Chip(
          avatar: const Icon(Icons.groups, size: 18),
          label: const Text('Lời mời đã đủ người'),
        ),
      );
    } else {
      final bool canJoinTeamA =
          isOpen && !isCancelled && !teamAFull && !joinInProgress;
      final bool canJoinTeamB =
          isOpen && !isCancelled && !teamBFull && !joinInProgress;

      actions.add(
        _buildTeamActionButton(
          request: request,
          team: 'teamA',
          label: teamAFull
              ? 'Team A đã đủ'
              : 'Tham gia Team A ($teamACounter người)',
          enabled: canJoinTeamA,
          loading: joiningTeamA,
          icon: Icons.group_add_outlined,
        ),
      );

      actions.add(
        _buildTeamActionButton(
          request: request,
          team: 'teamB',
          label: teamBFull
              ? 'Team B đã đủ'
              : 'Tham gia Team B ($teamBCounter người)',
          enabled: canJoinTeamB,
          loading: joiningTeamB,
          icon: Icons.group_add_outlined,
        ),
      );
    }
    final facilityParts = <String>[
      'Cơ sở: $facilityLabel',
      'Sân: $courtLabel',
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: NeuContainer(
        color: const Color(0xFFFFFFFF),
        borderColor: Colors.black,
        borderWidth: 3,
        borderRadius: BorderRadius.circular(18),
        shadowColor: Colors.black,
        offset: const Offset(6, 6),
        child: Padding(
          padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    border: Border.all(color: Colors.black, width: 3),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.sports_soccer_outlined,
                    size: 24,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sportLabel,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (isOwn)
                        Text(
                          'Lời mời của bạn',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _buildStatusChip(
                  isOpen: isOpen,
                  isCancelled: isCancelled,
                  matchFull: matchFull,
                  autoCancelled: autoCancelled,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                border: Border.all(color: Colors.black, width: 2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.access_time, size: 18, color: Colors.black),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      timeRangeText,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (autoCancelled)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Lời mời đã tự hủy do không đủ người khi đến giờ bắt đầu.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFFB71C1C),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (hasBookingWindow)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Đặt sân: ${_formatDateTime(request.bookingStart)} - ${_formatDateTime(request.bookingEnd)}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFAF0),
                border: Border.all(color: Colors.black, width: 2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.sports_martial_arts_outlined, size: 18, color: Colors.black),
                  const SizedBox(width: 8),
                  Text(
                    'Trình độ ${request.skillMin ?? 0} - ${request.skillMax ?? 100}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.groups_outlined, size: 18, color: Colors.black),
                  const SizedBox(width: 8),
                  Text(
                    participantText,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                border: Border.all(color: Colors.black, width: 2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.place_outlined, size: 18, color: Colors.black),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      facilityParts.join(' • '),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (request.bookingStatus != null) ...[
              const SizedBox(height: 4),
              Text('Trạng thái đặt sân: ${request.bookingStatus}'),
            ],
            if (request.notes != null && request.notes!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFAF0),
                  border: Border.all(color: Colors.black, width: 2),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black,
                      offset: Offset(3, 3),
                      blurRadius: 0,
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.notes_outlined, size: 18, color: Colors.black87),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        request.notes!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (isTeamModeRequest) ...[
              const SizedBox(height: 12),
              _buildTeamModeSummary(
                request,
                perTeamBadge: perTeamBadge,
              ),
            ] else ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildTeamSnapshot(
                      label: 'Team A',
                      count: teamACount,
                      limit: teamLimit,
                      selected: myTeam == 'teamA',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildTeamSnapshot(
                      label: 'Team B',
                      count: teamBCount,
                      limit: teamLimit,
                      selected: myTeam == 'teamB',
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: actions.isNotEmpty
                  ? actions
                  : [
                      Chip(
                        avatar: const Icon(Icons.info_outline, size: 18),
                        label: const Text('Không thể tham gia lúc này'),
                      ),
                    ],
            ),
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildStatusChip({
    required bool isOpen,
    required bool isCancelled,
    required bool matchFull,
    required bool autoCancelled,
  }) {
    late final String label;
    late final Color bg;
    late final Color borderColor;
    late final IconData icon;

    if (autoCancelled) {
      label = 'Tự hủy (thiếu người)';
      bg = const Color(0xFFFFF3E0);
      borderColor = const Color(0xFFFB8C00);
      icon = Icons.schedule_send_outlined;
    } else if (isCancelled) {
      label = 'Đã hủy';
      bg = const Color(0xFFFFE5E5);
      borderColor = const Color(0xFFDC3545);
      icon = Icons.cancel_outlined;
    } else if (matchFull) {
      label = 'Đã đủ người';
      bg = const Color(0xFFFFE5CC);
      borderColor = const Color(0xFF9C27B0);
      icon = Icons.groups;
    } else if (isOpen) {
      label = 'Đang mở';
      bg = const Color(0xFFE8F5E9);
      borderColor = const Color(0xFF4CAF50);
      icon = Icons.check_circle_outline;
    } else {
      label = 'Đã đóng';
      bg = const Color(0xFFF5F5F5);
      borderColor = Colors.black;
      icon = Icons.info_outline;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black, width: 3),
        boxShadow: const [
          BoxShadow(
            color: Colors.black,
            offset: Offset(3, 3),
            blurRadius: 0,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: borderColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: borderColor,
            ),
          ),
        ],
      ),
    );
  }
}
