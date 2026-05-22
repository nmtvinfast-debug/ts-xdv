import 'dart:async';

import 'dart:convert';

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:http/http.dart' as http;

import '../core/local_json_store.dart';



import '../models/auth_models.dart';

import '../core/constants.dart';

import '../core/responsive_layout.dart';



import 'admin_screen.dart';

import 'giam_doc_screen.dart';

import 'cskh_screen.dart';

import 'cvdv_screen.dart';

import 'bao_ve_screen.dart';

import 'khach_hang_screen.dart';

import 'ktv_screen.dart';

import 'quan_doc_screen.dart';

import 'kho_screen.dart';

import 'ke_toan_screen.dart';

import 'tv_screen.dart';

import '../widgets/company_chat_host.dart';
import '../core/app_update_check.dart';
import '../main.dart' show rootNavigatorKey;



class LoginScreen extends StatefulWidget {

  const LoginScreen({super.key});



  @override

  State<LoginScreen> createState() => _LoginScreenState();

}



class _LoginScreenState extends State<LoginScreen> {

  final TextEditingController _usernameCtrl = TextEditingController();

  final TextEditingController _passwordCtrl = TextEditingController();

  final FocusNode _passwordFocus = FocusNode();

  bool _isLoading = false;



  final String _apiOrigin = AppConfig.serverOrigin;

  static const Duration _httpTimeout = Duration(seconds: 20);



  @override

  void dispose() {

    _usernameCtrl.dispose();

    _passwordCtrl.dispose();

    _passwordFocus.dispose();

    super.dispose();

  }



  String _parseApiErrorBody(String body) {

    if (body.isEmpty) return 'Không có nội dung phản hồi từ máy chủ.';

    try {

      final d = jsonDecode(body);

      if (d is Map && d['error'] != null) return d['error'].toString();

    } catch (_) {}

    return body.length > 280 ? '${body.substring(0, 280)}…' : body;

  }



  Future<void> _handleLogin() async {

    if (_usernameCtrl.text.trim().isEmpty || _passwordCtrl.text.trim().isEmpty) {

      _showError('Vui lòng nhập đầy đủ tài khoản và mật khẩu!');

      return;

    }



    setState(() => _isLoading = true);



    final username = _usernameCtrl.text.trim();

    final password = _passwordCtrl.text.trim();



    try {

      final String endpoint = _apiOrigin.endsWith('/api/v1')

          ? '$_apiOrigin/auth/login'

          : '$_apiOrigin/api/v1/auth/login';



      final res = await http

          .post(

            Uri.parse(endpoint),

            headers: {'Content-Type': 'application/json'},

            body: jsonEncode({

              'username': username,

              'password': password,

            }),

          )

          .timeout(

            _httpTimeout,

            onTimeout: () => throw TimeoutException('Không nhận phản hồi trong ${_httpTimeout.inSeconds}s từ máy chủ.'),

          );



      if (res.statusCode == 200) {

        final data = jsonDecode(res.body);

        final token = data['token'];

        final user = data['user'];



        final role = user['role']?.toString().toUpperCase().replaceAll(' ', '') ?? '';



        final loginResult = LoginResult(

          token: token,

          baseUrl: _apiOrigin.endsWith('/api/v1') ? _apiOrigin.replaceAll('/api/v1', '') : _apiOrigin,

          userName: user['name'] ?? user['username'],

        );



        _navigateByRole(

          role,

          loginResult,

          myUserId: user['id']?.toString() ?? '',

          myDisplayName: user['name']?.toString() ?? user['username']?.toString() ?? loginResult.userName,

        );

        return;

      }



      if (!kIsWeb) try {

        final content = await readLocalJson('staff_db.json');

        if (content != null && content.isNotEmpty) {

          final List<dynamic> localStaffs = jsonDecode(content);



          for (var staff in localStaffs) {

            if (staff['username'] == username) {

              if (staff['isActive'] != true) {

                _showError('Tài khoản này đã bị khóa bởi Giám Đốc!');

                return;

              }



              final role = staff['role']?.toString().toUpperCase().replaceAll(' ', '').replaceAll('Ố', 'O').replaceAll('Ấ', 'A') ?? '';



              final loginResult = LoginResult(

                token: 'local_token_$username',

                baseUrl: _apiOrigin.endsWith('/api/v1') ? _apiOrigin.replaceAll('/api/v1', '') : _apiOrigin,

                userName: staff['fullName'] ?? username,

              );



              _navigateByRole(

                role,

                loginResult,

                myUserId: staff['id']?.toString() ?? '',

                myDisplayName: staff['fullName']?.toString() ?? username,

              );

              return;

            }

          }

        }

      } catch (e) {

        debugPrint('Lỗi đọc local staff_db: $e');

      }



      final parsed = _parseApiErrorBody(res.body);

      final err = parsed.trim().isEmpty ? 'Tên đăng nhập hoặc mật khẩu không đúng!' : parsed;

      _showError(err);

    } on TimeoutException catch (e) {

      _showError('${e.message}\n\nKiểm tra kết nối mạng và máy chủ ${AppConfig.serverOrigin}.');

    } catch (e) {
      final s = e.toString().toLowerCase();
      if (s.contains('socket') || s.contains('connection') || s.contains('failed host lookup')) {
        _showError('Không kết nối được máy chủ ${AppConfig.serverOrigin}. Thử lại sau vài phút.');
        return;
      }

      _showError('Lỗi kết nối: $e');

    } finally {

      if (mounted) setState(() => _isLoading = false);

    }

  }



