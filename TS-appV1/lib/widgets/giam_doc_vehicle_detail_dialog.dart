import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../core/cross_platform_export_helpers.dart';
import '../core/ro_display.dart';
import '../core/ro_workshop_timeline.dart';
import '../models/auth_models.dart';
import '../services/api_service.dart';
import 'vm_file_image.dart';

/// Chi tiết xe + timeline đầy đủ + xuất báo cáo giải trình (màn Giám đốc).
Future<void> showGiamDocVehicleDetailDialog({
  required BuildContext context,
  required ApiService api,
  required String token,
  required WorkOrderItem summary,
  String? workshopName,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _GiamDocVehicleDetailDialog(
      api: api,
      token: token,
      summary: summary,
      workshopName: workshopName,
    ),
  );
}

class _GiamDocVehicleDetailDialog extends StatefulWidget {
  final ApiService api;
  final String token;
  final WorkOrderItem summary;
  final String? workshopName;

  const _GiamDocVehicleDetailDialog({
    required this.api,
    required this.token,
    required this.summary,
    this.workshopName,
  });

  @override
  State<_GiamDocVehicleDetailDialog> createState() => _GiamDocVehicleDetailDialogState();
}

class _GiamDocVehicleDetailDialogState extends State<_GiamDocVehicleDetailDialog> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _roJson;
  List<WorkshopTimelineEvent> _events = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await widget.api.fetchRepairOrderJson(widget.token, widget.summary.id);
      final events = buildWorkshopTimeline(raw);
      if (!mounted) return;
      setState(() {
        _roJson = raw;
        _events = events;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _exportTxt() async {
    if (_roJson == null) return;
    final body = formatWorkshopTimelineReport(
      ro: _roJson!,
      events: _events,
      workshopName: widget.workshopName,
    );
    final safePlate = widget.summary.bienSo.replaceAll(RegExp(r'[^\w\-]'), '_');
    final defaultName =
        'giai_trinh_${safePlate}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.txt';
    final result = await saveTxtExport(
      content: body,
      fileName: defaultName,
      dialogTitle: 'Báo cáo diễn biến — ${widget.summary.bienSo}',
    );
    if (!mounted) return;
    showCrossPlatformSaveSnackBar(context, result, defaultName, successExtra: 'Báo cáo giải trình');
  }

  String get _exportButtonLabel => '${exportActionLabel(web: 'Tải báo cáo', mobile: 'Chia sẻ báo cáo', desktop: 'Xuất báo cáo')} (.txt)';

  Future<void> _copyToClipboard() async {
    if (_roJson == null) return;
    final body = formatWorkshopTimelineReport(
      ro: _roJson!,
      events: _events,
      workshopName: widget.workshopName,
    );
    await Clipboard.setData(ClipboardData(text: body));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã sao chép nội dung báo cáo.'), backgroundColor: Colors.green),
      );
    }
  }

  void _showImages() {
    final images = _roJson?['images'];
  List<dynamic> list = [];
    if (images is List) {
      list = images;
    } else if (images is String) {
      try {
        final d = jsonDecode(images);
        if (d is List) list = d;
      } catch (_) {}
    }
    if (list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa có ảnh trên phiếu.'), backgroundColor: Colors.orange),
      );
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Ảnh xe — ${widget.summary.bienSo}'),
        content: SizedBox(
          width: 560,
          height: 420,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: list.length,
            itemBuilder: (_, i) {
              final s = list[i]?.toString() ?? '';
              return ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: InkWell(onTap: () => _showFullImage(ctx, s), child: _buildSafeImage(s)),
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng'))],
      ),
    );
  }

  void _showFullImage(BuildContext ctx, String imageStr) {
    showDialog<void>(
      context: ctx,
      builder: (c) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(child: _buildSafeImage(imageStr)),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 32),
                onPressed: () => Navigator.pop(c),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSafeImage(String imageStr) {
    try {
      if (imageStr.startsWith('http://') || imageStr.startsWith('https://')) {
        return Image.network(imageStr, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image));
      }
      if (imageStr.startsWith('data:image')) {
        final base64Str = imageStr.split(',').last;
        return Image.memory(base64Decode(base64Str), fit: BoxFit.cover);
      }
      if (!kIsWeb && (imageStr.startsWith('file://') || imageStr.startsWith('/'))) {
        return buildVmFileImage(imageStr.replaceAll('file://', ''));
      }
    } catch (_) {}
    return const Icon(Icons.broken_image, color: Colors.grey);
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.summary;
    final wide = MediaQuery.sizeOf(context).width > 900;

    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Text(
              'Chi tiết — ${o.bienSo} · RO ${o.roCode}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(tooltip: 'Làm mới', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      content: SizedBox(
        width: wide ? 920 : 640,
        height: wide ? 620 : 520,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _load, child: const Text('Thử lại')),
                      ],
                    ),
                  )
                : _buildBody(o),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Đóng')),
        if (!_loading && _roJson != null) ...[
          OutlinedButton.icon(
            onPressed: _copyToClipboard,
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Sao chép'),
          ),
          OutlinedButton.icon(
            onPressed: _showImages,
            icon: const Icon(Icons.photo_library, size: 18),
            label: const Text('Ảnh xe'),
          ),
          FilledButton.icon(
            onPressed: _exportTxt,
            icon: Icon(kIsWeb ? Icons.download : Icons.ios_share, size: 18),
            label: Text(_exportButtonLabel),
          ),
        ],
      ],
    );
  }

  Widget _buildBody(WorkOrderItem o) {
    final status = roStatusTokenLabelVi(o.status);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _infoCard(o, status),
              const SizedBox(height: 12),
              const Text(
                'Diễn biến tại xưởng (dùng giải trình)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A)),
              ),
              const SizedBox(height: 8),
              Expanded(child: _timelineList()),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(child: _jobsPartsPanel(o)),
      ],
    );
  }

  Widget _infoCard(WorkOrderItem o, String status) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blueGrey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Khách: ${o.customerName} · ${o.customerPhone}', style: const TextStyle(fontWeight: FontWeight.w600)),
          Text('CVDV: ${o.cvdvUsername.isEmpty ? '—' : o.cvdvUsername} · KTV: ${o.ktvUsername.isEmpty ? '—' : o.ktvUsername}'),
          Text('Trạng thái: $status'),
          if (o.customerNote.isNotEmpty) Text('Ghi chú KH: ${o.customerNote}', style: const TextStyle(fontSize: 13)),
          Text('Số mốc thời gian: ${_events.length}', style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade700)),
        ],
      ),
    );
  }

  Widget _timelineList() {
    if (_events.isEmpty) {
      return const Center(child: Text('Chưa có diễn biến ghi nhận.', style: TextStyle(color: Colors.grey)));
    }
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _events.length,
        separatorBuilder: (_, __) => const Divider(height: 16),
        itemBuilder: (_, i) {
          final e = _events[i];
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('•', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.teal.shade800)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(e.line, style: const TextStyle(fontSize: 13.5, height: 1.45)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _jobsPartsPanel(WorkOrderItem o) {
    List<dynamic> jobs = [];
    List<dynamic> parts = [];
    try {
      if (o.jobs != null) jobs = o.jobs is String ? jsonDecode(o.jobs) : List.from(o.jobs);
      if (o.parts != null) parts = o.parts is String ? jsonDecode(o.parts) : List.from(o.parts);
    } catch (_) {}

    if (_roJson != null) {
      try {
        final j = _roJson!['jobs'];
        final p = _roJson!['parts'];
        if (j != null) jobs = j is String ? jsonDecode(j) : List.from(j as List);
        if (p != null) parts = p is String ? jsonDecode(p) : List.from(p as List);
      } catch (_) {}
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Công việc & phụ tùng', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(10),
            ),
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                const Text('Công việc', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.blue)),
                if (jobs.isEmpty) const Text(' (Chưa có)', style: TextStyle(color: Colors.grey, fontSize: 12)),
                ...jobs.map((j) {
                  if (j is! Map) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(left: 8, top: 4),
                    child: Text('· ${j['name'] ?? '—'}', style: const TextStyle(fontSize: 13)),
                  );
                }),
                const SizedBox(height: 12),
                const Text('Phụ tùng', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.orange)),
                if (parts.isEmpty) const Text(' (Chưa có)', style: TextStyle(color: Colors.grey, fontSize: 12)),
                ...parts.map((p) {
                  if (p is! Map) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(left: 8, top: 4),
                    child: Text('· ${p['name'] ?? '—'} × ${p['qty'] ?? 1}', style: const TextStyle(fontSize: 13)),
                  );
                }),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
