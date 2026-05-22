import '../core/ro_display.dart';
import '../core/time_format.dart';

class LoginResult {
  final String token;
  final String baseUrl;
  final String userName;
  final String role; // ĐÃ THÊM: Sửa lỗi màn hình Đăng nhập (No named parameter 'role')

  LoginResult({
    required this.token,
    required this.baseUrl,
    required this.userName,
    this.role = '', // Mặc định là chuỗi rỗng để không bị lỗi với các code cũ
  });
}

class WorkOrderItem {
  final String id;
  final String roCode;
  final String bienSo;
  final String status;
  final String customerName;
  final String customerPhone;
  final String cvdvUsername;
  final String ktvUsername;
  final String position;
  final String customerNote;
  final String linkRequestedBy;
  final String linkedCustomer;

  /// Mã WO do CVDV nhập (ưu tiên gửi KHO / đối chiếu tồn); rỗng thì dùng [roCode] hệ thống.
  final String cvdvWoCode;
  /// Gợi ý “xe đang làm gì” (hiển thị trên danh sách biển số); rỗng thì hiển thị theo trạng thái lệnh.
  final String vehicleActivityNote;
  /// Thời điểm KTV xác nhận đã xác định nguyên nhân lỗi (server: fault_diagnosis_at).
  final DateTime? faultDiagnosisAt;
  /// Phút từ mốc time_start / time_assign (server: ktv_inspection_elapsed_minutes).
  final int? ktvInspectionElapsedMinutes;
  
  // FIX LỖI: Đã xóa chữ 'final' ở các biến này để cho phép UI cập nhật tin nhắn tạm thời
  dynamic jobs;
  dynamic parts;
  dynamic chatLogs;
  dynamic images; // ĐÃ THÊM: Biến này dùng để lưu ảnh do bảo vệ chụp
  /// Nguồn thanh toán CVDV (JSON: customer_pay, insurance_pay, …).
  dynamic paymentInfo;
  
  final DateTime? createdAt;
  /// Từ server (Time Rules): phút ở trạng thái hiện tại
  final int? minutesInState;
  final bool customerWaiting;
  dynamic auditHistory;

  final String? cvdvPhone;

  WorkOrderItem({
    required this.id, required this.roCode, required this.bienSo, required this.status,
    required this.customerName, required this.customerPhone, required this.cvdvUsername, required this.ktvUsername,
    required this.position, required this.customerNote, required this.linkRequestedBy,
    required this.linkedCustomer,
    this.cvdvWoCode = '',
    this.vehicleActivityNote = '',
    this.faultDiagnosisAt,
    this.ktvInspectionElapsedMinutes,
    this.jobs, this.parts, this.chatLogs, this.images, this.paymentInfo, this.createdAt,
    this.minutesInState, this.customerWaiting = false, this.auditHistory,
    this.cvdvPhone,
  });

  /// Hiển thị "đã chờ" — ưu tiên `minutes_in_state` từ server; luôn dạng ngày/giờ/phút.
  String get waitDisplayShort {
    if (minutesInState != null) return formatDurationVnFromMinutes(minutesInState!);
    if (createdAt == null) return '-';
    return formatWaitSinceDateTime(createdAt, ifNull: '-');
  }

  factory WorkOrderItem.fromJson(Map<String, dynamic> json) {
    int? mi;
    final rawM = json['minutes_in_state'];
    if (rawM is int) mi = rawM;
    else if (rawM is num) mi = rawM.toInt();
    bool cw = false;
    final rawCw = json['customer_waiting'];
    if (rawCw is bool) cw = rawCw;
    else if (rawCw is String) cw = rawCw.toLowerCase() == 'true';

    return WorkOrderItem(
      id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
      roCode: json['ro_code']?.toString() ?? '',
      bienSo: json['bien_so']?.toString() ?? '',
      status: normalizeRepairOrderStatus(json['status']?.toString()),
      customerName: json['customer_name']?.toString() ?? '',
      customerPhone: json['customer_phone']?.toString() ?? '',
      cvdvUsername: json['cvdv_username']?.toString() ?? '',
      ktvUsername: json['ktv_username']?.toString() ?? '',
      position: json['position']?.toString() ?? json['customer_note']?.toString() ?? '',
      customerNote: json['customer_note']?.toString() ?? '',
      linkRequestedBy: json['link_requested_by']?.toString() ?? '',
      linkedCustomer: json['linked_customer']?.toString() ?? '',
      cvdvWoCode: json['cvdv_wo_code']?.toString() ?? json['wo_code_manual']?.toString() ?? '',
      vehicleActivityNote:
          json['vehicle_activity']?.toString() ?? json['vehicle_activity_note']?.toString() ?? '',
      faultDiagnosisAt: json['fault_diagnosis_at'] != null ? DateTime.tryParse(json['fault_diagnosis_at'].toString()) : null,
      ktvInspectionElapsedMinutes: () {
        final raw = json['ktv_inspection_elapsed_minutes'];
        if (raw is int) return raw;
        if (raw is num) return raw.toInt();
        return null;
      }(),
      jobs: json['jobs'],
      parts: json['parts'],
      chatLogs: json['chat_logs'],
      images: json['images'], // Map mảng ảnh từ máy chủ trả về
      paymentInfo: json['payment_info'],
      createdAt: json['time_in'] != null 
          ? DateTime.tryParse(json['time_in'].toString()) 
          : (json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null),
      minutesInState: mi,
      customerWaiting: cw,
      auditHistory: json['audit_history'],
      cvdvPhone: json['cvdv_phone']?.toString() ?? json['cvdvPhone']?.toString(),
    );
  }
}

class BookingItem {
  final String id;
  final String customerName;
  final String? customerPhone;
  final String? carModel;
  final String bienSo;
  final String time;
  final String? note;
  final String status;

  BookingItem({
    required this.id, required this.customerName, this.customerPhone, this.carModel,
    required this.bienSo, required this.time, this.note, required this.status,
  });

  factory BookingItem.fromJson(Map<String, dynamic> json) {
    return BookingItem(
      id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
      customerName: json['customer_name']?.toString() ?? '',
      customerPhone: json['customer_phone']?.toString(),
      carModel: json['car_model']?.toString(),
      bienSo: json['bien_so']?.toString() ?? '',
      time: json['time']?.toString() ?? '',
      note: json['note']?.toString(),
      status: json['status']?.toString() ?? '',
    );
  }
}

class UserItem {
  final String id;
  final String username;
  final String fullName;
  final String role;
  final bool isActive;
  final String? xdvId;
  /// SĐT nhân viên (Giám đốc nhập khi tạo TK).
  final String? phone;
  final DateTime? createdAt;
  final DateTime? lastLoginAt;

  // Cầu nối dữ liệu cho các file cũ (Kho, Kế toán)
  String get name => fullName;

  UserItem({
    required this.id, required this.username, required this.fullName,
    required this.role, required this.isActive, this.xdvId, this.phone,
    this.createdAt, this.lastLoginAt,
  });

  factory UserItem.fromJson(Map<String, dynamic> json) {
    return UserItem(
      id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      fullName: json['name']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      isActive: () {
        final ia = json['is_active'];
        if (ia is bool) return ia;
        if (ia is String) return ia.toLowerCase() == 'true';
        return true;
      }(),
      xdvId: json['xdv_id']?.toString(),
      phone: json['phone']?.toString(),
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
      lastLoginAt: json['last_login_at'] != null ? DateTime.tryParse(json['last_login_at'].toString()) : null,
    );
  }
}