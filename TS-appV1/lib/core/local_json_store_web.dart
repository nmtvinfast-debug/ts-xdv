import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

String _prefKey(String fileName) => 'ts_xdv_local_${fileName.replaceAll('/', '_')}';

Future<bool> localJsonExists(String fileName) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.containsKey(_prefKey(fileName));
}

Future<String?> readLocalJson(String fileName) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_prefKey(fileName));
}

Future<bool> writeLocalJson(String fileName, String content) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.setString(_prefKey(fileName), content);
}

Future<dynamic> readLocalJsonDecoded(String fileName) async {
  final raw = await readLocalJson(fileName);
  if (raw == null || raw.trim().isEmpty) return null;
  return jsonDecode(raw);
}
