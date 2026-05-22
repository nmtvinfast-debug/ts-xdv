import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Import cấu hình cốt lõi
import 'core/constants.dart';
import 'providers/auth_provider.dart';
import 'models/auth_models.dart'; 

// Import TOÀN BỘ màn hình chức năng
import 'screens/login_screen.dart';
import 'screens/admin_screen.dart';
import 'screens/giam_doc_screen.dart';
import 'screens/cvdv_screen.dart';
import 'screens/cskh_screen.dart';
import 'screens/bao_ve_screen.dart';
import 'screens/khach_hang_screen.dart';
import 'screens/ktv_screen.dart';
import 'screens/quan_doc_screen.dart';
import 'screens/kho_screen.dart';
import 'screens/ke_toan_screen.dart';
import 'screens/tv_screen.dart';
import 'widgets/company_chat_host.dart';
import 'core/app_update_check.dart';
import 'core/responsive_layout.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      title: 'TS-XDV SYSTEM',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        fontFamily: defaultTargetPlatform == TargetPlatform.windows ? 'Segoe UI' : null,
      ),
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();
        final mq = MediaQuery.of(context);
        final factor = appFormFactor(context);
        final TextScaler ts;
        switch (factor) {
          case AppFormFactor.phone:
            ts = mq.textScaler.clamp(minScaleFactor: 0.82, maxScaleFactor: 0.96);
          case AppFormFactor.tablet:
            ts = mq.textScaler.clamp(minScaleFactor: 0.88, maxScaleFactor: 1.02);
          case AppFormFactor.desktop:
            ts = kIsWeb && mq.size.width >= 900
                ? mq.textScaler.clamp(minScaleFactor: 0.95, maxScaleFactor: 1.12)
                : mq.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.05);
        }
        return MediaQuery(data: mq.copyWith(textScaler: ts), child: child);
      },
      home: const AppStartup(),
    );
  }
}

/// Kiểm tra bản cập nhật (V2, V3…) rồi vào đăng nhập / màn chính.
class AppStartup extends StatefulWidget {
  const AppStartup({super.key});

  @override
  State<AppStartup> createState() => _AppStartupState();
}

class _AppStartupState extends State<AppStartup> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ctx = rootNavigatorKey.currentContext;
      if (ctx != null) await AppUpdateCheck.runIfNeeded(ctx);
    });
  }

  @override
  Widget build(BuildContext context) => const AuthWrapper();
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (auth.isAutoLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Colors.blue),
        ),
      );
    }

    if (!auth.isLoggedIn) {
      return const LoginScreen();
    }

    final loginInfo = LoginResult(
      token: auth.token ?? '',
      baseUrl: AppConfig.serverOrigin,
      userName: auth.user?.username ?? auth.user?.fullName ?? 'Unknown User',
    );

    final currentRole = (auth.role ?? '').toUpperCase().replaceAll(' ', '');
    final user = auth.user;

    Widget screen;
    switch (currentRole) {
      case 'ADMIN':
        screen = AdminDashboardScreen(login: loginInfo);
        break;
      case 'GIAMDOC':
        screen = GiamDocDashboardScreen(login: loginInfo);
        break;
      case 'CSKH':
        screen = CskhDashboardScreen(login: loginInfo);
        break;
      case 'CVDV':
        screen = CvdvDashboardScreen(login: loginInfo);
        break;
      case 'BAOVE':
        screen = GuardDashboardScreen(login: loginInfo);
        break;
      case 'KHACHHANG':
        screen = KhachHangScreen(login: loginInfo);
        break;
      case 'QUANDOC':
        screen = QuanDocScreen(login: loginInfo);
        break;
      case 'KTV':
        screen = KtvScreen(login: loginInfo);
        break;
      case 'KHO':
        screen = KhoScreen(login: loginInfo);
        break;
      case 'KETOAN':
        screen = KeToanScreen(login: loginInfo);
        break;
      case 'TIVI':
      case 'TV':
        screen = TvDashboardScreen(login: loginInfo);
        break;
      default:
        return const LoginScreen();
    }

    return CompanyChatHost(
      login: loginInfo,
      userRole: currentRole,
      myUserId: user?.id ?? '',
      myDisplayName: user?.fullName ?? loginInfo.userName,
      child: screen,
    );
  }
}