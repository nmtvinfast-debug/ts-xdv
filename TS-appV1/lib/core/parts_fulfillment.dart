import 'dart:convert';

/// Có ít nhất một dòng phụ tùng trên báo giá với SL > 0.
bool quotedPartsNeedWarehouseIssue(dynamic partsRaw) {
  final list = _parsePartsList(partsRaw);
  for (final raw in list) {
    if (raw is! Map) continue;
    final p = Map<String, dynamic>.from(raw);
    final qty = num.tryParse('${p['qty'] ?? p['hours'] ?? 0}') ?? 0;
    if (qty > 0) return true;
  }
  return false;
}

/// RO đã đủ phát/xuất PT theo báo giá (issuedQty >= qty mọi dòng có SL>0).
bool allQuotedPartsFullyIssued(dynamic partsRaw) {
  final list = _parsePartsList(partsRaw);
  if (list.isEmpty) return false;

  var anyPositive = false;
  for (final raw in list) {
    if (raw is! Map) continue;
    final p = Map<String, dynamic>.from(raw);
    final qty = num.tryParse('${p['qty'] ?? p['hours'] ?? 0}') ?? 0;
    if (qty <= 0) continue;
    anyPositive = true;
    final issued = num.tryParse('${p['issuedQty'] ?? p['issued_qty'] ?? 0}') ?? 0;
    if (issued < qty) return false;
  }
  return anyPositive;
}

/// Đủ điều kiện chuyển kế toán về phụ tùng: không có PT trên BG, hoặc Kho đã xuất đủ SL báo giá.
bool repairOrderPartsReadyForSettlement(dynamic partsRaw) {
  if (!quotedPartsNeedWarehouseIssue(partsRaw)) return true;
  return allQuotedPartsFullyIssued(partsRaw);
}

List<dynamic> _parsePartsList(dynamic partsRaw) {
  if (partsRaw == null) return [];
  if (partsRaw is String) {
    final t = partsRaw.trim();
    if (t.isEmpty || t == 'null' || t == '[]') return [];
    try {
      return List<dynamic>.from(jsonDecode(t) as List);
    } catch (_) {
      return [];
    }
  }
  if (partsRaw is List) return List<dynamic>.from(partsRaw);
  return [];
}

/// Số lượt xuất kho đã ghi trên RO (theo mã PT).
Map<String, num> issuedQtyByPartCode(dynamic partsRaw) {
  final out = <String, num>{};
  for (final raw in _parsePartsList(partsRaw)) {
    if (raw is! Map) continue;
    final p = Map<String, dynamic>.from(raw);
    final code = p['code']?.toString().trim().toLowerCase() ?? '';
    if (code.isEmpty) continue;
    final issued = num.tryParse('${p['issuedQty'] ?? p['issued_qty'] ?? 0}') ?? 0;
    out[code] = issued;
  }
  return out;
}

String? notificationDataType(Map<String, dynamic> n) {
  final raw = n['data'];
  if (raw is Map) return raw['type']?.toString();
  if (raw is String) {
    try {
      final m = jsonDecode(raw);
      if (m is Map) return m['type']?.toString();
    } catch (_) {}
  }
  return null;
}

bool notificationIsUnread(Map<String, dynamic> n) {
  final r = n['read_at'];
  return r == null || (r is String && r.trim().isEmpty);
}
