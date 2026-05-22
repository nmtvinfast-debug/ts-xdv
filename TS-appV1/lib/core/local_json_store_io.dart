import 'dart:convert';
import 'dart:io';

Future<bool> localJsonExists(String fileName) async {
  try {
    return await File(fileName).exists();
  } catch (_) {
    return false;
  }
}

Future<String?> readLocalJson(String fileName) async {
  try {
    final file = File(fileName);
    if (!await file.exists()) return null;
    return await file.readAsString();
  } catch (_) {
    return null;
  }
}

Future<bool> writeLocalJson(String fileName, String content) async {
  try {
    await File(fileName).writeAsString(content);
    return true;
  } catch (_) {
    return false;
  }
}

Future<dynamic> readLocalJsonDecoded(String fileName) async {
  final raw = await readLocalJson(fileName);
  if (raw == null || raw.trim().isEmpty) return null;
  return jsonDecode(raw);
}
