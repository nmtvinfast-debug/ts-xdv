import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;

import '../models/auth_models.dart';
import '../services/api_service.dart';
import '../core/document_export.dart';
import '../core/workshop_local_sync.dart';
import '../core/pick_file_bytes.dart';
import '../core/responsive_layout.dart';
import '../widgets/responsive_shell.dart';
import '../widgets/company_chat_host.dart';
import '../widgets/maintenance_reminder_panel.dart';
import 'login_screen.dart';

class StaffUser {
  String id; String fullName; String username; String role; String phone; bool isActive;
  StaffUser({required this.id, required this.fullName, required this.username, required this.role, required this.phone, this.isActive = true});
  factory StaffUser.fromJson(Map<String, dynamic> json) => StaffUser(id: json['id']?.toString() ?? '', fullName: json['fullName']?.toString() ?? '', username: json['username']?.toString() ?? '', role: json['role']?.toString() ?? '', phone: json['phone']?.toString() ?? '', isActive: json['isActive'] ?? true);
  factory StaffUser.fromUserItem(UserItem u) => StaffUser(
    id: u.id,
    fullName: u.fullName,
    username: u.username,
    role: u.role,
    phone: u.phone ?? '',
    isActive: u.isActive,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is StaffUser && other.username == username;

  @override
  int get hashCode => username.hashCode;
}

class LocalBooking {
  final String id;
  final String bienSo;
  final String customerName;
  final String customerPhone;
  final String carModel;
  final String time;
  final String note;
  final String status;

  LocalBooking({required this.id, required this.bienSo, required this.customerName, required this.customerPhone, required this.carModel, required this.time, required this.note, required this.status});

  factory LocalBooking.fromJson(Map<String, dynamic> json) {
    return LocalBooking(
      id: json['id']?.toString() ?? '',
      bienSo: json['bien_so']?.toString() ?? '',
      customerName: json['customer_name']?.toString() ?? '',
      customerPhone: json['customer_phone']?.toString() ?? '',
      carModel: json['car_model']?.toString() ?? '',
      time: json['time']?.toString() ?? '',
      note: json['note']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
    );
  }
}

/// Trùng với app KH — lịch chờ CSKH xác nhận trước khi «Chờ tiếp nhận».
const String kBookingAwaitingCskh = 'Chờ CSKH duyệt';

class CskhDashboardScreen extends StatefulWidget {
  const CskhDashboardScreen({super.key, required this.login});
  final LoginResult login;

  @override
  State<CskhDashboardScreen> createState() => _CskhDashboardScreenState();
}

class _CskhDashboardScreenState extends State<CskhDashboardScreen> {
  late final ApiService api;
  bool loading = false;
  
  List<WorkOrderItem> orders = [];
  List<StaffUser> cvdvs = []; 
  List<LocalBooking> bookings = [];
  
  WorkOrderItem? selectedOrder;
  StaffUser? selectedCvdv;

  final bienSoCtrl = TextEditingController();
  final tenKhCtrl = TextEditingController();
  final sdtCtrl = TextEditingController();
  final dongXeCtrl = TextEditingController();
  final ngayHenCtrl = TextEditingController(text: DateFormat('dd/MM/yyyy').format(DateTime.now()));
  final gioHenCtrl = TextEditingController(text: '08:00');
  final yeuCauCtrl = TextEditingController();

  DateTime selectedBookingDate = DateTime.now();

  @override
  void initState() { 
    super.initState(); 
    api = ApiService(baseUrl: widget.login.baseUrl); 
    _loadData(); 
  }

