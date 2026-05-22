import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../models/auth_models.dart';
import '../core/constants.dart'; // File này của bạn phải tồn tại nhé

class ApiService {
  final String baseUrl;
  
  ApiService({required this.baseUrl});

  Future<List<WorkOrderItem>> fetchBoard(String token) async {
    final res = await http.get(Uri.parse('$baseUrl/api/v1/repair-orders'), headers: {'Authorization': 'Bearer $token'});
    if (res.statusCode == 200) {
      final List data = jsonDecode(res.body);
      return data.map((e) => WorkOrderItem.fromJson(e)).toList();
    }
    final detail = res.body.isEmpty ? '(body trống)' : res.body;
    throw Exception('Lỗi tải danh sách xe — HTTP ${res.statusCode}: $detail');
  }

  Future<List<UserItem>> fetchUsers(String token) async {
    final res = await http.get(Uri.parse('$baseUrl/api/v1/users'), headers: {'Authorization': 'Bearer $token'});
    if (res.statusCode == 200) {
      final List data = jsonDecode(res.body);
      return data.map((e) => UserItem.fromJson(e)).toList();
    }
    throw Exception('Lỗi tải danh sách nhân sự');
  }

  Future<List<BookingItem>> fetchBookings(String token) async {
    final res = await http.get(Uri.parse('$baseUrl/api/v1/bookings'), headers: {'Authorization': 'Bearer $token'});
    if (res.statusCode == 200) {
      final List data = jsonDecode(res.body);
      return data.map((e) => BookingItem.fromJson(e)).toList();
    }
    throw Exception('Lỗi tải lịch hẹn');
  }

  Future<void> updateRepairOrder({
    required String token, required String id, required String status,
    String? cvdvUsername, String? statusNote, String? jobs, String? parts,
    String? chatLogs, String? linkedCustomer, String? linkRequestedBy,
  }) async {
    Map<String, dynamic> body = {'status': status};
    if (cvdvUsername != null) body['cvdv_username'] = cvdvUsername;
    if (statusNote != null) body['customer_note'] = statusNote;
    if (jobs != null) body['jobs'] = jsonDecode(jobs); 
    if (parts != null) body['parts'] = jsonDecode(parts);
    if (chatLogs != null) body['chat_logs'] = jsonDecode(chatLogs);
    if (linkedCustomer != null) body['linked_customer'] = linkedCustomer;
    if (linkRequestedBy != null) body['link_requested_by'] = linkRequestedBy;

    final res = await http.patch(
      Uri.parse('$baseUrl/api/v1/repair-orders/$id'), 
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      body: jsonEncode(body)
    );
    if (res.statusCode != 200) throw Exception(res.body);
  }

  Future<void> createBooking({required String token, required Map<String, dynamic> data}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/v1/bookings'), 
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      body: jsonEncode(data)
    );
    if (res.statusCode != 201 && res.statusCode != 200) throw Exception(res.body);
  }

  Future<void> deleteBooking({required String token, required String id}) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/api/v1/bookings/$id'), 
      headers: {'Authorization': 'Bearer $token'}
    );
    if (res.statusCode != 200) throw Exception(res.body);
  }

  // =========================================================================
  // ĐÂY LÀ ĐOẠN QUAN TRỌNG NHẤT: ĐÃ THÊM `List<String>? images`
  // =========================================================================
  Future<void> createRepairOrder({
    required String token, required String bienSo, required String customerName,
    required String phone, required String position, List<String>? images,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/v1/repair-orders'), 
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      body: jsonEncode({
        'bien_so': bienSo, 
        'customer_name': customerName, 
        'customer_phone': phone, 
        'position': position,
        if (images != null) 'images': images, // Gửi danh sách ảnh Base64
      })
    );
    if (res.statusCode != 201) throw Exception(res.body);
  }

  Future<void> deleteRepairOrder({required String token, required String id}) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/api/v1/repair-orders/$id'), 
      headers: {'Authorization': 'Bearer $token'}
    );
    if (res.statusCode != 200) throw Exception(res.body);
  }

  // ==============================================================
  // HÀM REQUEST CŨ: GIỮ LẠI ĐỂ CÁC FILE CHƯA NÂNG CẤP KHÔNG BỊ LỖI
  // ==============================================================
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

    final url = Uri.parse("${AppConfig.baseUrl}$endpoint");
    
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
      final s = e.toString().toLowerCase();
      if (s.contains('socket') || s.contains('connection') || s.contains('failed host lookup')) {
        return http.Response(jsonEncode({"error": "Không thể kết nối đến máy chủ. Vui lòng kiểm tra lại!"}), 503);
      }
      return http.Response(jsonEncode({"error": "Lỗi hệ thống: ${e.toString()}"}), 500);
    }
  }
}