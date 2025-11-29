import 'package:flutter/material.dart';
import '../models/facility.dart';
import '../models/court.dart';
import '../services/api_service.dart';

class CourtsPage extends StatefulWidget {
  final Facility facility;
  const CourtsPage({super.key, required this.facility});

  @override
  State<CourtsPage> createState() => _CourtsPageState();
}

class _CourtsPageState extends State<CourtsPage> {
  final _api = ApiService();
  late Future<List<Court>> _future;

  Future<List<Court>> _load() => _api.getCourtsByFacility(widget.facility.id);

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Court>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Lỗi: ${snapshot.error}')));
          });
          return const Center(child: Text('Có lỗi xảy ra'));
        }
        final items = snapshot.data ?? const <Court>[];
        if (items.isEmpty) return const Center(child: Text('Chưa có dữ liệu'));
        return RefreshIndicator(
          onRefresh: () async => setState(() => _future = _load()),
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final c = items[i];
              return ListTile(
                title: Text(c.name),
                subtitle: Text(c.code ?? ''),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    Navigator.of(context).pushNamed('/booking', arguments: c),
              );
            },
          ),
        );
      },
    );
  }
}
