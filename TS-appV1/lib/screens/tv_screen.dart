import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/constants.dart';
import '../core/ro_display.dart';
import '../core/time_format.dart';
import '../core/tv_board_sort.dart';
import '../models/auth_models.dart';
import '../services/api_service.dart';
import '../widgets/company_chat_host.dart';
import 'login_screen.dart';

/// Đồng hồ chạy mỗi giây **chỉ rebuild chính nó** — tránh `setState` cả màn TV (ListView + hàng chục dòng).
class _TvHeaderClock extends StatefulWidget {
  final double fontSize;

  const _TvHeaderClock({required this.fontSize});

  @override
  State<_TvHeaderClock> createState() => _TvHeaderClockState();
}

class _TvHeaderClockState extends State<_TvHeaderClock> {
  Timer? _timer;
  late String _text;

  @override
  void initState() {
    super.initState();
    _text = DateFormat('HH:mm:ss  |  dd/MM/yyyy').format(DateTime.now());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _text = DateFormat('HH:mm:ss  |  dd/MM/yyyy').format(DateTime.now());
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _text,
      style: TextStyle(
        color: Colors.white,
        fontSize: widget.fontSize,
        fontWeight: FontWeight.bold,
        fontFamily: 'Courier',
      ),
    );
  }
}

class TvDashboardScreen extends StatefulWidget {
  final LoginResult login;

  const TvDashboardScreen({super.key, required this.login});

  @override
  State<TvDashboardScreen> createState() => _TvDashboardScreenState();
}

class _TvDashboardScreenState extends State<TvDashboardScreen> {
  late final ApiService api;
  List<WorkOrderItem> activeOrders = [];
  Timer? _refreshTimer;
  bool _isFetching = false;
  String? _lastError;
  DateTime? _lastSyncOk;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  /// Xe không còn hiển thị trên bảng xưởng (đã ra hoặc kết thúc luồng trong xưởng).
  static const Set<String> _excludedStatuses = {
    'DA_RA_CONG',
    'XE_RA_XUONG',
    'KH_TU_CHOI',
  };

