import 'dart:convert';

/// Phân bổ nguồn thanh toán CVDV nhập (C / I / W / công nợ).
class PaymentBreakdown {
  const PaymentBreakdown({
    this.customerPay = 0,
    this.insurancePay = 0,
    this.warrantyPay = 0,
    this.debt = 0,
    this.grandTotal = 0,
    this.insuranceCompany,
  });

  final double customerPay;
  final double insurancePay;
  final double warrantyPay;
  final double debt;
  final double grandTotal;
  final String? insuranceCompany;

  bool get hasAny =>
      customerPay > 0 || insurancePay > 0 || warrantyPay > 0 || debt > 0;
}

PaymentBreakdown parsePaymentInfo(dynamic raw) {
  if (raw == null) return const PaymentBreakdown();
  Map<String, dynamic> m;
  if (raw is String) {
    final t = raw.trim();
    if (t.isEmpty || t == 'null') return const PaymentBreakdown();
    try {
      m = Map<String, dynamic>.from(jsonDecode(t) as Map);
    } catch (_) {
      return const PaymentBreakdown();
    }
  } else if (raw is Map) {
    m = Map<String, dynamic>.from(raw);
  } else {
    return const PaymentBreakdown();
  }

  double pick(List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString().replaceAll(RegExp(r'[,\s]'), '')) ?? 0;
    }
    return 0;
  }

  final company = m['insurance_company']?.toString() ?? m['insuranceCompany']?.toString();
  return PaymentBreakdown(
    customerPay: pick(['customer_pay', 'customerPay', 'customer', 'c', 'kh']),
    insurancePay: pick(['insurance_pay', 'insurancePay', 'insurance', 'i', 'bh']),
    warrantyPay: pick(['warranty_pay', 'warrantyPay', 'warranty', 'vinfast_pay', 'vinfast', 'w']),
    debt: pick(['debt', 'cong_no', 'debt_pay']),
    grandTotal: pick(['grand_total', 'grandTotal', 'total']),
    insuranceCompany: (company != null && company.trim().isNotEmpty) ? company.trim() : null,
  );
}

Map<String, dynamic> buildPaymentInfoPayload({
  required double customerPay,
  required double insurancePay,
  required double warrantyPay,
  required double debt,
  required double grandTotal,
  String? insuranceCompany,
}) {
  return {
    'customer_pay': customerPay.round(),
    'insurance_pay': insurancePay.round(),
    'warranty_pay': warrantyPay.round(),
    'debt': debt.round(),
    'grand_total': grandTotal.round(),
    if (insuranceCompany != null && insuranceCompany.trim().isNotEmpty)
      'insurance_company': insuranceCompany.trim(),
  };
}

String formatPayAmount(double value) {
  if (value <= 0) return '0';
  return value
      .round()
      .toString()
      .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
}

/// Hãng BH CVDV ghi trong ghi chú: `[BH: Bảo Việt]`.
String? parseInsuranceCompanyFromBhTag(String? text) {
  if (text == null || text.trim().isEmpty) return null;
  final m = RegExp(r'\[BH:\s*([^\]]+)\]', caseSensitive: false).firstMatch(text);
  final s = m?.group(1)?.trim();
  return (s != null && s.isNotEmpty) ? s : null;
}

/// Tên BH trong dòng theo dõi kế toán: `CVDV: user · Bảo Việt`.
String? insuranceCompanyFromTrackingNote(String note) {
  final t = note.trim();
  if (t.isEmpty) return null;
  final m = RegExp(r'CVDV:\s*\S+\s*·\s*(.+)$', caseSensitive: false).firstMatch(t);
  final s = m?.group(1)?.trim();
  return (s != null && s.isNotEmpty) ? s : null;
}

/// Ưu tiên payment_info, sau đó ghi chú RO (customer_note / urgent).
String? resolveInsuranceCompanyName({
  PaymentBreakdown? pay,
  String? customerNote,
}) {
  final fromPay = pay?.insuranceCompany?.trim();
  if (fromPay != null && fromPay.isNotEmpty) return fromPay;
  return parseInsuranceCompanyFromBhTag(customerNote);
}
