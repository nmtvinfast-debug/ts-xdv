import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show PlatformDispatcher;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'cross_platform_file_save_types.dart';

bool get _isMobile => Platform.isAndroid || Platform.isIOS;

String _ensureExtension(String fileName, String? ext) {
  if (ext == null || ext.isEmpty) return fileName;
  final dot = '.$ext';
  if (fileName.toLowerCase().endsWith(dot)) return fileName;
  return '$fileName$dot';
}

/// Vị trí neo hộp chia sẻ trên iPad (tránh crash).
Rect? anchorShareOrigin() {
  try {
    final views = PlatformDispatcher.instance.views;
    if (views.isEmpty) return null;
    final view = views.first;
    final logical = view.physicalSize / view.devicePixelRatio;
    return Rect.fromLTWH(logical.width / 2, logical.height / 2, 1, 1);
  } catch (_) {
    return null;
  }
}

Future<CrossPlatformSaveResult> saveTextContent({
  required String content,
  required String fileName,
  String? dialogTitle,
}) async {
  return saveBytesContent(
    bytes: Uint8List.fromList(utf8.encode(content)),
    fileName: _ensureExtension(fileName, 'txt'),
    dialogTitle: dialogTitle ?? 'Lưu báo cáo',
    mimeType: 'text/plain',
    allowedExtensions: const ['txt'],
  );
}

Future<CrossPlatformSaveResult> saveBytesContent({
  required Uint8List bytes,
  required String fileName,
  String? dialogTitle,
  String? mimeType,
  List<String>? allowedExtensions,
}) async {
  final name = allowedExtensions != null && allowedExtensions.isNotEmpty
      ? _ensureExtension(fileName, allowedExtensions.first)
      : fileName;

  if (_isMobile) {
    try {
      final xf = XFile.fromData(
        bytes,
        name: name,
        mimeType: mimeType ?? 'application/octet-stream',
      );
      final result = await Share.shareXFiles(
        [xf],
        subject: dialogTitle,
        sharePositionOrigin: anchorShareOrigin(),
      );
      if (result.status == ShareResultStatus.dismissed) {
        return const CrossPlatformSaveResult(CrossPlatformSaveOutcome.cancelled);
      }
      return const CrossPlatformSaveResult(CrossPlatformSaveOutcome.shared);
    } catch (e) {
      return CrossPlatformSaveResult(CrossPlatformSaveOutcome.failed, e.toString());
    }
  }

  try {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: dialogTitle ?? 'Lưu file',
      fileName: name,
      type: allowedExtensions != null ? FileType.custom : FileType.any,
      allowedExtensions: allowedExtensions,
    );
    if (path == null) {
      return const CrossPlatformSaveResult(CrossPlatformSaveOutcome.cancelled);
    }
    final out = allowedExtensions != null && allowedExtensions.isNotEmpty
        ? _ensureExtension(path, allowedExtensions.first)
        : path;
    await File(out).writeAsBytes(bytes, flush: true);
    return CrossPlatformSaveResult(CrossPlatformSaveOutcome.saved, out);
  } catch (e) {
    return CrossPlatformSaveResult(CrossPlatformSaveOutcome.failed, e.toString());
  }
}
