import 'package:flutter/material.dart';

import '../services/api_service.dart';

class MaintenanceReminderPanel extends StatefulWidget {
  const MaintenanceReminderPanel({
    super.key,
    required this.api,
    required this.token,
    this.customerPhone,
    this.plateSearchQuery = '',
  });

  final ApiService api;
  final String token;
  final String? customerPhone;
  final String plateSearchQuery;

  @override
  State<MaintenanceReminderPanel> createState() => _MaintenanceReminderPanelState();
}

class _MaintenanceReminderPanelState extends State<MaintenanceReminderPanel> {
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> items = [];

  static String _normalizePlateKey(String s) =>
      s.replaceAll(RegExp(r'[\s\-.]'), '').toLowerCase();

  bool _matchesPlate(String bienSo) {
    final q = _normalizePlateKey(widget.plateSearchQuery);
    if (q.isEmpty) return true;
    return _normalizePlateKey(bienSo).contains(q);
  }

  List<Map<String, dynamic>> get _filteredItems =>
      items.where((r) => _matchesPlate((r['bien_so'] ?? '').toString())).toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final list = await widget.api.fetchMaintenanceReminders(
        token: widget.token,
        phone: widget.customerPhone,
      );
      if (mounted) setState(() => items = list);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Thử lại')),
            ],
          ),
        ),
      );
    }
    if (items.isEmpty) {
      return const Center(child: Text('Chưa có xe đủ điều kiện nhắc bảo dưỡng (Fadil/VF3: 6 tháng; Lux/VF5–9…: 12 tháng).'));
    }
    final shown = _filteredItems;
    if (shown.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Không có xe nhắc bảo dưỡng khớp «${widget.plateSearchQuery.trim()}».',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(8),
        itemCount: shown.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (ctx, i) {
          final r = shown[i];
          final overdue = r['overdue'] == true;
          final color = overdue ? Colors.red.shade700 : Colors.orange.shade800;
          return ListTile(
            leading: Icon(overdue ? Icons.notification_important : Icons.event, color: color),
            title: Text('${r['bien_so'] ?? ''} — ${r['vehicle_model'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              'Lần cuối: ${r['last_service_at']?.toString().substring(0, 10) ?? '—'}\n'
              'Nhắc: ${r['next_reminder_display'] ?? '—'} (${r['interval_months']} tháng)\n'
              '${r['customer_name'] ?? ''} ${r['customer_phone'] ?? ''}',
            ),
            isThreeLine: true,
            trailing: Chip(
              label: Text(r['status_label']?.toString() ?? '', style: const TextStyle(fontSize: 11)),
              backgroundColor: overdue ? Colors.red.shade50 : Colors.amber.shade50,
            ),
          );
        },
      ),
    );
  }
}
