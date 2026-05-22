import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';

import '../models/auth_models.dart';
import '../services/api_service.dart';
import '../core/time_format.dart';
import '../core/cross_platform_export_helpers.dart';
import '../core/workshop_local_sync.dart';
import '../core/pick_file_bytes.dart';
import '../widgets/column_filter_menu_header.dart';
import '../widgets/company_chat_host.dart';
import '../widgets/responsive_shell.dart';
import '../core/responsive_layout.dart';
import 'login_screen.dart';

/// Đọc trường PT từ JSON (camelCase hoặc snake_case).
String _partMapStr(dynamic row, List<String> keys) {
  if (row is! Map) return '';
  final m = Map<dynamic, dynamic>.from(row as Map);
  for (final k in keys) {
    final v = m[k]?.toString().trim();
    if (v != null && v.isNotEmpty && v.toLowerCase() != 'null') return v;
  }
  return '';
}

/// Ngày dự kiến trên dòng PT thiếu: ưu tiên field phẳng, sau đó đọc từ phần tử trong rawParts (server đôi khi chỉ lưu trong JSON part).
String _expectedDateForMissingLine(Map<String, dynamic> line) {
  var s = _partMapStr(line, ['expectedDate', 'expected_date', 'expected_delivery_date']);
  if (s.isNotEmpty) return s;
  try {
    final idx = line['partIndex'] is int ? line['partIndex'] as int : int.tryParse('${line['partIndex']}') ?? 0;
    final raw = line['rawParts'];
    final List<dynamic> list = raw is String ? (jsonDecode(raw) as List<dynamic>) : List<dynamic>.from(raw as List);
    if (idx >= 0 && idx < list.length && list[idx] is Map) {
      return _partMapStr(list[idx], ['expectedDate', 'expected_date', 'expected_delivery_date']);
    }
  } catch (_) {}
  return '';
}

const String kInvCatPhuTung = 'PHU_TUNG';
const String kInvCatCCDC = 'CONG_CU_DUNG_CU';

String _invCatLabel(String? raw) {
  final s = (raw ?? '').toUpperCase();
  if (s == kInvCatCCDC || s.contains('CONG_CU') || s.contains('CCDC') || s == 'TOOL') return 'Công cụ dụng cụ';
  return 'Phụ tùng';
}

/// Đọc loại hàng hoá từ ô Excel (nhãn tiếng Việt / mã).
String _invCatFromExcelCell(String? cell) {
  final t = (cell ?? '').toLowerCase().trim();
  if (t.isEmpty) return kInvCatPhuTung;
  if (t.contains('công') ||
      t.contains('cong') ||
      t.contains('ccdc') ||
      t.contains('dụng cụ') ||
      t.contains('dung cu') ||
      t == kInvCatCCDC.toLowerCase() ||
      t.contains('tool')) {
    return kInvCatCCDC;
  }
  return kInvCatPhuTung;
}

double _parseMoneyLoose(String? s) {
  if (s == null || s.isEmpty) return 0;
  return double.tryParse(s.replaceAll(',', '').replaceAll(' ', '').trim()) ?? 0;
}

double _partQuotedExportFromMap(Map<dynamic, dynamic> p) {
  const keys = [
    'lscPrice', 'lsc_price', 'lscUnitPrice', 'lsc_unit_price', 'lscAmount', 'lsc_amount',
    'lineServicePrice', 'line_service_price', 'roLinePrice', 'ro_line_price',
    'giaXuatLsc', 'gia_xuat_lsc', 'giaBanLsc', 'gia_ban_lsc',
    'exportPrice', 'export_price', 'salePrice', 'sale_price', 'quotedPrice', 'quoted_price',
    'unitPrice', 'unit_price', 'linePrice', 'line_price', 'price', 'customerPrice', 'customer_price',
    'baoGia', 'bao_gia',
  ];
  for (final k in keys) {
    final v = p[k];
    if (v == null) continue;
    final d = _parseMoneyLoose(v.toString());
    if (d > 0) return d;
  }
  return 0;
}

String _partInventoryCategory(Map<dynamic, dynamic> p) {
  final s = _partMapStr(p, ['inventoryCategory', 'inventory_category', 'hangLoai', 'hang_loai', 'itemCategory', 'item_category']).toUpperCase();
  if (s.contains('CCDC') || s.contains('CONG_CU') || s == 'TOOL') return kInvCatCCDC;
  return kInvCatPhuTung;
}

double _quotedExportForMissingLine(Map<String, dynamic> line) {
  final flat = _partQuotedExportFromMap(line);
  if (flat > 0) return flat;
  try {
    final idx = line['partIndex'] is int ? line['partIndex'] as int : int.tryParse('${line['partIndex']}') ?? 0;
    final raw = line['rawParts'];
    final List<dynamic> list = raw is String ? (jsonDecode(raw) as List<dynamic>) : List<dynamic>.from(raw as List);
    if (idx >= 0 && idx < list.length && list[idx] is Map) {
      return _partQuotedExportFromMap(Map<dynamic, dynamic>.from(list[idx] as Map));
    }
  } catch (_) {}
  return 0;
}

void _applyKhoOrderedPartFields(
  Map<String, dynamic> m, {
  required String expectedDate,
  required String orderType,
  required String importPrice,
  required String supplier,
}) {
  final now = DateTime.now().toIso8601String();
  m['isOrdered'] = true;
  m['is_ordered'] = true;
  m['expectedDate'] = expectedDate;
  m['expected_date'] = expectedDate;
  m['orderedDate'] = now;
  m['ordered_date'] = now;
  m['orderType'] = orderType;
  m['order_type'] = orderType;
  m['importPrice'] = importPrice;
  m['import_price'] = importPrice;
  m['supplier'] = supplier;
}

class CurrencyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue.copyWith(text: '0');
    String cleanText = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    if (cleanText.isEmpty) return newValue.copyWith(text: '0');
    double value = double.parse(cleanText);
    return TextEditingValue(
      text: NumberFormat('#,###').format(value),
      selection: TextSelection.collapsed(offset: NumberFormat('#,###').format(value).length),
    );
  }
}

class InventoryItem {
  String id, code, name, location, lastUpdated, poCode, woCode, bienSo;
  int quantity;
  double importPrice, exportPrice;
  /// [kInvCatPhuTung] | [kInvCatCCDC]
  String inventoryCategory;

  InventoryItem({
    required this.id, required this.code, required this.name, required this.quantity,
    required this.importPrice, required this.exportPrice, required this.location,
    required this.lastUpdated, this.poCode = '', this.woCode = '', this.bienSo = '',
    this.inventoryCategory = kInvCatPhuTung,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'code': code, 'name': name, 'quantity': quantity,
    'importPrice': importPrice, 'exportPrice': exportPrice,
    'location': location, 'lastUpdated': lastUpdated,
    'poCode': poCode, 'woCode': woCode, 'bienSo': bienSo,
    'inventoryCategory': inventoryCategory,
  };

  factory InventoryItem.fromJson(Map<String, dynamic> json) => InventoryItem(
    id: json['id']?.toString() ?? '', code: json['code']?.toString() ?? '',
    name: json['name']?.toString() ?? '', quantity: json['quantity'] ?? 0,
    importPrice: double.tryParse(json['importPrice']?.toString() ?? '0') ?? 0,
    exportPrice: double.tryParse(json['exportPrice']?.toString() ?? '0') ?? 0,
    location: json['location']?.toString() ?? '', lastUpdated: json['lastUpdated']?.toString() ?? '',
    poCode: json['poCode']?.toString() ?? '', woCode: json['woCode']?.toString() ?? '', bienSo: json['bienSo']?.toString() ?? '',
    inventoryCategory: (json['inventoryCategory'] != null && json['inventoryCategory'].toString().trim().isNotEmpty)
        ? json['inventoryCategory'].toString()
        : kInvCatPhuTung,
  );
}

class TransactionItem {
  String id, date, type, partCode, partName, poCode, woCode, userName;
  int quantity;
  /// Giá nhập (NHẬP: từ phiếu nhập; XUẤT: TB có trọng số theo lô trừ tồn).
  double importPrice;
  /// Biển số xe liên quan dòng giao dịch.
  String bienSo;
  /// Vị trí kệ/kho tại thời điểm ghi nhận.
  String location;
  /// Giá xuất/báo giá từ lệnh CVDV (kho không nhập); 0 = không có.
  double quotedExportPrice;
  String inventoryCategory;

  TransactionItem({
    required this.id, required this.date, required this.type, required this.partCode,
    required this.partName, required this.quantity, required this.poCode,
    required this.woCode, required this.userName,
    this.importPrice = 0,
    this.bienSo = '',
    this.location = '',
    this.quotedExportPrice = 0,
    this.inventoryCategory = kInvCatPhuTung,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'date': date, 'type': type, 'partCode': partCode, 'partName': partName,
    'quantity': quantity, 'poCode': poCode, 'woCode': woCode, 'userName': userName,
    'importPrice': importPrice,
    'bienSo': bienSo,
    'location': location,
    'quotedExportPrice': quotedExportPrice,
    'inventoryCategory': inventoryCategory,
  };

  factory TransactionItem.fromJson(Map<String, dynamic> json) => TransactionItem(
    id: json['id']?.toString() ?? '', date: json['date']?.toString() ?? '',
    type: json['type']?.toString() ?? '', partCode: json['partCode']?.toString() ?? '',
    partName: json['partName']?.toString() ?? '', quantity: json['quantity'] ?? 0,
    poCode: json['poCode']?.toString() ?? '', woCode: json['woCode']?.toString() ?? '',
    userName: json['userName']?.toString() ?? '',
    importPrice: double.tryParse(json['importPrice']?.toString() ?? '0') ?? 0,
    bienSo: json['bienSo']?.toString() ?? '',
    location: json['location']?.toString() ?? '',
    quotedExportPrice: double.tryParse(json['quotedExportPrice']?.toString() ?? '0') ?? 0,
    inventoryCategory: (json['inventoryCategory'] != null && json['inventoryCategory'].toString().trim().isNotEmpty)
        ? json['inventoryCategory'].toString()
        : kInvCatPhuTung,
  );
}

class KhoScreen extends StatefulWidget {
  final LoginResult login;
  const KhoScreen({super.key, required this.login});
  @override
  State<KhoScreen> createState() => _KhoScreenState();
}

class _KhoScreenState extends State<KhoScreen> with SingleTickerProviderStateMixin {
  /// RO không cần theo dõi phụ tùng thiếu: đã đóng, đã ra cổng xong, hoặc đã hủy.
  /// Giữ [DA_RA_CONG_THIEU_PT] (không nằm trong tập này) — vẫn cần đặt/hẹn PT.
  static const Set<String> _excludedStatusesForMissingParts = {
    'HUY',
    'HUY_CHO_QUYET_TOAN',
    'DA_THANH_TOAN',
    'DA_RA_CONG',
    'XE_RA_XUONG',
    'KT_DUYET_RA_CONG',
  };

  late final ApiService api;
  bool isLoading = false;
  int _selectedIndex = 0; 
  
  final searchCtrl = TextEditingController();
  final outboundSearchCtrl = TextEditingController();
  /// Lọc màn PT thiếu (biển số, WO/RO, PO).
  final missingPartsSearchCtrl = TextEditingController();
  
  final ScrollController _hScroll1 = ScrollController();
  final ScrollController _vScroll1 = ScrollController();
  final ScrollController _hScroll2 = ScrollController();
  final ScrollController _vScroll2 = ScrollController();
  final ScrollController _hScroll2b = ScrollController();
  final ScrollController _vScroll2b = ScrollController();
  final ScrollController _hScroll3 = ScrollController();
  final ScrollController _vScroll3 = ScrollController();
  
  final String inventoryFilePath = 'kho_db.json';
  final String historyFilePath = 'kho_history.json';

  List<WorkOrderItem> activeOrders = []; 
  List<Map<String, dynamic>> missingParts = []; 
  List<InventoryItem> inventory = [];
  List<TransactionItem> transactions = [];

  Map<int, bool> outboundSelections = {};
  List<Map<String, dynamic>> outboundDisplayList = [];

  Map<String, DateTime> snoozedAlerts = {};
  List<Map<String, dynamic>> urgentAlerts = [];

  /// Dòng PT thiếu — chưa đặt: ô tick để đặt hàng loạt.
  final Set<String> _chuaDatSelected = {};

  /// Nhắc CVDV đã báo mà KHO chưa xác nhận đặt: tối đa mỗi 30 phút / dòng.
  final Map<String, DateTime> _lastCvdvChuaDatNotify = {};

  late TabController _missingTabController;
  int _serverUnreadNotifCount = 0;
  List<String> _cvdvBellLines = [];

  static const List<MapEntry<String, String>> _missingDaFilterCols = [
    MapEntry('bienSo', 'Biển số'),
    MapEntry('roCode', 'WO/RO'),
    MapEntry('systemRoCode', 'RO hệ thống'),
    MapEntry('poCode', 'PO'),
    MapEntry('partCode', 'Mã PT'),
    MapEntry('partName', 'Tên PT'),
    MapEntry('hangLoai', 'Loại hàng hoá'),
    MapEntry('qty', 'SL'),
    MapEntry('ktv', 'KTV'),
    MapEntry('status', 'TT lệnh'),
    MapEntry('wait', 'Đã chờ'),
    MapEntry('orderType', 'Loại ĐH'),
    MapEntry('expectedDate', 'Dự kiến'),
  ];

