import 'package:flutter/material.dart';

import '../core/ro_display.dart';
import '../core/time_format.dart';
import '../models/auth_models.dart';
import '../services/api_service.dart';
import '../widgets/company_chat_host.dart';
import 'login_screen.dart';

class KtvScreen extends StatefulWidget {
  final LoginResult login;

  const KtvScreen({super.key, required this.login});

  @override
  State<KtvScreen> createState() => _KtvScreenState();
}

/// Xe không còn trong khu vực làm việc của KTV (đã ra xưởng / đã chuyển CVDV–KT…).
const Set<String> _ktvClosedStatuses = {
  'DA_RA_CONG',
  'DA_RA_CONG_THIEU_PT',
  'XE_RA_XUONG',
  'DA_THANH_TOAN',
  'HUY',
  'KT_DUYET_RA_CONG',
  // Quản đốc đã nghiệm thu → CVDV xử lý; KTV không còn việc trên xe.
  'CHO_CVDV_CHOT',
  'CHO_QUYET_TOAN',
  'HUY_CHO_QUYET_TOAN',
  'KH_TU_CHOI',
};

bool _assignedToKtv(WorkOrderItem o, String loginUsername) {
  final me = loginUsername.toLowerCase().trim();
  final ktv = o.ktvUsername.toLowerCase().trim();
  return ktv.isNotEmpty && ktv == me;
}

bool _visibleToKtv(WorkOrderItem o, String loginUsername) {
  if (!_assignedToKtv(o, loginUsername)) return false;
  return !_ktvClosedStatuses.contains(normalizeRepairOrderStatus(o.status));
}

const Set<String> _ktvDiagnosisStatuses = {
  'CHO_PHAN_CONG',
  'CHO_SUA_CHUA',
  'DANG_SUA',
  'DUNG_SUA',
  'CHO_PHU_TUNG',
};

const int _faultDiagnosisSlaMinutes = 4 * 60;

