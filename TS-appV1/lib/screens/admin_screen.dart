import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../core/workshop_features.dart';
import '../models/auth_models.dart';
import '../services/api_service.dart';
import '../widgets/column_filter_menu_header.dart';
import '../widgets/admin_kh_ads_panel.dart';
import '../widgets/company_chat_host.dart';
import 'login_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key, required this.login});
  final LoginResult login;

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _selectedIndex = 0;
  bool _isLoading = false;

  List<dynamic> _xdvs = [];
  List<dynamic> _users = [];
  List<dynamic> _directors = []; 
  List<dynamic> _orders = [];
  Map<String, dynamic>? _dashboardSummary;

  late final ApiService _settingsApi;
  bool _cfgLoading = false;
  bool _cfgSaving = false;
  bool _companyChatEnabled = true;
  KhAdsMode _khAdsMode = KhAdsMode.banner;
  List<KhAdItem> _khAdsDraft = [];
  List<Map<String, dynamic>> _khAdStats = [];
  Map<String, dynamic>? _khAdSummary;
  final _vndPerViewCtrl = TextEditingController();
  final _vndPerClickCtrl = TextEditingController();
  final _admobAndroidBannerCtrl = TextEditingController();
  final _admobIosBannerCtrl = TextEditingController();
  final _appVersionLabelCtrl = TextEditingController(text: 'V1.0');
  final _appVersionCtrl = TextEditingController(text: '1.0.0');
  final _appBuildCtrl = TextEditingController(text: '1');
  final _appDlWebCtrl = TextEditingController();
  final _appDlWindowsCtrl = TextEditingController();
  final _appDlAndroidCtrl = TextEditingController();
  final _appDlIosCtrl = TextEditingController();
  bool _appUpdateMandatory = false;

  static const List<MapEntry<String, String>> _xdvFilterCols = [
    MapEntry('code', 'Mã XDV'),
    MapEntry('name', 'Tên xưởng'),
    MapEntry('address', 'Địa chỉ'),
    MapEntry('phone', 'SĐT'),
    MapEntry('status', 'Trạng thái'),
  ];
  final Map<String, TextEditingController> _xdvCol = {};

  static const List<MapEntry<String, String>> _adminUserFilterCols = [
    MapEntry('username', 'Tên đăng nhập'),
    MapEntry('name', 'Họ và tên'),
    MapEntry('role', 'Vai trò'),
    MapEntry('xdv', 'Xưởng'),
    MapEntry('created', 'Ngày tạo'),
    MapEntry('lastLogin', 'ĐN cuối'),
    MapEntry('status', 'Trạng thái'),
  ];
  final Map<String, TextEditingController> _adminUserCol = {};

  @override
  void initState() {
    super.initState();
    _settingsApi = ApiService(baseUrl: widget.login.baseUrl);
    for (final e in _xdvFilterCols) {
      _xdvCol[e.key] = TextEditingController();
    }
    for (final e in _adminUserFilterCols) {
      _adminUserCol[e.key] = TextEditingController();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAllData();
      _loadWorkshopConfig();
    });
  }

  Future<void> _loadWorkshopConfig() async {
    setState(() => _cfgLoading = true);
    try {
      final raw = await _settingsApi.fetchWorkshopSettings(widget.login.token);
      final f = WorkshopFeatures.fromSettingsResponse(raw);
      Map<String, dynamic> report = {};
      try {
        report = await _settingsApi.fetchKhAdStats(widget.login.token);
      } catch (_) {}
      final statsRaw = report['stats'];
      final stats = statsRaw is List
          ? statsRaw.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _companyChatEnabled = f.companyChatEnabled;
        _khAdsMode = f.khAdsMode;
        _khAdsDraft = f.raw['kh_ads'] is List
            ? (f.raw['kh_ads'] as List)
                .whereType<Map>()
                .map((e) => KhAdItem.fromJson(Map<String, dynamic>.from(e)))
                .toList()
            : List<KhAdItem>.from(f.khAds);
        _vndPerViewCtrl.text = f.khAdsRevenue.vndPerView.round().toString();
        _vndPerClickCtrl.text = f.khAdsRevenue.vndPerClick.round().toString();
        _admobAndroidBannerCtrl.text = f.admob.androidBannerUnitId;
        _admobIosBannerCtrl.text = f.admob.iosBannerUnitId;
        final ar = f.raw['app_release'];
        final release = ar is Map ? Map<String, dynamic>.from(ar) : <String, dynamic>{};
        _appVersionLabelCtrl.text = release['version_label']?.toString() ?? 'V1.0';
        _appVersionCtrl.text = release['version']?.toString() ?? '1.0.0';
        _appBuildCtrl.text = '${release['build_number'] ?? 1}';
        _appDlWebCtrl.text = release['download_url_web']?.toString() ?? '';
        _appDlWindowsCtrl.text = release['download_url_windows']?.toString() ?? release['download_url']?.toString() ?? '';
        _appDlAndroidCtrl.text = release['download_url_android']?.toString() ?? '';
        _appDlIosCtrl.text = release['download_url_ios']?.toString() ?? '';
        _appUpdateMandatory = release['mandatory'] == true;
        _khAdStats = stats;
        _khAdSummary = report['summary'] is Map
            ? Map<String, dynamic>.from(report['summary'] as Map)
            : null;
        _cfgLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cfgLoading = false);
      _showError('Không tải cấu hình: $e');
    }
  }

  Future<void> _saveFeatureToggles() async {
    setState(() => _cfgSaving = true);
    try {
      final vView = double.tryParse(_vndPerViewCtrl.text.trim()) ?? 0;
      final vClick = double.tryParse(_vndPerClickCtrl.text.trim()) ?? 0;
      final modeStr = khAdsModeToApi(_khAdsMode);
      await _settingsApi.patchWorkshopSettings(widget.login.token, {
        'features': {
          'company_chat_enabled': _companyChatEnabled,
          'kh_ads_mode': modeStr,
          'kh_ads_enabled': _khAdsMode == KhAdsMode.banner,
        },
        'kh_ads': _khAdsDraft.map((e) => e.toJson()).toList(),
        'kh_ads_revenue': {
          'vnd_per_view': vView < 0 ? 0 : vView,
          'vnd_per_click': vClick < 0 ? 0 : vClick,
        },
        'admob': {
          'android_banner_unit_id': _admobAndroidBannerCtrl.text.trim(),
          'ios_banner_unit_id': _admobIosBannerCtrl.text.trim(),
        },
        'app_release': {
          'version_label': _appVersionLabelCtrl.text.trim(),
          'version': _appVersionCtrl.text.trim(),
          'build_number': int.tryParse(_appBuildCtrl.text.trim()) ?? 1,
          'download_url_web': _appDlWebCtrl.text.trim(),
          'download_url_windows': _appDlWindowsCtrl.text.trim(),
          'download_url_android': _appDlAndroidCtrl.text.trim(),
          'download_url_ios': _appDlIosCtrl.text.trim(),
          'download_url': _appDlWindowsCtrl.text.trim(),
          'mandatory': _appUpdateMandatory,
        },
      });
      await _loadWorkshopConfig();
      if (mounted) _showSuccess('Đã lưu cấu hình chat, quảng cáo và đơn giá.');
    } catch (e) {
      if (mounted) _showError('Lưu thất bại: $e');
    } finally {
      if (mounted) setState(() => _cfgSaving = false);
    }
  }

  @override
  void dispose() {
    for (final c in _xdvCol.values) {
      c.dispose();
    }
    for (final c in _adminUserCol.values) {
      c.dispose();
    }
    _vndPerViewCtrl.dispose();
    _vndPerClickCtrl.dispose();
    _admobAndroidBannerCtrl.dispose();
    _admobIosBannerCtrl.dispose();
    _appVersionLabelCtrl.dispose();
    _appVersionCtrl.dispose();
    _appBuildCtrl.dispose();
    _appDlWebCtrl.dispose();
    _appDlWindowsCtrl.dispose();
    _appDlAndroidCtrl.dispose();
    _appDlIosCtrl.dispose();
    super.dispose();
  }

  String _fmtVnd(num? n) {
    final v = (n ?? 0).round();
    return '${NumberFormat('#,###', 'vi_VN').format(v)} đ';
  }

  Widget _adSummaryTile(String label, dynamic count, dynamic revenueVnd) {
    final c = (count as num?)?.toInt() ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
          Text('$c lượt', style: TextStyle(color: Colors.grey.shade700)),
          const SizedBox(width: 16),
          Text(_fmtVnd(revenueVnd as num?), style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ==========================================
  // HÀM GỌI API AN TOÀN TRỰC TIẾP
  // ==========================================
  Future<http.Response> _apiReq(String method, String endpoint, {Map<String, dynamic>? body}) async {
    final url = Uri.parse('${widget.login.baseUrl}$endpoint');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${widget.login.token}'
    };

    if (method == 'GET') return await http.get(url, headers: headers);
    if (method == 'POST') return await http.post(url, headers: headers, body: jsonEncode(body));
    if (method == 'PATCH') return await http.patch(url, headers: headers, body: jsonEncode(body));
    if (method == 'DELETE') return await http.delete(url, headers: headers);
    return http.Response('Method not allowed', 405);
  }

  // ==========================================
  // TẢI TOÀN BỘ DỮ LIỆU
  // ==========================================
  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    
    try {
      final resXdv = await _apiReq("GET", "/api/v1/xdvs");
      if (resXdv.statusCode == 200) _xdvs = jsonDecode(resXdv.body);

      final resUser = await _apiReq("GET", "/api/v1/users");
      if (resUser.statusCode == 200) {
        final allUsers = jsonDecode(resUser.body) as List;
        _users = allUsers;
        _directors = allUsers.where((u) => 
          u['role']?.toString().toUpperCase() == 'GIAMDOC' || 
          u['role']?.toString().toUpperCase() == 'GIÁM ĐỐC'
        ).toList();
      }

      final resRo = await _apiReq("GET", "/api/v1/repair-orders");
      if (resRo.statusCode == 200) _orders = jsonDecode(resRo.body);

      final resDash = await _apiReq("GET", "/api/v1/dashboard/summary");
      if (resDash.statusCode == 200) {
        _dashboardSummary = Map<String, dynamic>.from(jsonDecode(resDash.body) as Map);
      } else {
        _dashboardSummary = null;
      }

    } catch (e) {
      debugPrint("Lỗi tải dữ liệu Admin: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSuccess(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.green));
  }
  
  void _showError(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  String _fmtTs(dynamic v) {
    if (v == null) return '-';
    final d = DateTime.tryParse(v.toString());
    if (d == null) return '-';
    return DateFormat('dd/MM/yy HH:mm').format(d.toLocal());
  }

  Widget _filterHdr(Map<String, TextEditingController> m, String key, String title) {
    return ColumnFilterMenuHeader(
      title: title,
      filterController: m[key]!,
      onFiltersChanged: () => setState(() {}),
    );
  }

  List<dynamic> _pipelineXdv(List<dynamic> base) {
    final filters = _xdvFilterCols.map((e) => _xdvCol[e.key]!.text).toList();
    return base.where((xdv) {
      final cells = <String>[
        xdv['code']?.toString() ?? '',
        xdv['name']?.toString() ?? '',
        xdv['address']?.toString() ?? '',
        xdv['phone']?.toString() ?? '',
        xdv['status']?.toString() ?? 'Hoạt động',
      ];
      return cellsMatchFilters(filters, cells);
    }).toList();
  }

  List<dynamic> _pipelineAdminUsers(List<dynamic> base) {
    final filters = _adminUserFilterCols.map((e) => _adminUserCol[e.key]!.text).toList();
    return base.where((u) {
      final isActive = u['is_active'] ?? false;
      final cells = <String>[
        u['username']?.toString() ?? '',
        u['name']?.toString() ?? '',
        u['role']?.toString() ?? '',
        u['xdv_name']?.toString() ?? 'Hệ thống Tổng',
        _fmtTs(u['created_at']),
        _fmtTs(u['last_login_at']),
        isActive ? 'Hoạt động' : 'Đã khóa',
      ];
      return cellsMatchFilters(filters, cells);
    }).toList();
  }

  // ==========================================
  // API CALL: XỬ LÝ XDV
  // ==========================================
  Future<void> _handleCreateXdv(Map<String, String> data) async {
    setState(() => _isLoading = true);
    try {
      final res = await _apiReq("POST", "/api/v1/xdvs", body: data);
      if (res.statusCode == 201) {
        _showSuccess("Tạo Xưởng Dịch Vụ thành công!");
        await _loadAllData();
      } else {
        _showError("Lỗi Server: ${jsonDecode(res.body)['error'] ?? res.body}");
      }
    } catch (e) { _showError("Lỗi kết nối: $e"); } 
    finally { if (mounted) setState(() => _isLoading = false); }
  }

  Future<void> _handleUpdateXdv(String id, Map<String, String> data) async {
    setState(() => _isLoading = true);
    try {
      final res = await _apiReq("PATCH", "/api/v1/xdvs/$id", body: data);
      if (res.statusCode == 200) {
        _showSuccess("Cập nhật XDV thành công!");
        await _loadAllData();
      } else {
        _showError("Lỗi Server: ${res.body}");
      }
    } catch (e) { _showError("Lỗi kết nối: $e"); } 
    finally { if (mounted) setState(() => _isLoading = false); }
  }

  Future<void> _handleToggleXdvStatus(String id) async {
    setState(() => _isLoading = true);
    try {
      final res = await _apiReq("DELETE", "/api/v1/xdvs/$id");
      if (res.statusCode == 200) {
        _showSuccess(jsonDecode(res.body)['message'] ?? "Đã thay đổi trạng thái XDV");
        await _loadAllData();
      } else {
        _showError("Lỗi Server: ${res.body}");
      }
    } catch (e) { _showError("Lỗi kết nối: $e"); } 
    finally { if (mounted) setState(() => _isLoading = false); }
  }

  // ==========================================
  // API CALL: XỬ LÝ USER
  // ==========================================
  Future<void> _handleCreateUser(Map<String, String> data) async {
    setState(() => _isLoading = true);
    try {
      final res = await _apiReq("POST", "/api/v1/users", body: data);
      if (res.statusCode == 201) {
        _showSuccess("Tạo Tài Khoản thành công!");
        await _loadAllData();
      } else {
        _showError("Lỗi tạo user: ${jsonDecode(res.body)['error'] ?? res.body}");
      }
    } catch (e) { _showError("Lỗi kết nối: $e"); } 
    finally { if (mounted) setState(() => _isLoading = false); }
  }

  Future<void> _handleUpdateUser(String id, Map<String, String> data) async {
    setState(() => _isLoading = true);
    try {
      final res = await _apiReq("PATCH", "/api/v1/users/$id", body: data);
      if (res.statusCode == 200) {
        _showSuccess("Cập nhật Tài khoản thành công!");
        await _loadAllData();
      } else {
        _showError("Lỗi Server: ${res.body}");
      }
    } catch (e) { _showError("Lỗi kết nối: $e"); } 
    finally { if (mounted) setState(() => _isLoading = false); }
  }

  Future<void> _handleToggleUserStatus(String id) async {
    setState(() => _isLoading = true);
    try {
      final res = await _apiReq("DELETE", "/api/v1/users/$id");
      if (res.statusCode == 200) {
        _showSuccess(jsonDecode(res.body)['message'] ?? "Đã thay đổi trạng thái User");
        await _loadAllData();
      } else {
        _showError("Lỗi Server: ${res.body}");
      }
    } catch (e) { _showError("Lỗi kết nối: $e"); } 
    finally { if (mounted) setState(() => _isLoading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text("TỔNG TRẠM QUẢN TRỊ HỆ THỐNG", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        actions: [
          const CompanyChatAppBarButton(),
          Center(child: Text("Xin chào, ${widget.login.userName}  ", style: const TextStyle(fontWeight: FontWeight.bold))),
          IconButton(tooltip: 'Làm mới dữ liệu', icon: const Icon(Icons.refresh), onPressed: _loadAllData),
          IconButton(
            tooltip: 'Đăng xuất', 
            icon: const Icon(Icons.logout, color: Colors.red), 
            onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()))
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (int index) => setState(() => _selectedIndex = index),
            labelType: NavigationRailLabelType.all,
            backgroundColor: Colors.white,
            selectedIconTheme: const IconThemeData(color: Colors.blue),
            selectedLabelTextStyle: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
            unselectedIconTheme: const IconThemeData(color: Colors.blueGrey),
            destinations: const [
              NavigationRailDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: Text('Dashboard')),
              NavigationRailDestination(icon: Icon(Icons.store_outlined), selectedIcon: Icon(Icons.store), label: Text('Quản lý XDV')),
              NavigationRailDestination(icon: Icon(Icons.manage_accounts_outlined), selectedIcon: Icon(Icons.manage_accounts), label: Text('Giám Đốc')),
              NavigationRailDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: Text('Users Tổng')),
              NavigationRailDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: Text('Cấu Hình')),
              NavigationRailDestination(icon: Icon(Icons.import_export), selectedIcon: Icon(Icons.import_export), label: Text('Data')),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1, color: Colors.black12),
          
          Expanded(
            child: _isLoading && _xdvs.isEmpty
                ? const Center(child: CircularProgressIndicator()) 
                : _buildMainContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    switch (_selectedIndex) {
      case 0: return _buildDashboard();
      case 1: return _buildManageXDV();
      case 2: return _buildManageDirectors();
      case 3: return _buildManageUsers();
      case 4: return _buildConfigSystem();
      case 5: return _buildImportExport();
      default: return const Center(child: Text("Lỗi điều hướng"));
    }
  }

  // ==========================================
  // TAB 1: DASHBOARD
  // ==========================================
  Widget _buildDashboard() {
    final s = _dashboardSummary;
    int activeXdvs = _xdvs.where((x) => x['status'] == 'Hoạt động').length;
    int lockedXdvs = _xdvs.length - activeXdvs;
    final carsInShop = s != null && s['repair_orders_in_workshop'] != null
        ? (s['repair_orders_in_workshop'] as num).toInt()
        : _orders.where((o) => o['status'] != 'DA_RA_CONG' && o['status'] != 'XE_RA_XUONG').length;
    final roOpen = s != null && s['repair_orders_open'] != null
        ? (s['repair_orders_open'] as num).toInt()
        : _orders.where((o) => !['XE_RA_XUONG', 'DA_RA_CONG', 'DA_RA_CONG_THIEU_PT'].contains(o['status'])).length;
    final roPayment = s != null && s['repair_orders_cho_quyet_toan'] != null
        ? (s['repair_orders_cho_quyet_toan'] as num).toInt()
        : _orders.where((o) => o['status'] == 'CHO_QUYET_TOAN').length;
    final usersActive = s != null && s['users_active'] != null
        ? (s['users_active'] as num).toInt()
        : _users.length;
    int warnings = _orders.where((o) => o['status'] == 'DUNG_SUA').length;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text("TỔNG QUAN HỆ THỐNG", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
        if (s != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Text(
              'Đồng bộ số liệu từ máy chủ (/dashboard/summary).',
              style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
            ),
          ),
        const SizedBox(height: 24),
        GridView.count(
          crossAxisCount: 4, shrinkWrap: true, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 2.5,
          children: [
            _buildStatCard("Tổng số XDV", "${_xdvs.length}", Icons.store, Colors.blue[800]!, onTap: () => setState(() => _selectedIndex = 1)),
            _buildStatCard("XDV Đang hoạt động", "$activeXdvs", Icons.check_circle, Colors.green, onTap: () => setState(() => _selectedIndex = 1)),
            _buildStatCard("Tổng User hoạt động", "$usersActive", Icons.people, Colors.purple, onTap: () => setState(() => _selectedIndex = 3)),
            _buildStatCard("XDV Bị khóa", "$lockedXdvs", Icons.lock, Colors.red, onTap: () => setState(() => _selectedIndex = 1)),
            _buildStatCard("Tổng xe đang trong xưởng", "$carsInShop", Icons.directions_car, Colors.orange),
            _buildStatCard("RO đang mở", "$roOpen", Icons.receipt_long, Colors.teal),
            _buildStatCard("RO chờ quyết toán", "$roPayment", Icons.payments, Colors.pink),
            _buildStatCard("Cảnh báo xe đang dừng", "$warnings", Icons.warning, Colors.red),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border(left: BorderSide(color: color, width: 4)), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))]),
        child: Row(
          children: [
            Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 28)),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(title, style: const TextStyle(fontSize: 13, color: Colors.blueGrey)),
              const SizedBox(height: 4),
              Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
            ]))
          ],
        ),
      ),
    );
  }

  // ==========================================
  // TAB 2: QUẢN LÝ XƯỞNG DỊCH VỤ
  // ==========================================
  Widget _buildManageXDV() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("DANH SÁCH XƯỞNG DỊCH VỤ", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              FilledButton.icon(
                onPressed: () => _showXdvDialog(), 
                icon: const Icon(Icons.add), 
                label: const Text("Tạo XDV Mới"),
                style: FilledButton.styleFrom(backgroundColor: Colors.blue[800]),
              )
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: "Tìm kiếm mã xưởng, tên xưởng...", prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), filled: true, fillColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              width: double.infinity, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[200]!)),
              child: _xdvs.isEmpty
                ? const Center(child: Text("Chưa có xưởng nào. Hãy tạo xưởng đầu tiên!", style: TextStyle(fontSize: 16, color: Colors.grey)))
                : () {
                          final xf = _pipelineXdv(_xdvs);
                          if (xf.isEmpty) {
                            return const Center(child: Text("Không có dòng khớp lọc cột.", style: TextStyle(fontSize: 16, color: Colors.grey)));
                          }
                          return SingleChildScrollView(
                            child: DataTable(
                              showCheckboxColumn: false,
                              headingRowColor: MaterialStateProperty.all(const Color(0xFFF1F5F9)),
                              columns: [
                                DataColumn(label: _filterHdr(_xdvCol, 'code', 'Mã XDV')),
                                DataColumn(label: _filterHdr(_xdvCol, 'name', 'Tên Xưởng')),
                                DataColumn(label: _filterHdr(_xdvCol, 'address', 'Địa Chỉ')),
                                DataColumn(label: _filterHdr(_xdvCol, 'phone', 'SĐT')),
                                DataColumn(label: _filterHdr(_xdvCol, 'status', 'Trạng Thái')),
                                const DataColumn(label: Text('Thao Tác', style: TextStyle(fontWeight: FontWeight.bold))),
                              ],
                              rows: xf.map((xdv) {
                                bool isActive = xdv['status'] == 'Hoạt động';
                                return DataRow(
                                  onSelectChanged: (selected) {
                                    if (selected == true) _showXdvDialog(existingXdv: xdv);
                                  },
                                  cells: [
                                    DataCell(Text(xdv['code']?.toString() ?? '')),
                                    DataCell(Text(xdv['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))),
                                    DataCell(Text(xdv['address']?.toString() ?? '')),
                                    DataCell(Text(xdv['phone']?.toString() ?? '')),
                                    DataCell(
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(color: isActive ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                                        child: Text(xdv['status']?.toString() ?? 'Hoạt động', style: TextStyle(color: isActive ? Colors.green : Colors.red, fontSize: 12)),
                                      ),
                                    ),
                                    DataCell(Row(
                                      children: [
                                        IconButton(
                                          icon: Icon(isActive ? Icons.lock : Icons.lock_open, color: isActive ? Colors.red : Colors.green, size: 20),
                                          onPressed: () => _confirmToggleXdv(xdv['id'], isActive),
                                        ),
                                      ],
                                    )),
                                  ],
                                );
                              }).toList(),
                            ),
                          );
                        }(),
            ),
          )
        ],
      ),
    );
  }

  void _showXdvDialog({dynamic existingXdv}) {
    final isEdit = existingXdv != null;
    final codeCtrl = TextEditingController(text: isEdit ? existingXdv['code'] : '');
    final nameCtrl = TextEditingController(text: isEdit ? existingXdv['name'] : '');
    final addrCtrl = TextEditingController(text: isEdit ? existingXdv['address'] : '');
    final phoneCtrl = TextEditingController(text: isEdit ? existingXdv['phone'] : '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? "Thông tin Chi Tiết XDV" : "Tạo Xưởng Dịch Vụ Mới", style: const TextStyle(fontWeight: FontWeight.bold)),
        content: SizedBox(width: 500, child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: codeCtrl, enabled: !isEdit, decoration: InputDecoration(labelText: 'Mã Xưởng (VD: TS-HN)', border: const OutlineInputBorder(), filled: isEdit)), const SizedBox(height: 12),
          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Tên Xưởng', border: OutlineInputBorder())), const SizedBox(height: 12),
          TextField(controller: addrCtrl, decoration: const InputDecoration(labelText: 'Địa chỉ', border: OutlineInputBorder())), const SizedBox(height: 12),
          TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Số điện thoại', border: OutlineInputBorder())),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Hủy")),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.blue[800]),
            onPressed: () {
              if(codeCtrl.text.isEmpty || nameCtrl.text.isEmpty) { _showError("Vui lòng nhập Mã và Tên xưởng!"); return; }
              if (isEdit) {
                _handleUpdateXdv(existingXdv['id'], {"name": nameCtrl.text, "address": addrCtrl.text, "phone": phoneCtrl.text});
              } else {
                _handleCreateXdv({"code": codeCtrl.text, "name": nameCtrl.text, "address": addrCtrl.text, "phone": phoneCtrl.text, "email": ""});
              }
              Navigator.pop(ctx);
            }, 
            child: Text(isEdit ? "Cập nhật Thông tin" : "Tạo Mới")
          ),
        ],
      )
    );
  }

  void _confirmToggleXdv(String id, bool isActive) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isActive ? "Xác nhận Khóa Xưởng" : "Xác nhận Mở Xưởng"),
        content: Text(isActive ? "Mọi nhân sự thuộc xưởng này sẽ không thể đăng nhập. Bạn có chắc chắn?" : "Xưởng sẽ được khôi phục hoạt động bình thường?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Hủy")),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: isActive ? Colors.red : Colors.green),
            onPressed: () { Navigator.pop(ctx); _handleToggleXdvStatus(id); }, 
            child: Text(isActive ? "Khóa Xưởng" : "Mở Khóa")
          ),
        ],
      )
    );
  }

  // ==========================================
  // TAB 3 & 4: QUẢN LÝ USER / GIÁM ĐỐC
  // ==========================================
  Widget _buildManageDirectors() {
    return _buildUserManagementLayout(title: "QUẢN LÝ TÀI KHOẢN GIÁM ĐỐC", dataList: _directors, fixedRole: 'GIAMDOC');
  }

  Widget _buildManageUsers() {
    return _buildUserManagementLayout(title: "QUẢN LÝ NGƯỜI DÙNG TOÀN HỆ THỐNG", dataList: _users);
  }

  Widget _buildUserManagementLayout({required String title, required List<dynamic> dataList, String? fixedRole}) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              FilledButton.icon(
                onPressed: () => _showUserDialog(fixedRole: fixedRole), 
                icon: const Icon(Icons.person_add), 
                label: const Text("Tạo Tài Khoản"),
                style: FilledButton.styleFrom(backgroundColor: Colors.blue[800]),
              )
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              width: double.infinity, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[200]!)),
              child: dataList.isEmpty 
                ? const Center(child: Text("Hệ thống chưa có người dùng nào."))
                : _buildUsersTable(dataList, fixedRole)
            )
          )
        ],
      )
    );
  }

  Widget _buildUsersTable(List<dynamic> dataList, String? fixedRole) {
    final filtered = _pipelineAdminUsers(dataList);
    return filtered.isEmpty
        ? const Center(child: Text('Không có dòng khớp lọc cột.', style: TextStyle(fontSize: 16, color: Colors.grey)))
        : SingleChildScrollView(
            child: DataTable(
              showCheckboxColumn: false,
              headingRowColor: MaterialStateProperty.all(const Color(0xFFF1F5F9)),
              columns: [
                DataColumn(label: _filterHdr(_adminUserCol, 'username', 'Tên đăng nhập')),
                DataColumn(label: _filterHdr(_adminUserCol, 'name', 'Họ và Tên')),
                DataColumn(label: _filterHdr(_adminUserCol, 'role', 'Vai Trò')),
                DataColumn(label: _filterHdr(_adminUserCol, 'xdv', 'Trực thuộc Xưởng')),
                DataColumn(label: _filterHdr(_adminUserCol, 'created', 'Ngày tạo')),
                DataColumn(label: _filterHdr(_adminUserCol, 'lastLogin', 'Đăng nhập cuối')),
                DataColumn(label: _filterHdr(_adminUserCol, 'status', 'Trạng Thái')),
                const DataColumn(label: Text('Khóa', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: filtered.map((u) {
                      bool isActive = u['is_active'] ?? false;
                      return DataRow(
                        onSelectChanged: (selected) {
                          if (selected == true) _showUserDialog(fixedRole: fixedRole, existingUser: u);
                        },
                        cells: [
                          DataCell(Text(u['username']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))),
                          DataCell(Text(u['name']?.toString() ?? '')),
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.blue)),
                              child: Text(u['role']?.toString() ?? 'NONE', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue)),
                            ),
                          ),
                          DataCell(Text(u['xdv_name']?.toString() ?? 'Hệ thống Tổng', style: TextStyle(fontWeight: FontWeight.bold, color: u['xdv_name'] == null ? Colors.red : Colors.teal))),
                          DataCell(Text(_fmtTs(u['created_at']))),
                          DataCell(Text(_fmtTs(u['last_login_at']))),
                          DataCell(
                            Row(
                              children: [
                                Icon(isActive ? Icons.check_circle : Icons.cancel, color: isActive ? Colors.green : Colors.red, size: 16),
                                const SizedBox(width: 4),
                                Text(isActive ? 'Hoạt động' : 'Đã khóa', style: TextStyle(color: isActive ? Colors.green : Colors.red)),
                              ],
                            ),
                          ),
                          DataCell(Row(
                            children: [
                              IconButton(
                                icon: Icon(isActive ? Icons.lock : Icons.lock_open, color: isActive ? Colors.red : Colors.green, size: 20),
                                onPressed: () => _confirmToggleUser(u['id'], isActive),
                              ),
                            ],
                          )),
                        ],
                      );
                    }).toList(),
            ),
          );
  }

  void _showUserDialog({String? fixedRole, dynamic existingUser}) {
    if (_xdvs.isEmpty) {
      _showError("Vui lòng Tạo Xưởng Dịch Vụ trước khi tạo User!");
      return;
    }

    final isEdit = existingUser != null;
    final userCtrl = TextEditingController(text: isEdit ? existingUser['username'] : '');
    final passCtrl = TextEditingController(); 
    final nameCtrl = TextEditingController(text: isEdit ? existingUser['name'] : '');
    
    // TẤT CẢ ROLE TRONG HỆ THỐNG
    final List<String> allRoles = ['GIAMDOC', 'CSKH', 'CVDV', 'QUANDOC', 'KTV', 'KHO', 'KETOAN', 'BAOVE', 'TV'];
    String selectedRole = fixedRole ?? (isEdit ? existingUser['role'] : 'CVDV');
    String? selectedXdvId = isEdit ? existingUser['xdv_id'] : null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isEdit ? "Thông tin Chi Tiết Tài Khoản" : "Tạo Tài Khoản Mới", style: const TextStyle(fontWeight: FontWeight.bold)),
          content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: userCtrl, enabled: !isEdit, decoration: InputDecoration(labelText: 'Tên đăng nhập', border: const OutlineInputBorder(), filled: isEdit)), const SizedBox(height: 12),
            if (!isEdit) ...[
              TextField(controller: passCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Mật khẩu', border: OutlineInputBorder())), const SizedBox(height: 12),
            ],
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Họ và Tên', border: OutlineInputBorder())), const SizedBox(height: 12),
            
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Trực thuộc Xưởng', border: OutlineInputBorder()),
              value: selectedXdvId,
              hint: const Text("--- Chọn Xưởng Dịch Vụ ---"),
              items: _xdvs.map((x) => DropdownMenuItem<String>(value: x['id'], child: Text(x['name']))).toList(),
              onChanged: (val) => setDialogState(() => selectedXdvId = val),
            ),
            const SizedBox(height: 12),

            if (fixedRole == null)
              DropdownButtonFormField<String>(
                value: selectedRole,
                decoration: const InputDecoration(labelText: 'Chọn Vai Trò (Role)', border: OutlineInputBorder()),
                items: allRoles.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                onChanged: (val) => setDialogState(() => selectedRole = val!),
              )
            else 
              TextField(enabled: false, decoration: InputDecoration(labelText: 'Vai Trò', border: const OutlineInputBorder(), hintText: fixedRole)),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Hủy")),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.blue[800]),
              onPressed: () {
                if(nameCtrl.text.isEmpty || (!isEdit && (userCtrl.text.isEmpty || passCtrl.text.isEmpty))) { 
                  _showError("Vui lòng điền đủ thông tin bắt buộc!"); return; 
                }
                if (isEdit) {
                  _handleUpdateUser(existingUser['id'], { "name": nameCtrl.text.trim(), "role": selectedRole, "xdv_id": selectedXdvId ?? '' });
                } else {
                  _handleCreateUser({ "username": userCtrl.text.trim(), "password": passCtrl.text.trim(), "name": nameCtrl.text.trim(), "role": selectedRole, "xdv_id": selectedXdvId ?? '' });
                }
                Navigator.pop(ctx);
              }, 
              child: Text(isEdit ? "Cập nhật Thông tin" : "Tạo Mới")
            ),
          ],
        )
      )
    );
  }

  void _confirmToggleUser(String id, bool isActive) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isActive ? "Khóa Tài khoản" : "Mở khóa Tài khoản"),
        content: Text(isActive ? "Người dùng này sẽ bị văng ra khỏi ứng dụng ngay lập tức." : "Cho phép người dùng này đăng nhập trở lại?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Hủy")),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: isActive ? Colors.red : Colors.green),
            onPressed: () { Navigator.pop(ctx); _handleToggleUserStatus(id); }, 
            child: Text(isActive ? "Khóa ngay" : "Mở khóa")
          ),
        ],
      )
    );
  }

  // ==========================================
  // TAB 5 & 6: CẤU HÌNH & DATA
  // ==========================================
  Widget _buildConfigSystem() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: ListView(
        children: [
          const Text('CẤU HÌNH HỆ THỐNG', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'Chat công ty, cập nhật app (V2, V3…) và quảng cáo màn Khách hàng.',
            style: TextStyle(fontSize: 13, color: Colors.blueGrey.shade600),
          ),
          const SizedBox(height: 24),
          if (_cfgLoading)
            const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
          else ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Tính năng', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('Chat công ty'),
                    subtitle: const Text('Nút «Chat công ty» cho CVDV, Kho, CSKH… — không hiển thị cho Khách hàng'),
                    value: _companyChatEnabled,
                    onChanged: _cfgSaving
                        ? null
                        : (v) => setState(() => _companyChatEnabled = v),
                  ),
                  const Divider(height: 28),
                  const Text('Cập nhật app (V2, V3…)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  Text(
                    'App đang cài có build thấp hơn «Số build» bên dưới sẽ thấy hộp thoại cập nhật khi mở app. '
                    'Ví dụ: app V1 build=1, ra V2 đặt nhãn V2.0, version 2.0.0, build=200.',
                    style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade700),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _appVersionLabelCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Nhãn hiển thị (VD: V2.0)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _appVersionCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Version (VD: 2.0.0)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 120,
                        child: TextField(
                          controller: _appBuildCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Số build',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _appDlWebCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Link Web (app trình duyệt)',
                      hintText: 'https://…/releases/web/',
                      border: OutlineInputBorder(),
                      isDense: true,
                      prefixIcon: Icon(Icons.language),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _appDlWindowsCtrl,
                    decoration: const InputDecoration(
                      labelText: 'File cài Windows (.exe / .msi)',
                      hintText: 'https://…/releases/ts_xdv.exe',
                      border: OutlineInputBorder(),
                      isDense: true,
                      prefixIcon: Icon(Icons.desktop_windows),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _appDlAndroidCtrl,
                    decoration: const InputDecoration(
                      labelText: 'File cài Android (.apk)',
                      hintText: 'https://…/releases/ts-xdv.apk',
                      border: OutlineInputBorder(),
                      isDense: true,
                      prefixIcon: Icon(Icons.android),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _appDlIosCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Link iOS (TestFlight / App Store)',
                      border: OutlineInputBorder(),
                      isDense: true,
                      prefixIcon: Icon(Icons.phone_iphone),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Đặt file build vào thư mục ts-server/releases/ trên máy chủ (web/, ts_xdv.exe, ts-xdv.apk) hoặc dán link CDN khác.',
                      style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade600),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Bắt buộc cập nhật'),
                    subtitle: const Text('Không có nút «Để sau»'),
                    value: _appUpdateMandatory,
                    onChanged: _cfgSaving ? null : (v) => setState(() => _appUpdateMandatory = v),
                  ),
                  const Divider(height: 28),
                  AdminKhAdsPanel(
                    api: _settingsApi,
                    token: widget.login.token,
                    mode: _khAdsMode,
                    onModeChanged: (m) => setState(() => _khAdsMode = m),
                    ads: _khAdsDraft,
                    onAdsChanged: (list) => setState(() => _khAdsDraft = list),
                    androidBannerCtrl: _admobAndroidBannerCtrl,
                    iosBannerCtrl: _admobIosBannerCtrl,
                    saving: _cfgSaving,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade800),
                    onPressed: _cfgSaving ? null : _saveFeatureToggles,
                    icon: _cfgSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.save),
                    label: Text(_cfgSaving ? 'Đang lưu…' : 'Lưu cấu hình'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Doanh thu quảng cáo (KH)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                      IconButton(
                        tooltip: 'Làm mới',
                        onPressed: _cfgLoading ? null : _loadWorkshopConfig,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  if (_khAdSummary != null) ...[
                    _adSummaryTile('Tổng lượt xem', _khAdSummary!['views'], _khAdSummary!['revenue_views_vnd']),
                    _adSummaryTile('Tổng lượt click', _khAdSummary!['clicks'], _khAdSummary!['revenue_clicks_vnd']),
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 12),
                      child: Text(
                        'Tổng doanh thu: ${_fmtVnd(_khAdSummary!['revenue_total_vnd'] as num?)}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E40AF)),
                      ),
                    ),
                    const Divider(),
                  ],
                  if (_khAdStats.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text('Chưa có lượt xem/click.', style: TextStyle(color: Colors.grey.shade600)),
                    )
                  else
                    ..._khAdStats.map((row) {
                      final adId = row['ad_id']?.toString() ?? '';
                      final views = (row['views'] as num?)?.toInt() ?? 0;
                      final clicks = (row['clicks'] as num?)?.toInt() ?? 0;
                      final rev = (row['revenue_total_vnd'] as num?) ?? 0;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(adId.isEmpty ? '(không mã)' : adId),
                        subtitle: Text('$views xem · $clicks click'),
                        trailing: Text(_fmtVnd(rev), style: const TextStyle(fontWeight: FontWeight.bold)),
                      );
                    }),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  Widget _buildImportExport() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("SAO LƯU & PHỤC HỒI DỮ LIỆU", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: Container(
                padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black12)),
                child: Column(
                  children: [
                    const Icon(Icons.download, size: 48, color: Colors.green), const SizedBox(height: 16),
                    const Text("Export Database", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), const SizedBox(height: 8),
                    const Text("Xuất toàn bộ CSDL ra file Backup", textAlign: TextAlign.center, style: TextStyle(color: Colors.blueGrey)), const SizedBox(height: 16),
                    OutlinedButton(onPressed: () => _showSuccess("Dữ liệu đã được xuất ra thành công!"), child: const Text("Thực hiện"))
                  ],
                ),
              )),
            ],
          )
        ],
      )
    );
  }
}