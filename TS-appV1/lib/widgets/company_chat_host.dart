import 'dart:async';

import 'package:flutter/material.dart';

import '../core/workshop_features.dart';
import '../models/auth_models.dart';
import '../services/api_service.dart';
import 'company_chat_sheet.dart';

/// Truy cập mở chat công ty từ AppBar (con của [CompanyChatHost]).
class CompanyChatScope extends InheritedWidget {
  final bool enabled;
  final int unreadCount;
  final VoidCallback openChat;

  const CompanyChatScope({
    super.key,
    required this.enabled,
    required this.unreadCount,
    required this.openChat,
    required super.child,
  });

  static CompanyChatScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<CompanyChatScope>();
  }

  @override
  bool updateShouldNotify(CompanyChatScope oldWidget) {
    return oldWidget.enabled != enabled || oldWidget.unreadCount != unreadCount;
  }
}

String _unreadLabel(int n) {
  if (n <= 0) return '';
  if (n > 99) return '99+';
  return '$n';
}

/// Nút «Chat công ty» trên AppBar — không hiển thị cho Khách hàng.
class CompanyChatAppBarButton extends StatelessWidget {
  const CompanyChatAppBarButton({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = CompanyChatScope.maybeOf(context);
    if (scope == null || !scope.enabled) return const SizedBox.shrink();
    final badge = _unreadLabel(scope.unreadCount);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Badge(
        isLabelVisible: badge.isNotEmpty,
        label: Text(badge),
        backgroundColor: Colors.red,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF1E40AF),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            visualDensity: VisualDensity.compact,
          ),
          onPressed: scope.openChat,
          icon: const Icon(Icons.forum, size: 20),
          label: const Text('Chat công ty', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ),
      ),
    );
  }
}

/// Bọc màn hình sau đăng nhập — chat nội bộ (trừ role Khách hàng).
class CompanyChatHost extends StatefulWidget {
  final LoginResult login;
  final String userRole;
  final String myUserId;
  final String myDisplayName;
  final Widget child;

  const CompanyChatHost({
    super.key,
    required this.login,
    required this.userRole,
    this.myUserId = '',
    this.myDisplayName = '',
    required this.child,
  });

  @override
  State<CompanyChatHost> createState() => _CompanyChatHostState();
}

class _CompanyChatHostState extends State<CompanyChatHost> {
  late final ApiService _api;
  bool _chatEnabled = true;
  bool _loaded = false;
  int _unread = 0;
  Timer? _unreadPoll;

  @override
  void initState() {
    super.initState();
    _api = ApiService(baseUrl: widget.login.baseUrl);
    _loadFeatures();
  }

  @override
  void dispose() {
    _unreadPoll?.cancel();
    super.dispose();
  }

  /// Chỉ nhân viên nội bộ — Khách hàng không dùng chat công ty.
  bool get _roleAllowsCompanyChat {
    final r = widget.userRole.toUpperCase().replaceAll(' ', '');
    return r != 'KHACHHANG';
  }

  bool get _hasUsableToken {
    final t = widget.login.token.trim();
    return t.startsWith('auth_token_') || t.startsWith('local_token_');
  }

  void _startUnreadPoll() {
    _unreadPoll?.cancel();
    _refreshUnread();
    _unreadPoll = Timer.periodic(const Duration(seconds: 12), (_) => _refreshUnread());
  }

  Future<void> _refreshUnread() async {
    if (!_chatEnabled || !_roleAllowsCompanyChat || !_hasUsableToken || widget.login.token.isEmpty) {
      return;
    }
    try {
      final n = await _api.fetchCompanyChatUnreadCount(widget.login.token);
      if (mounted) setState(() => _unread = n);
    } catch (_) {}
  }

  Future<void> _loadFeatures() async {
    try {
      final raw = await _api.fetchWorkshopSettings(widget.login.token);
      if (!mounted) return;
      final f = WorkshopFeatures.fromSettingsResponse(raw);
      setState(() {
        _chatEnabled = f.companyChatEnabled;
        _loaded = true;
      });
      if (f.companyChatEnabled && _roleAllowsCompanyChat && _hasUsableToken) {
        _startUnreadPoll();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _chatEnabled = true;
          _loaded = true;
        });
        if (_roleAllowsCompanyChat && _hasUsableToken) _startUnreadPoll();
      }
    }
  }

  Future<void> _openChat() async {
    await showCompanyChatSheet(
      context: context,
      login: widget.login,
      userRole: widget.userRole,
      myUserId: widget.myUserId,
      myDisplayName: widget.myDisplayName.isNotEmpty ? widget.myDisplayName : widget.login.userName,
      api: _api,
      onMarkedRead: () {
        if (mounted) setState(() => _unread = 0);
      },
    );
    await _refreshUnread();
  }

  @override
  Widget build(BuildContext context) {
    // Hiện nút ngay cho nhân viên (kể cả staff_db / local_token); chỉ ẩn khi đã tải cấu hình và tắt chat.
    final enabled = _roleAllowsCompanyChat &&
        _hasUsableToken &&
        (!_loaded || _chatEnabled);

    return CompanyChatScope(
      enabled: enabled,
      unreadCount: _unread,
      openChat: _openChat,
      child: widget.child,
    );
  }
}
