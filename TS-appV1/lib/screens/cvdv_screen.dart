import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border; 
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../core/app_pdf_fonts.dart';
import 'package:url_launcher/url_launcher.dart'; 
import 'package:archive/archive.dart';
import 'package:intl/intl.dart';

import '../models/auth_models.dart';
import '../services/api_service.dart';
import '../core/parts_fulfillment.dart';
import '../core/cross_platform_export_helpers.dart';
import '../core/document_export.dart';
import '../core/payment_info.dart';
import '../core/time_format.dart';
import '../core/workshop_local_sync.dart';
import '../core/pick_file_bytes.dart';
import '../widgets/company_chat_host.dart';
import '../widgets/vm_file_image.dart';
import '../widgets/responsive_shell.dart';
import '../core/responsive_layout.dart';
import 'login_screen.dart';

class CurrencyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) { return newValue.copyWith(text: '0'); }
    String cleanText = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    if (cleanText.isEmpty) return newValue.copyWith(text: '0');
    
    double value = double.parse(cleanText);
    final formatter = NumberFormat('#,###');
    String newText = formatter.format(value);
    
    return TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }
}

class JobItem {
  final codeCtrl = TextEditingController(); 
  final nameCtrl = TextEditingController(); 
  final hoursCtrl = TextEditingController(text: '1'); 
  final priceCtrl = TextEditingController(text: '0');
  final discountCtrl = TextEditingController(text: '0'); 
  final vatCtrl = TextEditingController(text: '8'); 
  final noteCtrl = TextEditingController(); 
  
  String paymentMethod = 'C';

  double get qty => double.tryParse(hoursCtrl.text) ?? 0;
  double get price => double.tryParse(priceCtrl.text.replaceAll(',', '')) ?? 0;
  double get discount => double.tryParse(discountCtrl.text.replaceAll(',', '')) ?? 0;
  double get vatRate => double.tryParse(vatCtrl.text) ?? 0;
  double get totalBeforeDiscount => qty * price;
  
  double get totalAfterDiscount { 
    double after = totalBeforeDiscount - discount; 
    return after > 0 ? after : 0; 
  }
  
  double get vatAmount => totalAfterDiscount * (vatRate / 100);
  double get totalWithVat => totalAfterDiscount + vatAmount;
  
  void dispose() { 
    codeCtrl.dispose();
    nameCtrl.dispose(); 
    hoursCtrl.dispose(); 
    priceCtrl.dispose(); 
    discountCtrl.dispose(); 
    vatCtrl.dispose(); 
    noteCtrl.dispose(); 
  }
}

class PartItem {
  final codeCtrl = TextEditingController(); 
  final nameCtrl = TextEditingController(); 
  final qtyCtrl = TextEditingController(text: '1');
  final priceCtrl = TextEditingController(text: '0'); 
  final discountCtrl = TextEditingController(text: '0'); 
  final vatCtrl = TextEditingController(text: '8'); 
  final noteCtrl = TextEditingController();

  String paymentMethod = 'C';
  bool inStock = true; 
  int issuedQty = 0; 
  bool isOrdered = false;
  /// ISO8601 — ghi khi CVDV bấm "Báo KHO"; dùng chặn gửi trùng kể cả khi server chỉ giữ snake_case hoặc mất cờ `isOrdered`.
  String khoBaoRequestedAt = '';

  double get qty => double.tryParse(qtyCtrl.text) ?? 0;
  double get price => double.tryParse(priceCtrl.text.replaceAll(',', '')) ?? 0;
  double get discount => double.tryParse(discountCtrl.text.replaceAll(',', '')) ?? 0;
  double get vatRate => double.tryParse(vatCtrl.text) ?? 0;
  double get totalBeforeDiscount => qty * price;
  
  double get totalAfterDiscount { 
    double after = totalBeforeDiscount - discount; 
    return after > 0 ? after : 0; 
  }
  
  double get vatAmount => totalAfterDiscount * (vatRate / 100);
  double get totalWithVat => totalAfterDiscount + vatAmount;

  void dispose() { 
    codeCtrl.dispose(); 
    nameCtrl.dispose(); 
    qtyCtrl.dispose(); 
    priceCtrl.dispose(); 
    discountCtrl.dispose(); 
    vatCtrl.dispose(); 
    noteCtrl.dispose(); 
  }
}

bool _jsonBoolTrue(dynamic v) {
  if (v == true || v == 1) return true;
  if (v is String) {
    final s = v.trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes';
  }
  return false;
}

/// Đã có yêu cầu đặt/báo KHO cho dòng PT (đọc mọi biến thể key server hay app).
bool _mapIndicatesKhoRequested(Map<String, dynamic> p) {
  if (_jsonBoolTrue(p['isOrdered']) || _jsonBoolTrue(p['is_ordered'])) return true;
  for (final key in [
    'khoBaoRequestedAt',
    'kho_bao_requested_at',
    'orderedDate',
    'ordered_date',
  ]) {
    final s = p[key]?.toString().trim() ?? '';
    if (s.isNotEmpty && s.toLowerCase() != 'null') return true;
  }
  return false;
}

bool _mapIndicatesInStock(Map<String, dynamic> p) =>
    _jsonBoolTrue(p['inStock']) || _jsonBoolTrue(p['in_stock']);

bool _partItemKhoRequested(PartItem p) =>
    p.isOrdered || p.khoBaoRequestedAt.trim().isNotEmpty;

String _statusHumanVi(String status) {
  switch (status) {
    case 'XE_VAO_XUONG':
      return 'Xe mới vào xưởng';
    case 'CHO_BAO_GIA':
      return 'Chờ lập & gửi báo giá';
    case 'CHO_KH_DUYET':
      return 'Chờ khách hàng duyệt báo giá';
    case 'CHO_CVDV_CHOT':
      return 'QD đã nghiệm thu — chờ CVDV chốt & giao xe';
    case 'CHO_PHAN_CONG':
      return 'Chờ phân công sửa chữa';
    case 'CHO_SUA_CHUA':
      return 'Chờ vào sửa chữa';
    case 'DANG_SUA':
      return 'Đang sửa chữa';
    case 'DUNG_SUA':
      return 'Tạm dừng sửa chữa';
    case 'CHO_QD_KIEM_TRA':
      return 'Chờ quản đốc kiểm tra';
    case 'CHO_QUYET_TOAN':
      return 'Chờ quyết toán';
    case 'DA_THANH_TOAN':
      return 'Đã thanh toán';
    case 'DA_RA_CONG':
    case 'XE_RA_XUONG':
      return 'Đã ra xưởng';
    case 'DA_RA_CONG_THIEU_PT':
      return 'Ra xưởng còn thiếu phụ tùng';
    case 'HUY':
      return 'Đã hủy (lưu trữ)';
    case 'HUY_CHO_QUYET_TOAN':
      return 'KH hủy — chờ Kế toán duyệt cho ra';
    case 'KT_DUYET_RA_CONG':
      return 'Kế toán đã duyệt ra — chờ Bảo vệ';
    default:
      return status.replaceAll('_', ' ');
  }
}

String _vehicleDoingLabel(WorkOrderItem o) {
  final t = o.vehicleActivityNote.trim();
  if (t.isNotEmpty) return t;
  return _statusHumanVi(o.status);
}

String _formatTimeInWorkshop(DateTime? t) {
  if (t == null) return '—';
  return DateFormat('yyyy-MM-dd HH:mm').format(t.toLocal());
}

class CvdvDashboardScreen extends StatefulWidget {
  const CvdvDashboardScreen({super.key, required this.login});
  final LoginResult login;

  @override
  State<CvdvDashboardScreen> createState() => _CvdvDashboardScreenState();
}

class _CvdvDashboardScreenState extends State<CvdvDashboardScreen> {
  late final ApiService api;
  bool loading = false;
  List<WorkOrderItem> orders = [];
  List<BookingItem> bookings = [];
  WorkOrderItem? selectedOrder;

  List<JobItem> currentJobs = [];
  List<PartItem> currentParts = [];
  final urgentNotesCtrl = TextEditingController();
  final cvdvWoCodeCtrl = TextEditingController();
  final vehicleActivityCtrl = TextEditingController();
  
  final searchBienSoCtrl = TextEditingController();

  final customerPayCtrl = TextEditingController(text: '0');
  final insurancePayCtrl = TextEditingController(text: '0');
  final vinfastPayCtrl = TextEditingController(text: '0');
  final debtCtrl = TextEditingController(text: '0');

  String _selectedFilter = 'XE ĐANG CHỜ XỬ LÝ & BÁO GIÁ';
  final List<String> _filters = [
    'XE ĐANG CHỜ XỬ LÝ & BÁO GIÁ',
    'XE ĐANG TRONG QUÁ TRÌNH SỬA',
    'XE ĐÃ RA XƯỞNG - HOÀN THÀNH',
    'XE ĐÃ RA XƯỞNG - THIẾU PT'
  ];

  final List<String> paymentOptions = ['C', 'I', 'W'];
  
  Map<String, String> globalUomMap = {};
  final String uomFilePath = 'uom_db.json';

  Map<String, DateTime> snoozedAlerts = {}; 
  List<Map<String, dynamic>> urgentAlerts = [];

  /// Sau lần "Báo sang KHO yêu cầu mua" thành công — chặn gửi trùng nếu danh sách PT (mã+SL) không đổi.
  String? _fpAfterLastKhoBaoRequest;

  /// Thông báo từ server (Kho / hệ thống), đếm chưa đọc cho badge chuông.
  int _unreadNotifCount = 0;

  List<bool> checkListStatus = List.filled(6, false);
  final List<String> todoTasks = [
    '1. Gọi điện xác nhận tình trạng xe với KH',
    '2. Lập & Gửi Báo Giá',
    '3. Chờ Khách Hàng chốt',
    '4. Phát lệnh sửa chữa cho Quản Đốc',
    '5. Theo dõi tiến độ & Báo phụ tùng',
    '6. Chuyển Kế toán quyết toán'
  ];

  final List<String> insuranceCompanies = [
    'Bảo Việt', 'PVI', 'PTI (Bưu điện)', 'MIC (Quân đội)', 
    'PJICO', 'Bảo Minh', 'Liberty', 'VNI', 'DBV', 'LPbank', 
    'BSH Việt Bắc', 'BH Toàn Cầu', 'Tasco', 'BIC', 'VBI', 'Khác'
  ];

