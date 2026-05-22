import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart'; 

import '../models/auth_models.dart';
import '../services/api_service.dart';
import '../widgets/company_chat_host.dart';
import '../widgets/vm_file_image.dart';
import '../widgets/responsive_shell.dart';
import '../core/responsive_layout.dart';
import 'login_screen.dart';

class GuardDashboardScreen extends StatefulWidget {
  const GuardDashboardScreen({super.key, required this.login});
  final LoginResult login;

  @override
  State<GuardDashboardScreen> createState() => _GuardDashboardScreenState();
}

class _GuardDashboardScreenState extends State<GuardDashboardScreen> {
  late final ApiService api;
  bool loading = false;
  List<WorkOrderItem> orders = [];
  List<WorkOrderItem> filteredOrders = []; 
  List<BookingItem> allBookings = []; 

  final bienSoCtrl = TextEditingController();
  final tenKhCtrl = TextEditingController();
  final sdtCtrl = TextEditingController();
  final viTriCtrl = TextEditingController();
  final kmCtrl = TextEditingController(); 
  final yeuCauCtrl = TextEditingController(); 

  final searchOutCtrl = TextEditingController(); 

  List<Uint8List?> capturedImages = [null, null, null, null]; 
  final List<String> photoLabels = ['Đầu xe', 'Đuôi xe', 'Hông Trái', 'Hông Phải'];
  final ImagePicker _picker = ImagePicker();

  late stt.SpeechToText _speech;
  bool _isListening = false;
  TextEditingController? _activeVoiceController;

