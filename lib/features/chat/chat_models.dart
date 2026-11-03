// Pulse chat models. Fields map to the `/api/v1/pulse/*` JSON (no API Resources
// server-side, so we read the keys we need and ignore the rest).

class PulseChannel {
  PulseChannel({
    required this.id,
    required this.name,
    required this.slug,
    required this.kind,
    required this.isGeneral,
    required this.unreadCount,
    this.topic,
  });

  final int id;
  final String name;
  final String slug;
  final String kind; // public | private
  final bool isGeneral;
  final int unreadCount;
  final String? topic;

  bool get isPrivate => kind == 'private';

  factory PulseChannel.fromJson(Map<String, dynamic> j) => PulseChannel(
        id: j['id'] as int,
        name: (j['name'] ?? '') as String,
        slug: (j['slug'] ?? '') as String,
        kind: (j['kind'] ?? 'public') as String,
        isGeneral: (j['is_general'] ?? false) as bool,
        unreadCount: (j['unread_count'] ?? 0) as int,
        topic: j['topic'] as String?,
      );
}

class PulseMessage {
  PulseMessage({
    required this.id,
    required this.body,
    required this.authorName,
    required this.kind,
    this.userId,
    this.bodyRendered,
    this.createdAt,
  });

  final int id;
  final int? userId;
  final String body;
  final String? bodyRendered;
  final String kind; // user | system | bot
  final String authorName;
  final DateTime? createdAt;

  factory PulseMessage.fromJson(Map<String, dynamic> j) {
    final user = j['user'];
    return PulseMessage(
      id: j['id'] as int,
      userId: j['user_id'] as int?,
      body: (j['body'] ?? '') as String,
      bodyRendered: j['body_rendered'] as String?,
      kind: (j['kind'] ?? 'user') as String,
      authorName: (user is Map && user['name'] != null)
          ? user['name'] as String
          : 'Someone',
      createdAt: j['created_at'] != null
          ? DateTime.tryParse(j['created_at'] as String)
          : null,
    );
  }
}
