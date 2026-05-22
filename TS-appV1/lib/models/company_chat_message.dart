class CompanyChatMessage {
  final String id;
  final String senderUserId;
  final String senderName;
  final String senderRole;
  final String body;
  final DateTime createdAt;

  CompanyChatMessage({
    required this.id,
    required this.senderUserId,
    required this.senderName,
    required this.senderRole,
    required this.body,
    required this.createdAt,
  });

  factory CompanyChatMessage.fromJson(Map<String, dynamic> json) {
    return CompanyChatMessage(
      id: json['id']?.toString() ?? '',
      senderUserId: json['sender_user_id']?.toString() ?? '',
      senderName: json['sender_name']?.toString() ?? '',
      senderRole: json['sender_role']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}
