/// Dòng theo dõi nội bộ trên màn Kế toán (lưu file `ke_toan_tracking.json`).

class KtTrackingEntry {

  final String id;

  String categoryKey;

  String title;

  String reference;

  double amount;

  String dueDate;

  String note;

  /// `open` = chưa thanh toán · `done` = đã thanh toán

  String status;

  String flowKind;

  String updatedAt;



  String repairOrderId;

  String bienSo;

  String roCode;

  /// insurance | warranty | debt

  String payerKind;



  /// gsm | insurance | customer | other — sau khi phân loại công nợ

  String debtCreditor;

  /// bao_duong | thay_the_pt | son | khac — chỉ khi [debtCreditor] == gsm

  String gsmDebtType;



  KtTrackingEntry({

    required this.id,

    required this.categoryKey,

    this.title = '',

    this.reference = '',

    this.amount = 0,

    this.dueDate = '',

    this.note = '',

    this.status = 'open',

    this.flowKind = '',

    String? updatedAt,

    this.repairOrderId = '',

    this.bienSo = '',

    this.roCode = '',

    this.payerKind = '',

    this.debtCreditor = '',

    this.gsmDebtType = '',

  }) : updatedAt = updatedAt ?? DateTime.now().toIso8601String();



  Map<String, dynamic> toJson() => {

        'id': id,

        'categoryKey': categoryKey,

        'title': title,

        'reference': reference,

        'amount': amount,

        'dueDate': dueDate,

        'note': note,

        'status': status,

        'flowKind': flowKind,

        'updatedAt': updatedAt,

        'repairOrderId': repairOrderId,

        'bienSo': bienSo,

        'roCode': roCode,

        'payerKind': payerKind,

        'debtCreditor': debtCreditor,

        'gsmDebtType': gsmDebtType,

      };



  factory KtTrackingEntry.fromJson(Map<String, dynamic> json) {

    double amt = 0;

    final raw = json['amount'];

    if (raw is num) {

      amt = raw.toDouble();

    } else if (raw != null) {

      amt = double.tryParse(raw.toString()) ?? 0;

    }

    return KtTrackingEntry(

      id: json['id']?.toString() ?? '',

      categoryKey: json['categoryKey']?.toString() ?? 'debt_other',

      title: json['title']?.toString() ?? '',

      reference: json['reference']?.toString() ?? '',

      amount: amt,

      dueDate: json['dueDate']?.toString() ?? '',

      note: json['note']?.toString() ?? '',

      status: json['status']?.toString() ?? 'open',

      flowKind: json['flowKind']?.toString() ?? '',

      updatedAt: json['updatedAt']?.toString(),

      repairOrderId: json['repairOrderId']?.toString() ?? '',

      bienSo: json['bienSo']?.toString() ?? '',

      roCode: json['roCode']?.toString() ?? '',

      payerKind: json['payerKind']?.toString() ?? '',

      debtCreditor: json['debtCreditor']?.toString() ?? '',

      gsmDebtType: json['gsmDebtType']?.toString() ?? '',

    );

  }

}

