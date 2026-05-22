import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../core/app_pdf_fonts.dart';
import '../core/cross_platform_export_helpers.dart';
import '../core/document_export.dart';
import '../core/ke_toan_debt_types.dart';
import '../core/ke_toan_tracking_store.dart';
import '../core/payment_info.dart';
import '../core/ro_display.dart';
import '../models/auth_models.dart';
import '../services/api_service.dart';
import '../widgets/column_filter_menu_header.dart';
import '../widgets/ke_toan_debt_classify_dialog.dart';
import '../widgets/ke_toan_tracking_panel.dart';
import '../core/responsive_layout.dart';
import '../widgets/responsive_shell.dart';
import '../widgets/invoice_tracking_panel.dart';
import '../widgets/company_chat_host.dart';
import 'login_screen.dart';

class KeToanScreen extends StatefulWidget {
  final LoginResult login;

  const KeToanScreen({super.key, required this.login});

  @override
  State<KeToanScreen> createState() => _KeToanScreenState();
}

class _KeToanScreenState extends State<KeToanScreen> with SingleTickerProviderStateMixin {
  late final ApiService api;
  late TabController _tabCtrl;
  bool isLoading = false;
  List<WorkOrderItem> orders = [];
  WorkOrderItem? selectedOrder;

  static const List<MapEntry<String, String>> _listFilterCols = [
    MapEntry('bienSo', 'Biển số'),
    MapEntry('customer', 'Khách hàng'),
    MapEntry('phone', 'SĐT'),
    MapEntry('roCode', 'Mã RO'),
    MapEntry('woCode', 'Mã WO (CVDV)'),
    MapEntry('status', 'Trạng thái'),
    MapEntry('cvdv', 'CVDV'),
    MapEntry('waiting', 'Đang chờ'),
    MapEntry('waited', 'Đã chờ'),
  ];

  final Map<String, TextEditingController> _listCol = {};
  final KeToanTrackingStore _trackingStore = KeToanTrackingStore();
  final GlobalKey<KeToanTrackingPanelState> _trackingPanelKey = GlobalKey<KeToanTrackingPanelState>();

