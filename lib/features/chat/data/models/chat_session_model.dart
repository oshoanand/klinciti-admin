class ChatSessionModel {
  final String id;
  final String partnerId;
  final String status;
  final String updatedAt;
  final int unreadCount;
  final String? lastMessage;

  // Real-time UI fields
  final String? partnerName;
  final String? partnerAvatar;
  final bool isOnline;
  final String? lastSeen;
  final bool isTyping;

  ChatSessionModel({
    required this.id,
    required this.partnerId,
    required this.status,
    required this.updatedAt,
    required this.unreadCount,
    this.lastMessage,
    this.partnerName,
    this.partnerAvatar,
    this.isOnline = false,
    this.lastSeen,
    this.isTyping = false,
  });

  factory ChatSessionModel.fromJson(Map<String, dynamic> json) {
    return ChatSessionModel(
      id: json['id'].toString(),
      partnerId: json['partnerId'].toString(),
      status: json['status'] ?? 'OPEN',
      updatedAt: json['updatedAt'] ?? DateTime.now().toIso8601String(),
      unreadCount: json['unreadCount'] ?? 0,
      lastMessage: json['lastMessage'],

      // Parse the dynamically joined partner details
      partnerName: json['partnerName']?.toString(),
      partnerAvatar:
          json['partnerAvatar']?.toString() ?? json['partnerImage']?.toString(),

      // Parse real-time presence from Redis
      isOnline: json['isOnline'] ?? false,
      lastSeen: json['lastSeen']?.toString(),
      isTyping: false, // Never comes from JSON
    );
  }

  ChatSessionModel copyWith({
    String? id,
    String? partnerId,
    String? status,
    String? updatedAt,
    int? unreadCount,
    String? lastMessage,
    String? partnerName,
    String? partnerAvatar,
    bool? isOnline,
    String? lastSeen,
    bool? isTyping, // ✅ Add to copyWith
  }) {
    return ChatSessionModel(
      id: id ?? this.id,
      partnerId: partnerId ?? this.partnerId,
      status: status ?? this.status,
      updatedAt: updatedAt ?? this.updatedAt,
      unreadCount: unreadCount ?? this.unreadCount,
      lastMessage: lastMessage ?? this.lastMessage,
      partnerName: partnerName ?? this.partnerName,
      partnerAvatar: partnerAvatar ?? this.partnerAvatar,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      isTyping: isTyping ?? this.isTyping, // ✅ Apply it
    );
  }
}
