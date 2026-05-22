import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';



import '../services/api_service.dart';

import 'cross_platform_export_helpers.dart';



bool get _useExportBottomSheet {

  if (kIsWeb) return false;

  return defaultTargetPlatform == TargetPlatform.android ||

      defaultTargetPlatform == TargetPlatform.iOS;

}



void showAdaptiveExportMenu({

  required BuildContext context,

  required String title,

  String? subtitle,

  required List<Widget> children,

}) {

  if (_useExportBottomSheet) {

    showModalBottomSheet<void>(

      context: context,

      showDragHandle: true,

      builder: (sheetCtx) => SafeArea(

        child: Padding(

          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),

          child: Column(

            mainAxisSize: MainAxisSize.min,

            crossAxisAlignment: CrossAxisAlignment.stretch,

            children: [

              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),

              if (subtitle != null) ...[

                const SizedBox(height: 6),

                Text(subtitle, style: const TextStyle(fontSize: 13, color: Colors.black54)),

              ],

              const SizedBox(height: 8),

              ...children,

            ],

          ),

        ),

      ),

    );

    return;

  }



  showDialog<void>(

    context: context,

    builder: (dialogCtx) => AlertDialog(

      title: Text(title),

      content: SingleChildScrollView(

        child: Column(

          mainAxisSize: MainAxisSize.min,

          crossAxisAlignment: CrossAxisAlignment.stretch,

          children: [

            if (subtitle != null)

              Padding(

                padding: const EdgeInsets.only(bottom: 12),

                child: Text(subtitle, style: const TextStyle(fontSize: 13, color: Colors.black54)),

              ),

            ...children,

          ],

        ),

      ),

      actions: [

        TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Đóng')),

      ],

    ),

  );

}



class DocumentTemplateOption {

  final String key;

  final String label;

  final IconData icon;



  const DocumentTemplateOption(this.key, this.label, this.icon);

}



const List<DocumentTemplateOption> kDocumentTemplates = [

  DocumentTemplateOption('phieu_tiep_nhan', 'Phiếu tiếp nhận xe (VF)', Icons.login),

  DocumentTemplateOption('bao_gia', 'Báo giá sửa chữa', Icons.request_quote_outlined),

  DocumentTemplateOption('lenh_sua_chua', 'Lệnh sửa chữa', Icons.build_circle_outlined),

  DocumentTemplateOption('phieu_yeu_cau_pt', 'Phiếu yêu cầu phụ tùng', Icons.inventory_2_outlined),

  DocumentTemplateOption('quyet_toan', 'Quyết toán sửa chữa', Icons.fact_check_outlined),

  DocumentTemplateOption('hoa_don_noi_bo', 'Hóa đơn nội bộ', Icons.receipt_long),

  DocumentTemplateOption('phieu_ra_cong', 'Phiếu ra cổng', Icons.logout),

];



String _formatExportError(Object e) {

  final msg = e.toString();

  if (msg.contains('404') || msg.toLowerCase().contains('cannot get')) {

    return 'Máy chủ chưa có API xuất phiếu (/documents).\n'

        '→ Deploy lại ts-server mới (có thư mục templates/) hoặc trỏ app về server local.';

  }

  if (msg.contains('Thiếu file mẫu') || msg.contains('ENOENT')) {

    return 'Server thiếu file mẫu Excel.\n→ Deploy ts-server kèm folder templates/.';

  }

  if (msg.contains('SocketException') ||
      msg.contains('Failed host lookup') ||
      msg.contains('Connection refused') ||
      msg.contains('ClientException')) {

    return 'Không kết nối được máy chủ.\n→ Kiểm tra ts-server đang chạy và địa chỉ trong AppConfig.';

  }

  if (msg.contains('Sharing violation') ||
      msg.contains('being used by another process') ||
      msg.contains('Access is denied') ||
      msg.contains('used by another')) {
    return 'File Excel đang mở — đóng file cũ hoặc lưu bản mới (tên file đã có thời gian để không trùng).';
  }
  if (msg.contains('401') || msg.contains('Chưa đăng nhập') || msg.contains('Token không hợp lệ')) {
    return 'Máy chủ từ chối phiên đăng nhập.\n'
        '→ Restart / deploy ts-server bản mới (API xuất phiếu không bắt buộc login).\n'
        '→ Hoặc đăng xuất, đăng nhập lại bằng mật khẩu trên server (không dùng staff_db nội bộ).';
  }

  return msg.replaceFirst('Exception: ', '');

}