  @override
  void initState() {
    super.initState();
    api = ApiService(baseUrl: widget.login.baseUrl);
    _initSpeech(); 
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadBoard());
  }

  void _initSpeech() async {
    if (kIsWeb) return;
    _speech = stt.SpeechToText();
    try {
      await _speech.initialize();
    } catch (e) {
      debugPrint('Lỗi khởi tạo Speech: $e');
    }
  }

  @override
  void dispose() {
    bienSoCtrl.dispose();
    tenKhCtrl.dispose();
    sdtCtrl.dispose();
    viTriCtrl.dispose();
    kmCtrl.dispose();
    yeuCauCtrl.dispose();
    searchOutCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBoard() async {
    setState(() => loading = true);
    try {
      final fetchedOrders = await api.fetchBoard(widget.login.token);
      final bk = await api.fetchBookings(widget.login.token);
      setState(() {
        orders = fetchedOrders.where((o) => o.status != 'XE_RA_XUONG').toList();
        _filterOutList(); 
        allBookings = bk;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi tải dữ liệu: $e'), backgroundColor: Colors.red));
    } finally {
      setState(() => loading = false);
    }
  }

  void _filterOutList() {
    String query = searchOutCtrl.text.trim().toLowerCase().replaceAll(RegExp(r'[\s-]'), '');
    if (query.isEmpty) {
      setState(() { filteredOrders = List.from(orders); });
    } else {
      setState(() {
        filteredOrders = orders.where((o) {
          String bs = o.bienSo.toLowerCase().replaceAll(RegExp(r'[\s-]'), '');
          return bs.contains(query);
        }).toList();
      });
    }
  }

  void _kiemTraThongTin() {
    String bs = bienSoCtrl.text.trim().toLowerCase().replaceAll(RegExp(r'[\s-]'), '');
    if (bs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng nhập biển số xe trước!'), backgroundColor: Colors.orange));
      return;
    }

    bool found = false;
    for (var b in allBookings) {
      if (b.bienSo.replaceAll(RegExp(r'[\s-]'), '').toLowerCase() == bs) {
        setState(() {
          tenKhCtrl.text = b.customerName?.toString() ?? '';
          sdtCtrl.text = b.customerPhone?.toString() ?? '';
          yeuCauCtrl.clear();
        });
        found = true;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã tìm thấy Lịch Hẹn của xe này!'), backgroundColor: Colors.green));
        break;
      }
    }

    if (!found) {
      for (var o in orders) {
        if (o.bienSo.replaceAll(RegExp(r'[\s-]'), '').toLowerCase() == bs) {
          setState(() {
            tenKhCtrl.text = o.customerName?.toString() ?? '';
            sdtCtrl.text = o.customerPhone?.toString() ?? '';
            yeuCauCtrl.clear();
          });
          found = true;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Khách hàng cũ, đã tải thông tin!'), backgroundColor: Colors.blue));
          break;
        }
      }
    }

    if (!found) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Xe mới. Vui lòng nhập thông tin thủ công.')));
    }
  }

  void _listen(TextEditingController controller) async {
    if (kIsWeb) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nhập giọng nói chưa hỗ trợ trên web — gõ tay hoặc dùng app Windows/Android.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    if (!_isListening) {
      bool available = await _speech.initialize(
        onStatus: (val) => debugPrint('onStatus: $val'),
        onError: (val) => debugPrint('onError: $val'),
      );
      if (available) {
        setState(() {
          _isListening = true;
          _activeVoiceController = controller;
        });
        _speech.listen(
          onResult: (val) => setState(() {
            controller.text = val.recognizedWords;
          }),
          localeId: 'vi_VN', 
        );
      } else {
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
               content: Text('Cấp quyền Microphone hoặc Thiết bị của bạn không hỗ trợ giọng nói!'), 
               backgroundColor: Colors.red
           ));
        }
      }
    } else {
      setState(() {
        _isListening = false;
        _activeVoiceController = null;
      });
      _speech.stop();
    }
  }

  Widget _buildVoiceTextField(String label, TextEditingController controller, {int maxLines = 1, IconData icon = Icons.text_fields, bool enabled = true}) {
    bool isThisActive = _isListening && _activeVoiceController == controller;
    return TextField(
      controller: controller,
      maxLines: maxLines,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.blueGrey),
        border: const OutlineInputBorder(),
        filled: true,
        fillColor: enabled ? Colors.white : Colors.grey.shade200,
        suffixIcon: enabled && !kIsWeb
            ? IconButton(
                icon: Icon(
                  isThisActive ? Icons.mic : Icons.mic_none,
                  color: isThisActive ? Colors.red : Colors.blue,
                  size: 28,
                ),
                onPressed: () => _listen(controller),
                tooltip: 'Bấm để nói',
              )
            : null,
      ),
    );
  }

  Future<void> _captureImage(int index) async {
    try {
      if (kIsWeb) {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          withData: true,
          allowMultiple: false,
        );
        if (result == null || result.files.isEmpty) return;
        final raw = result.files.first.bytes;
        if (raw == null || raw.isEmpty) {
          throw Exception('Không đọc được ảnh — chọn file JPG/PNG từ máy.');
        }
        setState(() {
          capturedImages[index] = raw is Uint8List ? raw : Uint8List.fromList(raw);
        });
        return;
      }

      final bool useGallery = defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux;

      final XFile? photo = useGallery
          ? await _picker.pickImage(
              source: ImageSource.gallery,
              imageQuality: 40,
              maxWidth: 800,
              maxHeight: 800,
            )
          : await _picker.pickImage(
              source: ImageSource.camera,
              imageQuality: 40,
              maxWidth: 800,
              maxHeight: 800,
              preferredCameraDevice: CameraDevice.rear,
            );

      if (photo != null) {
        final bytes = await photo.readAsBytes();
        setState(() {
          capturedImages[index] = bytes;
        });
      }
    } catch (e) {
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi ảnh: $e'), backgroundColor: Colors.red));
      }
    }
  }

  // --- HÀM GIẢI MÃ ẢNH ĐA NĂNG ĐỂ XEM FULL SCREEN ---
  Widget _buildSafeImage(dynamic imageSource) {
    try {
      if (imageSource is Uint8List) {
        return Image.memory(imageSource, fit: BoxFit.cover, errorBuilder: (ctx, err, stack) => const Icon(Icons.broken_image, color: Colors.grey));
      }
      
      String imageStr = imageSource.toString();
      if (imageStr.startsWith('http://') || imageStr.startsWith('https://')) {
        return Image.network(imageStr, fit: BoxFit.cover, errorBuilder: (ctx, err, stack) => const Icon(Icons.broken_image, color: Colors.grey));
      } else if (imageStr.startsWith('data:image')) {
        final String base64Str = imageStr.split(',').last;
        final Uint8List bytes = base64Decode(base64Str);
        return Image.memory(bytes, fit: BoxFit.cover, errorBuilder: (ctx, err, stack) => const Icon(Icons.broken_image, color: Colors.grey));
      } else if (imageStr.startsWith('file://') || imageStr.startsWith('/')) {
        return buildVmFileImage(imageStr.replaceAll('file://', ''), fit: BoxFit.cover);
      }
    } catch(e) {}
    return const Center(child: Icon(Icons.error_outline, color: Colors.red, size: 40));
  }

  void _showFullScreenImage(dynamic imageSource) {
    if (imageSource == null) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer( 
              panEnabled: true,
              boundaryMargin: const EdgeInsets.all(20),
              minScale: 0.5,
              maxScale: 4,
              child: _buildSafeImage(imageSource)
            ),
            Positioned(
              top: 10, right: 10,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 32),
                onPressed: () => Navigator.pop(ctx),
              ),
            )
          ],
        )
      )
    );
  }

  // --- POPUP XEM ẢNH CỦA XE ĐÃ Ở TRONG XƯỞNG ---
  Future<void> _showCarImagesDialog(WorkOrderItem order) async {
    List<String> imageUrls = [];
    try {
      dynamic rawImages = (order as dynamic).images;
      if (rawImages != null && rawImages.toString() != 'null' && rawImages.toString() != '[]') {
         List<dynamic> parsedImages = (rawImages is String) ? jsonDecode(rawImages) : List.from(rawImages);
         imageUrls = parsedImages.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
      }
    } catch(e) {}

    if (imageUrls.isEmpty) {
      try {
        final full = await api.fetchRepairOrder(widget.login.token, order.id);
        dynamic rawImages = (full as dynamic).images;
        if (rawImages != null && rawImages.toString() != 'null' && rawImages.toString() != '[]') {
          final parsedImages = (rawImages is String) ? jsonDecode(rawImages) : List.from(rawImages);
          imageUrls = parsedImages.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
        }
      } catch (_) {}
    }

    if (!mounted) return;
    showDialog(
      context: context, 
      builder: (ctx) => AlertDialog(
        title: Text('Ảnh chụp xe: ${order.bienSo} lúc vào xưởng', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
        content: SizedBox(
          width: 600, height: 400,
          child: imageUrls.isEmpty 
            ? const Center(child: Text('Chưa có dữ liệu ảnh hoặc Bảo vệ chưa chụp ảnh cho xe này.', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)))
            : GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 4/3
                ),
                itemCount: imageUrls.length,
                itemBuilder: (context, index) {
                  return GestureDetector(
                    onTap: () => _showFullScreenImage(imageUrls[index]), // Phóng to ảnh
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        color: Colors.black12,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _buildSafeImage(imageUrls[index]),
                            const Positioned(bottom: 8, right: 8, child: Icon(Icons.zoom_out_map, color: Colors.white70, size: 20))
                          ],
                        )
                      ),
                    ),
                  );
                }
              ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng'))],
      )
    );
  }

  Future<void> _tiepNhanXe() async {
    if (bienSoCtrl.text.isEmpty || tenKhCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng nhập Biển số và Tên KH!'), backgroundColor: Colors.red));
      return;
    }

    String currentBienSo = bienSoCtrl.text.trim().toUpperCase();
    bool isAlreadyInWorkshop = orders.any((o) => o.bienSo.toUpperCase() == currentBienSo);
    
    if (isAlreadyInWorkshop) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('❌ LỖI: Xe $currentBienSo hiện đang ở trong xưởng rồi! Không thể tiếp nhận 2 lần.'), 
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ));
      return;
    }

    setState(() => loading = true);
    try {
      String extraNote = '';
      if (viTriCtrl.text.isNotEmpty) extraNote += 'Vị trí đỗ: ${viTriCtrl.text} | ';
      if (yeuCauCtrl.text.isNotEmpty) extraNote += 'Yêu cầu: ${yeuCauCtrl.text}';

      List<String> base64Images = [];
      for (var bytes in capturedImages) {
        if (bytes != null) {
          final base64Image = "data:image/jpeg;base64,${base64Encode(bytes)}";
          base64Images.add(base64Image);
        }
      }

      String baseUrl = widget.login.baseUrl;
      final String endpoint = baseUrl.endsWith('/api/v1') ? '$baseUrl/repair-orders' : '$baseUrl/api/v1/repair-orders';

      final res = await http.post(
        Uri.parse(endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.login.token}',
        },
        body: jsonEncode({
          'bien_so': currentBienSo,
          'customer_name': extraNote.isNotEmpty ? '${tenKhCtrl.text.trim()} ($extraNote)' : tenKhCtrl.text.trim(),
          'customer_phone': sdtCtrl.text.trim(),
          'position': viTriCtrl.text.trim(),
          if (base64Images.isNotEmpty) 'images': base64Images, 
        })
      );

      if (res.statusCode != 201 && res.statusCode != 200) {
        throw Exception('Lỗi Server: ${res.body}');
      }
      
      setState(() {
        bienSoCtrl.clear(); tenKhCtrl.clear(); sdtCtrl.clear();
        viTriCtrl.clear(); kmCtrl.clear(); yeuCauCtrl.clear();
        capturedImages = [null, null, null, null];
      });

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tiếp nhận xe thành công!'), backgroundColor: Colors.green));
      _loadBoard();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi tạo đơn: $e'), backgroundColor: Colors.red));
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> _choXeRaCong(WorkOrderItem item) async {
    final okExit = item.status == 'DA_THANH_TOAN' ||
        item.status == 'DA_RA_CONG' ||
        item.status == 'KT_DUYET_RA_CONG';
    if (!okExit) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('❌ TỪ CHỐI: Chưa đủ điều kiện ra xưởng. Cần Kế toán xác nhận đã thu tiền (DA_THANH_TOAN), hoặc duyệt cho trường hợp hủy (KT_DUYET_RA_CONG), hoặc đã ra cổng xưởng (DA_RA_CONG).'), 
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5),
       ));
       return;
    }

    setState(() => loading = true);
    try {
      await api.updateRepairOrder(token: widget.login.token, id: item.id, status: 'XE_RA_XUONG');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã xác nhận xe rời khỏi cổng xưởng!'), backgroundColor: Colors.green));
      _loadBoard();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red));
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    if (phoneNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Khách hàng chưa có số điện thoại!'))); 
      return;
    }
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(launchUri)) { await launchUrl(launchUri); } 
    else { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thiết bị không hỗ trợ gọi điện.'))); }
  }

  // --- POPUP XEM VÀ CHỈNH SỬA CHI TIẾT ---
  void _showEditCarDialog(WorkOrderItem order) {
    final editTenKhCtrl = TextEditingController(text: order.customerName);
    final editSdtCtrl = TextEditingController(text: order.customerPhone);
    String pos = ''; String req = '';
    if (order.customerNote.contains('Vị trí đỗ:')) {
       final parts = order.customerNote.split(' | ');
       pos = parts[0].replaceAll('Vị trí đỗ:', '').trim();
       if (parts.length > 1) req = parts[1].replaceAll('Yêu cầu:', '').trim();
    } else {
       req = order.customerNote;
    }

    final editViTriCtrl = TextEditingController(text: pos);
    final editYeuCauCtrl = TextEditingController(text: req);

    showDialog(
      context: context, 
      builder: (ctx) => AlertDialog(
        title: Text('Chi Tiết Xe & Chỉnh Sửa: ${order.bienSo}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildVoiceTextField('Biển Số Xe (Không được sửa)', TextEditingController(text: order.bienSo), enabled: false, icon: Icons.pin),
                const SizedBox(height: 16),
                _buildVoiceTextField('Tên Khách Hàng', editTenKhCtrl, icon: Icons.person),
                const SizedBox(height: 16),
                _buildVoiceTextField('Số điện thoại', editSdtCtrl, icon: Icons.phone),
                const SizedBox(height: 16),
                _buildVoiceTextField('Vị trí đỗ xe', editViTriCtrl, icon: Icons.location_on),
                const SizedBox(height: 16),
                _buildVoiceTextField('Yêu cầu/Ghi chú', editYeuCauCtrl, maxLines: 2, icon: Icons.record_voice_over),
              ],
            ),
          ),
        ),
        actions: [
          // NÚT XEM ẢNH TRONG POP-UP BẢO VỆ
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _showCarImagesDialog(order);
            }, 
            icon: const Icon(Icons.photo_camera), 
            label: const Text('Xem Ảnh Xe')
          ),
          OutlinedButton.icon(
            onPressed: () => _makePhoneCall(order.customerPhone), 
            icon: const Icon(Icons.phone, color: Colors.green), 
            label: const Text('Gọi KH', style: TextStyle(color: Colors.green))
          ),
          const Spacer(), 
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
          FilledButton.icon(
            onPressed: () async {
               Navigator.pop(ctx);
               setState(() => loading = true);
               try {
                  String combinedNote = '';
                  if (editViTriCtrl.text.isNotEmpty) combinedNote += 'Vị trí đỗ: ${editViTriCtrl.text} | ';
                  if (editYeuCauCtrl.text.isNotEmpty) combinedNote += 'Yêu cầu: ${editYeuCauCtrl.text}';

                  String baseUrl = widget.login.baseUrl;
                  final String endpoint = baseUrl.endsWith('/api/v1') ? '$baseUrl/repair-orders/${order.id}' : '$baseUrl/api/v1/repair-orders/${order.id}';
                  
                  await http.patch(
                    Uri.parse(endpoint),
                    headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ${widget.login.token}' },
                    body: jsonEncode({
                      'customer_name': editTenKhCtrl.text.trim(),
                      'customer_phone': editSdtCtrl.text.trim(),
                      'position': editViTriCtrl.text.trim(),
                      'customer_note': combinedNote
                    })
                  );
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cập nhật thông tin thành công!'), backgroundColor: Colors.green));
                  _loadBoard();
               } catch(e) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi cập nhật: $e'), backgroundColor: Colors.red));
               } finally { setState(() => loading = false); }
            }, 
            icon: const Icon(Icons.save),
            label: const Text('Lưu')
          )
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text('Cổng Bảo Vệ - Tiếp Nhận & Trả Xe', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        actions: [
          const CompanyChatAppBarButton(),
          Center(child: Text('User: ${widget.login.userName}  ', style: const TextStyle(fontWeight: FontWeight.bold))),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadBoard, tooltip: 'Làm mới'),
          IconButton(icon: const Icon(Icons.logout, color: Colors.red), onPressed: () { Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen())); }),
          const SizedBox(width: 16),
        ],
      ),
      body: ResponsiveTwoColumns(
        first: Container(
              margin: EdgeInsets.all(appIsPhone(context) ? 8 : 16),
              padding: appScreenPadding(context),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))]),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('TIẾP NHẬN XE MỚI', style: TextStyle(fontSize: appPanelTitleSize(context, desktop: 20), fontWeight: FontWeight.bold, color: Colors.blue)),
                    const Divider(height: 32),
                    
                    Row(
                      children: [
                        Expanded(child: _buildVoiceTextField('Biển số xe (*)', bienSoCtrl, icon: Icons.pin)),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: _kiemTraThongTin, 
                          icon: const Icon(Icons.search), 
                          label: const Text('Kiểm tra'),
                          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16)),
                        )
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(child: _buildVoiceTextField('Tên Khách Hàng (*)', tenKhCtrl, icon: Icons.person)),
                        const SizedBox(width: 16),
                        Expanded(child: _buildVoiceTextField('Số Điện Thoại', sdtCtrl, icon: Icons.phone)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(child: _buildVoiceTextField('Số KM hiện tại', kmCtrl, icon: Icons.speed)),
                        const SizedBox(width: 16),
                        Expanded(child: _buildVoiceTextField('Vị trí đỗ xe', viTriCtrl, icon: Icons.location_on)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    _buildVoiceTextField('Yêu cầu của Khách Hàng (Tình trạng xe/Sự cố mới)', yeuCauCtrl, maxLines: 2, icon: Icons.record_voice_over),
                    
                    const SizedBox(height: 24),
                    const Text('Chụp ảnh tình trạng xe (4 góc):', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(4, (index) {
                        return Expanded(
                          child: GestureDetector(
                            onTap: () {
                              if (capturedImages[index] != null) {
                                // Nếu đã chụp rồi, bấm vào để phóng to xem rõ hơn
                                _showFullScreenImage(capturedImages[index]);
                              } else {
                                // Chưa chụp thì bật camera
                                _captureImage(index);
                              }
                            }, 
                            onLongPress: () {
                              // Nhấn giữ để xóa ảnh chụp lại
                              if (capturedImages[index] != null) {
                                setState(() { capturedImages[index] = null; });
                              }
                            },
                            child: Container(
                              margin: const EdgeInsets.only(right: 8),
                              height: 100,
                              decoration: BoxDecoration(color: Colors.grey.shade100, border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid), borderRadius: BorderRadius.circular(8)),
                              child: capturedImages[index] != null 
                                ? Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(capturedImages[index]!, fit: BoxFit.cover)),
                                      const Positioned(bottom: 4, right: 4, child: Icon(Icons.zoom_out_map, color: Colors.white, size: 16))
                                    ],
                                  )
                                : Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.camera_alt, color: Colors.grey), const SizedBox(height: 4), Text(photoLabels[index], style: const TextStyle(color: Colors.grey, fontSize: 12))]),
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 8),
                    const Text('* Mẹo: Nhấn giữ vào ảnh để Xóa chụp lại. Nhấn 1 lần để xem Full HD.', style: TextStyle(color: Colors.grey, fontSize: 12, fontStyle: FontStyle.italic)),
                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: loading ? null : _tiepNhanXe,
                        icon: const Icon(Icons.directions_car),
                        label: const Text('LƯU VÀ PHÁT LỆNH TIẾP NHẬN', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 20), backgroundColor: Colors.blue.shade700),
                      ),
                    )
                  ],
                ),
              ),
            ),
        second: Container(
              margin: EdgeInsets.all(appIsPhone(context) ? 8 : 16),
              padding: appScreenPadding(context),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))]),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('KIỂM SOÁT XE RA/VÀO', style: TextStyle(fontSize: appPanelTitleSize(context, desktop: 20), fontWeight: FontWeight.bold, color: Colors.green)),
                  const SizedBox(height: 16),
                  
                  TextField(
                    controller: searchOutCtrl,
                    onChanged: (val) => _filterOutList(),
                    decoration: InputDecoration(
                      hintText: 'Nhập biển số để tìm xe nhanh...',
                      prefixIcon: const Icon(Icons.search, color: Colors.green),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear), 
                        onPressed: () { searchOutCtrl.clear(); _filterOutList(); }
                      )
                    ),
                  ),
                  const Divider(height: 32),

                  Expanded(
                    child: loading 
                      ? const Center(child: CircularProgressIndicator())
                      : filteredOrders.isEmpty 
                        ? const Center(child: Text('Không có xe trong xưởng'))
                        : ListView.builder(
                            itemCount: filteredOrders.length,
                            itemBuilder: (context, index) {
                              final item = filteredOrders[index];
                              bool isPaid = item.status == 'DA_THANH_TOAN' ||
                                  item.status == 'DA_RA_CONG' ||
                                  item.status == 'KT_DUYET_RA_CONG';

                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(color: Colors.grey.shade50, border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(12)),
                                child: Row(
                                  children: [
                                    const Icon(Icons.directions_car, color: Colors.blueGrey, size: 40),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(item.bienSo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                                          Text('KH: ${item.customerName}'),
                                          const SizedBox(height: 8),
                                          
                                          InkWell(
                                            onTap: () => _showEditCarDialog(item),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.edit_note, size: 16, color: Colors.blue),
                                                SizedBox(width: 4),
                                                Text('Xem chi tiết / Sửa', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
                                              ],
                                            ),
                                          )
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(isPaid ? Icons.check_circle : Icons.warning_amber_rounded, color: isPaid ? Colors.green : Colors.red, size: 16),
                                            const SizedBox(width: 4),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(color: isPaid ? Colors.green.shade50 : Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                                              child: Text(
                                                item.status, 
                                                style: TextStyle(color: isPaid ? Colors.green : Colors.red, fontWeight: FontWeight.bold, fontSize: 12)
                                              )
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        
                                        FilledButton.icon(
                                          onPressed: () => _choXeRaCong(item), 
                                          icon: Icon(isPaid ? Icons.exit_to_app : Icons.block), 
                                          style: FilledButton.styleFrom(backgroundColor: isPaid ? Colors.green : Colors.grey.shade400), 
                                          label: const Text('CHO XE RA CỔNG')
                                        )
                                      ],
                                    )
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
      ),
    );
  }
}