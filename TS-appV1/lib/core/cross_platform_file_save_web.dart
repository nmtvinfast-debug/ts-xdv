import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import 'cross_platform_file_save_types.dart';

void _triggerDownload(Uint8List bytes, String fileName, String? mimeType) {
  final blob = html.Blob([bytes], mimeType ?? 'application/octet-stream');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..style.display = 'none'
    ..download = fileName;
  html.document.body?.children.add(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}

Future<CrossPlatformSaveResult> saveTextContent({
  required String content,
  required String fileName,
  String? dialogTitle,
}) async {
  final name = fileName.endsWith('.txt') ? fileName : '$fileName.txt';
  _triggerDownload(Uint8List.fromList(utf8.encode(content)), name, 'text/plain;charset=utf-8');
  return const CrossPlatformSaveResult(CrossPlatformSaveOutcome.downloaded);
}

Future<CrossPlatformSaveResult> saveBytesContent({
  required Uint8List bytes,
  required String fileName,
  String? dialogTitle,
  String? mimeType,
  List<String>? allowedExtensions,
}) async {
  _triggerDownload(bytes, fileName, mimeType);
  return const CrossPlatformSaveResult(CrossPlatformSaveOutcome.downloaded);
}
