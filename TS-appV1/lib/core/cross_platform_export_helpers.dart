import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:share_plus/share_plus.dart';

import 'cross_platform_file_save.dart';

Uint8List asUint8List(List<int> bytes) => bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

/// Nhãn nút xuất theo nền tảng (web / mobile / desktop).
String exportActionLabel({String desktop = 'Xuất file', String web = 'Tải xuống', String mobile = 'Chia sẻ / lưu'}) {
  if (kIsWeb) return web;
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
    return mobile;
  }
  return desktop;
}

Future<CrossPlatformSaveResult> saveExcelBytes({
  required List<int>? bytes,
  required String fileName,
  String? dialogTitle,
}) async {
  if (bytes == null || bytes.isEmpty) {
    return const CrossPlatformSaveResult(CrossPlatformSaveOutcome.failed, 'Nội dung file Excel trống.');
  }
  var name = fileName.trim();
  if (!name.toLowerCase().endsWith('.xlsx')) name = '$name.xlsx';
  return saveBytesContent(
    bytes: asUint8List(bytes),
    fileName: name,
    dialogTitle: dialogTitle,
    mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    allowedExtensions: const ['xlsx'],
  );
}

Future<CrossPlatformSaveResult> saveTxtExport({
  required String content,
  required String fileName,
  String? dialogTitle,
}) async {
  var name = fileName.trim();
  if (!name.toLowerCase().endsWith('.txt')) name = '$name.txt';
  return saveTextContent(content: content, fileName: name, dialogTitle: dialogTitle);
}

Future<CrossPlatformSaveResult> saveCsvExport({
  required String content,
  required String fileName,
  String? dialogTitle,
}) async {
  var name = fileName.trim();
  if (!name.toLowerCase().endsWith('.csv')) name = '$name.csv';
  return saveTextContent(
    content: content,
    fileName: name,
    dialogTitle: dialogTitle,
  );
}

/// Xuất PDF: mobile chia sẻ; Windows/macOS/Linux/web lưu file (tránh pdfium trên Windows).
Future<CrossPlatformSaveResult> printOrSharePdf({
  required Future<Uint8List> Function(PdfPageFormat format) onLayout,
  required String documentName,
  String? dialogTitle,
}) async {
  final safeName = documentName.replaceAll(RegExp(r'[^\w\-.]+'), '_');
  var fileName = safeName.trim();
  if (!fileName.toLowerCase().endsWith('.pdf')) fileName = '$fileName.pdf';

  final bytes = await onLayout(PdfPageFormat.a4);

  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
    final xfile = XFile.fromData(
      bytes,
      mimeType: 'application/pdf',
      name: fileName,
    );
    await Share.shareXFiles([xfile], subject: fileName);
    return const CrossPlatformSaveResult(CrossPlatformSaveOutcome.shared);
  }

  return saveBytesContent(
    bytes: bytes,
    fileName: fileName,
    dialogTitle: dialogTitle ?? 'Lưu PDF',
    mimeType: 'application/pdf',
    allowedExtensions: const ['pdf'],
  );
}

void showCrossPlatformSaveSnackBar(
  BuildContext context,
  CrossPlatformSaveResult result,
  String fileName, {
  String? successExtra,
}) {
  if (!context.mounted) return;
  final base = result.snackbarMessage(fileName);
  final msg = result.ok && successExtra != null && successExtra.isNotEmpty ? '$successExtra — $base' : base;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg),
      backgroundColor: result.ok
          ? Colors.green
          : (result.outcome == CrossPlatformSaveOutcome.cancelled ? Colors.orange : Colors.red),
      duration: const Duration(seconds: 6),
    ),
  );
}