  @override
  void initState() { 
    super.initState(); 
    api = ApiService(baseUrl: widget.login.baseUrl); 
    _loadUomMap(); 
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadBoard()); 
  }

  @override
  void dispose() { 
    _clearFormsRaw(); 
    urgentNotesCtrl.dispose();
    cvdvWoCodeCtrl.dispose();
    vehicleActivityCtrl.dispose();
    customerPayCtrl.dispose();
    insurancePayCtrl.dispose();
    vinfastPayCtrl.dispose();
    debtCtrl.dispose();
    searchBienSoCtrl.dispose(); 
    super.dispose(); 
  }

  Future<void> _loadUomMap() async {
    try {
      final data = await loadWorkshopJson(
        fileName: uomFilePath,
        api: api,
        token: widget.login.token,
      );
      if (data is Map) {
        setState(() {
          globalUomMap = data.map((key, value) => MapEntry(key.toString(), value.toString()));
        });
      }
    } catch (e) {}
  }

  void _clearFormsRaw() {
    for (var j in currentJobs) { j.dispose(); } 
    for (var p in currentParts) { p.dispose(); } 
    currentJobs.clear(); 
    currentParts.clear(); 
    urgentNotesCtrl.clear();
    cvdvWoCodeCtrl.clear();
    vehicleActivityCtrl.clear();
    customerPayCtrl.text = '0';
    insurancePayCtrl.text = '0';
    vinfastPayCtrl.text = '0';
    debtCtrl.text = '0';
    checkListStatus = List.filled(6, false);
  }

  bool _hasLinkRequest(dynamic req) {
    if (req == null) return false;
    String s = req.toString().trim().toLowerCase();
    return s.isNotEmpty && s != 'null' && s != 'false' && s != 'none' && s != '0';
  }

  static String _normPlate(String s) =>
      s.replaceAll(RegExp(r'[\s\-]'), '').toUpperCase();

  /// Tồn khả dụng cho lệnh hiện tại:
  /// - **Kho chung thật**: `woCode`/`wo_code` rỗng **và** `bienSo`/`bien_so` rỗng (không lấy dòng chỉ gắn biển xe khác làm "chung").
  /// - **Giữ theo RO**: mã WO khớp `roCode` lệnh.
  /// - **Giữ theo biển**: biển dòng khớp biển lệnh (kể cả WO trống nhưng có gắn biển).
  static int _qtyAvailableForRo(
    List<Map<String, dynamic>> inv,
    String partCode,
    String roCode,
    String bienSo,
  ) {
    final pc = partCode.trim().toLowerCase();
    if (pc.isEmpty) return 0;
    final ro = roCode.trim().toUpperCase();
    final bsNorm = _normPlate(bienSo);

    int sum = 0;
    for (final raw in inv) {
      final code = (raw['code']?.toString() ?? '').toLowerCase().trim();
      if (code != pc) continue;
      final q = int.tryParse(raw['quantity']?.toString() ?? '0') ?? 0;
      if (q <= 0) continue;

      final wo = (raw['woCode'] ?? raw['wo_code'] ?? '').toString().trim().toUpperCase();
      final rowBs = (raw['bienSo'] ?? raw['bien_so'] ?? '').toString().trim();
      final plateEmpty = rowBs.isEmpty || rowBs == '-';
      final woEmpty = wo.isEmpty;

      final countsAsGeneralPool = woEmpty && plateEmpty;
      final countsForThisRo = ro.isNotEmpty && wo == ro;
      final countsForThisPlate =
          bsNorm.isNotEmpty && !plateEmpty && _normPlate(rowBs) == bsNorm;

      if (countsAsGeneralPool || countsForThisRo || countsForThisPlate) {
        sum += q;
      }
    }
    return sum;
  }

  String _partsOrderFingerprint() {
    final bits = <String>[];
    for (final p in currentParts) {
      final c = p.codeCtrl.text.trim().toLowerCase();
      if (c.isEmpty) continue;
      bits.add('$c:${p.qty.toStringAsFixed(4)}');
    }
    bits.sort();
    return bits.join('\u001f');
  }

  bool _orderPartsFullyIssued(WorkOrderItem o) => allQuotedPartsFullyIssued(o.parts);

  bool _orderPartsReadyForSettlement(WorkOrderItem o) => repairOrderPartsReadyForSettlement(o.parts);

  int _preservedIssuedQtyForPart(PartItem e) {
    final code = e.codeCtrl.text.trim().toLowerCase();
    if (code.isEmpty) return e.issuedQty;
    return (issuedQtyByPartCode(selectedOrder?.parts)[code] ?? e.issuedQty).toInt();
  }

  static const _repairStatusesForPartsReady = {
    'CHO_PHAN_CONG',
    'CHO_SUA_CHUA',
    'DANG_SUA',
    'DUNG_SUA',
    'CHO_PHU_TUNG',
    'CHO_CVDV_CHOT',
    'CHO_QD_KIEM_TRA',
  };

  /// Thông báo vận hành theo rules CVDV (bổ sung ngoài link + chat).
  List<String> _cvdvRuleAlerts() {
    final me = widget.login.userName;
    final now = DateTime.now();
    final out = <String>[];

    for (final o in orders) {
      if (o.cvdvUsername != me) continue;

      if (o.status == 'CHO_BAO_GIA' && o.createdAt != null) {
        if (now.difference(o.createdAt!).inMinutes >= 30) {
          out.add('[${o.roCode}] ${o.bienSo}: Chờ báo giá ≥30p — lập & gửi BG.');
        }
      }
      if (o.status == 'CHO_KH_DUYET' && o.createdAt != null) {
        if (now.difference(o.createdAt!).inHours >= 4) {
          out.add('[${o.roCode}] ${o.bienSo}: Chờ KH duyệt ≥4h — liên hệ KH.');
        }
      }
      if (o.status == 'CHO_QUYET_TOAN' && o.createdAt != null) {
        if (now.difference(o.createdAt!).inMinutes >= 30) {
          out.add('[${o.roCode}] ${o.bienSo}: Chờ quyết toán lâu — phối hợp kế toán.');
        }
      }
      if (o.status == 'DA_RA_CONG_THIEU_PT') {
        out.add('[${o.roCode}] ${o.bienSo}: Xe ra cổng thiếu PT — theo dõi nợ/hẹn trả PT.');
      }
      if (_repairStatusesForPartsReady.contains(o.status) &&
          quotedPartsNeedWarehouseIssue(o.parts) &&
          _orderPartsFullyIssued(o)) {
        out.add('[${o.roCode}] ${o.bienSo}: ✅ Kho đã xuất đủ phụ tùng — liên hệ KTV / khách.');
      }
      if (o.status == 'CHO_CVDV_CHOT') {
        if (_orderPartsReadyForSettlement(o)) {
          out.add('[${o.roCode}] ${o.bienSo}: ✅ Quản đốc đã nghiệm thu — có thể chốt & chuyển kế toán (Kho đã xuất đủ PT).');
        } else if (quotedPartsNeedWarehouseIssue(o.parts)) {
          out.add('[${o.roCode}] ${o.bienSo}: Quản đốc đã nghiệm thu — chờ Kho xuất đủ phụ tùng trước khi quyết toán.');
        } else {
          out.add('[${o.roCode}] ${o.bienSo}: Quản đốc đã nghiệm thu — chốt hồ sơ / giao xe (không có PT trên báo giá).');
        }
      }

      try {
        if (o.parts != null &&
            o.parts.toString().isNotEmpty &&
            o.parts.toString() != 'null' &&
            o.parts.toString() != '[]') {
          final pList =
              (o.parts is String) ? jsonDecode(o.parts) : List.from(o.parts);
          bool missingNotOrdered = false;
          for (final raw in pList) {
            final p = Map<String, dynamic>.from(raw as Map);
            final inStock = _mapIndicatesInStock(p);
            if (!inStock && !_mapIndicatesKhoRequested(p)) {
              missingNotOrdered = true;
              break;
            }
          }
          if (missingNotOrdered) {
            out.add('[${o.roCode}] ${o.bienSo}: PT thiếu kho nhưng chưa báo KHO đặt hàng.');
          }
        }
      } catch (_) {}
    }
    return out;
  }

  /// Sau khi tải lại board, đồng bộ cờ đặt hàng/báo KHO từ server vào form đang mở (tránh báo trùng khi JSON server dùng snake_case).
  void _syncSelectedOrderPartsIntoForm() {
    final sel = selectedOrder;
    if (sel == null || currentParts.isEmpty) return;
    if (sel.parts == null) return;
    final ps = sel.parts.toString();
    if (ps.isEmpty || ps == 'null' || ps == '[]') return;
    try {
      final pList =
          (sel.parts is String) ? jsonDecode(sel.parts) as List : List.from(sel.parts as List);
      for (final cp in currentParts) {
        final target = cp.codeCtrl.text.trim().toLowerCase();
        if (target.isEmpty) continue;
        Map<String, dynamic>? pmap;
        for (final raw in pList) {
          final m = Map<String, dynamic>.from(raw as Map);
          final c = (m['code']?.toString() ?? '').trim().toLowerCase();
          if (c == target) {
            pmap = m;
            break;
          }
        }
        if (pmap == null) continue;
        cp.isOrdered = _mapIndicatesKhoRequested(pmap);
        final kb = pmap['khoBaoRequestedAt']?.toString() ??
            pmap['kho_bao_requested_at']?.toString() ??
            '';
        if (kb.trim().isNotEmpty) cp.khoBaoRequestedAt = kb;
        cp.inStock = _mapIndicatesInStock(pmap);
        cp.issuedQty = int.tryParse(pmap['issuedQty']?.toString() ?? '0') ?? 0;
      }
    } catch (_) {}
  }

  /// WO dùng cho kiểm tồn / đối chiếu KHO: CVDV nhập nếu có, không thì mã RO hệ thống.
  String _effectiveWoForKho() {
    final m = cvdvWoCodeCtrl.text.trim();
    if (m.isNotEmpty) return m.toUpperCase();
    return (selectedOrder?.roCode ?? '').trim().toUpperCase();
  }

  void _syncCvdvMetaFromSelectedOrder() {
    final sel = selectedOrder;
    if (sel == null) return;
    cvdvWoCodeCtrl.text = sel.cvdvWoCode;
    vehicleActivityCtrl.text = sel.vehicleActivityNote;
  }

  Future<void> _loadBoard() async {
    if (mounted) ScaffoldMessenger.of(context).clearSnackBars();
    setState(() => loading = true);
    int unreadN = 0;
    List<Map<String, dynamic>> nlist = [];
    try {
      nlist = await api.fetchNotifications(widget.login.token);
      unreadN = nlist.where(notificationIsUnread).length;
    } catch (_) {
      unreadN = 0;
    }
    try {
      final all = await api.fetchBoard(widget.login.token);
      final bk = await api.fetchBookings(widget.login.token);
      
      setState(() {
        orders = all; 
        bookings = bk;
        if (selectedOrder != null) {
          try { selectedOrder = orders.firstWhere((o) => o.id == selectedOrder!.id); } 
          catch (e) { selectedOrder = null; }
        }
        _syncSelectedOrderPartsIntoForm();
        _syncCvdvMetaFromSelectedOrder();
        _checkSLAAlerts();
      });
    } catch (e) {
    } finally { 
      setState(() {
        loading = false;
        _unreadNotifCount = unreadN;
      });
    }
  }

  List<WorkOrderItem> get filteredOrders {
    return orders.where((o) {
      bool isMyOrder = o.cvdvUsername == widget.login.userName;
      
      bool statusMatch = false;
      if (_selectedFilter == 'XE ĐANG CHỜ XỬ LÝ & BÁO GIÁ') {
        if (!isMyOrder) return false;
        statusMatch = ['XE_VAO_XUONG', 'CHO_BAO_GIA', 'CHO_KH_DUYET', 'CHO_CVDV_CHOT', 'CHO_QUYET_TOAN', 'DA_THANH_TOAN', 'HUY_CHO_QUYET_TOAN', 'KT_DUYET_RA_CONG'].contains(o.status);
      } else if (_selectedFilter == 'XE ĐANG TRONG QUÁ TRÌNH SỬA') {
        if (!isMyOrder) return false;
        statusMatch = ['CHO_PHAN_CONG', 'CHO_SUA_CHUA', 'DANG_SUA', 'DUNG_SUA', 'CHO_QD_KIEM_TRA'].contains(o.status);
      } else if (_selectedFilter == 'XE ĐÃ RA XƯỞNG - HOÀN THÀNH') {
        statusMatch = o.status == 'DA_RA_CONG' || o.status == 'XE_RA_XUONG' || o.status == 'KT_DUYET_RA_CONG';
      } else if (_selectedFilter == 'XE ĐÃ RA XƯỞNG - THIẾU PT') {
        statusMatch = o.status == 'DA_RA_CONG_THIEU_PT'; 
      }
      if (!statusMatch) return false;

      String query = searchBienSoCtrl.text.trim().toLowerCase().replaceAll(RegExp(r'[\s-]'), '');
      if (query.isNotEmpty) {
         String bs = o.bienSo.toLowerCase().replaceAll(RegExp(r'[\s-]'), '');
         if (!bs.contains(query)) return false;
      }
      return true;
    }).toList();
  }

  Widget _buildStatusBadge(String status) {
    Color bg; Color textC;
    switch(status) {
      case 'XE_VAO_XUONG': bg = Colors.red.shade100; textC = Colors.red.shade900; break;
      case 'CHO_BAO_GIA': bg = Colors.orange.shade100; textC = Colors.orange.shade900; break;
      case 'CHO_KH_DUYET': bg = Colors.yellow.shade100; textC = Colors.yellow.shade900; break;
      case 'CHO_CVDV_CHOT': bg = Colors.indigo.shade100; textC = Colors.indigo.shade900; break;
      case 'CHO_PHAN_CONG': bg = Colors.purple.shade100; textC = Colors.purple.shade900; break;
      case 'DANG_SUA': bg = Colors.blue.shade100; textC = Colors.blue.shade900; break;
      case 'DUNG_SUA': bg = Colors.red.shade700; textC = Colors.white; break;
      case 'CHO_QUYET_TOAN': bg = Colors.teal.shade100; textC = Colors.teal.shade900; break;
      case 'DA_THANH_TOAN': bg = Colors.green.shade100; textC = Colors.green.shade900; break;
      case 'HUY': bg = Colors.grey.shade400; textC = Colors.white; break;
      case 'HUY_CHO_QUYET_TOAN': bg = Colors.deepPurple.shade100; textC = Colors.deepPurple.shade900; break;
      case 'KT_DUYET_RA_CONG': bg = Colors.indigo.shade100; textC = Colors.indigo.shade900; break;
      default: bg = Colors.grey.shade200; textC = Colors.grey.shade800;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(status, style: TextStyle(color: textC, fontSize: 11, fontWeight: FontWeight.bold))
    );
  }

  Widget _buildRedAlertBadge(WorkOrderItem o) {
    if (o.createdAt == null) return const SizedBox.shrink();
    Duration diff = DateTime.now().difference(o.createdAt!);
    String alert = '';

    if (o.status == 'XE_VAO_XUONG' && diff.inMinutes >= 30) {
      alert = 'QUÁ 30P CHƯA BÁO GIÁ!';
    } else if (o.status == 'DA_RA_CONG_THIEU_PT' && diff.inDays >= 3) {
      alert = 'ĐỢI PHỤ TÙNG > 3 NGÀY!';
    } else if (o.status == 'CHO_QD_KIEM_TRA' && diff.inHours >= 4) {
      alert = 'QUẢN ĐỐC CHƯA DUYỆT > 4H!';
    }

    if (alert.isNotEmpty) {
      return Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: Colors.red.shade700, borderRadius: BorderRadius.circular(4)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning, color: Colors.white, size: 14),
            const SizedBox(width: 4),
            Text(alert, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        )
      );
    }
    return const SizedBox.shrink();
  }

  void _checkSLAAlerts() {
    urgentAlerts.clear();
    DateTime now = DateTime.now();

    for (var o in orders) {
      if (o.cvdvUsername != widget.login.userName) continue; 
      
      bool hasUnorderedMissingPart = false;
      if (o.parts != null && o.parts.toString().isNotEmpty && o.parts.toString() != '[]') {
         try {
            List pList = (o.parts is String) ? jsonDecode(o.parts) : List.from(o.parts);
            for (var raw in pList) {
               final p = Map<String, dynamic>.from(raw as Map);
               bool inStock = _mapIndicatesInStock(p);
               if (!inStock && !_mapIndicatesKhoRequested(p)) {
                  hasUnorderedMissingPart = true;
                  break;
               }
            }
         } catch(_) {}
      }

      if (hasUnorderedMissingPart) {
         urgentAlerts.add({
             'key': '${o.id}_unordered_parts', 
             'msg': 'CẢNH BÁO 7H30 SÁNG: Xe ${o.bienSo} có phụ tùng đang bị thiếu nhưng chưa được Đặt Hàng!'
         });
      }

      if (o.createdAt == null) continue;
      Duration diff = now.difference(o.createdAt!);
      String alertMsg = '';

      if (o.status == 'XE_VAO_XUONG' && diff.inMinutes >= 30) {
        alertMsg = 'Xe ${o.bienSo} đã vào xưởng >30 phút nhưng chưa lập Báo Giá!';
      }
      else if (o.status == 'DA_RA_CONG_THIEU_PT' && diff.inDays >= 3) {
        alertMsg = 'Xe ${o.bienSo} đang nợ phụ tùng Khách Hàng quá 3 ngày!';
      }
      else if (o.status == 'CHO_QD_KIEM_TRA' && diff.inHours >= 4) {
        alertMsg = 'Xe ${o.bienSo} đợi Quản Đốc kiểm tra chất lượng quá 4 tiếng!';
      }

      if (alertMsg.isNotEmpty) {
        String alertKey = '${o.id}_${o.status}';
        if (snoozedAlerts.containsKey(alertKey)) {
          if (now.difference(snoozedAlerts[alertKey]!).inHours >= 2) {
             urgentAlerts.add({'key': alertKey, 'msg': alertMsg});
          }
        } else {
           urgentAlerts.add({'key': alertKey, 'msg': alertMsg});
        }
      }
    }

    if (urgentAlerts.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showSLAAlertsDialog());
    }
  }

  void _showSLAAlertsDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [Icon(Icons.warning_amber, color: Colors.red, size: 30), SizedBox(width: 10), Text('CẢNH BÁO TIẾN ĐỘ', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))]),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: urgentAlerts.map((alert) => Container(
              margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.red.shade50, border: Border.all(color: Colors.red.shade200), borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                   Expanded(child: Text(alert['msg'], style: const TextStyle(fontWeight: FontWeight.bold))),
                   IconButton(icon: const Icon(Icons.close, color: Colors.grey), onPressed: () {
                     setState(() { snoozedAlerts[alert['key']] = DateTime.now(); urgentAlerts.remove(alert); });
                     Navigator.pop(ctx);
                     if (urgentAlerts.isNotEmpty) _showSLAAlertsDialog();
                   })
                ]
              )
            )).toList(),
          ),
        ),
        actions: [
           FilledButton(onPressed: () {
             for (var a in urgentAlerts) { snoozedAlerts[a['key']] = DateTime.now(); }
             setState(() { urgentAlerts.clear(); });
             Navigator.pop(ctx);
           }, style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('Đã hiểu & Tắt tất cả'))
        ],
      )
    );
  }

  Widget _buildSafeImage(String imageStr) {
    try {
      if (imageStr.startsWith('http://') || imageStr.startsWith('https://')) {
        return Image.network(imageStr, fit: BoxFit.cover, errorBuilder: (ctx, err, stack) => const Icon(Icons.broken_image, color: Colors.grey));
      } else if (imageStr.startsWith('data:image')) {
        final String base64Str = imageStr.split(',').last.replaceAll(RegExp(r'\s+'), '');
        final Uint8List bytes = base64Decode(base64Str);
        return Image.memory(bytes, fit: BoxFit.cover, errorBuilder: (ctx, err, stack) => const Icon(Icons.broken_image, color: Colors.grey));
      } else if (imageStr.startsWith('file://') || imageStr.startsWith('/')) {
        return buildVmFileImage(imageStr.replaceAll('file://', ''), fit: BoxFit.cover);
      } else {
        final String base64Str = imageStr.replaceAll(RegExp(r'\s+'), '');
        final Uint8List bytes = base64Decode(base64Str);
        return Image.memory(bytes, fit: BoxFit.cover, errorBuilder: (ctx, err, stack) => const Icon(Icons.broken_image, color: Colors.grey));
      }
    } catch(e) {
      debugPrint('Lỗi giải mã ảnh (Base64 bị hỏng): $e');
    }
    return const Center(child: Icon(Icons.error_outline, color: Colors.red, size: 40));
  }

  void _showFullScreenImage(String imageStr) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent, 
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer( 
              panEnabled: true,
              boundaryMargin: const EdgeInsets.all(20),
              minScale: 0.5,
              maxScale: 4,
              child: _buildSafeImage(imageStr)
            ),
            Positioned(
              top: 10, right: 10,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 32),
                onPressed: () => Navigator.pop(ctx),
              ),
            )
          ],
        )
      )
    );
  }

  void _showCarImagesDialog(WorkOrderItem order) {
    List<String> imageUrls = [];
    try {
      dynamic rawImages = (order as dynamic).images;
      if (rawImages != null && rawImages.toString() != 'null' && rawImages.toString() != '[]') {
         List<dynamic> parsedImages = (rawImages is String) ? jsonDecode(rawImages) : List.from(rawImages);
         imageUrls = parsedImages.map((e) => e.toString()).toList();
      }
    } catch(e) {}

    showDialog(
      context: context, 
      builder: (ctx) => AlertDialog(
        title: Text('Ảnh chụp xe: ${order.bienSo} lúc vào xưởng', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
        content: SizedBox(
          width: 600, height: 400,
          child: imageUrls.isEmpty 
            ? const Center(child: Text('Chưa có dữ liệu ảnh hoặc Bảo vệ chưa chụp ảnh cho xe này.', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)))
            : GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 4/3
                ),
                itemCount: imageUrls.length,
                itemBuilder: (context, index) {
                  return Material(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _showFullScreenImage(imageUrls[index]), 
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(borderRadius: BorderRadius.circular(8), child: _buildSafeImage(imageUrls[index])),
                          const Positioned(
                            bottom: 8, right: 8,
                            child: Icon(Icons.zoom_out_map, color: Colors.white70, size: 24)
                          )
                        ],
                      )
                    ),
                  );
                }
              ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng'))],
      )
    );
  }

  void _swapToPart(int jobIndex) {
     setState(() {
        final job = currentJobs[jobIndex];
        final part = PartItem();
        part.codeCtrl.text = job.codeCtrl.text;
        part.nameCtrl.text = job.nameCtrl.text;
        part.qtyCtrl.text = job.hoursCtrl.text;
        part.priceCtrl.text = job.priceCtrl.text;
        part.discountCtrl.text = job.discountCtrl.text;
        part.vatCtrl.text = job.vatCtrl.text;
        part.paymentMethod = job.paymentMethod;
        
        currentParts.add(part);
        currentJobs.removeAt(jobIndex);
     });
  }

  void _swapToJob(int partIndex) {
     setState(() {
        final part = currentParts[partIndex];
        final job = JobItem();
        job.codeCtrl.text = part.codeCtrl.text;
        job.nameCtrl.text = part.nameCtrl.text;
        job.hoursCtrl.text = part.qtyCtrl.text;
        job.priceCtrl.text = part.priceCtrl.text;
        job.discountCtrl.text = part.discountCtrl.text;
        job.vatCtrl.text = part.vatCtrl.text;
        job.paymentMethod = part.paymentMethod;
        
        currentJobs.add(job);
        currentParts.removeAt(partIndex);
     });
  }

  Future<void> _autoCheckInventory() async {
    if (currentParts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Danh sách phụ tùng đang trống!'), backgroundColor: Colors.orange));
      return;
    }
    
    setState(() => loading = true);
    
    List<Map<String, dynamic>> realInventory = await loadKhoInventoryMaps(
      api: api,
      token: widget.login.token,
    );

    List<String> outOfStockParts = [];
    List<String> inStockParts = [];
    bool hasUnorderedPart = false;

    final ro = _effectiveWoForKho();
    final bs = selectedOrder?.bienSo ?? '';

    setState(() {
      for (var part in currentParts) {
        String partCode = part.codeCtrl.text.trim().toLowerCase();
        double qtyNeeded = part.qty;
        bool foundInStock = false;
        
        if (partCode.isNotEmpty) {
           final avail = _qtyAvailableForRo(realInventory, partCode, ro, bs);
           if (avail >= qtyNeeded) {
             foundInStock = true;
           }
        }

        if (foundInStock) {
           part.inStock = true;
           inStockParts.add('${part.nameCtrl.text} (Mã: ${part.codeCtrl.text})');
        } else {
           part.inStock = false; 
           if (_partItemKhoRequested(part)) {
               outOfStockParts.add('${part.nameCtrl.text} (Mã: ${part.codeCtrl.text.isEmpty ? "Rỗng" : part.codeCtrl.text}) - Cần: $qtyNeeded [ĐANG CHỜ KHO NHẬP]');
           } else {
               outOfStockParts.add('${part.nameCtrl.text} (Mã: ${part.codeCtrl.text.isEmpty ? "Rỗng" : part.codeCtrl.text}) - Cần: $qtyNeeded');
               hasUnorderedPart = true;
           }
        }
      }
      loading = false;
    });

    if (mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(children: [Icon(Icons.inventory_2, color: Colors.blue), SizedBox(width: 8), Text('KẾT QUẢ KIỂM TRA KHO', style: TextStyle(fontWeight: FontWeight.bold))]),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Chỉ tính: tồn kho chung (WO trống và không gắn biển) + tồn giữ đúng RO hiện tại + tồn gắn đúng biển lệnh này. Không lấy tồn chỉ gắn biển/WO của xe khác.',
                    style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade700, height: 1.3),
                  ),
                  const SizedBox(height: 12),
                  if (outOfStockParts.isNotEmpty) ...[
                    const Text('🔴 KHÔNG SẴN CÓ (Cần nhập/Chờ hàng):', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                    const SizedBox(height: 4),
                    ...outOfStockParts.map((p) => Text('• $p', style: TextStyle(color: p.contains('[ĐANG CHỜ KHO NHẬP]') ? Colors.orange : Colors.red, fontStyle: p.contains('[ĐANG CHỜ KHO NHẬP]') ? FontStyle.italic : FontStyle.normal))),
                    const SizedBox(height: 16),
                  ],
                  if (inStockParts.isNotEmpty) ...[
                    const Text('🟢 ĐANG CÓ SẴN (Đủ tồn kho cho lệnh này):', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                    const SizedBox(height: 4),
                    ...inStockParts.map((p) => Text('• $p', style: const TextStyle(color: Colors.green))),
                  ]
                ],
              ),
            ),
          ),
          actions: [
            if (outOfStockParts.isNotEmpty && hasUnorderedPart)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.orange),
                onPressed: () async {
                  final invSnap = await loadKhoInventoryMaps(
                    api: api,
                    token: widget.login.token,
                  );
                  final ro0 = _effectiveWoForKho();
                  final bs0 = selectedOrder?.bienSo ?? '';
                  bool anyNeedNewOrder = false;
                  for (final p in currentParts) {
                    final c = p.codeCtrl.text.trim().toLowerCase();
                    if (c.isEmpty) continue;
                    final avail = _qtyAvailableForRo(invSnap, c, ro0, bs0);
                    if (avail < p.qty && !_partItemKhoRequested(p)) anyNeedNewOrder = true;
                  }
                  if (!anyNeedNewOrder) {
                    Navigator.pop(ctx);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text(
                          'Không có dòng phụ tùng thiếu nào cần báo KHO đặt mới (đã đặt hàng hoặc đủ tồn cho RO/biển này).',
                        ),
                        backgroundColor: Colors.orange,
                      ));
                    }
                    return;
                  }

                  final fp = _partsOrderFingerprint();
                  if (_fpAfterLastKhoBaoRequest != null &&
                      _fpAfterLastKhoBaoRequest == fp) {
                    Navigator.pop(ctx);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text(
                          'Đã gửi yêu cầu đặt hàng cho danh sách PT này. Chỉ gửi lại khi thêm/bớt dòng hoặc đổi số lượng phụ tùng.',
                        ),
                        backgroundColor: Colors.orange,
                      ));
                    }
                    return;
                  }
                  for (final p in currentParts) {
                    final c = p.codeCtrl.text.trim().toLowerCase();
                    if (c.isEmpty) continue;
                    if (_qtyAvailableForRo(invSnap, c, ro0, bs0) < p.qty) {
                      p.isOrdered = true;
                      if (p.khoBaoRequestedAt.trim().isEmpty) {
                        p.khoBaoRequestedAt = DateTime.now().toIso8601String();
                      }
                    }
                  }
                  Navigator.pop(ctx);
                  await _updateRoStatus(selectedOrder?.status ?? 'CHO_BAO_GIA');
                  if (mounted) {
                    setState(() {
                      _fpAfterLastKhoBaoRequest = fp;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Yêu cầu đặt đồ đã tự động báo sang màn hình của KHO!'),
                      backgroundColor: Colors.green,
                    ));
                  }
                },
                icon: const Icon(Icons.send_to_mobile),
                label: const Text('Báo sang KHO yêu cầu mua')
              ),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đã hiểu'))
          ],
        )
      );
    }
  }

  String _calculateSLA(DateTime? timeIn) => formatWaitSinceDateTime(timeIn, ifNull: 'Chưa rõ');

  Future<void> _handleLinkRequest(WorkOrderItem order, bool approve) async {
    setState(() => loading = true);
    try {
      await api.updateRepairOrder(token: widget.login.token, id: order.id, status: order.status, linkedCustomer: approve ? order.linkRequestedBy : '', linkRequestedBy: '');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(approve ? 'Đã cấp quyền cho Khách hàng' : 'Đã từ chối cấp quyền'), backgroundColor: approve ? Colors.green : Colors.red));
      await _loadBoard();
    } catch(e) {} finally { setState(() => loading = false); }
  }

  Future<void> _showNotificationsDialog() async {
    List<Map<String, dynamic>> serverNotifs = [];
    try {
      serverNotifs = await api.fetchNotifications(widget.login.token);
    } catch (_) {}

    final pendingOrders = orders.where((o) => _hasLinkRequest(o.linkRequestedBy)).toList();
    final unreadMsgOrders = orders.where((o) {
      try {
        if (o.chatLogs != null && o.chatLogs.toString() != '[]') {
          List logs = (o.chatLogs is String) ? jsonDecode(o.chatLogs) : List.from(o.chatLogs);
          if (logs.isNotEmpty && logs.last['role'] == 'Khách hàng') return true;
        }
      } catch (_) {}
      return false;
    }).toList();
    final ruleAlerts = _cvdvRuleAlerts();

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🔔 Thông báo', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
        content: SizedBox(
          width: 500,
          height: 400,
          child: (pendingOrders.isEmpty && unreadMsgOrders.isEmpty && ruleAlerts.isEmpty && serverNotifs.isEmpty) 
            ? const Center(child: Text('Không có thông báo mới.', style: TextStyle(color: Colors.grey)))
            : ListView(
                children: [
                  if (serverNotifs.isNotEmpty) ...[
                    const Padding(padding: EdgeInsets.all(8.0), child: Text('KHO / XƯỞNG / HỆ THỐNG:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal))),
                    ...serverNotifs.take(30).map((n) {
                      final unread = notificationIsUnread(n);
                      final type = notificationDataType(n);
                      final isParts = type == 'PARTS_READY_IN_SHOP';
                      final isQdDone = type == 'QD_INSPECTION_DONE_FOR_CVDV';
                      return ListTile(
                        dense: true,
                        tileColor: unread && isParts
                            ? Colors.teal.shade50
                            : (unread && isQdDone ? Colors.indigo.shade50 : null),
                        leading: Icon(
                          isParts
                              ? Icons.inventory_2
                              : (isQdDone ? Icons.verified_outlined : Icons.notifications),
                          color: isParts ? Colors.teal : (isQdDone ? Colors.indigo : Colors.blueGrey),
                          size: 28,
                        ),
                        title: Text(
                          n['title']?.toString() ?? '',
                          style: TextStyle(
                            fontWeight: unread ? FontWeight.bold : FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(n['body']?.toString() ?? '', style: const TextStyle(fontSize: 13)),
                        onTap: () async {
                          final nid = n['id']?.toString();
                          if (nid != null && nid.isNotEmpty) {
                            try {
                              await api.markNotificationRead(widget.login.token, nid);
                            } catch (_) {}
                          }
                          if (mounted) {
                            setState(() {
                              n['read_at'] = DateTime.now().toIso8601String();
                              _unreadNotifCount = serverNotifs.where(notificationIsUnread).length;
                            });
                          }
                        },
                      );
                    }),
                    const Divider(),
                  ],
                  if (ruleAlerts.isNotEmpty) ...[
                    const Padding(padding: EdgeInsets.all(8.0), child: Text('RULES CVDV / TIẾN ĐỘ:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange))),
                    ...ruleAlerts.map((t) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.policy, color: Colors.deepOrange, size: 28),
                      title: Text(t, style: const TextStyle(fontSize: 13)),
                    )),
                    const Divider(),
                  ],
                  if (pendingOrders.isNotEmpty) ...[
                    const Padding(padding: EdgeInsets.all(8.0), child: Text('YÊU CẦU LIÊN KẾT TÀI KHOẢN:', style: TextStyle(fontWeight: FontWeight.bold))),
                    ...pendingOrders.map((o) => ListTile(
                      leading: const Icon(Icons.directions_car, color: Colors.blue, size: 40),
                      title: Text('Xe ${o.bienSo} xin liên kết', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('SĐT: ${o.linkRequestedBy}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(onPressed: () { Navigator.pop(ctx); _handleLinkRequest(o, false); }, child: const Text('Từ chối', style: TextStyle(color: Colors.red))),
                          const SizedBox(width: 8),
                          FilledButton(onPressed: () { Navigator.pop(ctx); _handleLinkRequest(o, true); }, style: FilledButton.styleFrom(backgroundColor: Colors.green), child: const Text('Xác nhận')),
                        ],
                      ),
                    )),
                    const Divider(),
                  ],
                  if (unreadMsgOrders.isNotEmpty) ...[
                    const Padding(padding: EdgeInsets.all(8.0), child: Text('TIN NHẮN MỚI TỪ KHÁCH HÀNG:', style: TextStyle(fontWeight: FontWeight.bold))),
                    ...unreadMsgOrders.map((o) => ListTile(
                      leading: const Icon(Icons.message, color: Colors.blue, size: 40),
                      title: Text('Xe ${o.bienSo}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: const Text('Có tin nhắn mới chưa đọc'),
                      trailing: FilledButton(onPressed: () { Navigator.pop(ctx); setState(() { selectedOrder = o; }); _openChatDialog(); }, child: const Text('Xem')),
                    )),
                  ]
                ],
              ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng'))],
      )
    );
  }

  void _openChatDialog() {
    if (selectedOrder == null) return;
    final msgCtrl = TextEditingController();
    List<dynamic> logs = [];
    try { if (selectedOrder!.chatLogs != null && selectedOrder!.chatLogs.toString() != '[]') { logs = (selectedOrder!.chatLogs is String) ? jsonDecode(selectedOrder!.chatLogs) : List.from(selectedOrder!.chatLogs); } } catch (_) {}

    showDialog(
      context: context, 
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Text('Trao đổi Khách Hàng - RO: ${selectedOrder!.roCode}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
            content: SizedBox(
              width: 500, height: 400, 
              child: Column(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12)), 
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16), itemCount: logs.length, 
                        itemBuilder: (_, i) { 
                          bool isMe = logs[i]['sender'] == widget.login.userName; 
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12), alignment: isMe ? Alignment.centerRight : Alignment.centerLeft, 
                            child: Container(
                              padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: isMe ? Colors.blue[100] : Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[300]!)), 
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start, 
                                children: [
                                  Text('${logs[i]['sender']} (${logs[i]['role']})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey)), 
                                  const SizedBox(height: 4), Text(logs[i]['msg']), const SizedBox(height: 4), Text(logs[i]['time'].toString().substring(11, 16), style: const TextStyle(fontSize: 10, color: Colors.grey))
                                ]
                              )
                            )
                          ); 
                        }
                      )
                    )
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: TextField(controller: msgCtrl, decoration: const InputDecoration(hintText: 'Nhập tin nhắn để KH nhận được...', border: OutlineInputBorder()))), const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.send, color: Colors.blue), 
                        onPressed: () async { 
                          if (msgCtrl.text.trim().isEmpty) return; 
                          logs.add({'sender': widget.login.userName, 'role': 'CVDV', 'msg': msgCtrl.text.trim(), 'time': DateTime.now().toIso8601String()}); msgCtrl.clear(); selectedOrder!.chatLogs = jsonEncode(logs); setDialogState(() {}); await api.updateRepairOrder(token: widget.login.token, id: selectedOrder!.id, status: selectedOrder!.status, chatLogs: jsonEncode(logs)); _loadBoard(); 
                        }
                      )
                    ]
                  )
                ]
              )
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng'))],
          );
        }
      )
    );
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    if (phoneNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Khách hàng chưa cung cấp số điện thoại!'))); 
      return;
    }
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(launchUri)) { await launchUrl(launchUri); } 
    else { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thiết bị không hỗ trợ gọi điện.'))); }
  }

  double _parsePayCtrl(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '')) ?? 0;

  String? _insuranceCompanyFromNote() {
    final m = RegExp(r'\[BH:\s*([^\]]+)\]').firstMatch(urgentNotesCtrl.text);
    final s = m?.group(1)?.trim();
    return (s != null && s.isNotEmpty) ? s : null;
  }

  Map<String, dynamic> _paymentInfoPayload() => buildPaymentInfoPayload(
        customerPay: _parsePayCtrl(customerPayCtrl),
        insurancePay: _parsePayCtrl(insurancePayCtrl),
        warrantyPay: _parsePayCtrl(vinfastPayCtrl),
        debt: _parsePayCtrl(debtCtrl),
        grandTotal: grandTotal,
        insuranceCompany: _insuranceCompanyFromNote(),
      );

  void _loadPaymentFieldsFromOrder(WorkOrderItem item) {
    final p = parsePaymentInfo(item.paymentInfo);
    customerPayCtrl.text = formatPayAmount(p.customerPay);
    insurancePayCtrl.text = formatPayAmount(p.insurancePay);
    vinfastPayCtrl.text = formatPayAmount(p.warrantyPay);
    debtCtrl.text = formatPayAmount(p.debt);
  }

  bool _validatePayments() {
    double cPay = double.tryParse(customerPayCtrl.text.replaceAll(',', '')) ?? 0;
    double iPay = double.tryParse(insurancePayCtrl.text.replaceAll(',', '')) ?? 0;
    double wPay = double.tryParse(vinfastPayCtrl.text.replaceAll(',', '')) ?? 0;
    double dPay = double.tryParse(debtCtrl.text.replaceAll(',', '')) ?? 0;
    
    double totalPaymentInput = cPay + iPay + wPay + dPay;
    
    if (totalPaymentInput.round() != grandTotal.round()) {
        showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
                title: const Text('⚠️ NGUỒN THANH TOÁN ≠ TỔNG', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                content: Text(
                    "Tổng các nguồn thanh toán không khớp với Tổng thanh toán của Báo Giá!\n\n"
                    "• TỔNG BÁO GIÁ:\t\t${_formatVND(grandTotal)} đ\n"
                    "• TỔNG BẠN NHẬP:\t${_formatVND(totalPaymentInput)} đ\n\n"
                    "Vui lòng kiểm tra và điền lại các ô Nguồn Thanh Toán cho khớp tuyệt đối.",
                    style: const TextStyle(fontSize: 15, height: 1.5)
                ),
                actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Sửa lại'))]
            )
        );
        return false; 
    }
    return true;
  }

  // --- KIỂM TRA TỒN KHO TRƯỚC KHI CHO DUYỆT LỆNH SỬA CHỮA ---
  Future<void> _handleDispatchToTech() async {
     setState(() => loading = true);
     
     final realInventory = await loadKhoInventoryMaps(
       api: api,
       token: widget.login.token,
     );

     bool isBlocked = false;
     String blockMessage = '';

     final ro = _effectiveWoForKho();
     final bs = selectedOrder?.bienSo ?? '';

     for (var part in currentParts) {
        String partCode = part.codeCtrl.text.trim().toLowerCase();
        double qtyNeeded = part.qty;
        
        if (partCode.isNotEmpty) {
           final avail = _qtyAvailableForRo(realInventory, partCode, ro, bs);
           if (avail < qtyNeeded) {
              isBlocked = true;
              blockMessage = 'Phụ tùng ${part.nameCtrl.text} (Mã: ${part.codeCtrl.text}) không đủ tồn cho lệnh này (chỉ tính kho chung + tồn giữ đúng RO/biển số). Không thể phát lệnh sửa chữa ngay lúc này!';
              break;
           }
        }
     }

     if (isBlocked) {
         setState(() => loading = false);
         if (mounted) {
             showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                    title: const Row(children: [Icon(Icons.block, color: Colors.red), SizedBox(width: 8), Text('KHÔNG THỂ PHÁT LỆNH', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))]),
                    content: Text(blockMessage, style: const TextStyle(fontSize: 15, height: 1.5)),
                    actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đã hiểu'))]
                )
             );
         }
         return;
     }

     _updateRoStatus('CHO_PHAN_CONG');
  }

  Future<void> _handleInsuranceAndStatus(String targetStatus) async {
     if (targetStatus == 'CHO_QUYET_TOAN' && selectedOrder != null && !_orderPartsReadyForSettlement(selectedOrder!)) {
       if (!mounted) return;
       showDialog(
         context: context,
         builder: (ctx) => AlertDialog(
           title: const Row(
             children: [
               Icon(Icons.inventory_2_outlined, color: Colors.red),
               SizedBox(width: 8),
               Expanded(child: Text('Chưa đủ xuất kho', style: TextStyle(fontWeight: FontWeight.bold))),
             ],
           ),
           content: const Text(
             'Kho chưa xuất đủ phụ tùng theo báo giá (tab «Xuất kho» trên màn Kho).\n\n'
             'CVDV không thể chuyển kế toán cho đến khi Kho xác nhận xuất đủ.',
           ),
           actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đã hiểu'))],
         ),
       );
       return;
     }
     double iPay = double.tryParse(insurancePayCtrl.text.replaceAll(',', '')) ?? 0;
     if (iPay > 0 && (targetStatus == 'CHO_QUYET_TOAN' || targetStatus == 'DA_RA_CONG_THIEU_PT' || targetStatus == 'DA_RA_CONG')) {
         String selectedCompany = insuranceCompanies.first;
         final otherCompanyCtrl = TextEditingController();
         showDialog(
            context: context, barrierDismissible: false,
            builder: (ctx) => StatefulBuilder(builder: (context, setDialogState) {
                 return AlertDialog(
                    title: const Row(children: [Icon(Icons.shield, color: Colors.blue), SizedBox(width: 8), Text('CHỌN HÃNG BẢO HIỂM', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))]),
                    content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Xe này có thanh toán Bảo hiểm. Bắt buộc phải chọn hãng bảo hiểm để Kế toán hạch toán:'), const SizedBox(height: 16), Container(padding: const EdgeInsets.symmetric(horizontal: 12), decoration: BoxDecoration(border: Border.all(color: Colors.blue), borderRadius: BorderRadius.circular(8)), child: DropdownButtonHideUnderline(child: DropdownButton<String>(isExpanded: true, value: selectedCompany, onChanged: (val) { setDialogState(() { selectedCompany = val!; }); }, items: insuranceCompanies.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontWeight: FontWeight.bold)))).toList()))), if (selectedCompany == 'Khác') ...[const SizedBox(height: 16), TextField(controller: otherCompanyCtrl, decoration: const InputDecoration(labelText: 'Nhập tên hãng bảo hiểm khác', border: OutlineInputBorder()))]])),
                    actions: [ TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy thao tác')), FilledButton(onPressed: () { if (selectedCompany == 'Khác' && otherCompanyCtrl.text.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng nhập tên hãng bảo hiểm!'), backgroundColor: Colors.red)); return; } String finalCompany = selectedCompany == 'Khác' ? otherCompanyCtrl.text.trim() : selectedCompany; Navigator.pop(ctx); String note = urgentNotesCtrl.text.replaceAll(RegExp(r'\[BH:.*?\]'), '').trim(); urgentNotesCtrl.text = note.isEmpty ? '[BH: $finalCompany]' : '$note | [BH: $finalCompany]'; if (targetStatus == 'DA_RA_CONG_THIEU_PT') { _showMissingPartsDialog(); } else { _updateRoStatus(targetStatus); } }, child: const Text('XÁC NHẬN & TIẾP TỤC')) ]
                 );
              })
         );
     } else {
         if (targetStatus == 'DA_RA_CONG_THIEU_PT') { _showMissingPartsDialog(); } else { _updateRoStatus(targetStatus); }
     }
  }

  void _showMissingPartsDialog() {
    if (selectedOrder == null) return;
    List<bool> checkedParts = List.filled(currentParts.length, false);
    final noteCtrl = TextEditingController();
    showDialog(
      context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('Xác Nhận Xe Thiếu Phụ Tùng', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            content: SizedBox(width: 500, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Chọn các phụ tùng hiện đang bị thiếu/nợ Khách Hàng:'), const SizedBox(height: 16), if (currentParts.isEmpty) const Padding(padding: EdgeInsets.all(8.0), child: Text('Danh sách phụ tùng đang trống.', style: TextStyle(fontStyle: FontStyle.italic))) else Container(constraints: const BoxConstraints(maxHeight: 250), decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)), child: ListView.builder(shrinkWrap: true, itemCount: currentParts.length, itemBuilder: (context, index) { return CheckboxListTile(title: Text(currentParts[index].nameCtrl.text), subtitle: Text('Mã: ${currentParts[index].codeCtrl.text} | SL: ${currentParts[index].qtyCtrl.text}'), value: checkedParts[index], onChanged: (bool? value) { setDialogState(() { checkedParts[index] = value ?? false; }); }); })), const SizedBox(height: 16), TextField(controller: noteCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Ghi chú thêm cho Kế toán (Tùy chọn)', border: OutlineInputBorder()))])),
            actions: [ TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')), FilledButton.icon(onPressed: () { if (!_validatePayments()) return; List<String> missingNames = []; for (int i = 0; i < currentParts.length; i++) { if (checkedParts[i]) missingNames.add(currentParts[i].nameCtrl.text); } String extraNote = ""; if (missingNames.isNotEmpty) { extraNote = "[NỢ KHÁCH HÀNG] Thiếu: ${missingNames.join(', ')}."; } else { extraNote = "[KHÁCH LẤY XE VỀ, CHỜ PHỤ TÙNG]."; } if (noteCtrl.text.isNotEmpty) extraNote += " Ghi chú thêm: ${noteCtrl.text}"; String currentNote = urgentNotesCtrl.text.replaceAll(RegExp(r'\[NỢ KHÁCH HÀNG\].*?\.'), '').replaceAll(RegExp(r'\[KHÁCH LẤY XE VỀ.*?\.'), '').trim(); urgentNotesCtrl.text = currentNote.isEmpty ? extraNote : "$currentNote | $extraNote"; Navigator.pop(ctx); _updateRoStatus('CHO_QUYET_TOAN'); }, icon: const Icon(Icons.arrow_forward), style: FilledButton.styleFrom(backgroundColor: Colors.red), label: const Text('CHUYỂN KẾ TOÁN QUYẾT TOÁN')) ],
          );
        }
      )
    );
  }

  Future<void> _promptPauseReasonThenDungSua() async {
    if (selectedOrder == null) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lý do tạm dừng (DUNG_SUA)'),
        content: const Text('Chọn lý do theo Time Rules trước khi gửi lên máy chủ.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'CHO_PHU_TUNG'), child: const Text('Chờ phụ tùng')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'CHO_KH'), child: const Text('Chờ khách')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'CHO_BAO_HIEM'), child: const Text('Chờ bảo hiểm')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'KHAC'), child: const Text('Khác')),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    await _updateRoStatus('DUNG_SUA', pauseReason: choice);
  }

  bool _cvdvOpsFrozen() {
    final s = selectedOrder?.status ?? '';
    return s == 'HUY' || s == 'HUY_CHO_QUYET_TOAN' || s == 'KT_DUYET_RA_CONG';
  }

  Future<void> _confirmCustomerCancelNoRepair() async {
    if (selectedOrder == null || _cvdvOpsFrozen()) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('KH không sửa / Hủy lệnh'),
        content: const Text(
          'Xe sẽ chuyển sang Kế toán. Nếu không thu tiền, Kế toán phải bấm “Duyệt cho ra xưởng” thì Bảo vệ mới được mở cổng cho xe ra.\n\nTiếp tục?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Quay lại')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Xác nhận')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final ts = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    final stamp = '[KH HỦY / KHÔNG SỬA — $ts]';
    final cur = urgentNotesCtrl.text.trim();
    if (cur.isEmpty) {
      urgentNotesCtrl.text = stamp;
    } else if (!cur.contains('[KH HỦY / KHÔNG SỬA')) {
      urgentNotesCtrl.text = '$stamp $cur';
    }
    await _updateRoStatus('HUY_CHO_QUYET_TOAN');
  }

  Future<void> _updateRoStatus(String targetStatus, {String? pauseReason}) async {
    if (selectedOrder == null) return;
    if (targetStatus == 'CHO_QUYET_TOAN' && !_orderPartsReadyForSettlement(selectedOrder!)) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.inventory_2_outlined, color: Colors.red),
              SizedBox(width: 8),
              Expanded(child: Text('Chưa đủ xuất kho', style: TextStyle(fontWeight: FontWeight.bold))),
            ],
          ),
          content: const Text(
            'Kho chưa xuất đủ phụ tùng theo báo giá (tab «Xuất kho» trên màn Kho).\n\n'
            'CVDV không thể chuyển kế toán cho đến khi Kho xác nhận xuất đủ.',
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đã hiểu'))],
        ),
      );
      return;
    }
    setState(() => loading = true);
    try {
      final jobsJson = jsonEncode(currentJobs.map((e) => {'code': e.codeCtrl.text, 'name': e.nameCtrl.text, 'hours': e.qty, 'price': e.price, 'discount': e.discount, 'vat': e.vatRate, 'note': e.noteCtrl.text, 'total': e.totalWithVat, 'paymentMethod': e.paymentMethod}).toList());
      final partsJson = jsonEncode(currentParts.map((e) {
        final hadKho = _partItemKhoRequested(e);
        return {
          'code': e.codeCtrl.text,
          'name': e.nameCtrl.text,
          'qty': e.qty,
          'price': e.price,
          'discount': e.discount,
          'vat': e.vatRate,
          'note': e.noteCtrl.text,
          'total': e.totalWithVat,
          'paymentMethod': e.paymentMethod,
          'inStock': e.inStock,
          'in_stock': e.inStock,
          'issuedQty': _preservedIssuedQtyForPart(e),
          'issued_qty': _preservedIssuedQtyForPart(e),
          'isOrdered': hadKho,
          'is_ordered': hadKho,
          'khoBaoRequestedAt': e.khoBaoRequestedAt,
          'kho_bao_requested_at': e.khoBaoRequestedAt,
        };
      }).toList());

      await api.updateRepairOrder(
        token: widget.login.token,
        id: selectedOrder!.id,
        status: targetStatus,
        jobs: jobsJson,
        parts: partsJson,
        statusNote: urgentNotesCtrl.text,
        pauseReason: pauseReason,
        cvdvWoCode: cvdvWoCodeCtrl.text.trim(),
        vehicleActivity: vehicleActivityCtrl.text.trim(),
        paymentInfo: _paymentInfoPayload(),
      );
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã cập nhật dữ liệu thành công!'), backgroundColor: Colors.green)); }
      await _loadBoard();
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red)); } finally { setState(() => loading = false); }
  }

  double get subTotal => currentJobs.fold(0.0, (sum, item) => sum + item.totalAfterDiscount) + currentParts.fold(0.0, (sum, item) => sum + item.totalAfterDiscount);
  double get totalVat => currentJobs.fold(0.0, (sum, item) => sum + item.vatAmount) + currentParts.fold(0.0, (sum, item) => sum + item.vatAmount);
  double get grandTotal => subTotal + totalVat;
  String _formatVND(double value) { return value.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},'); }

  String _decodeBytesToString(List<int> bytes) {
    if (bytes.isEmpty) return '';
    try {
      if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
        StringBuffer sb = StringBuffer(); for (int i = 2; i < bytes.length - 1; i += 2) sb.writeCharCode(bytes[i] | (bytes[i + 1] << 8)); return sb.toString();
      }
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) { return String.fromCharCodes(bytes); }
  }

  String _getXmlAttr(String attrs, String attrName) { RegExp reg = RegExp(attrName + r'\s*=\s*"([^"]*)"'); var match = reg.firstMatch(attrs); return match != null ? match.group(1) ?? '' : ''; }
  
  double? _parseNumberStrict(String? raw) { 
    if (raw == null || raw.isEmpty) return null;
    try {
      String clean = raw.replaceAll(RegExp(r'[^\d.,\-]'), ''); 
      if (clean.isEmpty || clean == '.' || clean == ',') return null; 
      if (clean.contains(',') && !clean.contains('.')) { if (clean.split(',').last.length <= 2) clean = clean.replaceAll(',', '.'); else clean = clean.replaceAll(',', ''); } 
      else if (clean.contains('.') && clean.contains(',')) { int dotIdx = clean.lastIndexOf('.'); int commaIdx = clean.lastIndexOf(','); if (dotIdx > commaIdx) clean = clean.replaceAll(',', ''); else clean = clean.replaceAll('.', '').replaceAll(',', '.'); } 
      else if (clean.contains('.')) { if (clean.split('.').last.length == 3) clean = clean.replaceAll('.', ''); }
      return double.tryParse(clean); 
    } catch(_) { return null; }
  }
  
  String _extractCellString(dynamic cell) {
    if (cell == null) return '';
    try {
      dynamic val = cell; try { if (cell.value == null) return ''; val = cell.value; } catch(_) {} 
      String s = val.toString(); RegExp reg = RegExp(r'^[A-Za-z]+CellValue\((?:value:\s*)?(.*?)\)$', dotAll: true);
      if (reg.hasMatch(s)) s = reg.firstMatch(s)?.group(1) ?? s;
      if (s.startsWith('"') && s.endsWith('"') && s.length >= 2) s = s.substring(1, s.length - 1);
      return s.replaceAll('\x00', '').trim();
    } catch (_) { return ''; }
  }

  List<List<String>> _parseHtmlOrXmlTable(String content) {
    if (content.isEmpty) return []; List<List<String>> rows = [];
    RegExp rowRegex = RegExp(r'<(?:tr|Row)(?:\s+[^>]*)?>(.*?)<\/(?:tr|Row)>', caseSensitive: false, dotAll: true);
    for (var r in rowRegex.allMatches(content)) {
        String rowHtml = r.group(1) ?? ''; List<String> cells = [];
        RegExp cellRegex = RegExp(r'<(?:td|th|Cell)(?:\s+[^>]*)?>(.*?)<\/(?:td|th|Cell)>', caseSensitive: false, dotAll: true);
        for (var c in cellRegex.allMatches(rowHtml)) { String text = c.group(1) ?? ''; text = text.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll('&nbsp;', ' ').trim().replaceAll(RegExp(r'\s+'), ' '); cells.add(text); }
        if (cells.isNotEmpty && cells.any((e) => e.isNotEmpty)) rows.add(cells);
    }
    return rows;
  }

  List<List<String>> _parseCsvSimpleText(String content) {
    if (content.isEmpty) return []; content = content.replaceAll('\x00', ''); List<List<String>> rows = [];
    List<String> lines = content.split(RegExp(r'\r\n|\n|\r'));
    for (String line in lines) {
        if (line.trim().isEmpty) continue;
        int comma = line.split(',').length; int semi = line.split(';').length; int tab = line.split('\t').length;
        String d = ','; if (semi > comma && semi > tab) d = ';'; else if (tab > comma && tab > semi) d = '\t';
        List<String> cells = line.split(d).map((e) { String c = e.trim(); if (c.startsWith('"') && c.endsWith('"') && c.length >= 2) c = c.substring(1, c.length - 1); return c.trim(); }).toList();
        if (cells.isNotEmpty) rows.add(cells);
    }
    return rows;
  }

  void _parseMisaLogic(List<List<String>> allRows) {
    for (var rawRow in allRows) {
      try {
        if (rawRow.length < 2) continue;
        List<String> cells = [];
        for (var e in rawRow) { String c = _extractCellString(e).replaceAll('\n', ' ').trim(); if (c.isNotEmpty && c.toLowerCase() != 'nan' && c.toLowerCase() != 'null') cells.add(c); }
        if (cells.length < 2) continue;
        String fullRow = cells.join(' ').toLowerCase();

        if (fullRow.contains('khách hàng thanh toán') || fullRow.contains('tổng chi phí') || fullRow.contains('bằng chữ') || fullRow.contains('người lập phiếu')) break; 
        if (fullRow.contains('số phiếu:') || fullRow.contains('biển số') || fullRow.contains('tên chủ xe') || fullRow.contains('địa chỉ') || fullRow.contains('điện thoại:') || fullRow.contains('người mang xe') || fullRow.contains('mst:') || fullRow.contains('số km') || fullRow.contains('yêu cầu khách hàng') || fullRow.contains('thời gian') || fullRow.contains('ngày') || fullRow.contains('tổng cộng') || fullRow.contains('tên phụ tùng') || fullRow.contains('mã phụ tùng') || fullRow == 'sơn' || fullRow == 'thuế ngoài' || fullRow == 'phụ tùng' || fullRow.contains('tổng tiền:') || fullRow.contains('nội dung công việc') || (fullRow.contains('bảo dưỡng') && cells.length < 3) || fullRow == 'công việc' || fullRow.contains('đơn giá') || fullRow.contains('thành tiền')) continue;

        while (cells.isNotEmpty) { String first = cells[0].trim(); if (first.length <= 2 && int.tryParse(first) != null) cells.removeAt(0); else if (first.toLowerCase() == 'stt') cells.removeAt(0); else break; }
        if (cells.length < 2) continue;

        int nameEndIdx = -1;
        List<String> units = ['cái', 'bộ', 'lần', 'giờ', 'lít', 'chai', 'hộp', 'cuộn', 'mét', 'kg', 'chiếc', 'tuýp', 'thùng', 'c', 'i', 'cuốn', 'bình', 'ml', 'gram'];
        for (int i = cells.length - 1; i >= 0; i--) {
            String c = cells[i].toLowerCase(); if (units.contains(c)) continue;
            String cleanForNum = c.replaceAll('%', '').replaceAll('đ', '').replaceAll('vnd', '').replaceAll(',', '').replaceAll('.', '').trim();
            if (double.tryParse(cleanForNum) == null || RegExp(r'[a-zà-ỹA-ZÀ-Ỹ]').hasMatch(c)) { nameEndIdx = i + 1; break; }
        }

        if (nameEndIdx <= 0 || nameEndIdx >= cells.length) continue; 
        List<String> textParts = []; if (nameEndIdx <= cells.length) { textParts = cells.sublist(0, nameEndIdx); }
        while(textParts.isNotEmpty && units.contains(textParts.last.toLowerCase())) textParts.removeLast();
        if (textParts.isEmpty) continue;

        String code = ''; String name = '';
        if (textParts.length > 1 && (textParts[0].contains(RegExp(r'[0-9]')) && textParts[0].length >= 3 || textParts[0].toUpperCase() == textParts[0] && !textParts[0].contains(' ') && textParts[0].length > 3 || textParts[0].contains('-') || textParts[0].contains('_'))) { code = textParts[0]; if (textParts.length > 1) { name = textParts.sublist(1).join(' ').trim(); } } else { name = textParts.join(' ').trim(); }
        if (name.isEmpty || name.length < 2) continue;

        List<String> finParts = []; if (nameEndIdx < cells.length) { finParts = cells.sublist(nameEndIdx); }
        List<double> largeNums = []; List<double> smallNums = []; List<double> pcts = []; String httt = 'C';

        for (String c in finParts) {
            String cl = c.toLowerCase(); if (units.contains(cl)) continue;
            if (['c', 'i', 'w'].contains(cl)) { httt = cl.toUpperCase(); continue; }
            if (cl.contains('%')) { double? p = double.tryParse(cl.replaceAll('%', '').replaceAll(',', '.')); if (p != null) pcts.add(p); } else { double? val = double.tryParse(cl.replaceAll('đ', '').replaceAll('vnd', '').replaceAll(',', '').replaceAll('.', '')); if (val != null) { if (val >= 1000) largeNums.add(val); else if (val >= 0) smallNums.add(val); } }
        }

        if (largeNums.isEmpty) continue; 
        double price = largeNums.first; double total = largeNums.last; double qty = 1; double vat = 8; double ck = 0; bool isFree = pcts.contains(100.0);

        if (isFree) { total = 0; if (smallNums.isNotEmpty) qty = smallNums.first; ck = price * qty; } else if (price > 0 && total > 0) {
            bool isOne = false; if ((price - total).abs() < 5) isOne = true;
            for(double p in pcts) { if ((price * (1 - p/100) - total).abs() < 5) isOne = true; }
            if (largeNums.length >= 3 && (price - largeNums[1] - total).abs() < 5) isOne = true;

            if (isOne) { qty = 1; } else {
                bool foundQty = false;
                for (double n in smallNums) {
                    if ((price * n - total).abs() < 5) { qty = n; foundQty = true; break; }
                    for(double p in pcts) { if ((price * n * (1 - p/100) - total).abs() < 5) { qty = n; foundQty = true; break; } }
                    if (largeNums.length >= 3 && (price * n - largeNums[1] - total).abs() < 5) { qty = n; foundQty = true; break; }
                }
                if (!foundQty && smallNums.isNotEmpty) qty = smallNums.first;
            }
        } else if (smallNums.isNotEmpty) { qty = smallNums.first; }

        if (pcts.isNotEmpty) { if (pcts.last == 8 || pcts.last == 10) vat = pcts.last; }
        if (!isFree) {
            if (pcts.isNotEmpty) { for(double p in pcts) { if (p != 8 && p != 10 && p != 100) { ck = price * qty * (p / 100); break; } } if (ck == 0 && pcts.length >= 2 && pcts.first == 10) ck = price * qty * 0.1; }
            if (ck == 0 && largeNums.length >= 3 && (price * qty - largeNums[1] - total).abs() < 5) ck = largeNums[1]; else if (ck == 0 && total >= 0 && total < price * qty) ck = (price * qty) - total;
        }

        bool isJob = name.toLowerCase().contains('công') || name.toLowerCase().contains('thay') || name.toLowerCase().contains('sơn') || name.toLowerCase().contains('bảo dưỡng') || name.toLowerCase().contains('gò') || name.toLowerCase().contains('kiểm tra') || name.toLowerCase().contains('vệ sinh') || code.toUpperCase().contains('LABOR');

        if (isJob) { final job = JobItem(); job.codeCtrl.text = code; job.nameCtrl.text = name; job.hoursCtrl.text = qty.toStringAsFixed(1).replaceAll('.0',''); job.priceCtrl.text = price.toStringAsFixed(0); job.discountCtrl.text = ck.toStringAsFixed(0); job.vatCtrl.text = vat.toStringAsFixed(0); job.paymentMethod = httt; currentJobs.add(job); } 
        else { final part = PartItem(); part.codeCtrl.text = code; part.nameCtrl.text = name; part.qtyCtrl.text = qty.toStringAsFixed(1).replaceAll('.0',''); part.priceCtrl.text = price.toStringAsFixed(0); part.discountCtrl.text = ck.toStringAsFixed(0); part.vatCtrl.text = vat.toStringAsFixed(0); part.paymentMethod = httt; currentParts.add(part); }
      } catch (e) {}
    }
  }

  Future<void> _importMisa() async {
    if (selectedOrder == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng chọn 1 xe trước khi import MISA!'), backgroundColor: Colors.red)); return; }
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv', 'html', 'xml'],
        withData: true,
      );
      if (result != null) {
        setState(() => loading = true);
        final picked = await bytesFromPickerFile(result.files.single);
        if (picked == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Không đọc được file — chọn lại.'), backgroundColor: Colors.red),
            );
          }
          setState(() => loading = false);
          return;
        }
        var bytes = picked; 
        _clearFormsRaw(); 
        List<List<String>> excelRows = [];
        String fileContent = _decodeBytesToString(bytes);
        bool isXmlParsed = false;
        RegExp detailsRegExp = RegExp(r'<(Details\d*)\s+([^>]+)>');

        if (detailsRegExp.hasMatch(fileContent)) {
           for (var match in detailsRegExp.allMatches(fileContent)) {
               String attrs = match.group(2) ?? '';
               String code = _getXmlAttr(attrs, 'wps_xts_productid'); if (code.isEmpty) code = _getXmlAttr(attrs, 'Textbox140');
               String name = _getXmlAttr(attrs, 'wps_xts_productdescription'); if (name.isEmpty) name = _getXmlAttr(attrs, 'Textbox142');
               String qtyStr = _getXmlAttr(attrs, 'Textbox144').replaceAll(',', '.'); if (qtyStr.isEmpty) qtyStr = '1'; 
               String priceStr = _getXmlAttr(attrs, 'wps_xts_totalamountbeforediscountValue'); if (priceStr.isEmpty) priceStr = _getXmlAttr(attrs, 'Textbox146'); if (priceStr.isEmpty) priceStr = _getXmlAttr(attrs, 'ac_xts_provinceidEntityName'); 
               String discountStr = _getXmlAttr(attrs, 'wps_xts_discountpercentValue'); if (discountStr.isEmpty) discountStr = _getXmlAttr(attrs, 'wps_xts_discountpercentValue1');
               String vatStr = _getXmlAttr(attrs, 'Textbox38'); if (vatStr.isEmpty) vatStr = _getXmlAttr(attrs, 'Textbox165');

               if (name.isEmpty || priceStr.isEmpty) continue;
               double price = double.tryParse(priceStr) ?? 0; double qty = double.tryParse(qtyStr) ?? 1; double discount = 0;
               if (discountStr.contains('%')) { double pct = double.tryParse(discountStr.replaceAll('%','')) ?? 0; discount = price * qty * (pct/100); } else if (discountStr.isNotEmpty) discount = double.tryParse(discountStr) ?? 0;
               double vat = double.tryParse(vatStr.replaceAll('%','')) ?? 8;

               if (price > 0 || name.isNotEmpty) {
                   bool isJob = name.toLowerCase().contains('công') || name.toLowerCase().contains('sơn') || name.toLowerCase().contains('bảo dưỡng') || name.toLowerCase().contains('thay') || name.toLowerCase().contains('gò') || name.toLowerCase().contains('vệ sinh') || code.toUpperCase().contains('LABOR');
                   if (isJob) { final job = JobItem(); job.codeCtrl.text = code; job.nameCtrl.text = name; job.hoursCtrl.text = qty.toStringAsFixed(1).replaceAll('.0',''); job.priceCtrl.text = price.toStringAsFixed(0); job.discountCtrl.text = discount.toStringAsFixed(0); job.vatCtrl.text = vat.toStringAsFixed(0); currentJobs.add(job); isXmlParsed = true; } 
                   else { final part = PartItem(); part.codeCtrl.text = code; part.nameCtrl.text = name; part.qtyCtrl.text = qty.toStringAsFixed(1).replaceAll('.0',''); part.priceCtrl.text = price.toStringAsFixed(0); part.discountCtrl.text = discount.toStringAsFixed(0); part.vatCtrl.text = vat.toStringAsFixed(0); currentParts.add(part); isXmlParsed = true; }
               }
           }
        }

        if (!isXmlParsed) {
            bool isExcel = bytes.length > 2 && bytes[0] == 0x50 && bytes[1] == 0x4B;
            if (isExcel) { try { var excel = Excel.decodeBytes(bytes); for (var table in excel.tables.values) { for(var row in table.rows) { excelRows.add(row.map((e) => e?.value?.toString() ?? '').toList()); } } } catch (_) { } }
            if (excelRows.isEmpty) { if (fileContent.toLowerCase().contains('<table') || fileContent.toLowerCase().contains('<?xml')) { excelRows = _parseHtmlOrXmlTable(fileContent); } else { excelRows = _parseCsvSimpleText(fileContent); } }
            _parseMisaLogic(excelRows);
        }

        if (mounted) {
           if (currentJobs.isEmpty && currentParts.isEmpty) { showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('⚠️ KHÔNG TÌM THẤY DỮ LIỆU MISA', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)), content: const Text("App không thể trích xuất dữ liệu từ file MISA này."), actions: [FilledButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('Đã Hiểu'))])); } 
           else { setState(() {}); customerPayCtrl.text = grandTotal.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},'); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import MISA Thành Công! Đã bốc ${currentJobs.length} CV và ${currentParts.length} PT.'), backgroundColor: Colors.green)); }
        }
      }
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: File đang bị mở!'), backgroundColor: Colors.red)); } finally { setState(() => loading = false); }
  }

  Future<void> _importDms() async {
    if (selectedOrder == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng chọn 1 xe trước khi import DMS!'), backgroundColor: Colors.red)); return; }
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['docx', 'xml', 'csv', 'xlsx', 'xls'],
        withData: true,
      );
      if (result != null) {
        setState(() => loading = true);
        final picked = await bytesFromPickerFile(result.files.single);
        if (picked == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Không đọc được file — chọn lại.'), backgroundColor: Colors.red),
            );
          }
          setState(() => loading = false);
          return;
        }
        var bytes = picked;
        String extension = result.files.single.extension?.toLowerCase() ?? ''; _clearFormsRaw(); bool isParsed = false;
        if (extension == 'docx') {
             List<List<String>> allRows = [];
             try { final archive = ZipDecoder().decodeBytes(bytes); ArchiveFile? docXmlFile; for (final file in archive) { if (file.name == 'word/document.xml') { docXmlFile = file; break; } }
                if (docXmlFile != null) { final content = utf8.decode(docXmlFile.content as List<int>); RegExp trRegex = RegExp(r'<w:tr(?:[^>]*)>(.*?)</w:tr>');
                    for (var trMatch in trRegex.allMatches(content)) { String trContent = trMatch.group(1) ?? ''; List<String> rowCells = []; RegExp tcRegex = RegExp(r'<w:tc(?:[^>]*)>(.*?)</w:tc>');
                        for (var tcMatch in tcRegex.allMatches(trContent)) { String tcContent = tcMatch.group(1) ?? ''; RegExp tRegex = RegExp(r'<w:t(?:[^>]*)>([^<]*)</w:t>'); String cellText = tRegex.allMatches(tcContent).map((m) => m.group(1) ?? '').join(' ').trim(); rowCells.add(cellText); }
                        if (rowCells.isNotEmpty) allRows.add(rowCells);
                    }
                }
             } catch (e) {}

             for (var rowCells in allRows) {
                 if (rowCells.length < 5) continue; String joinedRow = rowCells.join(' ').toLowerCase();
                 if (joinedRow.contains('khách hàng thanh toán') || joinedRow.contains('chi phí') || joinedRow.contains('bằng chữ') || joinedRow.contains('người lập')) { break; }
                 if (joinedRow.contains('tổng cộng') || joinedRow.contains('stt') || joinedRow.contains('thành tiền')) continue;
                 String code = ''; String name = ''; int startIdx = 1; 
                 if (rowCells[1].length > 3 && rowCells[1].toUpperCase() == rowCells[1]) { code = rowCells[1].trim(); name = rowCells[2].trim(); startIdx = 3; } else if (rowCells[1].length > 5) { name = rowCells[1].trim(); startIdx = 2; } else { for (int i=1; i<4; i++) { if(rowCells[i].length > 5 && !rowCells[i].contains(RegExp(r'[0-9]'))) { name = rowCells[i]; startIdx = i+1; break; } } }
                 if (name.isEmpty || name.toLowerCase() == 'nan') continue;

                 List<double> numbers = []; List<double> pcts = []; String httt = 'C'; String lastCell = rowCells.last.trim().toUpperCase();
                 if (['C', 'I', 'W'].contains(lastCell)) { httt = lastCell; }

                 for (int i = startIdx; i < rowCells.length; i++) { String cell = rowCells[i].toLowerCase().trim(); if (cell.isEmpty) continue; if (['c', 'i', 'w'].contains(cell)) continue; if (cell.contains('%')) { double? p = double.tryParse(cell.replaceAll('%','').replaceAll(',','.')); if (p != null) pcts.add(p); } else { double? val = _parseNumberStrict(cell); if (val != null) numbers.add(val); } }

                 List<double> largeNums = numbers.where((n) => n >= 1000).toList(); List<double> smallNums = numbers.where((n) => n > 0 && n < 1000).toList();
                 if (largeNums.isNotEmpty) {
                      double price = largeNums.first; double total = largeNums.length > 1 ? largeNums.last : price; double qty = 1; double vat = 8; double discount = 0;
                      if (smallNums.isNotEmpty) qty = smallNums.first;
                      if (pcts.contains(100.0)) { discount = price * qty; total = 0; } else if (price * qty > total && total > 0) { discount = (price * qty) - total; }
                      if (pcts.contains(10.0)) vat = 10; else if (pcts.contains(8.0)) vat = 8;
                      bool isJob = name.toLowerCase().contains('công') || name.toLowerCase().contains('thay') || name.toLowerCase().contains('sơn') || name.toLowerCase().contains('bảo dưỡng') || name.toLowerCase().contains('kiểm tra') || name.toLowerCase().contains('vệ sinh') || code.toUpperCase().contains('LABOR') || code.toUpperCase().contains('ALL');
                      bool isDuplicate = currentJobs.any((j) => j.nameCtrl.text == name && j.priceCtrl.text == price.toStringAsFixed(0)) || currentParts.any((p) => p.nameCtrl.text == name && p.priceCtrl.text == price.toStringAsFixed(0));
                      if (!isDuplicate) { if (isJob) { final job = JobItem(); job.codeCtrl.text = code; job.nameCtrl.text = name; job.hoursCtrl.text = qty.toStringAsFixed(1).replaceAll('.0',''); job.priceCtrl.text = price.toStringAsFixed(0); job.discountCtrl.text = discount.toStringAsFixed(0); job.vatCtrl.text = vat.toStringAsFixed(0); job.paymentMethod = httt; currentJobs.add(job); isParsed = true; } else { final part = PartItem(); part.codeCtrl.text = code; part.nameCtrl.text = name; part.qtyCtrl.text = qty.toStringAsFixed(1).replaceAll('.0',''); part.priceCtrl.text = price.toStringAsFixed(0); part.discountCtrl.text = discount.toStringAsFixed(0); part.vatCtrl.text = vat.toStringAsFixed(0); part.paymentMethod = httt; currentParts.add(part); isParsed = true; } }
                 }
             }
        } else {
             String fileContent = _decodeBytesToString(bytes); RegExp detailsRegExp = RegExp(r'<(Details\d*)\s+([^>]+)>');
             if (detailsRegExp.hasMatch(fileContent)) {
                 for (var match in detailsRegExp.allMatches(fileContent)) {
                     String attrs = match.group(2) ?? ''; String code = _getXmlAttr(attrs, 'wps_xts_productid'); if (code.isEmpty) code = _getXmlAttr(attrs, 'Textbox140');
                     String name = _getXmlAttr(attrs, 'wps_xts_productdescription'); if (name.isEmpty) name = _getXmlAttr(attrs, 'Textbox142');
                     String qtyStr = _getXmlAttr(attrs, 'Textbox144').replaceAll(',', '.'); if (qtyStr.isEmpty) qtyStr = '1'; 
                     String priceStr = _getXmlAttr(attrs, 'wps_xts_totalamountbeforediscountValue'); if (priceStr.isEmpty) priceStr = _getXmlAttr(attrs, 'Textbox146'); if (priceStr.isEmpty) priceStr = _getXmlAttr(attrs, 'ac_xts_provinceidEntityName'); 
                     String discountStr = _getXmlAttr(attrs, 'wps_xts_discountpercentValue'); if (discountStr.isEmpty) discountStr = _getXmlAttr(attrs, 'wps_xts_discountpercentValue1');
                     String vatStr = _getXmlAttr(attrs, 'Textbox38'); if (vatStr.isEmpty) vatStr = _getXmlAttr(attrs, 'Textbox165');

                     if (name.isEmpty || priceStr.isEmpty) continue;
                     double price = double.tryParse(priceStr) ?? 0; double qty = double.tryParse(qtyStr) ?? 1; double discount = 0;
                     if (discountStr.contains('%')) { double pct = double.tryParse(discountStr.replaceAll('%','')) ?? 0; discount = price * qty * (pct/100); } else if (discountStr.isNotEmpty) discount = double.tryParse(discountStr) ?? 0;
                     double vat = double.tryParse(vatStr.replaceAll('%','')) ?? 8;

                     if (price > 0 || name.isNotEmpty) {
                         bool isJob = name.toLowerCase().contains('công') || name.toLowerCase().contains('sơn') || name.toLowerCase().contains('bảo dưỡng') || name.toLowerCase().contains('thay') || name.toLowerCase().contains('gò') || name.toLowerCase().contains('vệ sinh') || code.toUpperCase().contains('LABOR');
                         if (isJob) { final job = JobItem(); job.codeCtrl.text = code; job.nameCtrl.text = name; job.hoursCtrl.text = qty.toStringAsFixed(1).replaceAll('.0',''); job.priceCtrl.text = price.toStringAsFixed(0); job.discountCtrl.text = discount.toStringAsFixed(0); job.vatCtrl.text = vat.toStringAsFixed(0); currentJobs.add(job); isParsed = true; } 
                         else { final part = PartItem(); part.codeCtrl.text = code; part.nameCtrl.text = name; part.qtyCtrl.text = qty.toStringAsFixed(1).replaceAll('.0',''); part.priceCtrl.text = price.toStringAsFixed(0); part.discountCtrl.text = discount.toStringAsFixed(0); part.vatCtrl.text = vat.toStringAsFixed(0); currentParts.add(part); isParsed = true; }
                     }
                 }
             }
        }

        if (mounted) {
           if (!isParsed) { showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('⚠️ KHÔNG ĐỌC ĐƯỢC DỮ LIỆU DMS', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)), content: const SizedBox(width: 400, child: Text("Hệ thống DMS xuất dữ liệu ẩn không cho phép đọc qua Excel.\n\n👉 GIẢI PHÁP 100%:\n1. Mở phần mềm DMS, khi bấm xuất báo giá, hãy chọn ĐỊNH DẠNG WORD (.docx) thay vì Excel.\n2. Bấm Import DMS và chọn file Word đó.\nHoặc xuất định dạng XML (Data Feed).", style: TextStyle(fontSize: 14, height: 1.5))), actions: [FilledButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('Đã Hiểu'))])); } 
           else { setState(() {}); customerPayCtrl.text = grandTotal.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},'); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import DMS Thành Công! Đã bốc ${currentJobs.length} CV và ${currentParts.length} PT.'), backgroundColor: Colors.green)); }
        }
      }
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: Hãy chắc chắn bạn đã chọn file Word (.docx) hoặc file đang bị mở!'), backgroundColor: Colors.red)); } finally { setState(() => loading = false); }
  }

  Future<void> _importUnitMap() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
        withData: true,
      );
      if (result != null) {
        setState(() => loading = true);
        final picked = await bytesFromPickerFile(result.files.single);
        if (picked == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Không đọc được file — chọn lại.'), backgroundColor: Colors.red),
            );
          }
          setState(() => loading = false);
          return;
        }
        var bytes = picked;
        String extension = result.files.single.extension?.toLowerCase() ?? '';
        int count = 0;
        if (extension == 'csv') {
          String content = _decodeBytesToString(bytes);
          List<List<String>> rows = _parseCsvSimpleText(content);
          for (int i = 1; i < rows.length; i++) {
            if (rows[i].length >= 4) {
              String code = rows[i][1].trim(); String unit = rows[i][3].trim(); 
              if (code.isNotEmpty && code != 'Mã') { globalUomMap[code] = unit; count++; }
            }
          }
        } else {
          var excel = Excel.decodeBytes(bytes);
          for (var table in excel.tables.values) {
            for (var row in table.rows) {
              if (row.length >= 4) {
                String code = row[1]?.value?.toString().trim() ?? ''; String unit = row[3]?.value?.toString().trim() ?? '';
                if (code.isNotEmpty && code != 'Mã' && code != 'null') { globalUomMap[code] = unit; count++; }
              }
            }
          }
        }
        await saveWorkshopJson(
          fileName: uomFilePath,
          payload: globalUomMap,
          api: api,
          token: widget.login.token,
        );
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã nạp thành công $count mã Đơn vị tính!'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi nạp ĐVT: $e'), backgroundColor: Colors.red));
    } finally { setState(() => loading = false); }
  }

  Future<void> _exportMisaExcel() async {
    if (selectedOrder == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng chọn 1 xe trước khi xuất MISA!'), backgroundColor: Colors.red)); return; }
    if (currentJobs.isEmpty && currentParts.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Báo giá đang trống!'), backgroundColor: Colors.red)); return; }

    setState(() => loading = true);
    try {
      var excel = Excel.createExcel(); String sheetName = 'nhập khẩu hàng hóa'; excel.rename('Sheet1', sheetName); Sheet sheetObject = excel[sheetName];
      List<CellValue> headers = [TextCellValue('Mã hàng hóa'), TextCellValue('HTTT (*)'), TextCellValue('Tên hàng hóa/dịch vụ'), TextCellValue('Đơn vị tính'), TextCellValue('Số lượng'), TextCellValue('Đơn giá'), TextCellValue('Thành tiền'), TextCellValue('Tỷ lệ chiết khấu'), TextCellValue('Tiền chiết khấu'), TextCellValue('Thành tiền NT sau CK'), TextCellValue('Thành tiền sau CK'), TextCellValue('Thuế suất'), TextCellValue('Tiền thuế'), TextCellValue('Tổng tiền'), TextCellValue('Hàng KM'), TextCellValue('Đơn giá sau CK'), TextCellValue('Đơn giá bán'), TextCellValue('Báo giá (*)')];
      sheetObject.appendRow(headers);

      for (var job in currentJobs) {
        double discountRate = 0.0; if (job.totalBeforeDiscount > 0 && job.discount > 0) discountRate = (job.discount / job.totalBeforeDiscount) * 100;
        String uom = globalUomMap.containsKey(job.codeCtrl.text.trim()) ? globalUomMap[job.codeCtrl.text.trim()]! : 'Giờ';
        sheetObject.appendRow([TextCellValue(job.codeCtrl.text.trim()), TextCellValue(job.paymentMethod), TextCellValue(job.nameCtrl.text), TextCellValue(uom), DoubleCellValue(job.qty), DoubleCellValue(job.price), DoubleCellValue(job.totalBeforeDiscount), DoubleCellValue(double.parse(discountRate.toStringAsFixed(2))), DoubleCellValue(job.discount), TextCellValue(''), DoubleCellValue(job.totalAfterDiscount), TextCellValue('${job.vatRate.toStringAsFixed(0)}%'), DoubleCellValue(job.vatAmount), DoubleCellValue(job.totalWithVat), TextCellValue(''), TextCellValue(''), TextCellValue(''), TextCellValue(selectedOrder!.roCode)]);
      }

      for (var part in currentParts) {
        double discountRate = 0.0; if (part.totalBeforeDiscount > 0 && part.discount > 0) discountRate = (part.discount / part.totalBeforeDiscount) * 100;
        String uom = globalUomMap.containsKey(part.codeCtrl.text.trim()) ? globalUomMap[part.codeCtrl.text.trim()]! : 'Cái';
        sheetObject.appendRow([TextCellValue(part.codeCtrl.text.trim()), TextCellValue(part.paymentMethod), TextCellValue(part.nameCtrl.text), TextCellValue(uom), DoubleCellValue(part.qty), DoubleCellValue(part.price), DoubleCellValue(part.totalBeforeDiscount), DoubleCellValue(double.parse(discountRate.toStringAsFixed(2))), DoubleCellValue(part.discount), TextCellValue(''), DoubleCellValue(part.totalAfterDiscount), TextCellValue('${part.vatRate.toStringAsFixed(0)}%'), DoubleCellValue(part.vatAmount), DoubleCellValue(part.totalWithVat), TextCellValue(''), TextCellValue(''), TextCellValue(''), TextCellValue(selectedOrder!.roCode)]);
      }

      final fileName = 'BaoGia_MISA_${selectedOrder!.bienSo}.xlsx';
      final result = await saveExcelBytes(
        bytes: excel.save(),
        fileName: fileName,
        dialogTitle: 'Báo giá MISA',
      );
      if (mounted) {
        showCrossPlatformSaveSnackBar(context, result, fileName, successExtra: 'Báo giá MISA');
      }
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi xuất file: $e'), backgroundColor: Colors.red)); } finally { setState(() => loading = false); }
  }

  /// Lưu báo giá hiện tại lên server trước khi xuất Excel (API đọc từ DB).
  Future<void> _syncRoSnapshotForExport() async {
    if (selectedOrder == null) return;
    final jobsJson = jsonEncode(currentJobs
        .map((e) => {
              'code': e.codeCtrl.text,
              'name': e.nameCtrl.text,
              'hours': e.qty,
              'price': e.price,
              'discount': e.discount,
              'vat': e.vatRate,
              'note': e.noteCtrl.text,
              'total': e.totalWithVat,
              'paymentMethod': e.paymentMethod,
            })
        .toList());
    final partsJson = jsonEncode(currentParts.map((e) {
      final hadKho = _partItemKhoRequested(e);
      return {
        'code': e.codeCtrl.text,
        'name': e.nameCtrl.text,
        'qty': e.qty,
        'price': e.price,
        'discount': e.discount,
        'vat': e.vatRate,
        'note': e.noteCtrl.text,
        'total': e.totalWithVat,
        'paymentMethod': e.paymentMethod,
        'inStock': e.inStock,
        'in_stock': e.inStock,
        'issuedQty': _preservedIssuedQtyForPart(e),
        'issued_qty': _preservedIssuedQtyForPart(e),
        'isOrdered': hadKho,
        'is_ordered': hadKho,
        'khoBaoRequestedAt': e.khoBaoRequestedAt,
        'kho_bao_requested_at': e.khoBaoRequestedAt,
      };
    }).toList());
    await api.updateRepairOrder(
      token: widget.login.token,
      id: selectedOrder!.id,
      status: selectedOrder!.status,
      jobs: jobsJson,
      parts: partsJson,
      statusNote: urgentNotesCtrl.text,
      cvdvWoCode: cvdvWoCodeCtrl.text.trim(),
      vehicleActivity: vehicleActivityCtrl.text.trim(),
      paymentInfo: _paymentInfoPayload(),
    );
  }

  Future<void> _exportPdfDocument(String docTitle) async {
    if (selectedOrder == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng chọn xe trước khi xuất PDF.'), backgroundColor: Colors.red),
      );
      return;
    }
    setState(() => loading = true);
    try {
    final font = AppPdfFonts.regular;
    final fontBold = AppPdfFonts.bold;
    final pdf = pw.Document();
    
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4, 
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start, 
            children: [
              pw.Center(child: pw.Text('TS-XDV AUTO SERVICE', style: pw.TextStyle(font: fontBold, fontSize: 24))), 
              pw.Center(child: pw.Text(docTitle.toUpperCase(), style: pw.TextStyle(font: fontBold, fontSize: 20))), pw.SizedBox(height: 20),
              pw.Text('Khách hàng: ${selectedOrder!.customerName}', style: pw.TextStyle(font: font)), pw.Text('Biển số: ${selectedOrder!.bienSo} | Mã RO: ${selectedOrder!.roCode}', style: pw.TextStyle(font: font)), pw.Text('Ngày lập: ${DateTime.now().toString().substring(0, 16)}', style: pw.TextStyle(font: font)), pw.SizedBox(height: 20),
              
              if (currentJobs.isNotEmpty) ...[
                pw.Text('I. TIỀN CÔNG SỬA CHỮA', style: pw.TextStyle(font: fontBold, fontSize: 14)), pw.SizedBox(height: 8), 
                pw.Table.fromTextArray(context: context, cellStyle: pw.TextStyle(font: font), headerStyle: pw.TextStyle(font: fontBold), data: <List<String>>[
                    ['Mã', 'Tên công việc', 'ĐVT', 'Giờ', 'Đơn giá', 'Giảm', 'VAT', 'HTTT', 'Thành tiền'], 
                    ...currentJobs.map((e) => [e.codeCtrl.text.isEmpty ? '-' : e.codeCtrl.text, e.nameCtrl.text, globalUomMap[e.codeCtrl.text] ?? 'Giờ', e.hoursCtrl.text, _formatVND(e.price), _formatVND(e.discount), '${e.vatRate}%', e.paymentMethod, _formatVND(e.totalWithVat)])
                  ]), pw.SizedBox(height: 20)
              ],
              
              if (currentParts.isNotEmpty) ...[
                pw.Text('II. PHỤ TÙNG VẬT TƯ', style: pw.TextStyle(font: fontBold, fontSize: 14)), pw.SizedBox(height: 8), 
                pw.Table.fromTextArray(context: context, cellStyle: pw.TextStyle(font: font), headerStyle: pw.TextStyle(font: fontBold), data: <List<String>>[
                    ['Mã', 'Tên phụ tùng', 'ĐVT', 'SL', 'Đơn giá', 'Giảm', 'VAT', 'HTTT', 'Thành tiền'], 
                    ...currentParts.map((e) => [e.codeCtrl.text.isEmpty ? '-' : e.codeCtrl.text, e.nameCtrl.text, globalUomMap[e.codeCtrl.text] ?? 'Cái', e.qtyCtrl.text, _formatVND(e.price), _formatVND(e.discount), '${e.vatRate}%', e.paymentMethod, _formatVND(e.totalWithVat)])
                  ]), pw.SizedBox(height: 20)
              ],
              
              pw.Divider(), 
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                  pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                      pw.Text('Chi tiết thanh toán:', style: pw.TextStyle(font: fontBold, fontSize: 12)),
                      pw.Text('Khách hàng TT: ${_formatVND(double.tryParse(customerPayCtrl.text.replaceAll(',', '')) ?? 0)} đ', style: pw.TextStyle(font: font)),
                      pw.Text('Bảo hiểm TT: ${_formatVND(double.tryParse(insurancePayCtrl.text.replaceAll(',', '')) ?? 0)} đ', style: pw.TextStyle(font: font)),
                      pw.Text('VinFast TT: ${_formatVND(double.tryParse(vinfastPayCtrl.text.replaceAll(',', '')) ?? 0)} đ', style: pw.TextStyle(font: font)),
                      pw.Text('Công nợ: ${_formatVND(double.tryParse(debtCtrl.text.replaceAll(',', '')) ?? 0)} đ', style: pw.TextStyle(font: font)),
                  ]),
                  pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                      pw.Text('Cộng tiền hàng (Sau giảm): ${_formatVND(subTotal)} đ', style: pw.TextStyle(font: font)), 
                      pw.Text('Tổng tiền thuế VAT: ${_formatVND(totalVat)} đ', style: pw.TextStyle(font: font)), pw.SizedBox(height: 8), 
                      pw.Text('TỔNG THANH TOÁN: ${_formatVND(grandTotal)} đ', style: pw.TextStyle(font: fontBold, fontSize: 16))
                  ])
              ]),
            ]
          );
        }
      )
    );
    final pdfResult = await printOrSharePdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      documentName: 'Bao_Gia_${selectedOrder!.bienSo}',
      dialogTitle: 'Lưu báo giá PDF',
    );
    if (mounted) {
      showCrossPlatformSaveSnackBar(
        context,
        pdfResult,
        'Bao_Gia_${selectedOrder!.bienSo}.pdf',
        successExtra: 'Báo giá PDF',
      );
    }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi xuất PDF: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }
  
  void _showExportMenu() {
    if (selectedOrder == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng chọn xe trước khi xuất / in.'), backgroundColor: Colors.orange),
      );
      return;
    }
    showAdaptiveExportMenu(
      context: context,
      title: 'Xuất / In tài liệu',
      subtitle: 'Biển số: ${selectedOrder!.bienSo}',
      children: [
        ListTile(
          leading: const Icon(Icons.receipt),
          title: const Text('Báo giá sửa chữa (PDF)'),
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            _exportPdfDocument('Báo Giá Sửa Chữa');
          },
        ),
        ListTile(
          leading: const Icon(Icons.build),
          title: const Text('Lệnh sửa chữa (RO) (PDF)'),
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            _exportPdfDocument('Lệnh Sửa Chữa (RO)');
          },
        ),
        ListTile(
          leading: const Icon(Icons.table_view, color: Colors.green),
          title: const Text('Xuất Báo Giá MISA (Excel)'),
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            _exportMisaExcel();
          },
        ),
        ListTile(
          leading: Icon(Icons.description_outlined, color: Colors.teal.shade800),
          title: const Text('Phiếu theo mẫu VinFast (Excel)'),
          subtitle: const Text('Báo giá, Lệnh SC, quyết toán, ra cổng…'),
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            showDocumentExportSheet(
              context: context,
              api: api,
              token: widget.login.token,
              repairOrderId: selectedOrder!.id,
              bienSo: selectedOrder!.bienSo,
              onlyKeys: const ['bao_gia', 'lenh_sua_chua', 'phieu_yeu_cau_pt', 'quyet_toan', 'phieu_ra_cong', 'hoa_don_noi_bo'],
              prepareForExport: _syncRoSnapshotForExport,
            );
          },
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.upload_file, color: Colors.orange),
          title: const Text('Nạp file Danh mục ĐVT MISA'),
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            _importUnitMap();
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    int pendingReqs = orders.where((o) => _hasLinkRequest(o.linkRequestedBy)).length;
    int unreadMsgs = orders.where((o) {
      try {
        if (o.chatLogs != null && o.chatLogs.toString() != '[]') {
          List logs = (o.chatLogs is String) ? jsonDecode(o.chatLogs) : List.from(o.chatLogs);
          if (logs.isNotEmpty && logs.last['role'] == 'Khách hàng') return true;
        }
      } catch (_) {}
      return false;
    }).length;
    final int ruleCount = _cvdvRuleAlerts().length;
    int totalNotifications = pendingReqs + unreadMsgs + ruleCount + _unreadNotifCount;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('CVDV - Xử Lý Báo Giá & Dịch Vụ', style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: Colors.white,
        actions: [
          const CompanyChatAppBarButton(),
          Center(child: Text('User: ${widget.login.userName}  ', style: const TextStyle(fontWeight: FontWeight.bold))), 
          
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(icon: const Icon(Icons.notifications, color: Colors.blue), onPressed: () { _showNotificationsDialog(); }, tooltip: 'Thông báo'),
              if (totalNotifications > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.red),
                    child: Text(
                      totalNotifications > 99 ? '99+' : '$totalNotifications',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                )
            ],
          ),

          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadBoard, tooltip: 'Làm mới'), 
          IconButton(icon: const Icon(Icons.logout, color: Colors.red), onPressed: () { Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen())); }, tooltip: 'Đăng xuất'), const SizedBox(width: 16)
        ],
      ),
      body: ResponsiveMasterDetail(
        detailVisible: selectedOrder != null,
        onBackFromDetail: () => setState(() => selectedOrder = null),
        listWidth: appFormFactor(context) == AppFormFactor.tablet ? 320 : 380,
        listPane: Container(
            color: Colors.white,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16), color: const Color(0xFFE2E8F0), width: double.infinity, 
                  child: Column(
                    children: [
                      DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true, value: _selectedFilter, icon: const Icon(Icons.filter_list, color: Colors.blue),
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E293B), fontSize: 16),
                          items: _filters.map((String value) { return DropdownMenuItem<String>(value: value, child: Text(value)); }).toList(),
                          onChanged: (newValue) { setState(() { _selectedFilter = newValue!; selectedOrder = null; searchBienSoCtrl.clear(); }); },
                        ),
                      ),
                      const SizedBox(height: 12),
                      
                      TextField(
                        controller: searchBienSoCtrl,
                        onChanged: (val) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Nhập biển số để tìm xe...', prefixIcon: const Icon(Icons.search, color: Colors.blue),
                          filled: true, fillColor: Colors.white, isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                          suffixIcon: searchBienSoCtrl.text.isNotEmpty ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () { searchBienSoCtrl.clear(); setState(() {}); }) : null
                        ),
                      ),
                    ],
                  )
                ),

                Expanded(
                  child: loading 
                    ? const Center(child: CircularProgressIndicator()) 
                    : filteredOrders.isEmpty 
                      ? const Center(child: Text('Không có xe nào phù hợp với bộ lọc hiện tại', style: TextStyle(color: Colors.grey)))
                      : ListView.separated(
                          itemCount: filteredOrders.length, separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final item = filteredOrders[index]; final isSelected = selectedOrder?.id == item.id;
                            bool hasBooking = bookings.any((b) => b.bienSo.replaceAll(RegExp(r'[\s-]'), '').toLowerCase() == item.bienSo.replaceAll(RegExp(r'[\s-]'), '').toLowerCase());
                            bool hasLinkReq = _hasLinkRequest(item.linkRequestedBy);
                            bool hasNewMsg = false;
                            try { if (item.chatLogs != null && item.chatLogs.toString() != '[]') { List logs = (item.chatLogs is String) ? jsonDecode(item.chatLogs) : List.from(item.chatLogs); if (logs.isNotEmpty && logs.last['role'] == 'Khách hàng') hasNewMsg = true; } } catch (_) {}

                            return ListTile(
                              selected: isSelected, selectedTileColor: const Color(0xFFDBEAFE), leading: Icon(Icons.directions_car, color: isSelected ? Colors.blue : Colors.blueGrey, size: 40),
                              title: Row(children: [ Text(item.bienSo, style: TextStyle(fontWeight: FontWeight.bold, fontSize: appPanelTitleSize(context, desktop: 20))), if (hasBooking) ...[const SizedBox(width: 8), Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(4)), child: const Text('CÓ HẸN', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)))] ]), 
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start, 
                                  children: [
                                    Text(
                                      'Xe đang: ${_vehicleDoingLabel(item)}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 12, height: 1.25, color: Colors.blueGrey.shade800, fontWeight: FontWeight.w500),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Vào xưởng: ${_formatTimeInWorkshop(item.createdAt)}',
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                                    ),
                                    if (item.cvdvWoCode.trim().isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          'WO gửi KHO: ${item.cvdvWoCode}',
                                          style: TextStyle(fontSize: 10, color: Colors.teal.shade800, fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                    const SizedBox(height: 6),
                                    _buildStatusBadge(item.status), _buildRedAlertBadge(item),
                                    if (item.cvdvUsername == widget.login.userName && _orderPartsFullyIssued(item))
                                      Container(
                                        margin: const EdgeInsets.only(top: 6),
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.teal.shade700,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          '✅ KHO ĐÃ XUẤT ĐỦ',
                                          style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                                        ),
                                      )
                                    else if (item.cvdvUsername == widget.login.userName &&
                                        quotedPartsNeedWarehouseIssue(item.parts) &&
                                        !allQuotedPartsFullyIssued(item.parts))
                                      Container(
                                        margin: const EdgeInsets.only(top: 6),
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.shade800,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          '⏳ CHỜ KHO XUẤT',
                                          style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    if (hasLinkReq) Container(margin: const EdgeInsets.only(top: 6), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(6)), child: const Text('🔔 KHÁCH XIN LIÊN KẾT', style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold))),
                                    if (hasNewMsg) Container(margin: const EdgeInsets.only(top: 6), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(6)), child: const Text('💬 CÓ TIN NHẮN TỪ KHÁCH', style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)))
                                  ]
                                ),
                              ),
                              onTap: () { 
                                final prevId = selectedOrder?.id;
                                setState(() { 
                                  selectedOrder = item; _clearFormsRaw(); 
                                  if (prevId != item.id) _fpAfterLastKhoBaoRequest = null;
                                  try {
                                    urgentNotesCtrl.text = item.customerNote;
                                    cvdvWoCodeCtrl.text = item.cvdvWoCode;
                                    vehicleActivityCtrl.text = item.vehicleActivityNote;
                                    if (item.jobs != null && item.jobs.toString() != 'null' && item.jobs.toString() != '[]') {
                                      List jList = (item.jobs is String) ? jsonDecode(item.jobs) : List.from(item.jobs);
                                      for (var j in jList) {
                                        final job = JobItem(); job.codeCtrl.text = j['code']?.toString() ?? ''; job.nameCtrl.text = j['name']?.toString() ?? ''; job.hoursCtrl.text = (j['hours'] ?? j['qty'] ?? 1).toString(); job.priceCtrl.text = (j['price'] ?? 0).toStringAsFixed(0); job.discountCtrl.text = (j['discount'] ?? 0).toStringAsFixed(0); job.vatCtrl.text = (j['vat'] ?? 0).toStringAsFixed(0); job.noteCtrl.text = j['note']?.toString() ?? ''; job.paymentMethod = j['paymentMethod']?.toString() ?? 'C'; currentJobs.add(job);
                                      }
                                    }
                                    if (item.parts != null && item.parts.toString() != 'null' && item.parts.toString() != '[]') {
                                      List pList = (item.parts is String) ? jsonDecode(item.parts) : List.from(item.parts);
                                      for (var p in pList) {
                                        final part = PartItem(); 
                                        part.codeCtrl.text = p['code']?.toString() ?? ''; 
                                        part.nameCtrl.text = p['name']?.toString() ?? ''; 
                                        part.qtyCtrl.text = (p['qty'] ?? p['hours'] ?? 1).toString(); 
                                        part.priceCtrl.text = (p['price'] ?? 0).toStringAsFixed(0); 
                                        part.discountCtrl.text = (p['discount'] ?? 0).toStringAsFixed(0); 
                                        part.vatCtrl.text = (p['vat'] ?? 0).toStringAsFixed(0); 
                                        part.noteCtrl.text = p['note']?.toString() ?? ''; 
                                        part.paymentMethod = p['paymentMethod']?.toString() ?? 'C'; 
                                        part.inStock = _mapIndicatesInStock(Map<String, dynamic>.from(p as Map));
                                        
                                        part.issuedQty = int.tryParse(p['issuedQty']?.toString() ?? '0') ?? 0;
                                        final pmap = Map<String, dynamic>.from(p as Map);
                                        part.isOrdered = _mapIndicatesKhoRequested(pmap);
                                        part.khoBaoRequestedAt = pmap['khoBaoRequestedAt']?.toString() ?? pmap['kho_bao_requested_at']?.toString() ?? '';
                                        currentParts.add(part);
                                      }
                                    }
                                    _loadPaymentFieldsFromOrder(item);
                                  } catch(_) {}
                                }); 
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        detailPane: selectedOrder == null
            ? const Center(child: Text('← Chọn xe từ danh sách để làm Báo giá', style: TextStyle(fontSize: 16, color: Colors.grey)))
            : Column(
                  children: [
                    if (_hasLinkRequest(selectedOrder!.linkRequestedBy))
                      Container(
                        padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFFFEF2F2), border: Border(bottom: BorderSide(color: Colors.red.shade200))),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 32), const SizedBox(width: 12), 
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('YÊU CẦU TRUY CẬP TỪ KHÁCH HÀNG', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)), Text('SĐT [${selectedOrder!.linkRequestedBy}] yêu cầu theo dõi xe này.', style: const TextStyle(color: Colors.redAccent))])), 
                            TextButton(onPressed: () => _handleLinkRequest(selectedOrder!, false), child: const Text('TỪ CHỐI', style: TextStyle(color: Colors.red))), const SizedBox(width: 8), 
                            FilledButton(onPressed: () => _handleLinkRequest(selectedOrder!, true), style: FilledButton.styleFrom(backgroundColor: Colors.green), child: const Text('XÁC NHẬN CHO KHÁCH'))
                          ]
                        )
                      ),

                    Container(
                      color: Colors.white, padding: const EdgeInsets.all(24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start, 
                            children: [
                              Row(
                                children: [
                                  Text(selectedOrder!.bienSo, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))), 
                                  if (selectedOrder!.linkedCustomer.isNotEmpty && selectedOrder!.linkedCustomer != 'null') ...[
                                    const SizedBox(width: 12), 
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.green.shade50, border: Border.all(color: Colors.green), borderRadius: BorderRadius.circular(8)), 
                                      child: Row(children: [const Icon(Icons.verified_user, color: Colors.green, size: 16), const SizedBox(width: 4), Text('Đã KH: ${selectedOrder!.linkedCustomer}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12))])
                                    )
                                  ]
                                ]
                              ), 
                              const SizedBox(height: 8), 
                              Text('Khách hàng: ${selectedOrder!.customerName} | SĐT: ${selectedOrder!.customerPhone}', style: const TextStyle(fontSize: 16)),
                              const SizedBox(height: 4),
                              Row(children: [const Icon(Icons.access_time, size: 14, color: Colors.grey), const SizedBox(width: 4), Text('Thời gian xe vào xưởng: ${selectedOrder!.createdAt?.toString().substring(0,16) ?? "Chưa rõ"} (Đã ở xưởng: ${_calculateSLA(selectedOrder!.createdAt)})', style: const TextStyle(color: Colors.grey, fontStyle: FontStyle.italic))])
                            ]
                          ),
                          Expanded(
                            child: Wrap(
                              alignment: WrapAlignment.end, spacing: 12, runSpacing: 8, 
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                OutlinedButton.icon(onPressed: () => _showCarImagesDialog(selectedOrder!), icon: const Icon(Icons.photo_camera, color: Colors.purple), label: const Text('Xem Ảnh Xe', style: TextStyle(color: Colors.purple))), 
                                OutlinedButton.icon(onPressed: () => _makePhoneCall(selectedOrder!.customerPhone), icon: const Icon(Icons.phone, color: Colors.green), label: const Text('Gọi Khách', style: TextStyle(color: Colors.green))), 
                                FilledButton.icon(onPressed: _openChatDialog, icon: const Icon(Icons.chat), label: const Text('Nhắn tin KH')), 
                                OutlinedButton.icon(onPressed: _importMisa, icon: const Icon(Icons.upload_file, color: Colors.blue), label: const Text('Import MISA')), 
                                OutlinedButton.icon(onPressed: _importDms, icon: const Icon(Icons.drive_folder_upload, color: Colors.orange), label: const Text('Import DMS (DOCX)')), 
                                OutlinedButton.icon(onPressed: _showExportMenu, icon: const Icon(Icons.print), label: const Text('In / PDF')),
                              ]
                            ),
                          )
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 7,
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  TextField(controller: urgentNotesCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Ghi chú CẦN LÀM SỚM', border: OutlineInputBorder(), filled: true, fillColor: Color(0xFFFEF2F2), prefixIcon: Icon(Icons.warning, color: Colors.red))), 
                                  const SizedBox(height: 12),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: cvdvWoCodeCtrl,
                                          onChanged: (_) => setState(() {}),
                                          decoration: const InputDecoration(
                                            labelText: 'Mã WO gửi KHO (CVDV điền)',
                                            hintText: 'Để trống = dùng mã RO hệ thống',
                                            border: OutlineInputBorder(),
                                            isDense: true,
                                            prefixIcon: Icon(Icons.tag, size: 20),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        flex: 2,
                                        child: TextField(
                                          controller: vehicleActivityCtrl,
                                          onChanged: (_) => setState(() {}),
                                          maxLines: 2,
                                          decoration: const InputDecoration(
                                            labelText: 'Thông báo xe đang làm gì (hiện trên danh sách biển số)',
                                            hintText: 'Để trống = hiển thị theo trạng thái lệnh',
                                            border: OutlineInputBorder(),
                                            isDense: true,
                                            alignLabelWithHint: true,
                                            prefixIcon: Icon(Icons.info_outline, size: 20),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 32),
                                  
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween, 
                                    children: [
                                      const Text('I. TIỀN CÔNG SỬA CHỮA', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1E40AF))), 
                                      OutlinedButton.icon(onPressed: () { setState(() { currentJobs.add(JobItem()); }); }, icon: const Icon(Icons.add, size: 20), label: const Text('Thêm công việc'))
                                    ]
                                  ), 
                                  const SizedBox(height: 16),
                                  ...currentJobs.asMap().entries.map((entry) {
                                    JobItem job = entry.value; 
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 16), 
                                      child: Row(
                                        children: [
                                          Expanded(flex: 2, child: TextField(controller: job.codeCtrl, decoration: const InputDecoration(labelText: 'Mã CV', border: OutlineInputBorder(), isDense: true))), const SizedBox(width: 8),
                                          Expanded(flex: 3, child: TextField(controller: job.nameCtrl, decoration: const InputDecoration(labelText: 'Tên CV', border: OutlineInputBorder(), isDense: true))), const SizedBox(width: 8), 
                                          Expanded(flex: 1, child: TextField(controller: job.hoursCtrl, keyboardType: TextInputType.number, onChanged: (_) => setState((){}), decoration: const InputDecoration(labelText: 'Giờ/SL', border: OutlineInputBorder(), isDense: true))), const SizedBox(width: 8), 
                                          Expanded(flex: 2, child: TextField(controller: job.priceCtrl, keyboardType: TextInputType.number, onChanged: (_) { setState((){}); }, decoration: const InputDecoration(labelText: 'Đơn giá', border: OutlineInputBorder(), isDense: true))), const SizedBox(width: 8), 
                                          Expanded(flex: 1, child: TextField(controller: job.discountCtrl, keyboardType: TextInputType.number, onChanged: (_) { setState((){}); }, decoration: const InputDecoration(labelText: 'Giảm', border: OutlineInputBorder(), isDense: true))), const SizedBox(width: 8), 
                                          Expanded(flex: 1, child: TextField(controller: job.vatCtrl, keyboardType: TextInputType.number, onChanged: (_) { setState((){}); }, decoration: const InputDecoration(labelText: 'VAT%', border: OutlineInputBorder(), isDense: true))), const SizedBox(width: 8), 
                                          
                                          Container(
                                              width: 70,
                                              padding: const EdgeInsets.symmetric(horizontal: 8),
                                              decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(4)),
                                              child: DropdownButtonHideUnderline(
                                                  child: DropdownButton<String>(
                                                      value: job.paymentMethod,
                                                      isExpanded: true,
                                                      onChanged: (String? newValue) { if (newValue != null) { setState(() { job.paymentMethod = newValue; }); } },
                                                      items: paymentOptions.map<DropdownMenuItem<String>>((String value) {
                                                          return DropdownMenuItem<String>(value: value, child: Text(value, style: const TextStyle(fontWeight: FontWeight.bold)));
                                                      }).toList(),
                                                  )
                                              )
                                          ),
                                          const SizedBox(width: 8),
                            
                                          Expanded(flex: 2, child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8)), child: Text(_formatVND(job.totalWithVat), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold)))), const SizedBox(width: 4), 
                                          
                                          IconButton(icon: const Icon(Icons.swap_vert, color: Colors.orange), tooltip: 'Chuyển xuống Phụ Tùng', onPressed: () => _swapToPart(entry.key)),
                                          IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => setState(() => currentJobs.removeAt(entry.key))) 
                                        ]
                                      )
                                    );
                                  }),
                                  const SizedBox(height: 40),
                                  
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween, 
                                    children: [
                                      const Text('II. PHỤ TÙNG & VẬT TƯ', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1E40AF))), 
                                      Row(
                                        children: [
                                          FilledButton.icon(
                                            style: FilledButton.styleFrom(backgroundColor: Colors.teal),
                                            onPressed: _autoCheckInventory, 
                                            icon: const Icon(Icons.manage_search, size: 20), 
                                            label: const Text('Check Tồn Kho Tự Động')
                                          ),
                                          const SizedBox(width: 8),
                                          OutlinedButton.icon(onPressed: () { setState(() { currentParts.add(PartItem()); }); }, icon: const Icon(Icons.add, size: 20), label: const Text('Thêm phụ tùng'))
                                        ]
                                      )
                                    ]
                                  ), 
                                  const SizedBox(height: 16),
                                  ...currentParts.asMap().entries.map((entry) {
                                    PartItem part = entry.value; 
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 16), 
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start, 
                                        children: [
                                          Expanded(flex: 2, child: TextField(controller: part.codeCtrl, decoration: const InputDecoration(labelText: 'Mã PT', border: OutlineInputBorder(), isDense: true))), const SizedBox(width: 8),
                                          
                                          Expanded(flex: 3, child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              TextField(controller: part.nameCtrl, decoration: const InputDecoration(labelText: 'Tên PT', border: OutlineInputBorder(), isDense: true)),
                                              if (part.noteCtrl.text.isNotEmpty)
                                                Padding(
                                                  padding: const EdgeInsets.only(top: 4),
                                                  child: Row(
                                                    children: [
                                                      const Icon(Icons.edit_note, size: 14, color: Colors.orange),
                                                      const SizedBox(width: 4),
                                                      Expanded(child: Text('KTV: ${part.noteCtrl.text}', style: const TextStyle(fontSize: 12, color: Colors.orange, fontStyle: FontStyle.italic))),
                                                    ],
                                                  ),
                                                )
                                            ],
                                          )), const SizedBox(width: 8), 
                                          
                                          Expanded(flex: 1, child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              TextField(controller: part.qtyCtrl, keyboardType: TextInputType.number, onChanged: (_) => setState((){}), decoration: const InputDecoration(labelText: 'SL', border: OutlineInputBorder(), isDense: true)),
                                              const SizedBox(height: 4),
                                              Text(part.issuedQty >= part.qty ? '(Kho đã xuất đủ)' : (part.issuedQty > 0 ? '(Kho đã xuất: ${part.issuedQty})' : '(Chưa xuất)'), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: part.issuedQty >= part.qty ? Colors.green : Colors.red))
                                            ],
                                          )), const SizedBox(width: 8), 
                                          
                                          Expanded(flex: 2, child: TextField(controller: part.priceCtrl, keyboardType: TextInputType.number, onChanged: (_) { setState((){}); }, decoration: const InputDecoration(labelText: 'Đơn giá', border: OutlineInputBorder(), isDense: true))), const SizedBox(width: 8), 
                                          Expanded(flex: 1, child: TextField(controller: part.discountCtrl, keyboardType: TextInputType.number, onChanged: (_) { setState((){}); }, decoration: const InputDecoration(labelText: 'Giảm', border: OutlineInputBorder(), isDense: true))), const SizedBox(width: 8), 
                                          Expanded(flex: 1, child: TextField(controller: part.vatCtrl, keyboardType: TextInputType.number, onChanged: (_) { setState((){}); }, decoration: const InputDecoration(labelText: 'VAT%', border: OutlineInputBorder(), isDense: true))), const SizedBox(width: 8), 
                                          
                                          Container(
                                              width: 70,
                                              padding: const EdgeInsets.symmetric(horizontal: 8),
                                              decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(4)),
                                              child: DropdownButtonHideUnderline(
                                                  child: DropdownButton<String>(
                                                      value: part.paymentMethod,
                                                      isExpanded: true,
                                                      onChanged: (String? newValue) { if (newValue != null) { setState(() { part.paymentMethod = newValue; }); } },
                                                      items: paymentOptions.map<DropdownMenuItem<String>>((String value) {
                                                          return DropdownMenuItem<String>(value: value, child: Text(value, style: const TextStyle(fontWeight: FontWeight.bold)));
                                                      }).toList(),
                                                  )
                                              )
                                          ),
                                          const SizedBox(width: 8),
                            
                                          Expanded(flex: 2, child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8)), child: Text(_formatVND(part.totalWithVat), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold)))), const SizedBox(width: 4), 
                                          
                                          Column(
                                            children: [
                                              Checkbox(
                                                value: part.inStock,
                                                activeColor: Colors.green,
                                                onChanged: (val) {
                                                  setState(() { part.inStock = val ?? true; });
                                                },
                                              ),
                                              Text('Tồn kho', style: TextStyle(fontSize: 10, color: part.inStock ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                          
                                          IconButton(icon: const Icon(Icons.swap_vert, color: Colors.orange), tooltip: 'Chuyển lên Công Việc', onPressed: () => _swapToJob(entry.key)),
                                          IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => setState(() => currentParts.removeAt(entry.key))) 
                                        ]
                                      )
                                    );
                                  }),
                                ],
                              ),
                            ),
                          ),
                          
                          const VerticalDivider(width: 1),

                          Expanded(
                            flex: 3,
                            child: Container(
                              color: Colors.blue.shade50,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: double.infinity, padding: const EdgeInsets.all(16), color: Colors.blue.shade700,
                                    child: const Text('📋 TO-DO LIST (KIỂM TRA CÔNG VIỆC)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))
                                  ),
                                  Expanded(
                                    child: ListView.builder(
                                      padding: const EdgeInsets.all(8),
                                      itemCount: todoTasks.length,
                                      itemBuilder: (ctx, i) {
                                        return CheckboxListTile(
                                          title: Text(todoTasks[i], style: TextStyle(decoration: checkListStatus[i] ? TextDecoration.lineThrough : null, color: checkListStatus[i] ? Colors.grey : Colors.black87, fontWeight: FontWeight.bold)),
                                          value: checkListStatus[i],
                                          activeColor: Colors.green,
                                          onChanged: (val) { setState(() { checkListStatus[i] = val ?? false; }); },
                                        );
                                      }
                                    )
                                  )
                                ]
                              )
                            )
                          )
                        ]
                      )
                    ),
                    
                    Container(
                      padding: const EdgeInsets.all(24), 
                      decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))]),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            flex: 4,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('THAO TÁC CẬP NHẬT:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 14)), const SizedBox(height: 12),
                                Wrap( 
                                  spacing: 12, runSpacing: 12,
                                  children: [
                                    FilledButton.icon(
                                      onPressed: loading || _cvdvOpsFrozen() ? null : () => _confirmCustomerCancelNoRepair(), 
                                      icon: const Icon(Icons.cancel), style: FilledButton.styleFrom(backgroundColor: Colors.grey.shade400, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16)), label: const Text('KH Không Sửa (Hủy)', style: TextStyle(fontSize: 14))),
                                    FilledButton.icon(
                                      onPressed: loading || _cvdvOpsFrozen() ? null : () => _promptPauseReasonThenDungSua(), 
                                      icon: const Icon(Icons.pause_circle_outline), style: FilledButton.styleFrom(backgroundColor: Colors.red.shade400, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16)), label: const Text('Tạm Dừng Sửa', style: TextStyle(fontSize: 14))),
                                    FilledButton.icon(
                                      onPressed: loading || _cvdvOpsFrozen() ? null : () => _updateRoStatus('DANG_SUA'), 
                                      icon: const Icon(Icons.play_circle_outline), style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade400, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16)), label: const Text('Tiếp Tục Sửa', style: TextStyle(fontSize: 14))),
                                    
                                    FilledButton.icon(
                                      onPressed: loading || _cvdvOpsFrozen() ? null : () {
                                        if (_validatePayments()) {
                                          _updateRoStatus('CHO_BAO_GIA');
                                        }
                                      }, 
                                      icon: const Icon(Icons.save), style: FilledButton.styleFrom(backgroundColor: const Color(0xFF64748B), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16)), label: const Text('Lưu Nháp', style: TextStyle(fontSize: 14))), 
                                    FilledButton.icon(
                                      onPressed: loading || _cvdvOpsFrozen() ? null : () {
                                        if (_validatePayments()) {
                                          _updateRoStatus('CHO_KH_DUYET');
                                        }
                                      }, 
                                      icon: const Icon(Icons.send), style: FilledButton.styleFrom(backgroundColor: const Color(0xFFF59E0B), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16)), label: const Text('Gửi KH Duyệt', style: TextStyle(fontSize: 14))), 
                                    FilledButton.icon(
                                      onPressed: loading || _cvdvOpsFrozen() ? null : () {
                                        if (_validatePayments()) {
                                          _handleDispatchToTech();
                                        }
                                      }, 
                                      icon: const Icon(Icons.handyman), style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16)), label: const Text('Duyệt -> Quản Đốc', style: TextStyle(fontSize: 14))),
                                    FilledButton.icon(
                                      onPressed: loading || _cvdvOpsFrozen() ? null : () {
                                        if (_validatePayments()) {
                                          _handleInsuranceAndStatus('DA_RA_CONG_THIEU_PT');
                                        }
                                      }, 
                                      icon: const Icon(Icons.output), style: FilledButton.styleFrom(backgroundColor: Colors.red, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16)), label: const Text('Ra Xưởng (Thiếu PT)', style: TextStyle(fontSize: 14))),
                                    if (selectedOrder!.status == 'CHO_CVDV_CHOT')
                                      FilledButton.icon(
                                        onPressed: (loading || _cvdvOpsFrozen() || !_orderPartsReadyForSettlement(selectedOrder!))
                                            ? null
                                            : () {
                                                if (_validatePayments()) {
                                                  _handleInsuranceAndStatus('CHO_QUYET_TOAN');
                                                }
                                              },
                                        icon: const Icon(Icons.fact_check),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: Colors.teal,
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                        ),
                                        label: Text(
                                          _orderPartsReadyForSettlement(selectedOrder!)
                                              ? 'Kho đã xuất đủ → Chuyển kế toán'
                                              : 'Chờ Kho xuất đủ PT',
                                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                  ]
                                ),
                              ],
                            ),
                          ),
                          
                          Expanded(
                            flex: 3, 
                            child: Container(
                              padding: const EdgeInsets.all(20), margin: const EdgeInsets.only(right: 16), decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0))),
                              child: Column(
                                children: [
                                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Cộng tiền hàng:'), Expanded(child: Align(alignment: Alignment.centerRight, child: Row(mainAxisSize: MainAxisSize.min, children: [Flexible(child: SelectableText(_formatVND(subTotal), style: const TextStyle(fontWeight: FontWeight.bold))), const Text(' ₫', style: TextStyle(fontWeight: FontWeight.bold))])))]), const SizedBox(height: 8),
                                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Tổng Thuế VAT:'), Expanded(child: Align(alignment: Alignment.centerRight, child: Row(mainAxisSize: MainAxisSize.min, children: [Flexible(child: SelectableText(_formatVND(totalVat), style: const TextStyle(fontWeight: FontWeight.bold))), const Text(' ₫', style: TextStyle(fontWeight: FontWeight.bold))])))]), const Divider(height: 24),
                                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('TỔNG:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), Expanded(child: Align(alignment: Alignment.centerRight, child: Row(mainAxisSize: MainAxisSize.min, children: [Flexible(child: SelectableText(_formatVND(grandTotal), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24, color: Colors.red))), const Text(' ₫', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24, color: Colors.red))])))]),
                                ],
                              ),
                            )
                          ),

                          Expanded(
                              flex: 3,
                              child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue.shade200)),
                                  child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                          const Text('Nguồn Thanh Toán (C, I, W):', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)), const SizedBox(height: 8),
                                          Row(
                                              children: [
                                                  Expanded(child: TextField(controller: customerPayCtrl, keyboardType: TextInputType.number, inputFormatters: [CurrencyInputFormatter()], decoration: const InputDecoration(labelText: 'KH Thanh toán (C)', isDense: true, border: OutlineInputBorder(), filled: true, fillColor: Colors.white))), const SizedBox(width: 8),
                                                  Expanded(child: TextField(controller: insurancePayCtrl, keyboardType: TextInputType.number, inputFormatters: [CurrencyInputFormatter()], decoration: const InputDecoration(labelText: 'Bảo hiểm TT (I)', isDense: true, border: OutlineInputBorder(), filled: true, fillColor: Colors.white))),
                                              ]
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                              children: [
                                                  Expanded(child: TextField(controller: vinfastPayCtrl, keyboardType: TextInputType.number, inputFormatters: [CurrencyInputFormatter()], decoration: const InputDecoration(labelText: 'Bảo hành TT (W)', isDense: true, border: OutlineInputBorder(), filled: true, fillColor: Colors.white))), const SizedBox(width: 8),
                                                  Expanded(child: TextField(controller: debtCtrl, keyboardType: TextInputType.number, inputFormatters: [CurrencyInputFormatter()], decoration: const InputDecoration(labelText: 'Công nợ', isDense: true, border: OutlineInputBorder(), filled: true, fillColor: Colors.white))),
                                              ]
                                          )
                                      ]
                                  )
                              )
                          ),
                        ],
                      ),
                    )
                  ],
                ),
      ),
    );
  }
}