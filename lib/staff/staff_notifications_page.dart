import 'package:flutter/material.dart';
import 'package:neubrutalism_ui/neubrutalism_ui.dart';

import 'package:khu_lien_hop_tt/models/staff_notification.dart';
import 'package:khu_lien_hop_tt/services/api_service.dart';
import 'package:khu_lien_hop_tt/staff/staff_bookings_page.dart';
import 'package:khu_lien_hop_tt/widgets/neu_button.dart';
import 'package:khu_lien_hop_tt/widgets/neo_loading.dart';

enum _NotificationFilter { all, unread, read, important }

extension _NotificationFilterX on _NotificationFilter {
  String get label => switch (this) {
    _NotificationFilter.all => 'Tất cả',
    _NotificationFilter.unread => 'Chưa đọc',
    _NotificationFilter.read => 'Đã đọc',
    _NotificationFilter.important => 'Quan trọng',
  };

  IconData get icon => switch (this) {
    _NotificationFilter.all => Icons.notifications_active_outlined,
    _NotificationFilter.unread => Icons.markunread_outlined,
    _NotificationFilter.read => Icons.mark_email_read_outlined,
    _NotificationFilter.important => Icons.priority_high_rounded,
  };
}

class StaffNotificationsPage extends StatefulWidget {
  const StaffNotificationsPage({
    super.key,
    this.embedded = false,
    this.onUnreadCountChanged,
  });

  final bool embedded;
  final ValueChanged<int>? onUnreadCountChanged;

  @override
  State<StaffNotificationsPage> createState() => _StaffNotificationsPageState();
}

