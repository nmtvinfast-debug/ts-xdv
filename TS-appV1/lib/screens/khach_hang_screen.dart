import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/cross_platform_export_helpers.dart';
import '../core/workshop_features.dart';
import '../core/payment_info.dart';
import '../core/responsive_layout.dart';
import '../core/ro_display.dart';
import '../models/auth_models.dart';
import '../services/api_service.dart';
import '../widgets/kh_ad_banner.dart';
import '../widgets/kh_admob_banner.dart';
import '../widgets/maintenance_reminder_panel.dart';
import 'login_screen.dart';

class KhachHangScreen extends StatefulWidget {
  const KhachHangScreen({super.key, required this.login});
  final LoginResult login;

  @override
  State<KhachHangScreen> createState() => _KhachHangScreenState();
}

class _KhachHangScreenState extends State<KhachHangScreen> {
  late final ApiService api;
  List<WorkOrderItem> _ordersInWorkshop = [];
  List<WorkOrderItem> _ordersArchive = [];
  int _khOrderTab = 0;
  List<WorkOrderItem> pendingRequests = [];
  bool loading = false;
  bool _fetching = false;
  String? _loadError;
  Timer? _autoRefresh;
  List<Map<String, dynamic>> _notifications = [];
  int _unreadNotify = 0;
  final TextEditingController _plateSearchCtrl = TextEditingController();

  /// SĐT CSKH / tổng đài (cấu hình xưởng hoặc user CSKH trên server).
  String _cskhDial = '19001001';
  final Map<String, String> _staffPhoneByUsernameLower = {};
  WorkshopFeatures? _workshopFeatures;

  /// Lịch từ app KH — CSKH duyệt trước khi vào «Chờ tiếp nhận».
  static const String _bookingPendingCskh = 'Chờ CSKH duyệt';
  static const String _bookingRejected = 'CSKH từ chối hẹn';

  static String _digitsOnly(String s) => s.replaceAll(RegExp(r'\D'), '');

  /// Chuẩn hóa biển số để so khớp (bỏ khoảng trắng, gạch).
  static String _normalizePlateKey(String s) =>
      s.replaceAll(RegExp(r'[\s\-.]'), '').toLowerCase();

  static bool _plateMatches(String bienSo, String query) {
    final q = _normalizePlateKey(query);
    if (q.isEmpty) return true;
    return _normalizePlateKey(bienSo).contains(q);
  }

  /// Cùng biển: thêm mọi RO trên bảng nếu KH đã liên kết ít nhất một RO với biển đó (phiếu mới thường chưa có `linked_customer`).
  static List<WorkOrderItem> _expandOrdersOnLinkedPlates(
    List<WorkOrderItem> allBoard,
    List<WorkOrderItem> strictlyMine,
  ) {
    final plates = strictlyMine.map((o) => o.bienSo.trim().toUpperCase()).where((p) => p.isNotEmpty).toSet();
    if (plates.isEmpty) return strictlyMine;
    final byId = <String, WorkOrderItem>{};
    for (final o in strictlyMine) {
      byId[o.id] = o;
    }
    for (final o in allBoard) {
      final p = o.bienSo.trim().toUpperCase();
      if (!plates.contains(p)) continue;
      byId[o.id] = o;
    }
    return byId.values.toList();
  }

  /// Liên kết theo `linkedCustomer` hoặc trùng SĐT đăng nhập (tài khoản KH thường là số điện thoại).
  bool _orderBelongsToMe(WorkOrderItem o) {
    final u = widget.login.userName.toLowerCase().trim();
    if (u.isEmpty) return false;
    if (o.linkedCustomer.toLowerCase().trim() == u) return true;
    final loginDigits = _digitsOnly(widget.login.userName);
    final phoneDigits = _digitsOnly(o.customerPhone);
    if (loginDigits.length >= 9 && phoneDigits.isNotEmpty && phoneDigits == loginDigits) return true;
    return false;
  }

  DateTime? _bookingDateTimeFromString(String timeStr) {
    final s = timeStr.trim();
    if (s.isEmpty) return null;
    try {
      return DateFormat('dd/MM/yyyy HH:mm').parseStrict(s);
    } catch (_) {}
    try {
      return DateFormat('dd/MM/yyyy H:mm').parseLoose(s);
    } catch (_) {}
    try {
      return DateTime.parse(s);
    } catch (_) {}
    return null;
  }

  bool _sameCalendarDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  int _countBookingsOnDay(List<BookingItem> list, DateTime day) {
    var n = 0;
    for (final b in list) {
      if (b.status == _bookingRejected) continue;
      final t = _bookingDateTimeFromString(b.time);
      if (t != null && _sameCalendarDay(t, day)) n++;
    }
    return n;
  }

  bool _vehicleStillInWorkshop(WorkOrderItem o) {
    const out = {'DA_RA_CONG', 'XE_RA_XUONG', 'HUY'};
    return !out.contains(normalizeRepairOrderStatus(o.status));
  }

  int _countCurrentWorkshop(List<WorkOrderItem> board) => board.where(_vehicleStillInWorkshop).length;

  String _guestPhonePrefill() {
    final d = _digitsOnly(widget.login.userName);
    if (d.length >= 9) return d;
    return '';
  }

  /// Xe đã ra / kết thúc luồng trong xưởng → KH gọi CSKH.
  static bool _vehicleOutsideWorkshopForDial(String status) {
    const outside = {
      'DA_RA_CONG',
      'DA_RA_CONG_THIEU_PT',
      'XE_RA_XUONG',
      'KH_TU_CHOI',
      'HUY',
      'HUY_CHO_QUYET_TOAN',
      'KT_DUYET_RA_CONG',
    };
    return outside.contains(normalizeRepairOrderStatus(status));
  }

