import 'package:flutter/material.dart';

import '../core/parts_fulfillment.dart';
import '../core/ro_display.dart';
import '../core/time_format.dart';
import '../models/auth_models.dart';
import '../services/api_service.dart';
import '../widgets/column_filter_menu_header.dart';
import '../widgets/company_chat_host.dart';
import '../widgets/responsive_shell.dart';
import '../core/responsive_layout.dart';
import 'login_screen.dart';

class QuanDocScreen extends StatefulWidget {
  final LoginResult login;
  const QuanDocScreen({super.key, required this.login});

  @override
  State<QuanDocScreen> createState() => _QuanDocScreenState();
}

class _QuanDocScreenState extends State<QuanDocScreen> {
  late final ApiService api;
  bool isLoading = false;
  List<WorkOrderItem> pendingOrders = [];
  List<WorkOrderItem> inProgressOrders = [];
  List<UserItem> ktvList = [];
  Map<String, String?> selectedKtvs = {};
  List<Map<String, dynamic>> _serverNotifs = [];
  int _unreadNotifCount = 0;

  /// Cùng quy ước bảng điều phối Giám đốc: lọc theo từng trường (menu tam giác).
  static const List<MapEntry<String, String>> _qdFilterCols = [
    MapEntry('bienSo', 'Biển số'),
    MapEntry('roCode', 'Mã RO'),
    MapEntry('woCode', 'Mã WO (CVDV)'),
    MapEntry('customer', 'Khách hàng'),
    MapEntry('phone', 'SĐT'),
    MapEntry('cvdv', 'CVDV'),
    MapEntry('ktv', 'KTV'),
    MapEntry('position', 'Vị trí xe'),
    MapEntry('waiting', 'Đang chờ'),
    MapEntry('waited', 'Đã chờ'),
    MapEntry('status', 'Mã trạng thái'),
  ];

  final Map<String, TextEditingController> _pendingCol = {};
  final Map<String, TextEditingController> _progressCol = {};

  @override
  void initState() {
    super.initState();
    for (final e in _qdFilterCols) {
      _pendingCol[e.key] = TextEditingController();
      _progressCol[e.key] = TextEditingController();
    }
    api = ApiService(baseUrl: widget.login.baseUrl);
    _loadData();
  }

  @override
  void dispose() {
    for (final e in _qdFilterCols) {
      _pendingCol[e.key]?.dispose();
      _progressCol[e.key]?.dispose();
    }
    super.dispose();
  }

  Widget _filterHdr(Map<String, TextEditingController> m, String key, String title) {
    return ColumnFilterMenuHeader(
      title: title,
      filterController: m[key]!,
      onFiltersChanged: () => setState(() {}),
    );
  }

  List<String> _orderCells(WorkOrderItem o) {
    final wo = o.cvdvWoCode.trim().isEmpty ? '—' : o.cvdvWoCode;
    final ktv = o.ktvUsername.trim().isEmpty ? '—' : o.ktvUsername;
    return [
      o.bienSo,
      o.roCode,
      wo,
      o.customerName,
      o.customerPhone,
      o.cvdvUsername,
      ktv,
      o.position,
      waitingBriefForStatus(o.status, customerWaiting: o.customerWaiting),
      o.waitDisplayShort,
      o.status,
    ];
  }

  List<WorkOrderItem> _pipelinePending() {
    final filters = _qdFilterCols.map((e) => _pendingCol[e.key]!.text).toList();
    return pendingOrders.where((o) => cellsMatchFilters(filters, _orderCells(o))).toList();
  }

  List<WorkOrderItem> _pipelineProgress() {
    final filters = _qdFilterCols.map((e) => _progressCol[e.key]!.text).toList();
    return inProgressOrders.where((o) => cellsMatchFilters(filters, _orderCells(o))).toList();
  }

