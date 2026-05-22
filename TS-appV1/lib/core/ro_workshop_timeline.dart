import 'dart:convert';

import 'package:intl/intl.dart';

import 'ro_display.dart';

/// Một mốc trong diễn biến xử lý xe tại xưởng (dùng giải trình / xuất báo cáo).
class WorkshopTimelineEvent {
  final DateTime at;
  final String line;
  final String kind;

  const WorkshopTimelineEvent({
    required this.at,
    required this.line,
    this.kind = 'event',
  });
}

final _dateFmt = DateFormat('dd/MM/yyyy');
final _dateTimeFmt = DateFormat('dd/MM/yyyy HH:mm');

String _formatDay(DateTime d) => _dateFmt.format(d);

String _formatDayTime(DateTime d) => _dateTimeFmt.format(d);

DateTime? _parseTs(dynamic raw) {
  if (raw == null) return null;
  return DateTime.tryParse(raw.toString());
}

String _pauseReasonVi(String? code) {
  switch (code?.toUpperCase()) {
    case 'CHO_PHU_TUNG':
      return 'chờ phụ tùng';
    case 'CHO_KH':
      return 'chờ khách hàng';
    case 'CHO_BAO_HIEM':
      return 'chờ bảo hiểm / đối soát bảo hiểm';
    default:
      return 'tạm dừng khác';
  }
}

List<dynamic> _asList(dynamic raw) {
  if (raw == null) return [];
  if (raw is List) return raw;
  if (raw is String) {
    try {
      final d = jsonDecode(raw);
      if (d is List) return d;
    } catch (_) {}
  }
  return [];
}

/// Gom audit, mốc thời gian, tạm dừng, chat… thành dòng thời gian theo thứ tự.
List<WorkshopTimelineEvent> buildWorkshopTimeline(Map<String, dynamic> ro) {
  final events = <WorkshopTimelineEvent>[];
  final seenAt = <String>{};

  void add(DateTime? at, String line, {String kind = 'event'}) {
    if (at == null || line.trim().isEmpty) return;
    final key = '${at.millisecondsSinceEpoch}|$kind|${line.hashCode}';
    if (seenAt.contains(key)) return;
    seenAt.add(key);
    events.add(WorkshopTimelineEvent(at: at, line: line.trim(), kind: kind));
  }

  final bienSo = ro['bien_so']?.toString() ?? '';
  final customer = ro['customer_name']?.toString() ?? '';
  final noteKh = ro['customer_note']?.toString().trim() ?? '';
  final position = ro['position']?.toString().trim() ?? '';
  final cvdv = ro['cvdv_username']?.toString() ?? '';
  final ktv = ro['ktv_username']?.toString() ?? '';

  final timeIn = _parseTs(ro['time_in'] ?? ro['created_at']);
  if (timeIn != null) {
    final parts = <String>[
      'Khách hàng đưa xe vào xưởng',
      if (bienSo.isNotEmpty) ' — biển số $bienSo',
      if (customer.isNotEmpty) ' ($customer)',
      '.',
    ];
    if (noteKh.isNotEmpty) parts.add(' Tình trạng / ghi chú tiếp nhận: $noteKh.');
    if (position.isNotEmpty) parts.add(' Vị trí đỗ: $position.');
    add(timeIn, 'Ngày ${_formatDay(timeIn)} ${parts.join()}', kind: 'intake');
  }

  final urgent = ro['urgent_note']?.toString().trim();
  if (urgent != null && urgent.isNotEmpty) {
    add(_parseTs(ro['updated_at']) ?? timeIn, 'Ghi chú khẩn: $urgent', kind: 'note');
  }

  final milestones = <(String field, String label)>[
    ('time_receive', 'CVDV tiếp nhận hồ sơ xe'),
    ('time_quote_created', 'Lập báo giá'),
    ('time_quote_sent', 'Gửi báo giá (khách / bảo hiểm)'),
    ('time_quote_approved', 'Khách hoặc bảo hiểm duyệt báo giá'),
    ('time_assign', 'Quản đốc phân công KTV${ktv.isNotEmpty ? ' ($ktv)' : ''}'),
    ('time_start', 'KTV bắt đầu sửa chữa${ktv.isNotEmpty ? ' ($ktv)' : ''}'),
    ('fault_diagnosis_at', 'KTV xác nhận đã xác định nguyên nhân lỗi'),
    ('time_done', 'Hoàn thành sửa chữa — chờ nghiệm thu / chốt'),
    ('time_ready_for_settlement', 'Sẵn sàng quyết toán — chuyển kế toán'),
    ('time_paid', 'Đã thanh toán'),
    ('time_out', 'Xe ra khỏi xưởng'),
  ];

  for (final m in milestones) {
    final t = _parseTs(ro[m.$1]);
    if (t != null) {
      add(t, 'Ngày ${_formatDayTime(t)} ${m.$2}.', kind: 'milestone');
    }
  }

  for (final e in _asList(ro['audit_history'])) {
    if (e is! Map) continue;
    final m = Map<String, dynamic>.from(e);
    final at = _parseTs(m['at'] ?? m['created_at']);
    if (at == null) continue;

    final action = m['action']?.toString() ?? 'status_change';
    final note = m['note']?.toString().trim() ?? '';
    final user = m['user_id']?.toString() ?? m['user']?.toString() ?? '';
    final userSuffix = user.isNotEmpty ? ' (người thực hiện: $user)' : '';

    if (action == 'create_ro') {
      add(
        at,
        'Ngày ${_formatDayTime(at)} Tạo phiếu sửa chữa trên hệ thống${note.isNotEmpty ? '. $note' : '.'}$userSuffix',
        kind: 'audit',
      );
      continue;
    }

    final from = normalizeRepairOrderStatus(m['from_status']?.toString() ?? m['from']?.toString());
    final to = normalizeRepairOrderStatus(m['to_status']?.toString() ?? m['to']?.toString() ?? m['status']?.toString());
    final fromL = from.isEmpty ? '—' : roStatusTokenLabelVi(from);
    final toL = to.isEmpty ? '—' : roStatusTokenLabelVi(to);

  String line;
    if (from == to && note.isNotEmpty) {
      line = 'Ngày ${_formatDayTime(at)} Cập nhật: $note$userSuffix';
    } else {
      line = 'Ngày ${_formatDayTime(at)} Chuyển trạng thái: $fromL → $toL';
      if (note.isNotEmpty) line += '. $note';
      line += userSuffix;
    }
    add(at, line, kind: 'audit');
  }

  for (final p in _asList(ro['pauses'])) {
    if (p is! Map) continue;
    final seg = Map<String, dynamic>.from(p);
    final pauseAt = _parseTs(seg['pause_at']);
    final resumeAt = _parseTs(seg['resume_at']);
    final reason = _pauseReasonVi(seg['reason']?.toString());

    if (pauseAt != null) {
      add(
        pauseAt,
        'Ngày ${_formatDayTime(pauseAt)} Tạm dừng sửa chữa — $reason.',
        kind: 'pause',
      );
    }
    if (resumeAt != null) {
      add(
        resumeAt,
        'Ngày ${_formatDayTime(resumeAt)} Tiếp tục sửa chữa sau khi $reason.',
        kind: 'pause',
      );
    }
  }

  final chatRaw = _asList(ro['chat_logs']);
  final chatSorted = <Map<String, dynamic>>[];
  for (final c in chatRaw) {
    if (c is! Map) continue;
    chatSorted.add(Map<String, dynamic>.from(c));
  }
  chatSorted.sort((a, b) {
    final ta = _parseTs(a['time'] ?? a['at']) ?? DateTime.fromMillisecondsSinceEpoch(0);
    final tb = _parseTs(b['time'] ?? b['at']) ?? DateTime.fromMillisecondsSinceEpoch(0);
    return ta.compareTo(tb);
  });
  for (final m in chatSorted.length > 25 ? chatSorted.sublist(chatSorted.length - 25) : chatSorted) {
    final at = _parseTs(m['time'] ?? m['at']);
    final msg = m['msg']?.toString().trim() ?? m['message']?.toString().trim() ?? '';
    if (at == null || msg.isEmpty || msg.length < 4) continue;
    final role = m['role']?.toString() ?? m['sender']?.toString() ?? '';
    final who = role.isNotEmpty ? '$role: ' : '';
    if (msg.length > 280) continue;
    add(at, 'Ngày ${_formatDayTime(at)} Trao đổi nội bộ / với KH — $who$msg', kind: 'chat');
  }

  final images = _asList(ro['images']);
  if (images.isNotEmpty && timeIn != null) {
    add(
      timeIn,
      'Có ${images.length} hình ảnh đính kèm trên phiếu (tiếp nhận / quá trình xử lý).',
      kind: 'media',
    );
  }

  final activity = ro['vehicle_activity']?.toString().trim() ?? ro['vehicle_activity_note']?.toString().trim() ?? '';
  if (activity.isNotEmpty) {
    final actAt = _parseTs(ro['updated_at']) ?? timeIn;
    final label = vehicleActivityLineForKh(activity, ro['status']?.toString() ?? '') ?? activity;
    add(actAt, 'Cập nhật hoạt động xe: $label.', kind: 'activity');
  }

  if (cvdv.isNotEmpty && timeIn != null) {
    add(
      timeIn,
      'CVDV phụ trách: $cvdv.',
      kind: 'staff',
    );
  }

  events.sort((a, b) => a.at.compareTo(b.at));
  return events;
}

