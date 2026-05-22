import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../services/api_service.dart';
import 'local_json_store.dart';

/// Ánh xạ tên file local ↔ khóa API `/workshop-data/:key`.
const Map<String, String> kWorkshopDataKeys = {
  'kho_db.json': 'kho_db',
  'kho_history.json': 'kho_history',
  'uom_db.json': 'uom_db',
  'staff_db.json': 'staff_db',
  'ke_toan_tracking.json': 'ke_toan_tracking',
};

String? workshopApiKeyForFile(String fileName) => kWorkshopDataKeys[fileName];

/// Đọc JSON: ưu tiên server (cùng dữ liệu Windows/Web), cache local/prefs.
Future<dynamic> loadWorkshopJson({
  required String fileName,
  ApiService? api,
  String? token,
}) async {
  final apiKey = workshopApiKeyForFile(fileName);
  if (api != null && token != null && token.isNotEmpty && apiKey != null) {
    try {
      final remote = await api.fetchWorkshopData(token, apiKey);
      if (remote != null) {
        await writeLocalJson(fileName, jsonEncode(remote));
        return remote;
      }
    } catch (e) {
      debugPrint('loadWorkshopJson server $fileName: $e');
    }
  }
  return readLocalJsonDecoded(fileName);
}

/// Ghi JSON: local + đẩy lên server khi có token.
Future<void> saveWorkshopJson({
  required String fileName,
  required dynamic payload,
  ApiService? api,
  String? token,
}) async {
  final encoded = jsonEncode(payload);
  await writeLocalJson(fileName, encoded);
  final apiKey = workshopApiKeyForFile(fileName);
  if (api != null && token != null && token.isNotEmpty && apiKey != null) {
    try {
      await api.saveWorkshopData(token, apiKey, payload);
    } catch (e) {
      debugPrint('saveWorkshopJson server $fileName: $e');
    }
  }
}

/// Tải danh sách tồn kho dạng `List<Map>` (dùng CVDV kiểm tra PT).
Future<List<Map<String, dynamic>>> loadKhoInventoryMaps({
  ApiService? api,
  String? token,
}) async {
  final data = await loadWorkshopJson(
    fileName: 'kho_db.json',
    api: api,
    token: token,
  );
  if (data is List) {
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
  return [];
}