  static String? _phoneFromWorkshopMap(Map<String, dynamic> w) {
    const keys = ['cskh_phone', 'cskh_hotline', 'hotline_cskh', 'hotline', 'phone_cskh', 'dien_thoai_cskh', 'csdk_phone'];
    for (final k in keys) {
      final v = w[k];
      if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
    }
    return null;
  }

  Future<void> _callWorkshopSmart(WorkOrderItem order) async {
    final outside = _vehicleOutsideWorkshopForDial(order.status);
    String raw;
    if (outside) {
      raw = _cskhDial;
    } else {
      final fromRo = order.cvdvPhone?.trim();
      final un = order.cvdvUsername.trim().toLowerCase();
      if (fromRo != null && fromRo.isNotEmpty) {
        raw = fromRo;
      } else if (un.isNotEmpty) {
        raw = _staffPhoneByUsernameLower[un] ?? _cskhDial;
      } else {
        raw = _cskhDial;
      }
    }
    raw = raw.trim();
    final digits = _digitsOnly(raw);
    if (digits.length < 8) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chưa có số điện thoại hợp lệ. Vui lòng liên hệ CSKH hoặc tổng đài.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    await _makePhoneCall(digits);
  }

  @override
  void initState() {
    super.initState();
    api = ApiService(baseUrl: widget.login.baseUrl);
    _loadData();
    _autoRefresh = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && !_fetching) _loadData();
    });
  }

  @override
  void dispose() {
    _autoRefresh?.cancel();
    _plateSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (_fetching) return;
    _fetching = true;
    setState(() {
      loading = true;
      _loadError = null;
    });
    try {
      final all = await api.fetchBoard(widget.login.token);
      final un = widget.login.userName.toLowerCase().trim();

      var nextCskh = _cskhDial;
      final phoneMap = Map<String, String>.from(_staffPhoneByUsernameLower);
      try {
        final users = await api.fetchUsers(widget.login.token);
        for (final u in users) {
          final p = u.phone?.trim();
          if (p == null || p.isEmpty) continue;
          phoneMap[u.username.toLowerCase()] = p;
          if (u.role.toUpperCase().contains('CSKH') && (nextCskh == '19001001' || nextCskh.isEmpty)) {
            nextCskh = p;
          }
        }
      } catch (_) {}
      WorkshopFeatures? features;
      try {
        final w = await api.fetchWorkshopSettings(widget.login.token);
        features = WorkshopFeatures.fromSettingsResponse(w);
        final p = _phoneFromWorkshopMap(w);
        if (p != null && p.isNotEmpty) nextCskh = p;
      } catch (_) {}

      List<Map<String, dynamic>> notifs = [];
      var unread = 0;
      try {
        notifs = await api.fetchNotifications(widget.login.token);
        unread = notifs.where((n) => n['read_at'] == null).length;
        notifs.sort((a, b) {
          final ta = DateTime.tryParse((a['created_at'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
          final tb = DateTime.tryParse((b['created_at'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
          return tb.compareTo(ta);
        });
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        final strict = all.where(_orderBelongsToMe).toList();
        final expanded = _KhachHangScreenState._expandOrdersOnLinkedPlates(all, strict);
        int byTimeIn(WorkOrderItem a, WorkOrderItem b) {
          final ta = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final tb = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return tb.compareTo(ta);
        }
        final inW = expanded.where((o) => !repairOrderStatusKhArchiveTab(o.status)).toList()..sort(byTimeIn);
        final arch = expanded.where((o) => repairOrderStatusKhArchiveTab(o.status)).toList()..sort(byTimeIn);
        _ordersInWorkshop = inW;
        _ordersArchive = arch;
        pendingRequests = all.where((o) => o.linkRequestedBy.toLowerCase() == un).toList();
        _notifications = notifs;
        _unreadNotify = unread;
        _cskhDial = nextCskh.isNotEmpty ? nextCskh : '19001001';
        _staffPhoneByUsernameLower
          ..clear()
          ..addAll(phoneMap);
        if (features != null) _workshopFeatures = features;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = e.toString();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không tải được dữ liệu: $e'), backgroundColor: Colors.red),
        );
      }
      debugPrint('KhachHang _loadData: $e');
    } finally {
      if (mounted) setState(() => loading = false);
      _fetching = false;
    }
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    if (phoneNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chưa có số điện thoại để gọi.')));
      return;
    }
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thiết bị không hỗ trợ gọi điện.')));
    }
  }

  void _openChatDialog(WorkOrderItem order) {
    final msgCtrl = TextEditingController();
    List<dynamic> logs = [];
    try {
      if (order.chatLogs != null) {
        logs = (order.chatLogs is String) ? jsonDecode(order.chatLogs as String) : List.from(order.chatLogs as List);
      }
    } catch (_) {}

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Text('Nhắn tin với xưởng — ${order.bienSo}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
            content: SizedBox(
              width: 500,
              height: 400,
              child: Column(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: logs.length,
                        itemBuilder: (_, i) {
                          final log = logs[i];
                          final isMe = log['sender'] == widget.login.userName;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isMe ? Colors.blue[100] : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey[300]!),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${log['sender']} (${log['role']})',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey)),
                                  const SizedBox(height: 4),
                                  Text(log['msg']?.toString() ?? ''),
                                  const SizedBox(height: 4),
                                  Text(
                                    log['time']?.toString().substring(11, 16) ?? '',
                                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: msgCtrl,
                          decoration: const InputDecoration(hintText: 'Nhắn gửi xưởng…', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.send, color: Colors.blue),
                        onPressed: () async {
                          if (msgCtrl.text.trim().isEmpty) return;
                          logs.add({
                            'sender': widget.login.userName,
                            'role': 'Khách hàng',
                            'msg': msgCtrl.text.trim(),
                            'time': DateTime.now().toIso8601String(),
                          });
                          msgCtrl.clear();
                          order.chatLogs = jsonEncode(logs);
                          setDialogState(() {});
                          await api.updateRepairOrder(
                            token: widget.login.token,
                            id: order.id,
                            status: order.status,
                            chatLogs: jsonEncode(logs),
                          );
                          if (mounted) await _loadData();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng'))],
          );
        },
      ),
    );
  }

  Future<void> _exportExcel() async {
    if (_ordersTotalCount == 0) return;
    setState(() => loading = true);
    try {
      var excel = Excel.createExcel();
      Sheet sheet = excel['Tiến độ xe'];
      sheet.appendRow([
        TextCellValue('Biển số'),
        TextCellValue('Mã RO'),
        TextCellValue('Cố vấn'),
        TextCellValue('Trạng thái'),
        TextCellValue('Đang chờ'),
        TextCellValue('Vị trí'),
        TextCellValue('Chi phí dự kiến (đ)'),
      ]);

      final exportList = _isPlateSearchActive
          ? [..._ordersInWorkshop, ..._ordersArchive]
              .where((o) => _plateMatches(o.bienSo, _plateSearchQuery))
              .toList()
          : [..._ordersInWorkshop, ..._ordersArchive];
      for (var o in exportList) {
        double total = 0;
        try {
          if (o.jobs != null) {
            final jList = (o.jobs is String) ? jsonDecode(o.jobs as String) : List.from(o.jobs as List);
            for (var j in jList) {
              total += _num(j['total']);
            }
          }
          if (o.parts != null) {
            final pList = (o.parts is String) ? jsonDecode(o.parts as String) : List.from(o.parts as List);
            for (var p in pList) {
              total += _num(p['total']);
            }
          }
        } catch (_) {}
        sheet.appendRow([
          TextCellValue(o.bienSo),
          TextCellValue(o.roCode),
          TextCellValue(o.cvdvUsername),
          TextCellValue(_statusMeta(o.status)['text']!),
          TextCellValue(waitingBriefForStatus(o.status, customerWaiting: o.customerWaiting)),
          TextCellValue(o.position),
          TextCellValue(total.toStringAsFixed(0)),
        ]);
      }

      final fileName = 'TienDoXe_${widget.login.userName}.xlsx';
      final result = await saveExcelBytes(
        bytes: excel.save(),
        fileName: fileName,
        dialogTitle: 'Tiến độ xe',
      );
      if (mounted) {
        showCrossPlatformSaveSnackBar(context, result, fileName, successExtra: 'Tiến độ xe');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi xuất Excel: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _showAddCarDialog() {
    final bsCtrl = TextEditingController();
    bool isSearching = false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Tìm & liên kết xe', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Có thể thêm nhiều xe nếu bạn là khách doanh nghiệp.', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              TextField(
                controller: bsCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Biển số (VD: 30A-12345)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.directions_car),
                ),
              ),
              if (isSearching) const Padding(padding: EdgeInsets.only(top: 16), child: CircularProgressIndicator()),
            ],
          ),
          actions: [
            TextButton(onPressed: isSearching ? null : () => Navigator.pop(ctx), child: const Text('Hủy')),
            FilledButton.icon(
              onPressed: isSearching
                  ? null
                  : () async {
                      final input = _normalizePlateKey(bsCtrl.text);
                      if (input.isEmpty) return;
                      setDialogState(() => isSearching = true);
                      try {
                        final allOrders = await api.fetchBoard(widget.login.token);
                        final matches = allOrders
                            .where((o) => _normalizePlateKey(o.bienSo) == input)
                            .toList();
                        final found = matches.isEmpty ? null : matches.first;
                        if (found == null) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Không tìm thấy xe trong xưởng!'), backgroundColor: Colors.red),
                            );
                          }
                          setDialogState(() => isSearching = false);
                          return;
                        }

                        await api.updateRepairOrder(
                          token: widget.login.token,
                          id: found.id,
                          status: found.status,
                          linkRequestedBy: widget.login.userName,
                        );
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Đã gửi yêu cầu đến cố vấn dịch vụ.'), backgroundColor: Colors.green),
                          );
                          await _loadData();
                        }
                      } catch (e) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red));
                        }
                        setDialogState(() => isSearching = false);
                      }
                    },
              icon: const Icon(Icons.send),
              label: const Text('Gửi yêu cầu'),
            ),
          ],
        ),
      ),
    );
  }

  void _showBookingDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => _BookingRequestDialog(
        api: api,
        token: widget.login.token,
        pendingStatus: _bookingPendingCskh,
        initialBienSo: _ordersInWorkshop.isNotEmpty
            ? _ordersInWorkshop.first.bienSo
            : (_ordersArchive.isNotEmpty ? _ordersArchive.first.bienSo : ''),
        initialName: widget.login.userName,
        initialPhone: _guestPhonePrefill(),
        loadDayStats: (day) async {
          final bookings = await api.fetchBookings(widget.login.token);
          final board = await api.fetchBoard(widget.login.token);
          return (
            appointments: _countBookingsOnDay(bookings, day),
            workshop: _countCurrentWorkshop(board),
          );
        },
        onSuccess: () {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Đã gửi đặt hẹn. CSKH sẽ xem và phản hồi.'),
              backgroundColor: Colors.green,
            ),
          );
          _loadData();
        },
      ),
    );
  }

  Future<void> _approveRO(
    String orderId,
    bool isApprove,
    String note,
    BuildContext sheetContext,
  ) async {
    void closeSheet() {
      if (sheetContext.mounted) Navigator.of(sheetContext).maybePop();
    }

    try {
      await api.updateRepairOrder(
        token: widget.login.token,
        id: orderId,
        status: isApprove ? 'CHO_PHAN_CONG' : 'HUY_CHO_QUYET_TOAN',
        statusNote: isApprove
            ? 'Khách đã duyệt báo giá: $note'
            : 'Khách từ chối báo giá — chờ Kế toán xác nhận cho ra xưởng${note.trim().isEmpty ? '' : ': $note'}',
      );
      closeSheet();
      if (!mounted) return;
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isApprove ? 'Cảm ơn bạn! Xưởng sẽ tiến hành sửa chữa.' : 'Bạn đã từ chối báo giá.'),
          backgroundColor: isApprove ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      closeSheet();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không cập nhật được: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  String _formatVND(double value) =>
      value.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');

  Widget _paymentSourceRow(String label, double amount) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
          Text(
            '${_formatVND(amount)} đ',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: amount > 0 ? const Color(0xFF0F172A) : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  /// Nhãn ngắn cho khách (song song với [waitingBriefForStatus] cho dòng “đang chờ”).
  Map<String, dynamic> _statusMeta(String rawStatus) {
    final s = normalizeRepairOrderStatus(rawStatus);
    if (s.isEmpty) return {'text': 'Chưa xác định', 'color': Colors.blueGrey};
    if (s.contains('VAO_XUONG')) return {'text': 'Mới tiếp nhận', 'color': Colors.blue};
    if (s.contains('CHO_BAO_GIA')) return {'text': 'Đang kiểm tra / báo giá', 'color': Colors.orange};
    if (s.contains('CHO_KH_DUYET')) return {'text': 'Cần duyệt báo giá', 'color': Colors.red};
    if (s.contains('CHO_PHAN_CONG')) return {'text': 'Đã duyệt — chờ phân KTV', 'color': Colors.purple};
    if (s.contains('CHO_SUA_CHUA')) return {'text': 'Chờ KTV bắt đầu sửa', 'color': Colors.deepPurple};
    if (s.contains('DANG_SUA')) return {'text': 'Đang sửa chữa', 'color': Colors.green};
    if (s.contains('CHO_QD_KIEM_TRA')) return {'text': 'Chờ nghiệm thu', 'color': Colors.cyan};
    if (s.contains('DUNG_SUA') || s.contains('CHO_PHU_TUNG')) {
      return {'text': 'Tạm dừng / chờ phụ tùng', 'color': Colors.deepOrange};
    }
    if (s.contains('CHO_CVDV_CHOT')) return {'text': 'Chờ CVDV chốt vật tư', 'color': Colors.amber.shade800};
    // Tránh HUY_CHO_QUYET_TOAN khớp nhầm nhánh «chờ quyết toán» (substring CHO_QUYET_TOAN).
    if ((s.contains('CHO_QUYET_TOAN') && !s.contains('HUY_CHO_QUYET')) || s.contains('DA_THANH_TOAN')) {
      return {'text': 'Hoàn tất — chờ giao xe', 'color': Colors.teal};
    }
    if (s.contains('HUY_CHO_QUYET_TOAN')) return {'text': 'Đã hủy — chờ kế toán', 'color': Colors.deepPurple};
    if (s.contains('KT_DUYET_RA_CONG')) return {'text': 'Được phép ra cổng', 'color': Colors.indigo};
    if (s == 'DA_RA_CONG_THIEU_PT') {
      return {'text': 'Đã xuất — thiếu phụ tùng', 'color': Colors.grey};
    }
    if (s.contains('DA_RA_CONG')) return {'text': 'Đã xuất xưởng', 'color': Colors.grey};
    if (s.contains('XE_RA_XUONG')) return {'text': 'Đã / sắp ra xưởng', 'color': Colors.grey};
    if (s.contains('TU_CHOI')) {
      return {'text': 'Từ chối báo giá — chờ Kế toán duyệt ra xưởng', 'color': Colors.deepPurple};
    }
    return {'text': s, 'color': Colors.blueGrey};
  }

  void _showNotificationsPanel() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.55,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text('Thông báo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
                    ],
                  ),
                ),
                Expanded(
                  child: _notifications.isEmpty
                      ? const Center(child: Text('Chưa có thông báo từ xưởng.'))
                      : ListView.separated(
                          padding: const EdgeInsets.only(bottom: 16),
                          itemCount: _notifications.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final n = _notifications[i];
                            final id = n['id']?.toString() ?? '';
                            final title = (n['title'] ?? '').toString();
                            final body = (n['body'] ?? '').toString();
                            final unread = n['read_at'] == null;
                            return ListTile(
                              tileColor: unread ? Colors.orange.shade50 : null,
                              title: Text(
                                title,
                                style: TextStyle(fontWeight: unread ? FontWeight.bold : FontWeight.w500),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(body, maxLines: 5, overflow: TextOverflow.ellipsis),
                              ),
                              onTap: id.isEmpty
                                  ? null
                                  : () async {
                                      try {
                                        await api.markNotificationRead(widget.login.token, id);
                                      } catch (_) {}
                                      if (!mounted) return;
                                      Navigator.pop(context);
                                      _loadData();
                                    },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  int get _ordersTotalCount => _ordersInWorkshop.length + _ordersArchive.length;

  List<WorkOrderItem> get _ordersCurrentTab =>
      _khOrderTab == 0 ? _ordersInWorkshop : (_khOrderTab == 1 ? _ordersArchive : []);

  String get _plateSearchQuery => _plateSearchCtrl.text;

  bool get _isPlateSearchActive => _normalizePlateKey(_plateSearchQuery).isNotEmpty;

  List<WorkOrderItem> get _filteredPending =>
      pendingRequests.where((o) => _plateMatches(o.bienSo, _plateSearchQuery)).toList();

  List<WorkOrderItem> get _filteredOrdersCurrentTab =>
      _ordersCurrentTab.where((o) => _plateMatches(o.bienSo, _plateSearchQuery)).toList();

  Widget _buildPlateSearchField() {
    return TextField(
      controller: _plateSearchCtrl,
      textCapitalization: TextCapitalization.characters,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: 'Tìm theo biển số (VD: 30A12345)',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _isPlateSearchActive
            ? IconButton(
                tooltip: 'Xóa tìm kiếm',
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _plateSearchCtrl.clear();
                  setState(() {});
                },
              )
            : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        isDense: true,
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }

  String _tabCountLabel(int shown, int total) {
    if (!_isPlateSearchActive || shown == total) return '($total)';
    return '($shown/$total)';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text('TS-XDV — Xe của tôi', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        actions: [
          Center(
            child: Text(
              'Xin chào, ${widget.login.userName}  ',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
            ),
          ),
          if (_ordersTotalCount > 0)
            OutlinedButton.icon(
              onPressed: loading ? null : _exportExcel,
              icon: const Icon(Icons.download, color: Colors.green),
              label: const Text('Xuất Excel', style: TextStyle(color: Colors.green)),
            ),
          const SizedBox(width: 8),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                tooltip: 'Thông báo',
                onPressed: loading ? null : _showNotificationsPanel,
              ),
              if (_unreadNotify > 0)
                Positioned(
                  right: 4,
                  top: 4,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(8)),
                      constraints: const BoxConstraints(minWidth: 16),
                      child: Text(
                        _unreadNotify > 9 ? '9+' : '$_unreadNotify',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: loading ? null : _loadData, tooltip: 'Làm mới'),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.red),
            onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          if (loading && _ordersTotalCount == 0 && pendingRequests.isEmpty)
            const Center(child: CircularProgressIndicator())
          else
            RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: appPageHorizontalPadding(context, bottom: 88),
                children: [
                  if (_loadError != null && _ordersTotalCount == 0 && pendingRequests.isEmpty)
                    Card(
                      color: Colors.red.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('Lần tải trước bị lỗi: $_loadError\nKéo xuống để thử lại.', style: TextStyle(color: Colors.red.shade900)),
                      ),
                    ),
                  Row(
                    children: [
                      Chip(label: Text('$_ordersTotalCount phiếu')),
                      const SizedBox(width: 8),
                      if (pendingRequests.isNotEmpty)
                        Chip(
                          avatar: const Icon(Icons.hourglass_empty, size: 18),
                          label: Text('${pendingRequests.length} chờ xác nhận'),
                          backgroundColor: Colors.orange.shade50,
                        ),
                      const Spacer(),
                      Text('Tự làm mới mỗi 30 giây', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (pendingRequests.isNotEmpty || _ordersTotalCount > 0) ...[
                    _buildPlateSearchField(),
                    const SizedBox(height: 12),
                  ],
                  if (_workshopFeatures?.khAdsMode == KhAdsMode.banner &&
                      (_workshopFeatures?.khAds.isNotEmpty ?? false))
                    KhAdBanner(
                      login: widget.login,
                      ads: _workshopFeatures!.khAds,
                    )
                  else if (_workshopFeatures?.khAdsMode == KhAdsMode.admob)
                    KhAdmobBanner(config: _workshopFeatures!.admob),
                  if (pendingRequests.isNotEmpty) ...[
                    Text(
                      'Đang chờ xưởng xác nhận${_tabCountLabel(_filteredPending.length, pendingRequests.length)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
                    ),
                    const SizedBox(height: 8),
                    if (_filteredPending.isEmpty && _isPlateSearchActive)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Không có xe chờ xác nhận khớp «${_plateSearchCtrl.text.trim()}».',
                          style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
                        ),
                      )
                    else
                    ..._filteredPending.map(
                      (r) => Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.hourglass_empty, color: Colors.orange),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Xe ${r.bienSo} — chờ CVDV duyệt liên kết.',
                                style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (_ordersTotalCount == 0)
                    Center(
                      child: Column(
                        children: [
                          const SizedBox(height: 40),
                          const Icon(Icons.car_crash, size: 80, color: Colors.grey),
                          const SizedBox(height: 16),
                          const Text(
                            'Tài khoản chưa liên kết với xe nào (hoặc chưa trùng SĐT trên phiếu).',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: _showAddCarDialog,
                            icon: const Icon(Icons.search),
                            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16)),
                            label: const Text('Tìm và liên kết xe', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: Text(
                            'Trong xưởng${_tabCountLabel(_ordersInWorkshop.where((o) => _plateMatches(o.bienSo, _plateSearchQuery)).length, _ordersInWorkshop.length)}',
                          ),
                          selected: _khOrderTab == 0,
                          onSelected: (v) {
                            if (v) setState(() => _khOrderTab = 0);
                          },
                        ),
                        ChoiceChip(
                          label: Text(
                            'Đã ra xưởng${_tabCountLabel(_ordersArchive.where((o) => _plateMatches(o.bienSo, _plateSearchQuery)).length, _ordersArchive.length)}',
                          ),
                          selected: _khOrderTab == 1,
                          onSelected: (v) {
                            if (v) setState(() => _khOrderTab = 1);
                          },
                        ),
                        ChoiceChip(
                          label: const Text('Nhắc bảo dưỡng'),
                          selected: _khOrderTab == 2,
                          onSelected: (v) {
                            if (v) setState(() => _khOrderTab = 2);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_khOrderTab == 2)
                      SizedBox(
                        height: 420,
                        child: MaintenanceReminderPanel(
                          api: api,
                          token: widget.login.token,
                          customerPhone: widget.login.userName,
                          plateSearchQuery: _plateSearchQuery,
                        ),
                      )
                    else if (_ordersCurrentTab.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 12),
                        child: Center(
                          child: Text(
                            _khOrderTab == 0
                                ? 'Không có xe đang trong xưởng. Chuyển sang tab «Đã ra xưởng» để xem lịch sử.'
                                : 'Chưa có phiếu đã ra xưởng.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 15, color: Colors.grey.shade700),
                          ),
                        ),
                      )
                    else if (_filteredOrdersCurrentTab.isEmpty && _isPlateSearchActive)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 12),
                        child: Center(
                          child: Text(
                            'Không có phiếu khớp biển «${_plateSearchCtrl.text.trim()}» trong tab này.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 15, color: Colors.grey.shade700),
                          ),
                        ),
                      )
                    else
                      ..._filteredOrdersCurrentTab.map((o) => _buildVehicleCard(o)),
                  ],
                ],
              ),
            ),
          if (loading && (_ordersTotalCount > 0 || pendingRequests.isNotEmpty))
            const Positioned.fill(
              child: IgnorePointer(
                child: ModalBarrier(dismissible: false, color: Color(0x08000000)),
              ),
            ),
          if (loading && (_ordersTotalCount > 0 || pendingRequests.isNotEmpty)) const Center(child: CircularProgressIndicator()),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'kh_fab_booking',
            tooltip: 'Đặt hẹn',
            onPressed: loading ? null : _showBookingDialog,
            child: const Icon(Icons.calendar_month),
          ),
          if (_ordersTotalCount > 0) ...[
            const SizedBox(height: 12),
            FloatingActionButton.extended(
              heroTag: 'kh_fab_add_car',
              onPressed: _showAddCarDialog,
              label: const Text('Thêm xe khác'),
              icon: const Icon(Icons.add_circle),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVehicleCard(WorkOrderItem order) {
    final needsAttention = normalizeRepairOrderStatus(order.status) == 'CHO_KH_DUYET';
    final meta = _statusMeta(order.status);
    final activityLine = vehicleActivityLineForKh(order.vehicleActivityNote, order.status);
    final wo = order.cvdvWoCode.trim().isEmpty ? '—' : order.cvdvWoCode;

    var hasNewMsg = false;
    try {
      if (order.chatLogs != null) {
        final logs = (order.chatLogs is String) ? jsonDecode(order.chatLogs as String) : List.from(order.chatLogs as List);
        if (logs.isNotEmpty && logs.last['role'] == 'CVDV') hasNewMsg = true;
      }
    } catch (_) {}

    final callLabel = _vehicleOutsideWorkshopForDial(order.status) ? 'Gọi CSKH' : 'Gọi CVDV';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              onTap: () => _showRODetail(order),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.blue,
                      child: Icon(Icons.directions_car, color: Colors.white, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            order.bienSo,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, height: 1.1),
                          ),
                          Text(
                            'RO ${order.roCode} · WO $wo · ${order.cvdvUsername.isEmpty ? '—' : order.cvdvUsername}',
                            style: TextStyle(color: Colors.blueGrey.shade700, fontSize: 10, height: 1.2),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            meta['text'] as String,
                            style: TextStyle(color: meta['color'] as Color?, fontWeight: FontWeight.w600, fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Chờ: ${waitingBriefForStatus(order.status, customerWaiting: order.customerWaiting)} · Đã chờ: ${order.waitDisplayShort}',
                            style: TextStyle(color: Colors.blueGrey.shade800, fontSize: 10, height: 1.25),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (order.customerWaiting)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'KH đang chờ tại xưởng',
                                style: TextStyle(color: Colors.red.shade800, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          if (activityLine != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                activityLine,
                                style: TextStyle(color: Colors.indigo.shade800, fontSize: 10, fontWeight: FontWeight.w500),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (needsAttention)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
                            child: const Text(
                              'DUYỆT BG',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 9),
                            ),
                          ),
                        if (hasNewMsg)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(4)),
                            child: const Text(
                              'TIN NHẮN',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 9),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => _callWorkshopSmart(order),
                  icon: const Icon(Icons.phone, color: Colors.blue, size: 16),
                  label: Text(
                    callLabel,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => _openChatDialog(order),
                  icon: const Icon(Icons.chat, color: Colors.orange, size: 16),
                  label: const Text('Nhắn CVDV', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showRODetail(WorkOrderItem order) {
    final meta = _statusMeta(order.status);
    final detailActivity = vehicleActivityLineForKh(order.vehicleActivityNote, order.status);
    final isWaitingApproval = normalizeRepairOrderStatus(order.status) == 'CHO_KH_DUYET';
    final wo = order.cvdvWoCode.trim().isEmpty ? '—' : order.cvdvWoCode;

    double totalJobs = 0;
    double totalParts = 0;
    List<dynamic> jobs = [];
    List<dynamic> parts = [];
    try {
      if (order.jobs != null) jobs = (order.jobs is String) ? jsonDecode(order.jobs as String) : List.from(order.jobs as List);
    } catch (_) {}
    try {
      if (order.parts != null) parts = (order.parts is String) ? jsonDecode(order.parts as String) : List.from(order.parts as List);
    } catch (_) {}
    for (var j in jobs) {
      totalJobs += _num(j['total']);
    }
    for (var p in parts) {
      totalParts += _num(p['total']);
    }
    final grandTotal = totalJobs + totalParts;
    final pay = parsePaymentInfo(order.paymentInfo);
    final noteCtrl = TextEditingController();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.95,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (_, scroll) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                child: Row(
                  children: [
                    const SizedBox(width: 40, height: 40),
                    Expanded(
                      child: Center(
                        child: Container(
                          width: 40,
                          height: 5,
                          decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Đóng',
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scroll,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 2))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(order.bienSo, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: (meta['color'] as Color).withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(meta['text'] as String, style: TextStyle(color: meta['color'] as Color, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                          Text('Mã RO: ${order.roCode}  ·  Mã WO (CVDV): $wo', style: TextStyle(color: Colors.blueGrey.shade700)),
                          const Divider(height: 30),
                          Row(
                            children: [
                              const Icon(Icons.map, size: 20, color: Colors.grey),
                              const SizedBox(width: 8),
                              const Text('Xe đang ở:', style: TextStyle(color: Colors.grey, fontSize: 15)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  order.position.isNotEmpty ? order.position : 'Trong xưởng',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(Icons.person, size: 20, color: Colors.grey),
                              const SizedBox(width: 8),
                              const Text('Cố vấn:', style: TextStyle(color: Colors.grey, fontSize: 15)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  order.cvdvUsername.isNotEmpty ? order.cvdvUsername : 'Đang phân công',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Đang chờ: ${waitingBriefForStatus(order.status, customerWaiting: order.customerWaiting)}',
                            style: TextStyle(color: Colors.blueGrey.shade800, fontWeight: FontWeight.w600),
                          ),
                          Text('Đã chờ: ${order.waitDisplayShort}', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w600)),
                          if (detailActivity != null) ...[
                            const SizedBox(height: 8),
                            Text('Công việc trên xe: $detailActivity',
                                style: TextStyle(color: Colors.indigo.shade800, fontWeight: FontWeight.w500)),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (jobs.isNotEmpty || parts.isNotEmpty) ...[
                      const Text('Chi tiết chi phí dự kiến', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (jobs.isNotEmpty) ...[
                              const Text('1. Tiền công sửa chữa:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                              const SizedBox(height: 8),
                              ...jobs.map(
                                (j) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(child: Text('• ${j['name']}')),
                                      Text('${_formatVND(_num(j['total']))} đ', style: const TextStyle(fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                              ),
                              const Divider(),
                            ],
                            if (parts.isNotEmpty) ...[
                              const Text('2. Phụ tùng / vật tư:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                              const SizedBox(height: 8),
                              ...parts.map(
                                (p) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(child: Text('• ${p['name']} (x${p['qty']})')),
                                      Text('${_formatVND(_num(p['total']))} đ', style: const TextStyle(fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                              ),
                              const Divider(),
                            ],
                            if (pay.hasAny) ...[
                              const SizedBox(height: 8),
                              const Text(
                                'Nguồn thanh toán (CVDV xác nhận)',
                                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey),
                              ),
                              const SizedBox(height: 10),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.blue.shade100),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _paymentSourceRow('Khách hàng thanh toán (C)', pay.customerPay),
                                    _paymentSourceRow('Bảo hiểm thanh toán (I)', pay.insurancePay),
                                    _paymentSourceRow('Bảo hành / VinFast (W)', pay.warrantyPay),
                                    _paymentSourceRow('Công nợ', pay.debt),
                                    if (pay.insuranceCompany != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Text(
                                          'Hãng bảo hiểm: ${pay.insuranceCompany}',
                                          style: TextStyle(fontSize: 13, color: Colors.blueGrey.shade800),
                                        ),
                                      ),
                                    if (pay.customerPay > 0) ...[
                                      const Divider(height: 20),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Expanded(
                                            child: Text(
                                              'Quý khách cần thanh toán',
                                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                            ),
                                          ),
                                          Text(
                                            '${_formatVND(pay.customerPay)} đ',
                                            style: const TextStyle(
                                              fontSize: 20,
                                              color: Colors.green,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const Divider(),
                            ],
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('TỔNG THANH TOÁN:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                Text(
                                  '${_formatVND(grandTotal)} đ',
                                  style: const TextStyle(fontSize: 22, color: Colors.red, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                    if (isWaitingApproval) ...[
                      const Text('Quyết định của bạn', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.red.withOpacity(0.3)),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'Vui lòng xem kỹ chi phí. Nếu đồng ý, xưởng sẽ tiến hành sửa chữa.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.red),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: noteCtrl,
                              maxLines: 2,
                              decoration: const InputDecoration(
                                labelText: 'Ghi chú cho xưởng',
                                border: OutlineInputBorder(),
                                filled: true,
                                fillColor: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _approveRO(order.id, false, noteCtrl.text, sheetContext),
                                    icon: const Icon(Icons.cancel, color: Colors.red),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      side: const BorderSide(color: Colors.red),
                                    ),
                                    label: const Text('TỪ CHỐI', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: () => _approveRO(order.id, true, noteCtrl.text, sheetContext),
                                    icon: const Icon(Icons.check_circle),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                    ),
                                    label: const Text('ĐỒNG Ý SỬA', style: TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ).then((_) => noteCtrl.dispose());
  }
}

/// Dialog đặt hẹn — dùng [StatefulWidget] để tránh `setState` sau khi route đóng (lỗi `_dependents.isEmpty`).
class _BookingRequestDialog extends StatefulWidget {
  const _BookingRequestDialog({
    required this.api,
    required this.token,
    required this.pendingStatus,
    required this.initialBienSo,
    required this.initialName,
    required this.initialPhone,
    required this.loadDayStats,
    required this.onSuccess,
  });

  final ApiService api;
  final String token;
  final String pendingStatus;
  final String initialBienSo;
  final String initialName;
  final String initialPhone;
  final Future<({int appointments, int workshop})> Function(DateTime day) loadDayStats;
  final VoidCallback onSuccess;

  @override
  State<_BookingRequestDialog> createState() => _BookingRequestDialogState();
}

class _BookingRequestDialogState extends State<_BookingRequestDialog> {
  late final TextEditingController _timeCtrl;
  late final TextEditingController _bsCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _noteCtrl;
  late final TextEditingController _carModelCtrl;

  DateTime _selectedDate = DateTime.now();
  int _appt = 0;
  int _workshop = 0;
  bool _statsLoading = true;
  String? _statsErr;
  bool _submitting = false;

  static String _formatHour(String rawHour) {
    String h = rawHour.toLowerCase().replaceAll('h', ':').trim();
    if (!h.contains(':')) h += ':00';
    try {
      final p = h.split(':');
      return '${p[0].padLeft(2, '0')}:${p[1].padLeft(2, '0')}';
    } catch (_) {
      return '08:00';
    }
  }

  @override
  void initState() {
    super.initState();
    _timeCtrl = TextEditingController(text: '08:00');
    _bsCtrl = TextEditingController(text: widget.initialBienSo);
    _nameCtrl = TextEditingController(text: widget.initialName);
    _phoneCtrl = TextEditingController(text: widget.initialPhone);
    _noteCtrl = TextEditingController();
    _carModelCtrl = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshStats());
  }

  @override
  void dispose() {
    _timeCtrl.dispose();
    _bsCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _noteCtrl.dispose();
    _carModelCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshStats() async {
    if (!mounted) return;
    setState(() {
      _statsLoading = true;
      _statsErr = null;
    });
    try {
      final day = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
      final r = await widget.loadDayStats(day);
      if (!mounted) return;
      setState(() {
        _appt = r.appointments;
        _workshop = r.workshop;
        _statsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statsErr = e.toString();
        _statsLoading = false;
      });
    }
  }

  Future<void> _submit() async {
    if (_bsCtrl.text.trim().isEmpty || _nameCtrl.text.trim().isEmpty || _phoneCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập biển số, tên và SĐT.'), backgroundColor: Colors.red),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final timeLine = '${DateFormat('dd/MM/yyyy').format(_selectedDate)} ${_formatHour(_timeCtrl.text)}';
      await widget.api.createBooking(
        token: widget.token,
        data: {
          'bien_so': _bsCtrl.text.trim().toUpperCase(),
          'car_model': _carModelCtrl.text.trim(),
          'time': timeLine,
          'customer_name': _nameCtrl.text.trim(),
          'customer_phone': _phoneCtrl.text.trim(),
          'note': _noteCtrl.text.trim(),
          'status': widget.pendingStatus,
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onSuccess();
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dayLabel = DateFormat('dd/MM/yyyy').format(_selectedDate);
    final dialogW = math.min(MediaQuery.sizeOf(context).width - 48, 440.0);

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.calendar_month, color: Colors.blue),
          SizedBox(width: 8),
          Expanded(child: Text('Đặt hẹn', style: TextStyle(fontWeight: FontWeight.bold))),
        ],
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: dialogW,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Yêu cầu được gửi tới CSKH. Bạn sẽ được phục vụ sau khi CSKH xác nhận lịch.',
                style: TextStyle(color: Colors.black87, fontSize: 13),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text('Ngày hẹn: $dayLabel', style: const TextStyle(fontWeight: FontWeight.w600)),
                trailing: IconButton(
                  icon: const Icon(Icons.edit_calendar),
                  onPressed: _submitting
                      ? null
                      : () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: _selectedDate,
                            firstDate: DateTime.now().subtract(const Duration(days: 1)),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (d != null && mounted) {
                            setState(() => _selectedDate = d);
                            await _refreshStats();
                          }
                        },
                ),
              ),
              TextField(
                controller: _timeCtrl,
                enabled: !_submitting,
                decoration: const InputDecoration(
                  labelText: 'Giờ (VD: 8h00 hoặc 08:30)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _bsCtrl,
                enabled: !_submitting,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Biển số', border: OutlineInputBorder(), isDense: true),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nameCtrl,
                enabled: !_submitting,
                decoration: const InputDecoration(labelText: 'Tên khách', border: OutlineInputBorder(), isDense: true),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _phoneCtrl,
                enabled: !_submitting,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Số điện thoại', border: OutlineInputBorder(), isDense: true),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _carModelCtrl,
                enabled: !_submitting,
                decoration: const InputDecoration(labelText: 'Dòng xe (tuỳ chọn)', border: OutlineInputBorder(), isDense: true),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _noteCtrl,
                enabled: !_submitting,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Ghi chú / yêu cầu', border: OutlineInputBorder(), isDense: true),
              ),
              const SizedBox(height: 12),
              Material(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _statsLoading
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(8),
                            child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2)),
                          ),
                        )
                      : _statsErr != null
                          ? Text('Không tải được thống kê: $_statsErr', style: const TextStyle(color: Colors.red, fontSize: 12))
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Ngày $dayLabel:', style: const TextStyle(fontWeight: FontWeight.bold)),
                                Text('• Đã có $_appt lịch đặt hẹn (chưa bị CSKH từ chối).', style: const TextStyle(fontSize: 13)),
                                Text(
                                  '• Hiện có khoảng $_workshop xe còn trong quy trình xưởng (chưa ra cổng / chưa hủy).',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ],
                            ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _submitting ? null : () => Navigator.of(context).pop(), child: const Text('Hủy')),
        FilledButton(onPressed: _submitting ? null : _submit, child: const Text('Gửi yêu cầu')),
      ],
    );
  }
}
