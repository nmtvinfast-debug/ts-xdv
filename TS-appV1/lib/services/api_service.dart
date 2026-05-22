import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../models/auth_models.dart';
import '../models/company_chat_message.dart';
import '../core/constants.dart';
import '../core/api_base.dart';

class ApiService {
  final String baseUrl;

  ApiService({required this.baseUrl});

  Uri _v1(String path) => Uri.parse(joinApiV1(baseUrl, path));

  /// Header Authorization — token từ login là `auth_token_<id>` (không kèm chữ Bearer).
  static Map<String, String> authHeaders(String token, {Map<String, String>? extra}) {
    final t = token.trim();
    final bearer = t.toLowerCase().startsWith('bearer ') ? t : 'Bearer $t';
    return {'Authorization': bearer, if (extra != null) ...extra};
  }

  /// Fly scale-to-zero / cold start: 502–504 có thể hết sau vài giây — thử lại.
  Future<http.Response> _getWithRetry(
    Uri uri, {
    Map<String, String>? headers,
    int maxAttempts = 5,
  }) async {
    const retryStatuses = {502, 503, 504};
    Object? lastErr;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final res = await http
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 60));
        if (retryStatuses.contains(res.statusCode) && attempt < maxAttempts) {
          await Future<void>.delayed(Duration(seconds: 2 * attempt));
          continue;
        }
        return res;
      } on TimeoutException catch (e) {
        lastErr = e;
        if (attempt < maxAttempts) {
          await Future<void>.delayed(Duration(seconds: 2 * attempt));
          continue;
        }
        rethrow;
      } catch (e) {
        if (_isTransientNetworkError(e) && attempt < maxAttempts) {
          lastErr = e;
          await Future<void>.delayed(Duration(seconds: 2 * attempt));
          continue;
        }
        rethrow;
      }
    }
    throw Exception('Không kết nối được máy chủ sau $maxAttempts lần thử${lastErr != null ? ': $lastErr' : ''}');
  }

  static bool _isTransientNetworkError(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('socket') ||
        s.contains('connection') ||
        s.contains('failed host lookup') ||
        s.contains('network is unreachable') ||
        s.contains('clientexception');
  }

  /// Dữ liệu xưởng đồng bộ (kho, uom, staff…) — Web dùng chung với Windows.
  Future<dynamic> fetchWorkshopData(String token, String key) async {
    final res = await _getWithRetry(
      _v1('/workshop-data/$key'),
      headers: authHeaders(token),
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    throw Exception('Lỗi tải dữ liệu $key: HTTP ${res.statusCode}');
  }

  Future<void> saveWorkshopData(String token, String key, dynamic payload) async {
    final res = await http.put(
      _v1('/workshop-data/$key'),
      headers: {
        ...authHeaders(token),
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    throw Exception('Lỗi lưu dữ liệu $key: ${res.body}');
  }

  Future<WorkOrderItem> fetchRepairOrder(String token, String id) async {
    final json = await fetchRepairOrderJson(token, id);
    return WorkOrderItem.fromJson(json);
  }

  /// JSON đầy đủ phiếu RO (audit, pauses, mốc thời gian, ảnh…).
  Future<Map<String, dynamic>> fetchRepairOrderJson(String token, String id) async {
    final res = await _getWithRetry(
      _v1('/repair-orders/$id'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (res.statusCode == 200) {
      return Map<String, dynamic>.from(jsonDecode(res.body) as Map);
    }
    throw Exception('Không tải được phiếu RO: HTTP ${res.statusCode}');
  }

  Future<List<WorkOrderItem>> fetchBoard(String token) async {
    final res = await _getWithRetry(
      _v1('/repair-orders'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (res.statusCode == 200) {
      final List data = jsonDecode(res.body);
      return data.map((e) => WorkOrderItem.fromJson(e as Map<String, dynamic>)).toList();
    }
    if (res.statusCode == 502 || res.statusCode == 503 || res.statusCode == 504) {
      throw Exception(
        'Máy chủ chưa sẵn sàng (HTTP ${res.statusCode}). '
        'Đợi ~30 giây rồi bấm Làm mới. Nếu vẫn lỗi: kiểm tra Fly (fly status, fly logs) hoặc deploy lại ts-server.',
      );
    }
    final detail = res.body.isEmpty ? '(body trống)' : res.body;
    throw Exception('Lỗi tải danh sách xe — HTTP ${res.statusCode}: $detail');
  }

  Future<Map<String, dynamic>> fetchDashboardSummary(String token) async {
    final res = await http.get(_v1('/dashboard/summary'), headers: {'Authorization': 'Bearer $token'});
    if (res.statusCode == 200) {
      return Map<String, dynamic>.from(jsonDecode(res.body) as Map);
    }
    throw Exception('Lỗi tải dashboard: ${res.body}');
  }

  Future<Map<String, dynamic>> fetchWorkshopSettings(String token) async {
    final res = await http.get(_v1('/settings/workshop'), headers: {'Authorization': 'Bearer $token'});
    if (res.statusCode == 200) {
      return Map<String, dynamic>.from(jsonDecode(res.body) as Map);
    }
    throw Exception('Lỗi tải cấu hình xưởng: ${res.body}');
  }

  /// Upload ảnh banner QC (ADMIN) — trả về `image_url` dạng `/uploads/kh_ads/...`.
  Future<String> uploadKhAdBannerImage({
    required String token,
    required List<int> imageBytes,
    String filename = 'banner.jpg',
  }) async {
    final uri = _v1('/settings/kh-ads/upload-image');
    final req = http.MultipartRequest('POST', uri);
    req.headers['Authorization'] = 'Bearer $token';
    req.headers['Accept'] = 'application/json';
    req.files.add(http.MultipartFile.fromBytes('image', imageBytes, filename: filename));
    final streamed = await req.send().timeout(const Duration(seconds: 90));
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode == 201 || res.statusCode == 200) {
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      return (map['image_url'] ?? '').toString();
    }
    throw Exception(res.body);
  }

  Future<Map<String, dynamic>> patchWorkshopSettings(
    String token,
    Map<String, dynamic> workshopDefaults,
  ) async {
    final res = await http.patch(
      _v1('/settings/workshop'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'workshop_defaults': workshopDefaults}),
    );
    if (res.statusCode == 200) {
      return Map<String, dynamic>.from(jsonDecode(res.body) as Map);
    }
    throw Exception('Lỗi lưu cấu hình: ${res.body}');
  }

  Future<int> fetchCompanyChatUnreadCount(String token) async {
    final res = await http.get(
      _v1('/company-chat/messages/unread-count'),
      headers: authHeaders(token),
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return (data['unread'] as num?)?.toInt() ?? 0;
    }
    return 0;
  }

  Future<void> markCompanyChatRead(String token) async {
    final res = await http.post(
      _v1('/company-chat/messages/mark-read'),
      headers: authHeaders(token),
    );
    if (res.statusCode != 200) {
      throw Exception('Lỗi đánh dấu đã đọc chat: ${res.body}');
    }
  }

  Future<List<CompanyChatMessage>> fetchCompanyMessages(String token, {String? since}) async {
    var path = '/company-chat/messages?limit=200';
    if (since != null && since.isNotEmpty) {
      path += '&since=${Uri.encodeComponent(since)}';
    }
    final res = await http.get(
      _v1(path),
      headers: authHeaders(token),
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final list = data['messages'] as List<dynamic>? ?? [];
      return list.map((e) => CompanyChatMessage.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    }
    if (res.statusCode == 403) {
      throw Exception('Không có quyền xem chat công ty (vai trò hoặc xưởng).');
    }
    throw Exception('Lỗi tải chat công ty: ${res.body}');
  }

  Future<CompanyChatMessage> postCompanyMessage(String token, String body) async {
    final res = await http.post(
      _v1('/company-chat/messages'),
      headers: authHeaders(token, extra: {'Content-Type': 'application/json'}),
      body: jsonEncode({'body': body}),
    );
    if (res.statusCode == 201) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return CompanyChatMessage.fromJson(Map<String, dynamic>.from(data['message'] as Map));
    }
    throw Exception('Lỗi gửi tin: ${res.body}');
  }

  Future<double> recordKhAdImpression(String token, String adId) async {
    final res = await http.post(
      _v1('/company-chat/kh-ads/impression'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'ad_id': adId}),
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return (data['revenue_vnd'] as num?)?.toDouble() ?? 0;
    }
    throw Exception('Lỗi ghi nhận lượt xem QC: ${res.body}');
  }

  Future<double> recordKhAdClick(String token, String adId) async {
    final res = await http.post(
      _v1('/company-chat/kh-ads/click'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'ad_id': adId}),
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return (data['revenue_vnd'] as num?)?.toDouble() ?? 0;
    }
    throw Exception('Lỗi ghi nhận lượt click QC: ${res.body}');
  }

  /// Trả về `stats`, `summary`, `rates` từ server.
  Future<Map<String, dynamic>> fetchKhAdStats(String token) async {
    final res = await http.get(
      _v1('/company-chat/kh-ads/stats'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (res.statusCode == 200) {
      return Map<String, dynamic>.from(jsonDecode(res.body) as Map);
    }
    throw Exception('Lỗi thống kê QC: ${res.body}');
  }

  Future<List<UserItem>> fetchUsers(String token) async {
    final res = await http.get(_v1('/users'), headers: authHeaders(token));
    if (res.statusCode == 200) {
      final List data = jsonDecode(res.body);
      return data.map((e) => UserItem.fromJson(e as Map<String, dynamic>)).toList();
    }
    throw Exception('Lỗi tải danh sách nhân sự');
  }

  /// SĐT nhân sự (staff_db + users) — dùng cho KH «Gọi CVDV» (không cần quyền /users).
  Future<List<Map<String, dynamic>>> fetchDialContacts(String token) async {
    final res = await _getWithRetry(
      _v1('/users/dial-contacts'),
      headers: authHeaders(token),
    );
    if (res.statusCode == 200) {
      final List data = jsonDecode(res.body);
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    throw Exception('Lỗi tải số liên hệ: ${res.body}');
  }

  /// CVDV hoạt động — CSKH phân công xe (không cần staff_db.json).
  Future<List<UserItem>> fetchAssignableCvdv(String token) async {
    final res = await http.get(
      _v1('/users/assignable-cvdv'),
      headers: authHeaders(token),
    );
    if (res.statusCode == 200) {
      final List data = jsonDecode(res.body);
      return data.map((e) => UserItem.fromJson(e as Map<String, dynamic>)).toList();
    }
    throw Exception('Lỗi tải danh sách CVDV: ${res.body}');
  }

  /// KTV hoạt động — dùng cho Quản đốc phân công (không cần quyền list users đầy đủ).
  Future<List<UserItem>> fetchAssignableKtv(String token) async {
    final res = await http.get(
      _v1('/users/assignable-ktv'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (res.statusCode == 200) {
      final List data = jsonDecode(res.body);
      return data.map((e) => UserItem.fromJson(e as Map<String, dynamic>)).toList();
    }
    throw Exception('Lỗi tải danh sách KTV');
  }

  Future<UserItem> createUser({
    required String token,
    required String username,
    required String password,
    required String name,
    required String role,
    String? xdvId,
    String? phone,
  }) async {
    final body = <String, dynamic>{
      'username': username,
      'password': password,
      'name': name,
      'role': role,
      if (xdvId != null && xdvId.isNotEmpty) 'xdv_id': xdvId,
      if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
    };
    final res = await http.post(
      _v1('/users'),
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (res.statusCode == 201) {
      return UserItem.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
    }
    throw Exception(res.body);
  }

  Future<UserItem> updateUser({
    required String token,
    required String id,
    String? name,
    String? role,
    String? password,
    String? xdvId,
    String? phone,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (role != null) body['role'] = role;
    if (password != null && password.isNotEmpty) body['password'] = password;
    if (xdvId != null) body['xdv_id'] = xdvId;
    if (phone != null) body['phone'] = phone.trim();
    final res = await http.patch(
      _v1('/users/$id'),
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (res.statusCode == 200) {
      return UserItem.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
    }
    throw Exception(res.body);
  }

  /// API dùng DELETE để đảo trạng thái is_active (khóa / mở khóa).
  Future<Map<String, dynamic>> toggleUserActive(String token, String id) async {
    final res = await http.delete(_v1('/users/$id'), headers: {'Authorization': 'Bearer $token'});
    if (res.statusCode == 200) {
      return Map<String, dynamic>.from(jsonDecode(res.body) as Map);
    }
    throw Exception(res.body);
  }

  Future<List<BookingItem>> fetchBookings(String token) async {
    final res = await http.get(_v1('/bookings'), headers: {'Authorization': 'Bearer $token'});
    if (res.statusCode == 200) {
      final List data = jsonDecode(res.body);
      return data.map((e) => BookingItem.fromJson(e as Map<String, dynamic>)).toList();
    }
    throw Exception('Lỗi tải lịch hẹn');
  }

  Future<void> updateRepairOrder({
    required String token,
    required String id,
    required String status,
    String? cvdvUsername,
    String? ktvUsername,
    String? statusNote,
    String? jobs,
    String? parts,
    String? chatLogs,
    String? linkedCustomer,
    String? linkRequestedBy,
    String? pauseReason,
    String? cvdvWoCode,
    String? vehicleActivity,
    String? faultDiagnosisAtIso,
    Map<String, dynamic>? paymentInfo,
  }) async {
    Map<String, dynamic> body = {'status': status};
    if (cvdvUsername != null) body['cvdv_username'] = cvdvUsername;
    if (ktvUsername != null) body['ktv_username'] = ktvUsername;
    if (statusNote != null) body['customer_note'] = statusNote;
    if (jobs != null) body['jobs'] = jsonDecode(jobs);
    if (parts != null) body['parts'] = jsonDecode(parts);
    if (chatLogs != null) body['chat_logs'] = jsonDecode(chatLogs);
    if (linkedCustomer != null) body['linked_customer'] = linkedCustomer;
    if (linkRequestedBy != null) body['link_requested_by'] = linkRequestedBy;
    if (pauseReason != null && pauseReason.isNotEmpty) body['pause_reason'] = pauseReason;
    if (cvdvWoCode != null) body['cvdv_wo_code'] = cvdvWoCode;
    if (vehicleActivity != null) body['vehicle_activity'] = vehicleActivity;
    if (faultDiagnosisAtIso != null) body['fault_diagnosis_at'] = faultDiagnosisAtIso;
    if (paymentInfo != null) body['payment_info'] = paymentInfo;

    final uri = _v1('/repair-orders/$id');
    final headers = {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
    final encoded = jsonEncode(body);

    http.Response res = await http.patch(uri, headers: headers, body: encoded);
    if (res.statusCode != 200) {
      final bodyLower = res.body.toLowerCase();
      final tryPut = res.statusCode == 405 ||
          res.statusCode == 501 ||
          bodyLower.contains('cannot patch') ||
          bodyLower.contains('method not allowed');
      if (tryPut) {
        res = await http.put(uri, headers: headers, body: encoded);
      }
    }
    if (res.statusCode != 200) {
      Object? apiErr;
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map && decoded['error'] != null) apiErr = decoded['error'];
      } catch (_) {}
      throw Exception(apiErr?.toString() ?? res.body);
    }
  }

  Future<List<Map<String, dynamic>>> fetchNotifications(String token) async {
    final res = await http.get(_v1('/notifications'), headers: {'Authorization': 'Bearer $token'});
    if (res.statusCode == 200) {
      final List data = jsonDecode(res.body);
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    throw Exception(res.body);
  }

  Future<void> markNotificationRead(String token, String notificationId) async {
    final res = await http.patch(
      _v1('/notifications/$notificationId/read'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (res.statusCode != 200) throw Exception(res.body);
  }

  /// Kho gọi sau khi cập nhật parts — server báo CVDV (xe trong xưởng) hoặc gửi tin app KH (DA_RA_CONG_THIEU_PT).
  Future<Map<String, dynamic>> postPartArrivalNotify({
    required String token,
    required String orderId,
  }) async {
    final res = await http.post(
      _v1('/repair-orders/$orderId/part-arrival-notify'),
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
    );
    if (res.statusCode == 200) {
      return Map<String, dynamic>.from(jsonDecode(res.body) as Map);
    }
    throw Exception(res.body);
  }

  /// Xuất phiếu Excel theo mẫu `ts-server/templates` (lenh_sua_chua, quyet_toan, …).
  Future<List<int>> downloadRepairOrderDocument({
    required String token,
    required String repairOrderId,
    required String templateKey,
  }) async {
    final res = await _getWithRetry(
      _v1('/documents/export/$templateKey/$repairOrderId'),
      headers: authHeaders(token),
      maxAttempts: 3,
    );
    if (res.statusCode == 200) return res.bodyBytes;
    Object? apiErr;
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map && decoded['error'] != null) apiErr = decoded['error'];
    } catch (_) {}
    throw Exception(apiErr?.toString() ?? 'HTTP ${res.statusCode}: ${res.body}');
  }

  Future<List<Map<String, dynamic>>> fetchMaintenanceReminders({
    required String token,
    String? phone,
  }) async {
    var path = '/extras/maintenance-reminders';
    if (phone != null && phone.trim().isNotEmpty) {
      path += '?phone=${Uri.encodeQueryComponent(phone.trim())}';
    }
    final res = await _getWithRetry(_v1(path), headers: authHeaders(token));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final list = data['reminders'];
      if (list is List) {
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    }
    throw Exception('Lỗi tải nhắc bảo dưỡng: ${res.body}');
  }

  Future<Map<String, dynamic>> fetchInvoiceTracking({required String token}) async {
    final res = await _getWithRetry(
      _v1('/extras/invoice-tracking'),
      headers: authHeaders(token),
    );
    if (res.statusCode == 200) {
      return Map<String, dynamic>.from(jsonDecode(res.body) as Map);
    }
    throw Exception('Lỗi tải theo dõi hóa đơn: ${res.body}');
  }

  Future<Map<String, dynamic>> uploadInvoicePartsFile({
    required String token,
    required List<int> bytes,
    required String filename,
  }) async {
    final uri = _v1('/extras/invoice-tracking/upload');
    final req = http.MultipartRequest('POST', uri);
    req.headers.addAll(authHeaders(token));
    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await req.send().timeout(const Duration(seconds: 120));
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode == 200) {
      return Map<String, dynamic>.from(jsonDecode(res.body) as Map);
    }
    throw Exception('Lỗi upload file PT: ${res.body}');
  }

  Future<Map<String, dynamic>> markInvoiceIssued({
    required String token,
    required String repairOrderId,
    String? username,
  }) async {
    final res = await http.post(
      _v1('/extras/invoice-tracking/mark-issued/$repairOrderId'),
      headers: {
        ...authHeaders(token),
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'username': username ?? ''}),
    );
    if (res.statusCode == 200) {
      return Map<String, dynamic>.from(jsonDecode(res.body) as Map);
    }
    throw Exception('Lỗi đánh dấu đã xuất HĐ: ${res.body}');
  }

  Future<List<int>> downloadInvoiceVehicleExcel({
    required String token,
    required String repairOrderId,
  }) async {
    final res = await _getWithRetry(
      _v1('/extras/invoice-tracking/export/$repairOrderId'),
      headers: authHeaders(token),
    );
    if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
      return res.bodyBytes;
    }
    throw Exception('Lỗi xuất Excel theo dõi HĐ: ${res.body}');
  }

  /// OCR ảnh phiếu xuất — multipart field `image`, trả về `{ text }`.
  Future<String> ocrStockSlip({
    required String token,
    required List<int> imageBytes,
    String filename = 'slip.jpg',
  }) async {
    final uri = _v1('/ocr/stock-slip');
    final req = http.MultipartRequest('POST', uri);
    req.headers['Authorization'] = 'Bearer $token';
    req.headers['Accept'] = 'application/json';
    req.files.add(http.MultipartFile.fromBytes('image', imageBytes, filename: filename));
    final streamed = await req.send().timeout(const Duration(seconds: 120));
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode == 200) {
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      return (map['text'] ?? '').toString().trim();
    }
    throw Exception(res.body);
  }

  Future<void> createBooking({required String token, required Map<String, dynamic> data}) async {
    final res = await http.post(
      _v1('/bookings'),
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
    if (res.statusCode != 201 && res.statusCode != 200) throw Exception(res.body);
  }

  Future<void> deleteBooking({required String token, required String id}) async {
    final res = await http.delete(
      _v1('/bookings/$id'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (res.statusCode != 200) throw Exception(res.body);
  }

  /// Cập nhật lịch hẹn (CSKH duyệt / từ chối).
  /// Thử PATCH → PUT; nếu máy chủ không hỗ trợ (Express «Cannot PATCH») và có [recreateOnMethodFailure]
  /// thì xóa bản ghi cũ và POST lại (cùng nội dung + trạng thái mới).
  Future<void> updateBooking({
    required String token,
    required String id,
    String? status,
    String? note,
    String? customerName,
    String? customerPhone,
    String? carModel,
    String? time,
    Map<String, dynamic>? recreateOnMethodFailure,
  }) async {
    final body = <String, dynamic>{};
    if (status != null) body['status'] = status;
    if (note != null) body['note'] = note;
    if (customerName != null) body['customer_name'] = customerName;
    if (customerPhone != null) body['customer_phone'] = customerPhone;
    if (carModel != null) body['car_model'] = carModel;
    if (time != null) body['time'] = time;
    if (body.isEmpty && recreateOnMethodFailure == null) {
      throw Exception('Không có trường cập nhật cho lịch hẹn.');
    }

    final headers = {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
    final uri = _v1('/bookings/$id');

    bool ok(http.Response r) => r.statusCode == 200 || r.statusCode == 204;

    bool looksLikeMethodNotRegistered(http.Response r) {
      if (r.statusCode == 404 || r.statusCode == 405) return true;
      final b = r.body;
      if (b.contains('<!DOCTYPE') && (b.contains('Cannot PATCH') || b.contains('Cannot PUT'))) return true;
      return false;
    }

    String errMsg(http.Response r) {
      final b = r.body;
      if (b.contains('<!DOCTYPE') || b.contains('<html')) {
        return 'Máy chủ từ chối cập nhật lịch hẹn (${r.statusCode}). Cần bật PATCH/PUT bookings trên API hoặc dùng chế độ tạo lại.';
      }
      return b.isNotEmpty ? b : 'HTTP ${r.statusCode}';
    }

    var res = await http.patch(uri, headers: headers, body: jsonEncode(body));
    if (ok(res)) return;
    if (!looksLikeMethodNotRegistered(res)) throw Exception(errMsg(res));

    res = await http.put(uri, headers: headers, body: jsonEncode(body));
    if (ok(res)) return;
    if (!looksLikeMethodNotRegistered(res)) throw Exception(errMsg(res));

    if (recreateOnMethodFailure != null) {
      await deleteBooking(token: token, id: id);
      final data = Map<String, dynamic>.from(recreateOnMethodFailure);
      if (status != null) data['status'] = status;
      if (note != null) data['note'] = note;
      if (customerName != null) data['customer_name'] = customerName;
      if (customerPhone != null) data['customer_phone'] = customerPhone;
      if (carModel != null) data['car_model'] = carModel;
      if (time != null) data['time'] = time;
      await createBooking(token: token, data: data);
      return;
    }

    throw Exception(errMsg(res));
  }

  Future<void> createRepairOrder({
    required String token,
    required String bienSo,
    required String customerName,
    required String phone,
    required String position,
    List<String>? images,
  }) async {
    final res = await http.post(
      _v1('/repair-orders'),
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      body: jsonEncode({
        'bien_so': bienSo,
        'customer_name': customerName,
        'customer_phone': phone,
        'position': position,
        if (images != null) 'images': images,
      }),
    );
    if (res.statusCode != 201) throw Exception(res.body);
  }

  Future<void> deleteRepairOrder({required String token, required String id}) async {
    final res = await http.delete(
      _v1('/repair-orders/$id'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (res.statusCode != 200) throw Exception(res.body);
  }

  static const int _timeoutSeconds = 15;

  static Future<http.Response> request(
    String method,
    String endpoint, {
    Map<String, dynamic>? data,
    String? token,
  }) async {
    if (!endpoint.startsWith('/')) {
      endpoint = '/$endpoint';
    }

    final url = Uri.parse('${AppConfig.baseUrl}$endpoint');

    final headers = {
      "Content-Type": "application/json",
      "Accept": "application/json",
    };

    if (token != null && token.isNotEmpty) {
      headers["Authorization"] = "Bearer $token";
    }

    try {
      http.Response response;
      final body = data != null ? jsonEncode(data) : null;

      switch (method.toUpperCase()) {
        case "POST":
          response = await http.post(url, headers: headers, body: body).timeout(const Duration(seconds: _timeoutSeconds));
          break;
        case "PATCH":
          response = await http.patch(url, headers: headers, body: body).timeout(const Duration(seconds: _timeoutSeconds));
          break;
        case "PUT":
          response = await http.put(url, headers: headers, body: body).timeout(const Duration(seconds: _timeoutSeconds));
          break;
        case "DELETE":
          response = await http.delete(url, headers: headers).timeout(const Duration(seconds: _timeoutSeconds));
          break;
        case "GET":
        default:
          response = await http.get(url, headers: headers).timeout(const Duration(seconds: _timeoutSeconds));
          break;
      }
      return response;
    } on TimeoutException {
      return http.Response(jsonEncode({"error": "Lỗi mạng: Hết thời gian kết nối đến máy chủ."}), 408);
    } catch (e) {
      if (_isTransientNetworkError(e)) {
        return http.Response(jsonEncode({"error": "Không thể kết nối đến máy chủ. Vui lòng kiểm tra lại!"}), 503);
      }
      return http.Response(jsonEncode({"error": "Lỗi hệ thống: ${e.toString()}"}), 500);
    }
  }
}
