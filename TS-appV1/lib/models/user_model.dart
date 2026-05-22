class UserModel {
  final String id;
  final String username;
  final String name;
  final String role;
  
  // Các trường có thể null (tùy thuộc vào việc user có cập nhật hay không)
  final String? phone;
  final String? email;
  final String? xdvId; // Mã Xưởng Dịch Vụ mà nhân sự này trực thuộc
  final bool isActive; // Trạng thái khóa / mở tài khoản
  final DateTime? createdAt;
  final DateTime? lastLogin;

  UserModel({
    required this.id,
    required this.username,
    required this.name,
    required this.role,
    this.phone,
    this.email,
    this.xdvId,
    this.isActive = true,
    this.createdAt,
    this.lastLogin,
  });

  // ==========================================
  // 1. CHUYỂN JSON TỪ BACKEND -> OBJECT FLUTTER
  // ==========================================
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Người dùng',
      role: json['role']?.toString() ?? 'NONE',
      phone: json['phone']?.toString(),
      email: json['email']?.toString(),
      xdvId: json['xdv_id']?.toString(), // Để biết KTV/CVDV này thuộc xưởng nào
      isActive: json['is_active'] ?? true, // Mặc định là true nếu không có
      
      // Parse thời gian an toàn, tránh lỗi crash nếu backend trả về null hoặc sai định dạng
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
      lastLogin: json['last_login'] != null ? DateTime.tryParse(json['last_login'].toString()) : null,
    );
  }

  // ==========================================
  // 2. CHUYỂN OBJECT FLUTTER -> JSON (Để Gửi Lên Server)
  // ==========================================
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'name': name,
      'role': role,
      'phone': phone,
      'email': email,
      'xdv_id': xdvId,
      'is_active': isActive,
      'created_at': createdAt?.toIso8601String(),
      'last_login': lastLogin?.toIso8601String(),
    };
  }

  // ==========================================
  // 3. HELPER METHODS - KIỂM TRA QUYỀN NHANH CHÓNG TRÊN UI
  // ==========================================
  // Thay vì phải gõ: if (user.role == AppRoles.admin) thì chỉ cần gõ: if (user.isAdmin)
  bool get isAdmin => role == 'ADMIN';
  bool get isGiamDoc => role == 'GIAMDOC';
  bool get isCvdv => role == 'CVDV';
  bool get isQuanDoc => role == 'QUANDOC';
  bool get isKtv => role == 'KTV';
  bool get isKho => role == 'KHO';
  bool get isKeToan => role == 'KETOAN';
  bool get isBaoVe => role == 'BAOVE';
  bool get isCskh => role == 'CSKH';
  bool get isKhachHang => role == 'KHACHHANG';

  // Copy đối tượng hiện tại và thay đổi 1 vài thuộc tính (Dùng cho state management)
  UserModel copyWith({
    String? id,
    String? username,
    String? name,
    String? role,
    String? phone,
    String? email,
    String? xdvId,
    bool? isActive,
    DateTime? createdAt,
    DateTime? lastLogin,
  }) {
    return UserModel(
      id: id ?? this.id,
      username: username ?? this.username,
      name: name ?? this.name,
      role: role ?? this.role,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      xdvId: xdvId ?? this.xdvId,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      lastLogin: lastLogin ?? this.lastLogin,
    );
  }
}