import '../models/kt_tracking_entry.dart';

/// Phân loại công nợ khi Kế toán đánh dấu «đã thanh toán» / theo dõi.

class DebtCreditor {
  static const gsm = 'gsm';
  static const insurance = 'insurance';
  static const other = 'other';
  static const customer = 'customer';

  static const List<(String key, String label)> options = [
    (gsm, 'Công nợ GSM (VinFast)'),
    (insurance, 'Công nợ / đối soát Bảo hiểm'),
    (customer, 'Công nợ Khách hàng'),
    (other, 'Công nợ đối tác khác'),
  ];

  static String label(String? key) {
    for (final o in options) {
      if (o.$1 == key) return o.$2;
    }
    return key ?? '—';
  }
}

class GsmDebtType {
  static const baoDuong = 'bao_duong';
  static const thayThePt = 'thay_the_pt';
  static const son = 'son';
  static const khac = 'khac';

  static const List<(String key, String label)> options = [
    (baoDuong, 'Công nợ Bảo dưỡng'),
    (thayThePt, 'Công nợ thay thế phụ tùng'),
    (son, 'Công nợ Sơn'),
    (khac, 'Công nợ khác (GSM)'),
  ];

  static String label(String? key) {
    for (final o in options) {
      if (o.$1 == key) return o.$2;
    }
    return key ?? '—';
  }

  static String categoryKeyFor(String gsmType) => 'debt_gsm_$gsmType';
}

/// Kết quả hộp thoại phân loại công nợ.
class DebtPaidClassification {
  final String creditor;
  final String? gsmType;

  const DebtPaidClassification({required this.creditor, this.gsmType});

  void applyTo(KtTrackingEntry entry, {bool appendTitleTag = true}) {
    entry.debtCreditor = creditor;
    entry.gsmDebtType = creditor == DebtCreditor.gsm ? (gsmType ?? GsmDebtType.khac) : '';
    entry.categoryKey = _categoryKeyForEntry();
    if (!appendTitleTag) return;
    final ben = DebtCreditor.label(creditor);
    final sub = creditor == DebtCreditor.gsm && gsmType != null ? ' · ${GsmDebtType.label(gsmType)}' : '';
    final tag = '[$ben$sub]';
    if (!entry.title.contains(tag)) {
      entry.title = '${entry.title.trim()} $tag'.trim();
    }
  }

  String _categoryKeyForEntry() {
    switch (creditor) {
      case DebtCreditor.gsm:
        return GsmDebtType.categoryKeyFor(gsmType ?? GsmDebtType.khac);
      case DebtCreditor.insurance:
        return 'debt_insurance';
      case DebtCreditor.customer:
      case DebtCreditor.other:
      default:
        return 'debt_other';
    }
  }
}

bool trackingEntryIsDebt(KtTrackingEntry e) {
  if (e.payerKind == 'debt') return true;
  if (e.categoryKey.startsWith('debt_gsm')) return true;
  return e.categoryKey == 'debt_other' || e.categoryKey == 'debt_gsm';
}

String trackingCategoryLabel(String categoryKey, {String? debtCreditor, String? gsmDebtType}) {
  if (categoryKey.startsWith('debt_gsm_')) {
    final t = categoryKey.replaceFirst('debt_gsm_', '');
    return GsmDebtType.label(t);
  }
  if (categoryKey == 'debt_gsm' && gsmDebtType != null && gsmDebtType.isNotEmpty) {
    return GsmDebtType.label(gsmDebtType);
  }
  switch (categoryKey) {
    case 'debt_insurance':
      return 'Bảo hiểm thanh toán (I)';
    case 'warranty_vinfast':
      return 'Bảo hành VinFast (W)';
    case 'debt_gsm':
      return 'Công nợ GSM (chưa phân loại chi tiết)';
    case 'debt_other':
      if (debtCreditor != null && debtCreditor.isNotEmpty) {
        return DebtCreditor.label(debtCreditor);
      }
      return 'Công nợ khác';
    default:
      return categoryKey;
  }
}

bool trackingMatchesCategoryFilter(KtTrackingEntry e, String filterKey) {
  if (filterKey == 'all') return true;
  if (filterKey == 'debt_gsm') {
    return e.categoryKey.startsWith('debt_gsm') || e.categoryKey == 'debt_gsm';
  }
  return e.categoryKey == filterKey;
}