  static const List<MapEntry<String, String>> _missingChuaFilterCols = [
    MapEntry('bienSo', 'Biển số'),
    MapEntry('roCode', 'WO/RO'),
    MapEntry('systemRoCode', 'RO hệ thống'),
    MapEntry('poCode', 'PO'),
    MapEntry('partCode', 'Mã PT'),
    MapEntry('partName', 'Tên PT'),
    MapEntry('hangLoai', 'Loại hàng hoá'),
    MapEntry('qty', 'SL'),
    MapEntry('ktv', 'KTV'),
    MapEntry('status', 'TT lệnh'),
    MapEntry('wait', 'Đã chờ'),
    MapEntry('flow', 'Báo CVDV'),
  ];

  final Map<String, TextEditingController> _missingDaCol = {};
  final Map<String, TextEditingController> _missingChuaCol = {};

  static const List<MapEntry<String, String>> _invFilterCols = [
    MapEntry('code', 'Mã PT'),
    MapEntry('name', 'Tên PT'),
    MapEntry('hangLoai', 'Loại hàng hoá'),
    MapEntry('poCode', 'Mã PO'),
    MapEntry('woCode', 'Mã WO'),
    MapEntry('bienSo', 'Biển số'),
    MapEntry('qty', 'SL tồn'),
    MapEntry('location', 'Vị trí'),
    MapEntry('importPrice', 'Giá nhập'),
    MapEntry('exportPrice', 'Giá bán'),
    MapEntry('lastUpdated', 'Cập nhật'),
  ];

  static const List<MapEntry<String, String>> _historyFilterCols = [
    MapEntry('date', 'Thời gian'),
    MapEntry('type', 'Loại'),
    MapEntry('partCode', 'Mã PT'),
    MapEntry('partName', 'Tên PT'),
    MapEntry('hangLoai', 'Loại hàng hoá'),
    MapEntry('quantity', 'Số lượng'),
    MapEntry('importPrice', 'Giá nhập'),
    MapEntry('bienSo', 'Biển số xe'),
    MapEntry('location', 'Vị trí kho'),
    MapEntry('quotedExport', 'Giá xuất (LSC CVDV)'),
    MapEntry('poCode', 'Mã PO'),
    MapEntry('woCode', 'Mã WO'),
    MapEntry('userName', 'Người TH'),
  ];

  /// Cột xuất kho (không gồm ô tick).
  static const List<MapEntry<String, String>> _outboundColFilterCols = [
    MapEntry('bienSo', 'Biển số'),
    MapEntry('roCode', 'Mã WO'),
    MapEntry('partName', 'Tên PT'),
    MapEntry('partCode', 'Mã PT'),
    MapEntry('hangLoai', 'Loại hàng hoá'),
    MapEntry('qty', 'SL cần'),
    MapEntry('stock', 'Tồn'),
    MapEntry('viTri', 'Vị trí'),
  ];

  final Map<String, TextEditingController> _invCol = {};
  final Map<String, TextEditingController> _historyCol = {};
  final Map<String, TextEditingController> _outboundCol = {};

  String _inboundHangLoai = kInvCatPhuTung;
  final _ibCodeCtrl = TextEditingController();
  final _ibNameCtrl = TextEditingController();
  final _ibQtyCtrl = TextEditingController();
  final _ibImportPriceCtrl = TextEditingController();
  final _ibExportPriceCtrl = TextEditingController();
  final _ibSupplierCtrl = TextEditingController();
  final _ibLocationCtrl = TextEditingController();
  final _ibPoCtrl = TextEditingController();
  final _ibWoCtrl = TextEditingController();
  final _ibBienSoCtrl = TextEditingController();

  /// Sau GET board — nếu server chưa phản ánh ngay expectedDate trên dòng phẳng, đồng bộ từ UI vừa lưu.
  void _stompMissingRowsOrdered({
    required List<Map<String, dynamic>> targets,
    required String expectedDate,
    required String orderType,
    required String importPrice,
    required String supplier,
  }) {
    final now = DateTime.now().toIso8601String();
    for (final target in targets) {
      final key = _partLineKey(target);
      for (var i = 0; i < missingParts.length; i++) {
        if (_partLineKey(missingParts[i]) != key) continue;
        final row = Map<String, dynamic>.from(missingParts[i]);
        row['expectedDate'] = expectedDate;
        row['expected_date'] = expectedDate;
        row['isOrdered'] = true;
        row['is_ordered'] = true;
        row['orderType'] = orderType;
        row['order_type'] = orderType;
        row['importPrice'] = importPrice;
        row['import_price'] = importPrice;
        row['supplier'] = supplier;
        row['orderedDate'] = now;
        row['ordered_date'] = now;
        final idx = row['partIndex'] is int ? row['partIndex'] as int : int.tryParse('${row['partIndex']}') ?? 0;
        final rp = List<dynamic>.from(row['rawParts'] as List);
        final m = Map<String, dynamic>.from(rp[idx] as Map);
        _applyKhoOrderedPartFields(m, expectedDate: expectedDate, orderType: orderType, importPrice: importPrice, supplier: supplier);
        rp[idx] = m;
        row['rawParts'] = rp;
        missingParts[i] = row;
        break;
      }
    }
  }

  @override
  void initState() {
    super.initState();
    api = ApiService(baseUrl: widget.login.baseUrl);
    _missingTabController = TabController(length: 2, vsync: this);
    for (final e in _missingDaFilterCols) {
      _missingDaCol[e.key] = TextEditingController();
    }
    for (final e in _missingChuaFilterCols) {
      _missingChuaCol[e.key] = TextEditingController();
    }
    for (final e in _invFilterCols) {
      _invCol[e.key] = TextEditingController();
    }
    for (final e in _historyFilterCols) {
      _historyCol[e.key] = TextEditingController();
    }
    for (final e in _outboundColFilterCols) {
      _outboundCol[e.key] = TextEditingController();
    }
    _loadLocalData();
    _loadData();
  }

  @override
  void dispose() {
    searchCtrl.dispose();
    outboundSearchCtrl.dispose();
    missingPartsSearchCtrl.dispose();
    _missingTabController.dispose();
    for (final c in _missingDaCol.values) {
      c.dispose();
    }
    for (final c in _missingChuaCol.values) {
      c.dispose();
    }
    for (final c in _invCol.values) {
      c.dispose();
    }
    for (final c in _historyCol.values) {
      c.dispose();
    }
    for (final c in _outboundCol.values) {
      c.dispose();
    }
    _ibCodeCtrl.dispose();
    _ibNameCtrl.dispose();
    _ibQtyCtrl.dispose();
    _ibImportPriceCtrl.dispose();
    _ibExportPriceCtrl.dispose();
    _ibSupplierCtrl.dispose();
    _ibLocationCtrl.dispose();
    _ibPoCtrl.dispose();
    _ibWoCtrl.dispose();
    _ibBienSoCtrl.dispose();
    _hScroll1.dispose(); _vScroll1.dispose();
    _hScroll2.dispose(); _vScroll2.dispose();
    _hScroll2b.dispose(); _vScroll2b.dispose();
    _hScroll3.dispose(); _vScroll3.dispose();
    super.dispose();
  }

  Future<void> _loadLocalData() async {
    try {
      final inv = await loadWorkshopJson(
        fileName: inventoryFilePath,
        api: api,
        token: widget.login.token,
      );
      if (inv is List) {
        setState(() {
          inventory = inv.map<InventoryItem>((e) => InventoryItem.fromJson(Map<String, dynamic>.from(e as Map))).toList();
        });
      }
      final hist = await loadWorkshopJson(
        fileName: historyFilePath,
        api: api,
        token: widget.login.token,
      );
      if (hist is List) {
        setState(() {
          transactions = hist.map<TransactionItem>((e) => TransactionItem.fromJson(Map<String, dynamic>.from(e as Map))).toList();
        });
      }
    } catch (e) { debugPrint('Lỗi đọc local data: $e'); }
  }

  Future<void> _saveInventory() async {
    await saveWorkshopJson(
      fileName: inventoryFilePath,
      payload: inventory.map((e) => e.toJson()).toList(),
      api: api,
      token: widget.login.token,
    );
  }

  Future<void> _saveHistory() async {
    await saveWorkshopJson(
      fileName: historyFilePath,
      payload: transactions.map((e) => e.toJson()).toList(),
      api: api,
      token: widget.login.token,
    );
  }

  /// Sau nhập/xuất đủ PT — server báo CVDV (xe trong xưởng) hoặc KH (thiếu PT đã ra).
  Future<void> _notifyPartsArrivalForOrders(Set<String> orderIds) async {
    for (final oid in orderIds) {
      if (oid.isEmpty) continue;
      try {
        final r = await api.postPartArrivalNotify(token: widget.login.token, orderId: oid);
        if (!mounted) return;
        final n = r['notified']?.toString() ?? '';
        if (n == 'cvdv') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Đã báo CVDV: đủ phụ tùng — ${r['bien_so'] ?? oid}.'),
              backgroundColor: Colors.teal,
            ),
          );
        } else if (n.contains('customer')) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Đã báo Khách (app): đủ phụ tùng.'),
              backgroundColor: Colors.deepPurple,
            ),
          );
        }
      } catch (_) {}
    }
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    try {
      int unreadN = 0;
      try {
        final nlist = await api.fetchNotifications(widget.login.token);
        unreadN = nlist.where((e) {
          final r = e['read_at'];
          return r == null || (r is String && r.trim().isEmpty);
        }).length;
      } catch (_) {}

      final allOrders = await api.fetchBoard(widget.login.token);
      setState(() {
        _serverUnreadNotifCount = unreadN;
        activeOrders = allOrders.where((o) => !_excludedStatusesForMissingParts.contains(o.status)).toList();
        missingParts.clear();

        for (var order in activeOrders) {
          if (order.parts != null && order.parts.toString().isNotEmpty && order.parts.toString() != 'null') {
            try {
              List pList = (order.parts is String) ? jsonDecode(order.parts) : List.from(order.parts);
              for (int i = 0; i < pList.length; i++) {
                var p = pList[i];
                int issuedQty = int.tryParse(p['issuedQty']?.toString() ?? p['issued_qty']?.toString() ?? '0') ?? 0;
                double qty = double.tryParse(p['qty']?.toString() ?? p['quantity']?.toString() ?? '1') ?? 1;

                if (issuedQty < qty) {
                    final woForKho = order.cvdvWoCode.trim().isNotEmpty ? order.cvdvWoCode.trim() : order.roCode;
                    missingParts.add({
                      'orderId': order.id, 'partIndex': i, 'rawParts': pList,
                      'roCode': woForKho, 'bienSo': order.bienSo, 'status': order.status,
                      'systemRoCode': order.roCode,
                      'ktv': order.ktvUsername.isEmpty ? 'Chưa phân công' : order.ktvUsername,
                      'partCode': p['code']?.toString() ?? '',
                      'partName': p['name']?.toString() ?? 'Chưa có tên',
                      'qty': qty - issuedQty, 'timeIn': order.createdAt,
                      'isOrdered': p['isOrdered'] == true || p['isOrdered'] == 'true' || p['is_ordered'] == true || p['is_ordered'] == 'true',
                      'importPrice': _partMapStr(p, ['importPrice', 'import_price']),
                      'supplier': _partMapStr(p, ['supplier', 'supplier_name']),
                      'orderType': _partMapStr(p, ['orderType', 'order_type']).isEmpty ? 'Thường' : _partMapStr(p, ['orderType', 'order_type']),
                      'expectedDate': _partMapStr(p, ['expectedDate', 'expected_date', 'expected_delivery_date']),
                      'expected_date': _partMapStr(p, ['expectedDate', 'expected_date', 'expected_delivery_date']),
                      'orderedDate': _partMapStr(p, ['orderedDate', 'ordered_date']),
                      'khoBaoRequestedAt': _partMapStr(p, ['khoBaoRequestedAt', 'kho_bao_requested_at']),
                      'poCode': _partMapStr(p, ['poCode', 'po_code']),
                      'inventoryCategory': _partInventoryCategory(Map<dynamic, dynamic>.from(p as Map)),
                    });
                }
              }
            } catch (e) {}
          }
        }
      });
      _chuaDatSelected.removeWhere((k) => !missingParts.any((p) => _partLineKey(p) == k));
      _filterOutboundList();
      _checkLateOrders();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi kết nối: $e'), backgroundColor: Colors.red));
    } finally { setState(() => isLoading = false); }
  }

  void _showSLAAlertsDialog() {
    showDialog(
      context: context, barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.warning_amber, color: Colors.red, size: 30),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'CẢNH BÁO PT (quá dự kiến / quá SLA)',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ]),
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
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () { 
                      setState(() { snoozedAlerts[alert['key']] = DateTime.now(); urgentAlerts.remove(alert); });
                      Navigator.pop(ctx); 
                      if (urgentAlerts.isNotEmpty) _showSLAAlertsDialog(); 
                    }
                  )
                ]
              )
            )).toList()
          )
        ),
        actions: [
           FilledButton(
             onPressed: () { 
               for (var a in urgentAlerts) { snoozedAlerts[a['key']] = DateTime.now(); }
               setState(() { urgentAlerts.clear(); });
               Navigator.pop(ctx);
             }, 
             style: FilledButton.styleFrom(backgroundColor: Colors.red), 
             child: const Text('Đã hiểu (nhắc lại tối đa 1 lần/ngày / dòng)')
           )
        ],
      )
    );
  }

  int get _khoBellBadgeCount =>
      _serverUnreadNotifCount + urgentAlerts.length + (_cvdvBellLines.isNotEmpty ? 1 : 0);

  Future<void> _showKhoBellDialog() async {
    List<Map<String, dynamic>> notifs = [];
    try {
      notifs = await api.fetchNotifications(widget.login.token);
    } catch (_) {}

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.notifications_active, color: Colors.teal),
            SizedBox(width: 8),
            Text('Thông báo Kho', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 520,
          height: 440,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (notifs.isNotEmpty) ...[
                  const Text('Hệ thống / Kho', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
                  ...notifs.take(50).map(
                    (n) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.info_outline, size: 22),
                      title: Text(n['title']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(n['body']?.toString() ?? ''),
                    ),
                  ),
                  const Divider(),
                ],
                if (_cvdvBellLines.isNotEmpty) ...[
                  const Text('CVDV đã báo đặt — KHO chưa xác nhận (>1h)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                  ..._cvdvBellLines.map((t) => Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(t, style: const TextStyle(fontSize: 13)))),
                  const Divider(),
                ],
                if (urgentAlerts.isNotEmpty) ...[
                  const Text('Cảnh báo phụ tùng (quá hạn / SLA)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                  ...urgentAlerts.map(
                    (a) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(a['msg']?.toString() ?? '', style: const TextStyle(fontSize: 13)),
                    ),
                  ),
                ],
                if (notifs.isEmpty && _cvdvBellLines.isEmpty && urgentAlerts.isEmpty) const Text('Không có thông báo.', style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng (chưa đánh dấu đã đọc)')),
          FilledButton(
            onPressed: () async {
              for (final row in notifs) {
                final r = row['read_at'];
                final unread = r == null || (r is String && r.toString().trim().isEmpty);
                if (!unread) continue;
                final id = row['id']?.toString();
                if (id == null || id.isEmpty) continue;
                try {
                  await api.markNotificationRead(widget.login.token, id);
                } catch (_) {}
              }
              for (final a in urgentAlerts) {
                snoozedAlerts[a['key']?.toString() ?? ''] = DateTime.now();
              }
              if (mounted) {
                setState(() {
                  urgentAlerts.clear();
                  _cvdvBellLines.clear();
                  _serverUnreadNotifCount = 0;
                });
              }
              if (ctx.mounted) Navigator.pop(ctx);
              await _loadData();
            },
            child: const Text('Đã đọc xong'),
          ),
        ],
      ),
    );
  }

