import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:intl/intl.dart';

import '../models/auth_models.dart';
import '../services/api_service.dart';
import '../core/ro_display.dart';
import '../core/time_format.dart';
import '../core/workshop_local_sync.dart';
import '../core/pick_file_bytes.dart';
import '../widgets/vm_file_image.dart';
import '../widgets/column_filter_menu_header.dart';
import '../widgets/company_chat_host.dart';
import '../widgets/giam_doc_vehicle_detail_dialog.dart';
import '../widgets/responsive_shell.dart';
import '../core/responsive_layout.dart';
import 'login_screen.dart';

// --- MÔ HÌNH DỮ LIỆU ---
class StaffUser {
  String id;
  String fullName;
  String username;
  String role;
  String phone;
  bool isActive;

  StaffUser({required this.id, required this.fullName, required this.username, required this.role, required this.phone, this.isActive = true});

  Map<String, dynamic> toJson() => {'id': id, 'fullName': fullName, 'username': username, 'role': role, 'phone': phone, 'isActive': isActive};
  factory StaffUser.fromJson(Map<String, dynamic> json) => StaffUser(id: json['id'] ?? '', fullName: json['fullName'] ?? '', username: json['username'] ?? '', role: json['role'] ?? '', phone: json['phone'] ?? '', isActive: json['isActive'] ?? true);
}

class GiamDocDashboardScreen extends StatefulWidget {
  final LoginResult login;
  const GiamDocDashboardScreen({super.key, required this.login});

  @override
  State<GiamDocDashboardScreen> createState() => _GiamDocDashboardScreenState();
}

class _GiamDocDashboardScreenState extends State<GiamDocDashboardScreen> {
  late final ApiService api;
  bool isLoading = false;
  int _selectedIndex = 0; 
  String _statusFilter = 'TẤT CẢ'; 

  List<WorkOrderItem> allOrders = [];
  List<WorkOrderItem> activeOrders = []; 
  List<WorkOrderItem> completedOrders = []; 
  
  final searchBienSoCtrl = TextEditingController();

  static const List<MapEntry<String, String>> _boardFilterCols = [
    MapEntry('bienSo', 'Biển số'),
    MapEntry('customerName', 'Khách hàng'),
    MapEntry('roCode', 'Mã RO'),
    MapEntry('ktv', 'KTV'),
    MapEntry('cvdv', 'CVDV'),
    MapEntry('note', 'Vị trí / GC'),
    MapEntry('status', 'Trạng thái'),
    MapEntry('waiting', 'Đang chờ'),
    MapEntry('waited', 'Đã chờ'),
  ];
  final Map<String, TextEditingController> _boardCol = {};

  static const List<MapEntry<String, String>> _staffGdFilterCols = [
    MapEntry('fullName', 'Họ tên'),
    MapEntry('username', 'Đăng nhập'),
    MapEntry('role', 'Vai trò'),
    MapEntry('active', 'Hoạt động'),
    MapEntry('lastLogin', 'ĐN cuối'),
  ];
  final Map<String, TextEditingController> _staffGdCol = {};

  final shopNameCtrl = TextEditingController(text: 'TS-XDV AUTO SERVICE');
  final shopAddressCtrl = TextEditingController(text: 'Khu Công Nghiệp ABC, Hà Nội');
  final shopPhoneCtrl = TextEditingController(text: '0988.888.888');
  final shopHoursCtrl = TextEditingController(text: '08:00 - 17:30');

  List<StaffUser> staffList = [];
  /// Nhân sự từ API (khi đăng nhập bằng tài khoản server, không phải staff_db nội bộ).
  List<UserItem> _serverStaff = [];

  /// Vai trò Giám đốc xưởng được tạo/sửa (khớp server — không gồm ADMIN / GIAMDOC).
  static const List<MapEntry<String, String>> _roleCodeToLabel = [
    MapEntry('CVDV', 'Cố vấn dịch vụ'),
    MapEntry('KETOAN', 'Kế toán'),
    MapEntry('KTV', 'Kỹ thuật viên'),
    MapEntry('QUANDOC', 'Quản đốc'),
    MapEntry('KHO', 'Thủ kho'),
    MapEntry('BAOVE', 'Bảo vệ'),
    MapEntry('CSKH', 'CSKH'),
    MapEntry('TV', 'Màn hình TV (bảng điện tử)'),
  ];

  static const Set<String> _rolesProtectedFromGiamDoc = {'ADMIN', 'GIAMDOC'};

  bool _giamDocCannotManageUser(UserItem u) {
    final r = u.role.trim().toUpperCase().replaceAll(RegExp(r'[\s\-]+'), '_');
    return _rolesProtectedFromGiamDoc.contains(r);
  }

  Widget _filterHdr(Map<String, TextEditingController> m, String key, String title) {
    return ColumnFilterMenuHeader(
      title: title,
      filterController: m[key]!,
      onFiltersChanged: () => setState(() {}),
    );
  }

  String _labelForRoleCode(String code) {
    final u = code.toUpperCase();
    for (final e in _roleCodeToLabel) {
      if (e.key == u) return e.value;
    }
    return code;
  }

  /// Chuẩn hóa role cũ (tiếng Việt / tự do) → mã server.
  String _coerceRoleCode(String? raw) {
    if (raw == null || raw.isEmpty) return _roleCodeToLabel.first.key;
    final up = raw.toUpperCase().trim();
    if (_roleCodeToLabel.any((e) => e.key == up)) return up;
    final low = raw.toLowerCase();
    if (low.contains('giám') || up == 'GIAMDOC' || up.contains('GIAMDOC')) return 'GIAMDOC';
    if (low.contains('kế') || low.contains('ke toan')) return 'KETOAN';
    if (low.contains('tv') || low.contains('tivi') || low.contains('màn hình')) return 'TV';
    if (low.contains('quản')) return 'QUANDOC';
    if (low == 'kho' || low.contains('thủ kho')) return 'KHO';
    if (low.contains('bảo')) return 'BAOVE';
    if (low.contains('cskh')) return 'CSKH';
    if (low.contains('ktv') || low.contains('kỹ')) return 'KTV';
    if (low.contains('cvdv') || low.contains('cố')) return 'CVDV';
    return _roleCodeToLabel.first.key;
  }

