import 'constants.dart';
import 'time_format.dart';

/// "Đang chờ gì" theo trạng thái RO (đặc tả board Giám đốc / Time Rules).
String waitingBriefForStatus(String status, {bool customerWaiting = false}) {
  final st = normalizeRepairOrderStatus(status);
  if (customerWaiting) return 'Khách đang chờ tại xưởng';
  switch (st) {
    case 'XE_VAO_XUONG':
      return 'Chờ CSKH / CVDV tiếp nhận';
    case 'CHO_BAO_GIA':
      return 'Chờ báo giá (SLA ${formatDurationVnFromMinutes(SlaRules.timeToQuote)})';
    case 'CHO_KH_DUYET':
      return 'Chờ khách duyệt báo giá';
    case 'CHO_PHAN_CONG':
      return 'Chờ Quản đốc phân công KTV';
    case 'CHO_SUA_CHUA':
      return 'Chờ KTV bắt đầu sửa';
    case 'DANG_SUA':
      return 'Đang sửa chữa';
    case 'DUNG_SUA':
    case 'CHO_PHU_TUNG':
      return 'Tạm dừng / chờ phụ tùng hoặc KH';
    case 'CHO_QD_KIEM_TRA':
      return 'Chờ quản đốc kiểm tra';
    case 'CHO_CVDV_CHOT':
      return 'Chờ CVDV chốt trước kế toán';
    case 'CHO_QUYET_TOAN':
      return 'Chờ quyết toán (SLA ${formatDurationVnFromMinutes(SlaRules.timeToSettle)})';
    case 'HUY_CHO_QUYET_TOAN':
      return 'Chờ Kế toán xác nhận cho ra xưởng (KH hủy / từ chối báo giá)';
    case 'KT_DUYET_RA_CONG':
      return 'Kế toán đã duyệt — chờ Bảo vệ cho ra cổng';
    case 'DA_THANH_TOAN':
      return 'Đã thanh toán — chờ ra cổng';
    case 'DA_RA_CONG':
    case 'DA_RA_CONG_THIEU_PT':
    case 'XE_RA_XUONG':
      return 'Đã / sắp ra xưởng';
    case 'KH_TU_CHOI':
      return 'Chờ Kế toán xác nhận cho ra xưởng (từ chối báo giá — phiếu cũ)';
    default:
      return 'Đang xử lý';
  }
}

/// Chuẩn hóa mã trạng thái RO từ API (khoảng trắng, gạch ngang, hoa/thường).
String normalizeRepairOrderStatus(String? raw) {
  if (raw == null) return '';
  var s = raw.trim();
  if (s.isEmpty) return '';
  s = s.replaceAll(RegExp(r'[\s\-]+'), '_');
  while (s.contains('__')) {
    s = s.replaceAll('__', '_');
  }
  return s.toUpperCase();
}

/// Trạng thái RO đã ra / kết thúc luồng trong xưởng (đồng bộ logic nút gọi KH).
bool vehicleStatusIndicatesOutsideWorkshop(String status) {
  const outside = {
    'DA_RA_CONG',
    'DA_RA_CONG_THIEU_PT',
    'XE_RA_XUONG',
    'HUY',
  };
  return outside.contains(status.trim().toUpperCase());
}

/// Tab «Đã ra xưởng / lịch sử» trên app KH — phiếu không còn trong luồng xử lý tại xưởng.
bool repairOrderStatusKhArchiveTab(String status) {
  const archive = {
    'DA_RA_CONG',
    'DA_RA_CONG_THIEU_PT',
    'XE_RA_XUONG',
    'HUY',
  };
  return archive.contains(normalizeRepairOrderStatus(status));
}

bool _looksLikeRoStatusToken(String s) {
  final t = s.trim();
  if (t.isEmpty || t.length > 48) return false;
  return RegExp(r'^[A-Z0-9_]+$').hasMatch(t.toUpperCase());
}

/// Nhãn ngắn cho mã trạng thái RO (khi hiện trong dòng gợi ý xe).
String roStatusTokenLabelVi(String code) {
  switch (code.trim().toUpperCase()) {
    case 'XE_VAO_XUONG':
      return 'Mới vào xưởng';
    case 'CHO_BAO_GIA':
      return 'Chờ báo giá';
    case 'CHO_KH_DUYET':
      return 'Chờ duyệt báo giá';
    case 'CHO_PHAN_CONG':
      return 'Chờ phân công KTV';
    case 'CHO_SUA_CHUA':
      return 'Chờ KTV bắt đầu sửa';
    case 'DANG_SUA':
      return 'Đang sửa chữa';
    case 'DUNG_SUA':
    case 'CHO_PHU_TUNG':
      return 'Tạm dừng / chờ phụ tùng';
    case 'CHO_QD_KIEM_TRA':
      return 'Chờ nghiệm thu';
    case 'CHO_CVDV_CHOT':
      return 'Chờ CVDV chốt';
    case 'CHO_QUYET_TOAN':
      return 'Chờ quyết toán';
    case 'HUY_CHO_QUYET_TOAN':
      return 'Đã hủy — chờ kế toán';
    case 'KT_DUYET_RA_CONG':
      return 'Được phép ra cổng';
    case 'DA_THANH_TOAN':
      return 'Đã thanh toán';
    case 'DA_RA_CONG':
      return 'Đã xuất xưởng';
    case 'DA_RA_CONG_THIEU_PT':
      return 'Ra xưởng — thiếu phụ tùng';
    case 'XE_RA_XUONG':
      return 'Xe ra xưởng';
    case 'KH_TU_CHOI':
      return 'Khách từ chối báo giá';
    case 'HUY':
      return 'Đã hủy';
    default:
      return code.replaceAll('_', ' ');
  }
}

/// Dòng «công việc / gợi ý xe» trên app KH: không lặp `status`; bỏ qua mã «đã ra» nếu RO vẫn trong xưởng (tránh nhập nhầm `vehicle_activity`).
String? vehicleActivityLineForKh(String activity, String orderStatus) {
  final raw = activity.trim();
  if (raw.isEmpty) return null;
  final act = raw.toUpperCase();
  final st = orderStatus.trim().toUpperCase();
  if (act == st) return null;
  if (_looksLikeRoStatusToken(raw)) {
    if (vehicleStatusIndicatesOutsideWorkshop(act) && !vehicleStatusIndicatesOutsideWorkshop(st)) {
      return null;
    }
    return roStatusTokenLabelVi(act);
  }
  return raw;
}