Future<void> _markOrderedStatus(Map<String, dynamic> partData, bool isOrdered) async {
    setState(() => isLoading = true);
    try {
      List rawParts = List.from(partData['rawParts']);
      int pIdx = partData['partIndex'];
      rawParts[pIdx]['isOrdered'] = isOrdered;
      rawParts[pIdx]['is_ordered'] = isOrdered;
      
      if (!isOrdered) {
         rawParts[pIdx]['importPrice'] = '';
         rawParts[pIdx]['import_price'] = '';
         rawParts[pIdx]['supplier'] = '';
         rawParts[pIdx]['orderType'] = '';
         rawParts[pIdx]['order_type'] = '';
         rawParts[pIdx]['expectedDate'] = '';
         rawParts[pIdx]['expected_date'] = '';
         rawParts[pIdx]['orderedDate'] = '';
         rawParts[pIdx]['ordered_date'] = '';
      }
      
      await api.updateRepairOrder(token: widget.login.token, id: partData['orderId'], status: partData['status'], parts: jsonEncode(rawParts));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isOrdered ? 'Đã chuyển sang: ĐÃ ĐẶT HÀNG' : 'Đã chuyển về: CHƯA ĐẶT'), backgroundColor: Colors.green));
      await _loadData();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi cập nhật: $e'), backgroundColor: Colors.red));
    } finally { setState(() => isLoading = false); }
  }

  void _showOrderPurchaseDialog(Map<String, dynamic> partData) {
     final importPriceCtrl = TextEditingController();
     final supplierCtrl = TextEditingController();
     final expectedDateCtrl = TextEditingController();
     String selectedType = 'Thường'; 

     showDialog(
       context: context, 
       builder: (ctx) => StatefulBuilder(
         builder: (context, setDialogState) {
           return AlertDialog(
             title: const Text('Xác nhận đặt hàng', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
             content: SizedBox(
               width: 450,
               child: Column(
                 mainAxisSize: MainAxisSize.min,
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                   Text('Món đồ: ${partData['partName']} (SL: ${partData['qty']})', style: const TextStyle(fontWeight: FontWeight.bold)),
                   const SizedBox(height: 16),
                   
                   Row(
                     children: [
                       const Text('Mức độ ưu tiên: ', style: TextStyle(fontWeight: FontWeight.bold)),
                       const SizedBox(width: 16),
                       ChoiceChip(
                         label: const Text('Thường (5 ngày)'),
                         selected: selectedType == 'Thường',
                         onSelected: (val) { if(val) setDialogState(() => selectedType = 'Thường'); },
                       ),
                       const SizedBox(width: 8),
                       ChoiceChip(
                         label: const Text('Khẩn cấp (3 ngày)'),
                         selected: selectedType == 'Khẩn',
                         selectedColor: Colors.red.shade100,
                         onSelected: (val) { if(val) setDialogState(() => selectedType = 'Khẩn'); },
                       ),
                     ],
                   ),
                   const SizedBox(height: 16),
                   
                   TextField(
                     controller: expectedDateCtrl,
                     readOnly: true,
                     decoration: const InputDecoration(labelText: 'Ngày dự kiến hàng về *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.calendar_month)),
                     onTap: () async {
                       DateTime? pickedDate = await showDatePicker(
                         context: context, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime(2030)
                       );
                       if (pickedDate != null) {
                         setDialogState(() { expectedDateCtrl.text = DateFormat('dd/MM/yyyy').format(pickedDate); });
                       }
                     },
                   ),
                   const SizedBox(height: 16),

                   TextField(controller: importPriceCtrl, keyboardType: TextInputType.number, inputFormatters: [CurrencyInputFormatter()], decoration: const InputDecoration(labelText: 'Giá Nhập (VNĐ)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.attach_money))),
                   const SizedBox(height: 16),
                   TextField(controller: supplierCtrl, decoration: const InputDecoration(labelText: 'Tên Nhà Cung Cấp (Nơi mua)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.store))),
                 ],
               ),
             ),
             actions: [
               TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
               FilledButton.icon(
                 onPressed: () async {
                   if (expectedDateCtrl.text.isEmpty) {
                     ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng chọn ngày dự kiến hàng về!'), backgroundColor: Colors.red));
                     return;
                   }
                   Navigator.pop(ctx);
                   setState(() => isLoading = true);
                   try {
                     List rawParts = List.from(partData['rawParts']);
                     int pIdx = partData['partIndex'] is int ? partData['partIndex'] as int : int.tryParse('${partData['partIndex']}') ?? 0;
                     final m = Map<String, dynamic>.from(rawParts[pIdx] as Map);
                     _applyKhoOrderedPartFields(
                       m,
                       expectedDate: expectedDateCtrl.text,
                       orderType: selectedType,
                       importPrice: importPriceCtrl.text,
                       supplier: supplierCtrl.text,
                     );
                     rawParts[pIdx] = m;
                     
                     await api.updateRepairOrder(token: widget.login.token, id: partData['orderId'], status: partData['status'], parts: jsonEncode(rawParts));
                     if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã chuyển sang trạng thái: ĐÃ ĐẶT HÀNG'), backgroundColor: Colors.green));
                     await _loadData();
                     if (mounted) {
                       setState(() {
                         _stompMissingRowsOrdered(
                           targets: [partData],
                           expectedDate: expectedDateCtrl.text.trim(),
                           orderType: selectedType,
                           importPrice: importPriceCtrl.text,
                           supplier: supplierCtrl.text,
                         );
                       });
                       _checkLateOrders();
                       _missingTabController.animateTo(1);
                     }
                   } catch(e) {
                     if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi cập nhật: $e'), backgroundColor: Colors.red));
                   } finally { setState(() => isLoading = false); }
                 }, 
                 icon: const Icon(Icons.check), label: const Text('XÁC NHẬN ĐÃ ĐẶT')
               )
             ],
           );
         }
       )
     );
  }

  Future<void> _showBatchOrderPurchaseDialog() async {
    final selectedRows = _missingChuaDatList.where((p) => _chuaDatSelected.contains(_partLineKey(p))).toList();
    if (selectedRows.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chọn ít nhất một dòng ở tab Chưa đặt.'), backgroundColor: Colors.orange),
        );
      }
      return;
    }

    final importPriceCtrl = TextEditingController();
    final supplierCtrl = TextEditingController();
    final expectedDateCtrl = TextEditingController();
    String selectedType = 'Thường';

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('Xác nhận đặt hàng (${selectedRows.length} dòng)', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
            content: SizedBox(
              width: 450,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Áp dụng chung: ngày dự kiến, loại đặt, giá nhập, NCC cho tất cả dòng đã chọn.', style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text('Mức độ: ', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('Thường (5 ngày)'),
                          selected: selectedType == 'Thường',
                          onSelected: (val) {
                            if (val) setDialogState(() => selectedType = 'Thường');
                          },
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('Khẩn (3 ngày)'),
                          selected: selectedType == 'Khẩn',
                          selectedColor: Colors.red.shade100,
                          onSelected: (val) {
                            if (val) setDialogState(() => selectedType = 'Khẩn');
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: expectedDateCtrl,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Ngày dự kiến hàng về *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.calendar_month),
                      ),
                      onTap: () async {
                        final pickedDate = await showDatePicker(
                          context: ctx,
                          initialDate: DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate: DateTime(2035),
                        );
                        if (pickedDate != null) {
                          setDialogState(() {
                            expectedDateCtrl.text = DateFormat('dd/MM/yyyy').format(pickedDate);
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: importPriceCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [CurrencyInputFormatter()],
                      decoration: const InputDecoration(labelText: 'Giá Nhập (VNĐ)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.attach_money)),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: supplierCtrl,
                      decoration: const InputDecoration(labelText: 'Nhà cung cấp', border: OutlineInputBorder(), prefixIcon: Icon(Icons.store)),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
              FilledButton.icon(
                icon: const Icon(Icons.check),
                label: const Text('XÁC NHẬN ĐÃ ĐẶT'),
                onPressed: () async {
                  if (expectedDateCtrl.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng chọn ngày dự kiến hàng về!'), backgroundColor: Colors.red));
                    return;
                  }
                  Navigator.pop(ctx);
                  setState(() => isLoading = true);
                  try {
                    final Map<String, List<Map<String, dynamic>>> byOrder = {};
                    for (final row in selectedRows) {
                      final oid = row['orderId'].toString();
                      byOrder.putIfAbsent(oid, () => []).add(row);
                    }
                    for (final entry in byOrder.entries) {
                      final rows = entry.value;
                      final base = rows.first;
                      final rawDyn = List<dynamic>.from(base['rawParts'] as List);
                      final rawParts = rawDyn.map((e) => Map<String, dynamic>.from(e as Map)).toList();
                      for (final r in rows) {
                        final pIdx = r['partIndex'] is int ? r['partIndex'] as int : int.tryParse('${r['partIndex']}') ?? 0;
                        final m = Map<String, dynamic>.from(rawParts[pIdx] as Map);
                        _applyKhoOrderedPartFields(
                          m,
                          expectedDate: expectedDateCtrl.text,
                          orderType: selectedType,
                          importPrice: importPriceCtrl.text,
                          supplier: supplierCtrl.text,
                        );
                        rawParts[pIdx] = m;
                      }
                      await api.updateRepairOrder(
                        token: widget.login.token,
                        id: base['orderId'].toString(),
                        status: base['status'].toString(),
                        parts: jsonEncode(rawParts),
                      );
                    }
                    _chuaDatSelected.clear();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Đã xác nhận đặt ${selectedRows.length} dòng.'), backgroundColor: Colors.green),
                      );
                    }
                    await _loadData();
                    if (mounted) {
                      setState(() {
                        _stompMissingRowsOrdered(
                          targets: selectedRows,
                          expectedDate: expectedDateCtrl.text.trim(),
                          orderType: selectedType,
                          importPrice: importPriceCtrl.text,
                          supplier: supplierCtrl.text,
                        );
                      });
                      _checkLateOrders();
                      _missingTabController.animateTo(1);
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red));
                    }
                  } finally {
                    if (mounted) setState(() => isLoading = false);
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  String _formatVND(double value) {
    return value.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');
  }

  /// Đơn giá nhập trung bình (có trọng số SL) khi xuất từ nhiều lô tồn.
  double _txnAvgImportLots(List<InventoryItem> items, List<int> amounts, int qtyOut) {
    if (qtyOut <= 0 || items.length != amounts.length) return 0;
    var sum = 0.0;
    for (var j = 0; j < items.length; j++) {
      sum += items[j].importPrice * amounts[j];
    }
    return sum / qtyOut;
  }

  String _txnLocLots(List<InventoryItem> items, List<int> amounts) {
    final seen = <String>{};
    for (var j = 0; j < items.length; j++) {
      if (amounts[j] <= 0) continue;
      final s = items[j].location.trim();
      if (s.isNotEmpty) seen.add(s);
    }
    return seen.join('; ');
  }

  Widget _filterHdr(Map<String, TextEditingController> m, String key, String title) {
    return ColumnFilterMenuHeader(
      title: title,
      filterController: m[key]!,
      onFiltersChanged: () => setState(() {}),
    );
  }

  String _calculateWaitTime(DateTime? timeIn) => formatWaitSinceDateTime(timeIn, ifNull: '-');

  String _partLineKey(Map<String, dynamic> p) => '${p['orderId']}_${p['partIndex']}';

  /// KHO đã xác nhận đặt (có ngày dự kiến về) — khác với chỉ CVDV "báo sang KHO".
  bool _khoDaXacNhanDat(Map<String, dynamic> p) {
    return _expectedDateForMissingLine(p).isNotEmpty;
  }

  String _chuaDatFlowLabel(Map<String, dynamic> p) {
    if ((p['khoBaoRequestedAt']?.toString().trim() ?? '').isNotEmpty) return 'CVDV đã báo';
    return 'Chưa báo';
  }

  List<Map<String, dynamic>> get _missingDaDat =>
      missingParts.where((p) => _khoDaXacNhanDat(p)).toList();

  List<Map<String, dynamic>> get _missingChuaDatList =>
      missingParts.where((p) => !_khoDaXacNhanDat(p)).toList();

  DateTime? _tryParseDdMmYyyy(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final parts = s.split(RegExp(r'[/\-.]'));
    if (parts.length != 3) return null;
    final d = int.tryParse(parts[0].trim());
    final m = int.tryParse(parts[1].trim());
    final y = int.tryParse(parts[2].trim());
    if (d == null || m == null || y == null) return null;
    try {
      return DateTime(y, m, d);
    } catch (_) {
      return null;
    }
  }

  DateTime _dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);

  List<Map<String, dynamic>> _filterMissingSearch(List<Map<String, dynamic>> src) {
    final q = missingPartsSearchCtrl.text.trim().toLowerCase().replaceAll(RegExp(r'[\s-]'), '');
    if (q.isEmpty) return src;
    String norm(String? s) => (s ?? '').toLowerCase().replaceAll(RegExp(r'[\s-]'), '');
    return src.where((p) {
      return norm(p['bienSo']?.toString()).contains(q) ||
          norm(p['roCode']?.toString()).contains(q) ||
          norm(p['systemRoCode']?.toString()).contains(q) ||
          norm(p['poCode']?.toString()).contains(q);
    }).toList();
  }

  List<Map<String, dynamic>> _pipelineMissingDaDat() {
    final base = _filterMissingSearch(_missingDaDat);
    final filters = _missingDaFilterCols.map((e) => _missingDaCol[e.key]!.text).toList();
    return base.where((p) {
      final ti = p['timeIn'];
      final DateTime? tIn = ti is DateTime ? ti : DateTime.tryParse(ti?.toString() ?? '');
      final cells = <String>[
        p['bienSo']?.toString() ?? '',
        p['roCode']?.toString() ?? '',
        p['systemRoCode']?.toString() ?? '',
        (p['poCode']?.toString() ?? '').isEmpty ? '' : p['poCode'].toString(),
        p['partCode']?.toString() ?? '',
        p['partName']?.toString() ?? '',
        _invCatLabel(p['inventoryCategory']?.toString()),
        '${p['qty']}',
        p['ktv']?.toString() ?? '',
        p['status']?.toString() ?? '',
        _calculateWaitTime(tIn),
        p['orderType']?.toString() ?? '',
        _expectedDateForMissingLine(p),
      ];
      return cellsMatchFilters(filters, cells);
    }).toList();
  }

  List<Map<String, dynamic>> _pipelineMissingChuaDat() {
    final base = _filterMissingSearch(_missingChuaDatList);
    final filters = _missingChuaFilterCols.map((e) => _missingChuaCol[e.key]!.text).toList();
    return base.where((p) {
      final ti = p['timeIn'];
      final DateTime? tIn = ti is DateTime ? ti : DateTime.tryParse(ti?.toString() ?? '');
      final cells = <String>[
        p['bienSo']?.toString() ?? '',
        p['roCode']?.toString() ?? '',
        p['systemRoCode']?.toString() ?? '',
        (p['poCode']?.toString() ?? '').isEmpty ? '' : p['poCode'].toString(),
        p['partCode']?.toString() ?? '',
        p['partName']?.toString() ?? '',
        _invCatLabel(p['inventoryCategory']?.toString()),
        '${p['qty']}',
        p['ktv']?.toString() ?? '',
        p['status']?.toString() ?? '',
        _calculateWaitTime(tIn),
        _chuaDatFlowLabel(p),
      ];
      return cellsMatchFilters(filters, cells);
    }).toList();
  }

  List<InventoryItem> _pipelineInventory(List<InventoryItem> base) {
    final filters = _invFilterCols.map((e) => _invCol[e.key]!.text).toList();
    return base.where((item) {
      final cells = <String>[
        item.code,
        item.name,
        _invCatLabel(item.inventoryCategory),
        item.poCode.isEmpty ? '-' : item.poCode,
        item.woCode.isEmpty ? 'Kho Chung' : item.woCode,
        item.bienSo.isEmpty ? '-' : item.bienSo,
        '${item.quantity}',
        item.location.isEmpty ? '-' : item.location,
        '${_formatVND(item.importPrice)} đ',
        '${_formatVND(item.exportPrice)} đ',
        item.lastUpdated,
      ];
      return cellsMatchFilters(filters, cells);
    }).toList();
  }

  List<TransactionItem> _pipelineHistory() {
    final filters = _historyFilterCols.map((e) => _historyCol[e.key]!.text).toList();
    return transactions.where((t) {
      final cells = <String>[
        t.date,
        t.type,
        t.partCode,
        t.partName,
        _invCatLabel(t.inventoryCategory),
        (t.type == 'NHẬP' ? '+' : '-') + t.quantity.toString(),
        t.importPrice > 0 ? '${_formatVND(t.importPrice)} đ' : '—',
        t.bienSo.trim().isEmpty ? '—' : t.bienSo,
        t.location.trim().isEmpty ? '—' : t.location,
        t.quotedExportPrice > 0 ? '${_formatVND(t.quotedExportPrice)} đ' : '—',
        t.poCode.isEmpty ? '-' : t.poCode,
        t.woCode.isEmpty ? '-' : t.woCode,
        t.userName,
      ];
      return cellsMatchFilters(filters, cells);
    }).toList();
  }

  List<String> _outboundRowFilterCells(Map<String, dynamic> p) {
    final qtyNeeded = (p['qty'] as num).toInt();
    final String pCode = p['partCode'].toString().toLowerCase().replaceAll(' ', '');
    final String pWo = p['roCode'].toString().toUpperCase();
    int privateStock = 0;
    int publicStock = 0;
    String viTri = 'Không xác định';
    for (final inv in inventory) {
      if (inv.code.toLowerCase() == pCode) {
        if (inv.woCode.toUpperCase() == pWo) {
          privateStock += inv.quantity;
          viTri = inv.location;
        } else if (inv.woCode.isEmpty) {
          publicStock += inv.quantity;
          if (viTri == 'Không xác định') viTri = inv.location;
        }
      }
    }
    final totalAvail = privateStock + publicStock;
    final canFulfill = totalAvail >= qtyNeeded;
    final stockLabel =
        canFulfill ? 'Đủ hàng ($totalAvail)' : 'Thiếu hàng (Còn $totalAvail)';
    return <String>[
      p['bienSo']?.toString() ?? '',
      p['roCode']?.toString() ?? '',
      p['partName']?.toString() ?? '',
      p['partCode']?.toString() ?? '',
      _invCatLabel(p['inventoryCategory']?.toString()),
      '$qtyNeeded',
      stockLabel,
      viTri,
    ];
  }

  List<int> _outboundFilteredIndices() {
    final filters = _outboundColFilterCols.map((e) => _outboundCol[e.key]!.text).toList();
    final out = <int>[];
    for (var i = 0; i < outboundDisplayList.length; i++) {
      if (cellsMatchFilters(filters, _outboundRowFilterCells(outboundDisplayList[i]))) {
        out.add(i);
      }
    }
    return out;
  }

  void _checkLateOrders() {
    urgentAlerts.clear();
    final now = DateTime.now();
    final today = _dateOnly(now);

    final List<String> cvdvSnackLines = [];

    for (final p in missingParts) {
      final partKey = _partLineKey(p);
      final partName = p['partName']?.toString() ?? '';
      final bien = p['bienSo']?.toString() ?? '';
      final ro = p['roCode']?.toString() ?? '';

      if (!_khoDaXacNhanDat(p)) {
        final reqRaw = p['khoBaoRequestedAt']?.toString().trim() ?? '';
        if (reqRaw.isNotEmpty) {
          final reqAt = DateTime.tryParse(reqRaw);
          if (reqAt != null && now.difference(reqAt).inMinutes >= 60) {
            final last = _lastCvdvChuaDatNotify[partKey];
            if (last == null || now.difference(last).inMinutes >= 30) {
              _lastCvdvChuaDatNotify[partKey] = now;
              cvdvSnackLines.add('• $partName — $bien ($ro)');
            }
          }
        }
      }

      if (!_khoDaXacNhanDat(p)) continue;

      String? alertMsg;
      final expStr = _expectedDateForMissingLine(p).trim();
      final expDt = _tryParseDdMmYyyy(expStr);
      if (expDt != null) {
        if (today.isAfter(_dateOnly(expDt))) {
          alertMsg = '📅 Quá ngày dự kiến về ($expStr): $partName — xe $bien ($ro) vẫn chưa đủ xuất kho.';
        }
      } else {
        final odRaw = _partMapStr(p, ['orderedDate', 'ordered_date']).trim();
        final orderedDate = DateTime.tryParse(odRaw);
        if (orderedDate != null) {
          final diffDays = now.difference(orderedDate).inDays;
          final ot = _partMapStr(p, ['orderType', 'order_type']).trim();
          final isKhan = (ot == 'Khẩn');
          if ((isKhan && diffDays >= 3) || (!isKhan && diffDays >= 5)) {
            alertMsg = isKhan
                ? '🚨 Hàng KHẨN: $partName (xe $bien) đã ${diffDays} ngày kể từ khi đặt, chưa có ngày dự kiến / chưa về đủ.'
                : '⚠️ Hàng THƯỜNG: $partName (xe $bien) đã ${diffDays} ngày kể từ khi đặt, chưa có ngày dự kiến / chưa về đủ.';
          }
        }
      }

      if (alertMsg != null) {
        final alertKey = 'over_${p['orderId']}_${p['partCode']}';
        if (snoozedAlerts.containsKey(alertKey)) {
          if (now.difference(snoozedAlerts[alertKey]!).inHours >= 24) {
            urgentAlerts.add({'key': alertKey, 'msg': alertMsg});
          }
        } else {
          urgentAlerts.add({'key': alertKey, 'msg': alertMsg});
        }
      }
    }

    _cvdvBellLines = cvdvSnackLines;
    if (mounted) setState(() {});
  }

  Future<void> _importInventoryExcel() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      withData: true,
    );
    if (result != null) {
      setState(() => isLoading = true);
      try {
        final picked = await bytesFromPickerFile(result.files.single);
        if (picked == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Không đọc được file Excel.'), backgroundColor: Colors.red),
            );
          }
          return;
        }
        var bytes = picked;
        var excel = Excel.decodeBytes(bytes);
        int addedCount = 0;

        for (var table in excel.tables.values) {
          for (int i = 5; i < table.rows.length; i++) { 
            var row = table.rows[i];
            if (row.length >= 14) {
              String code = row[1]?.value?.toString().trim() ?? '';
              String name = row[2]?.value?.toString().trim() ?? '';
              int qty = int.tryParse(row[10]?.value?.toString().trim() ?? '0') ?? 0;
              double exportPrice = double.tryParse(row[13]?.value?.toString().trim() ?? '0') ?? 0;
              final String cat = row.length >= 13 ? _invCatFromExcelCell(row[12]?.value?.toString()) : kInvCatPhuTung;

              if (code.isNotEmpty && name.isNotEmpty) {
                 int existingIdx = inventory.indexWhere((e) => e.code.toLowerCase() == code.toLowerCase() && e.woCode == '');
                 if (existingIdx >= 0) {
                     inventory[existingIdx].quantity = qty;
                     inventory[existingIdx].exportPrice = exportPrice;
                     inventory[existingIdx].inventoryCategory = cat;
                     inventory[existingIdx].lastUpdated = DateTime.now().toString().substring(0, 10);
                 } else {
                     inventory.add(InventoryItem(
                        id: DateTime.now().millisecondsSinceEpoch.toString() + i.toString(),
                        code: code, name: name, quantity: qty,
                        importPrice: 0, exportPrice: exportPrice,
                        location: 'Chưa rõ', lastUpdated: DateTime.now().toString().substring(0, 10),
                        poCode: '', woCode: '', bienSo: '',
                        inventoryCategory: cat,
                     ));
                 }
                 addedCount++;
              }
            }
          }
        }
        await _saveInventory();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã nạp / cập nhật thành công $addedCount mã Phụ tùng!'), backgroundColor: Colors.green));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi đọc file: $e'), backgroundColor: Colors.red));
      } finally { setState(() => isLoading = false); }
    }
  }

  Future<void> _exportInventoryReport() async {
    setState(() => isLoading = true);
    try {
      var excel = Excel.createExcel();
      Sheet sheet = excel['TỔNG HỢP TỒN KHO'];
      excel.setDefaultSheet('TỔNG HỢP TỒN KHO');
      
      sheet.appendRow([TextCellValue('TỔNG HỢP TỒN KHO')]);
      sheet.appendRow([TextCellValue('Chi nhánh: CTy Thái Thanh, Kho: Kho hàng hóa Thái Thanh')]);
      sheet.appendRow([TextCellValue('')]);
      sheet.appendRow([
        TextCellValue('Tên kho'), TextCellValue('Mã hàng'), TextCellValue('Tên hàng'), TextCellValue('ĐVT'),
        TextCellValue('Đầu kỳ'), TextCellValue(''), TextCellValue('Nhập kho'), TextCellValue(''),
        TextCellValue('Xuất kho'), TextCellValue(''),         TextCellValue('Cuối kỳ'), TextCellValue(''),
        TextCellValue('Loại hàng hoá'), TextCellValue('Đơn giá bán 1'), TextCellValue('Đơn giá bán 2'), TextCellValue('Đơn giá cố định')
      ]);
      sheet.appendRow([
        TextCellValue(''), TextCellValue(''), TextCellValue(''), TextCellValue(''),
        TextCellValue('Số lượng'), TextCellValue('Giá trị'), TextCellValue('Số lượng'), TextCellValue('Giá trị'),
        TextCellValue('Số lượng'), TextCellValue('Giá trị'), TextCellValue('Số lượng'), TextCellValue('Giá trị'),
        TextCellValue(''), TextCellValue(''), TextCellValue(''), TextCellValue('')
      ]);

      for (var item in inventory) {
        sheet.appendRow([
          TextCellValue('Kho hàng hóa Thái Thanh'), TextCellValue(item.code), TextCellValue(item.name), TextCellValue('Cái'),
          IntCellValue(0), IntCellValue(0), IntCellValue(0), IntCellValue(0), IntCellValue(0), IntCellValue(0),
          IntCellValue(item.quantity), DoubleCellValue(item.quantity * item.importPrice),
          TextCellValue(_invCatLabel(item.inventoryCategory)), DoubleCellValue(item.exportPrice), IntCellValue(0), DoubleCellValue(item.exportPrice)
        ]);
      }

      if (excel.tables.containsKey('Sheet1')) { excel.delete('Sheet1'); }

      final fileName = 'TonKho_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final result = await saveExcelBytes(
        bytes: excel.save(),
        fileName: fileName,
        dialogTitle: 'Tồn kho',
      );
      if (mounted) {
        showCrossPlatformSaveSnackBar(context, result, fileName, successExtra: 'Báo cáo tồn kho');
      }
    } catch (e) {
       if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi xuất file: $e'), backgroundColor: Colors.red));
    } finally { setState(() => isLoading = false); }
  }

  Future<void> _exportMissingPartsReport() async {
    if (missingParts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không có phụ tùng nào bị thiếu để xuất báo cáo.'), backgroundColor: Colors.orange));
      return;
    }
    final daDat = _missingDaDat;
    final chuaDat = _missingChuaDatList;

    setState(() => isLoading = true);
    try {
      var excel = Excel.createExcel();

      final header = [
        TextCellValue('Biển Số Xe'),
        TextCellValue('Mã WO/RO'),
        TextCellValue('Mã RO hệ thống'),
        TextCellValue('Mã PO'),
        TextCellValue('Tên Phụ Tùng'),
        TextCellValue('Mã Phụ Tùng'),
        TextCellValue('Loại hàng hoá'),
        TextCellValue('SL thiếu'),
        TextCellValue('TT lệnh'),
        TextCellValue('KTV'),
        TextCellValue('Đã chờ'),
        TextCellValue('Loại đặt'),
        TextCellValue('Dự kiến về'),
        TextCellValue('Giá nhập'),
        TextCellValue('NCC'),
        TextCellValue('CVDV báo lúc'),
      ];

      Sheet sheetDa = excel['Da_dat_hang'];
      excel.setDefaultSheet('Da_dat_hang');
      sheetDa.appendRow(header);

      Sheet sheetChua = excel['Chua_dat_hang'];
      sheetChua.appendRow(header);

      void appendRow(Sheet sh, Map<String, dynamic> p) {
        final ti = p['timeIn'];
        final DateTime? tIn = ti is DateTime ? ti : DateTime.tryParse(ti?.toString() ?? '');
        sh.appendRow([
          TextCellValue(p['bienSo']?.toString() ?? ''),
          TextCellValue(p['roCode']?.toString() ?? ''),
          TextCellValue(p['systemRoCode']?.toString() ?? ''),
          TextCellValue(p['poCode']?.toString() ?? ''),
          TextCellValue(p['partName']?.toString() ?? ''),
          TextCellValue(p['partCode']?.toString() ?? ''),
          TextCellValue(_invCatLabel(p['inventoryCategory']?.toString())),
          DoubleCellValue(double.tryParse(p['qty'].toString()) ?? 0),
          TextCellValue(p['status']?.toString() ?? ''),
          TextCellValue(p['ktv']?.toString() ?? ''),
          TextCellValue(_calculateWaitTime(tIn)),
          TextCellValue(p['orderType']?.toString() ?? ''),
          TextCellValue(p['expectedDate']?.toString() ?? ''),
          TextCellValue(p['importPrice']?.toString() ?? ''),
          TextCellValue(p['supplier']?.toString() ?? ''),
          TextCellValue(p['khoBaoRequestedAt']?.toString() ?? ''),
        ]);
      }

      for (var p in daDat) {
        appendRow(sheetDa, p);
      }
      for (var p in chuaDat) {
        appendRow(sheetChua, p);
      }

      if (excel.tables.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      final fileName = 'DanhSachDatHangPT_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final result = await saveExcelBytes(
        bytes: excel.save(),
        fileName: fileName,
        dialogTitle: 'Danh sách đặt hàng PT',
      );
      if (mounted) {
        showCrossPlatformSaveSnackBar(
          context,
          result,
          fileName,
          successExtra: result.ok ? '2 sheet: Da_dat_hang & Chua_dat_hang' : null,
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi xuất file: $e'), backgroundColor: Colors.red));
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _exportHistoryExcel() async {
    if (transactions.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chưa có lịch sử để xuất.'), backgroundColor: Colors.orange),
        );
      }
      return;
    }
    setState(() => isLoading = true);
    try {
      final rows = _pipelineHistory();
      final excel = Excel.createExcel();
      final sh = excel['Lich_su_xuat_nhap'];
      excel.setDefaultSheet('Lich_su_xuat_nhap');
      sh.appendRow([
        TextCellValue('Thời gian'),
        TextCellValue('Loại'),
        TextCellValue('Mã PT'),
        TextCellValue('Tên PT'),
        TextCellValue('Loại hàng hoá'),
        TextCellValue('Số lượng'),
        TextCellValue('Giá nhập'),
        TextCellValue('Biển số xe'),
        TextCellValue('Vị trí kho'),
        TextCellValue('Giá xuất (LSC CVDV)'),
        TextCellValue('Mã PO'),
        TextCellValue('Mã WO'),
        TextCellValue('Người TH'),
      ]);
      for (final t in rows) {
        final qtyStr = (t.type == 'NHẬP' ? '+' : '-') + t.quantity.toString();
        sh.appendRow([
          TextCellValue(t.date),
          TextCellValue(t.type),
          TextCellValue(t.partCode),
          TextCellValue(t.partName),
          TextCellValue(_invCatLabel(t.inventoryCategory)),
          TextCellValue(qtyStr),
          TextCellValue(t.importPrice > 0 ? _formatVND(t.importPrice) : ''),
          TextCellValue(t.bienSo.trim().isEmpty ? '—' : t.bienSo),
          TextCellValue(t.location.trim().isEmpty ? '—' : t.location),
          TextCellValue(t.quotedExportPrice > 0 ? _formatVND(t.quotedExportPrice) : ''),
          TextCellValue(t.poCode.isEmpty ? '-' : t.poCode),
          TextCellValue(t.woCode.isEmpty ? '-' : t.woCode),
          TextCellValue(t.userName),
        ]);
      }
      if (excel.tables.containsKey('Sheet1')) excel.delete('Sheet1');
      final fileName = 'LichSuKho_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final result = await saveExcelBytes(
        bytes: excel.save(),
        fileName: fileName,
        dialogTitle: 'Lịch sử nhập/xuất',
      );
      if (mounted) {
        showCrossPlatformSaveSnackBar(
          context,
          result,
          fileName,
          successExtra: result.ok ? '${rows.length} dòng' : null,
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi xuất file: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _filterOutboundList() {
    String query = outboundSearchCtrl.text.trim().toLowerCase().replaceAll(RegExp(r'[\s-]'), '');
    outboundDisplayList = missingParts.where((item) {
      if (query.isEmpty) return true;
      String norm(String? s) => (s ?? '').toLowerCase().replaceAll(RegExp(r'[\s-]'), '');
      final q = query;
      return norm(item['roCode']?.toString()).contains(q) ||
          norm(item['bienSo']?.toString()).contains(q) ||
          norm(item['systemRoCode']?.toString()).contains(q) ||
          norm(item['poCode']?.toString()).contains(q);
    }).toList();

    Map<int, bool> newSelections = {};
    for (int i = 0; i < outboundDisplayList.length; i++) {
       newSelections[i] = outboundSelections.containsKey(i) ? outboundSelections[i]! : false;
    }
    outboundSelections = newSelections;
  }

  void _openOcrDialog() {
    final textCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dán văn bản OCR từ Ảnh', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Dùng điện thoại (Zalo/Google Lens) quét chữ từ Phiếu Yêu Cầu Xuất Kho và dán vào đây.', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 12),
              TextField(
                controller: textCtrl,
                maxLines: 8,
                decoration: const InputDecoration(
                  hintText: 'Dán đoạn chữ đọc được vào đây...\nVD: RO: SVC30000314\nMã số: BEX10003701',
                  border: OutlineInputBorder(),
                ),
              ),
            ]
          )
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton.icon(
            icon: const Icon(Icons.auto_awesome),
            label: const Text('LỌC VÀ CHỌN TỰ ĐỘNG'),
            onPressed: () {
              Navigator.pop(ctx);
              _processOcrText(textCtrl.text);
            },
          )
        ],
      )
    );
  }

  void _processOcrText(String text) {
    if (text.isEmpty) return;

    String foundRoCode = '';
    final roRegex = RegExp(r'(RO-\d+|SVC\d+|[A-Z0-9]+-WO-[A-Z0-9\-\.]+)', caseSensitive: false);
    final roMatch = roRegex.firstMatch(text);
    
    if (roMatch != null) {
        foundRoCode = roMatch.group(0)?.toUpperCase() ?? '';
        outboundSearchCtrl.text = foundRoCode; 
    }

    _filterOutboundList();

    int matchedCount = 0;
    if (outboundDisplayList.isNotEmpty) {
        for (int i = 0; i < outboundDisplayList.length; i++) {
            String pCode = outboundDisplayList[i]['partCode'].toString().toLowerCase();
            String cleanText = text.replaceAll(' ', '').toLowerCase();
            String cleanPCode = pCode.replaceAll(' ', '');

            if (cleanText.contains(cleanPCode) && cleanPCode.isNotEmpty) { 
                outboundSelections[i] = true;
                matchedCount++;
            }
        }
    }

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Tìm thấy Lệnh: ${foundRoCode.isEmpty ? 'Không rõ' : foundRoCode}. Đã tự động chọn $matchedCount phụ tùng khớp trên phiếu!'), 
      backgroundColor: Colors.green
    ));
    setState(() {}); 
  }

  Future<void> _pickStockSlipImageOcr() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 2000);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    var fn = x.name;
    if (fn.isEmpty) fn = 'slip.jpg';
    if (!mounted) return;
    setState(() => isLoading = true);
    try {
      final text = await api.ocrStockSlip(token: widget.login.token, imageBytes: bytes, filename: fn);
      if (!mounted) return;
      if (text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('OCR không đọc được chữ trên ảnh. Thử ảnh rõ hơn hoặc dán văn bản.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      _processOcrText(text);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('OCR ảnh: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Widget _buildInventoryTab() {
    String query = searchCtrl.text.trim().toLowerCase();
    List<InventoryItem> displayList = inventory.where((item) => 
       query.isEmpty || item.name.toLowerCase().contains(query) || item.code.toLowerCase().contains(query) || 
       item.poCode.toLowerCase().contains(query) || item.woCode.toLowerCase().contains(query) || item.bienSo.toLowerCase().contains(query)
    ).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Danh Sách Tồn Kho', 
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))
            ),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _importInventoryExcel, 
                  icon: const Icon(Icons.file_upload, color: Colors.green), 
                  label: const Text('Import Excel', style: TextStyle(color: Colors.green))
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _exportInventoryReport, 
                  icon: const Icon(Icons.file_download, color: Colors.blue), 
                  label: const Text('Export Tồn Kho')
                ),
              ],
            )
          ]
        ),
        const SizedBox(height: 16),
        TextField(
          controller: searchCtrl,
          onChanged: (val) => setState((){}),
          decoration: InputDecoration(
            hintText: 'Tìm kiếm mã PT, tên PT, Mã PO, Mã WO, Biển số...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: query.isNotEmpty ? IconButton(icon: const Icon(Icons.clear), onPressed: (){ searchCtrl.clear(); setState((){}); }) : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: () {
              if (inventory.isEmpty) {
                return const Center(
                  child: Text('Chưa có dữ liệu tồn kho.', style: TextStyle(color: Colors.grey, fontSize: 16)),
                );
              }
              final invFiltered = _pipelineInventory(displayList);
              final emptyFilter = invFiltered.isEmpty;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Scrollbar(
                controller: _hScroll1,
                thumbVisibility: true,
                trackVisibility: true,
                child: SingleChildScrollView(
                  controller: _hScroll1,
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 200),
                    child: Scrollbar(
                      controller: _vScroll1,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        controller: _vScroll1,
                        child: DataTable(
                          headingRowColor: MaterialStateProperty.all(Colors.blueGrey.shade50),
                          dataRowMinHeight: 50,
                          dataRowMaxHeight: 60,
                          columnSpacing: 25,
                          columns: [
                            DataColumn(label: _filterHdr(_invCol, 'code', 'Mã PT')),
                            DataColumn(label: _filterHdr(_invCol, 'name', 'Tên Phụ Tùng')),
                            DataColumn(label: _filterHdr(_invCol, 'hangLoai', 'Loại hàng hoá')),
                            DataColumn(label: _filterHdr(_invCol, 'poCode', 'Mã PO')),
                            DataColumn(label: _filterHdr(_invCol, 'woCode', 'Mã WO')),
                            DataColumn(label: _filterHdr(_invCol, 'bienSo', 'Biển Số Xe')),
                            DataColumn(label: _filterHdr(_invCol, 'qty', 'Số Lượng Tồn')),
                            DataColumn(label: _filterHdr(_invCol, 'location', 'Vị Trí')),
                            DataColumn(label: _filterHdr(_invCol, 'importPrice', 'Giá Nhập')),
                            DataColumn(label: _filterHdr(_invCol, 'exportPrice', 'Giá Bán (RO)')),
                            DataColumn(label: _filterHdr(_invCol, 'lastUpdated', 'Cập nhật')),
                          ],
                          rows: invFiltered.map((item) {
                            bool isLowStock = item.quantity < 5;
                            return DataRow(
                              cells: [
                                DataCell(SelectableText(item.code, style: const TextStyle(fontWeight: FontWeight.bold))),
                                DataCell(SelectableText(item.name)),
                                DataCell(Text(_invCatLabel(item.inventoryCategory), style: const TextStyle(fontWeight: FontWeight.w600))),
                                DataCell(SelectableText(item.poCode.isEmpty ? '-' : item.poCode, style: const TextStyle(color: Colors.blue))),
                                DataCell(SelectableText(item.woCode.isEmpty ? 'Kho Chung' : item.woCode, style: TextStyle(fontWeight: FontWeight.bold, color: item.woCode.isEmpty ? Colors.green : Colors.deepOrange))),
                                DataCell(SelectableText(item.bienSo.isEmpty ? '-' : item.bienSo, style: const TextStyle(fontWeight: FontWeight.bold))),
                                DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: isLowStock ? Colors.red.shade100 : Colors.green.shade100,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      item.quantity.toString(),
                                      style: TextStyle(
                                        color: isLowStock ? Colors.red : Colors.green.shade800,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                DataCell(SelectableText(item.location.isEmpty ? '-' : item.location)),
                                DataCell(Text('${_formatVND(item.importPrice)} đ')),
                                DataCell(Text('${_formatVND(item.exportPrice)} đ')),
                                DataCell(Text(item.lastUpdated)),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
                  ),
                  if (emptyFilter)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Text(
                        displayList.isEmpty
                            ? 'Không có dòng khớp tìm kiếm.'
                            : 'Không có dòng khớp lọc cột. Mở menu tam giác trên tiêu đề cột → «Xóa lọc cột» để xem lại.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
                      ),
                    ),
                ],
              );
            }(),
          ),
        )
      ],
    );
  }

  Widget _buildInboundTab() {
    return Center(
      child: Container(
        width: 800,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.move_to_inbox, color: Colors.blue, size: 32),
                  SizedBox(width: 12),
                  Text('NHẬP KHO (INBOUND)', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blue)),
                ],
              ),
              const SizedBox(height: 8),
              const Text('Cập nhật số lượng mới nhập vào xưởng (phân loại Phụ tùng / Công cụ dụng cụ).', style: TextStyle(color: Colors.grey)),
              const Divider(height: 40),
              const Text('Loại hàng hoá', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: Color(0xFF1E293B))),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment<String>(value: kInvCatPhuTung, label: Text('Phụ tùng'), icon: Icon(Icons.precision_manufacturing_outlined)),
                  ButtonSegment<String>(value: kInvCatCCDC, label: Text('Công cụ dụng cụ'), icon: Icon(Icons.construction)),
                ],
                selected: {_inboundHangLoai},
                onSelectionChanged: (s) => setState(() => _inboundHangLoai = s.first),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: TextField(controller: _ibCodeCtrl, decoration: const InputDecoration(labelText: 'Mã Phụ Tùng *', border: OutlineInputBorder()))),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: TextField(controller: _ibNameCtrl, decoration: const InputDecoration(labelText: 'Tên Phụ Tùng *', border: OutlineInputBorder()))),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: TextField(controller: _ibPoCtrl, decoration: const InputDecoration(labelText: 'Mã PO (Tùy chọn)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.article)))),
                  const SizedBox(width: 16),
                  Expanded(child: TextField(controller: _ibWoCtrl, decoration: const InputDecoration(labelText: 'Mã WO (Tùy chọn)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.build)))),
                  const SizedBox(width: 16),
                  Expanded(child: TextField(controller: _ibBienSoCtrl, decoration: const InputDecoration(labelText: 'Biển Số Xe (Tùy chọn)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.directions_car)))),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: TextField(controller: _ibQtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Số Lượng Nhập *', border: OutlineInputBorder()))),
                  const SizedBox(width: 16),
                  Expanded(child: TextField(controller: _ibImportPriceCtrl, keyboardType: TextInputType.number, inputFormatters: [CurrencyInputFormatter()], decoration: const InputDecoration(labelText: 'Giá Nhập (VNĐ)', border: OutlineInputBorder()))),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _ibExportPriceCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [CurrencyInputFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Giá bán gợi ý (VNĐ)',
                        helperText: 'Gợi ý tồn; giá xuất theo báo giá CVDV hiện ở tab Lịch sử khi xuất RO',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: TextField(controller: _ibSupplierCtrl, decoration: const InputDecoration(labelText: 'Nhà Cung Cấp', border: OutlineInputBorder()))),
                  const SizedBox(width: 16),
                  Expanded(child: TextField(controller: _ibLocationCtrl, decoration: const InputDecoration(labelText: 'Vị Trí Cất Giữ (Kệ / Tầng)', border: OutlineInputBorder()))),
                ],
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: FilledButton.icon(
                  onPressed: () async {
                    if (_ibCodeCtrl.text.isEmpty || _ibNameCtrl.text.isEmpty || _ibQtyCtrl.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng nhập đủ các trường có dấu *'), backgroundColor: Colors.red));
                      return;
                    }

                    String po = _ibPoCtrl.text.trim().toUpperCase();
                    String wo = _ibWoCtrl.text.trim().toUpperCase();
                    String bs = _ibBienSoCtrl.text.trim().toUpperCase();
                    int qty = int.tryParse(_ibQtyCtrl.text) ?? 0;
                    String inputCode = _ibCodeCtrl.text.trim().toLowerCase();

                    // Nhập kho chỉ tăng tồn — KHÔNG cộng issuedQty (xuất cho xe chỉ ở tab Xuất kho).
                    if (wo.isNotEmpty || bs.isNotEmpty) {
                      final reserved = missingParts.where((p) {
                        final pWo = p['roCode'].toString().toUpperCase();
                        final pBs = p['bienSo'].toString().toUpperCase();
                        final pCode = p['partCode'].toString().toLowerCase();
                        return pCode == inputCode && (pWo == wo || pBs.contains(bs));
                      }).toList();
                      if (reserved.isNotEmpty && qty > 0) {
                        final first = reserved.first;
                        final needed = (first['qty'] as num?)?.toInt() ?? 0;
                        if (qty > needed && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Nhập $qty cái cho WO/biển $wo — phần dư sẽ vào tồn kho chung. '
                                'Xuất cho xe: dùng tab «Xuất kho».',
                              ),
                              backgroundColor: Colors.blue.shade800,
                              duration: const Duration(seconds: 6),
                            ),
                          );
                        }
                      }
                    }

                    setState(() {
                      int existingIdx = inventory.indexWhere((e) => e.code.toLowerCase() == inputCode && e.woCode == wo);

                      if (existingIdx >= 0) {
                        inventory[existingIdx].quantity += qty;
                        inventory[existingIdx].lastUpdated = DateTime.now().toString().substring(0, 10);
                        inventory[existingIdx].inventoryCategory = _inboundHangLoai;
                        if (po.isNotEmpty) inventory[existingIdx].poCode = po;
                        if (bs.isNotEmpty) inventory[existingIdx].bienSo = bs;
                        if (_ibLocationCtrl.text.isNotEmpty) inventory[existingIdx].location = _ibLocationCtrl.text;
                      } else {
                        inventory.add(InventoryItem(
                          id: DateTime.now().millisecondsSinceEpoch.toString(),
                          code: _ibCodeCtrl.text,
                          name: _ibNameCtrl.text,
                          quantity: qty,
                          importPrice: double.tryParse(_ibImportPriceCtrl.text.replaceAll(',', '')) ?? 0,
                          exportPrice: double.tryParse(_ibExportPriceCtrl.text.replaceAll(',', '')) ?? 0,
                          location: _ibLocationCtrl.text,
                          lastUpdated: DateTime.now().toString().substring(0, 10),
                          poCode: po,
                          woCode: wo,
                          bienSo: bs,
                          inventoryCategory: _inboundHangLoai,
                        ));
                      }

                      transactions.insert(
                        0,
                        TransactionItem(
                          id: DateTime.now().millisecondsSinceEpoch.toString(),
                          date: DateTime.now().toString().substring(0, 16),
                          type: 'NHẬP',
                          partCode: _ibCodeCtrl.text,
                          partName: _ibNameCtrl.text,
                          quantity: qty,
                          poCode: po,
                          woCode: wo,
                          userName: widget.login.userName,
                          importPrice: double.tryParse(_ibImportPriceCtrl.text.replaceAll(',', '')) ?? 0,
                          bienSo: bs,
                          location: _ibLocationCtrl.text.trim(),
                          quotedExportPrice: 0,
                          inventoryCategory: _inboundHangLoai,
                        ),
                      );
                    });

                    await _saveInventory();
                    await _saveHistory();
                    await _loadData();

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nhập kho thành công!'), backgroundColor: Colors.green));
                      setState(() {
                        _selectedIndex = 0;
                        _ibCodeCtrl.clear();
                        _ibNameCtrl.clear();
                        _ibQtyCtrl.clear();
                        _ibImportPriceCtrl.clear();
                        _ibExportPriceCtrl.clear();
                        _ibSupplierCtrl.clear();
                        _ibLocationCtrl.clear();
                        _ibPoCtrl.clear();
                        _ibWoCtrl.clear();
                        _ibBienSoCtrl.clear();
                      });
                    }
                  },
                  icon: const Icon(Icons.check_circle, size: 24),
                  label: const Text('XÁC NHẬN NHẬP KHO', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOutboundTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Row(
              children: [
                Icon(Icons.outbox, color: Colors.teal, size: 32),
                SizedBox(width: 12),
                Text('XUẤT KHO THÔNG MINH', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.teal)),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.icon(
                  onPressed: isLoading ? null : _pickStockSlipImageOcr,
                  icon: const Icon(Icons.image_search),
                  label: const Text('ẢNH PHIẾU (OCR)', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: FilledButton.styleFrom(backgroundColor: Colors.deepPurple),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _openOcrDialog,
                  icon: const Icon(Icons.document_scanner),
                  label: const Text('DÁN VĂN BẢN', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: FilledButton.styleFrom(backgroundColor: Colors.indigo),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text('Gõ Biển số, Mã WO, PO… Hoặc chọn ảnh phiếu (server OCR) / dán văn bản để tự động tick xuất đồ.', style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 24),
        
        TextField(
          controller: outboundSearchCtrl,
          onChanged: (val) {
            setState(() { _filterOutboundList(); });
          },
          decoration: InputDecoration(
            hintText: 'Biển số, Mã WO, PO… (hoặc ảnh / dán phiếu)',
            prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true, fillColor: Colors.white,
          ),
        ),
        const SizedBox(height: 24),
        Expanded(
          child: outboundDisplayList.isEmpty
              ? Center(
                  child: Text(
                    outboundSearchCtrl.text.isEmpty
                        ? 'Hãy nhập/dán nội dung phiếu xuất để lấy danh sách cần xuất.'
                        : 'Không tìm thấy phụ tùng đang chờ cho từ khóa này!',
                    style: const TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: () {
                        final vis = _outboundFilteredIndices();
                        final emptyFilter = vis.isEmpty;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: Container(
                          width: double.infinity,
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
                          child: Scrollbar(
                            controller: _hScroll3,
                            thumbVisibility: true,
                            trackVisibility: true,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              controller: _hScroll3,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 200),
                                child: Scrollbar(
                                  controller: _vScroll3,
                                  thumbVisibility: true,
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.vertical,
                                    controller: _vScroll3,
                                    child: DataTable(
                                      headingRowColor: MaterialStateProperty.all(Colors.teal.shade50),
                                      columnSpacing: 25,
                                      dataRowMinHeight: 50,
                                      dataRowMaxHeight: 60,
                                      columns: [
                                        DataColumn(
                                          label: Checkbox(
                                            value: vis.isNotEmpty && vis.every((i) => outboundSelections[i] == true),
                                            onChanged: (bool? value) {
                                              setState(() {
                                                final v = value ?? false;
                                                for (final i in vis) {
                                                  outboundSelections[i] = v;
                                                }
                                              });
                                            },
                                          ),
                                        ),
                                        DataColumn(label: _filterHdr(_outboundCol, 'bienSo', 'Biển Số')),
                                        DataColumn(label: _filterHdr(_outboundCol, 'roCode', 'Mã WO')),
                                        DataColumn(label: _filterHdr(_outboundCol, 'partName', 'Tên Phụ Tùng')),
                                        DataColumn(label: _filterHdr(_outboundCol, 'partCode', 'Mã PT')),
                                        DataColumn(label: _filterHdr(_outboundCol, 'hangLoai', 'Loại hàng hoá')),
                                        DataColumn(label: _filterHdr(_outboundCol, 'qty', 'SL Cần')),
                                        DataColumn(label: _filterHdr(_outboundCol, 'stock', 'Tình trạng Tồn Kho')),
                                        DataColumn(label: _filterHdr(_outboundCol, 'viTri', 'Vị Trí Cất')),
                                      ],
                                      rows: vis.map((index) {
                                        var p = outboundDisplayList[index];
                                        int qtyNeeded = (p['qty'] as num).toInt();
                                        String pCode = p['partCode'].toString().toLowerCase().replaceAll(' ', '');
                                        String pWo = p['roCode'].toString().toUpperCase();

                                        int privateStock = 0;
                                        int publicStock = 0;
                                        String viTri = 'Không xác định';

                                        for (var inv in inventory) {
                                          if (inv.code.toLowerCase() == pCode) {
                                            if (inv.woCode.toUpperCase() == pWo) {
                                              privateStock += inv.quantity;
                                              viTri = inv.location;
                                            } else if (inv.woCode.isEmpty) {
                                              publicStock += inv.quantity;
                                              if (viTri == 'Không xác định') viTri = inv.location;
                                            }
                                          }
                                        }

                                        int totalAvail = privateStock + publicStock;
                                        bool canFulfill = totalAvail >= qtyNeeded;

                                        return DataRow(
                                          cells: [
                                            DataCell(
                                              Checkbox(
                                                value: outboundSelections[index] == true,
                                                onChanged: (bool? value) {
                                                  setState(() {
                                                    outboundSelections[index] = value ?? false;
                                                  });
                                                },
                                              ),
                                            ),
                                            DataCell(SelectableText(p['bienSo'], style: const TextStyle(fontWeight: FontWeight.bold))),
                                            DataCell(SelectableText(p['roCode'])),
                                            DataCell(SelectableText(p['partName'])),
                                            DataCell(SelectableText(p['partCode'])),
                                            DataCell(Text(_invCatLabel(p['inventoryCategory']?.toString()), style: const TextStyle(fontWeight: FontWeight.w600))),
                                            DataCell(Text(qtyNeeded.toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                                            DataCell(
                                              canFulfill
                                                  ? Row(children: [
                                                      const Icon(Icons.check_circle, color: Colors.green, size: 16),
                                                      const SizedBox(width: 4),
                                                      Text('Đủ hàng ($totalAvail)', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                                                    ])
                                                  : Row(children: [
                                                      const Icon(Icons.error, color: Colors.red, size: 16),
                                                      const SizedBox(width: 4),
                                                      Text('Thiếu hàng (Còn $totalAvail)', style: const TextStyle(color: Colors.red)),
                                                    ]),
                                            ),
                                            DataCell(Text(viTri, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))),
                                          ],
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                          ),
                          if (emptyFilter)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: Text(
                                'Không có dòng nào khớp lọc cột. Mở menu tam giác trên tiêu đề cột → «Xóa lọc cột» để xem lại.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
                              ),
                            ),
                        ],
                      );
                      }(),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        if (outboundDisplayList.isNotEmpty)
          SizedBox(
            width: double.infinity, height: 55,
            child: FilledButton.icon(
              onPressed: () async {
                  bool hasSelection = false;
                  for (var v in outboundSelections.values) { if (v) hasSelection = true; }
                  if (!hasSelection) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng tick chọn ít nhất 1 phụ tùng để xuất!'), backgroundColor: Colors.orange));
                      return;
                  }
                  
                  setState(() => isLoading = true);
                  
                  final Set<String> ordersToNotify = {};
                  try {
                      for (int i = 0; i < outboundDisplayList.length; i++) {
                          if (outboundSelections[i] == true) {
                              var p = outboundDisplayList[i];
                              int qtyNeeded = (p['qty'] as num).toInt();
                              String inputCode = p['partCode'].toString().toLowerCase().replaceAll(' ', '');
                              String inputWo = p['roCode'].toString().toUpperCase();
                              
                              int remainingNeeded = qtyNeeded;
                              List<InventoryItem> itemsToDeduct = [];
                              List<int> deductAmounts = [];
                              String nameForHistory = p['partName'];

                              int privateStockCheck = 0;
                              int publicStockCheck = 0;
                              for(var inv in inventory) {
                                 String invCode = inv.code.toLowerCase().replaceAll(' ', '');
                                 if(invCode == inputCode) {
                                    if(inv.woCode.toUpperCase() == inputWo) privateStockCheck += inv.quantity;
                                    else if(inv.woCode.isEmpty) publicStockCheck += inv.quantity;
                                 }
                              }
                              if (privateStockCheck + publicStockCheck < qtyNeeded) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: PT [${p['partName']}] không đủ số lượng tồn kho để xuất!'), backgroundColor: Colors.red));
                                  continue; 
                              }
  
                              for (var item in inventory) {
                                 String invCode = item.code.toLowerCase().replaceAll(' ', '');
                                 if (invCode == inputCode && item.woCode.toUpperCase() == inputWo && item.quantity > 0) {
                                     int take = item.quantity >= remainingNeeded ? remainingNeeded : item.quantity;
                                     itemsToDeduct.add(item); deductAmounts.add(take); remainingNeeded -= take;
                                     if (remainingNeeded == 0) break;
                                 }
                              }
  
                              if (remainingNeeded > 0) {
                                  bool blockRobbery = false;
                                  String olderWo = '';
  
                                  for (var waitP in missingParts) {
                                      String wPCode = waitP['partCode'].toString().toLowerCase().replaceAll(' ', '');
                                      if (wPCode == inputCode) {
                                          String waitWo = waitP['roCode'].toString().toUpperCase();
                                          if (waitWo != inputWo) {
                                              blockRobbery = true; olderWo = waitWo; break;
                                          } else { break; }
                                      }
                                  }
  
                                  if (blockRobbery) {
                                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Không xuất được ${p['partName']}. Cần ưu tiên cho lệnh [$olderWo] đợi trước.'), backgroundColor: Colors.red));
                                      continue; 
                                  }
  
                                  for (var item in inventory) {
                                     String invCode = item.code.toLowerCase().replaceAll(' ', '');
                                     if (invCode == inputCode && item.woCode == '' && item.quantity > 0) {
                                         int take = item.quantity >= remainingNeeded ? remainingNeeded : item.quantity;
                                         itemsToDeduct.add(item); deductAmounts.add(take); remainingNeeded -= take;
                                         if (remainingNeeded == 0) break;
                                     }
                                  }
                              }
  
                              if (remainingNeeded == 0) {
                                  for (int j = 0; j < itemsToDeduct.length; j++) {
                                    itemsToDeduct[j].quantity -= deductAmounts[j];
                                    itemsToDeduct[j].lastUpdated = DateTime.now().toString().substring(0, 10);
                                  }

                                  final avgImp = _txnAvgImportLots(itemsToDeduct, deductAmounts, qtyNeeded);
                                  final locTx = _txnLocLots(itemsToDeduct, deductAmounts);
                                  final bsTx = (p['bienSo'] ?? '').toString().trim();

                                  transactions.insert(0, TransactionItem(
                                       id: DateTime.now().millisecondsSinceEpoch.toString() + i.toString(),
                                       date: DateTime.now().toString().substring(0, 16),
                                       type: 'XUẤT', partCode: p['partCode'], partName: nameForHistory, quantity: qtyNeeded,
                                       poCode: '', woCode: inputWo, userName: widget.login.userName,
                                       importPrice: avgImp,
                                       bienSo: bsTx,
                                       location: locTx,
                                       quotedExportPrice: _quotedExportForMissingLine(p),
                                       inventoryCategory: p['inventoryCategory']?.toString() ?? kInvCatPhuTung,
                                  ));
                                  
                                  List rawParts = List.from(p['rawParts']);
                                  int pIdx = p['partIndex'] is int ? p['partIndex'] as int : int.tryParse('${p['partIndex']}') ?? 0;
                                  int currentIssued = int.tryParse(rawParts[pIdx]['issuedQty']?.toString() ?? rawParts[pIdx]['issued_qty']?.toString() ?? '0') ?? 0;
                                  rawParts[pIdx]['issuedQty'] = currentIssued + qtyNeeded;
                                  rawParts[pIdx]['issued_qty'] = currentIssued + qtyNeeded;
                                  await api.updateRepairOrder(token: widget.login.token, id: p['orderId'], status: p['status'], parts: jsonEncode(rawParts));
                                  ordersToNotify.add(p['orderId'].toString());
                              }
                          }
                      }

                      await _notifyPartsArrivalForOrders(ordersToNotify);
  
                      await _saveInventory();
                      await _saveHistory();
                      await _loadData(); 
  
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Xuất kho thành công các PT hợp lệ!'), backgroundColor: Colors.green));
                      setState(() { _selectedIndex = 4; outboundSearchCtrl.clear(); }); 
                  } catch(e) {} finally { setState(() => isLoading = false); }
              }, 
              icon: const Icon(Icons.outbox, size: 24),
              style: FilledButton.styleFrom(backgroundColor: Colors.teal),
              label: const Text('XUẤT CÁC PHỤ TÙNG ĐÃ CHỌN', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            )
          )
      ],
    );
  }

  Widget _wrapPtTableScroll(ScrollController hCtrl, ScrollController vCtrl, DataTable table) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Scrollbar(
        controller: hCtrl,
        thumbVisibility: true,
        trackVisibility: true,
        child: SingleChildScrollView(
          controller: hCtrl,
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 200),
            child: Scrollbar(
              controller: vCtrl,
              thumbVisibility: true,
              trackVisibility: true,
              child: SingleChildScrollView(
                controller: vCtrl,
                scrollDirection: Axis.vertical,
                child: table,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMissingPartsDaDatTable() {
    final noOrders = _missingDaDat.isEmpty;
    final items = noOrders ? <Map<String, dynamic>>[] : _pipelineMissingDaDat();
    final emptyFilter = !noOrders && items.isEmpty;
    final table = DataTable(
      headingRowColor: MaterialStateProperty.all(Colors.green.shade50),
      columnSpacing: 16,
      dataRowMinHeight: 48,
      dataRowMaxHeight: 64,
      columns: [
        DataColumn(label: _filterHdr(_missingDaCol, 'bienSo', 'Biển số')),
        DataColumn(label: _filterHdr(_missingDaCol, 'roCode', 'WO/RO')),
        DataColumn(label: _filterHdr(_missingDaCol, 'systemRoCode', 'RO hệ thống')),
        DataColumn(label: _filterHdr(_missingDaCol, 'poCode', 'PO')),
        DataColumn(label: _filterHdr(_missingDaCol, 'partCode', 'Mã PT')),
        DataColumn(label: _filterHdr(_missingDaCol, 'partName', 'Tên PT')),
        DataColumn(label: _filterHdr(_missingDaCol, 'hangLoai', 'Loại hàng hoá')),
        DataColumn(label: _filterHdr(_missingDaCol, 'qty', 'SL thiếu')),
        DataColumn(label: _filterHdr(_missingDaCol, 'ktv', 'KTV')),
        DataColumn(label: _filterHdr(_missingDaCol, 'status', 'TT lệnh')),
        DataColumn(label: _filterHdr(_missingDaCol, 'wait', 'Đã chờ')),
        DataColumn(label: _filterHdr(_missingDaCol, 'orderType', 'Loại ĐH')),
        DataColumn(label: _filterHdr(_missingDaCol, 'expectedDate', 'Dự kiến về')),
        const DataColumn(label: Text('', style: TextStyle(fontWeight: FontWeight.bold))),
      ],
      rows: items.map((p) {
        final ti = p['timeIn'];
        final DateTime? tIn = ti is DateTime ? ti : DateTime.tryParse(ti?.toString() ?? '');
        return DataRow(
          cells: [
            DataCell(Text(p['bienSo']?.toString() ?? '')),
            DataCell(Text(p['roCode']?.toString() ?? '')),
            DataCell(Text(p['systemRoCode']?.toString() ?? '')),
            DataCell(Text((p['poCode']?.toString() ?? '').isEmpty ? '—' : p['poCode'].toString())),
            DataCell(SelectableText(p['partCode']?.toString() ?? '')),
            DataCell(SizedBox(width: 180, child: Text(p['partName']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis))),
            DataCell(Text(_invCatLabel(p['inventoryCategory']?.toString()), style: const TextStyle(fontWeight: FontWeight.w600))),
            DataCell(Text('${p['qty']}')),
            DataCell(Text(p['ktv']?.toString() ?? '')),
            DataCell(Text(p['status']?.toString() ?? '')),
            DataCell(Text(_calculateWaitTime(tIn))),
            DataCell(Text(p['orderType']?.toString() ?? '')),
            DataCell(Text(_expectedDateForMissingLine(p))),
            DataCell(
              IconButton(
                tooltip: 'Sửa thông tin đặt',
                icon: const Icon(Icons.edit_note, color: Colors.blue),
                onPressed: isLoading ? null : () => _showOrderPurchaseDialog(p),
              ),
            ),
          ],
        );
      }).toList(),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _wrapPtTableScroll(_hScroll2, _vScroll2, table)),
        if (noOrders || emptyFilter)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Text(
              noOrders
                  ? 'Không có dòng KHO đã xác nhận đặt (có ngày dự kiến).'
                  : 'Không có dòng khớp tìm kiếm / lọc cột. Mở menu tam giác trên tiêu đề cột → «Xóa lọc cột».',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
            ),
          ),
      ],
    );
  }

  Widget _buildMissingPartsChuaDatTable() {
    final noOrders = _missingChuaDatList.isEmpty;
    final items = noOrders ? <Map<String, dynamic>>[] : _pipelineMissingChuaDat();
    final emptyFilter = !noOrders && items.isEmpty;
    final allKeys = items.map((p) => _partLineKey(p)).toSet();
    final allSelected = allKeys.isNotEmpty && allKeys.every((k) => _chuaDatSelected.contains(k));

    final table = DataTable(
      headingRowColor: MaterialStateProperty.all(Colors.orange.shade50),
      columnSpacing: 12,
      dataRowMinHeight: 48,
      dataRowMaxHeight: 64,
      columns: [
        DataColumn(
          label: Checkbox(
            value: allSelected,
            onChanged: (_) {
              setState(() {
                if (allSelected) {
                  for (final k in allKeys) {
                    _chuaDatSelected.remove(k);
                  }
                } else {
                  for (final k in allKeys) {
                    _chuaDatSelected.add(k);
                  }
                }
              });
            },
          ),
        ),
        DataColumn(label: _filterHdr(_missingChuaCol, 'bienSo', 'Biển số')),
        DataColumn(label: _filterHdr(_missingChuaCol, 'roCode', 'WO/RO')),
        DataColumn(label: _filterHdr(_missingChuaCol, 'systemRoCode', 'RO hệ thống')),
        DataColumn(label: _filterHdr(_missingChuaCol, 'poCode', 'PO')),
        DataColumn(label: _filterHdr(_missingChuaCol, 'partCode', 'Mã PT')),
        DataColumn(label: _filterHdr(_missingChuaCol, 'partName', 'Tên PT')),
        DataColumn(label: _filterHdr(_missingChuaCol, 'hangLoai', 'Loại hàng hoá')),
        DataColumn(label: _filterHdr(_missingChuaCol, 'qty', 'SL thiếu')),
        DataColumn(label: _filterHdr(_missingChuaCol, 'ktv', 'KTV')),
        DataColumn(label: _filterHdr(_missingChuaCol, 'status', 'TT lệnh')),
        DataColumn(label: _filterHdr(_missingChuaCol, 'wait', 'Đã chờ')),
        DataColumn(label: _filterHdr(_missingChuaCol, 'flow', 'Báo CVDV')),
        const DataColumn(label: Text('', style: TextStyle(fontWeight: FontWeight.bold))),
      ],
      rows: items.map((p) {
        final key = _partLineKey(p);
        final ti = p['timeIn'];
        final DateTime? tIn = ti is DateTime ? ti : DateTime.tryParse(ti?.toString() ?? '');
        final sel = _chuaDatSelected.contains(key);
        return DataRow(
          cells: [
            DataCell(
              Checkbox(
                value: sel,
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      _chuaDatSelected.add(key);
                    } else {
                      _chuaDatSelected.remove(key);
                    }
                  });
                },
              ),
            ),
            DataCell(Text(p['bienSo']?.toString() ?? '')),
            DataCell(Text(p['roCode']?.toString() ?? '')),
            DataCell(Text(p['systemRoCode']?.toString() ?? '')),
            DataCell(Text((p['poCode']?.toString() ?? '').isEmpty ? '—' : p['poCode'].toString())),
            DataCell(SelectableText(p['partCode']?.toString() ?? '')),
            DataCell(SizedBox(width: 160, child: Text(p['partName']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis))),
            DataCell(Text(_invCatLabel(p['inventoryCategory']?.toString()), style: const TextStyle(fontWeight: FontWeight.w600))),
            DataCell(Text('${p['qty']}')),
            DataCell(Text(p['ktv']?.toString() ?? '')),
            DataCell(Text(p['status']?.toString() ?? '')),
            DataCell(Text(_calculateWaitTime(tIn))),
            DataCell(
              Text(
                _chuaDatFlowLabel(p),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _chuaDatFlowLabel(p) == 'CVDV đã báo' ? Colors.deepOrange : Colors.grey,
                ),
              ),
            ),
            DataCell(
              IconButton(
                tooltip: 'Xác nhận đặt hàng',
                icon: const Icon(Icons.shopping_cart_checkout, color: Colors.teal),
                onPressed: isLoading ? null : () => _showOrderPurchaseDialog(p),
              ),
            ),
          ],
        );
      }).toList(),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _wrapPtTableScroll(_hScroll2b, _vScroll2b, table)),
        if (noOrders || emptyFilter)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Text(
              noOrders
                  ? 'Không có dòng chờ KHO xác nhận đặt.'
                  : 'Không có dòng khớp tìm kiếm / lọc cột. Mở menu tam giác trên tiêu đề cột → «Xóa lọc cột».',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
            ),
          ),
      ],
    );
  }

  Widget _buildMissingPartsTab() {
    final nDa = _missingDaDat.length;
    final nChua = _missingChuaDatList.length;
    final nSel = _chuaDatSelected.where((k) => _missingChuaDatList.any((p) => _partLineKey(p) == k)).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.deepOrange, size: 32),
                  SizedBox(width: 12),
                  Text('Phụ tùng thiếu / chờ xuất', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                ],
              ),
              OutlinedButton.icon(
                onPressed: isLoading ? null : _exportMissingPartsReport,
                icon: const Icon(Icons.file_download),
                label: const Text('Xuất Excel'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Đã đặt = KHO đã nhập ngày dự kiến về. Chưa đặt = chưa xác nhận trên hệ thống (CVDV có thể đã báo). issuedQty < SL báo giá.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: missingPartsSearchCtrl,
            decoration: const InputDecoration(
              hintText: 'Tìm: biển số, WO/RO, mã RO hệ thống, PO…',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          TabBar(
            controller: _missingTabController,
            labelColor: Colors.teal.shade800,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.teal,
            tabs: [
              Tab(text: 'Chưa đặt ($nChua)'),
              Tab(text: 'Đã đặt ($nDa)'),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: missingParts.isEmpty
                ? const Center(child: Text('Không có phụ tùng thiếu.', style: TextStyle(color: Colors.grey, fontSize: 16)))
                : TabBarView(
                    controller: _missingTabController,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            children: [
                              FilledButton.icon(
                                onPressed: isLoading || nSel == 0 ? null : _showBatchOrderPurchaseDialog,
                                icon: const Icon(Icons.playlist_add_check),
                                label: Text('Đặt hàng cho đã chọn ($nSel)'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Expanded(child: _buildMissingPartsChuaDatTable()),
                        ],
                      ),
                      Expanded(child: _buildMissingPartsDaDatTable()),
                    ],
                  ),
          ),
        ],
    );
  }

  Widget _buildHistoryTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Lịch Sử Nhập / Xuất Kho', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
            OutlinedButton.icon(
              onPressed: isLoading ? null : _exportHistoryExcel,
              icon: const Icon(Icons.file_download),
              label: const Text('Xuất Excel'),
            ),
          ],
        ),
        SizedBox(height: transactions.isNotEmpty ? 8 : 16),
        Expanded(
          child: transactions.isEmpty
              ? const Center(child: Text('Chưa có lịch sử giao dịch.', style: TextStyle(color: Colors.grey)))
              : Container(
                  width: double.infinity,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
                  child: () {
                    final rows = _pipelineHistory();
                    final emptyFilter = rows.isEmpty;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Scrollbar(
                            controller: _hScroll1,
                            thumbVisibility: true,
                            trackVisibility: true,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              controller: _hScroll1,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 200),
                                child: Scrollbar(
                                  controller: _vScroll1,
                                  thumbVisibility: true,
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.vertical,
                                    controller: _vScroll1,
                                    child: DataTable(
                                      headingRowColor: MaterialStateProperty.all(Colors.blueGrey.shade50),
                                      columnSpacing: 25,
                                      dataRowMinHeight: 50,
                                      dataRowMaxHeight: 60,
                                      columns: [
                                        DataColumn(label: _filterHdr(_historyCol, 'date', 'Thời Gian')),
                                        DataColumn(label: _filterHdr(_historyCol, 'type', 'Loại')),
                                        DataColumn(label: _filterHdr(_historyCol, 'partCode', 'Mã PT')),
                                        DataColumn(label: _filterHdr(_historyCol, 'partName', 'Tên PT')),
                                        DataColumn(label: _filterHdr(_historyCol, 'hangLoai', 'Loại hàng hoá')),
                                        DataColumn(label: _filterHdr(_historyCol, 'quantity', 'Số Lượng')),
                                        DataColumn(label: _filterHdr(_historyCol, 'importPrice', 'Giá nhập')),
                                        DataColumn(label: _filterHdr(_historyCol, 'bienSo', 'Biển số xe')),
                                        DataColumn(label: _filterHdr(_historyCol, 'location', 'Vị trí kho')),
                                        DataColumn(label: _filterHdr(_historyCol, 'quotedExport', 'Giá xuất (LSC CVDV)')),
                                        DataColumn(label: _filterHdr(_historyCol, 'poCode', 'Mã PO')),
                                        DataColumn(label: _filterHdr(_historyCol, 'woCode', 'Mã WO')),
                                        DataColumn(label: _filterHdr(_historyCol, 'userName', 'Người TH')),
                                      ],
                                      rows: rows.map((t) {
                                        return DataRow(
                                          cells: [
                                            DataCell(Text(t.date)),
                                            DataCell(
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(color: t.type == 'NHẬP' ? Colors.green.shade100 : Colors.orange.shade100, borderRadius: BorderRadius.circular(6)),
                                                child: Text(t.type, style: TextStyle(color: t.type == 'NHẬP' ? Colors.green.shade800 : Colors.orange.shade800, fontWeight: FontWeight.bold)),
                                              ),
                                            ),
                                            DataCell(SelectableText(t.partCode, style: const TextStyle(fontWeight: FontWeight.bold))),
                                            DataCell(SelectableText(t.partName)),
                                            DataCell(Text(_invCatLabel(t.inventoryCategory), style: const TextStyle(fontWeight: FontWeight.w600))),
                                            DataCell(Text((t.type == 'NHẬP' ? '+' : '-') + t.quantity.toString(), style: TextStyle(fontWeight: FontWeight.bold, color: t.type == 'NHẬP' ? Colors.green : Colors.red, fontSize: 16))),
                                            DataCell(Text(t.importPrice > 0 ? '${_formatVND(t.importPrice)} đ' : '—', style: TextStyle(fontWeight: FontWeight.w600, color: t.importPrice > 0 ? Colors.indigo.shade800 : Colors.grey))),
                                            DataCell(SelectableText(t.bienSo.trim().isEmpty ? '—' : t.bienSo, style: const TextStyle(fontWeight: FontWeight.w500))),
                                            DataCell(SelectableText(t.location.trim().isEmpty ? '—' : t.location, style: const TextStyle(fontWeight: FontWeight.w500))),
                                            DataCell(Text(t.quotedExportPrice > 0 ? '${_formatVND(t.quotedExportPrice)} đ' : '—', style: TextStyle(fontWeight: FontWeight.w600, color: t.quotedExportPrice > 0 ? Colors.teal.shade800 : Colors.grey))),
                                            DataCell(SelectableText(t.poCode.isEmpty ? '-' : t.poCode)),
                                            DataCell(SelectableText(t.woCode.isEmpty ? '-' : t.woCode)),
                                            DataCell(Text(t.userName)),
                                          ],
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (emptyFilter)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            child: Text(
                              'Không có dòng khớp lọc cột. Mở menu tam giác trên tiêu đề cột → «Xóa lọc cột» để xem lại.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
                            ),
                          ),
                      ],
                    );
                  }(),
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('THỦ KHO - Quản Lý Vật Tư Phụ Tùng', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white,
        actions: [
          const CompanyChatAppBarButton(),
          Center(child: Text('User: ${widget.login.userName}  ', style: const TextStyle(fontWeight: FontWeight.bold))),
          
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications, color: Colors.white),
                onPressed: _showKhoBellDialog,
                tooltip: 'Thông báo Kho',
              ),
              if (_khoBellBadgeCount > 0)
                Positioned(
                  right: 8, top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.red),
                    child: Text(
                      _khoBellBadgeCount > 99 ? '99+' : '$_khoBellBadgeCount',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                )
            ],
          ),

          IconButton(icon: const Icon(Icons.refresh), onPressed: () { _loadLocalData(); _loadData(); }),
          IconButton(icon: const Icon(Icons.logout, color: Colors.redAccent), onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()))), 
          const SizedBox(width: 16)
        ],
      ),
      body: ResponsiveNavScaffold(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (int index) {
          setState(() {
            _selectedIndex = index;
            if (index == 2) {
              outboundSearchCtrl.clear();
              _filterOutboundList();
            }
          });
        },
        destinations: [
          const NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory), label: 'Tồn kho'),
          const NavigationDestination(icon: Icon(Icons.add_box_outlined), selectedIcon: Icon(Icons.add_box), label: 'Nhập'),
          const NavigationDestination(icon: Icon(Icons.outbox_outlined), selectedIcon: Icon(Icons.outbox), label: 'Xuất'),
          NavigationDestination(
            icon: missingParts.isNotEmpty
                ? const Badge(label: Text('!'), child: Icon(Icons.warning_amber_outlined))
                : const Icon(Icons.warning_amber_outlined),
            selectedIcon: missingParts.isNotEmpty
                ? const Badge(label: Text('!'), child: Icon(Icons.warning))
                : const Icon(Icons.warning),
            label: 'PT thiếu',
          ),
          const NavigationDestination(icon: Icon(Icons.history_outlined), selectedIcon: Icon(Icons.history), label: 'Lịch sử'),
        ],
        body: isLoading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: appScreenPadding(context),
                child: Builder(
                  builder: (context) {
                    switch (_selectedIndex) {
                      case 0:
                        return _buildInventoryTab();
                      case 1:
                        return _buildInboundTab();
                      case 2:
                        return _buildOutboundTab();
                      case 3:
                        return _buildMissingPartsTab();
                      case 4:
                        return _buildHistoryTab();
                      default:
                        return const SizedBox();
                    }
                  },
                ),
              ),
      ),
    );
  }
}