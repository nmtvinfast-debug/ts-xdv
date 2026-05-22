import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/auth_models.dart';
import '../models/company_chat_message.dart';
import '../services/api_service.dart';

/// Phòng chat nội bộ toàn công ty.
Future<void> showCompanyChatSheet({
  required BuildContext context,
  required LoginResult login,
  required String userRole,
  required ApiService api,
  String myUserId = '',
  String myDisplayName = '',
  VoidCallback? onMarkedRead,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => _CompanyChatPanel(
        login: login,
        userRole: userRole,
        myUserId: myUserId,
        myDisplayName: myDisplayName,
        api: api,
        scrollController: scrollCtrl,
        onMarkedRead: onMarkedRead,
      ),
    ),
  );
}

class _CompanyChatPanel extends StatefulWidget {
  final LoginResult login;
  final String userRole;
  final String myUserId;
  final String myDisplayName;
  final ApiService api;
  final ScrollController scrollController;
  final VoidCallback? onMarkedRead;

  const _CompanyChatPanel({
    required this.login,
    required this.userRole,
    required this.myUserId,
    required this.myDisplayName,
    required this.api,
    required this.scrollController,
    this.onMarkedRead,
  });

  @override
  State<_CompanyChatPanel> createState() => _CompanyChatPanelState();
}

class _CompanyChatPanelState extends State<_CompanyChatPanel> {
  static String _chatScopeSubtitle(String role) {
    final r = role.toUpperCase().replaceAll(' ', '');
    if (r == 'ADMIN') {
      return 'Quản trị hệ thống — xem chat mọi xưởng';
    }
    return 'Chỉ nhân viên cùng xưởng (bảo mật giữa các XDV)';
  }

  final _msgCtrl = TextEditingController();
  final _listCtrl = ScrollController();
  List<CompanyChatMessage> _messages = [];
  Timer? _poll;
  bool _loading = true;
  String? _error;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 8), (_) => _refresh(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _msgCtrl.dispose();
    _listCtrl.dispose();
    super.dispose();
  }

  String _friendlyRole(String code) {
    switch (code.toUpperCase()) {
      case 'ADMIN':
        return 'Quản trị';
      case 'GIAMDOC':
        return 'Giám đốc';
      case 'CSKH':
        return 'CSKH';
      case 'CVDV':
        return 'CVDV';
      case 'QUANDOC':
        return 'Quản đốc';
      case 'KTV':
        return 'KTV';
      case 'KHO':
        return 'Kho';
      case 'KETOAN':
        return 'Kế toán';
      case 'BAOVE':
        return 'Bảo vệ';
      case 'KHACHHANG':
        return 'Khách hàng';
      case 'TV':
      case 'TIVI':
        return 'TV';
      default:
        return code;
    }
  }

  String _friendlyError(Object e) {
    final raw = e.toString();
    if (raw.contains('Không có quyền')) {
      return 'Tài khoản chưa được cấp quyền chat công ty. Liên hệ Admin kiểm tra vai trò (ADMIN, CVDV, KETOAN…).';
    }
    if (raw.contains('vai trò hoặc xưởng')) {
      return 'Không có quyền xem chat xưởng này. Đăng nhập đúng tài khoản thuộc xưởng của bạn.';
    }
    if (raw.contains('company_messages') || raw.contains('does not exist')) {
      return 'Máy chủ chưa có bảng chat — cần deploy lại ts-server và khởi động DB.';
    }
    if (raw.contains('Chưa đăng nhập') || raw.contains('Chua dang nhap')) {
      return 'Phiên đăng nhập hết hạn. Đăng xuất và đăng nhập lại bằng tài khoản trên máy chủ (không dùng staff_db.json).';
    }
    if (raw.contains('staff_db') || raw.contains('không hợp lệ') || raw.contains('khong hop le')) {
      return 'Chat công ty chỉ dùng khi đăng nhập qua máy chủ (API). Tài khoản chỉ có trong staff_db.json không dùng được — liên hệ Admin tạo user trên hệ thống.';
    }
    return raw.replaceFirst('Exception: ', '');
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final list = await widget.api.fetchCompanyMessages(widget.login.token);
      if (!mounted) return;
      setState(() {
        _messages = list;
        _loading = false;
        _error = null;
      });
      _scrollToBottom();
      await _markRead();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(e);
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_listCtrl.hasClients) return;
      _listCtrl.animateTo(
        _listCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _markRead() async {
    try {
      await widget.api.markCompanyChatRead(widget.login.token);
      widget.onMarkedRead?.call();
    } catch (_) {}
  }

  bool _isMyMessage(CompanyChatMessage m) {
    if (widget.myUserId.isNotEmpty && m.senderUserId == widget.myUserId) return true;
    final me = widget.myDisplayName.toLowerCase().trim();
    final login = widget.login.userName.toLowerCase().trim();
    final sender = m.senderName.toLowerCase().trim();
    return sender == me || sender == login;
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final msg = await widget.api.postCompanyMessage(widget.login.token, text);
      _msgCtrl.clear();
      setState(() {
        _messages = [..._messages, msg];
        _sending = false;
      });
      _scrollToBottom();
    } catch (e) {
      setState(() => _sending = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không gửi được: ${_friendlyError(e)}'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF1F5F9),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 48,
            height: 5,
            decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(4)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                const Icon(Icons.forum, color: Color(0xFF1E40AF), size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Chat công ty', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      Text(
                        _chatScopeSubtitle(widget.userRole),
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                IconButton(onPressed: () => _refresh(), icon: const Icon(Icons.refresh)),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, textAlign: TextAlign.center))
                    : _messages.isEmpty
                        ? const Center(child: Text('Chưa có tin nhắn. Hãy bắt đầu trao đổi.'))
                        : ListView.builder(
                            controller: _listCtrl,
                            padding: const EdgeInsets.all(12),
                            itemCount: _messages.length,
                            itemBuilder: (_, i) {
                              final m = _messages[i];
                              final isMe = _isMyMessage(m);
                              return Align(
                                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  constraints: const BoxConstraints(maxWidth: 520),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isMe ? const Color(0xFFDBEAFE) : Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.grey.shade300),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${m.senderName} · ${_friendlyRole(m.senderRole)}',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF475569)),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(m.body, style: const TextStyle(fontSize: 15)),
                                      const SizedBox(height: 4),
                                      Text(
                                        DateFormat('dd/MM HH:mm').format(m.createdAt.toLocal()),
                                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _msgCtrl,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: 'Nhắn toàn công ty…',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _sending ? null : _send,
                    child: _sending
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