  Widget _filterStrip(Map<String, TextEditingController> m) {
    return Material(
      color: const Color(0xFFF8FAFC),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            for (final e in _qdFilterCols)
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: _filterHdr(m, e.key, e.value),
              ),
          ],
        ),
      ),
    );
  }

  List<UserItem> _ktvFallbackFromOrders(List<WorkOrderItem> orders) {
    final names = <String>{};
    for (final o in orders) {
      final u = o.ktvUsername.trim();
      if (u.isNotEmpty) names.add(u);
    }
    return names
        .map(
          (u) => UserItem(
            id: u,
            username: u,
            fullName: u,
            role: 'KTV',
            isActive: true,
          ),
        )
        .toList();
  }

  Future<void> _loadData() async {
    setState(() {
      isLoading = true;
    });
    Object? boardErr;
    try {
      final allOrders = await api.fetchBoard(widget.login.token);
      List<UserItem> ktvs = [];
      try {
        ktvs = await api.fetchAssignableKtv(widget.login.token);
      } catch (_) {
        ktvs = _ktvFallbackFromOrders(allOrders);
      }
      List<Map<String, dynamic>> notifs = [];
      try {
        notifs = await api.fetchNotifications(widget.login.token);
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        ktvList = ktvs;
        pendingOrders = allOrders.where((o) => o.status == 'CHO_PHAN_CONG').toList();
        inProgressOrders = allOrders.where((o) =>
            o.status == 'CHO_SUA_CHUA' ||
            o.status == 'DANG_SUA' ||
            o.status == 'DUNG_SUA' ||
            o.status == 'CHO_QD_KIEM_TRA').toList();
        _serverNotifs = notifs;
        _unreadNotifCount = notifs.where(notificationIsUnread).length;
      });
    } catch (e) {
      boardErr = e;
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
        if (boardErr != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi tải bảng xe: $boardErr'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _assignJobToKtv(String orderId, String bienSo) async {
    final selectedKtvUsername = selectedKtvs[orderId];
    if (selectedKtvUsername == null || selectedKtvUsername.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng chọn Kỹ Thuật Viên!'), backgroundColor: Colors.red));
      return;
    }
    setState(() {
      isLoading = true;
    });
    try {
      await api.updateRepairOrder(token: widget.login.token, id: orderId, status: 'CHO_SUA_CHUA', ktvUsername: selectedKtvUsername);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã phân công xe $bienSo cho KTV: $selectedKtvUsername'), backgroundColor: Colors.green));
      }
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi giao việc: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> _approveQuality(String orderId) async {
    setState(() {
      isLoading = true;
    });
    try {
      await api.updateRepairOrder(token: widget.login.token, id: orderId, status: 'CHO_CVDV_CHOT');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nghiệm thu OK! Đã chuyển CVDV chốt vật tư.'), backgroundColor: Colors.green));
      }
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> _showQdNotificationsDialog() async {
    List<Map<String, dynamic>> list = List<Map<String, dynamic>>.from(_serverNotifs);
    try {
      list = await api.fetchNotifications(widget.login.token);
    } catch (_) {}

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thông báo', style: TextStyle(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 480,
          height: 400,
          child: list.isEmpty
              ? const Center(child: Text('Không có thông báo.', style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final n = list[i];
                    final unread = notificationIsUnread(n);
                    final isDiag = notificationDataType(n) == 'KTV_DIAGNOSIS_OVERDUE';
                    return ListTile(
                      dense: true,
                      tileColor: unread && isDiag ? Colors.deepOrange.shade50 : null,
                      leading: Icon(
                        isDiag ? Icons.engineering_outlined : Icons.notifications,
                        color: isDiag ? Colors.deepOrange : Colors.blueGrey,
                      ),
                      title: Text(
                        n['title']?.toString() ?? '',
                        style: TextStyle(fontWeight: unread ? FontWeight.bold : FontWeight.w500),
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
                          n['read_at'] = DateTime.now().toIso8601String();
                          setState(() {
                            _serverNotifs = list;
                            _unreadNotifCount = list.where(notificationIsUnread).length;
                          });
                        }
                      },
                    );
                  },
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng'))],
      ),
    );

    if (mounted) {
      setState(() {
        _serverNotifs = list;
        _unreadNotifCount = list.where(notificationIsUnread).length;
      });
    }
  }

  /// Thời gian tổng từ khi vào hệ thống (bổ sung cho rule “đã ở xưởng”).
  String _timeSinceCreated(DateTime? timeIn) => formatWaitSinceDateTime(timeIn, ifNull: 'Chưa có thông tin');

  Color _getStatusColor(String status) {
    switch (status) {
      case 'CHO_SUA_CHUA':
        return Colors.purple;
      case 'DANG_SUA':
        return Colors.green;
      case 'DUNG_SUA':
        return Colors.orange;
      case 'CHO_QD_KIEM_TRA':
        return Colors.blue;
      default:
        return Colors.blueGrey;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'CHO_SUA_CHUA':
        return 'Mới giao - KTV chưa bắt đầu';
      case 'DANG_SUA':
        return 'KTV đang tiến hành sửa';
      case 'DUNG_SUA':
        return 'KTV báo Tạm Dừng';
      case 'CHO_QD_KIEM_TRA':
        return 'KTV BÁO XONG - CẦN NGHIỆM THU';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: Text(compactAppBarTitle(context, 'QUẢN ĐỐC — Điều phối'), style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          const CompanyChatAppBarButton(),
          Center(child: Text('User: ${widget.login.userName}  ', style: const TextStyle(fontWeight: FontWeight.bold))),
          IconButton(
            tooltip: 'Thông báo',
            icon: Badge(
              isLabelVisible: _unreadNotifCount > 0,
              label: Text(_unreadNotifCount > 99 ? '99+' : '$_unreadNotifCount'),
              child: const Icon(Icons.notifications_outlined),
            ),
            onPressed: isLoading ? null : _showQdNotificationsDialog,
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: isLoading ? null : _loadData),
          IconButton(
              icon: const Icon(Icons.logout, color: Colors.redAccent),
              onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()))),
          const SizedBox(width: 16)
        ],
      ),
      body: isLoading && pendingOrders.isEmpty && inProgressOrders.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                ResponsiveTwoColumns(
                  first: Container(
                        margin: EdgeInsets.all(appIsPhone(context) ? 8 : 16),
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))]),
                        child: Column(
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: const BoxDecoration(
                                  color: Color(0xFFFEF2F2), borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
                              child: Row(children: [
                                const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
                                const SizedBox(width: 12),
                                Text('CẦN GIAO VIỆC (${pendingOrders.length})',
                                    style: TextStyle(fontSize: appPanelTitleSize(context, desktop: 20), fontWeight: FontWeight.bold, color: Colors.red))
                              ]),
                            ),
                            _filterStrip(_pendingCol),
                            Expanded(
                              child: Builder(
                                builder: (context) {
                                  final rows = _pipelinePending();
                                  if (pendingOrders.isEmpty) {
                                    return const Center(
                                        child: Text('Không có xe nào đang chờ phân công.', style: TextStyle(color: Colors.grey, fontSize: 16)));
                                  }
                                  if (rows.isEmpty) {
                                    return Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(24),
                                        child: Text(
                                          'Không có dòng khớp lọc cột. Mở menu tam giác trên từng tiêu đề → «Xóa lọc cột» để xem lại.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
                                        ),
                                      ),
                                    );
                                  }
                                  return ListView.separated(
                                    padding: const EdgeInsets.all(16),
                                    itemCount: rows.length,
                                    separatorBuilder: (_, __) => const Divider(height: 32),
                                    itemBuilder: (context, index) {
                                      final order = rows[index];
                                      final timeInShop = _timeSinceCreated(order.createdAt);
                                      final woLine = order.cvdvWoCode.trim().isEmpty ? '—' : order.cvdvWoCode;

                                      return Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                            color: const Color(0xFFF8FAFC),
                                            border: Border.all(color: Colors.indigo.withOpacity(0.2)),
                                            borderRadius: BorderRadius.circular(12)),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Text(order.bienSo,
                                                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.indigo)),
                                                  Chip(label: Text('CVDV: ${order.cvdvUsername}'), backgroundColor: Colors.blue.shade50)
                                                ]),
                                            const SizedBox(height: 6),
                                            Text('Mã RO: ${order.roCode}', style: const TextStyle(fontWeight: FontWeight.w600)),
                                            Text('Mã WO (CVDV): $woLine', style: TextStyle(color: Colors.blueGrey.shade700)),
                                            if (order.customerName.isNotEmpty)
                                              Text('Khách: ${order.customerName}  ·  ${order.customerPhone}', style: const TextStyle(fontSize: 13)),
                                            if (order.vehicleActivityNote.trim().isNotEmpty) ...[
                                              const SizedBox(height: 6),
                                              Text('Ghi chú xe / công việc: ${order.vehicleActivityNote}',
                                                  style: TextStyle(color: Colors.indigo.shade800, fontWeight: FontWeight.w500)),
                                            ],
                                            const SizedBox(height: 8),
                                            Row(children: [
                                              Icon(Icons.hourglass_top, size: 16, color: Colors.deepPurple.shade700),
                                              const SizedBox(width: 4),
                                              Expanded(
                                                  child: Text(
                                                      'Đang chờ: ${waitingBriefForStatus(order.status, customerWaiting: order.customerWaiting)}',
                                                      style: TextStyle(color: Colors.deepPurple.shade800, fontWeight: FontWeight.w600))),
                                            ]),
                                            const SizedBox(height: 4),
                                            Row(children: [
                                              const Icon(Icons.timer_outlined, size: 16, color: Colors.redAccent),
                                              const SizedBox(width: 4),
                                              Text('Đã chờ (trạng thái hiện tại): ${order.waitDisplayShort}',
                                                  style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                                            ]),
                                            const SizedBox(height: 4),
                                            Row(children: [
                                              const Icon(Icons.access_time, size: 16, color: Colors.black54),
                                              const SizedBox(width: 4),
                                              Text('Tổng thời gian tại xưởng (ước lượng): $timeInShop', style: const TextStyle(color: Colors.black87)),
                                            ]),
                                            const SizedBox(height: 4),
                                            Row(children: [
                                              const Icon(Icons.location_on, size: 16, color: Colors.grey),
                                              const SizedBox(width: 4),
                                              Expanded(child: Text('Vị trí xe: ${order.position}', style: const TextStyle(color: Colors.black87))),
                                            ]),
                                            if (order.customerNote.isNotEmpty) ...[
                                              const SizedBox(height: 8),
                                              Text('Ghi chú CVDV: ${order.customerNote}', style: const TextStyle(color: Colors.red, fontStyle: FontStyle.italic)),
                                            ],
                                            const SizedBox(height: 20),
                                            const Text('Chỉ định Kỹ Thuật Viên phụ trách:', style: TextStyle(fontWeight: FontWeight.bold)),
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: DropdownButtonFormField<String>(
                                                    value: selectedKtvs[order.id],
                                                    hint: const Text('Bấm để chọn KTV...'),
                                                    decoration: InputDecoration(
                                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                                        filled: true,
                                                        fillColor: Colors.white),
                                                    items: ktvList
                                                        .map((ktv) => DropdownMenuItem<String>(
                                                            value: ktv.username, child: Text('${ktv.fullName} (Mã: ${ktv.username})')))
                                                        .toList(),
                                                    onChanged: (value) => setState(() => selectedKtvs[order.id] = value),
                                                  ),
                                                ),
                                                const SizedBox(width: 16),
                                                FilledButton.icon(
                                                    onPressed: () => _assignJobToKtv(order.id, order.bienSo),
                                                    icon: const Icon(Icons.handyman),
                                                    label: const Text('GIAO VIỆC', style: TextStyle(fontWeight: FontWeight.bold)),
                                                    style: FilledButton.styleFrom(
                                                        backgroundColor: Colors.indigo,
                                                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))))
                                              ],
                                            )
                                          ],
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                  second: Container(
                        margin: EdgeInsets.fromLTRB(
                          appIsPhone(context) ? 8 : 0,
                          appIsPhone(context) ? 8 : 16,
                          appIsPhone(context) ? 8 : 16,
                          appIsPhone(context) ? 8 : 16,
                        ),
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))]),
                        child: Column(
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: const BoxDecoration(
                                  color: Color(0xFFF0FDF4), borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
                              child: Row(children: [
                                const Icon(Icons.build_circle, color: Colors.green, size: 28),
                                const SizedBox(width: 12),
                                Text('ĐANG SỬA (${inProgressOrders.length})',
                                    style: TextStyle(fontSize: appPanelTitleSize(context, desktop: 20), fontWeight: FontWeight.bold, color: Colors.green))
                              ]),
                            ),
                            _filterStrip(_progressCol),
                            Expanded(
                              child: Builder(
                                builder: (context) {
                                  final rows = _pipelineProgress();
                                  if (inProgressOrders.isEmpty) {
                                    return const Center(
                                        child: Text('Không có xe nào đang sửa.', style: TextStyle(color: Colors.grey, fontSize: 16)));
                                  }
                                  if (rows.isEmpty) {
                                    return Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(24),
                                        child: Text(
                                          'Không có dòng khớp lọc cột. Mở menu tam giác trên từng tiêu đề → «Xóa lọc cột» để xem lại.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
                                        ),
                                      ),
                                    );
                                  }
                                  return ListView.separated(
                                    padding: const EdgeInsets.all(16),
                                    itemCount: rows.length,
                                    separatorBuilder: (_, __) => const Divider(height: 24),
                                    itemBuilder: (context, index) {
                                      final order = rows[index];
                                      final statusColor = _getStatusColor(order.status);
                                      final timeInShop = _timeSinceCreated(order.createdAt);
                                      final woLine = order.cvdvWoCode.trim().isEmpty ? '—' : order.cvdvWoCode;

                                      return Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                            color: Colors.white,
                                            border: Border(left: BorderSide(color: statusColor, width: 6)),
                                            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))]),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Text(order.bienSo, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                                                  Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                      decoration:
                                                          BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                                                      child: Text(_getStatusText(order.status),
                                                          style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12)))
                                                ]),
                                            const SizedBox(height: 8),
                                            Text('Mã RO: ${order.roCode}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                            Text('Mã WO (CVDV): $woLine', style: TextStyle(color: Colors.blueGrey.shade700, fontSize: 13)),
                                            if (order.customerName.isNotEmpty)
                                              Text('Khách: ${order.customerName}', style: const TextStyle(fontSize: 13)),
                                            if (order.vehicleActivityNote.trim().isNotEmpty) ...[
                                              const SizedBox(height: 6),
                                              Text('Ghi chú xe / công việc: ${order.vehicleActivityNote}',
                                                  style: TextStyle(color: Colors.indigo.shade800, fontWeight: FontWeight.w500, fontSize: 13)),
                                            ],
                                            const SizedBox(height: 6),
                                            Row(children: [
                                              Icon(Icons.hourglass_top, size: 16, color: Colors.deepPurple.shade700),
                                              const SizedBox(width: 4),
                                              Expanded(
                                                  child: Text(
                                                      'Đang chờ: ${waitingBriefForStatus(order.status, customerWaiting: order.customerWaiting)}',
                                                      style: TextStyle(fontSize: 13, color: Colors.deepPurple.shade800, fontWeight: FontWeight.w600))),
                                            ]),
                                            const SizedBox(height: 4),
                                            Row(children: [
                                              const Icon(Icons.timer_outlined, size: 16, color: Colors.orange),
                                              const SizedBox(width: 4),
                                              Text('Đã chờ (trạng thái hiện tại): ${order.waitDisplayShort}',
                                                  style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 13)),
                                            ]),
                                            const SizedBox(height: 4),
                                            Row(children: [
                                              const Icon(Icons.access_time, size: 16, color: Colors.black54),
                                              const SizedBox(width: 4),
                                              Expanded(
                                                  child: Text('Tổng thời gian tại xưởng: $timeInShop',
                                                      style: const TextStyle(color: Colors.black87, fontSize: 13))),
                                            ]),
                                            const SizedBox(height: 4),
                                            Row(children: [
                                              const Icon(Icons.person, size: 16, color: Colors.indigo),
                                              const SizedBox(width: 4),
                                              Text('KTV: ${order.ktvUsername.isEmpty ? "—" : order.ktvUsername}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                            ]),
                                            const SizedBox(height: 4),
                                            Row(children: [
                                              const Icon(Icons.support_agent, size: 16, color: Colors.blue),
                                              const SizedBox(width: 4),
                                              Text('CVDV: ${order.cvdvUsername}', style: const TextStyle(color: Colors.grey)),
                                            ]),
                                            if (order.status == 'DUNG_SUA') ...[
                                              const SizedBox(height: 8),
                                              Container(
                                                  width: double.infinity,
                                                  padding: const EdgeInsets.all(8),
                                                  decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
                                                  child: Text('Lý do dừng / ghi chú: ${order.customerNote}',
                                                      style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold))),
                                            ],
                                            if (order.status == 'CHO_QD_KIEM_TRA') ...[
                                              const SizedBox(height: 12),
                                              SizedBox(
                                                width: double.infinity,
                                                child: FilledButton.icon(
                                                  onPressed: isLoading ? null : () => _approveQuality(order.id),
                                                  icon: const Icon(Icons.verified),
                                                  label: const Text('NGHIỆM THU -> BÁO CVDV'),
                                                  style: FilledButton.styleFrom(backgroundColor: Colors.blue),
                                                ),
                                              ),
                                            ]
                                          ],
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                ),
                if (isLoading && (pendingOrders.isNotEmpty || inProgressOrders.isNotEmpty))
                  const Positioned.fill(
                    child: IgnorePointer(
                      child: ModalBarrier(dismissible: false, color: Color(0x11000000)),
                    ),
                  ),
                if (isLoading && (pendingOrders.isNotEmpty || inProgressOrders.isNotEmpty))
                  const Center(child: CircularProgressIndicator()),
              ],
            ),
    );
  }
}
