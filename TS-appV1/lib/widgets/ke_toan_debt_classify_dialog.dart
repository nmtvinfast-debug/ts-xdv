import 'package:flutter/material.dart';

import '../core/ke_toan_debt_types.dart';

/// Hộp thoại chọn bên công nợ; nếu GSM thì chọn thêm loại (BD / PT / Sơn / Khác).
Future<DebtPaidClassification?> showDebtPaidClassificationDialog(
  BuildContext context, {
  int debtLineCount = 1,
}) async {
  String? creditor;
  String? gsmType;

  return showDialog<DebtPaidClassification>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isGsm = creditor == DebtCreditor.gsm;

          return AlertDialog(
            title: const Text('Phân loại công nợ', style: TextStyle(fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      debtLineCount == 1
                          ? 'Chọn công nợ của bên nào trước khi chuyển sang «Đã thanh toán».'
                          : 'Đang đánh dấu $debtLineCount dòng công nợ — chọn bên nợ áp dụng cho tất cả các dòng đã chọn.',
                      style: TextStyle(fontSize: 14, color: Colors.blueGrey.shade800, height: 1.35),
                    ),
                    const SizedBox(height: 16),
                    const Text('Công nợ của bên nào?', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ...DebtCreditor.options.map(
                      (o) => RadioListTile<String>(
                        dense: true,
                        title: Text(o.$2, style: const TextStyle(fontSize: 14)),
                        value: o.$1,
                        groupValue: creditor,
                        onChanged: (v) => setDialogState(() {
                          creditor = v;
                          if (v != DebtCreditor.gsm) gsmType = null;
                        }),
                      ),
                    ),
                    if (isGsm) ...[
                      const Divider(height: 24),
                      const Text(
                        'Loại công nợ GSM',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                      ),
                      const SizedBox(height: 8),
                      ...GsmDebtType.options.map(
                        (o) => RadioListTile<String>(
                          dense: true,
                          title: Text(o.$2, style: const TextStyle(fontSize: 14)),
                          value: o.$1,
                          groupValue: gsmType,
                          onChanged: (v) => setDialogState(() => gsmType = v),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
              FilledButton(
                onPressed: () {
                  if (creditor == null) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Vui lòng chọn bên công nợ.'), backgroundColor: Colors.orange),
                    );
                    return;
                  }
                  if (creditor == DebtCreditor.gsm && (gsmType == null || gsmType!.isEmpty)) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        content: Text('Với công nợ GSM, vui lòng chọn loại: Bảo dưỡng / PT / Sơn / Khác.'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                    return;
                  }
                  Navigator.pop(
                    ctx,
                    DebtPaidClassification(creditor: creditor!, gsmType: gsmType),
                  );
                },
                child: const Text('Xác nhận đã thanh toán'),
              ),
            ],
          );
        },
      );
    },
  );
}