class _KtvScreenState extends State<KtvScreen> {
  late final ApiService api;
  bool isLoading = false;
  List<WorkOrderItem> myOrders = [];
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    api = ApiService(baseUrl: widget.login.baseUrl);
    _loadData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'CHO_PHAN_CONG':
        return 'Đã giao KTV — chờ bắt đầu';
      case 'CHO_SUA_CHUA':
        return 'Chờ KTV bắt đầu';
      case 'DANG_SUA':
        return 'Đang sửa chữa';
      case 'DUNG_SUA':
      case 'CHO_PHU_TUNG':
        return 'Tạm dừng / chờ phụ tùng';
      case 'CHO_QD_KIEM_TRA':
        return 'Chờ quản đốc nghiệm thu';
      case 'CHO_CVDV_CHOT':
        return 'Chờ CVDV chốt';
      case 'CHO_QUYET_TOAN':
        return 'Chờ quyết toán';
      default:
        return roStatusTokenLabelVi(status);
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'CHO_PHAN_CONG':
        return Colors.deepPurple;
      case 'CHO_SUA_CHUA':
        return Colors.purple;
      case 'DANG_SUA':
        return Colors.green;
      case 'DUNG_SUA':
      case 'CHO_PHU_TUNG':
        return Colors.orange;
      default:
        return Colors.blueGrey;
    }
  }

  List<WorkOrderItem> _filteredOrders() {
    final q = _searchCtrl.text.trim().toLowerCase().replaceAll(RegExp(r'[\s\-]'), '');
    if (q.isEmpty) return myOrders;
    return myOrders.where((o) {
      final hay = '${o.bienSo} ${o.roCode} ${o.cvdvWoCode} ${o.customerName} ${o.status}'
          .toLowerCase()
          .replaceAll(RegExp(r'[\s\-]'), '');
      return hay.contains(q);
    }).toList();
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    try {
      final allOrders = await api.fetchBoard(widget.login.token);
      final next = allOrders.where((o) => _visibleToKtv(o, widget.login.userName)).toList();
      if (!mounted) return;
      setState(() => myOrders = next);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi tải dữ liệu KTV: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _setOrderStatus(String orderId, String targetStatus, {String? pauseReason}) async {
    setState(() => isLoading = true);
    try {
      await api.updateRepairOrder(
        token: widget.login.token,
        id: orderId,
        status: targetStatus,
        pauseReason: pauseReason,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã cập nhật tiến độ xe thành công!'), backgroundColor: Colors.green),
        );
      }
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi cập nhật: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _confirmFaultDiagnosis(WorkOrderItem order) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận đã xác định nguyên nhân lỗi?'),
        content: const Text(
          'Chỉ bấm sau khi đã kết luận được hướng xử lý. Quản đốc sẽ không còn nhận cảnh báo quá hạn cho xe này.\n\n'
          'Nên mô tả ngắn trong «Cập nhật công việc» trước khi xác nhận.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Xác nhận')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => isLoading = true);
    try {
      await api.updateRepairOrder(
        token: widget.login.token,
        id: order.id,
        status: order.status,
        faultDiagnosisAtIso: DateTime.now().toUtc().toIso8601String(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã ghi nhận xác định nguyên nhân. Hệ thống sẽ không còn cảnh báo quá hạn cho xe này.'),
            backgroundColor: Colors.green,
          ),
        );
      }
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _patchVehicleActivity(WorkOrderItem order, String activity) async {
    setState(() => isLoading = true);
    try {
      await api.updateRepairOrder(
        token: widget.login.token,
        id: order.id,
        status: order.status,
        vehicleActivity: activity.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã cập nhật mô tả công việc trên xe.'), backgroundColor: Colors.green),
        );
      }
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showVehicleActivityDialog(WorkOrderItem order) {
    final ctrl = TextEditingController(text: order.vehicleActivityNote);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cập nhật công việc đang làm', style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Mô tả ngắn',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _patchVehicleActivity(order, ctrl.text);
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  void _showPauseDialog(String orderId) {
    final noteCtrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Báo dừng sửa chữa', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: noteCtrl,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Lý do tạm dừng', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
            onPressed: () {
              if (noteCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Bạn phải nhập lý do dừng sửa chữa!'), backgroundColor: Colors.red),
                );
                return;
              }
              Navigator.pop(ctx);
              _setOrderStatus(orderId, 'DUNG_SUA', pauseReason: noteCtrl.text.trim());
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Xác nhận dừng'),
          ),
        ],
      ),
    );
  }

  void _confirmHoanThanh(String orderId, String bienSo) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Báo hoàn thành sửa chữa?'),
        content: Text('Xe $bienSo sẽ chuyển sang chờ Quản đốc nghiệm thu (CHO_QD_KIEM_TRA).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _setOrderStatus(orderId, 'CHO_QD_KIEM_TRA');
            },
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
  }

  Widget _buildActionColumn(WorkOrderItem order) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (order.status == 'CHO_PHAN_CONG' ||
            order.status == 'CHO_SUA_CHUA' ||
            order.status == 'DUNG_SUA' ||
            order.status == 'CHO_PHU_TUNG')
          FilledButton.icon(
            onPressed: isLoading
                ? null
                : () {
                    if (order.status == 'CHO_PHAN_CONG') {
                      _setOrderStatus(order.id, 'CHO_SUA_CHUA');
                    } else {
                      _setOrderStatus(order.id, 'DANG_SUA');
                    }
                  },
            icon: const Icon(Icons.play_arrow),
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            label: Text(order.status == 'CHO_PHAN_CONG' ? 'NHẬN VIỆC' : (order.status == 'CHO_SUA_CHUA' ? 'BẮT ĐẦU SỬA' : 'TIẾP TỤC SỬA')),
          ),
        if (order.status == 'DANG_SUA') ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: isLoading ? null : () => _showPauseDialog(order.id),
            icon: const Icon(Icons.pause, color: Colors.orange),
            label: const Text('TẠM DỪNG', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: isLoading ? null : () => _confirmHoanThanh(order.id, order.bienSo),
            icon: const Icon(Icons.check_circle),
            style: FilledButton.styleFrom(backgroundColor: Colors.blue),
            label: const Text('BÁO HOÀN THÀNH'),
          ),
        ],
      ],
    );
  }

  Widget _buildOrderCard(WorkOrderItem order) {
    final statusColor = _getStatusColor(order.status);
    final woLine = order.cvdvWoCode.trim().isEmpty ? '—' : order.cvdvWoCode;
    final showDiagButton = order.faultDiagnosisAt == null && _ktvDiagnosisStatuses.contains(order.status);
    final diagOverSla = showDiagButton &&
        order.ktvInspectionElapsedMinutes != null &&
        order.ktvInspectionElapsedMinutes! >= _faultDiagnosisSlaMinutes;
    final inspectionStr = order.ktvInspectionElapsedMinutes != null
        ? formatDurationVnFromMinutes(order.ktvInspectionElapsedMinutes!)
        : '—';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: statusColor, width: 6)),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(order.bienSo, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(16)),
                  child: Text(
                    _statusLabel(order.status),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
                if (order.customerWaiting)
                  Chip(
                    label: const Text('Khách chờ tại xưởng', style: TextStyle(color: Colors.white)),
                    backgroundColor: Colors.red.shade700,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text('RO: ${order.roCode}  ·  WO: $woLine'),
            if (order.customerName.isNotEmpty) Text('Khách: ${order.customerName} · ${order.customerPhone}'),
            Text('CVDV: ${order.cvdvUsername}  ·  Vị trí: ${order.position.isEmpty ? "—" : order.position}'),
            Text(
              'Đang chờ: ${waitingBriefForStatus(order.status, customerWaiting: order.customerWaiting)}',
              style: TextStyle(color: Colors.deepPurple.shade800, fontWeight: FontWeight.w600),
            ),
            Text('Đã chờ: ${order.waitDisplayShort}', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
            Text('Thời gian KTV xử lý (từ giao việc/bắt đầu): $inspectionStr',
                style: TextStyle(color: Colors.blueGrey.shade800, fontSize: 13)),
            if (order.vehicleActivityNote.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Công việc: ${order.vehicleActivityNote}', style: TextStyle(color: Colors.indigo.shade800)),
              ),
            if (order.customerNote.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Ghi chú: ${order.customerNote}', style: TextStyle(color: Colors.red.shade800)),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: isLoading ? null : () => _showVehicleActivityDialog(order),
              icon: const Icon(Icons.edit_note),
              label: const Text('Cập nhật công việc'),
            ),
            if (showDiagButton) ...[
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: isLoading ? null : () => _confirmFaultDiagnosis(order),
                icon: const Icon(Icons.fact_check_outlined),
                style: FilledButton.styleFrom(
                  backgroundColor: diagOverSla ? Colors.deepOrange : Colors.indigo,
                ),
                label: const Text('Đã xác định nguyên nhân lỗi'),
              ),
            ],
            const SizedBox(height: 8),
            _buildActionColumn(order),
          ],
        ),
      ),
    );
  }

  Widget _buildBodyList(List<WorkOrderItem> visible) {
    if (isLoading && myOrders.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (myOrders.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Chưa có xe nào được giao cho bạn.\nQuản đốc cần phân công KTV trên phiếu.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ),
      );
    }
    if (visible.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Không tìm thấy xe khớp «${_searchCtrl.text}».',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: visible.length,
      itemBuilder: (_, i) => _buildOrderCard(visible[i]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _filteredOrders();

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text('KỸ THUẬT VIÊN — Khu vực sửa chữa', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blueGrey,
        foregroundColor: Colors.white,
        actions: [
          const CompanyChatAppBarButton(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Center(
              child: Text(
                'KTV: ${widget.login.userName}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: isLoading ? null : _loadData),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Icon(Icons.build, color: Color(0xFF1E293B)),
                  const Text('Xe được giao cho bạn', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  Chip(
                    label: Text(
                      visible.length == myOrders.length
                          ? 'Tổng: ${myOrders.length} xe'
                          : 'Hiển thị ${visible.length} / ${myOrders.length} xe',
                    ),
                    backgroundColor: Colors.blue.shade100,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Tìm biển số, RO, WO…',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchCtrl.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() {});
                          },
                        ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: _buildBodyList(visible)),
          ],
        ),
      ),
    );
  }
}
