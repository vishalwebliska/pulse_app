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

/// Delivery state for a locally-composed message before the server confirms it.
enum MessageSendState { sent, sending, failed }

class PulseAttachment {
  const PulseAttachment({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.sizeBytes,
  });

  final int id;
  final String name;
  final String mimeType;
  final int sizeBytes;

  bool get isImage => mimeType.startsWith('image/');

  String get sizeLabel {
    final b = sizeBytes;
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  factory PulseAttachment.fromJson(Map<String, dynamic> j) => PulseAttachment(
        id: j['id'] as int,
        name: (j['original_name'] ?? 'file') as String,
        mimeType: (j['mime_type'] ?? 'application/octet-stream') as String,
        sizeBytes: (j['size_bytes'] ?? 0) as int,
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
    this.isPinned = false,
    this.isSaved = false,
    this.sendState = MessageSendState.sent,
    this.attachments = const [],
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
  final bool isPinned;
  final bool isSaved;
  final MessageSendState sendState;
  final List<PulseAttachment> attachments;

  PulseMessage copyWith({
    List<MessageReaction>? reactions,
    String? body,
    DateTime? editedAt,
    bool? isPinned,
    bool? isSaved,
    MessageSendState? sendState,
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
        isPinned: isPinned ?? this.isPinned,
        isSaved: isSaved ?? this.isSaved,
        sendState: sendState ?? this.sendState,
        attachments: attachments,
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
      isPinned: (j['is_pinned'] ?? false) as bool,
      isSaved: (j['is_saved'] ?? false) as bool,
      attachments: (j['attachments'] is List)
          ? (j['attachments'] as List)
              .whereType<Map>()
              .map((e) => PulseAttachment.fromJson(e.cast<String, dynamic>()))
              .toList()
          : const [],
    );
  }
}

/// A saved message ("bookmark") from `GET /pulse/saved-messages`, carrying its
/// message and the channel it lives in (so it can be opened).
class SavedItem {
  const SavedItem({
    required this.message,
    required this.channelId,
    required this.channelName,
    required this.channelKind,
  });

  final PulseMessage message;
  final int channelId;
  final String channelName;
  final String channelKind;

  bool get isDm => channelKind == 'dm' || channelKind == 'group_dm';
}

/// A personal reminder from `GET /pulse/reminders` ("Remind me about this
/// message"), carrying the message + the channel it lives in so it can be
/// opened. Only active (not-yet-notified) reminders are returned.
class PulseReminder {
  const PulseReminder({
    required this.id,
    required this.messageId,
    required this.messageBody,
    required this.channelId,
    required this.channelName,
    required this.channelKind,
    this.remindAt,
  });

  final int id;
  final int messageId;
  final String messageBody;
  final int channelId;
  final String channelName;
  final String channelKind;
  final DateTime? remindAt;

  bool get isDm => channelKind == 'dm' || channelKind == 'group_dm';

  factory PulseReminder.fromJson(Map<String, dynamic> j) {
    final msg = j['message'];
    final ch = j['channel'];
    return PulseReminder(
      id: j['id'] as int,
      messageId: (msg is Map ? msg['id'] as int? : null) ?? 0,
      messageBody: (msg is Map ? (msg['body'] ?? '') : '') as String,
      channelId: (ch is Map ? ch['id'] as int? : null) ??
          (msg is Map ? msg['channel_id'] as int? : null) ??
          0,
      channelName: (ch is Map ? (ch['name'] ?? '') : '') as String,
      channelKind: (ch is Map ? (ch['kind'] ?? 'public') : 'public') as String,
      remindAt: j['remind_at'] != null
          ? DateTime.tryParse(j['remind_at'] as String)
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

/// A mention of the current user from `GET /pulse/mentions` (flattened shape).
class Mention {
  const Mention({
    required this.id,
    required this.messageId,
    required this.channelId,
    required this.channelName,
    required this.channelKind,
    required this.authorName,
    this.body,
    this.mentionedAt,
    this.read = false,
  });

  final int id;
  final int messageId;
  final int channelId;
  final String channelName;
  final String channelKind;
  final String authorName;
  final String? body;
  final DateTime? mentionedAt;
  final bool read;

  bool get isDm => channelKind == 'dm' || channelKind == 'group_dm';

  factory Mention.fromJson(Map<String, dynamic> j) => Mention(
        id: j['id'] as int,
        messageId: (j['message_id'] ?? 0) as int,
        channelId: (j['channel_id'] ?? 0) as int,
        channelName: (j['channel_name'] ?? '') as String,
        channelKind: (j['channel_kind'] ?? 'public') as String,
        authorName: (j['author_name'] ?? 'Someone') as String,
        body: j['body'] as String?,
        mentionedAt: j['mentioned_at'] != null
            ? DateTime.tryParse(j['mentioned_at'] as String)
            : null,
        read: j['read_at'] != null,
      );
}

/// A member of a channel from `GET /pulse/channels/{id}/members`.
class ChannelMemberRow {
  const ChannelMemberRow({
    required this.userId,
    required this.name,
    required this.email,
    required this.role,
  });

  final int userId;
  final String name;
  final String email;
  final String role;

  factory ChannelMemberRow.fromJson(Map<String, dynamic> j) {
    final u = j['user'];
    return ChannelMemberRow(
      userId: (u is Map ? u['id'] as int? : null) ?? 0,
      name: (u is Map ? (u['name'] ?? '') : '') as String,
      email: (u is Map ? (u['email'] ?? '') : '') as String,
      role: (j['role'] ?? 'member') as String,
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
