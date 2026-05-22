
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../core/pick_file_bytes.dart';
import 'package:flutter/material.dart';

import '../core/cross_platform_export_helpers.dart';
import '../core/responsive_layout.dart';
import '../services/api_service.dart';



class InvoiceTrackingPanel extends StatefulWidget {

  const InvoiceTrackingPanel({super.key, required this.api, required this.token});



  final ApiService api;

  final String token;



  @override

  State<InvoiceTrackingPanel> createState() => _InvoiceTrackingPanelState();

}



class _InvoiceTrackingPanelState extends State<InvoiceTrackingPanel> {

  bool loading = true;

  String? error;

  Map<String, dynamic>? report;

  int _filterTab = 0; // 0 = chưa xuất, 1 = đã xuất



  @override

  void initState() {

    super.initState();

    _load();

  }



  Future<void> _load() async {

    setState(() {

      loading = true;

      error = null;

    });

    try {

      final data = await widget.api.fetchInvoiceTracking(token: widget.token);

      if (mounted) setState(() => report = data);

    } catch (e) {

      if (mounted) setState(() => error = e.toString());

    } finally {

      if (mounted) setState(() => loading = false);

    }

  }



  Future<void> _upload() async {
    final pick = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'xls'],
      withData: true,
    );
    if (pick == null || pick.files.isEmpty) return;

    final f = pick.files.first;
    List<int>? fileBytes = f.bytes;
    if (fileBytes == null || fileBytes.isEmpty) {
      fileBytes = await bytesFromPickerFile(f);
    }
    if (fileBytes == null || fileBytes.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('File Excel trống hoặc không đọc được. Chọn lại file .xlsx'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() => loading = true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đang tải file tồn kho lên server…'), duration: Duration(seconds: 2)),
      );
    }

    try {
      final data = await widget.api.uploadInvoicePartsFile(
        token: widget.token,
        bytes: fileBytes,
        filename: f.name.isNotEmpty ? f.name : 'ton_kho.xlsx',
      );

      if (mounted) {

        setState(() => report = data);

        ScaffoldMessenger.of(context).showSnackBar(

          SnackBar(

            content: Text(data['message']?.toString() ?? 'Đã cập nhật file tồn kho'),

            backgroundColor: Colors.green,

          ),

        );

      }

    } catch (e) {

      if (mounted) {

        ScaffoldMessenger.of(context).showSnackBar(

          SnackBar(content: Text('Lỗi upload: $e'), backgroundColor: Colors.red),

        );

      }

    } finally {

      if (mounted) setState(() => loading = false);

    }

  }



  List<Map<String, dynamic>> get _filteredVehicles {
    final all = (report?['vehicles'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (_filterTab == 0) {
      return all.where((v) => v['accountant_issued'] != true).toList();
    }
    return all.where((v) => v['accountant_issued'] == true).toList();
  }

  Future<void> _markIssued(Map<String, dynamic> v) async {
    final roId = v['ro_id']?.toString() ?? '';
    if (roId.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận đã xuất hóa đơn'),
        content: Text(
          'Xe ${v['bien_so']} — RO ${v['ro_code']}\n\nChuyển sang tab «Đã xuất hóa đơn»?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Đã xuất hóa đơn')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => loading = true);
    try {
      await widget.api.markInvoiceIssued(token: widget.token, repairOrderId: roId);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã chuyển sang «Đã xuất hóa đơn»'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }



  Future<void> _exportVehicle(Map<String, dynamic> v) async {

    final roId = v['ro_id']?.toString() ?? '';

    if (roId.isEmpty) return;

    try {

      final bytes = await widget.api.downloadInvoiceVehicleExcel(

        token: widget.token,

        repairOrderId: roId,

      );

      if (!mounted) return;

      final plate = (v['bien_so'] ?? 'xe').toString();

      final result = await saveExcelBytes(
        bytes: bytes,
        fileName: 'TheoDoiHD_$plate.xlsx',
      );
      if (mounted && result.pathOrHint != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.pathOrHint!)),
        );
      }

    } catch (e) {

      if (mounted) {

        ScaffoldMessenger.of(context).showSnackBar(

          SnackBar(content: Text('Lỗi xuất Excel: $e'), backgroundColor: Colors.red),

        );

      }

    }

  }



  void _showDetail(Map<String, dynamic> v) {

    final lines = (v['lines'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    showDialog(

      context: context,

      builder: (ctx) => AlertDialog(

        title: Text('${v['bien_so']} — ${v['ro_code']}'),

        content: SizedBox(

          width: 900,

          height: 480,

          child: Column(

            crossAxisAlignment: CrossAxisAlignment.stretch,

            children: [

              Text(

                v['parts_ready'] == true || v['ready_to_issue'] == true

                    ? 'Đủ PT trong file tồn kho — có thể xuất hóa đơn'

                    : 'Thiếu ${v['missing_parts_count']} mã PT trong file tồn kho',

                style: TextStyle(

                  fontWeight: FontWeight.bold,

                  color: v['ready_to_issue'] == true ? Colors.green.shade800 : Colors.orange.shade900,

                ),

              ),

              const SizedBox(height: 8),

              Expanded(

                child: SingleChildScrollView(

                  scrollDirection: Axis.horizontal,

                  child: SingleChildScrollView(

                    child: DataTable(

                      headingRowHeight: 36,

                      dataRowMinHeight: 32,

                      columns: const [
                        DataColumn(label: Text('Loại')),
                        DataColumn(label: Text('Mã CV/PT')),
                        DataColumn(label: Text('Tên')),
                        DataColumn(label: Text('ĐVT')),
                        DataColumn(label: Text('SL phiếu')),
                        DataColumn(label: Text('ĐG cố định')),
                        DataColumn(label: Text('Giá nhập')),
                        DataColumn(label: Text('Giá xuất')),
                        DataColumn(label: Text('Chênh lệch')),
                        DataColumn(label: Text('CK — SL')),
                        DataColumn(label: Text('CK — Giá trị')),
                        DataColumn(label: Text('HĐ')),
                      ],

                      rows: [

                        for (final l in lines)

                          DataRow(

                            cells: [

                              DataCell(Text(l['type'] == 'job' ? 'CV' : 'PT')),

                              DataCell(Text('${l['code'] ?? ''}')),

                              DataCell(Text('${l['name'] ?? ''}', maxLines: 2)),

                              DataCell(Text('${l['unit'] ?? ''}')),

                              DataCell(Text('${l['qty'] ?? ''}')),

                              DataCell(Text(_fmtNum(l['fixed_price']))),

                              DataCell(Text(_fmtNum(l['price_in']))),

                              DataCell(Text(_fmtNum(l['price_out']))),

                              DataCell(Text(_fmtNum(l['price_diff']))),
                              DataCell(Text(_fmtNum(l['stock_qty']))),
                              DataCell(Text(_fmtNum(l['stock_value']))),
                              DataCell(
                                Text(
                                  l['type'] == 'job'
                                      ? 'Quyết toán CVDV'
                                      : (l['has_invoice'] == true ? 'Đã có HĐ' : 'Chưa có HĐ'),
                                ),
                              ),

                            ],

                          ),

                      ],

                    ),

                  ),

                ),

              ),

            ],

          ),

        ),

        actions: [

          TextButton.icon(

            onPressed: () {

              Navigator.pop(ctx);

              _exportVehicle(v);

            },

            icon: const Icon(Icons.download),

            label: const Text('Xuất Excel'),

          ),

          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),

        ],

      ),

    );

  }



  String _fmtNum(dynamic v) {

    if (v == null || v == '') return '—';

    final n = num.tryParse(v.toString());

    if (n == null) return v.toString();

    return n.toStringAsFixed(0).replaceAllMapped(

      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),

      (m) => '${m[1]},',

    );

  }



  @override

  Widget build(BuildContext context) {

    if (loading && report == null) return const Center(child: CircularProgressIndicator());

    if (error != null && report == null) {

      return Center(child: Text(error!, style: const TextStyle(color: Colors.red)));

    }



    final vehicles = _filteredVehicles;

    final notCount = report?['not_invoiced_count'] ?? 0;
    final yesCount = report?['invoiced_count'] ?? 0;
    final readyInQueue = report?['ready_count'] ?? 0;



    final phone = appIsPhone(context);

    Widget mainContent = Column(

            crossAxisAlignment: CrossAxisAlignment.stretch,

            children: [

              Padding(

                padding: const EdgeInsets.all(12),

                child: Wrap(

                  spacing: 12,

                  runSpacing: 8,

                  crossAxisAlignment: WrapCrossAlignment.center,

                  children: [

                    FilledButton.icon(

                      onPressed: loading ? null : _upload,

                      icon: const Icon(Icons.upload_file),

                      label: const Text('Upload file tồn kho (thay bản cũ)'),

                    ),

                    OutlinedButton.icon(

                      onPressed: loading ? null : _load,

                      icon: const Icon(Icons.refresh),

                      label: const Text('Làm mới'),

                    ),

                    Text('File PT: ${report?['uploaded_parts_count'] ?? 0} mã'),
                    if (_filterTab == 0 && readyInQueue > 0)
                      Chip(
                        label: Text('Đủ PT — xuất HĐ: $readyInQueue xe'),
                        backgroundColor: const Color(0xFFE8F5E9),
                      ),

                    if (report?['last_upload_at'] != null)

                      Text(

                        'Cập nhật: ${report!['last_upload_at']}',

                        style: const TextStyle(fontSize: 12, color: Colors.grey),

                      ),

                  ],

                ),

              ),

              const Divider(height: 1),

              Expanded(

                child: vehicles.isEmpty

                    ? Center(

                        child: Text(

                          _filterTab == 0

                              ? 'Không có xe cần theo dõi hóa đơn.'

                              : 'Chưa có xe nào được đánh dấu «Đã xuất hóa đơn».',

                        ),

                      )

                    : ListView.builder(

                        itemCount: vehicles.length,

                        itemBuilder: (ctx, i) {

                          final v = vehicles[i];

                          final ready = v['parts_ready'] == true || v['ready_to_issue'] == true;
                          final issued = v['accountant_issued'] == true;

                          return ListTile(

                            leading: Icon(

                              ready ? Icons.check_circle : Icons.warning_amber,

                              color: ready ? Colors.green : Colors.orange,

                            ),

                            title: Text(

                              '${v['bien_so']} — ${v['customer_name']}',

                              style: const TextStyle(fontWeight: FontWeight.bold),

                            ),

                            subtitle: Text(
                              v['stock_sufficient'] == false
                                  ? 'RO ${v['ro_code']} | Không đủ tồn kho file upload'
                                  : 'RO ${v['ro_code']} | Thiếu HĐ: ${v['missing_parts_count']} PT',
                            ),

                            trailing: phone
                                ? PopupMenuButton<String>(
                                    onSelected: (a) {
                                      if (a == 'export') _exportVehicle(v);
                                      if (a == 'detail') _showDetail(v);
                                      if (a == 'issued') _markIssued(v);
                                    },
                                    itemBuilder: (_) => [
                                      const PopupMenuItem(value: 'export', child: Text('Xuất Excel')),
                                      const PopupMenuItem(value: 'detail', child: Text('Chi tiết')),
                                      if (_filterTab == 0 && ready && !issued)
                                        const PopupMenuItem(value: 'issued', child: Text('Đã xuất HĐ')),
                                    ],
                                  )
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Xuất Excel',
                                        icon: const Icon(Icons.download),
                                        onPressed: () => _exportVehicle(v),
                                      ),
                                      IconButton(
                                        tooltip: 'Chi tiết',
                                        icon: const Icon(Icons.visibility),
                                        onPressed: () => _showDetail(v),
                                      ),
                                      if (_filterTab == 0 && ready && !issued)
                                        FilledButton.tonal(
                                          onPressed: loading ? null : () => _markIssued(v),
                                          child: const Text('Đã xuất HĐ', style: TextStyle(fontSize: 11)),
                                        )
                                      else if (ready)
                                        const Chip(
                                          label: Text('Đủ PT', style: TextStyle(fontSize: 11)),
                                          backgroundColor: Color(0xFFE8F5E9),
                                        )
                                      else
                                        const Chip(
                                          label: Text('Chờ PT', style: TextStyle(fontSize: 11)),
                                        ),
                                    ],
                                  ),

                            onTap: () => _showDetail(v),

                          );

                        },

                      ),

              ),

            ],

          );

    if (phone) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: SegmentedButton<int>(
              segments: [
                ButtonSegment(
                  value: 0,
                  label: Text('Chưa HĐ ($notCount)'),
                  icon: const Icon(Icons.pending_actions, size: 18),
                ),
                ButtonSegment(
                  value: 1,
                  label: Text('Đã HĐ ($yesCount)'),
                  icon: const Icon(Icons.receipt_long, size: 18),
                ),
              ],
              selected: {_filterTab},
              onSelectionChanged: (s) => setState(() => _filterTab = s.first),
            ),
          ),
          Expanded(child: mainContent),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NavigationRail(
          selectedIndex: _filterTab,
          onDestinationSelected: (i) => setState(() => _filterTab = i),
          labelType: NavigationRailLabelType.all,
          destinations: [
            NavigationRailDestination(
              icon: Badge(label: Text('$notCount'), child: const Icon(Icons.pending_actions)),
              label: const Text('Chưa xuất HĐ'),
            ),
            NavigationRailDestination(
              icon: Badge(label: Text('$yesCount'), child: const Icon(Icons.receipt_long)),
              label: const Text('Đã xuất HĐ'),
            ),
          ],
        ),
        const VerticalDivider(width: 1),
        Expanded(child: mainContent),
      ],
    );

  }

}


