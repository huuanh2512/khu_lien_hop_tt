import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'services/auth_service.dart';
import 'screens/auth/login_page.dart';
import 'screens/auth/register_page.dart';
import 'screens/verify_email_screen.dart';
import 'screens/sports_page.dart';
import 'screens/facilities_page.dart';
import 'admin/courts_admin_page.dart';
import 'admin/price_profiles_page.dart';
import 'admin/users_page.dart';
import 'admin/bookings_admin_page.dart';
import 'admin/audit_logs_page.dart';
import 'customer/customer_home_page.dart';
import 'staff/staff_home_page.dart';
import 'models/user.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await initializeDateFormatting('vi');
  await AuthService.instance.restoreSessionFromStorage();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthService.instance;
    return AnimatedBuilder(
      animation: auth,
      builder: (context, _) {
        final user = auth.currentUser;
        Widget home;
        if (!auth.isLoggedIn || user == null) {
          home = const LoginPage();
        } else if (user.role == 'customer' && !auth.isCustomerEmailVerified) {
          home = const VerifyEmailScreen();
        } else {
          switch (user.role) {
            case 'admin':
              home = const AdminDashboardPage();
              break;
            case 'staff':
              home = const StaffHomePage();
              break;
            default:
              home = const CustomerHomePage();
          }
        }

        return MaterialApp(
          title: 'Khu Liên Hợp Thể Thao',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          ),
          locale: const Locale('vi'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ], 
          supportedLocales: const [
            Locale('vi'),
            Locale('en'),
          ],
          routes: {'/register': (_) => const RegisterPage()},
          home: home,
        );
      },
    );
  }
}

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _layerOne;
  late final Animation<double> _layerTwo;

  static const List<Color> _backgroundGradient = [
    Color(0xFF0D1B2A),
    Color(0xFF1B4332),
    Color(0xFF2D6A4F),
  ];
  static const Color _highlightColor = Color(0xFF45DFB1);
  static const Color _accentColor = Color(0xFF48CAE4);
  static const Color _cardOverlay = Color(0x1AFFFFFF);

  final List<_AdminAction> _actions = const [
    _AdminAction(
      icon: Icons.sports,
      title: 'Môn thể thao',
      description: 'Cập nhật danh sách môn và quy định bộ môn.',
      builder: _buildSports,
    ),
    _AdminAction(
      icon: Icons.location_city,
      title: 'Khu liên hợp',
      description: 'Quản lý cơ sở, tiện ích và thông tin hiển thị.',
      builder: _buildFacilities,
    ),
    _AdminAction(
      icon: Icons.sports_tennis,
      title: 'Sân thi đấu',
      description: 'Theo dõi, cấu hình sân và lịch bảo trì.',
      builder: _buildCourts,
    ),
    _AdminAction(
      icon: Icons.price_change,
      title: 'Bảng giá',
      description: 'Thiết lập gói giá, khuyến mãi và phụ phí.',
      builder: _buildPriceProfiles,
    ),
    _AdminAction(
      icon: Icons.people_alt,
      title: 'Người dùng',
      description: 'Phân quyền, kích hoạt và hỗ trợ khách hàng.',
      builder: _buildUsers,
    ),
    _AdminAction(
      icon: Icons.calendar_month,
      title: 'Đặt sân',
      description: 'Xử lý đơn đặt, kiểm tra tình trạng và duyệt.',
      builder: _buildBookings,
    ),
    _AdminAction(
      icon: Icons.history,
      title: 'Lịch sử thao tác',
      description: 'Theo dõi hành động để đảm bảo minh bạch.',
      builder: _buildAuditLogs,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5800),
    )..repeat(reverse: true);
    _layerOne = Tween<double>(begin: -30, end: 30).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
    );
    _layerTwo = Tween<double>(begin: 25, end: -25).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;
    final theme = Theme.of(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Bảng điều khiển Admin'),
        actions: [
          if (user != null)
            AnimatedOpacity(
              duration: const Duration(milliseconds: 500),
              opacity: 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: _accentColor.withValues(alpha: 0.25),
                      child: const Icon(Icons.person, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      user.name?.isNotEmpty == true ? user.name! : user.email,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          IconButton(
            tooltip: 'Đăng xuất',
            onPressed: () async {
              final navigator = Navigator.of(context);
              await AuthService.instance.logout();
              if (!mounted) return;
              navigator.pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginPage()),
                (route) => false,
              );
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: _backgroundGradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          Positioned.fill(child: _buildAnimatedBackdrop()),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 900;
                final crossAxisCount = isWide
                    ? 3
                    : (constraints.maxWidth > 600 ? 2 : 1);

                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 20,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildWelcomeHeader(theme, user),
                      const SizedBox(height: 24),
                      Expanded(
                        child: GridView.builder(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                mainAxisSpacing: 20,
                                crossAxisSpacing: 20,
                                childAspectRatio: isWide ? 1.4 : 1.2,
                              ),
                          itemCount: _actions.length,
                          itemBuilder: (context, index) =>
                              _buildActionCard(index),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeHeader(ThemeData theme, AppUser? user) {
    final textTheme = theme.textTheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.9, end: 1.0),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        return Opacity(
          opacity: ((value - 0.9) / 0.1).clamp(0.0, 1.0),
          child: Transform.scale(scale: value, child: child),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: _cardOverlay,
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 24,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Xin chào ${user?.name ?? user?.email ?? 'Admin'} 👋',
                    style: textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Quản trị toàn bộ hoạt động khu liên hợp dễ dàng hơn với bảng điều khiển trực quan.',
                    style: textTheme.bodyMedium?.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _highlightColor.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.dashboard_customize,
                color: Colors.white,
                size: 36,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard(int index) {
    final action = _actions[index];
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.9, end: 1.0),
      duration: Duration(milliseconds: 450 + index * 70),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        final opacity = ((value - 0.9) / 0.1).clamp(0.0, 1.0);
        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 40),
            child: Transform.scale(scale: value, child: child),
          ),
        );
      },
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: action.builder)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: _cardOverlay,
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          ),
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _accentColor.withValues(alpha: 0.85),
                ),
                child: Icon(
                  action.icon,
                  color: Colors.white.withValues(alpha: 0.92),
                  size: 22,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                action.title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Text(
                  action.description,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.bottomRight,
                child: FilledButton.tonal(
                  onPressed: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: action.builder)),
                  style: FilledButton.styleFrom(
                    backgroundColor: _accentColor.withValues(alpha: 0.32),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Mở quản lý'),
                      SizedBox(width: 6),
                      Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedBackdrop() {
    return IgnorePointer(
      ignoring: true,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Stack(
            children: [
              Positioned(
                top: -160 + _layerOne.value,
                left: -90,
                child: _buildBlob(280, const [
                  Color(0x3348CAE4),
                  Color(0x1148CAE4),
                ]),
              ),
              Positioned(
                right: -80,
                child: _buildBlob(250, const [
                  Color(0x3345DFB1),
                  Color(0x1145DFB1),
                ]),
              ),
              Positioned(
                top: 180 + (_layerTwo.value * 0.4),
                right: 140 + (_layerOne.value * 0.3),
                child: _buildBlob(160, const [
                  Color(0x3348CAE4),
                  Color(0x0D48CAE4),
                ]),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBlob(double size, List<Color> colors) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.last.withValues(alpha: 0.4),
            blurRadius: size * 0.25,
            spreadRadius: size * 0.02,
          ),
        ],
      ),
    );
  }

  static Widget _buildSports(BuildContext context) => const SportsPage();
  static Widget _buildFacilities(BuildContext context) =>
      const FacilitiesPage();
  static Widget _buildCourts(BuildContext context) => const CourtsAdminPage();
  static Widget _buildPriceProfiles(BuildContext context) =>
      const PriceProfilesPage();
  static Widget _buildUsers(BuildContext context) => const UsersPage();
  static Widget _buildBookings(BuildContext context) =>
      const BookingsAdminPage();
  static Widget _buildAuditLogs(BuildContext context) => const AuditLogsPage();
}

class _AdminAction {
  final IconData icon;
  final String title;
  final String description;
  final WidgetBuilder builder;

  const _AdminAction({
    required this.icon,
    required this.title,
    required this.description,
    required this.builder,
  });
}