  bool get _isLocalStaffLogin => widget.login.token.startsWith('local_token_');

  Map<String, String> globalUomMap = {};
  Map<String, dynamic>? _serverSummary;
  Map<String, dynamic>? _workshopSettingsCached;
  final _companyNameCtrl = TextEditingController();
  final _companyAddrCtrl = TextEditingController();
  final _companyPhoneCtrl = TextEditingController();
  bool _companySaving = false;

  final List<String> filterOptions = ['TẤT CẢ', 'CHO_PHAN_CONG', 'DANG_SUA', 'DUNG_SUA', 'CHO_QUYET_TOAN', 'DA_RA_CONG_THIEU_PT', 'XE_CU_TRE_HAN'];

  final String staffFilePath = 'staff_db.json';
  final String uomFilePath = 'uom_db.json';

  @override
  void initState() {
    super.initState();
    api = ApiService(baseUrl: widget.login.baseUrl);
    for (final e in _boardFilterCols) {
      _boardCol[e.key] = TextEditingController();
    }
    for (final e in _staffGdFilterCols) {
      _staffGdCol[e.key] = TextEditingController();
    }
    _loadLocalData(); 
    _loadData();
  }

  @override
  void dispose() {
    searchBienSoCtrl.dispose();
    shopNameCtrl.dispose();
    shopAddressCtrl.dispose();
    shopPhoneCtrl.dispose();
    shopHoursCtrl.dispose();
    for (final c in _boardCol.values) {
      c.dispose();
    }
    for (final c in _staffGdCol.values) {
      c.dispose();
    }
    _companyNameCtrl.dispose();
    _companyAddrCtrl.dispose();
    _companyPhoneCtrl.dispose();
    super.dispose();
  }

  void _syncCompanyFieldsFromSettings() {
    final wd = _workshopSettingsCached?['workshop_defaults'];
    final map = wd is Map ? Map<String, dynamic>.from(wd) : _workshopSettingsCached;
    if (map == null) return;
    _companyNameCtrl.text = map['company_name']?.toString() ?? '';
    _companyAddrCtrl.text = map['company_address']?.toString() ?? '';
    _companyPhoneCtrl.text = map['company_phone']?.toString() ?? '';
  }