class _StaffNotificationsPageState extends State<StaffNotificationsPage>
    with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final Set<String> _marking = <String>{};
  final Set<String> _hiddenNotificationIds = <String>{};

  late final TabController _tabController;

  List<StaffNotification> _allNotifications = const [];
  bool _loading = true;
  String? _error;
  bool _markingAll = false;
  String _searchQuery = '';
  static const _autoCancelMarkerKey = '__autoCancellation';

  @override
  void initState() {
    super.initState();
    _tabController =
        TabController(length: _NotificationFilter.values.length, vsync: this)
          ..addListener(() {
            if (mounted && !_tabController.indexIsChanging) {
              setState(() {});
            }
          });
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _load({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final items = await _api.staffGetNotifications(limit: 100);
      if (!mounted) return;
      setState(() {
        _hiddenNotificationIds.clear();
        _allNotifications = items
            .map(_decorateNotification)
            .toList(growable: false);
        _loading = false;
        _error = null;
      });
      _notifyUnreadCount();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(e);
      });
    }
  }

  StaffNotification _decorateNotification(StaffNotification notification) {
    final metadata = notification.metadata;
    if (metadata[_autoCancelMarkerKey] == true) {
      return notification;
    }
    final eventType = metadata['eventType']?.toString().toLowerCase();
    final cancelledBy = metadata['cancelledBy']?.toString().toLowerCase();
    final isAutoCancel =
        eventType == 'customer_booking_cancelled' &&
        cancelledBy == 'system_auto_timeout';
    if (!isAutoCancel) return notification;

    const autoCancelReason =
        'Hệ thống đã huỷ vì khách không xác nhận trong thời gian quy định.';
    final originalMessage = notification.message.trim();
    final message = originalMessage.isEmpty
        ? autoCancelReason
        : '$autoCancelReason\n$originalMessage';
    final decoratedMetadata = Map<String, dynamic>.from(metadata)
      ..[_autoCancelMarkerKey] = true;
    return notification.copyWith(
      title: 'Hệ thống huỷ sân tự động',
      message: message,
      metadata: decoratedMetadata,
    );
  }

  bool _isAutoCancellation(StaffNotification notification) {
    if (notification.metadata[_autoCancelMarkerKey] == true) return true;
    final eventType = notification.metadata['eventType']
        ?.toString()
        .toLowerCase();
    final cancelledBy = notification.metadata['cancelledBy']
        ?.toString()
        .toLowerCase();
    return eventType == 'customer_booking_cancelled' &&
        cancelledBy == 'system_auto_timeout';
  }

  void _notifyUnreadCount() {
    final unread = _allNotifications.where((item) => !item.read).length;
    widget.onUnreadCountChanged?.call(unread);
  }

  String? _normalizeBookingStatus(dynamic value) {
    if (value == null) return null;
    final status = value.toString().trim().toLowerCase();
    const allowed = {'pending', 'confirmed', 'cancelled', 'completed', 'all'};
    return allowed.contains(status) ? status : null;
  }

  Future<bool> _handleNavigationIntent(StaffNotification notification) async {
    final metadata = notification.metadata;
    if (metadata.isEmpty) return false;

    final eventType = metadata['eventType']?.toString().trim().toLowerCase();
    final target = metadata['target']?.toString().trim().toLowerCase();
    final resource = metadata['resource']?.toString().trim().toLowerCase();
    final bookingId = metadata['bookingId']?.toString().trim();
    final channel = notification.channel?.toLowerCase();

    bool bookingEvent = bookingId != null && bookingId.isNotEmpty;
    bookingEvent = bookingEvent || (eventType?.contains('booking') ?? false);
    bookingEvent = bookingEvent || target == 'booking' || resource == 'booking';
    bookingEvent = bookingEvent || channel == 'booking';

    if (bookingEvent && bookingId != null && bookingId.isNotEmpty) {
      await _markAsRead(notification, silent: true);
      if (!mounted) return true;
      final status = _normalizeBookingStatus(metadata['status']);
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => StaffBookingsPage(
            embedded: false,
            initialStatus: status,
            focusBookingId: bookingId,
          ),
        ),
      );
      return true;
    }

    return false;
  }

  bool _isImportant(StaffNotification notification) {
    final priority = notification.priority?.toLowerCase();
    if (priority == 'critical' || priority == 'high') return true;
    final channel = notification.channel?.toLowerCase();
    if (channel == 'system' || channel == 'alert') return true;
    final metadataType = notification.metadata['type']
        ?.toString()
        .toLowerCase();
    if (metadataType == 'system' || metadataType == 'alert') return true;
    final isImportantFlag = notification.metadata['isImportant'];
    if (isImportantFlag is bool && isImportantFlag) return true;
    return false;
  }

  List<StaffNotification> _notificationsForFilter(_NotificationFilter filter) {
    Iterable<StaffNotification> source = _allNotifications.where(
      (item) => !_hiddenNotificationIds.contains(item.id),
    );

    switch (filter) {
      case _NotificationFilter.unread:
        source = source.where((item) => !item.read);
        break;
      case _NotificationFilter.read:
        source = source.where((item) => item.read);
        break;
      case _NotificationFilter.important:
        source = source.where(_isImportant);
        break;
      case _NotificationFilter.all:
        break;
    }

    if (_searchQuery.isEmpty) {
      return source.toList(growable: false);
    }

    final query = _searchQuery.toLowerCase();
    return source
        .where((item) {
          final title = item.title.toLowerCase();
          final message = item.message.toLowerCase();
          final channel = (item.channel ?? '').toLowerCase();
          final priority = (item.priority ?? '').toLowerCase();
          return title.contains(query) ||
              message.contains(query) ||
              channel.contains(query) ||
              priority.contains(query);
        })
        .toList(growable: false);
  }

  Future<void> _markAsRead(
    StaffNotification notification, {
    bool silent = false,
  }) async {
    if (notification.read || _marking.contains(notification.id)) return;
    setState(() => _marking.add(notification.id));
    try {
      await _api.staffMarkNotificationRead(notification.id);
      if (!mounted) return;
      setState(() {
        _marking.remove(notification.id);
        _allNotifications = _allNotifications
            .map(
              (item) => item.id == notification.id
                  ? item.copyWith(read: true, readAt: DateTime.now())
                  : item,
            )
            .toList(growable: false);
      });
      _notifyUnreadCount();
      if (!silent) {
        await _showSnack('Đã đánh dấu đã đọc');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _marking.remove(notification.id));
      _showSnack(_friendlyError(e), isError: true);
    }
  }

  Future<void> _markAllRead() async {
    if (_markingAll) return;
    final unreadExists = _allNotifications.any(
      (notification) => !notification.read,
    );
    if (!unreadExists) return;
    setState(() => _markingAll = true);
    try {
      await _api.staffMarkAllNotificationsRead();
      if (!mounted) return;
      setState(() {
        _markingAll = false;
        _allNotifications = _allNotifications
            .map(
              (item) => item.copyWith(
                read: true,
                readAt: item.readAt ?? DateTime.now(),
              ),
            )
            .toList(growable: false);
      });
      _notifyUnreadCount();
      await _showSnack('Đã đánh dấu tất cả thông báo');
    } catch (e) {
      if (!mounted) return;
      setState(() => _markingAll = false);
      _showSnack(_friendlyError(e), isError: true);
    }
  }

  Future<void> _openNotificationDetail(StaffNotification notification) async {
    if (await _handleNavigationIntent(notification)) {
      return;
    }

    if (!notification.read) {
      await _markAsRead(notification, silent: true);
    }

    final latest = _allNotifications.firstWhere(
      (item) => item.id == notification.id,
      orElse: () => notification,
    );

    final detailNotification = _decorateNotification(
      latest.copyWith(read: true, readAt: latest.readAt ?? DateTime.now()),
    );

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: _NotificationDetailBottomSheet(
          notification: detailNotification,
          isImportant: _isImportant(detailNotification),
          isAutoCancellation: _isAutoCancellation(detailNotification),
        ),
      ),
    );
  }

  Future<void> _hideNotification(StaffNotification notification) async {
    setState(() => _hiddenNotificationIds.add(notification.id));
    await _showSnack(
      'Đã ẩn thông báo khỏi danh sách. Kéo để tải lại nếu muốn.',
    );
  }

  Future<void> _showSnack(String message, {bool isError = false}) async {
    if (!mounted) return;
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? theme.colorScheme.error
            : theme.colorScheme.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    const prefix = 'Exception: ';
    return text.startsWith(prefix) ? text.substring(prefix.length) : text;
  }

  String _formatTimestamp(DateTime timestamp) {
    final local = timestamp.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    final now = DateTime.now();
    final difference = now.difference(local);
    if (difference.inMinutes < 1) return 'Vừa xong';
    if (difference.inHours < 1) {
      return '${difference.inMinutes} phút trước';
    }
    if (difference.inHours < 24) {
      return '${difference.inHours} giờ trước';
    }
    final datePart = '${two(local.day)}/${two(local.month)}/${local.year}';
    final timePart = '${two(local.hour)}:${two(local.minute)}';
    return '$timePart · $datePart';
  }

  IconData _channelIcon(String? channel) {
    switch (channel?.toLowerCase()) {
      case 'booking':
        return Icons.calendar_month_outlined;
      case 'maintenance':
        return Icons.build_outlined;
      case 'finance':
        return Icons.payments_outlined;
      case 'support':
        return Icons.support_agent_outlined;
      case 'system':
        return Icons.warning_amber_rounded;
      default:
        return Icons.notifications_none_outlined;
    }
  }

  Color _priorityColor(ColorScheme scheme, String? priority) {
    switch (priority?.toLowerCase()) {
      case 'critical':
        return scheme.error;
      case 'high':
        return scheme.tertiary;
      case 'medium':
        return scheme.secondary;
      default:
        return scheme.primary;
    }
  }

  String _priorityLabel(String? priority) {
    switch (priority?.toLowerCase()) {
      case 'critical':
        return 'Khẩn cấp';
      case 'high':
        return 'Quan trọng';
      case 'medium':
        return 'Trung bình';
      case 'low':
        return 'Thấp';
      default:
        return 'Thông thường';
    }
  }

  String _statusLabel(StaffNotification notification) {
    if (!notification.read) return 'Chưa đọc';
    return 'Đã đọc';
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final tabBar = _buildTabBar(context);
    final surfaceColor = Theme.of(context).colorScheme.surface;

    return PreferredSize(
      preferredSize: Size.fromHeight(
        kToolbarHeight + tabBar.preferredSize.height,
      ),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFB2DFDB), Color(0xFF80CBC4)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              SizedBox(
                height: kToolbarHeight,
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Text(
                        'Thông báo',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Tìm kiếm',
                      icon: const Icon(Icons.search),
                      onPressed: () {
                        FocusScope.of(context).requestFocus(_searchFocusNode);
                      },
                    ),
                    IconButton(
                      tooltip: 'Đánh dấu tất cả là đã đọc',
                      icon: _markingAll
                          ? const NeoLoadingDot(size: 18, fillColor: Colors.white)
                          : const Icon(Icons.done_all_rounded),
                      onPressed:
                          _markingAll ||
                              _allNotifications.every((item) => item.read)
                          ? null
                          : _markAllRead,
                    ),
                  ],
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 12,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: tabBar,
              ),
            ],
          ),
        ),
      ),
    );
  }

  TabBar _buildTabBar(BuildContext context) {
    return TabBar(
      controller: _tabController,
      isScrollable: true,
      // Keep vertical padding zero so the app bar height matches its constraints and avoids overflow.
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      labelPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      indicator: BoxDecoration(
        color: const Color(0xFF4CAF50),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black, width: 3),
        boxShadow: const [
          BoxShadow(color: Colors.black, offset: Offset(4, 4), blurRadius: 0),
        ],
      ),
      labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      unselectedLabelStyle: const TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
      labelColor: Colors.white,
      unselectedLabelColor: Colors.black,
      tabs: _NotificationFilter.values.map((filter) {
        final count = _notificationsForFilter(filter).length;
        final isSelected =
            _tabController.index == _NotificationFilter.values.indexOf(filter);
        return Tab(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: isSelected
                ? null
                : BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.black, width: 2),
                  ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(filter.icon, size: 16),
                const SizedBox(width: 8),
                Text('${filter.label} ($count)'),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        decoration: InputDecoration(
          hintText: 'Tìm kiếm thông báo...',
          hintStyle: const TextStyle(fontWeight: FontWeight.w500),
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Xóa từ khóa',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Colors.black, width: 2.4),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Colors.black, width: 2.4),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Colors.black, width: 3),
          ),
          filled: true,
          fillColor: Colors.white,
        ),
        textInputAction: TextInputAction.search,
        onChanged: (value) => setState(() => _searchQuery = value.trim()),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: NeoLoadingCard(
          label: 'Đang tải thông báo...',
          width: 260,
        ),
      );
    }
    if (_error != null) {
      final theme = Theme.of(context);
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: NeuContainer(
            borderRadius: BorderRadius.circular(24),
            color: theme.colorScheme.surface,
            borderColor: Colors.black,
            borderWidth: 3,
            shadowColor: Colors.black.withValues(alpha: 0.25),
            offset: const Offset(8, 8),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_rounded, size: 64),
                  const SizedBox(height: 12),
                  Text(
                    'Không thể tải thông báo',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  NeuButton(
                    onPressed: _load,
                    buttonHeight: 48,
                    buttonWidth: double.infinity,
                    borderRadius: BorderRadius.circular(16),
                    borderColor: Colors.black,
                    buttonColor: theme.colorScheme.primary,
                    shadowColor: Colors.black.withValues(alpha: 0.35),
                    child: const Text(
                      'Thử lại',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        _buildSearchBar(),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: _NotificationFilter.values
                .map(_buildTabContent)
                .toList(growable: false),
          ),
        ),
      ],
    );
  }

  Widget _buildTabContent(_NotificationFilter filter) {
    final notifications = _notificationsForFilter(filter);
    return RefreshIndicator(
      onRefresh: () => _load(showSpinner: false),
      child: notifications.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(left: 32, right: 32, bottom: 24),
              children: [
                SizedBox(height: MediaQuery.of(context).size.height * 0.15),
                _EmptyState(filter: filter),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: 24,
              ),
              itemCount: notifications.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final item = notifications[index];
                return TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.97, end: 1),
                  duration: Duration(milliseconds: 300 + (index * 20)),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) => Transform.scale(
                    scale: value,
                    alignment: Alignment.topCenter,
                    child: child,
                  ),
                  child: _buildSwipeableCard(item),
                );
              },
            ),
    );
  }

  Widget _buildSwipeableCard(StaffNotification notification) {
    final theme = Theme.of(context);
    final extraChips = <_StatusChip>[];
    if (_isAutoCancellation(notification)) {
      extraChips.add(
        _StatusChip(
          label: 'Huỷ tự động',
          color: theme.colorScheme.error,
          icon: Icons.alarm_off_rounded,
        ),
      );
    }

    return Dismissible(
      key: ValueKey(notification.id),
      background: _SwipeActionBackground(
        icon: Icons.done_all_rounded,
        label: notification.read ? 'Đã đọc' : 'Đánh dấu đã đọc',
        color: Colors.green.shade400,
        alignment: Alignment.centerLeft,
      ),
      secondaryBackground: _SwipeActionBackground(
        icon: Icons.delete_forever_rounded,
        label: 'Ẩn',
        color: Colors.redAccent,
        alignment: Alignment.centerRight,
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          if (!notification.read) {
            await _markAsRead(notification);
          }
          return false;
        }
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Ẩn thông báo?'),
            content: const Text(
              'Thông báo sẽ được ẩn khỏi danh sách hiện tại. Bạn có thể tải lại để xem lại nếu cần.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Hủy'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Ẩn'),
              ),
            ],
          ),
        );
        if (confirm == true) {
          await _hideNotification(notification);
        }
        return false;
      },
      child: _NotificationCard(
        notification: notification,
        isImportant: _isImportant(notification),
        timestamp: _formatTimestamp(notification.createdAt),
        marking: _marking.contains(notification.id),
        onTap: () => _openNotificationDetail(notification),
        onMarkRead: () => _markAsRead(notification),
        priorityLabel: _priorityLabel(notification.priority),
        priorityColor: _priorityColor(theme.colorScheme, notification.priority),
        channelIcon: _channelIcon(notification.channel),
        statusLabel: _statusLabel(notification),
        extraChips: extraChips,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return SafeArea(
        top: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(
                'Thông báo',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            _buildTabBar(context),
            Expanded(child: _buildBody()),
          ],
        ),
      );
    }

    return Scaffold(appBar: _buildAppBar(context), body: _buildBody());
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.isImportant,
    required this.timestamp,
    required this.marking,
    required this.onTap,
    required this.onMarkRead,
    required this.priorityLabel,
    required this.priorityColor,
    required this.channelIcon,
    required this.statusLabel,
    this.extraChips = const <_StatusChip>[],
  });

  final StaffNotification notification;
  final bool isImportant;
  final String timestamp;
  final bool marking;
  final VoidCallback onTap;
  final VoidCallback onMarkRead;
  final String priorityLabel;
  final Color priorityColor;
  final IconData channelIcon;
  final String statusLabel;
  final List<_StatusChip> extraChips;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardColor = notification.read
        ? const Color(0xFFF5F5F5)
        : const Color(0xFFFFF8DC);

    return NeuContainer(
      borderRadius: BorderRadius.circular(24),
      color: cardColor,
      borderColor: Colors.black,
      borderWidth: notification.read ? 2 : 3,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      offset: notification.read ? const Offset(4, 4) : const Offset(6, 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: priorityColor, width: 2),
                    ),
                    child: Icon(channelIcon, color: priorityColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(
                                notification.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (!notification.read)
                              Container(
                                width: 10,
                                height: 10,
                                margin: const EdgeInsets.only(left: 8),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            PopupMenuButton<String>(
                              tooltip: 'Tùy chọn',
                              onSelected: (value) {
                                if (value == 'read' && !notification.read) {
                                  onMarkRead();
                                } else if (value == 'detail') {
                                  onTap();
                                }
                              },
                              itemBuilder: (context) => [
                                if (!notification.read)
                                  const PopupMenuItem(
                                    value: 'read',
                                    child: Text('Đánh dấu đã đọc'),
                                  ),
                                const PopupMenuItem(
                                  value: 'detail',
                                  child: Text('Xem chi tiết'),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          notification.message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _StatusChip(
                    label: statusLabel,
                    color: notification.read
                        ? theme.colorScheme.outline
                        : theme.colorScheme.primary,
                  ),
                  if (!isImportant && priorityLabel != 'Thông thường')
                    _StatusChip(
                      label: priorityLabel,
                      color: priorityColor,
                      icon: Icons.flag_outlined,
                    ),
                  if (notification.channel != null &&
                      notification.channel!.isNotEmpty)
                    _StatusChip(
                      label: notification.channel!,
                      color: theme.colorScheme.secondary,
                      icon: Icons.layers_outlined,
                    ),
                  if (isImportant)
                    _StatusChip(
                      label: 'Quan trọng',
                      color: theme.colorScheme.error,
                      icon: Icons.priority_high_rounded,
                    ),
                  ...extraChips,
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    size: 16,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    timestamp,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  const Spacer(),
                  if (!notification.read)
                    SizedBox(
                      height: 36,
                      child: NeuButton(
                        onPressed: marking ? null : onMarkRead,
                        buttonHeight: 36,
                        buttonWidth: 160,
                        borderRadius: BorderRadius.circular(12),
                        borderColor: Colors.black,
                        buttonColor: theme.colorScheme.primaryContainer,
                        shadowColor: Colors.black.withValues(alpha: 0.3),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (marking)
                              const NeoLoadingDot(size: 16, fillColor: Colors.white)
                            else
                              const Icon(Icons.done_outlined, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              marking ? 'Đang xử lý...' : 'Đánh dấu đã đọc',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
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
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black, offset: Offset(2, 2), blurRadius: 0),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _SwipeActionBackground extends StatelessWidget {
  const _SwipeActionBackground({
    required this.icon,
    required this.label,
    required this.color,
    required this.alignment,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      color: color,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (alignment == Alignment.centerRight) ...[
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Icon(icon, color: Colors.white),
          if (alignment == Alignment.centerLeft) ...[
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filter});

  final _NotificationFilter filter;

  String get _title => switch (filter) {
    _NotificationFilter.all => 'Hiện chưa có thông báo nào.',
    _NotificationFilter.unread => 'Không còn thông báo chưa đọc.',
    _NotificationFilter.read => 'Chưa có thông báo đã đọc.',
    _NotificationFilter.important => 'Không có thông báo quan trọng.',
  };

  String get _subtitle => switch (filter) {
    _NotificationFilter.unread =>
      'Tuyệt vời! Bạn đã xem hết mọi thông báo mới.',
    _NotificationFilter.read =>
      'Thông báo sẽ xuất hiện tại đây sau khi bạn xem chi tiết.',
    _NotificationFilter.important =>
      'Các cảnh báo khẩn sẽ được hiển thị tại thẻ này.',
    _NotificationFilter.all => 'Kéo xuống để làm mới khi có thông báo mới.',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NeuContainer(
      borderRadius: BorderRadius.circular(24),
      color: theme.colorScheme.surface,
      borderColor: Colors.black,
      borderWidth: 3,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      offset: const Offset(8, 8),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(
              Icons.notifications_off_rounded,
              size: 72,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              _title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationDetailBottomSheet extends StatelessWidget {
  const _NotificationDetailBottomSheet({
    required this.notification,
    required this.isImportant,
    this.isAutoCancellation = false,
  });

  final StaffNotification notification;
  final bool isImportant;
  final bool isAutoCancellation;

  String _formatDate(DateTime dateTime) {
    String two(int value) => value.toString().padLeft(2, '0');
    final local = dateTime.toLocal();
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.5,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          children: [
            Container(
              width: 46,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    notification.title,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                if (isImportant)
                  Icon(
                    Icons.priority_high_rounded,
                    color: theme.colorScheme.error,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(notification.message, style: theme.textTheme.bodyLarge),
            if (isAutoCancellation) ...[
              const SizedBox(height: 12),
              _DetailRow(
                icon: Icons.alarm_off_rounded,
                label: 'Nguồn huỷ',
                value: 'Hệ thống tự động · Quá hạn xác nhận',
              ),
            ],
            const SizedBox(height: 16),
            _DetailRow(
              icon: Icons.schedule_rounded,
              label: 'Thời gian tạo',
              value: _formatDate(notification.createdAt),
            ),
            const SizedBox(height: 8),
            _DetailRow(
              icon: Icons.layers_outlined,
              label: 'Loại thông báo',
              value: notification.channel?.toUpperCase() ?? 'Không xác định',
            ),
            const SizedBox(height: 8),
            _DetailRow(
              icon: Icons.flag_outlined,
              label: 'Mức độ ưu tiên',
              value: notification.priority == null
                  ? 'Thông thường'
                  : notification.priority!,
            ),
            const SizedBox(height: 24),
            NeuButton(
              onPressed: () => Navigator.of(context).maybePop(),
              buttonHeight: 48,
              buttonWidth: double.infinity,
              borderRadius: BorderRadius.circular(16),
              borderColor: Colors.black,
              buttonColor: theme.colorScheme.secondaryContainer,
              shadowColor: Colors.black.withValues(alpha: 0.35),
              child: const Text(
                'Đóng',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelMedium),
              Text(value, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}