  @override
  void initState() {
    super.initState();
    for (final e in _listFilterCols) {
      _listCol[e.key] = TextEditingController();
    }
    _tabCtrl = TabController(length: 3, vsync: this);
    api = ApiService(baseUrl: widget.login.baseUrl);
    _trackingStore.configure(api: api, token: widget.login.token);
    _trackingStore.load();
    _loadData();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    for (final c in _listCol.values) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _filterHdr(String key, String title) {
    return ColumnFilterMenuHeader(
      title: title,
      filterController: _listCol[key]!,
      onFiltersChanged: () => setState(() {}),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'CHO_QUYET_TOAN':
        return 'Chờ thu tiền';
      case 'HUY_CHO_QUYET_TOAN':
        return 'KH hủy / từ chối BG — chờ KT duyệt ra';
      case 'KH_TU_CHOI':
        return 'KH từ chối báo giá — chờ KT duyệt ra';
      case 'KT_DUYET_RA_CONG':
        return 'Đã duyệt ra (KH hủy) — chờ BV';
      case 'DA_THANH_TOAN':
        return 'Đã thanh toán';
      default:
        return status;
    }
  }

  List<String> _listCells(WorkOrderItem o) {
    final wo = o.cvdvWoCode.trim().isEmpty ? '—' : o.cvdvWoCode;
    return [
      o.bienSo,
      o.customerName,
      o.customerPhone,
      o.roCode,
      wo,
      _statusLabel(o.status),
      o.cvdvUsername,
      waitingBriefForStatus(o.status, customerWaiting: o.customerWaiting),
      o.waitDisplayShort,
    ];
  }

  List<WorkOrderItem> _pipelineVisible() {
    final filters = _listFilterCols.map((e) => _listCol[e.key]!.text).toList();
    return orders.where((o) => cellsMatchFilters(filters, _listCells(o))).toList();
  }

  int _statusRank(String status) {
    const order = ['HUY_CHO_QUYET_TOAN', 'KH_TU_CHOI', 'CHO_QUYET_TOAN', 'KT_DUYET_RA_CONG', 'DA_THANH_TOAN'];
    final i = order.indexOf(status);
    return i < 0 ? 99 : i;
  }

  Future<void> _loadData() async {
    setState(() {
      isLoading = true;
    });

    try {
      final allOrders = await api.fetchBoard(widget.login.token);

      setState(() {
        orders = allOrders
            .where((o) =>
                o.status == 'CHO_QUYET_TOAN' ||
                o.status == 'HUY_CHO_QUYET_TOAN' ||
                o.status == 'KH_TU_CHOI' ||
                o.status == 'KT_DUYET_RA_CONG' ||
                o.status == 'DA_THANH_TOAN')
            .toList();

        orders.sort((a, b) {
          final ra = _statusRank(a.status);
          final rb = _statusRank(b.status);
          if (ra != rb) return ra.compareTo(rb);
          return 0;
        });

        if (selectedOrder != null) {
          try {
            selectedOrder = orders.firstWhere((o) => o.id == selectedOrder!.id);
          } catch (_) {
            selectedOrder = null;
          }
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi tải dữ liệu Kế toán: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> _approveCancelledExit(String orderId) async {
    setState(() {
      isLoading = true;
    });
    try {
      await api.updateRepairOrder(
        token: widget.login.token,
        id: orderId,
        status: 'KT_DUYET_RA_CONG',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Đã duyệt cho ra xưởng (KH hủy / từ chối báo giá). Bảo vệ có thể cho xe ra cổng.',
            ),
            backgroundColor: Colors.green,
          ),
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
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> _confirmPayment(WorkOrderItem order) async {
    final pay = parsePaymentInfo(order.paymentInfo);
    final onlyCustomer = paymentIsCustomerOnly(pay);
    final hasExternal = !onlyCustomer;

    DebtPaidClassification? debtClassification;
    if (pay.debt > 0) {
      debtClassification = await showDebtPaidClassificationDialog(context);
      if (debtClassification == null) return;
    }

    setState(() => isLoading = true);

    try {
      await api.updateRepairOrder(
        token: widget.login.token,
        id: order.id,
        status: 'DA_THANH_TOAN',
      );

      if (hasExternal) {
        await _trackingStore.ingestFromRepairOrder(
          order,
          pay,
          debtClassification: debtClassification,
        );
      }

      if (!mounted) return;

      if (onlyCustomer) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Đã thu tiền KH. Trạng thái «Đã thanh toán» — Bảo vệ có thể cho xe ra cổng.',
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 6),
          ),
        );
      } else {
        _tabCtrl.animateTo(1);
        _trackingPanelKey.currentState?.focusCategory(_trackingStore.focusCategoryKey);
        final parts = <String>[];
        if (pay.insurancePay > 0) parts.add('BH ${_formatVND(pay.insurancePay)} đ');
        if (pay.warrantyPay > 0) parts.add('VinFast ${_formatVND(pay.warrantyPay)} đ');
        if (pay.debt > 0) parts.add('Công nợ ${_formatVND(pay.debt)} đ');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              pay.customerPay > 0
                  ? 'Đã thu phần KH (${_formatVND(pay.customerPay)} đ). Xe có thể ra cổng. '
                      'Theo dõi thêm: ${parts.join(' · ')} — tab «Theo dõi».'
                  : 'Đã ghi nhận. Theo dõi: ${parts.join(' · ')} — tab «Theo dõi».',
            ),
            backgroundColor: Colors.indigo.shade800,
            duration: const Duration(seconds: 9),
            action: SnackBarAction(
              label: 'Mở tab',
              textColor: Colors.white,
              onPressed: () {
                _tabCtrl.animateTo(1);
                _trackingPanelKey.currentState?.focusCategory(_trackingStore.focusCategoryKey);
              },
            ),
          ),
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

  void _confirmPaymentDialog(WorkOrderItem order, String totalVnd) {
    final pay = parsePaymentInfo(order.paymentInfo);
    final onlyCustomer = paymentIsCustomerOnly(pay);
    final hasExternal = !onlyCustomer;

    String body = 'Xe ${order.bienSo} — Tổng hóa đơn: $totalVnd VNĐ\n\n';
    if (onlyCustomer) {
      body += 'Chỉ thu từ khách hàng (C). Sau xác nhận: «Đã thanh toán» → Bảo vệ cho ra cổng.';
    } else {
      body += 'Phân bổ:\n';
      if (pay.customerPay > 0) body += '• KH thu quầy (C): ${_formatVND(pay.customerPay)} đ\n';
      if (pay.insurancePay > 0) body += '• Bảo hiểm (I): ${_formatVND(pay.insurancePay)} đ → tab Theo dõi BH\n';
      if (pay.warrantyPay > 0) body += '• VinFast (W): ${_formatVND(pay.warrantyPay)} đ → tab Theo dõi VinFast\n';
      if (pay.debt > 0) {
        body += '• Công nợ: ${_formatVND(pay.debt)} đ → tab Theo dõi (sẽ chọn bên nợ / loại GSM)\n';
      }
      body += '\nPhần KH (nếu có) xác nhận thu quầy; BH / VinFast / nợ chuyển sang tab «Theo dõi công nợ & thu chi».';
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận đã thu tiền?'),
        content: SingleChildScrollView(child: Text(body)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _confirmPayment(order);
            },
            child: Text(hasExternal ? 'Xác nhận & mở theo dõi' : 'Xác nhận thu'),
          ),
        ],
      ),
    );
  }

  void _confirmApproveCancelDialog(String orderId, String bienSo) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Duyệt cho ra xưởng?'),
        content: Text(
          'Xe $bienSo — Khách hủy không sửa hoặc từ chối báo giá.\n\n'
          'Chuyển sang KT_DUYET_RA_CONG: Bảo vệ mới cho ra cổng.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.deepPurple.shade700),
            onPressed: () {
              Navigator.pop(ctx);
              _approveCancelledExit(orderId);
            },
            child: const Text('Duyệt cho ra'),
          ),
        ],
      ),
    );
  }

  Widget _paymentSourceRow(String label, double amount, {Color? amountColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
          Text(
            '${_formatVND(amount)} đ',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: amount > 0 ? (amountColor ?? const Color(0xFF0F172A)) : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentAllocationSection(WorkOrderItem o, double invoiceTotal) {
    final pay = parsePaymentInfo(o.paymentInfo);
    final allocated = pay.customerPay + pay.insurancePay + pay.warrantyPay + pay.debt;
    final refTotal = invoiceTotal > 0 ? invoiceTotal : pay.grandTotal;
    final mismatch = pay.hasAny && refTotal > 0 && allocated.round() != refTotal.round();

    if (!pay.hasAny) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.amber.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.amber.shade900, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Chưa có phân bổ nguồn thanh toán',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber.shade900, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'CVDV chưa lưu nguồn thanh toán (C / I / W / công nợ) trên phiếu. '
              'Yêu cầu CVDV mở xe và lưu lại trước khi thu tiền, hoặc tự ghi chú trên phiếu thu.',
              style: TextStyle(fontSize: 14, height: 1.4),
            ),
            if (refTotal > 0) ...[
              const SizedBox(height: 10),
              Text(
                'Tổng hóa đơn (công + PT): ${_formatVND(refTotal)} đ',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ],
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'III. PHÂN BỔ NGUỒN THANH TOÁN (CVDV)',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey),
        ),
        const SizedBox(height: 4),
        const Text(
          'Kế toán thu / đối soát theo từng nguồn — tổng các dòng phải khớp tổng hóa đơn.',
          style: TextStyle(fontSize: 13, color: Colors.black54),
        ),
        const SizedBox(height: 16),
        if (mismatch)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Text(
              'Cảnh báo: Tổng phân bổ (${_formatVND(allocated)} đ) ≠ tổng hóa đơn (${_formatVND(refTotal)} đ). '
              'Liên hệ CVDV chỉnh lại nguồn thanh toán.',
              style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F9FF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.shade100),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _paymentSourceRow(
                'Khách hàng thanh toán tại quầy (C)',
                pay.customerPay,
                amountColor: Colors.teal.shade800,
              ),
              _paymentSourceRow(
                'Bảo hiểm thanh toán (I)',
                pay.insurancePay,
                amountColor: Colors.indigo.shade800,
              ),
              _paymentSourceRow(
                'Bảo hành / VinFast (W)',
                pay.warrantyPay,
                amountColor: Colors.blue.shade800,
              ),
              _paymentSourceRow(
                'Công nợ',
                pay.debt,
                amountColor: Colors.orange.shade900,
              ),
              if (pay.insuranceCompany != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Hãng bảo hiểm: ${pay.insuranceCompany}',
                    style: TextStyle(fontSize: 14, color: Colors.blueGrey.shade800),
                  ),
                ),
              const Divider(height: 24),
              _paymentSourceRow('Tổng phân bổ (C + I + W + nợ)', allocated),
              if (refTotal > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Tổng hóa đơn (công + PT): ${_formatVND(refTotal)} đ',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: mismatch ? Colors.red.shade700 : Colors.blueGrey.shade800,
                    ),
                  ),
                ),
              if (pay.customerPay > 0) ...[
                const Divider(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.teal.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.payments_outlined, color: Colors.teal.shade800),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Thu tại quầy kế toán',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal.shade900, fontSize: 16),
                        ),
                      ),
                      Text(
                        '${_formatVND(pay.customerPay)} đ',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (pay.insurancePay > 0 || pay.warrantyPay > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    [
                      if (pay.insurancePay > 0) 'BH: ${_formatVND(pay.insurancePay)} đ',
                      if (pay.warrantyPay > 0) 'BHành: ${_formatVND(pay.warrantyPay)} đ',
                    ].join('  ·  '),
                    style: TextStyle(fontSize: 13, color: Colors.indigo.shade800, fontStyle: FontStyle.italic),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _printReceipt(
    WorkOrderItem order,
    List<dynamic> jobs,
    List<dynamic> parts,
    double grandTotal,
  ) async {
    final font = AppPdfFonts.regular;
    final fontBold = AppPdfFonts.bold;
    final pdf = pw.Document();
    final woLine = order.cvdvWoCode.trim().isEmpty ? '—' : order.cvdvWoCode;
    final pay = parsePaymentInfo(order.paymentInfo);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text('TS-XDV AUTO SERVICE', style: pw.TextStyle(font: fontBold, fontSize: 18)),
              ),
              pw.Center(
                child: pw.Text('PHIẾU THU TIỀN / HÓA ĐƠN', style: pw.TextStyle(font: fontBold, fontSize: 14)),
              ),
              pw.SizedBox(height: 16),
              pw.Text('Khách hàng: ${order.customerName}', style: pw.TextStyle(font: font, fontSize: 10)),
              pw.Text('Số điện thoại: ${order.customerPhone}', style: pw.TextStyle(font: font, fontSize: 10)),
              pw.Text('Biển số xe: ${order.bienSo}', style: pw.TextStyle(font: fontBold, fontSize: 10)),
              pw.Text('Mã RO: ${order.roCode}', style: pw.TextStyle(font: font, fontSize: 10)),
              pw.Text('Mã WO (CVDV): $woLine', style: pw.TextStyle(font: font, fontSize: 10)),
              pw.Text('Thời gian in: ${DateTime.now().toString().substring(0, 16)}', style: pw.TextStyle(font: font, fontSize: 10)),
              pw.Text('Thu ngân: ${widget.login.userName}', style: pw.TextStyle(font: font, fontSize: 10)),
              pw.SizedBox(height: 16),
              pw.Divider(thickness: 1),
              pw.SizedBox(height: 8),
              if (jobs.isNotEmpty) ...[
                pw.Text('I. TIỀN CÔNG DỊCH VỤ', style: pw.TextStyle(font: fontBold, fontSize: 10)),
                pw.SizedBox(height: 4),
                ...jobs.map((j) => pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 4),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Expanded(child: pw.Text('- ${j['name']}', style: pw.TextStyle(font: font, fontSize: 10))),
                          pw.Text('${_formatVND(_num(j['total']))} đ', style: pw.TextStyle(font: fontBold, fontSize: 10)),
                        ],
                      ),
                    )),
                pw.SizedBox(height: 8),
              ],
              if (parts.isNotEmpty) ...[
                pw.Text('II. PHỤ TÙNG & VẬT TƯ', style: pw.TextStyle(font: fontBold, fontSize: 10)),
                pw.SizedBox(height: 4),
                ...parts.map((p) => pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 4),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Expanded(
                              child: pw.Text('- ${p['name']} (x${p['qty']})', style: pw.TextStyle(font: font, fontSize: 10))),
                          pw.Text('${_formatVND(_num(p['total']))} đ', style: pw.TextStyle(font: fontBold, fontSize: 10)),
                        ],
                      ),
                    )),
                pw.SizedBox(height: 8),
              ],
              pw.Divider(thickness: 1),
              pw.SizedBox(height: 8),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('TỔNG CỘNG:', style: pw.TextStyle(font: fontBold, fontSize: 12)),
                  pw.Text('${_formatVND(grandTotal)} đ', style: pw.TextStyle(font: fontBold, fontSize: 14)),
                ],
              ),
              if (pay.hasAny) ...[
                pw.SizedBox(height: 12),
                pw.Text('PHÂN BỔ NGUỒN THANH TOÁN', style: pw.TextStyle(font: fontBold, fontSize: 10)),
                pw.SizedBox(height: 4),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Khách hàng (C)', style: pw.TextStyle(font: font, fontSize: 9)),
                    pw.Text('${_formatVND(pay.customerPay)} đ', style: pw.TextStyle(font: fontBold, fontSize: 9)),
                  ],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Bảo hiểm (I)', style: pw.TextStyle(font: font, fontSize: 9)),
                    pw.Text('${_formatVND(pay.insurancePay)} đ', style: pw.TextStyle(font: fontBold, fontSize: 9)),
                  ],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Bảo hành (W)', style: pw.TextStyle(font: font, fontSize: 9)),
                    pw.Text('${_formatVND(pay.warrantyPay)} đ', style: pw.TextStyle(font: fontBold, fontSize: 9)),
                  ],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Công nợ', style: pw.TextStyle(font: font, fontSize: 9)),
                    pw.Text('${_formatVND(pay.debt)} đ', style: pw.TextStyle(font: fontBold, fontSize: 9)),
                  ],
                ),
                if (pay.customerPay > 0)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 6),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Thu tại quầy:', style: pw.TextStyle(font: fontBold, fontSize: 10)),
                        pw.Text('${_formatVND(pay.customerPay)} đ', style: pw.TextStyle(font: fontBold, fontSize: 11)),
                      ],
                    ),
                  ),
              ],
              pw.SizedBox(height: 24),
              pw.Center(
                child: pw.Text('Cảm ơn Quý khách & Hẹn gặp lại!',
                    style: pw.TextStyle(font: font, fontSize: 10, fontStyle: pw.FontStyle.italic)),
              ),
            ],
          );
        },
      ),
    );

    final pdfResult = await printOrSharePdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      documentName: 'Hoa_Don_${order.bienSo}',
      dialogTitle: 'Lưu hóa đơn PDF',
    );
    if (mounted) {
      showCrossPlatformSaveSnackBar(context, pdfResult, 'Hoa_Don_${order.bienSo}.pdf', successExtra: 'Hóa đơn PDF');
    }
  }

  static num _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    return num.tryParse(v.toString()) ?? 0;
  }

  String _formatVND(num value) {
    return value.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]},',
        );
  }

  ({List<dynamic> jobs, List<dynamic> parts, double grandTotal}) _parseInvoice(WorkOrderItem? o) {
    if (o == null) return (jobs: <dynamic>[], parts: <dynamic>[], grandTotal: 0);
    List<dynamic> jobs = [];
    List<dynamic> parts = [];
    double grandTotal = 0;
    try {
      if (o.jobs != null && o.jobs.toString() != 'null') {
        jobs = (o.jobs is String) ? jsonDecode(o.jobs as String) : List.from(o.jobs as List);
        for (final j in jobs) {
          grandTotal += _num(j['total']).toDouble();
        }
      }
      if (o.parts != null && o.parts.toString() != 'null') {
        parts = (o.parts is String) ? jsonDecode(o.parts as String) : List.from(o.parts as List);
        for (final p in parts) {
          grandTotal += _num(p['total']).toDouble();
        }
      }
    } catch (e) {
      debugPrint('Lỗi parse dữ liệu hóa đơn: $e');
    }
    return (jobs: jobs, parts: parts, grandTotal: grandTotal);
  }

  Widget _summaryStrip() {
    final nHuy = orders.where((o) => o.status == 'HUY_CHO_QUYET_TOAN' || o.status == 'KH_TU_CHOI').length;
    final nThu = orders.where((o) => o.status == 'CHO_QUYET_TOAN').length;
    final nRa = orders.where((o) => o.status == 'KT_DUYET_RA_CONG').length;
    final nDone = orders.where((o) => o.status == 'DA_THANH_TOAN').length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          Chip(
            avatar: const Icon(Icons.warning_amber, size: 18),
            label: Text('KH hủy / từ chối BG — chờ duyệt: $nHuy'),
            backgroundColor: Colors.deepPurple.shade50,
          ),
          Chip(
            avatar: const Icon(Icons.attach_money, size: 18),
            label: Text('Chờ thu: $nThu'),
            backgroundColor: Colors.orange.shade50,
          ),
          Chip(
            avatar: const Icon(Icons.exit_to_app, size: 18),
            label: Text('Đã duyệt ra (hủy): $nRa'),
            backgroundColor: Colors.blueGrey.shade50,
          ),
          Chip(
            avatar: const Icon(Icons.check_circle, size: 18),
            label: Text('Đã thanh toán: $nDone'),
            backgroundColor: Colors.green.shade50,
          ),
        ],
      ),
    );
  }

  Widget _filterStrip() {
    return Material(
      color: const Color(0xFFF0FDFA),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            for (final e in _listFilterCols)
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: _filterHdr(e.key, e.value),
              ),
          ],
        ),
      ),
    );
  }

  Widget _leftPanel(List<WorkOrderItem> visible) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.teal.shade50,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Icon(Icons.point_of_sale, color: Colors.teal.shade700, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Phiếu quyết toán / thu',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal.shade800),
                      ),
                      Text(
                        'Hiển thị ${visible.length} / ${orders.length}',
                        style: TextStyle(fontSize: 13, color: Colors.teal.shade900),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _summaryStrip(),
          _filterStrip(),
          Expanded(
            child: isLoading && orders.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : orders.isEmpty
                    ? const Center(
                        child: Text(
                          'Chưa có phiếu quyết toán hoặc hồ sơ KH hủy cần xử lý.',
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                      )
                    : visible.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text(
                                'Không có dòng khớp lọc. Mở menu tam giác trên tiêu đề → «Xóa lọc cột».',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: visible.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final item = visible[index];
                              final isSelected = selectedOrder?.id == item.id;
                              final isPaid = item.status == 'DA_THANH_TOAN';
                              final isCancelPending = item.status == 'HUY_CHO_QUYET_TOAN' || item.status == 'KH_TU_CHOI';
                              final isExitApproved = item.status == 'KT_DUYET_RA_CONG';

                              return InkWell(
                                onTap: () => setState(() => selectedOrder = item),
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: isSelected ? Colors.teal.shade50 : Colors.white,
                                    border: Border.all(
                                      color: isSelected ? Colors.teal : Colors.grey.shade200,
                                      width: isSelected ? 2 : 1,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: isPaid
                                              ? Colors.green.shade100
                                              : (isExitApproved
                                                  ? Colors.blueGrey.shade100
                                                  : (isCancelPending
                                                      ? Colors.deepPurple.shade100
                                                      : Colors.orange.shade100)),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          isPaid
                                              ? Icons.check_circle
                                              : (isExitApproved
                                                  ? Icons.exit_to_app
                                                  : (isCancelPending ? Icons.cancel_schedule_send : Icons.attach_money)),
                                          color: isPaid
                                              ? Colors.green
                                              : (isExitApproved
                                                  ? Colors.blueGrey
                                                  : (isCancelPending ? Colors.deepPurple : Colors.orange.shade800)),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.bienSo,
                                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'RO ${item.roCode} · ${_statusLabel(item.status)}',
                                              style: TextStyle(color: Colors.blueGrey.shade800, fontSize: 12),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            Text(
                                              item.customerName,
                                              style: const TextStyle(color: Colors.black87),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (isExitApproved)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.blueGrey.shade700,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            'CHỜ RA CỔNG',
                                            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                          ),
                                        )
                                      else if (!isPaid && isCancelPending)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.deepPurple,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            'KH HỦY — CHỜ DUYỆT',
                                            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                          ),
                                        )
                                      else if (!isPaid)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.red,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            'CẦN THU',
                                            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                    ],
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

  Widget _detailPanel() {
    if (selectedOrder == null) {
      return const Center(
        child: Text(
          '← Chọn một phiếu để thu tiền, duyệt ra hoặc in phiếu',
          style: TextStyle(fontSize: 18, color: Colors.grey),
        ),
      );
    }

    final o = selectedOrder!;
    final isPaid = o.status == 'DA_THANH_TOAN';
    final isCancelPending = o.status == 'HUY_CHO_QUYET_TOAN' || o.status == 'KH_TU_CHOI';
    final isExitApproved = o.status == 'KT_DUYET_RA_CONG';
    final parsed = _parseInvoice(o);
    final jobs = parsed.jobs;
    final parts = parsed.parts;
    final grandTotal = parsed.grandTotal;
    final pay = parsePaymentInfo(o.paymentInfo);
    final collectAtDesk = pay.customerPay > 0 ? pay.customerPay : grandTotal;
    final woLine = o.cvdvWoCode.trim().isEmpty ? '—' : o.cvdvWoCode;

    return Container(
      margin: const EdgeInsets.only(top: 16, right: 16, bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('CHI TIẾT HÓA ĐƠN', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text(
                        o.bienSo,
                        style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                      ),
                      const SizedBox(height: 4),
                      Text('Mã RO: ${o.roCode}  ·  Mã WO (CVDV): $woLine'),
                      Text('Khách hàng: ${o.customerName} — SĐT: ${o.customerPhone}'),
                      Text('Cố vấn dịch vụ: ${o.cvdvUsername}'),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.hourglass_top, size: 16, color: Colors.deepPurple.shade700),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Đang chờ: ${waitingBriefForStatus(o.status, customerWaiting: o.customerWaiting)}',
                              style: TextStyle(color: Colors.deepPurple.shade800, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('Đã chờ (trạng thái hiện tại): ${o.waitDisplayShort}',
                          style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: isPaid
                        ? Colors.green.shade50
                        : (isExitApproved
                            ? Colors.blueGrey.shade50
                            : (isCancelPending ? Colors.deepPurple.shade50 : Colors.orange.shade50)),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isPaid
                          ? Colors.green
                          : (isExitApproved ? Colors.blueGrey : (isCancelPending ? Colors.deepPurple : Colors.orange)),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        isPaid
                            ? 'ĐÃ THANH TOÁN'
                            : (isExitApproved
                                ? 'ĐÃ DUYỆT RA (HỦY)'
                                : (isCancelPending ? 'HỦY / TỪ CHỐI BG — CHỜ KT' : 'CHỜ THU TIỀN')),
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          color: isPaid
                              ? Colors.green
                              : (isExitApproved
                                  ? Colors.blueGrey.shade900
                                  : (isCancelPending ? Colors.deepPurple.shade900 : Colors.orange.shade900)),
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      if (isPaid)
                        const Text('Khách có thể lấy xe', style: TextStyle(color: Colors.green, fontSize: 12))
                      else if (isExitApproved)
                        const Text(
                          'Chờ Bảo vệ cho ra cổng',
                          textAlign: TextAlign.end,
                          style: TextStyle(color: Colors.blueGrey, fontSize: 11),
                        )
                      else if (isCancelPending)
                        const Text(
                          'Chờ Kế toán duyệt cho ra',
                          textAlign: TextAlign.end,
                          style: TextStyle(color: Colors.deepPurple, fontSize: 11),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (jobs.isNotEmpty) ...[
                    const Text('I. TIỀN CÔNG SỬA CHỮA',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                    const SizedBox(height: 16),
                    ...jobs.map((j) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              Expanded(child: Text('• ${j['name']}', style: const TextStyle(fontSize: 16))),
                              Text('${_formatVND(_num(j['total']))} đ',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        )),
                    const Divider(height: 32),
                  ],
                  if (parts.isNotEmpty) ...[
                    const Text('II. PHỤ TÙNG & VẬT TƯ',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                    const SizedBox(height: 16),
                    ...parts.map((p) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              Expanded(
                                  child: Text('• ${p['name']} (x${p['qty']})', style: const TextStyle(fontSize: 16))),
                              Text('${_formatVND(_num(p['total']))} đ',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        )),
                    const Divider(height: 32),
                  ],
                  if (jobs.isEmpty && parts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 24),
                      child: Text(
                        'Chưa có dòng công / phụ tùng trên phiếu (kiểm tra lại dữ liệu CVDV).',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  if (jobs.isNotEmpty || parts.isNotEmpty) const Divider(height: 32),
                  _buildPaymentAllocationSection(o, grandTotal),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
              boxShadow: [
                BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2)),
              ],
            ),
            child: LayoutBuilder(
              builder: (context, c) {
                final stackActions = c.maxWidth < 520;
                final totalLabel = isCancelPending || isExitApproved
                    ? 'GIÁ TRỊ BÁO GIÁ (THAM KHẢO):'
                    : 'TỔNG SỐ TIỀN CẦN THU:';

                final printBtn = OutlinedButton.icon(
                  onPressed: () => _printReceipt(o, jobs, parts, grandTotal),
                  icon: const Icon(Icons.print),
                  label: const Text('IN PHIẾU THU'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  ),
                );

                final excelTplBtn = OutlinedButton.icon(
                  onPressed: isLoading
                      ? null
                      : () {
                          showDocumentExportSheet(
                            context: context,
                            api: api,
                            token: widget.login.token,
                            repairOrderId: o.id,
                            bienSo: o.bienSo,
                            onlyKeys: const ['quyet_toan', 'phieu_ra_cong', 'bao_gia', 'lenh_sua_chua', 'hoa_don_noi_bo'],
                          );
                        },
                  icon: const Icon(Icons.table_chart_outlined),
                  label: const Text('MẪU EXCEL'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                  ),
                );

                Widget? primaryBtn;
                if (isCancelPending) {
                  primaryBtn = FilledButton.icon(
                    onPressed: isLoading ? null : () => _confirmApproveCancelDialog(o.id, o.bienSo),
                    icon: const Icon(Icons.exit_to_app),
                    label: const Text('DUYỆT CHO RA XƯỞNG (KH HỦY)', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.deepPurple.shade700,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                    ),
                  );
                } else if (!isPaid && !isExitApproved) {
                  primaryBtn = FilledButton.icon(
                    onPressed: isLoading
                        ? null
                        : () => _confirmPaymentDialog(o, '${_formatVND(grandTotal)}'),
                    icon: const Icon(Icons.check_circle),
                    label: const Text('XÁC NHẬN ĐÃ THU TIỀN', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.teal.shade600,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                    ),
                  );
                } else if (isPaid || isExitApproved) {
                  primaryBtn = FilledButton.icon(
                    onPressed: null,
                    icon: Icon(isPaid ? Icons.verified : Icons.done_all),
                    label: Text(isPaid ? 'ĐÃ HOÀN TẤT THU TIỀN' : 'ĐÃ DUYỆT RA — CHỜ BẢO VỆ'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.grey,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                    ),
                  );
                }

                final totalBlock = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      totalLabel,
                      style: TextStyle(
                        color: Colors.grey,
                        fontWeight: FontWeight.bold,
                        fontSize: stackActions ? 14 : 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_formatVND(grandTotal)} VNĐ',
                      style: TextStyle(
                        fontSize: stackActions ? 28 : 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    if (pay.hasAny && !isCancelPending && !isExitApproved)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Thu tại quầy (C): ${_formatVND(collectAtDesk)} đ'
                          '${pay.insurancePay > 0 ? '  ·  BH: ${_formatVND(pay.insurancePay)} đ' : ''}'
                          '${pay.warrantyPay > 0 ? '  ·  BHành: ${_formatVND(pay.warrantyPay)} đ' : ''}'
                          '${pay.debt > 0 ? '  ·  Nợ: ${_formatVND(pay.debt)} đ' : ''}',
                          style: TextStyle(fontSize: 13, color: Colors.teal.shade800, fontWeight: FontWeight.w600),
                        ),
                      ),
                    if (isCancelPending)
                      Padding(
                        padding: EdgeInsets.only(top: stackActions ? 8 : 8, bottom: stackActions ? 12 : 0),
                        child: const Text(
                          'KH không sửa: không bắt buộc thu — bấm «Duyệt cho ra xưởng».',
                          style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                        ),
                      ),
                  ],
                );

                if (stackActions) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      totalBlock,
                      printBtn,
                      const SizedBox(height: 10),
                      excelTplBtn,
                      if (primaryBtn != null) ...[
                        const SizedBox(height: 10),
                        primaryBtn,
                      ],
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(child: totalBlock),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.end,
                      children: [
                        printBtn,
                        excelTplBtn,
                        if (primaryBtn != null) primaryBtn,
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _pipelineVisible();
    final phone = appIsPhone(context);
    final narrow = phone || MediaQuery.sizeOf(context).width < 960;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: Text(
          compactAppBarTitle(context, 'KẾ TOÁN — Quyết toán'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.teal.shade800,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabCtrl,
          isScrollable: true,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Phiếu quyết toán'),
            Tab(text: 'Theo dõi công nợ & thu chi'),
            Tab(text: 'Theo dõi hóa đơn PT'),
          ],
        ),
        actions: [
          const CompanyChatAppBarButton(),
          Center(
            child: Text(
              'Kế toán: ${widget.login.userName}  ',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: isLoading ? null : _loadData,
            tooltip: 'Làm mới',
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
            tooltip: 'Đăng xuất',
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          Stack(
            children: [
              narrow
                  ? Column(
                      children: [
                        SizedBox(height: phone ? 260 : 340, child: _leftPanel(visible)),
                        Expanded(child: _detailPanel()),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 420, child: _leftPanel(visible)),
                        Expanded(child: _detailPanel()),
                      ],
                    ),
              if (isLoading && orders.isNotEmpty)
                const Positioned.fill(
                  child: IgnorePointer(
                    child: ModalBarrier(dismissible: false, color: Color(0x11000000)),
                  ),
                ),
              if (isLoading && orders.isNotEmpty) const Center(child: CircularProgressIndicator()),
            ],
          ),
          KeToanTrackingPanel(
            key: _trackingPanelKey,
            store: _trackingStore,
            userName: widget.login.userName,
          ),
          InvoiceTrackingPanel(api: api, token: widget.login.token),
        ],
      ),
    );
  }
}