bool _documentExportInFlight = false;

Future<void> saveRepairOrderDocumentTemplate({

  required BuildContext context,

  required ApiService api,

  required String token,

  required String repairOrderId,

  required String bienSo,

  required String templateKey,

  required String templateLabel,

  Future<void> Function()? prepareForExport,

}) async {
  if (_documentExportInFlight) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đang xuất file khác — đợi xong rồi thử lại.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
    return;
  }
  _documentExportInFlight = true;

  if (repairOrderId.trim().isEmpty) {
    _documentExportInFlight = false;
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không có mã phiếu — chọn lại xe.'), backgroundColor: Colors.red),
      );
    }
    return;
  }



  if (!context.mounted) return;

  showDialog<void>(

    context: context,

    barrierDismissible: false,

    builder: (_) => const AlertDialog(

      content: Row(

        children: [

          CircularProgressIndicator(),

          SizedBox(width: 20),

          Expanded(child: Text('Đang tạo file Excel…')),

        ],

      ),

    ),

  );



  try {

    if (prepareForExport != null) {
      try {
        await prepareForExport();
      } catch (syncErr) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Không lưu được nháp lên server (${syncErr.toString().replaceFirst('Exception: ', '')}). Vẫn xuất theo dữ liệu đã lưu trước đó.'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 6),
            ),
          );
        }
      }
    }

    final bytes = await api.downloadRepairOrderDocument(

      token: token,

      repairOrderId: repairOrderId,

      templateKey: templateKey,

    );

    if (!context.mounted) return;

    Navigator.of(context, rootNavigator: true).pop();



    if (bytes.isEmpty) {

      throw Exception('Server trả file Excel rỗng.');

    }



    final safePlate = bienSo.replaceAll(RegExp(r'[^\w\-]'), '_');
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final defaultName = '${templateKey}_${safePlate}_$stamp.xlsx';

    final result = await saveExcelBytes(

      bytes: bytes,

      fileName: defaultName,

      dialogTitle: 'Lưu — $templateLabel',

    );



    if (context.mounted) {

      showCrossPlatformSaveSnackBar(context, result, defaultName, successExtra: templateLabel);

    }

  } catch (e) {

    if (context.mounted) {

      final nav = Navigator.of(context, rootNavigator: true);

      if (nav.canPop()) nav.pop();

      ScaffoldMessenger.of(context).showSnackBar(

        SnackBar(

          content: Text('Lỗi xuất $templateLabel:\n${_formatExportError(e)}'),

          backgroundColor: Colors.red,

          duration: const Duration(seconds: 10),

        ),

      );

    }

  } finally {
    _documentExportInFlight = false;
  }

}



void showDocumentExportSheet({

  required BuildContext context,

  required ApiService api,

  required String token,

  required String repairOrderId,

  required String bienSo,

  List<String>? onlyKeys,

  Future<void> Function()? prepareForExport,

}) {

  final options = onlyKeys == null

      ? kDocumentTemplates

      : kDocumentTemplates.where((t) => onlyKeys.contains(t.key)).toList();



  showAdaptiveExportMenu(

    context: context,

    title: 'Xuất phiếu theo mẫu Excel (TS)',

    subtitle: 'Biển $bienSo — nên Lưu nháp trước khi xuất để đủ công việc & PT.',

    children: [

      for (final t in options)

        ListTile(

          leading: Icon(t.icon, color: Colors.teal.shade800),

          title: Text(t.label),

          subtitle: Text(t.key, style: const TextStyle(fontSize: 11)),

          onTap: () {

            Navigator.of(context, rootNavigator: true).pop();

            saveRepairOrderDocumentTemplate(

              context: context,

              api: api,

              token: token,

              repairOrderId: repairOrderId,

              bienSo: bienSo,

              templateKey: t.key,

              templateLabel: t.label,

              prepareForExport: prepareForExport,

            );

          },

        ),

    ],

  );

}


