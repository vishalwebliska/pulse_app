// Pulse chat models. Fields map to the `/api/v1/pulse/*` JSON (no API Resources
// server-side, so we read the keys we need and ignore the rest).

/// Human-friendly message timestamp with date + time:
/// "Today 11:49 AM", "Yesterday 6:42 PM", "3 Nov, 11:49 AM", or
/// "3 Nov 2025, 11:49 AM" for older years.
String formatMessageTimestamp(DateTime dt) {
  final l = dt.toLocal();
  final now = DateTime.now();
  final day = DateTime(l.year, l.month, l.day);
  final today = DateTime(now.year, now.month, now.day);
  final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
  final ampm = l.hour >= 12 ? 'PM' : 'AM';
  final time = '$h:${l.minute.toString().padLeft(2, '0')} $ampm';
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today $time';
  if (diff == 1) return 'Yesterday $time';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  final date = l.year == now.year
      ? '${l.day} ${months[l.month - 1]}'
      : '${l.day} ${months[l.month - 1]} ${l.year}';
  return '$date, $time';
}

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

/// One emoji reaction on a message (`{id, message_id, user_id, emoji}`).
class MessageReaction {
  const MessageReaction({required this.userId, required this.emoji});

  final int userId;
  final String emoji;

  factory MessageReaction.fromJson(Map<String, dynamic> j) => MessageReaction(
        userId: (j['user_id'] ?? 0) as int,
        emoji: (j['emoji'] ?? '') as String,
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
    this.reactions = const [],
    this.replyCount = 0,
    this.editedAt,
  });

  final int id;
  final int? userId;
  final String body;
  final String? bodyRendered;
  final String kind; // user | system | bot
  final String authorName;
  final DateTime? createdAt;
  final List<MessageReaction> reactions;
  final int replyCount;
  final DateTime? editedAt;

  PulseMessage copyWith({
    List<MessageReaction>? reactions,
    String? body,
    DateTime? editedAt,
  }) =>
      PulseMessage(
        id: id,
        userId: userId,
        body: body ?? this.body,
        bodyRendered: bodyRendered,
        kind: kind,
        authorName: authorName,
        createdAt: createdAt,
        reactions: reactions ?? this.reactions,
        replyCount: replyCount,
        editedAt: editedAt ?? this.editedAt,
      );

  factory PulseMessage.fromJson(Map<String, dynamic> j) {
    final user = j['user'];
    final rawReactions = j['reactions'];
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
      reactions: rawReactions is List
          ? rawReactions
              .whereType<Map>()
              .map((e) => MessageReaction.fromJson(e.cast<String, dynamic>()))
              .toList()
          : const [],
      replyCount: (j['reply_count'] ?? 0) as int,
      editedAt: j['edited_at'] != null
          ? DateTime.tryParse(j['edited_at'] as String)
          : null,
    );
  }
}

/// A message search hit from `GET /pulse/search` (carries its channel).
class SearchResult {
  const SearchResult({
    required this.messageId,
    required this.body,
    required this.authorName,
    required this.channelId,
    required this.channelName,
    required this.channelKind,
  });

  final int messageId;
  final String body;
  final String authorName;
  final int channelId;
  final String channelName;
  final String channelKind;

  bool get isDm => channelKind == 'dm' || channelKind == 'group_dm';

  factory SearchResult.fromJson(Map<String, dynamic> j) {
    final user = j['user'];
    final channel = j['channel'];
    return SearchResult(
      messageId: j['id'] as int,
      body: (j['body'] ?? '') as String,
      authorName: (user is Map && user['name'] != null)
          ? user['name'] as String
          : 'Someone',
      channelId: (channel is Map ? channel['id'] as int? : null) ?? 0,
      channelName: channel is Map ? (channel['name'] ?? '').toString() : '',
      channelKind:
          channel is Map ? (channel['kind'] ?? 'public').toString() : 'public',
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
