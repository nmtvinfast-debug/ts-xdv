import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/auth_models.dart';
import '../models/kt_tracking_entry.dart';
import '../services/api_service.dart';
import 'ke_toan_debt_types.dart';
import 'payment_info.dart';
import 'workshop_local_sync.dart';



/// Lưu theo dõi BH / VinFast / công nợ (file `ke_toan_tracking.json` cùng thư mục chạy app).

class KeToanTrackingStore extends ChangeNotifier {

  static const String fileName = 'ke_toan_tracking.json';

  ApiService? _api;
  String? _token;

  void configure({ApiService? api, String? token}) {
    _api = api;
    _token = token;
  }



  static const List<(String key, String label)> categories = [

    ('all', 'Tất cả BH / nợ / VinFast'),

    ('debt_insurance', 'Bảo hiểm thanh toán (I)'),

    ('warranty_vinfast', 'Bảo hành VinFast (W)'),

    ('debt_gsm', 'Công nợ GSM (tất cả)'),

    ('debt_gsm_bao_duong', 'GSM · Bảo dưỡng'),

    ('debt_gsm_thay_the_pt', 'GSM · Thay thế PT'),

    ('debt_gsm_son', 'GSM · Sơn'),

    ('debt_gsm_khac', 'GSM · Khác'),

    ('debt_other', 'Công nợ khác'),

  ];



  List<KtTrackingEntry> _all = [];

  bool loading = false;



  /// Sau khi thu tiền có BH/nợ/VinFast — panel chọn danh mục này.

  String focusCategoryKey = 'debt_insurance';



  List<KtTrackingEntry> get all => List.unmodifiable(_all);



  Future<void> load() async {

    loading = true;

    notifyListeners();

    try {
      final data = await loadWorkshopJson(
        fileName: fileName,
        api: _api,
        token: _token,
      );
      if (data is List) {
        _all = data.map((e) => KtTrackingEntry.fromJson(Map<String, dynamic>.from(e as Map))).toList();
        _backfillInsuranceDebtCreditors();
      } else {
        _all = [];
      }
    } catch (e) {

      debugPrint('KeToanTrackingStore.load: $e');

      _all = [];

    } finally {

      loading = false;

      notifyListeners();

    }

  }



  Future<void> save() async {

    try {
      await saveWorkshopJson(
        fileName: fileName,
        payload: _all.map((e) => e.toJson()).toList(),
        api: _api,
        token: _token,
      );
    } catch (e) {

      debugPrint('KeToanTrackingStore.save: $e');

      rethrow;

    }

    notifyListeners();

  }



  /// Thêm / cập nhật dòng theo dõi từ phiếu RO sau khi Kế toán xác nhận thu (phần C).

  Future<void> ingestFromRepairOrder(

    WorkOrderItem order,

    PaymentBreakdown pay, {

    DebtPaidClassification? debtClassification,

  }) async {

    final roId = order.id;

    final bien = order.bienSo;

    final ro = order.roCode;

    final cvdv = order.cvdvUsername;



    if (pay.insurancePay > 0) {
      final bhName = resolveInsuranceCompanyName(
            pay: pay,
            customerNote: order.customerNote,
          ) ??
          '';

      await _upsertOpen(

        repairOrderId: roId,

        categoryKey: 'debt_insurance',

        payerKind: 'insurance',

        title: 'Đối soát BH — $bien',

        reference: ro,

        bienSo: bien,

        roCode: ro,

        amount: pay.insurancePay,

        note: bhName.isEmpty ? 'CVDV: $cvdv' : 'CVDV: $cvdv · $bhName',

        debtCreditor: bhName,

      );

      focusCategoryKey = 'debt_insurance';

    }

    if (pay.warrantyPay > 0) {

      await _upsertOpen(

        repairOrderId: roId,

        categoryKey: 'warranty_vinfast',

        payerKind: 'warranty',

        title: 'Thanh toán VinFast (W) — $bien',

        reference: ro,

        bienSo: bien,

        roCode: ro,

        amount: pay.warrantyPay,

        note: 'CVDV: $cvdv · Chờ quyết toán bảo hành VinFast',

      );

      focusCategoryKey = 'warranty_vinfast';

    }

    if (pay.debt > 0) {

      var catKey = 'debt_other';

      var creditor = '';

      var gsmType = '';

      if (debtClassification != null) {

        final probe = KtTrackingEntry(id: '_', categoryKey: catKey);

        debtClassification.applyTo(probe, appendTitleTag: false);

        catKey = probe.categoryKey;

        creditor = probe.debtCreditor;

        gsmType = probe.gsmDebtType;

        focusCategoryKey = catKey.startsWith('debt_gsm') ? catKey : 'debt_other';

      } else if (pay.insurancePay <= 0 && pay.warrantyPay <= 0) {

        focusCategoryKey = 'debt_other';

      }

      await _upsertOpen(

        repairOrderId: roId,

        categoryKey: catKey,

        payerKind: 'debt',

        title: 'Công nợ — $bien',

        reference: ro,

        bienSo: bien,

        roCode: ro,

        amount: pay.debt,

        note: 'CVDV: $cvdv',

        debtCreditor: creditor,

        gsmDebtType: gsmType,

      );

      if (debtClassification != null) {

        final idx = _all.indexWhere(

          (e) => e.repairOrderId == roId && e.payerKind == 'debt' && e.status != 'done',

        );

        if (idx >= 0) {

          debtClassification.applyTo(_all[idx]);

        }

      }

    }



    await save();

  }



