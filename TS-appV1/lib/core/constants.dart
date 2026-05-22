import 'package:flutter/material.dart';

// ==========================================
// 1. CẤU HÌNH MẠNG & HỆ THỐNG
// ==========================================
class AppConfig {
  /// Chỉ host (không có `/api/v1`) — dùng cho LoginResult + ApiService.
  static const String serverOrigin = String.fromEnvironment(
    'TS_SERVER_ORIGIN',
    defaultValue: 'https://ts-server.fly.dev',
  );

  /// Giữ tương thích code cũ dùng `AppConfig.baseUrl` (đã gồm `/api/v1`).
  static String get baseUrl => '$serverOrigin/api/v1';

  static const String appName = "TS-XDV AUTO SERVICE";
}

// ==========================================
// 2. HỆ THỐNG MÀU SẮC GIAO DIỆN CHUẨN
// ==========================================
class AppColors {
  static const Color primary = Color(0xFF1E40AF); // Xanh đậm chuyên nghiệp
  static const Color secondary = Color(0xFF3B82F6); 
  static const Color background = Color(0xFFF1F5F9); // Xám sáng mượt mà
  static const Color surface = Colors.white;
  static const Color textMain = Color(0xFF0F172A);
  static const Color textMuted = Color(0xFF64748B);
  
  // Màu cảnh báo SLA (Theo Rule TV Dashboard)
  static const Color statusNormal = Color(0xFF22C55E); // Xanh lá: Bình thường / Đang sửa
  static const Color statusWarning = Color(0xFFEAB308); // Vàng: Sắp trễ / Chờ đợi
  static const Color statusDanger = Color(0xFFEF4444); // Đỏ: Trễ hạn / Dừng lâu / Lỗi
  static const Color statusPayment = Color(0xFFA855F7); // Tím: Chờ thanh toán
}

// ==========================================
// 3. ĐỊNH NGHĨA VAI TRÒ (ROLES)
// ==========================================
class AppRoles {
  static const String admin = "ADMIN";
  static const String giamDoc = "GIAMDOC";
  static const String cvdv = "CVDV";
  static const String quanDoc = "QUANDOC";
  static const String ktv = "KTV";
  static const String kho = "KHO";
  static const String keToan = "KETOAN";
  static const String cskh = "CSKH";
  static const String baoVe = "BAOVE";
  static const String khachHang = "KHACHHANG";
  /// Màn hình tiếp đón / bảng điện tử xưởng (read-only board).
  static const String tv = "TV";
}

// ==========================================
// 4. LÝ DO DỪNG SỬA CHỮA (RULE 4)
// ==========================================
class PauseReasons {
  static const String choPhuTung = "CHO_PHU_TUNG";
  static const String choKhachHang = "CHO_KH";
  static const String choBaoHiem = "CHO_BAO_HIEM";
  static const String khac = "KHAC";

  static String getDisplayName(String reasonCode) {
    switch (reasonCode) {
      case choPhuTung: return "Chờ phụ tùng";
      case choKhachHang: return "Chờ KH quyết định";
      case choBaoHiem: return "Chờ bảo hiểm duyệt";
      default: return "Lý do khác";
    }
  }
}

// ==========================================
// 5. HỆ THỐNG TRẠNG THÁI RO / XE (RULE 2 & TV DASHBOARD)
// ==========================================
enum RoStatus {
  XE_VAO_XUONG,
  CHO_BAO_GIA,
  CHO_KH_DUYET,
  CHO_PHAN_CONG,
  CHO_SUA_CHUA,
  DANG_SUA,
  DUNG_SUA,
  CHO_PHU_TUNG,
  DA_SUA_XONG,
  CHO_QUYET_TOAN,
  DA_THANH_TOAN,
  XE_RA_XUONG
}

// Extension này giúp tự động dịch Enum thành Tiếng Việt và lấy màu tương ứng cho giao diện
extension RoStatusExtension on RoStatus {
  String get displayName {
    switch (this) {
      case RoStatus.XE_VAO_XUONG: return "Xe vào xưởng";
      case RoStatus.CHO_BAO_GIA: return "Chờ báo giá";
      case RoStatus.CHO_KH_DUYET: return "Chờ KH duyệt";
      case RoStatus.CHO_PHAN_CONG: return "Chờ phân công";
      case RoStatus.CHO_SUA_CHUA: return "Chờ sửa chữa";
      case RoStatus.DANG_SUA: return "Đang sửa chữa";
      case RoStatus.DUNG_SUA: return "Đang dừng sửa";
      case RoStatus.CHO_PHU_TUNG: return "Chờ phụ tùng";
      case RoStatus.DA_SUA_XONG: return "Đã sửa xong";
      case RoStatus.CHO_QUYET_TOAN: return "Chờ quyết toán";
      case RoStatus.DA_THANH_TOAN: return "Đã thanh toán";
      case RoStatus.XE_RA_XUONG: return "Xe ra xưởng";
    }
  }

  Color get color {
    switch (this) {
      case RoStatus.XE_VAO_XUONG:
      case RoStatus.CHO_PHAN_CONG:
      case RoStatus.CHO_SUA_CHUA:
        return AppColors.secondary; // Xanh dương
      
      case RoStatus.DANG_SUA:
        return AppColors.statusNormal; // Xanh lá
      
      case RoStatus.CHO_BAO_GIA:
      case RoStatus.CHO_KH_DUYET:
      case RoStatus.CHO_PHU_TUNG:
      case RoStatus.DUNG_SUA:
        return AppColors.statusWarning; // Vàng / Cam (Cần chú ý)
        
      case RoStatus.CHO_QUYET_TOAN:
      case RoStatus.DA_THANH_TOAN:
        return AppColors.statusPayment; // Tím (Liên quan đến tiền)
        
      case RoStatus.DA_SUA_XONG:
      case RoStatus.XE_RA_XUONG:
        return Colors.grey;
    }
  }
}

// ==========================================
// 6. SLA THỜI GIAN CHUẨN (Tính bằng Phút)
// ==========================================
class SlaRules {
  static const int timeToQuote = 30; // Chờ báo giá <= 30p
  static const int timeToAssign = 15; // Chờ phân công <= 15p
  static const int timeToStartRepair = 30; // Chờ bắt đầu sửa <= 30p
  static const int timeToSettle = 30; // Chờ quyết toán <= 30p
  static const int timeToExit = 15; // Đã thanh toán -> ra cổng <= 15p
}