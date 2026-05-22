import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import 'pick_file_bytes_io.dart' if (dart.library.html) 'pick_file_bytes_stub.dart';

/// Đọc bytes từ kết quả FilePicker (web: f.bytes; desktop: path hoặc bytes).
Future<Uint8List?> bytesFromPickerFile(PlatformFile f) async {
  if (f.bytes != null && f.bytes!.isNotEmpty) {
    return f.bytes is Uint8List ? f.bytes! : Uint8List.fromList(f.bytes!);
  }
  if (!kIsWeb && f.path != null && f.path!.isNotEmpty) {
    return readPathBytes(f.path!);
  }
  return null;
}