  void _navigateByRole(

    String role,

    LoginResult loginData, {

    String myUserId = '',

    String myDisplayName = '',

  }) {

    Widget nextScreen;



    switch (role) {

      case 'ADMIN':

        nextScreen = AdminDashboardScreen(login: loginData);

        break;

      case 'GIAMDOC':

      case 'GIÁMĐỐC':

        nextScreen = GiamDocDashboardScreen(login: loginData);

        break;

      case 'CSKH':

        nextScreen = CskhDashboardScreen(login: loginData);

        break;

      case 'CVDV':

      case 'CỐVẤN':

      case 'COVAN':

        nextScreen = CvdvDashboardScreen(login: loginData);

        break;

      case 'BAOVE':

      case 'BẢOVỆ':

        nextScreen = GuardDashboardScreen(login: loginData);

        break;

      case 'KHACHHANG':

        nextScreen = KhachHangScreen(login: loginData);

        break;

      case 'QUANDOC':

      case 'QUẢNĐỐC':

        nextScreen = QuanDocScreen(login: loginData);

        break;

      case 'KTV':

      case 'KỸTHUẬT':

        nextScreen = KtvScreen(login: loginData);

        break;

      case 'KHO':

        nextScreen = KhoScreen(login: loginData);

        break;

      case 'KETOAN':

      case 'KẾTOÁN':

        nextScreen = KeToanScreen(login: loginData);

        break;

      case 'TIVI':

      case 'TV':

        nextScreen = TvDashboardScreen(login: loginData);

        break;

      default:

        _showError('Chức vụ "$role" chưa được cập nhật giao diện mới!');

        return;

    }



    Navigator.pushReplacement(

      context,

      MaterialPageRoute(

        builder: (context) => CompanyChatHost(

          login: loginData,

          userRole: role,

          myUserId: myUserId,

          myDisplayName: myDisplayName.isNotEmpty ? myDisplayName : loginData.userName,

          child: nextScreen,

        ),

      ),

    );

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ctx = rootNavigatorKey.currentContext;
      if (ctx != null) await AppUpdateCheck.runIfNeeded(ctx);
    });

  }



  void _showError(String message) {

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(

      SnackBar(content: Text(message), backgroundColor: Colors.red),

    );

  }



  void _showRegisterDialog() {

    final nameCtrl = TextEditingController();

    final phoneCtrl = TextEditingController();

    final passCtrl = TextEditingController();



    showDialog(

      context: context,

      builder: (ctx) => AlertDialog(

        title: const Text('ĐĂNG KÝ TÀI KHOẢN KHÁCH HÀNG', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),

        content: SizedBox(

          width: 350,

          child: Column(

            mainAxisSize: MainAxisSize.min,

            children: [

              const Text(

                'Số điện thoại của Quý khách sẽ được dùng làm Tên đăng nhập để theo dõi xe.',

                style: TextStyle(color: Colors.grey, fontSize: 13),

              ),

              const SizedBox(height: 16),

              TextField(

                controller: nameCtrl,

                decoration: const InputDecoration(

                  labelText: 'Họ và tên',

                  border: OutlineInputBorder(),

                  prefixIcon: Icon(Icons.person),

                ),

              ),

              const SizedBox(height: 12),

              TextField(

                controller: phoneCtrl,

                keyboardType: TextInputType.phone,

                decoration: const InputDecoration(

                  labelText: 'Số điện thoại',

                  border: OutlineInputBorder(),

                  prefixIcon: Icon(Icons.phone),

                ),

              ),

              const SizedBox(height: 12),

              TextField(

                controller: passCtrl,

                obscureText: true,

                decoration: const InputDecoration(

                  labelText: 'Tạo Mật khẩu',

                  border: OutlineInputBorder(),

                  prefixIcon: Icon(Icons.lock),

                ),

              ),

            ],

          ),

        ),

        actions: [

          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),

          FilledButton(

            onPressed: () async {

              if (nameCtrl.text.isEmpty || phoneCtrl.text.isEmpty || passCtrl.text.isEmpty) {

                _showError('Vui lòng nhập đủ thông tin!');

                return;

              }

              Navigator.pop(ctx);

              setState(() => _isLoading = true);

              try {

                final String endpoint =

                    _apiOrigin.endsWith('/api/v1') ? '$_apiOrigin/users' : '$_apiOrigin/api/v1/users';

                final res = await http

                    .post(

                      Uri.parse(endpoint),

                      headers: {'Content-Type': 'application/json'},

                      body: jsonEncode({

                        'username': phoneCtrl.text.trim(),

                        'password': passCtrl.text.trim(),

                        'name': nameCtrl.text.trim(),

                        'role': 'KHACHHANG',

                      }),

                    )

                    .timeout(_httpTimeout, onTimeout: () => throw TimeoutException('Hết thời gian chờ máy chủ.'));



                if (res.statusCode == 201) {

                  ScaffoldMessenger.of(context).showSnackBar(

                    const SnackBar(

                      content: Text('Đăng ký thành công! Vui lòng đăng nhập.'),

                      backgroundColor: Colors.green,

                    ),

                  );

                  _usernameCtrl.text = phoneCtrl.text.trim();

                  _passwordCtrl.text = passCtrl.text.trim();

                } else {

                  _showError('Lỗi đăng ký: ${_parseApiErrorBody(res.body)}');

                }

              } on TimeoutException catch (e) {

                _showError(e.message ?? 'Hết thời gian chờ');

              } catch (e) {

                _showError('Lỗi kết nối máy chủ: $e');

              } finally {

                if (mounted) setState(() => _isLoading = false);

              }

            },

            child: const Text('XÁC NHẬN ĐĂNG KÝ'),

          ),

        ],

      ),

    );

  }



  @override

  Widget build(BuildContext context) {

    final w = MediaQuery.sizeOf(context).width;

    final cardW = math.min(w - 32, math.min(appContentMaxWidth(context), 520.0)).clamp(280.0, 560.0);

    return Scaffold(

      backgroundColor: const Color(0xFFF1F5F9),

      body: Center(

        child: SingleChildScrollView(

          padding: const EdgeInsets.symmetric(vertical: 24),

          child: Column(

            mainAxisAlignment: MainAxisAlignment.center,

            children: [

              Container(

                width: cardW,

                padding: const EdgeInsets.all(40),

                decoration: BoxDecoration(

                  color: Colors.white,

                  borderRadius: BorderRadius.circular(20),

                  boxShadow: const [

                    BoxShadow(color: Colors.black12, blurRadius: 20, offset: Offset(0, 10)),

                  ],

                ),

                child: Column(

                  mainAxisSize: MainAxisSize.min,

                  children: [

                    Container(

                      padding: const EdgeInsets.all(16),

                      decoration: BoxDecoration(

                        color: Colors.blue.withOpacity(0.1),

                        shape: BoxShape.circle,

                      ),

                      child: const Icon(Icons.car_repair, size: 60, color: Colors.blue),

                    ),

                    const SizedBox(height: 24),

                    const Text(

                      'ĐĂNG NHẬP HỆ THỐNG',

                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 1.2),

                    ),

                    const SizedBox(height: 8),

                    const Text('TS-XDV AUTO SERVICE', style: TextStyle(color: Colors.grey)),

                    const SizedBox(height: 40),

                    TextField(

                      controller: _usernameCtrl,

                      textInputAction: TextInputAction.next,

                      decoration: InputDecoration(

                        labelText: 'Tên đăng nhập',

                        prefixIcon: const Icon(Icons.person_outline),

                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),

                      ),

                      onSubmitted: (_) {

                        if (_passwordCtrl.text.isEmpty) {

                          _passwordFocus.requestFocus();

                        } else if (!_isLoading) {

                          _handleLogin();

                        } else {

                          _passwordFocus.requestFocus();

                        }

                      },

                    ),

                    const SizedBox(height: 20),

                    TextField(

                      controller: _passwordCtrl,

                      focusNode: _passwordFocus,

                      obscureText: true,

                      textInputAction: TextInputAction.done,

                      decoration: InputDecoration(

                        labelText: 'Mật khẩu',

                        prefixIcon: const Icon(Icons.lock_outline),

                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),

                      ),

                      onSubmitted: (_) {

                        if (!_isLoading) _handleLogin();

                      },

                    ),

                    const SizedBox(height: 32),

                    SizedBox(

                      width: double.infinity,

                      height: 50,

                      child: FilledButton(

                        onPressed: _isLoading ? null : _handleLogin,

                        style: FilledButton.styleFrom(

                          backgroundColor: const Color(0xFF1E3A8A),

                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),

                        ),

                        child: _isLoading

                            ? const SizedBox(

                                width: 24,

                                height: 24,

                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),

                              )

                            : const Text('ĐĂNG NHẬP', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),

                      ),

                    ),

                    const SizedBox(height: 20),

                    const Divider(),

                    const SizedBox(height: 20),

                    SizedBox(

                      width: double.infinity,

                      height: 50,

                      child: OutlinedButton.icon(

                        onPressed: _showRegisterDialog,

                        icon: const Icon(Icons.app_registration),

                        label: const Text(

                          'KHÁCH HÀNG MỚI? ĐĂNG KÝ NGAY',

                          style: TextStyle(fontWeight: FontWeight.bold),

                        ),

                        style: OutlinedButton.styleFrom(

                          side: const BorderSide(color: Colors.blue),

                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),

                        ),

                      ),

                    ),

                  ],

                ),

              ),

            ],

          ),

        ),

      ),

    );

  }

}


