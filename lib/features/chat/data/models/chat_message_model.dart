class ChatMessageModel {
  final String id;
  final String chatSessionId;
  final String senderId;
  final String? text;
  final String? imageUrl;
  final bool isRead;
  final String createdAt;

  ChatMessageModel({
    required this.id,
    required this.chatSessionId,
    required this.senderId,
    this.text,
    this.imageUrl,
    required this.isRead,
    required this.createdAt,
  });

  factory ChatMessageModel.fromJson(Map<String, dynamic> json) {
    return ChatMessageModel(
      id: json['id'].toString(),
      chatSessionId:
          json['chat_session_id']?.toString() ??
          json['chatSessionId']?.toString() ??
          '',
      senderId:
          json['sender_id']?.toString() ?? json['senderId']?.toString() ?? '',
      text: json['text'],
      imageUrl: json['image_url'] ?? json['imageUrl'],
      isRead: json['is_read'] == true || json['isRead'] == true,
      createdAt:
          json['created_at'] ??
          json['createdAt'] ??
          DateTime.now().toIso8601String(),
    );
  }

  ChatMessageModel copyWith({
    String? id,
    String? chatSessionId,
    String? senderId,
    String? text,
    String? imageUrl,
    bool? isRead,
    String? createdAt,
  }) {
    return ChatMessageModel(
      id: id ?? this.id,
      chatSessionId: chatSessionId ?? this.chatSessionId,
      senderId: senderId ?? this.senderId,
      text: text ?? this.text,
      imageUrl: imageUrl ?? this.imageUrl,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
