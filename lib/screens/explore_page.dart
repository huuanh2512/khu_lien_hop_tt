import 'dart:async';
import 'package:flutter/material.dart';
import '../models/facility.dart';
import '../models/sport.dart';
import '../models/court.dart';
import '../services/api_service.dart';
import '../widgets/status_badge.dart';
import '../utils/sport_icons.dart';

class ExplorePage extends StatefulWidget {
  final int refreshTick;
  const ExplorePage({super.key, this.refreshTick = 0});

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  final _api = ApiService();
  late Future<void> _initFuture;
  List<Facility> _facilities = const [];
  List<Sport> _sports = const [];
  Facility? _selectedFacility;
  Sport? _selectedSport;
  Future<List<Court>>? _courtsFuture;

  Future<void> _loadInitial() async {
    final results = await Future.wait([_api.getFacilities(), _api.getSports()]);
    _facilities = results[0] as List<Facility>;
    _sports = results[1] as List<Sport>;
    if (_facilities.isNotEmpty) {
      _selectedFacility ??= _facilities.first;
      _loadCourts();
    }
  }

  void _loadCourts() {
    final fac = _selectedFacility;
    if (fac == null) {
      setState(() => _courtsFuture = Future.value(const <Court>[]));
      return;
    }
    setState(() {
      _courtsFuture = _api.getCourtsByFacility(
        fac.id,
        sportId: _selectedSport?.id,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    _initFuture = _loadInitial();
  }

  @override
  void didUpdateWidget(covariant ExplorePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTick != widget.refreshTick) {
      setState(() => _initFuture = _loadInitial());
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Lỗi: ${snapshot.error}'));
        }
        if (_facilities.isEmpty) {
          return const Center(child: Text('Chưa có cơ sở hoạt động'));
        }

        final sportMap = {for (final s in _sports) s.id: s};

        return Column(
          children: [
            // Filters
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<Facility>(
                          decoration: const InputDecoration(
                            labelText: 'Chọn cơ sở',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          initialValue: _selectedFacility,
                          items: _facilities
                              .map(
                                (f) => DropdownMenuItem(
                                  value: f,
                                  child: Text(f.name),
                                ),
                              )
                              .toList(),
                          onChanged: (f) {
                            _selectedFacility = f;
                            _loadCourts();
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (_selectedFacility != null) const StatusBadge.active(),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ChoiceChip(
                          label: const Text('Tất cả'),
                          selected: _selectedSport == null,
                          onSelected: (v) {
                            if (v) {
                              setState(() => _selectedSport = null);
                              _loadCourts();
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                        ..._sports.map(
                          (s) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(sportIcon(s.code), size: 16),
                                  const SizedBox(width: 6),
                                  Text(s.name),
                                ],
                              ),
                              selected: _selectedSport?.id == s.id,
                              onSelected: (v) {
                                setState(() => _selectedSport = v ? s : null);
                                _loadCourts();
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Courts grid
            Expanded(
              child: FutureBuilder<List<Court>>(
                future: _courtsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Lỗi: ${snapshot.error}'));
                  }
                  final courts = snapshot.data ?? const <Court>[];
                  if (courts.isEmpty) {
                    return const Center(child: Text('Không có sân phù hợp'));
                  }
                  final isWide = MediaQuery.of(context).size.width > 600;
                  final crossAxisCount = isWide ? 3 : 2;
                  return RefreshIndicator(
                    onRefresh: () async => _loadCourts(),
                    child: GridView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 1.2,
                      ),
                      itemCount: courts.length,
                      itemBuilder: (context, i) {
                        final c = courts[i];
                        final sport = sportMap[c.sportId];
                        return Card(
                          elevation: 1,
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => Navigator.of(
                              context,
                            ).pushNamed('/booking', arguments: c),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          c.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                      const Icon(Icons.chevron_right),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  if (c.code != null && c.code!.isNotEmpty)
                                    Text(
                                      c.code!,
                                      style: const TextStyle(
                                        color: Colors.black54,
                                      ),
                                    ),
                                  const Spacer(),
                                  Row(
                                    children: [
                                      Icon(
                                        sportIcon(sport?.code),
                                        size: 18,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          sport?.name ?? 'Không rõ môn',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.bottomLeft,
                                    child: OutlinedButton.icon(
                                      icon: const Icon(Icons.calendar_month),
                                      label: const Text('Đặt sân'),
                                      onPressed: () => Navigator.of(
                                        context,
                                      ).pushNamed('/booking', arguments: c),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