  Future<void> _upsertOpen({

    required String repairOrderId,

    required String categoryKey,

    required String payerKind,

    required String title,

    required String reference,

    required String bienSo,

    required String roCode,

    required double amount,

    required String note,

    String debtCreditor = '',

    String gsmDebtType = '',

  }) async {

    final idx = _all.indexWhere(

      (e) =>

          e.repairOrderId == repairOrderId &&

          e.payerKind == payerKind &&

          e.status != 'done',

    );

    if (idx >= 0) {

      final e = _all[idx];

      e.categoryKey = categoryKey;

      e.title = title;

      e.reference = reference;

      e.bienSo = bienSo;

      e.roCode = roCode;

      e.amount = amount;

      e.note = note;

      e.payerKind = payerKind;

      if (debtCreditor.isNotEmpty) e.debtCreditor = debtCreditor;

      if (gsmDebtType.isNotEmpty) e.gsmDebtType = gsmDebtType;

      e.updatedAt = DateTime.now().toIso8601String();

      return;

    }

    _all.insert(

      0,

      KtTrackingEntry(

        id: '${DateTime.now().millisecondsSinceEpoch}_$payerKind',

        categoryKey: categoryKey,

        repairOrderId: repairOrderId,

        bienSo: bienSo,

        roCode: roCode,

        payerKind: payerKind,

        title: title,

        reference: reference,

        amount: amount,

        note: note,

        status: 'open',

        debtCreditor: debtCreditor,

        gsmDebtType: gsmDebtType,

      ),

    );

  }



  List<KtTrackingEntry> query({

    required bool paidTab,

    required String categoryKey,

    required String searchQuery,

  }) {

    final q = searchQuery.trim().toLowerCase();

    return _all.where((e) {

      if (!_isTrackableCategory(e.categoryKey)) return false;

      final isPaid = e.status == 'done';

      if (paidTab != isPaid) return false;

      if (!trackingMatchesCategoryFilter(e, categoryKey)) return false;

      if (q.isEmpty) return true;

      final hay =

          '${e.title} ${e.reference} ${e.bienSo} ${e.roCode} ${e.note} ${e.payerKind} ${e.debtCreditor} ${e.gsmDebtType}'

              .toLowerCase();

      return hay.contains(q);

    }).toList()

      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  }



  void _backfillInsuranceDebtCreditors() {
    var changed = false;
    for (final e in _all) {
      if (e.categoryKey != 'debt_insurance' && e.payerKind != 'insurance') continue;
      if (e.debtCreditor.isNotEmpty) continue;
      final name = insuranceCompanyFromTrackingNote(e.note);
      if (name == null || name.isEmpty) continue;
      e.debtCreditor = name;
      changed = true;
    }
    if (changed) {
      save().catchError((err) => debugPrint('KeToanTrackingStore backfill: $err'));
    }
  }

  bool _isTrackableCategory(String key) {

    if (key.startsWith('debt_gsm')) return true;

    return key == 'debt_insurance' || key == 'warranty_vinfast' || key == 'debt_other';

  }



  Future<void> markPaid(

    List<String> entryIds, {

    DebtPaidClassification? debtClassification,

  }) async {

    final now = DateTime.now().toIso8601String();

    for (final e in _all) {

      if (!entryIds.contains(e.id)) continue;

      if (trackingEntryIsDebt(e) && debtClassification != null) {

        debtClassification.applyTo(e);

      }

      e.status = 'done';

      e.updatedAt = now;

    }

    await save();

  }



  String exportCsv(List<KtTrackingEntry> rows) {

    final buf = StringBuffer();

    buf.writeln(

      'Danh_muc,Ben_no,Loai_GSM,Tieu_de,Bien_so,Ma_RO,Tham_chieu,So_tien,Trang_thai,Han,Ghi_chu,Cap_nhat',

    );

    for (final e in rows) {

      final catLabel = trackingCategoryLabel(

        e.categoryKey,

        debtCreditor: e.debtCreditor,

        gsmDebtType: e.gsmDebtType,

      );

      buf.writeln([

        _csv(catLabel),

        _csv(
          e.debtCreditor.isEmpty
              ? '—'
              : (e.categoryKey == 'debt_insurance' || e.payerKind == 'insurance'
                  ? e.debtCreditor
                  : DebtCreditor.label(e.debtCreditor)),
        ),

        _csv(e.gsmDebtType.isEmpty ? '—' : GsmDebtType.label(e.gsmDebtType)),

        _csv(e.title),

        _csv(e.bienSo),

        _csv(e.roCode),

        _csv(e.reference),

        e.amount.toStringAsFixed(0),

        _csv(e.status == 'done' ? 'Đã thanh toán' : 'Chưa thanh toán'),

        _csv(e.dueDate),

        _csv(e.note),

        _csv(e.updatedAt),

      ].join(','));

    }

    return buf.toString();

  }



  static String _csv(String s) {

    final t = s.replaceAll('"', '""');

    return '"$t"';

  }

}



/// Chỉ thu tại quầy KH — không còn BH / VinFast / công nợ.

bool paymentIsCustomerOnly(PaymentBreakdown pay) {

  return pay.insurancePay <= 0 && pay.warrantyPay <= 0 && pay.debt <= 0;

}