  Future<void> _loadData({bool showNotice = false}) async {
    setState(() => loading = true);
    try {
      final loadedOrders = await api.fetchBoard(widget.login.token);
      
      List<StaffUser> cvdvList = [];
      try {
        final apiCvdvs = await api.fetchAssignableCvdv(widget.login.token);
        cvdvList = apiCvdvs.where((u) => u.isActive).map(StaffUser.fromUserItem).toList();
      } catch (e) {
        debugPrint('Lỗi tải CVDV từ server: $e');
      }
      if (cvdvList.isEmpty) {
        try {
          final data = await loadWorkshopJson(
            fileName: 'staff_db.json',
            api: api,
            token: widget.login.token,
          );
          if (data is List) {
            final localStaffs = data.map((e) => StaffUser.fromJson(Map<String, dynamic>.from(e as Map))).toList();
            cvdvList = localStaffs
                .where((u) =>
                    u.isActive &&
                    (u.role.toUpperCase().contains('CVDV') || u.role.toUpperCase().contains('CỐ VẤN')))
                .toList();
          }
        } catch (e) {
          debugPrint('Lỗi đọc staff_db: $e');
        }
      }

      List<LocalBooking> loadedBookings = [];
      try {
        final bUrl = Uri.parse('${widget.login.baseUrl}/api/v1/bookings');
        final bRes = await http.get(bUrl, headers: {'Authorization': 'Bearer ${widget.login.token}'});
        if (bRes.statusCode == 200) {
          List<dynamic> bJson = jsonDecode(bRes.body);
          loadedBookings = bJson.map((e) => LocalBooking.fromJson(e)).toList();
        }
      } catch (e) { debugPrint('Lỗi tải bookings: $e'); }

      DateTime now = DateTime.now();
      DateTime today = DateTime(now.year, now.month, now.day);
      int deletedCount = 0;

      for (var b in loadedBookings) {
        DateTime? bDate = _parseDate(b.time);
        if (bDate != null && today.difference(bDate).inDays >= 1) {
          try {
            final url = Uri.parse('${widget.login.baseUrl}/api/v1/bookings/${b.id}');
            await http.delete(url, headers: {'Authorization': 'Bearer ${widget.login.token}'});
            deletedCount++;
          } catch (_) {}
        }
      }

      if (deletedCount > 0 && showNotice && mounted) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã dọn dẹp $deletedCount lịch hẹn quá hạn.'), backgroundColor: Colors.orange));
      }

      setState(() {
        orders = loadedOrders;
        cvdvs = cvdvList;

        bookings = loadedBookings.where((b) {
           DateTime? bDate = _parseDate(b.time);
           if (bDate == null) return true;
           return today.difference(bDate).inDays < 1;
        }).toList();

        cvdvs.sort((a, b) => _getWorkload(a.username).compareTo(_getWorkload(b.username)));
        if (selectedOrder != null) {
          try { selectedOrder = orders.firstWhere((o) => o.id == selectedOrder!.id); } catch (_) { selectedOrder = null; }
        }
        if (selectedCvdv != null) {
          try {
            selectedCvdv = cvdvs.firstWhere((u) => u.username == selectedCvdv!.username);
          } catch (_) {
            selectedCvdv = null;
          }
        }
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi tải dữ liệu: $e'), backgroundColor: Colors.red));
    } finally {
      setState(() => loading = false);
    }
  }

  int _getWorkload(String username) {
    return orders.where((o) => o.cvdvUsername == username && !['XE_RA_XUONG', 'HUY', 'HUY_CHO_QUYET_TOAN', 'KT_DUYET_RA_CONG'].contains(o.status)).length;
  }

  // ===========================================================================
  // CỖ MÁY ĐẢO NGƯỢC LỖI NGÀY THÁNG EXCEL (MỸ -> VIỆT NAM)
  // ===========================================================================
  String _extractCellValue(dynamic cell) {
    if (cell == null) return '';
    String s = cell.toString().trim();
    
    // Nếu là dạng Date của Excel Mỹ (bị ngược tháng với ngày)
    if (s.startsWith('DateCellValue(')) {
      final y = RegExp(r'year:\s*(\d+)').firstMatch(s)?.group(1);
      final m = RegExp(r'month:\s*(\d+)').firstMatch(s)?.group(1); // Tháng Mỹ = Ngày Việt Nam
      final d = RegExp(r'day:\s*(\d+)').firstMatch(s)?.group(1);   // Ngày Mỹ = Tháng Việt Nam
      
      if (y != null && m != null && d != null) {
        // ĐẢO NGƯỢC LẠI CHO ĐÚNG (m và d đổi chỗ)
        return '${m.padLeft(2, '0')}/${d.padLeft(2, '0')}/$y'; 
      }
    } 
    else if (s.startsWith('TextCellValue(') || s.startsWith('IntCellValue(') || s.startsWith('DoubleCellValue(')) {
      int start = s.indexOf('(');
      int end = s.lastIndexOf(')');
      if (start != -1 && end != -1) return s.substring(start + 1, end).trim();
    }
    return s;
  }

  String _normalizeDate(String input) {
    input = input.trim();
    if (input.isEmpty) return '';
    input = input.split(' ')[0].split('T')[0]; // Chặt bỏ chữ T thừa
    
    if (input.contains('-')) {
      var p = input.split('-');
      if (p.length == 3) {
        if (p[0].length == 4) {
          // Nếu CSV lưu dạng Mỹ: 2026-09-05 (09 là ngày, 05 là tháng) => Đảo lại!
          return '${p[1].padLeft(2,'0')}/${p[2].padLeft(2,'0')}/${p[0]}';
        }
        return '${p[0].padLeft(2,'0')}/${p[1].padLeft(2,'0')}/${p[2]}';
      }
    } else if (input.contains('/')) {
      var p = input.split('/');
      if (p.length == 3) return '${p[0].padLeft(2,'0')}/${p[1].padLeft(2,'0')}/${p[2]}';
    }
    return input;
  }

  DateTime? _parseDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return null;
    try {
      String dateOnly = _normalizeDate(dateStr);
      var p = dateOnly.split('/');
      if (p.length == 3) return DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
    } catch (e) { return null; }
    return null;
  }

