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
  DateTime? _desiredEnd;
  int _participantLimit = 2;
  int _teamSizePerSide = 1;
  bool _loading = true;
  bool _submitting = false;
  bool _loadingCourts = false;
  ApiErrorDetails? _error;
  final Set<String> _joining = <String>{};
  final Set<String> _cancelling = <String>{};
  String? _filterSportId;
  bool _filterOnlyOpen = true;
  bool _filterOnlyMine = false;
  String? _selectedVariantId;

  @override
  void initState() {
    super.initState();
    _desiredStart = _roundToNextHour(
      DateTime.now().add(const Duration(hours: 1)),
    );
    _desiredEnd = _desiredStart?.add(const Duration(hours: 2));
    _load();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  DateTime _roundToNextHour(DateTime value) {
    final nextHour = value.add(Duration(hours: value.minute > 0 ? 1 : 0));
    return DateTime(nextHour.year, nextHour.month, nextHour.day, nextHour.hour);
  }

  Sport? _getSportById(String? id) {
    if (id == null) return null;
    for (final sport in _sports) {
      if (sport.id == id) return sport;
    }
    return null;
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
    var size = sport?.teamSize ?? 0;
    if (size <= 0) {
      size = (_maxParticipantsForSport(sportId) / 2).floor();
    }
    if (size < 1) size = 1;
    if (size > 12) size = 12;
    return size;
  }

  List<int> _teamSizeOptionsForCurrentSport() {
    final maxSize = _maxTeamSizeForSport(_selectedSport);
    final capped = maxSize < 1 ? 1 : maxSize;
    return List<int>.generate(capped, (index) => index + 1);
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
      final maxTeamSizeForSport = _maxTeamSizeForSport(nextSport);
      if (nextTeamSize > maxTeamSizeForSport) {
        nextTeamSize = maxTeamSizeForSport;
      }
      if (nextTeamSize < 1) {
        nextTeamSize = 1;
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
        _requests = requests;
        _loading = false;
        _filterSportId = nextFilterSport;
        _selectedVariantId = null;
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
      setState(() => _requests = requests);
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
      setState(() {
        _joining.remove(joinKey);
        _requests = _requests
            .map((item) => item.id == updated.id ? updated : item)
            .toList();
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

  Future<void> _cancelRequest(MatchRequest request) async {
    if (_cancelling.contains(request.id)) return;
    setState(() => _cancelling.add(request.id));
    try {
      final updated = await _api.cancelMatchRequest(request.id);
      if (!mounted) return;
      setState(() {
        _cancelling.remove(request.id);
        _requests = _requests
            .map((item) => item.id == updated.id ? updated : item)
            .toList();
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

      final tentativeEnd = _desiredEnd ?? base.add(const Duration(hours: 2));
      final endTime = TimeOfDay.fromDateTime(tentativeEnd);
      var nextEnd = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        endTime.hour,
        endTime.minute,
      );
      if (!nextEnd.isAfter(_desiredStart!)) {
        nextEnd = _desiredStart!.add(const Duration(hours: 2));
      }
      _desiredEnd = nextEnd;
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
    setState(() {
      _desiredStart = result;
      if (_desiredEnd == null || !_desiredEnd!.isAfter(result)) {
        _desiredEnd = result.add(const Duration(hours: 2));
      }
    });
  }

  Future<void> _pickDesiredEnd() async {
    final now = DateTime.now();
    final fallbackStart = _desiredStart ?? _roundToNextHour(now);
    final base = (_desiredEnd != null && _desiredEnd!.isAfter(fallbackStart))
        ? _desiredEnd!
        : fallbackStart.add(const Duration(hours: 2));
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
    if (!result.isAfter(fallbackStart)) {
      if (!mounted) return;
      await _showSnack(
        'Thời gian kết thúc phải sau thời gian bắt đầu.',
        isError: true,
      );
      return;
    }
    setState(() => _desiredEnd = result);
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
    final end = _desiredEnd;
    if (start == null || end == null || !start.isBefore(end)) {
      await _showSnack('Vui lòng chọn thời gian hợp lệ.', isError: true);
      return;
    }

    final teamSize = _teamSizePerSide;
    if (teamSize < 1) {
      await _showSnack('Vui lòng chọn số người mỗi đội.', isError: true);
      return;
    }

    var participantLimit = _participantLimit;
    final minimumParticipants = teamSize * 2;
    if (participantLimit < minimumParticipants) {
      participantLimit = minimumParticipants;
    }
    if (participantLimit < 2) participantLimit = 2;
    final maxParticipants = _maxParticipantsForSport(sportId);
    if (participantLimit > maxParticipants) {
      participantLimit = maxParticipants;
    }

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
        participantLimit: participantLimit,
        teamSize: teamSize,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _notesController.clear();
        _requests = [request, ..._requests];
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
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(textColor),
                ),
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
        final isOpen = statusLower == 'open';
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
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
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
        _teamSizePerSide = selected;
        _selectedVariantId = null;
        if (_participantLimit < selected * 2) {
          _participantLimit = selected * 2;
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
      body = const Center(child: CircularProgressIndicator());
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
    final variantOptions = _variantOptionsForCurrentSport();
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
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
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
                  'Số người: $_participantLimit tổng, $_teamSizePerSide mỗi bên',
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
              onTap: _showParticipantLimitSheet,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFAF0),
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
                            'Giới hạn người tham gia',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black.withValues(alpha: 0.6),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$_participantLimit người',
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
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
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
    final hasStart = _desiredStart != null;
    final hasEnd = _desiredEnd != null;
    final dateText = _formatDateOnly(_desiredStart);
    final startText = hasStart
        ? _formatTimeOnly(_desiredStart)
        : 'Chưa chọn';
    final endText = hasEnd
        ? _formatTimeOnly(_desiredEnd)
        : 'Chưa chọn';

    Widget buildCard({
      required String title,
      required String value,
      required IconData icon,
      required VoidCallback? onTap,
      bool enabled = true,
    }) {
      final bgColor = enabled
          ? const Color(0xFFFFFFFF)
          : const Color(0xFFF5F5F5);
      final textColor = enabled
          ? Colors.black
          : Colors.black45;
      return GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black, width: 3),
            boxShadow: enabled
                ? const [
                    BoxShadow(
                      color: Colors.black,
                      offset: Offset(4, 4),
                      blurRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: enabled
                      ? const Color(0xFFE8F5E9)
                      : const Color(0xFFF5F5F5),
                  border: Border.all(color: Colors.black, width: 2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: enabled ? Colors.black : Colors.black45,
                  size: 22,
                ),
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
                        color: textColor,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: enabled
                    ? theme.colorScheme.outline
                    : theme.disabledColor,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildCard(
          title: 'Ngày thi đấu',
          value: dateText,
          icon: Icons.calendar_month_outlined,
          onTap: _pickDesiredDate,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: buildCard(
                title: 'Giờ bắt đầu',
                value: startText,
                icon: Icons.play_arrow_outlined,
                onTap: _pickDesiredStart,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: buildCard(
                title: 'Giờ kết thúc',
                value: endText,
                icon: Icons.flag_outlined,
                onTap: hasStart ? _pickDesiredEnd : null,
                enabled: hasStart,
              ),
            ),
          ],
        ),
        if (!hasStart)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Chọn ngày và giờ bắt đầu trước khi điều chỉnh giờ kết thúc.',
              style: theme.textTheme.bodySmall,
            ),
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
    final isOpen = statusLower == 'open';
    final isCancelled = statusLower == 'cancelled';
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
    final bool joiningTeamA = _joining.contains('${request.id}::teamA');
    final bool joiningTeamB = _joining.contains('${request.id}::teamB');
    final bool joinInProgress = _joining.any(
      (value) => value.startsWith(joinPrefix),
    );
    final bool cancelling = _cancelling.contains(request.id);

    final bool matchFull =
        request.participantLimit != null &&
        request.participantCount >= request.participantLimit!;
    final bool teamAFull = teamLimit != null && teamACount >= teamLimit;
    final bool teamBFull = teamLimit != null && teamBCount >= teamLimit;
    final String? myTeam = request.myTeam;
    final actions = <Widget>[];

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
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
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

    if (myTeam != null && !isCancelled) {
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
          avatar: const Icon(Icons.cancel_outlined, size: 18),
          label: const Text('Lời mời đã hủy'),
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
    final participantText = request.participantLimit != null
        ? '${request.participantCount}/${request.participantLimit} người'
        : '${request.participantCount} người';
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
                      'Từ ${_formatDateTime(request.desiredStart)} đến ${_formatDateTime(request.desiredEnd)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
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
  }) {
    late final String label;
    late final Color bg;
    late final Color borderColor;
    late final IconData icon;

    if (isCancelled) {
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