  Future<void> _saveCompanySettings() async {
    setState(() => _companySaving = true);
    try {
      final res = await api.patchWorkshopSettings(widget.login.token, {
        'company_name': _companyNameCtrl.text.trim(),
        'company_address': _companyAddrCtrl.text.trim(),
        'company_phone': _companyPhoneCtrl.text.trim(),
      });
      setState(() {
        _workshopSettingsCached = {
          ...?_workshopSettingsCached,
          'workshop_defaults': res['workshop_defaults'],
        };
        _syncCompanyFieldsFromSettings();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã lưu thông tin công ty (hiển thị trên phiếu Excel).'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi lưu: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _companySaving = false);
    }
  }

  Future<void> _loadLocalData() async {
    try {
      final data = await loadWorkshopJson(
        fileName: staffFilePath,
        api: api,
        token: widget.login.token,
      );
      if (data is List) {
        setState(() { staffList = data.map((e) => StaffUser.fromJson(Map<String, dynamic>.from(e as Map))).toList(); });
      } else {
        setState(() { staffList = [StaffUser(id: '1', fullName: 'Giám Đốc', username: widget.login.userName, role: 'Giám đốc', phone: '')]; });
      }
    } catch (e) { debugPrint('Lỗi đọc staff_db: $e'); }
    try {
      final uom = await loadWorkshopJson(
        fileName: uomFilePath,
        api: api,
        token: widget.login.token,
      );
      if (uom is Map) {
        setState(() { globalUomMap = uom.map((key, value) => MapEntry(key.toString(), value.toString())); });
      }
    } catch (e) { debugPrint('Lỗi đọc uom_db: $e'); }
  }

  Future<void> _saveStaffList() async {
    await saveWorkshopJson(
      fileName: staffFilePath,
      payload: staffList.map((e) => e.toJson()).toList(),
      api: api,
      token: widget.login.token,
    );
  }

  Future<void> _saveUomMap() async {
    await saveWorkshopJson(
      fileName: uomFilePath,
      payload: globalUomMap,
      api: api,
      token: widget.login.token,
    );
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    try {
      final fetchedOrders = await api.fetchBoard(widget.login.token);
      try {
        _serverSummary = await api.fetchDashboardSummary(widget.login.token);
      } catch (_) {
        _serverSummary = null;
      }
      try {
        _workshopSettingsCached = await api.fetchWorkshopSettings(widget.login.token);
        _syncCompanyFieldsFromSettings();
      } catch (_) {
        _workshopSettingsCached = null;
      }
      setState(() {
        allOrders = fetchedOrders;
        activeOrders = allOrders.where((o) => !['DA_THANH_TOAN', 'XE_RA_XUONG', 'DA_RA_CONG', 'HUY', 'HUY_CHO_QUYET_TOAN', 'KT_DUYET_RA_CONG'].contains(o.status)).toList();
        completedOrders = allOrders.where((o) => ['DA_THANH_TOAN', 'XE_RA_XUONG', 'DA_RA_CONG', 'KT_DUYET_RA_CONG'].contains(o.status)).toList();
      });
      if (!_isLocalStaffLogin) {
        try {
          final users = await api.fetchUsers(widget.login.token);
          if (mounted) setState(() => _serverStaff = users);
        } catch (e) {
          debugPrint('Lỗi fetchUsers Giám đốc: $e');
          if (mounted) setState(() => _serverStaff = []);
        }
      }
    } catch (e) { debugPrint('Lỗi load board: $e'); } 
    finally { setState(() => isLoading = false); }
  }

  String _formatVND(double value) {
    return NumberFormat('#,###').format(value);
  }

  String _calculateWaitTime(DateTime? timeIn) => formatWaitSinceDateTime(timeIn, ifNull: '-');

  Map<String, double> _calculateFinancials() {
    double revenue = 0; double profit = 0;
    var validOrders = allOrders.where((o) => ['DA_THANH_TOAN', 'XE_RA_XUONG', 'DA_RA_CONG', 'KT_DUYET_RA_CONG'].contains(o.status));
    for (var o in validOrders) {
      try {
        if (o.jobs != null) {
          List jobs = (o.jobs is String) ? jsonDecode(o.jobs) : List.from(o.jobs);
          for (var j in jobs) {
            double line = ((double.tryParse(j['price'].toString()) ?? 0) * (double.tryParse(j['hours'].toString()) ?? 0)) - (double.tryParse(j['discount'].toString()) ?? 0);
            revenue += line; profit += line * 0.7;
          }
        }
        if (o.parts != null) {
          List parts = (o.parts is String) ? jsonDecode(o.parts) : List.from(o.parts);
          for (var p in parts) {
            double line = ((double.tryParse(p['price'].toString()) ?? 0) * (double.tryParse(p['qty'].toString()) ?? 0)) - (double.tryParse(p['discount'].toString()) ?? 0);
            revenue += line; profit += line * 0.25;
          }
        }
      } catch (e) {}
    }
    return {'rev': revenue, 'prof': profit};
  }

  void _applyFilter(String status) {
    setState(() {
      _statusFilter = status;
      _selectedIndex = 1; 
      searchBienSoCtrl.clear(); 
    });
  }

  void _showOrderDetailsDialog(WorkOrderItem order) {
    final workshop = _workshopSettingsCached?['workshop_name']?.toString() ??
        _workshopSettingsCached?['name']?.toString();
    showGiamDocVehicleDetailDialog(
      context: context,
      api: api,
      token: widget.login.token,
      summary: order,
      workshopName: workshop,
    );
  }

  // --- HÀM GIẢI MÃ ẢNH ĐA NĂNG ĐỂ XỬ LÝ LỖI ---
  Widget _buildSafeImage(String imageStr) {
    try {
      if (imageStr.startsWith('http://') || imageStr.startsWith('https://')) {
        return Image.network(imageStr, fit: BoxFit.cover, errorBuilder: (ctx, err, stack) => const Icon(Icons.broken_image, color: Colors.grey));
      } else if (imageStr.startsWith('data:image')) {
        // Tách bỏ phần "data:image/jpeg;base64," ở đầu chuỗi
        final String base64Str = imageStr.split(',').last;
        final Uint8List bytes = base64Decode(base64Str);
        return Image.memory(bytes, fit: BoxFit.cover, errorBuilder: (ctx, err, stack) => const Icon(Icons.broken_image, color: Colors.grey));
      } else if (imageStr.startsWith('file://') || imageStr.startsWith('/')) {
        return buildVmFileImage(imageStr.replaceAll('file://', ''), fit: BoxFit.cover);
      }
    } catch(e) {
      debugPrint('Lỗi giải mã ảnh: $e');
    }
    return const Center(child: Icon(Icons.error_outline, color: Colors.red, size: 40));
  }

  // --- HÀM PHÓNG TO ẢNH FULL MÀN HÌNH ---
  void _showFullScreenImage(String imageStr) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer( // Cho phép zoom, thu phóng ảnh
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
                  return GestureDetector(
                    onTap: () => _showFullScreenImage(imageUrls[index]), // Bấm vào ảnh để phóng to
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        color: Colors.black12,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _buildSafeImage(imageUrls[index]),
                            const Positioned(
                              bottom: 8, right: 8,
                              child: Icon(Icons.zoom_out_map, color: Colors.white70, size: 20)
                            )
                          ],
                        )
                      ),
                    ),
                  );
                }
              ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng'))],
      )
    );
  }

  // ==========================================================================
  // NHÂN SỰ MÁY CHỦ (API) — tạo tài khoản TV, KTV, …
  // ==========================================================================
  Future<void> _showServerUserEditorDialog(UserItem? user) async {
    if (user != null && _giamDocCannotManageUser(user)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tài khoản ADMIN / Giám đốc chỉ Quản trị hệ thống (ADMIN) mới được sửa.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 6),
        ),
      );
      return;
    }
    final isEdit = user != null;
    final nameCtrl = TextEditingController(text: user?.fullName ?? '');
    final userCtrl = TextEditingController(text: user?.username ?? '');
    final passCtrl = TextEditingController();
    String roleCode = _coerceRoleCode(user?.role);

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setD) {
          final codes = _roleCodeToLabel.map((e) => e.key).toList();
          final safeRole = codes.contains(roleCode) ? roleCode : codes.first;
          return AlertDialog(
            title: Text(isEdit ? 'Sửa tài khoản (server)' : 'Thêm tài khoản (server)', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Họ tên (*)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person))),
                    if (!isEdit) ...[
                      const SizedBox(height: 12),
                      TextField(controller: userCtrl, decoration: const InputDecoration(labelText: 'Tên đăng nhập (*)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.badge))),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: passCtrl,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: isEdit ? 'Mật khẩu mới (để trống = giữ nguyên)' : 'Mật khẩu (*)',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.lock),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: safeRole,
                      decoration: const InputDecoration(labelText: 'Vai trò', border: OutlineInputBorder(), prefixIcon: Icon(Icons.work)),
                      items: _roleCodeToLabel.map((e) => DropdownMenuItem(value: e.key, child: Text('${e.value} (${e.key})'))).toList(),
                      onChanged: (v) => setD(() => roleCode = v ?? safeRole),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Giám đốc xưởng chỉ quản lý nhân sự vận hành (CVDV, KTV, Kho…). '
                      'Tài khoản ADMIN do màn Quản trị hệ thống quản lý.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
              FilledButton(
                onPressed: () async {
                  if (nameCtrl.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nhập họ tên.'), backgroundColor: Colors.red));
                    return;
                  }
                  if (!isEdit && (userCtrl.text.trim().isEmpty || passCtrl.text.isEmpty)) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cần tên đăng nhập và mật khẩu.'), backgroundColor: Colors.red));
                    return;
                  }
                  try {
                    setState(() => isLoading = true);
                    if (isEdit) {
                      await api.updateUser(
                        token: widget.login.token,
                        id: user!.id,
                        name: nameCtrl.text.trim(),
                        role: roleCode,
                        password: passCtrl.text.isNotEmpty ? passCtrl.text : null,
                      );
                    } else {
                      await api.createUser(
                        token: widget.login.token,
                        username: userCtrl.text.trim(),
                        password: passCtrl.text,
                        name: nameCtrl.text.trim(),
                        role: roleCode,
                      );
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                    await _loadData();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã lưu tài khoản.'), backgroundColor: Colors.green));
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
                    }
                  } finally {
                    if (mounted) setState(() => isLoading = false);
                  }
                },
                child: const Text('Lưu'),
              ),
            ],
          );
        },
      ),
    );
  }

  bool _isProtectedLocalDirector(StaffUser u) {
    final r = u.role.toUpperCase();
    if (r.contains('GIAM') || r.contains('GIÁM')) return true;
    if (u.username.toLowerCase() == widget.login.userName.toLowerCase()) return true;
    return false;
  }

  // ==========================================================================
  // HÀM QUẢN LÝ NHÂN SỰ (file staff_db — đăng nhập nội bộ)
  // ==========================================================================
  void _showAddEditUserDialog([StaffUser? user]) {
    final isEdit = user != null;
    final nameCtrl = TextEditingController(text: user?.fullName ?? '');
    final userCtrl = TextEditingController(text: user?.username ?? '');
    final passCtrl = TextEditingController();
    final phoneCtrl = TextEditingController(text: user?.phone ?? '');
    String selectedRoleCode = _coerceRoleCode(user?.role);
    bool isActive = user?.isActive ?? true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final codes = _roleCodeToLabel.map((e) => e.key).toList();
          final safeRole = codes.contains(selectedRoleCode) ? selectedRoleCode : codes.first;
          return AlertDialog(
            title: Text(isEdit ? 'CHỈNH SỬA TÀI KHOẢN' : 'THÊM NHÂN SỰ MỚI', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
            content: SizedBox(
              width: 450,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Họ và Tên (*)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person))),
                    const SizedBox(height: 16),
                    TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Số điện thoại', border: OutlineInputBorder(), prefixIcon: Icon(Icons.phone))),
                    const SizedBox(height: 16),
                    TextField(controller: userCtrl, enabled: !isEdit, decoration: InputDecoration(labelText: 'Tên đăng nhập (*)', border: const OutlineInputBorder(), filled: isEdit, prefixIcon: const Icon(Icons.badge))),
                    const SizedBox(height: 16),
                    TextField(controller: passCtrl, obscureText: true, decoration: InputDecoration(labelText: isEdit ? 'Mật khẩu mới (Bỏ trống nếu không đổi)' : 'Mật khẩu (*)', border: const OutlineInputBorder(), prefixIcon: const Icon(Icons.lock))),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: safeRole,
                      decoration: const InputDecoration(labelText: 'Vai trò trong xưởng', border: OutlineInputBorder(), prefixIcon: Icon(Icons.work)),
                      items: _roleCodeToLabel.map((e) => DropdownMenuItem(value: e.key, child: Text('${e.value} (${e.key})'))).toList(),
                      onChanged: (val) { setDialogState(() { selectedRoleCode = val!; }); },
                    ),
                    if (isEdit) ...[
                      const SizedBox(height: 16),
                      SwitchListTile(
                        title: const Text('Trạng thái hoạt động', style: TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(isActive ? 'Đang kích hoạt (Nhân viên có thể đăng nhập)' : 'Đã khóa (Nhân viên không thể đăng nhập)', style: TextStyle(color: isActive ? Colors.green : Colors.red)),
                        value: isActive,
                        activeColor: Colors.green,
                        onChanged: (val) { setDialogState(() { isActive = val; }); }
                      )
                    ]
                  ],
                ),
              ),
            ),
            actions: [
              if (isEdit && !_isProtectedLocalDirector(user!)) 
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _confirmDeleteUser(user);
                  }, 
                  icon: const Icon(Icons.delete, color: Colors.red), 
                  label: const Text('Xóa', style: TextStyle(color: Colors.red))
                ),
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
              FilledButton(
                onPressed: () {
                  if (nameCtrl.text.trim().isEmpty || userCtrl.text.trim().isEmpty || (!isEdit && passCtrl.text.isEmpty)) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng điền đủ các trường bắt buộc (*)'), backgroundColor: Colors.red));
                    return;
                  }
                  setState(() {
                    if (isEdit) {
                      user!.fullName = nameCtrl.text.trim();
                      user.phone = phoneCtrl.text.trim();
                      user.role = selectedRoleCode;
                      user.isActive = isActive;
                    } else {
                      staffList.add(StaffUser(id: DateTime.now().millisecondsSinceEpoch.toString(), fullName: nameCtrl.text.trim(), username: userCtrl.text.trim(), role: selectedRoleCode, phone: phoneCtrl.text.trim(), isActive: true));
                    }
                  });
                  _saveStaffList(); 
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isEdit ? 'Cập nhật tài khoản thành công!' : 'Đã cấp tài khoản mới!'), backgroundColor: Colors.green));
                }, 
                child: const Text('Lưu thông tin')
              )
            ],
          );
        }
      )
    );
  }

  void _confirmDeleteUser(StaffUser user) {
    showDialog(
      context: context, 
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa Tài Khoản', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        content: Text('Bạn có chắc chắn muốn xóa vĩnh viễn tài khoản "${user.fullName}" không?\n\nLưu ý: Thao tác này không thể hoàn tác. Khuyến nghị chỉ nên "Khóa" tài khoản để giữ lại lịch sử.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              setState(() { staffList.removeWhere((u) => u.id == user.id); });
              _saveStaffList();
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã xóa tài khoản!')));
            }, 
            child: const Text('Xóa Vĩnh Viễn')
          )
        ],
      )
    );
  }

  Widget _buildStatCard(String title, String value, Color color, IconData icon, {VoidCallback? onTap}) {
    return Material(
      color: Colors.white, borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12), decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8)]),
          child: Row(children: [
              Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 24)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)), const SizedBox(height: 4), Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color))])),
          ]),
        ),
      ),
    );
  }

  Widget _buildDashboardTab() {
    final fin = _calculateFinancials();
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('📊 Thống Kê Xưởng Thời Gian Thực', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
          if (_serverSummary != null) ...[
            const SizedBox(height: 16),
            const Text('Theo máy chủ (dashboard/summary)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildStatCard('Xe trong xưởng', '${_serverSummary!['repair_orders_in_workshop'] ?? '—'}', Colors.blue, Icons.directions_car),
                _buildStatCard('RO đang mở', '${_serverSummary!['repair_orders_open'] ?? '—'}', Colors.teal, Icons.receipt_long),
                _buildStatCard('Chờ quyết toán', '${_serverSummary!['repair_orders_cho_quyet_toan'] ?? '—'}', Colors.purple, Icons.payments),
                _buildStatCard('User hoạt động', '${_serverSummary!['users_active'] ?? '—'}', Colors.indigo, Icons.people),
              ],
            ),
            const SizedBox(height: 16),
          ],
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 5, crossAxisSpacing: 16, mainAxisSpacing: 16, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), childAspectRatio: 2.2,
            children: [
              _buildStatCard('Doanh Thu (VNĐ)', NumberFormat('#,###').format(fin['rev']), Colors.teal, Icons.attach_money, onTap: () => setState(() => _selectedIndex = 4)),
              _buildStatCard('Lợi Nhuận Dự Tính', NumberFormat('#,###').format(fin['prof']), Colors.deepPurple, Icons.trending_up, onTap: () => setState(() => _selectedIndex = 4)),
              _buildStatCard('Xe Trong Xưởng', activeOrders.length.toString(), Colors.blue, Icons.directions_car, onTap: () => _applyFilter('TẤT CẢ')),
              _buildStatCard('Chờ Phân Công', activeOrders.where((o)=>o.status=='CHO_PHAN_CONG').length.toString(), Colors.orange, Icons.assignment_ind, onTap: () => _applyFilter('CHO_PHAN_CONG')),
              _buildStatCard('Đang Sửa Chữa', activeOrders.where((o)=>o.status=='DANG_SUA').length.toString(), Colors.green, Icons.build, onTap: () => _applyFilter('DANG_SUA')),
              _buildStatCard('Đang Dừng Sửa', activeOrders.where((o)=>o.status=='DUNG_SUA').length.toString(), Colors.red, Icons.pan_tool, onTap: () => _applyFilter('DUNG_SUA')),
              _buildStatCard('Chờ Thanh Toán', activeOrders.where((o)=>o.status=='CHO_QUYET_TOAN').length.toString(), Colors.blueGrey, Icons.payments, onTap: () => _applyFilter('CHO_QUYET_TOAN')),
              _buildStatCard('Xe Cũ/Trễ Hẹn', activeOrders.where((o)=>o.createdAt != null && DateTime.now().difference(o.createdAt!).inDays > 2).length.toString(), Colors.redAccent, Icons.timer_off, onTap: () => _applyFilter('XE_CU_TRE_HAN')),
              _buildStatCard('Thiếu Phụ Tùng', activeOrders.where((o)=>o.status=='DA_RA_CONG_THIEU_PT').length.toString(), Colors.brown, Icons.inventory_2, onTap: () => _applyFilter('DA_RA_CONG_THIEU_PT')),
              _buildStatCard('Đã Ra Xưởng', completedOrders.length.toString(), Colors.teal, Icons.check_circle, onTap: () => setState(() => _selectedIndex = 2)),
            ],
          ),
        ],
      ),
    );
  }

  List<WorkOrderItem> _pipelineBoard(List<WorkOrderItem> base) {
    final filters = _boardFilterCols.map((e) => _boardCol[e.key]!.text).toList();
    return base.where((o) {
      final cells = <String>[
        o.bienSo,
        o.customerName,
        o.roCode,
        o.ktvUsername.isEmpty ? '—' : o.ktvUsername,
        o.cvdvUsername.isEmpty ? '—' : o.cvdvUsername,
        o.customerNote.isNotEmpty ? o.customerNote : (o.position.isEmpty ? '—' : o.position),
        o.status,
        waitingBriefForStatus(o.status, customerWaiting: o.customerWaiting),
        o.waitDisplayShort,
      ];
      return cellsMatchFilters(filters, cells);
    }).toList();
  }

  List<UserItem> _pipelineStaffGd(List<UserItem> base) {
    final filters = _staffGdFilterCols.map((e) => _staffGdCol[e.key]!.text).toList();
    return base.where((u) {
      final cells = <String>[
        u.fullName.isEmpty ? '—' : u.fullName,
        u.username,
        '${_labelForRoleCode(u.role)} (${u.role})',
        u.isActive ? 'Có' : 'Đã khóa',
        u.lastLoginAt == null ? '—' : DateFormat('dd/MM/yy HH:mm').format(u.lastLoginAt!.toLocal()),
      ];
      return cellsMatchFilters(filters, cells);
    }).toList();
  }

  Widget _buildActiveBoardTab() {
    List<WorkOrderItem> displayList = activeOrders.where((o) {
      if (_statusFilter != 'TẤT CẢ' && _statusFilter != 'XE_CU_TRE_HAN') {
         if (o.status != _statusFilter) return false;
      }
      if (_statusFilter == 'XE_CU_TRE_HAN') {
         if (o.createdAt == null || DateTime.now().difference(o.createdAt!).inDays <= 2) return false;
      }
      String query = searchBienSoCtrl.text.trim().toLowerCase().replaceAll(RegExp(r'[\s-]'), '');
      if (query.isNotEmpty) {
         String bs = o.bienSo.toLowerCase().replaceAll(RegExp(r'[\s-]'), '');
         if (!bs.contains(query)) return false;
      }
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
                const Text('🚘 Điều Hành Xưởng', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(width: 24),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12), decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200)),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _statusFilter,
                      items: filterOptions.map((f) => DropdownMenuItem(value: f, child: Text(f == 'TẤT CẢ' ? 'TẤT CẢ XE TRONG XƯỞNG' : f, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)))).toList(),
                      onChanged: (v) => _applyFilter(v!),
                    ),
                  ),
                )
            ]),
            SizedBox(
              width: 300,
              child: TextField(
                controller: searchBienSoCtrl,
                onChanged: (val) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Nhập biển số để tìm nhanh...',
                  prefixIcon: const Icon(Icons.search, color: Colors.blue),
                  filled: true,
                  fillColor: Colors.white,
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  suffixIcon: searchBienSoCtrl.text.isNotEmpty 
                    ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () { searchBienSoCtrl.clear(); setState(() {}); })
                    : null
                ),
              ),
            ),
            FilledButton.icon(onPressed: _loadData, icon: const Icon(Icons.refresh), label: const Text('Làm mới')),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            width: double.infinity, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
            child: displayList.isEmpty
              ? Center(child: Text('Không có xe nào phù hợp với bộ lọc hiện tại', style: TextStyle(color: Colors.grey.shade600)))
              : () {
                  final bf = _pipelineBoard(displayList);
                  if (bf.isEmpty) {
                    return Center(
                      child: Text('Không có dòng khớp lọc cột.', style: TextStyle(color: Colors.grey.shade600)),
                    );
                  }
                  return SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowColor: MaterialStateProperty.all(Colors.grey.shade100),
                        columns: [
                          DataColumn(label: _filterHdr(_boardCol, 'bienSo', 'Biển Số')),
                          DataColumn(label: _filterHdr(_boardCol, 'customerName', 'Khách Hàng')),
                          DataColumn(label: _filterHdr(_boardCol, 'roCode', 'Mã RO')),
                          DataColumn(label: _filterHdr(_boardCol, 'ktv', 'KTV')),
                          DataColumn(label: _filterHdr(_boardCol, 'cvdv', 'CVDV')),
                          DataColumn(label: _filterHdr(_boardCol, 'note', 'Vị trí / Ghi chú')),
                          DataColumn(label: _filterHdr(_boardCol, 'status', 'Trạng Thái')),
                          DataColumn(label: _filterHdr(_boardCol, 'waiting', 'Đang chờ gì')),
                          DataColumn(label: _filterHdr(_boardCol, 'waited', 'Đã chờ')),
                          const DataColumn(label: Text('Thao Tác', style: TextStyle(fontWeight: FontWeight.bold))),
                        ],
                        rows: bf.map((o) => DataRow(cells: [
                          DataCell(Text(o.bienSo, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))),
                          DataCell(Text(o.customerName)),
                          DataCell(Text(o.roCode)),
                          DataCell(Text(o.ktvUsername.isEmpty ? '—' : o.ktvUsername)),
                          DataCell(Text(o.cvdvUsername.isEmpty ? '—' : o.cvdvUsername)),
                          DataCell(Text(o.customerNote.isNotEmpty ? o.customerNote : (o.position.isEmpty ? '—' : o.position))),
                          DataCell(Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(8)), child: Text(o.status, style: const TextStyle(fontSize: 12)))),
                          DataCell(Text(waitingBriefForStatus(o.status, customerWaiting: o.customerWaiting), style: const TextStyle(fontSize: 11))),
                          DataCell(Text(o.waitDisplayShort)),
                          DataCell(TextButton.icon(onPressed: () => _showOrderDetailsDialog(o), icon: const Icon(Icons.visibility, size: 16), label: const Text('Chi tiết'))),
                        ])).toList(),
                      ),
                    ),
                  );
                }(),
          ),
        )
      ],
    );
  }

  Widget _buildHistoryTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('🕒 Lịch Sử Xe Ra Xưởng', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(
          'Bấm «Chi tiết» để xem diễn biến đầy đủ và xuất báo cáo giải trình (.txt).',
          style: TextStyle(color: Colors.blueGrey.shade700, fontSize: 13),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: completedOrders.isEmpty
                ? const Center(child: Text('Trống'))
                : ListView.separated(
                    itemCount: completedOrders.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final o = completedOrders[i];
                      return ListTile(
                        title: Text(o.bienSo, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('${o.customerName} · RO ${o.roCode}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(roStatusTokenLabelVi(o.status), style: const TextStyle(fontSize: 12)),
                            const SizedBox(width: 8),
                            FilledButton.tonalIcon(
                              onPressed: () => _showOrderDetailsDialog(o),
                              icon: const Icon(Icons.timeline, size: 18),
                              label: const Text('Chi tiết'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildStaffTab() {
    if (!_isLocalStaffLogin) {
      return _buildServerStaffTab();
    }
    return _buildLocalStaffTab();
  }

  Widget _buildServerStaffTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('👥 Quản lý nhân sự (máy chủ)', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(
                    'Tạo/sửa tài khoản nhân sự xưởng (CVDV, KTV, Kho, TV…). '
                    'Không hiển thị / không sửa được tài khoản ADMIN — chỉ đăng nhập màn Quản trị.',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                  ),
                ],
              ),
            ),
            IconButton(tooltip: 'Làm mới danh sách', onPressed: _loadData, icon: const Icon(Icons.refresh)),
            const SizedBox(width: 4),
            FilledButton.icon(
              onPressed: () => _showServerUserEditorDialog(null),
              icon: const Icon(Icons.person_add),
              label: const Text('Thêm tài khoản'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: _serverStaff.isEmpty
                ? const Center(child: Text('Chưa tải được danh sách user hoặc danh sách trống.', style: TextStyle(color: Colors.grey)))
                : () {
                          final sf = _pipelineStaffGd(_serverStaff);
                          if (sf.isEmpty) {
                            return Center(
                              child: Text('Không có dòng khớp lọc cột.', style: TextStyle(color: Colors.grey.shade600)),
                            );
                          }
                          return Scrollbar(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: SingleChildScrollView(
                                child: DataTable(
                                  headingRowColor: MaterialStateProperty.all(Colors.blue.shade50),
                                  columns: [
                                    DataColumn(label: _filterHdr(_staffGdCol, 'fullName', 'Họ tên')),
                                    DataColumn(label: _filterHdr(_staffGdCol, 'username', 'Đăng nhập')),
                                    DataColumn(label: _filterHdr(_staffGdCol, 'role', 'Vai trò')),
                                    DataColumn(label: _filterHdr(_staffGdCol, 'active', 'Hoạt động')),
                                    DataColumn(label: _filterHdr(_staffGdCol, 'lastLogin', 'Đăng nhập cuối')),
                                    const DataColumn(label: Text('Thao tác', style: TextStyle(fontWeight: FontWeight.bold))),
                                  ],
                                  rows: sf.map((u) {
                                    return DataRow(
                                      cells: [
                                        DataCell(Text(u.fullName.isEmpty ? '—' : u.fullName)),
                                        DataCell(Text(u.username)),
                                        DataCell(Text('${_labelForRoleCode(u.role)} (${u.role})')),
                                        DataCell(Text(u.isActive ? 'Có' : 'Đã khóa')),
                                        DataCell(Text(
                                          u.lastLoginAt == null ? '—' : DateFormat('dd/MM/yy HH:mm').format(u.lastLoginAt!.toLocal()),
                                        )),
                                        DataCell(
                                          _giamDocCannotManageUser(u)
                                              ? Tooltip(
                                                  message: 'Chỉ ADMIN quản lý tài khoản này',
                                                  child: Icon(Icons.lock_outline, size: 20, color: Colors.grey.shade500),
                                                )
                                              : Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    IconButton(
                                                      icon: const Icon(Icons.edit, color: Colors.blue),
                                                      tooltip: 'Sửa',
                                                      onPressed: () => _showServerUserEditorDialog(u),
                                                    ),
                                                    IconButton(
                                                      icon: Icon(
                                                        u.isActive ? Icons.no_accounts_outlined : Icons.check_circle_outline,
                                                        color: u.isActive ? Colors.orange : Colors.green,
                                                      ),
                                                      tooltip: u.isActive ? 'Khóa đăng nhập' : 'Mở khóa',
                                                      onPressed: () async {
                                                        try {
                                                          await api.toggleUserActive(widget.login.token, u.id);
                                                          await _loadData();
                                                          if (mounted) {
                                                            ScaffoldMessenger.of(context).showSnackBar(
                                                              const SnackBar(
                                                                content: Text('Đã cập nhật trạng thái tài khoản.'),
                                                                backgroundColor: Colors.teal,
                                                              ),
                                                            );
                                                          }
                                                        } catch (e) {
                                                          if (mounted) {
                                                            ScaffoldMessenger.of(context).showSnackBar(
                                                              SnackBar(content: Text('$e'), backgroundColor: Colors.red),
                                                            );
                                                          }
                                                        }
                                                      },
                                                    ),
                                                  ],
                                                ),
                                        ),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          );
                        }(),
          ),
        ),
      ],
    );
  }

  Widget _buildLocalStaffTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('👥 Nhân sự nội bộ (file)', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text('Đăng nhập qua staff_db.json. Chọn vai trò «TV» để vào màn hình TV.', style: TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            ),
            FilledButton.icon(onPressed: () => _showAddEditUserDialog(), icon: const Icon(Icons.person_add), label: const Text('Thêm Tài Khoản')),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
            child: ListView.separated(
              itemCount: staffList.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final user = staffList[i];
                final avatarCh = user.role.isNotEmpty ? user.role[0] : '?';
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  leading: CircleAvatar(
                    backgroundColor: user.isActive ? Colors.blue.shade100 : Colors.grey.shade300,
                    child: Text(avatarCh, style: TextStyle(color: user.isActive ? Colors.blue : Colors.grey, fontWeight: FontWeight.bold)),
                  ),
                  title: Row(
                    children: [
                      Text(user.fullName, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, decoration: user.isActive ? null : TextDecoration.lineThrough, color: user.isActive ? Colors.black : Colors.grey)),
                      if (!user.isActive) ...[
                        const SizedBox(width: 8),
                        Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)), child: const Text('ĐÃ KHÓA', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))),
                      ],
                    ],
                  ),
                  subtitle: Text('Vai trò: ${_labelForRoleCode(user.role)} (${user.role}) | Tên ĐN: ${user.username} | SĐT: ${user.phone.isEmpty ? 'Trống' : user.phone}'),
                  trailing: IconButton(icon: const Icon(Icons.edit_document, color: Colors.blue), onPressed: () => _showAddEditUserDialog(user)),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReportTab() {
    final fin = _calculateFinancials();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('📈 Báo Cáo Doanh Thu AI', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      const SizedBox(height: 24),
      Row(children: [
          Expanded(child: _buildStatCard('TỔNG DOANH THU', '${NumberFormat('#,###').format(fin['rev'])} ₫', Colors.green, Icons.monetization_on)),
          const SizedBox(width: 16),
          Expanded(child: _buildStatCard('LỢI NHUẬN RÒNG (DỰ TÍNH)', '${NumberFormat('#,###').format(fin['prof'])} ₫', Colors.blue, Icons.stars)),
      ]),
      const SizedBox(height: 24),
      const Text('Chú thích AI: Lợi nhuận = (70% Công thợ) + (25% Chênh lệch phụ tùng).', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
    ]);
  }

  Future<void> _importDVT_MISA() async {
    FilePickerResult? r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'csv'],
      withData: true,
    );
    if (r != null) {
      setState(() => isLoading = true);
      final picked = await bytesFromPickerFile(r.files.single);
      if (picked == null) {
        setState(() => isLoading = false);
        return;
      }
      var bytes = picked;
      int count = 0;
      try {
         var excel = Excel.decodeBytes(bytes);
         for (var table in excel.tables.values) {
            for (var row in table.rows) {
               if (row.length >= 4) {
                  String code = row[1]?.value?.toString().trim() ?? '';
                  String unit = row[3]?.value?.toString().trim() ?? '';
                  if (code.isNotEmpty && code != 'Mã' && code.toLowerCase() != 'null') {
                      globalUomMap[code] = unit;
                      count++;
                  }
               }
            }
         }
         await _saveUomMap();
      } catch(e) {}
      setState(() => isLoading = false);
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã đồng bộ thành công $count mã ĐVT! CVDV có thể sử dụng ngay.'), backgroundColor: Colors.green));
    }
  }

  Widget _buildConfigTab() {
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('⚙️ Cấu Hình Hệ Thống', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 24),
        Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
          child: Column(children: [
            ListTile(leading: const Icon(Icons.cloud_upload, color: Colors.green), title: const Text('Đồng bộ ĐVT MISA'), subtitle: const Text('Tải lên file danh mục để hệ thống tự nhận Đơn vị tính.'), trailing: FilledButton(onPressed: _importDVT_MISA, child: const Text('Tải lên'))),
          ]),
        ),
        const SizedBox(height: 24),
        const Text('Thông tin công ty (trên phiếu Báo giá / LSC / Quyết toán)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _companyNameCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Tên công ty (dòng 1; dòng 2 = tên phụ nếu xuống dòng)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _companyAddrCtrl,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Địa chỉ', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _companyPhoneCtrl,
                decoration: const InputDecoration(labelText: 'Hotline / điện thoại', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _companySaving ? null : _saveCompanySettings,
                  icon: _companySaving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save),
                  label: Text(_companySaving ? 'Đang lưu…' : 'Lưu thông tin công ty'),
                ),
              ),
            ],
          ),
        ),
        if (_workshopSettingsCached == null) ...[
          const SizedBox(height: 16),
          Text('Chưa tải được cấu hình xưởng từ máy chủ (kiểm tra mạng / quyền).', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(title: const Text('Giám Đốc Xưởng - Bảng Điều Khiển', style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: Colors.white,
        actions: [
          const CompanyChatAppBarButton(),
          Center(child: Text('Giám Đốc: ${widget.login.userName}  ', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))),
          IconButton(icon: const Icon(Icons.logout, color: Colors.red), onPressed: () { Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen())); }),
          const SizedBox(width: 16)
        ],
      ),
      body: ResponsiveNavScaffold(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() {
          _selectedIndex = i;
          if (i != 1) _statusFilter = 'TẤT CẢ';
        }),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Tổng quan'),
          NavigationDestination(icon: Icon(Icons.build_circle_outlined), selectedIcon: Icon(Icons.build_circle), label: 'Board xe'),
          NavigationDestination(icon: Icon(Icons.history_outlined), selectedIcon: Icon(Icons.history), label: 'Lịch sử'),
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Nhân sự'),
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: 'Báo cáo'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Cấu hình'),
        ],
        body: isLoading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: appScreenPadding(context),
                child: Builder(
                  builder: (ctx) {
                    switch (_selectedIndex) {
                      case 0:
                        return _buildDashboardTab();
                      case 1:
                        return _buildActiveBoardTab();
                      case 2:
                        return _buildHistoryTab();
                      case 3:
                        return _buildStaffTab();
                      case 4:
                        return _buildReportTab();
                      case 5:
                        return _buildConfigTab();
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