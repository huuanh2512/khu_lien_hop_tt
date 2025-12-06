import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:neubrutalism_ui/neubrutalism_ui.dart';
import 'package:khu_lien_hop_tt/app_config.dart';
import 'package:khu_lien_hop_tt/customer/match_requests/match_requests_page.dart';
import 'package:khu_lien_hop_tt/customer/user_booking/booking_history_page.dart';
import 'package:khu_lien_hop_tt/customer/user_booking/facility_court_page.dart';
import 'package:khu_lien_hop_tt/customer/user_booking/sport_selection_page.dart';
import 'package:khu_lien_hop_tt/customer/user_finance/user_invoices_page.dart';
import 'package:khu_lien_hop_tt/customer/user_profile/user_profile_page.dart';
import 'package:khu_lien_hop_tt/models/booking.dart';
import 'package:khu_lien_hop_tt/models/match_request.dart';
import 'package:khu_lien_hop_tt/models/sport.dart';
import 'package:khu_lien_hop_tt/models/user.dart';
import 'package:khu_lien_hop_tt/screens/auth/login_page.dart';
import 'package:khu_lien_hop_tt/screens/verify_email_screen.dart';
import 'package:khu_lien_hop_tt/services/api_service.dart';
import 'package:khu_lien_hop_tt/services/auth_service.dart';
import 'package:khu_lien_hop_tt/services/user_billing_service.dart';
import 'package:khu_lien_hop_tt/services/user_booking_service.dart';
import 'package:khu_lien_hop_tt/utils/api_error_utils.dart';
import 'package:khu_lien_hop_tt/widgets/sports_gradient_background.dart';
import 'package:khu_lien_hop_tt/widgets/error_state_widget.dart';
import 'package:khu_lien_hop_tt/widgets/neu_button.dart';
import 'package:khu_lien_hop_tt/widgets/neo_loading.dart';

class CustomerHomePage extends StatefulWidget {
  const CustomerHomePage({super.key});

  @override
  State<CustomerHomePage> createState() => _CustomerHomePageState();
}

class _CustomerHomePageState extends State<CustomerHomePage> {
  static const Duration _sectionAnimationDuration = Duration(milliseconds: 250);
  static const Curve _sectionAnimationCurve = Curves.easeInOut;
  static const Duration _navDoubleTapThreshold = Duration(milliseconds: 450);