/// Nội dung file giải trình (bullet •).
String formatWorkshopTimelineReport({
  required Map<String, dynamic> ro,
  required List<WorkshopTimelineEvent> events,
  String? workshopName,
}) {
  final buf = StringBuffer();
  final roCode = ro['ro_code']?.toString() ?? '';
  final bienSo = ro['bien_so']?.toString() ?? '';
  final customer = ro['customer_name']?.toString() ?? '';
  final phone = ro['customer_phone']?.toString() ?? '';
  final status = roStatusTokenLabelVi(normalizeRepairOrderStatus(ro['status']?.toString()));

  buf.writeln('BÁO CÁO DIỄN BIẾN XỬ LÝ TẠI XƯỞNG');
  if (workshopName != null && workshopName.isNotEmpty) {
    buf.writeln('Xưởng: $workshopName');
  }
  buf.writeln('Ngày xuất: ${_formatDayTime(DateTime.now())}');
  buf.writeln('');
  buf.writeln('Biển số: $bienSo');
  buf.writeln('Mã RO: $roCode');
  buf.writeln('Khách hàng: $customer${phone.isNotEmpty ? ' — $phone' : ''}');
  buf.writeln('Trạng thái hiện tại: $status');
  final noteKh = ro['customer_note']?.toString().trim();
  if (noteKh != null && noteKh.isNotEmpty) {
    buf.writeln('Ghi chú tiếp nhận: $noteKh');
  }
  buf.writeln('');
  buf.writeln('— DIỄN BIẾN THEO THỜI GIAN —');
  buf.writeln('');

  if (events.isEmpty) {
    buf.writeln('(Chưa có mốc thời gian ghi nhận trên hệ thống.)');
  } else {
    for (final e in events) {
      buf.writeln('• ${e.line}');
    }
  }

  buf.writeln('');
  buf.writeln('— HẾT —');
  return buf.toString();
}