  @override
  void initState() {
    super.initState();
    api = ApiService(baseUrl: widget.login.baseUrl);
    _loadData();
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) => _loadData());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _exitToLogin() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  List<WorkOrderItem> get _displayOrders {
    return filterTvBoardSearch(activeOrders, _searchQuery);
  }

  Future<void> _loadData() async {
    if (_isFetching) return;
    if (mounted) setState(() => _isFetching = true);
    try {
      final allOrders = await api.fetchBoard(widget.login.token);
      if (!mounted) return;

      final next = allOrders.where((o) => !_excludedStatuses.contains(o.status)).toList();
      sortTvBoardOrders(next);

      setState(() {
        _isFetching = false;
        _lastError = null;
        _lastSyncOk = DateTime.now();
        activeOrders = next;
      });
    } catch (e) {
      debugPrint('Lỗi tải dữ liệu màn hình TV: $e');
      if (mounted) {
        setState(() {
          _isFetching = false;
          _lastError = e.toString();
        });
      }
    }
  }

  /// Màu cột “thời gian chờ” theo SLA (phút trong trạng thái hiện tại).
  Color _waitAccent(WorkOrderItem o) {
    final m = o.minutesInState;
    if (m == null) return Colors.amberAccent;
    int? limit;
    switch (o.status) {
      case 'CHO_BAO_GIA':
        limit = SlaRules.timeToQuote;
        break;
      case 'CHO_PHAN_CONG':
        limit = SlaRules.timeToAssign;
        break;
      case 'CHO_SUA_CHUA':
        limit = SlaRules.timeToStartRepair;
        break;
      case 'CHO_QUYET_TOAN':
        limit = SlaRules.timeToSettle;
        break;
      case 'DA_THANH_TOAN':
        limit = SlaRules.timeToExit;
        break;
      default:
        return Colors.amberAccent;
    }
    if (m >= limit * 2) return AppColors.statusDanger;
    if (m >= limit) return AppColors.statusWarning;
    return Colors.amberAccent;
  }

  Map<String, dynamic> _getFriendlyStatus(String status) {
    switch (status) {
      case 'XE_VAO_XUONG':
        return {'text': 'MỚI TIẾP NHẬN', 'color': Colors.blueAccent, 'icon': Icons.login};
      case 'CHO_BAO_GIA':
        return {'text': 'ĐANG KIỂM TRA', 'color': Colors.orangeAccent, 'icon': Icons.search};
      case 'CHO_KH_DUYET':
        return {'text': 'CHỜ KHÁCH DUYỆT', 'color': Colors.redAccent, 'icon': Icons.touch_app};
      case 'CHO_PHAN_CONG':
      case 'CHO_SUA_CHUA':
        return {'text': 'CHỜ SỬA CHỮA', 'color': Colors.purpleAccent, 'icon': Icons.hourglass_empty};
      case 'DANG_SUA':
        return {'text': 'ĐANG SỬA CHỮA', 'color': Colors.greenAccent, 'icon': Icons.build_circle};
      case 'CHO_QD_KIEM_TRA':
        return {'text': 'CHỜ NGHIỆM THU', 'color': Colors.cyanAccent, 'icon': Icons.fact_check};
      case 'DUNG_SUA':
      case 'CHO_PHU_TUNG':
        return {'text': 'TẠM DỪNG / CHỜ PHỤ TÙNG', 'color': Colors.deepOrangeAccent, 'icon': Icons.pause_circle_filled};
      case 'CHO_CVDV_CHOT':
        return {'text': 'CHỜ CVDV CHỐT VẬT TƯ', 'color': Colors.amberAccent, 'icon': Icons.handshake};
      case 'CHO_QUYET_TOAN':
      case 'DA_THANH_TOAN':
        return {'text': 'HOÀN THÀNH - CHỜ GIAO', 'color': Colors.tealAccent, 'icon': Icons.check_circle};
      case 'HUY_CHO_QUYET_TOAN':
        return {'text': 'ĐÃ HỦY - CHỜ KẾ TOÁN', 'color': Colors.deepPurpleAccent, 'icon': Icons.cancel_schedule_send};
      case 'KT_DUYET_RA_CONG':
        return {'text': 'ĐƯỢC PHÉP RA CỔNG', 'color': Colors.lightBlueAccent, 'icon': Icons.logout};
      case 'DA_RA_CONG_THIEU_PT':
        return {'text': 'RA CỔNG (THIẾU PT)', 'color': Colors.limeAccent, 'icon': Icons.warning_amber};
      default:
        return {'text': 'ĐANG XỬ LÝ', 'color': Colors.white70, 'icon': Icons.sync};
    }
  }

  String _maskLicensePlate(String bienSo) {
    if (bienSo.length < 6) return bienSo;
    return bienSo.replaceRange(bienSo.length - 3, bienSo.length, '***');
  }

  String _syncLabel() {
    if (_lastSyncOk == null) return 'Chưa đồng bộ';
    final t = DateFormat('HH:mm:ss').format(_lastSyncOk!);
    return 'Cập nhật $t';
  }

  Widget _errorBanner() {
    if (_lastError == null) return const SizedBox.shrink();
    return Material(
      color: Colors.red.shade900.withOpacity(0.9),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.cloud_off, color: Colors.white, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Lỗi tải dữ liệu: $_lastError',
                style: const TextStyle(color: Colors.white, fontSize: 15),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tableHeader(double minW) {
    TextStyle th() => TextStyle(color: Colors.grey.shade400, fontSize: math.min(20, minW * 0.014), fontWeight: FontWeight.bold);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
      color: const Color(0xFF0F172A),
      child: SizedBox(
        width: minW,
        child: Row(
          children: [
            Expanded(flex: 1, child: Text('STT', style: th())),
            Expanded(flex: 3, child: Text('BIỂN SỐ XE', style: th())),
            Expanded(flex: 2, child: Text('CVDV', style: th())),
            Expanded(flex: 2, child: Text('KTV', style: th())),
            Expanded(flex: 3, child: Text('VỊ TRÍ / KHU VỰC', style: th())),
            Expanded(flex: 2, child: Text('THỜI GIAN CHỜ', style: th())),
            Expanded(flex: 4, child: Text('TRẠNG THÁI', style: th())),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(WorkOrderItem order, int index, double minW) {
    final rank = tvRankOrder(order);
    final statusMeta = _getFriendlyStatus(order.status);
    final tier = rank.tier;
    final accent = tier.color;
    final waitColor = rank.slaOverdueMinutes > 0 ? AppColors.statusDanger : _waitAccent(order);
    final fs = math.min(22.0, minW * 0.016);
    final fsLarge = math.min(30.0, minW * 0.022);
    final ktv = order.ktvUsername.trim().isEmpty ? '—' : order.ktvUsername.toUpperCase();
    final pos = order.position.isEmpty
        ? (order.customerNote.isEmpty ? 'Khu vực chờ' : order.customerNote)
        : order.position;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: accent, width: 10)),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4))],
      ),
      child: SizedBox(
        width: minW,
        child: Row(
          children: [
            Expanded(
              flex: 1,
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${index + 1}', style: TextStyle(color: Colors.white54, fontSize: fs, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: accent.withOpacity(0.8)),
                      ),
                      child: Text(
                        tier.label,
                        style: TextStyle(color: accent, fontSize: math.max(11, fs * 0.55), fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _maskLicensePlate(order.bienSo),
                    style: TextStyle(color: Colors.white, fontSize: fsLarge, fontWeight: FontWeight.bold, letterSpacing: 2),
                  ),
                  if (order.vehicleActivityNote.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, right: 8),
                      child: Text(
                        order.vehicleActivityNote,
                        style: TextStyle(color: Colors.cyan.shade200, fontSize: fs * 0.78, fontWeight: FontWeight.w500),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  Icon(Icons.support_agent, color: Colors.blueGrey.shade300, size: fs),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      order.cvdvUsername.isEmpty ? '—' : order.cvdvUsername.toUpperCase(),
                      style: TextStyle(color: Colors.white70, fontSize: fs),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  Icon(Icons.handyman, color: Colors.blueGrey.shade300, size: fs),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(ktv, style: TextStyle(color: Colors.white70, fontSize: fs), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  Icon(Icons.location_on, color: Colors.blueGrey.shade300, size: fs),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      pos,
                      style: TextStyle(color: Colors.white70, fontSize: fs),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(order.waitDisplayShort, style: TextStyle(color: waitColor, fontSize: fs, fontWeight: FontWeight.bold)),
                  Text(
                    waitingBriefForStatus(order.status, customerWaiting: order.customerWaiting),
                    style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: math.max(12, fs * 0.62), height: 1.2),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  Icon(statusMeta['icon'] as IconData?, color: statusMeta['color'] as Color?, size: fs * 1.2),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      statusMeta['text'] as String,
                      style: TextStyle(
                        color: statusMeta['color'] as Color?,
                        fontSize: math.min(24, fs * 1.05),
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchBar(double width) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              decoration: InputDecoration(
                hintText: 'Tìm biển số, RO, CVDV, KTV, vị trí…',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.45)),
                prefixIcon: const Icon(Icons.search, color: Colors.white70),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white70),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF475569))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF475569))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.blueAccent, width: 2)),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
              onSubmitted: (v) => setState(() => _searchQuery = v),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: math.min(140, width * 0.12),
            child: _priorityLegendCompact(),
          ),
        ],
      ),
    );
  }

  Widget _priorityLegendCompact() {
    Widget chip(TvPriorityTier t, String hint) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: t.color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text('${t.label}', style: TextStyle(color: t.color, fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        chip(TvPriorityTier.p1Critical, 'Ngay'),
        chip(TvPriorityTier.p2Risk, 'Rủi ro'),
        chip(TvPriorityTier.p5Done, 'Xong'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    final display = _displayOrders;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Column(
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: math.min(40, media.width * 0.04), vertical: 16),
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              border: Border(bottom: BorderSide(color: Color(0xFF334155), width: 2)),
            ),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.2), shape: BoxShape.circle),
                            child: const Icon(Icons.car_repair, color: Colors.blueAccent, size: 40),
                          ),
                          const SizedBox(width: 16),
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  AppConfig.appName,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: math.min(28, media.width * 0.035),
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _searchQuery.isEmpty
                                      ? 'BẢNG TIẾN ĐỘ XƯỞNG (LIVE) · ${activeOrders.length} xe'
                                      : 'Hiển thị ${display.length} / ${activeOrders.length} xe',
                                  style: TextStyle(
                                    color: Colors.blueAccent.shade100,
                                    fontSize: math.min(16, media.width * 0.022),
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _TvHeaderClock(fontSize: math.min(32, media.width * 0.04)),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_isFetching)
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.greenAccent),
                              )
                            else
                              const Icon(Icons.wifi, color: Colors.greenAccent, size: 16),
                            const SizedBox(width: 8),
                            Text(
                              '${_syncLabel()} · 15s',
                              style: TextStyle(color: Colors.greenAccent.shade400, fontSize: 13),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    const CompanyChatAppBarButton(),
                    IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.red.shade800,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.all(14),
                      ),
                      tooltip: 'Thoát đăng nhập',
                      onPressed: _exitToLogin,
                      icon: const Icon(Icons.logout, size: 28),
                    ),
                  ],
                ),
                _searchBar(media.width),
              ],
            ),
          ),
          _errorBanner(),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final minW = math.max(1100.0, constraints.maxWidth);
                return Scrollbar(
                  thumbVisibility: constraints.maxWidth < minW,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: minW,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _tableHeader(minW),
                          Expanded(
                            child: display.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.garage, color: Colors.grey.shade800, size: math.min(100, constraints.maxHeight * 0.2)),
                                        const SizedBox(height: 20),
                                        Text(
                                          _searchQuery.isNotEmpty
                                              ? 'KHÔNG CÓ XE KHỚP TÌM KIẾM'
                                              : (_lastError != null ? 'KHÔNG CÓ DỮ LIỆU HIỂN THỊ' : 'XƯỞNG ĐANG TRỐNG'),
                                          style: const TextStyle(color: Color(0xFF64748B), fontSize: 26, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  )
                                : RepaintBoundary(
                                    child: ListView.builder(
                                      padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
                                      itemCount: display.length,
                                      addRepaintBoundaries: true,
                                      addAutomaticKeepAlives: false,
                                      itemBuilder: (context, index) {
                                        return _buildRow(display[index], index, minW);
                                      },
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