  final AuthService _auth = AuthService.instance;
  final ApiService _api = ApiService();
  final UserBillingService _billing = UserBillingService();
  late final Dio _userClient = Dio(
    BaseOptions(
      baseUrl: AppConfig.apiBase,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      responseType: ResponseType.json,
    ),
  )..interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
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
          options.headers.putIfAbsent('Accept', () => 'application/json');
          return handler.next(options);
        },
      ),
    );

  List<Booking> _upcomingBookings = const [];
  List<_UserNotification> _recentNotifications = const [];
  int? _unpaidInvoiceCount;
  List<MatchRequest> _recentMatchRequests = const [];

  bool _loadingOverview = false;

  ApiErrorDetails? _upcomingError;
  ApiErrorDetails? _notificationsError;
  ApiErrorDetails? _invoiceError;
  ApiErrorDetails? _matchRequestsError;

  int _currentIndex = 0;
  final Map<int, Key> _tabKeys = {
    1: UniqueKey(),
    2: UniqueKey(),
    3: UniqueKey(),
    4: UniqueKey(),
  };
  DateTime? _lastNavTapTime;
  int? _lastNavTappedIndex;

  @override
  void initState() {
    super.initState();
    _auth.addListener(_handleAuthChanged);
    _loadAll();
  }

  @override
  void dispose() {
    _auth.removeListener(_handleAuthChanged);
    _userClient.close(force: true);
    super.dispose();
  }

  void _handleAuthChanged() {
    if (!mounted) return;
    _loadAll();
  }

  Future<void> _loadAll() async {
    final user = _auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _upcomingBookings = const [];
        _recentNotifications = const [];
        _unpaidInvoiceCount = null;
        _recentMatchRequests = const [];
        _upcomingError = null;
        _notificationsError = null;
        _invoiceError = null;
        _matchRequestsError = null;
        _loadingOverview = false;
      });
      return;
    }

    if (mounted) {
      setState(() {
        _loadingOverview = true;
        _upcomingError = null;
        _notificationsError = null;
        _invoiceError = null;
        _upcomingBookings = const [];
        _recentNotifications = const [];
        _unpaidInvoiceCount = null;
        _recentMatchRequests = const [];
        _matchRequestsError = null;
      });
    }

    try {
      final upcomingFuture = _api.getUserUpcomingBookings();
      final notificationsFuture = _fetchUserNotifications(limit: 3);
      final invoicesFuture = _billing.fetchInvoices();
      final matchRequestsFuture = _api.getMatchRequests(limit: 10);

      List<Booking> upcoming = const [];
      ApiErrorDetails? upcomingError;
      try {
        final bookings = await upcomingFuture;
        upcoming = _prepareUpcomingBookings(bookings);
      } catch (error) {
        upcomingError = _friendlyError(error);
      }

      List<_UserNotification> notifications = const [];
      ApiErrorDetails? notificationsError;
      try {
        notifications = await notificationsFuture;
      } catch (error) {
        notificationsError = _friendlyError(error);
      }

      int? unpaidCount;
      ApiErrorDetails? invoiceError;
      try {
        final invoices = await invoicesFuture;
        unpaidCount = invoices
            .where((invoice) => invoice.status.toLowerCase() != 'paid')
            .length;
      } catch (error) {
        invoiceError = _friendlyError(error);
      }

      List<MatchRequest> recentRequests = const [];
      ApiErrorDetails? matchRequestsError;
      try {
        final requests = await matchRequestsFuture;
        recentRequests = _prepareRecentMatchRequests(requests);
      } catch (error) {
        matchRequestsError = _friendlyError(error);
      }

      if (!mounted) return;

      setState(() {
        _upcomingBookings = upcoming;
        _recentNotifications = notifications;
        _unpaidInvoiceCount = unpaidCount;
        _upcomingError = upcomingError;
        _notificationsError = notificationsError;
        _invoiceError = invoiceError;
        _recentMatchRequests = recentRequests;
        _matchRequestsError = matchRequestsError;
        _loadingOverview = false;
      });
    } catch (error) {
      if (!mounted) return;
      final message = _friendlyError(error);
      setState(() {
        _upcomingBookings = const [];
        _recentNotifications = const [];
        _unpaidInvoiceCount = null;
        _upcomingError = message;
        _notificationsError = message;
        _invoiceError = message;
        _recentMatchRequests = const [];
        _matchRequestsError = message;
        _loadingOverview = false;
      });
    }
  }

  Future<void> _refreshOverview() async {
    await _loadAll();
  }

  void _redirectToLogin() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  void _redirectToVerifyEmail() {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const VerifyEmailScreen()),
    );
  }

  List<Booking> _prepareUpcomingBookings(List<Booking> bookings) {
    final now = DateTime.now().toLocal();
    const allowedStatuses = {'pending', 'confirmed'};
    final filtered = bookings.where((booking) {
      final status = booking.status.toLowerCase();
      if (!allowedStatuses.contains(status)) return false;
      return booking.end.toLocal().isAfter(now);
    }).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    return filtered.take(3).toList(growable: false);
  }

  List<MatchRequest> _prepareRecentMatchRequests(
    List<MatchRequest> requests,
  ) {
    if (requests.isEmpty) return const [];
    final now = DateTime.now().toLocal();
    final filtered = requests.where((request) {
      final status = request.status.toLowerCase();
      const excludedStatuses = {
        'cancelled',
        'canceled',
        'expired',
        'closed',
        'ended',
        'completed',
      };
      if (excludedStatuses.contains(status)) return false;
      final start = (request.desiredStart ?? request.bookingStart);
      if (start == null) return false;
      return !start.toLocal().isBefore(now);
    }).toList();
    if (filtered.isEmpty) return const [];
    filtered.sort((a, b) {
      final aDate = a.createdAt ?? a.desiredStart ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b.createdAt ?? b.desiredStart ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
    return filtered.take(3).toList(growable: false);
  }

  Future<List<_UserNotification>> _fetchUserNotifications({int limit = 3}) async {
    try {
      final response = await _userClient.get<dynamic>(
        '/api/user/notifications',
        queryParameters: {
          if (limit > 0) 'limit': limit.toString(),
        },
      );
      final data = response.data;
      if (data == null) return const [];
      if (data is! List) {
        throw Exception('Phản hồi thông báo không hợp lệ');
      }
      final items = data
          .whereType<Map<String, dynamic>>()
          .map(_UserNotification.fromJson)
          .toList(growable: false);
      if (limit > 0 && items.length > limit) {
        return items.take(limit).toList(growable: false);
      }
      return items;
    } on DioException catch (error) {
      final response = error.response;
      final bodyText = response?.data?.toString();
      final message = bodyText != null && bodyText.trim().isNotEmpty
          ? bodyText
          : error.message ?? 'Không thể tải thông báo';
      throw Exception(message);
    }
  }

  void _startBooking(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return Padding(
          padding: const EdgeInsets.all(16),
          child: NeuContainer(
            color: const Color(0xFFFFF8DC),
            borderColor: Colors.black,
            borderWidth: 3,
            borderRadius: BorderRadius.circular(16),
            shadowColor: Colors.black.withValues(alpha: 0.25),
            offset: const Offset(5, 5),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Chọn cách đặt sân',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _startQuickBooking(context);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.black, width: 2),
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
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFE5E5),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.black, width: 2),
                            ),
                            child: const Icon(Icons.flash_on, size: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Đặt sân nhanh',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Sử dụng môn ưa thích hoặc lịch gần đây để đề xuất nhanh.',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _startFullBooking(context);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.black, width: 2),
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
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE6F3FF),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.black, width: 2),
                            ),
                            child: const Icon(Icons.sports_tennis, size: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Đặt sân đầy đủ',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Chọn môn, sân và thời gian chi tiết.',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: const BorderSide(color: Colors.black, width: 2),
                        ),
                      ),
                      child: const Text(
                        'Huỷ',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _startQuickBooking(BuildContext context) async {
    final user = _auth.currentUser;
    if (user == null) {
      _startFullBooking(context);
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final pageNavigator = Navigator.of(context);
    final rootNavigator = Navigator.of(context, rootNavigator: true);

    Future<void> openFullBookingViaNavigator() async {
      await pageNavigator.push(
        MaterialPageRoute(builder: (_) => const UserBookingSportSelectionPage()),
      );
    }

    String? mainSportId = user.mainSportId;
    if (mainSportId == null || mainSportId.isEmpty) {
      try {
        final refreshed = await _auth.reloadCurrentUser();
        mainSportId = refreshed.mainSportId;
      } catch (error) {
        debugPrint('Failed to refresh user before quick booking: $error');
      }
      if (!context.mounted) return;
    }

    if (mainSportId == null || mainSportId.isEmpty) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content:
              Text('Bạn chưa chọn môn ưa thích. Vui lòng đặt sân theo cách đầy đủ.'),
        ),
      );
      await openFullBookingViaNavigator();
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: NeoLoadingCard(
          label: 'Đang chuẩn bị đặt nhanh...',
          width: 240,
          height: 180,
        ),
      ),
    );

    try {
      final service = UserBookingService();
      final sports = await service.fetchSports();
      Sport? selectedSport;
      for (final sport in sports) {
        if (sport.id == mainSportId) {
          selectedSport = sport;
          break;
        }
      }
      if (rootNavigator.mounted) {
        rootNavigator.pop();
      }
      if (!mounted) return;
      if (selectedSport == null) {
        messenger.showSnackBar(
          const SnackBar(
            content:
                Text('Không tìm thấy môn ưa thích. Vui lòng đặt sân theo cách đầy đủ.'),
          ),
        );
        await openFullBookingViaNavigator();
        return;
      }

      await pageNavigator.push(
        MaterialPageRoute(
          builder: (_) => FacilityCourtSelectionPage(sport: selectedSport!),
          settings: RouteSettings(
            name: 'customer.quick_booking.facility',
            arguments: {
              'quickMode': true,
              'preselectedSportId': mainSportId,
            },
          ),
        ),
      );
    } catch (error) {
      if (rootNavigator.mounted) {
        rootNavigator.pop();
      }
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Không thể tải môn ưa thích: $error'),
        ),
      );
      await openFullBookingViaNavigator();
    }
  }

  void _startFullBooking(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const UserBookingSportSelectionPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;

    return SportsGradientBackground(
      variant: SportsBackgroundVariant.customer,
      hideTopLeftAccent: true,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: false,
        body: SafeArea(
          top: false,
          bottom: false,
          child: IndexedStack(
            index: _currentIndex,
            children: [
              _buildOverviewTab(user),
              BookingHistoryPage(key: _tabKeys[1], embedded: true),
              UserInvoicesPage(key: _tabKeys[2], embedded: true),
              MatchRequestsPage(key: _tabKeys[3], embedded: true),
              UserProfilePage(
                key: _tabKeys[4],
                embedded: true,
                onProfileChanged: _loadAll,
              ),
            ],
          ),
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFFFE5CC),
            border: const Border(
              top: BorderSide(color: Colors.black, width: 3),
            ),
            boxShadow: const [
              BoxShadow(
                color: Colors.black,
                offset: Offset(0, -4),
                blurRadius: 0,
              ),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: BottomNavigationBar(
                type: BottomNavigationBarType.fixed,
                backgroundColor: Colors.transparent,
                elevation: 0,
                currentIndex: _currentIndex,
                onTap: _handleNavTap,
                selectedItemColor: Colors.black,
                unselectedItemColor: Colors.black54,
                selectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 11,
                ),
                selectedIconTheme: const IconThemeData(
                  size: 26,
                ),
                unselectedIconTheme: const IconThemeData(
                  size: 24,
                ),
                items: const [
                  BottomNavigationBarItem(
                    icon: Icon(Icons.home_outlined),
                    activeIcon: Icon(Icons.home),
                    label: 'Tổng quan',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.event_note_outlined),
                    activeIcon: Icon(Icons.event_note),
                    label: 'Đặt sân',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.receipt_long_outlined),
                    activeIcon: Icon(Icons.receipt_long),
                    label: 'Hoá đơn',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.handshake_outlined),
                    activeIcon: Icon(Icons.handshake),
                    label: 'Ghép trận',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.person_outline),
                    activeIcon: Icon(Icons.person),
                    label: 'Hồ sơ',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleNavTap(int index) {
    final now = DateTime.now();
    final sameTab = index == _currentIndex;
    final isDoubleTap = sameTab &&
        _lastNavTappedIndex == index &&
        _lastNavTapTime != null &&
        now.difference(_lastNavTapTime!) <= _navDoubleTapThreshold;

    _lastNavTapTime = now;
    _lastNavTappedIndex = index;

    if (!sameTab) {
      setState(() => _currentIndex = index);
      _reloadTab(index);
      return;
    }

    if (isDoubleTap) {
      _reloadTab(index);
    }
  }

  void _reloadTab(int index) {
    if (index == 0) {
      _refreshOverview();
      return;
    }
    if (!_tabKeys.containsKey(index)) return;
    setState(() {
      _tabKeys[index] = UniqueKey();
    });
  }

  Widget _buildOverviewTab(AppUser? user) {
    final mediaPadding = MediaQuery.of(context).padding;
    final topPadding = mediaPadding.top + 24;
    final bottomPadding = mediaPadding.bottom + 24;

    if (user == null) {
      return Padding(
        padding: EdgeInsets.fromLTRB(16, topPadding, 16, bottomPadding),
        child: Center(
          child: Text(
            'Vui lòng đăng nhập để xem tổng quan hoạt động của bạn.',
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshOverview,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, topPadding, 16, bottomPadding),
        children: [
          _buildQuickActions(context),
          const SizedBox(height: 16),
          _buildUpcomingSection(context),
          const SizedBox(height: 16),
          _buildMatchRequestsSection(context),
          const SizedBox(height: 16),
          _buildNotificationSection(context),
          const SizedBox(height: 16),
          _buildInvoiceSection(context),
        ],
      ),
    );
  }

  Widget _wrapSection(Widget child) {
    return AnimatedContainer(
      duration: _sectionAnimationDuration,
      curve: _sectionAnimationCurve,
      child: child,
    );
  }

  // Shared async state renderer to keep section presentation consistent.
  Widget _buildAsyncSection({
    required bool isLoading,
    required Widget child,
    ApiErrorDetails? error,
    VoidCallback? onRetry,
    String loadingLabel = 'Đang tải...',
  }) {
    return AsyncSection(
      isLoading: isLoading,
      error: error,
      loadingLabel: loadingLabel,
      onRetry: onRetry ?? () {
        _refreshOverview();
      },
      onLogin: _redirectToLogin,
      onVerifyEmail: _redirectToVerifyEmail,
      child: child,
    );
  }

  Widget _buildSectionError(ApiErrorDetails details, {VoidCallback? onRetry}) {
    return ErrorStateWidget(
      statusCode: details.statusCode,
      message: details.message,
      onRetry: onRetry ?? () {
        _refreshOverview();
      },
      onLogin: _redirectToLogin,
      onVerifyEmail: _redirectToVerifyEmail,
      padding: const EdgeInsets.symmetric(vertical: 12),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    final theme = Theme.of(context);
    return _wrapSection(
      NeuContainer(
        color: const Color(0xFFFFF8DC),
        borderColor: Colors.black,
        borderWidth: 3,
        borderRadius: BorderRadius.circular(16),
        shadowColor: Colors.black.withValues(alpha: 0.25),
        offset: const Offset(6, 6),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.black, width: 2),
                    ),
                    child: const Icon(Icons.bolt, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Thao tác nhanh',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: NeuButton(
                      buttonHeight: 48,
                      buttonWidth: double.infinity,
                      borderRadius: BorderRadius.circular(12),
                      buttonColor: theme.colorScheme.primary,
                      onPressed: () => _startBooking(context),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.sports_tennis_outlined, color: Colors.white, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Đặt sân',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: NeuButton(
                      buttonHeight: 48,
                      buttonWidth: double.infinity,
                      borderRadius: BorderRadius.circular(12),
                      buttonColor: Colors.white,
                      onPressed: _openMatchRequests,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.handshake_outlined, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Tìm đối thủ',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUpcomingSection(BuildContext context) {
    final theme = Theme.of(context);
    Widget content;
    if (_upcomingBookings.isEmpty) {
      content = Text(
        'Bạn chưa có lịch đặt sân sắp tới.',
        style: theme.textTheme.bodyMedium,
      );
    } else {
      content = Column(
        children: [
          for (var i = 0; i < _upcomingBookings.length; i++)
            Container(
              margin: EdgeInsets.only(top: i == 0 ? 0 : 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black, width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black,
                    offset: Offset(3, 3),
                    blurRadius: 0,
                  ),
                ],
              ),
              child: _buildUpcomingBookingInfo(_upcomingBookings[i], theme),
            ),
        ],
      );
    }

    return _wrapSection(
      NeuContainer(
        color: const Color(0xFFE6F3FF),
        borderColor: Colors.black,
        borderWidth: 3,
        borderRadius: BorderRadius.circular(16),
        shadowColor: Colors.black.withValues(alpha: 0.25),
        offset: const Offset(6, 6),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.black, width: 2),
                    ),
                    child: const Icon(Icons.event_note, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Lịch đặt sân sắp tới',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _goToBookingsTab,
                    child: const Text('Xem tất cả'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildAsyncSection(
                isLoading: _loadingOverview,
                error: _upcomingError,
                loadingLabel: 'Đang tải lịch đặt sân...',
                child: content,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMatchRequestsSection(BuildContext context) {
    final theme = Theme.of(context);
    Widget body;
    if (_loadingOverview) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: NeoLoadingCard(
            label: 'Đang tải lời mời...',
            width: 240,
          ),
        ),
      );
    } else if (_matchRequestsError != null) {
      body = _buildSectionError(
        _matchRequestsError!,
        onRetry: () {
          _refreshOverview();
        },
      );
    } else if (_recentMatchRequests.isEmpty) {
      body = Text(
        'Bạn chưa có lời mời ghép trận nào.',
        style: theme.textTheme.bodyMedium,
      );
    } else {
      body = Column(
        children: [
          for (var i = 0; i < _recentMatchRequests.length; i++)
            Container(
              margin: EdgeInsets.only(top: i == 0 ? 0 : 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black, width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black,
                    offset: Offset(3, 3),
                    blurRadius: 0,
                  ),
                ],
              ),
              child: _buildMatchRequestPreview(
                _recentMatchRequests[i],
                theme,
              ),
            ),
        ],
      );
    }

    return _wrapSection(
      NeuContainer(
        color: const Color(0xFFE8F5E9),
        borderColor: Colors.black,
        borderWidth: 3,
        borderRadius: BorderRadius.circular(16),
        shadowColor: Colors.black.withValues(alpha: 0.25),
        offset: const Offset(6, 6),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.black, width: 2),
                    ),
                    child: const Icon(Icons.handshake, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Lời mời ghép trận',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _openMatchRequests,
                    child: const Text('Xem tất cả'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              body,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUpcomingBookingInfo(Booking booking, ThemeData theme) {
    final court = booking.courtName ?? booking.sportName ?? 'Sân #${booking.courtId}';
    final facility = booking.facilityName ?? 'Cơ sở ${booking.facilityId}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(court, style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          facility,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
        Text(
          _formatBookingWindow(booking.start, booking.end),
          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            _bookingStatusLabel(booking.status),
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  Widget _buildNotificationSection(BuildContext context) {
    final theme = Theme.of(context);
    Widget content;
    if (_recentNotifications.isEmpty) {
      content = Text(
        'Bạn chưa có thông báo mới.',
        style: theme.textTheme.bodyMedium,
      );
    } else {
      content = Column(
        children: [
          for (var i = 0; i < _recentNotifications.length; i++)
            Container(
              margin: EdgeInsets.only(top: i == 0 ? 0 : 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _recentNotifications[i].isUnread
                    ? const Color(0xFFFFF8DC)
                    : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _recentNotifications[i].isUnread
                      ? theme.colorScheme.primary
                      : Colors.black,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _recentNotifications[i].isUnread
                        ? theme.colorScheme.primary.withValues(alpha: 0.3)
                        : Colors.black,
                    offset: const Offset(3, 3),
                    blurRadius: 0,
                  ),
                ],
              ),
              child: _buildNotificationPreview(_recentNotifications[i], theme),
            ),
        ],
      );
    }

    return _wrapSection(
      NeuContainer(
        color: const Color(0xFFFFE5E5),
        borderColor: Colors.black,
        borderWidth: 3,
        borderRadius: BorderRadius.circular(16),
        shadowColor: Colors.black.withValues(alpha: 0.25),
        offset: const Offset(6, 6),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.black, width: 2),
                    ),
                    child: const Icon(Icons.notifications, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Thông báo mới',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildAsyncSection(
                isLoading: _loadingOverview,
                error: _notificationsError,
                loadingLabel: 'Đang tải thông báo...',
                child: content,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationPreview(_UserNotification notification, ThemeData theme) {
    final title = notification.title?.isNotEmpty == true
        ? notification.title!
        : 'Thông báo';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              notification.isUnread ? Icons.notifications_active : Icons.notifications_none,
              color: notification.isUnread
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleSmall),
                  if ((notification.message ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        notification.message!,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _formatDateTime(notification.createdAt),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInvoiceSection(BuildContext context) {
    final theme = Theme.of(context);
    final count = _unpaidInvoiceCount ?? 0;
    final hasUnpaid = count > 0;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          hasUnpaid
              ? 'Bạn có $count hoá đơn chưa thanh toán.'
              : 'Không có hoá đơn chưa thanh toán.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: NeuButton(
            buttonHeight: 44,
            buttonWidth: 180,
            borderRadius: BorderRadius.circular(12),
            buttonColor: hasUnpaid
                ? theme.colorScheme.primary
                : Colors.white,
            onPressed: _goToInvoicesTab,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.receipt_long_outlined,
                  color: hasUnpaid ? Colors.white : Colors.black,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  hasUnpaid ? 'Thanh toán ngay' : 'Xem hoá đơn',
                  style: TextStyle(
                    color: hasUnpaid ? Colors.white : Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    return _wrapSection(
      NeuContainer(
        color: const Color(0xFFF3E5F5),
        borderColor: Colors.black,
        borderWidth: 3,
        borderRadius: BorderRadius.circular(16),
        shadowColor: Colors.black.withValues(alpha: 0.25),
        offset: const Offset(6, 6),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.black, width: 2),
                    ),
                    child: const Icon(Icons.receipt, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Tình trạng hoá đơn',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildAsyncSection(
                isLoading: _loadingOverview,
                error: _invoiceError,
                loadingLabel: 'Đang tải hoá đơn...',
                child: content,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMatchRequestPreview(MatchRequest request, ThemeData theme) {
    final sportLabel = (request.sportName?.trim().isNotEmpty ?? false)
        ? request.sportName!.trim()
        : 'Môn thể thao (chưa xác định)';
    final facilityLabel = (request.facilityName?.trim().isNotEmpty ?? false)
        ? request.facilityName!.trim()
        : '(chưa rõ)';
    final courtLabel = (request.courtName?.trim().isNotEmpty ?? false)
        ? request.courtName!.trim()
        : '(chưa rõ)';
    final timeLabel = _formatMatchRequestTime(request);
    final statusLabel = _matchRequestStatusLabel(request.status);
    final locationParts = <String>[
      'Cơ sở: $facilityLabel',
      'Sân: $courtLabel',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(sportLabel, style: theme.textTheme.titleMedium),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            locationParts.join(' • '),
            style: theme.textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          timeLabel,
          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            statusLabel,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  void _openMatchRequests() {
    if (_currentIndex == 3) return;
    setState(() => _currentIndex = 3);
  }

  void _goToBookingsTab() {
    if (_currentIndex == 1) return;
    setState(() => _currentIndex = 1);
  }

  void _goToInvoicesTab() {
    if (_currentIndex == 2) return;
    setState(() => _currentIndex = 2);
  }

  String _formatBookingWindow(DateTime start, DateTime end) {
    final localStart = start.toLocal();
    final localEnd = end.toLocal();
    final startDate = '${_two(localStart.day)}/${_two(localStart.month)}';
    final startTime = '${_two(localStart.hour)}:${_two(localStart.minute)}';
    final endTime = '${_two(localEnd.hour)}:${_two(localEnd.minute)}';
    return '$startDate $startTime - $endTime';
  }

  String _bookingStatusLabel(String status) {
    final normalized = status.toLowerCase();
    switch (normalized) {
      case 'confirmed':
        return 'Đã xác nhận';
      case 'pending':
        return 'Chờ xác nhận';
      case 'completed':
        return 'Hoàn tất';
      case 'cancelled':
        return 'Đã huỷ';
      default:
        return status;
    }
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) return '--';
    final local = value.toLocal();
    return '${_two(local.day)}/${_two(local.month)} ${_two(local.hour)}:${_two(local.minute)}';
  }

  String _formatMatchRequestTime(MatchRequest request) {
    final start = request.desiredStart;
    final end = request.desiredEnd;
    if (start == null && end == null) {
      return 'Thời gian sẽ cập nhật sau';
    }
    if (start != null && end != null) {
      final localStart = start.toLocal();
      final localEnd = end.toLocal();
      final sameDay = localStart.year == localEnd.year &&
          localStart.month == localEnd.month &&
          localStart.day == localEnd.day;
      final startLabel =
          '${_two(localStart.day)}/${_two(localStart.month)} ${_two(localStart.hour)}:${_two(localStart.minute)}';
      final endLabel = '${_two(localEnd.hour)}:${_two(localEnd.minute)}';
      if (sameDay) {
        return '$startLabel - $endLabel';
      }
      final endDateLabel = '${_two(localEnd.day)}/${_two(localEnd.month)} $endLabel';
      return '$startLabel - $endDateLabel';
    }
    final single = (start ?? end)!.toLocal();
    return '${_two(single.day)}/${_two(single.month)} ${_two(single.hour)}:${_two(single.minute)}';
  }

  String _matchRequestStatusLabel(String status) {
    final normalized = status.toLowerCase();
    switch (normalized) {
      case 'open':
        return 'Đang tìm đối thủ';
      case 'matched':
        return 'Đã ghép';
      case 'cancelled':
        return 'Đã huỷ';
      case 'closed':
        return 'Đã đóng';
      default:
        return status;
    }
  }

  ApiErrorDetails _friendlyError(Object error) {
    final parsed = parseApiError(error);
    final message = parsed.message?.trim();
    if (message != null && message.isNotEmpty) {
      return parsed;
    }
    return ApiErrorDetails(
      statusCode: parsed.statusCode,
      message: 'Không tải được dữ liệu, kéo để thử lại',
      raw: parsed.raw,
    );
  }

  String _two(int value) => value.toString().padLeft(2, '0');
}

class _UserNotification {
  const _UserNotification({
    required this.id,
    required this.status,
    this.title,
    this.message,
    this.createdAt,
  });

  final String id;
  final String status;
  final String? title;
  final String? message;
  final DateTime? createdAt;

  bool get isUnread => status.toLowerCase() != 'read';

  factory _UserNotification.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic value) {
      if (value is DateTime) return value.toLocal();
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    final rawId = json['id'] ?? json['_id'];
    return _UserNotification(
      id: rawId?.toString() ?? '',
      status: (json['status'] ?? 'unread').toString(),
      title: json['title']?.toString(),
      message: json['message']?.toString(),
      createdAt: parseDate(json['createdAt']),
    );
  }
}

class AsyncSection extends StatelessWidget {
  const AsyncSection({
    super.key,
    required this.isLoading,
    required this.child,
    required this.onRetry,
    this.error,
    this.onLogin,
    this.onVerifyEmail,
    this.loadingLabel = 'Đang tải...',
  });

  final bool isLoading;
  final Widget child;
  final ApiErrorDetails? error;
  final VoidCallback onRetry;
  final VoidCallback? onLogin;
  final VoidCallback? onVerifyEmail;
  final String loadingLabel;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: NeoLoadingCard(
            label: loadingLabel,
            width: 240,
          ),
        ),
      );
    }

    if (error != null) {
      return ErrorStateWidget(
        statusCode: error!.statusCode,
        message: error!.message,
        onRetry: onRetry,
        onLogin: onLogin,
        onVerifyEmail: onVerifyEmail,
        padding: const EdgeInsets.symmetric(vertical: 12),
      );
    }

    return child;
  }
}