  String _formatHour(String rawHour) {
    String h = rawHour.toLowerCase().replaceAll('h', ':').trim();
    if (!h.contains(':')) h += ':00';
    try {
      var p = h.split(':');
      return '${p[0].padLeft(2, '0')}:${p[1].padLeft(2, '0')}';
    } catch (e) { return '08:00'; }
  }

  Future<void> _selectBookingDate(BuildContext context, {bool isForFilter = true}) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isForFilter ? selectedBookingDate : DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        if (isForFilter) {
          selectedBookingDate = picked;
        } else {
          ngayHenCtrl.text = DateFormat('dd/MM/yyyy').format(picked);
        }
      });
    }
  }

  void _kiemTraThongTin() {
    String bs = bienSoCtrl.text.trim().toLowerCase().replaceAll(RegExp(r'[\s-]'), '');
    if (bs.isEmpty) return;
    bool found = false;
    for (var b in bookings) {
      if (b.bienSo.replaceAll(RegExp(r'[\s-]'), '').toLowerCase() == bs) {
        setState(() { 
          tenKhCtrl.text = b.customerName; 
          sdtCtrl.text = b.customerPhone; 
          dongXeCtrl.text = b.carModel;
        });
        found = true; break;
      }
    }
    if (!found) {
      for (var o in orders) {
        if (o.bienSo.replaceAll(RegExp(r'[\s-]'), '').toLowerCase() == bs) {
          setState(() { 
            tenKhCtrl.text = o.customerName ?? ''; 
            sdtCtrl.text = o.customerPhone ?? ''; 
          });
          found = true; break;
        }
      }
    }
    if (!found) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không tìm thấy dữ liệu xe này.')));
  }

  Future<void> _addManualBooking() async {
    if (bienSoCtrl.text.isEmpty || tenKhCtrl.text.isEmpty || sdtCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng nhập đủ Biển số, Tên KH và SĐT!'), backgroundColor: Colors.red));
      return;
    }
    setState(() => loading = true);
    try {
      await http.post(
        Uri.parse('${widget.login.baseUrl}/api/v1/bookings'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${widget.login.token}'},
        body: jsonEncode({
          'bien_so': bienSoCtrl.text.trim().toUpperCase(),
          'car_model': dongXeCtrl.text.trim(),
          'time': '${ngayHenCtrl.text} ${_formatHour(gioHenCtrl.text)}',
          'customer_name': tenKhCtrl.text.trim(),
          'customer_phone': sdtCtrl.text.trim(),
          'note': yeuCauCtrl.text.trim(),
          'status': 'Chờ tiếp nhận'
        })
      );
      
      DateTime? newlyAdded = _parseDate(ngayHenCtrl.text);
      if (newlyAdded != null) selectedBookingDate = newlyAdded;

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã thêm lịch hẹn thành công!'), backgroundColor: Colors.green));
      yeuCauCtrl.clear();
      await _loadData();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally { setState(() => loading = false); }
  }

  // --- HÀM IMPORT EXCEL ---
  Future<void> _importBookings() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'csv'],
        withData: true,
      );
      if (result != null) {
        setState(() => loading = true);
        final bytes = await bytesFromPickerFile(result.files.single);
        if (bytes == null) {
          setState(() => loading = false);
          return;
        }
        String ext = result.files.single.extension?.toLowerCase() ?? '';
        int count = 0;
        DateTime? jumpToDate;

        Future<void> processRow(List<dynamic> rawRow) async {
          if (rawRow.length >= 7) {
            String bs = _extractCellValue(rawRow[1]).toUpperCase();
            if (bs.isEmpty || bs.toLowerCase() == 'biển số xe') return;

            // Xử lý nắn thẳng mọi thể loại ngày
            String dateRaw = _normalizeDate(_extractCellValue(rawRow[3]));
            String hourFormatted = _formatHour(_extractCellValue(rawRow[4]));

            if (jumpToDate == null && dateRaw.isNotEmpty) jumpToDate = _parseDate(dateRaw);

            String note = '';
            if (rawRow.length > 7) note = rawRow.sublist(7).map((e) => _extractCellValue(e)).join(',').replaceAll('"', '').trim();

            final res = await http.post(
              Uri.parse('${widget.login.baseUrl}/api/v1/bookings'),
              headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${widget.login.token}'},
              body: jsonEncode({
                'bien_so': bs,
                'car_model': _extractCellValue(rawRow[2]),
                'time': '$dateRaw $hourFormatted'.trim(), 
                'customer_name': _extractCellValue(rawRow[5]),
                'customer_phone': _extractCellValue(rawRow[6]),
                'note': note,
                'status': 'Chờ tiếp nhận'
              })
            );
            if (res.statusCode == 200 || res.statusCode == 201) count++;
          }
        }

        if (ext == 'csv') {
          String content;
          try { content = utf8.decode(bytes, allowMalformed: true); } catch(e) { content = String.fromCharCodes(bytes); }
          List<String> lines = content.split(RegExp(r'\r?\n'));
          for (int i = 1; i < lines.length; i++) {
            if (lines[i].trim().isEmpty) continue;
            List<String> row = lines[i].split(',');
            await processRow(row);
          }
        } else {
          var excel = Excel.decodeBytes(bytes);
          for (var table in excel.tables.values) {
            for (int i = 1; i < table.rows.length; i++) {
              var row = table.rows[i].map((e) => e?.value).toList();
              await processRow(row);
            }
          }
        }

        if (jumpToDate != null) selectedBookingDate = jumpToDate!;
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Thành công! Đã nạp $count lịch hẹn.'), backgroundColor: Colors.green));
        await _loadData(showNotice: true);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi tải file: $e'), backgroundColor: Colors.red));
    } finally { setState(() => loading = false); }
  }

  Future<void> _assignCvdv() async {
    if (selectedOrder == null || selectedCvdv == null) return;
    setState(() => loading = true);
    try {
      await api.updateRepairOrder(token: widget.login.token, id: selectedOrder!.id, status: 'CHO_BAO_GIA', cvdvUsername: selectedCvdv!.username);
      setState(() { selectedOrder = null; selectedCvdv = null; });
      await _loadData();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Phân công thành công!'), backgroundColor: Colors.green));
    } catch (e) {
      debugPrint('Lỗi phân công: $e');
      if (mounted) {
        final msg = _friendlyAssignError(e);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  /// Chuỗi lỗi API ngắn gọn (JSON `{ "error": "..." }` hoặc HTML).
  String _friendlyAssignError(Object e) {
    final raw = e.toString();
    var inner = raw.startsWith('Exception:') ? raw.substring('Exception:'.length).trim() : raw;
    if (inner.startsWith('Exception:')) inner = inner.substring('Exception:'.length).trim();
    try {
      if (inner.startsWith('{')) {
        final j = jsonDecode(inner);
        if (j is Map && j['error'] != null) inner = j['error'].toString();
      }
    } catch (_) {}
    if (inner.contains('time_receive')) {
      return 'Máy chủ lỗi CSDL: thiếu cột «time_receive» trên bảng lệnh sửa chữa. '
          'Cần thêm cột trên PostgreSQL (hoặc sửa API bỏ tham chiếu cột này), sau đó thử phân công lại.';
    }
    if (inner.contains('<!DOCTYPE') || inner.contains('<html')) {
      return 'Máy chủ trả về lỗi HTML (không phải JSON). Kiểm tra URL API và log phía server.';
    }
    return inner.length > 260 ? '${inner.substring(0, 260)}…' : inner;
  }

  Future<void> _respondCskhBooking(LocalBooking b, bool accept) async {
    setState(() => loading = true);
    try {
      await api.updateBooking(
        token: widget.login.token,
        id: b.id,
        status: accept ? 'Chờ tiếp nhận' : 'CSKH từ chối hẹn',
        recreateOnMethodFailure: {
          'bien_so': b.bienSo.trim(),
          'car_model': b.carModel.trim(),
          'time': b.time.trim(),
          'customer_name': b.customerName.trim(),
          'customer_phone': b.customerPhone.trim(),
          'note': b.note.trim(),
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(accept ? 'Đã nhận lịch hẹn.' : 'Đã từ chối lịch hẹn.'),
            backgroundColor: accept ? Colors.green : Colors.orange,
          ),
        );
      }
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Widget _buildCskhFormColumn() {
    return Container(
      color: Colors.white,
      padding: appScreenPadding(context),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('THÊM LỊCH HẸN / KIỂM TRA', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
            const Divider(),
            const SizedBox(height: 8),
            TextField(controller: bienSoCtrl, decoration: InputDecoration(labelText: 'Biển số xe', border: const OutlineInputBorder(), suffixIcon: IconButton(onPressed: _kiemTraThongTin, icon: const Icon(Icons.search)))),
            const SizedBox(height: 12),
            TextField(controller: tenKhCtrl, decoration: const InputDecoration(labelText: 'Tên khách hàng', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: sdtCtrl, decoration: const InputDecoration(labelText: 'Số điện thoại', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: dongXeCtrl, decoration: const InputDecoration(labelText: 'Dòng xe', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: TextField(controller: ngayHenCtrl, readOnly: true, decoration: InputDecoration(labelText: 'Ngày hẹn', border: const OutlineInputBorder(), suffixIcon: IconButton(onPressed: () => _selectBookingDate(context, isForFilter: false), icon: const Icon(Icons.calendar_today))))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: gioHenCtrl, decoration: const InputDecoration(labelText: 'Giờ (VD: 8h00)', border: OutlineInputBorder()))),
              ],
            ),
            const SizedBox(height: 12),
            TextField(controller: yeuCauCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Yêu cầu khách', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, height: 48, child: FilledButton.icon(onPressed: loading ? null : _addManualBooking, icon: const Icon(Icons.add_task), label: const Text('THÊM LỊCH HẸN'))),
          ],
        ),
      ),
    );
  }

  Widget _buildCskhListsColumn() {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(
            labelColor: Colors.blue,
            unselectedLabelColor: Colors.grey,
            isScrollable: true,
            tabs: [
              Tab(text: 'XE CHỜ'),
              Tab(text: 'LỊCH HẸN'),
              Tab(text: 'BẢO DƯỠNG'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                ListView.builder(
                  itemCount: orders.where((o) => o.status == 'XE_VAO_XUONG').length,
                  itemBuilder: (ctx, i) {
                    final pending = orders.where((o) => o.status == 'XE_VAO_XUONG').toList();
                    final o = pending[i];
                    return ListTile(
                      selected: selectedOrder?.id == o.id,
                      title: Text(o.bienSo, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(o.customerName),
                      onTap: () => setState(() => selectedOrder = o),
                    );
                  },
                ),
                _buildBookingsList(),
                MaintenanceReminderPanel(api: api, token: widget.login.token),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookingsList() {
    final filteredBookings = bookings.where((b) {
      try {
        DateTime? bDate = _parseDate(b.time);
        if (bDate == null) return true;
        final today = DateTime.now();
        final t = DateTime(today.year, today.month, today.day);
        return t.difference(bDate).inDays < 1;
      } catch (_) {
        return true;
      }
    }).toList();

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          color: Colors.blue.shade50,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text('Lịch: ${DateFormat('dd/MM/yyyy').format(selectedBookingDate)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))),
              TextButton.icon(onPressed: () => _selectBookingDate(context), icon: const Icon(Icons.calendar_month), label: const Text('Ngày')),
            ],
          ),
        ),
        Expanded(
          child: filteredBookings.isEmpty
              ? const Center(child: Text('Không có lịch hẹn'))
              : ListView.separated(
                  itemCount: filteredBookings.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (ctx, i) {
                    final b = filteredBookings[i];
                    final pending = b.status == kBookingAwaitingCskh;
                    return ListTile(
                      title: Text('${b.time} — ${b.bienSo}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: Text('${b.customerName} · ${b.status}', maxLines: 3, overflow: TextOverflow.ellipsis),
                      trailing: pending
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(icon: const Icon(Icons.check_circle, color: Colors.green), onPressed: loading ? null : () => _respondCskhBooking(b, true)),
                                IconButton(icon: const Icon(Icons.cancel, color: Colors.red), onPressed: loading ? null : () => _respondCskhBooking(b, false)),
                              ],
                            )
                          : null,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCskhAssignColumn() {
    if (selectedOrder == null) {
      return const Center(child: Text('Chọn xe chờ phân công', textAlign: TextAlign.center));
    }
    return Container(
      padding: appScreenPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('PHÂN CÔNG: ${selectedOrder!.bienSo}', style: TextStyle(fontSize: appPanelTitleSize(context, desktop: 22), fontWeight: FontWeight.bold, color: Colors.blue)),
          Text('KH: ${selectedOrder!.customerName}'),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: loading
                ? null
                : () {
                    showDocumentExportSheet(
                      context: context,
                      api: api,
                      token: widget.login.token,
                      repairOrderId: selectedOrder!.id,
                      bienSo: selectedOrder!.bienSo,
                      onlyKeys: const ['phieu_tiep_nhan'],
                    );
                  },
            icon: const Icon(Icons.description_outlined),
            label: const Text('Xuất phiếu tiếp nhận'),
          ),
          const SizedBox(height: 16),
          const Text('CHỌN CVDV:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          DropdownButtonFormField<StaffUser>(
            value: selectedCvdv,
            isExpanded: true,
            decoration: const InputDecoration(border: OutlineInputBorder(), prefixIcon: Icon(Icons.person)),
            hint: Text(cvdvs.isEmpty ? 'Chưa có CVDV trên server' : 'Chọn CVDV...'),
            items: cvdvs
                .map((u) => DropdownMenuItem(
                      value: u,
                      child: Text('${u.fullName} (${_getWorkload(u.username)} xe)'),
                    ))
                .toList(),
            onChanged: cvdvs.isEmpty ? null : (v) => setState(() => selectedCvdv = v),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: (loading || selectedCvdv == null) ? null : _assignCvdv,
              icon: const Icon(Icons.send),
              label: const Text('XÁC NHẬN PHÂN CÔNG', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCskhPhoneBody(List<WorkOrderItem> pendingOrders) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          TabBar(
            labelColor: Colors.blue.shade800,
            tabs: [
              const Tab(text: 'Lịch hẹn'),
              Tab(text: 'Xe chờ (${pendingOrders.length})'),
              Tab(text: selectedOrder == null ? 'Phân công' : selectedOrder!.bienSo),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildCskhFormColumn(),
                _buildCskhListsColumn(),
                _buildCskhAssignColumn(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendingOrders = orders.where((o) => o.status == 'XE_VAO_XUONG').toList();
    
    final filteredBookings = bookings.where((b) {
      try {
        DateTime? bDate = _parseDate(b.time);
        if (bDate == null) return false;
        return bDate.day == selectedBookingDate.day && bDate.month == selectedBookingDate.month && bDate.year == selectedBookingDate.year;
      } catch (e) { return false; }
    }).toList()
      ..sort((a, b) {
        final pa = a.status == kBookingAwaitingCskh ? 0 : 1;
        final pb = b.status == kBookingAwaitingCskh ? 0 : 1;
        if (pa != pb) return pa.compareTo(pb);
        return a.time.compareTo(b.time);
      });

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text('CSKH - ĐIỀU PHỐI & LỊCH HẸN', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        actions: [
          const CompanyChatAppBarButton(),
          Center(child: Text('User: ${widget.login.userName}  ', style: const TextStyle(fontWeight: FontWeight.bold))),
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => _loadData()),
          IconButton(icon: const Icon(Icons.upload_file), onPressed: _importBookings, tooltip: 'Import Excel/CSV Lịch Hẹn'),
          IconButton(icon: const Icon(Icons.logout, color: Colors.red), onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()))),
          const SizedBox(width: 16)
        ],
      ),
      body: appIsPhone(context) ? _buildCskhPhoneBody(pendingOrders) : Row(
        children: [
          Container(
            width: 350, color: Colors.white, padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('THÊM LỊCH HẸN / KIỂM TRA', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                  const Divider(),
                  const SizedBox(height: 16),
                  TextField(controller: bienSoCtrl, decoration: InputDecoration(labelText: 'Biển số xe', border: const OutlineInputBorder(), suffixIcon: IconButton(onPressed: _kiemTraThongTin, icon: const Icon(Icons.search)))),
                  const SizedBox(height: 12),
                  TextField(controller: tenKhCtrl, decoration: const InputDecoration(labelText: 'Tên khách hàng', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(controller: sdtCtrl, decoration: const InputDecoration(labelText: 'Số điện thoại', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(controller: dongXeCtrl, decoration: const InputDecoration(labelText: 'Dòng xe', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: TextField(controller: ngayHenCtrl, readOnly: true, decoration: InputDecoration(labelText: 'Ngày hẹn', border: const OutlineInputBorder(), suffixIcon: IconButton(onPressed: () => _selectBookingDate(context, isForFilter: false), icon: const Icon(Icons.calendar_today))))),
                      const SizedBox(width: 8),
                      Expanded(child: TextField(controller: gioHenCtrl, decoration: const InputDecoration(labelText: 'Giờ (VD: 8h00)', border: OutlineInputBorder()))),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: yeuCauCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Yêu cầu khách', border: OutlineInputBorder())),
                  const SizedBox(height: 20),
                  SizedBox(width: double.infinity, height: 50, child: FilledButton.icon(onPressed: loading ? null : _addManualBooking, icon: const Icon(Icons.add_task), label: const Text('THÊM LỊCH HẸN MỚI'))),
                ],
              ),
            ),
          ),
          const VerticalDivider(width: 1),

          // --- CỘT 2: DANH SÁCH ---
          Expanded(
            flex: 2,
            child: DefaultTabController(
              length: 3,
              child: Column(
                children: [
                  const TabBar(
                    labelColor: Colors.blue,
                    unselectedLabelColor: Colors.grey,
                    tabs: [
                      Tab(text: 'XE ĐANG CHỜ'),
                      Tab(text: 'DANH SÁCH HẸN'),
                      Tab(text: 'NHẮC BẢO DƯỠNG'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        ListView.builder(
                          itemCount: pendingOrders.length,
                          itemBuilder: (ctx, i) => ListTile(
                            selected: selectedOrder?.id == pendingOrders[i].id,
                            selectedTileColor: Colors.blue.shade50,
                            leading: const Icon(Icons.directions_car, color: Colors.blueGrey),
                            title: Text(pendingOrders[i].bienSo, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('Khách: ${pendingOrders[i].customerName}'),
                            onTap: () => setState(() => selectedOrder = pendingOrders[i]),
                          ),
                        ),
                        Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8), color: Colors.blue.shade50,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Lịch hẹn: ${DateFormat('dd/MM/yyyy').format(selectedBookingDate)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                                  TextButton.icon(onPressed: () => _selectBookingDate(context), icon: const Icon(Icons.calendar_month), label: const Text('Lọc ngày'))
                                ],
                              ),
                            ),
                            Expanded(
                              child: filteredBookings.isEmpty 
                                ? const Center(child: Text('Không có lịch hẹn ngày này'))
                                : ListView.separated(
                                    itemCount: filteredBookings.length,
                                    separatorBuilder: (_, __) => const Divider(),
                                    itemBuilder: (ctx, i) {
                                      final b = filteredBookings[i];
                                      final pending = b.status == kBookingAwaitingCskh;
                                      return Material(
                                        color: pending ? Colors.orange.shade50 : Colors.transparent,
                                        child: ListTile(
                                          isThreeLine: true,
                                          leading: Icon(
                                            pending ? Icons.mark_email_unread : Icons.event_available,
                                            color: pending ? Colors.deepOrange : Colors.orange,
                                            size: 28,
                                          ),
                                          title: Text(
                                            '${b.time} — ${b.bienSo}',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: pending ? Colors.deepOrange.shade900 : Colors.red,
                                              fontSize: 14,
                                            ),
                                          ),
                                          subtitle: Text(
                                            'Xe: ${b.carModel} | KH: ${b.customerName} — ${b.customerPhone}\nYêu cầu: ${b.note}\nTrạng thái: ${b.status}',
                                            style: const TextStyle(fontSize: 12),
                                          ),
                                          trailing: pending
                                              ? Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    IconButton(
                                                      tooltip: 'Nhận hẹn',
                                                      icon: const Icon(Icons.check_circle, color: Colors.green),
                                                      onPressed: loading ? null : () => _respondCskhBooking(b, true),
                                                    ),
                                                    IconButton(
                                                      tooltip: 'Từ chối',
                                                      icon: const Icon(Icons.cancel, color: Colors.red),
                                                      onPressed: loading ? null : () => _respondCskhBooking(b, false),
                                                    ),
                                                  ],
                                                )
                                              : Padding(
                                                  padding: const EdgeInsets.only(left: 4),
                                                  child: Text(
                                                    b.status,
                                                    style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
                                                    textAlign: TextAlign.end,
                                                  ),
                                                ),
                                        ),
                                      );
                                    },
                                  ),
                            ),
                          ],
                        ),
                        MaintenanceReminderPanel(api: api, token: widget.login.token),
                      ],
                    ),
                  )
                ],
              ),
            ),
          ),
          const VerticalDivider(width: 1),

          // --- CỘT 3: PHÂN CÔNG ---
          Expanded(
            flex: 2,
            child: selectedOrder == null 
              ? const Center(child: Text('Chọn xe chờ phân công để tiếp tục'))
              : Container(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('PHÂN CÔNG XE: ${selectedOrder!.bienSo}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.blue)),
                      const SizedBox(height: 12),
                      Text('Khách hàng: ${selectedOrder!.customerName}'),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: loading
                            ? null
                            : () {
                                showDocumentExportSheet(
                                  context: context,
                                  api: api,
                                  token: widget.login.token,
                                  repairOrderId: selectedOrder!.id,
                                  bienSo: selectedOrder!.bienSo,
                                  onlyKeys: const ['phieu_tiep_nhan'],
                                );
                              },
                        icon: const Icon(Icons.description_outlined),
                        label: const Text('Xuất phiếu tiếp nhận xe (VF)'),
                      ),
                      const SizedBox(height: 24),
                      const Text('CHỌN CỐ VẤN DỊCH VỤ:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<StaffUser>(
                        value: selectedCvdv,
                        isExpanded: true,
                        decoration: const InputDecoration(border: OutlineInputBorder(), prefixIcon: Icon(Icons.person)),
                        hint: Text(cvdvs.isEmpty ? 'Chưa có CVDV — tạo tài khoản CVDV trên server' : 'Danh sách CVDV rảnh nhất...'),
                        items: cvdvs
                            .map((u) => DropdownMenuItem(
                                  value: u,
                                  child: Text('${u.fullName} (Đang nhận: ${_getWorkload(u.username)} xe)'),
                                ))
                            .toList(),
                        onChanged: cvdvs.isEmpty ? null : (v) => setState(() => selectedCvdv = v),
                      ),
                      const Spacer(),
                      SizedBox(width: double.infinity, height: 60, child: FilledButton.icon(onPressed: (loading || selectedCvdv == null) ? null : _assignCvdv, icon: const Icon(Icons.send), label: const Text('XÁC NHẬN PHÂN CÔNG', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)))),
                    ],
                  ),
                ),
          )
        ],
      ),
    );
  }
}