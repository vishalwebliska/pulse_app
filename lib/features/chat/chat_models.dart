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
    this.displayName,
  });

  final int id;
  final String name;
  final String slug;
  final String kind; // public | private | dm | group_dm
  final bool isGeneral;
  final int unreadCount;
  final String? topic;

  /// Set for DMs by `GET /pulse/dms` — the other person's name (1:1) or a
  /// comma-joined label (group DM). Null for regular channels.
  final String? displayName;

  bool get isPrivate => kind == 'private';
  bool get isDm => kind == 'dm' || kind == 'group_dm';
  bool get isGroupDm => kind == 'group_dm';

  /// What to show as the conversation title.
  String get title {
    if (displayName != null && displayName!.isNotEmpty) return displayName!;
    if (name.isNotEmpty) return name;
    return isDm ? 'Direct message' : 'Channel';
  }

  factory PulseChannel.fromJson(Map<String, dynamic> j) => PulseChannel(
        id: j['id'] as int,
        name: (j['name'] ?? '') as String,
        slug: (j['slug'] ?? '') as String,
        kind: (j['kind'] ?? 'public') as String,
        isGeneral: (j['is_general'] ?? false) as bool,
        unreadCount: (j['unread_count'] ?? 0) as int,
        topic: j['topic'] as String?,
        displayName: j['display_name'] as String?,
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

/// A workspace member from `GET /pulse/members/directory` — used by the
/// people-search picker and the @-mention autocomplete.
class PulseMember {
  PulseMember({
    required this.userId,
    required this.name,
    required this.email,
    required this.status,
    required this.online,
  });

  final int userId;
  final String name;
  final String email;
  final String status; // active | invited
  final bool online;

  /// The @-mention token the server resolves: the display name with spaces
  /// removed (verified: `@PulseTesterTwo` resolves to "Pulse Tester Two").
  String get mentionToken => name.replaceAll(RegExp(r'\s+'), '');

  factory PulseMember.fromJson(Map<String, dynamic> j) => PulseMember(
        userId: j['user_id'] as int,
        name: (j['name'] ?? '') as String,
        email: (j['email'] ?? '') as String,
        status: (j['status'] ?? 'active') as String,
        online: (j['online'] ?? false) as bool,
      );
}
