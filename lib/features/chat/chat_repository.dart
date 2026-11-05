import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../core/config.dart';
import 'chat_models.dart';

/// Thin wrapper over the `/api/v1/pulse/*` endpoints used by the chat features
/// (channels, direct messages, people directory, groups).
class ChatRepository {
  ChatRepository._();
  static final ChatRepository instance = ChatRepository._();

  Dio get _dio => ApiClient.instance.dio;

  // ---- Channels ----

  /// GET /pulse/channels → { data: [ ... ] } (public + joined private; no DMs)
  Future<List<PulseChannel>> channels() async {
    final res = await _dio.get('/pulse/channels');
    final list = (res.data['data'] as List? ?? []);
    return list
        .map((e) => PulseChannel.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// Create a named group as a channel: POST /pulse/channels, then add members
  /// via POST /pulse/channels/{id}/members. Returns the new channel.
  Future<PulseChannel> createGroupChannel({
    required String name,
    List<int> userIds = const [],
    bool private = true,
  }) async {
    final res = await _dio.post('/pulse/channels', data: {
      'name': name,
      'kind': private ? 'private' : 'public',
    });
    final channel =
        PulseChannel.fromJson((res.data['data'] as Map).cast<String, dynamic>());
    if (userIds.isNotEmpty) {
      await _dio.post('/pulse/channels/${channel.id}/members',
          data: {'user_ids': userIds});
    }
    return channel;
  }

  /// GET /pulse/channels/{id} → channel details (with members_count).
  Future<PulseChannel> channelInfo(int channelId) async {
    final res = await _dio.get('/pulse/channels/$channelId');
    return PulseChannel.fromJson(
        (res.data['data'] as Map).cast<String, dynamic>());
  }

  /// GET /pulse/channels/{id}/members → [{ user:{id,name,email}, role }].
  Future<List<ChannelMemberRow>> channelMembers(int channelId) async {
    final res = await _dio.get('/pulse/channels/$channelId/members');
    final list = (res.data['data'] as List? ?? []);
    return list
        .map((e) =>
            ChannelMemberRow.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// POST /pulse/channels/{id}/members { user_ids } — add members.
  Future<void> addChannelMembers(int channelId, List<int> userIds) async {
    await _dio
        .post('/pulse/channels/$channelId/members', data: {'user_ids': userIds});
  }

  /// POST /pulse/channels/{id}/leave — leave a channel.
  Future<void> leaveChannel(int channelId) async {
    await _dio.post('/pulse/channels/$channelId/leave');
  }

  // ---- Per-channel notification preferences ----

  /// GET /pulse/channels/{id}/my-preferences → { data: { notifications_pref,
  /// muted_until } }. 404 if the user isn't a member of this channel.
  Future<({String pref, DateTime? mutedUntil})> channelPreferences(
      int channelId) async {
    final res = await _dio.get('/pulse/channels/$channelId/my-preferences');
    final d = (res.data['data'] as Map).cast<String, dynamic>();
    return (
      pref: (d['notifications_pref'] ?? 'all') as String,
      mutedUntil: d['muted_until'] != null
          ? DateTime.tryParse(d['muted_until'] as String)
          : null,
    );
  }

  /// PUT /pulse/channels/{id}/my-preferences { notifications_pref?,
  /// muted_minutes? } — pref is all | mentions | muted.
  Future<void> updateChannelPreferences(int channelId,
      {String? pref, int? mutedMinutes}) async {
    final data = <String, dynamic>{};
    if (pref != null) data['notifications_pref'] = pref;
    if (mutedMinutes != null) data['muted_minutes'] = mutedMinutes;
    await _dio.put('/pulse/channels/$channelId/my-preferences', data: data);
  }

  /// POST /pulse/channels/{id}/unread { message_id } — mark the conversation
  /// unread from a message (it and everything after count as unread again).
  Future<void> markUnread(int channelId, int messageId) async {
    await _dio.post('/pulse/channels/$channelId/unread',
        data: {'message_id': messageId});
  }

  // ---- Direct messages ----

  /// GET /pulse/dms → { data: [ channel w/ display_name ] }
  Future<List<PulseChannel>> dms() async {
    final res = await _dio.get('/pulse/dms');
    final list = (res.data['data'] as List? ?? []);
    return list
        .map((e) => PulseChannel.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// POST /pulse/dms { user_ids:[...] } → 201 { data: channel }.
  /// Idempotent find-or-create: same participants always resolve to one channel.
  Future<PulseChannel> createDm(List<int> userIds, {String? name}) async {
    final res = await _dio.post('/pulse/dms', data: {
      'user_ids': userIds,
      if (name != null && name.isNotEmpty) 'name': name,
    });
    return PulseChannel.fromJson(
        (res.data['data'] as Map).cast<String, dynamic>());
  }

  // ---- Messages ----

  /// GET /pulse/channels/{id}/messages → { data: [ ... ascending by id ], meta }.
  /// Works for DM channels too (listing isn't restricted by kind).
  Future<List<PulseMessage>> messages(int channelId,
      {int? beforeId, int limit = 50}) async {
    final qp = <String, dynamic>{'limit': limit};
    if (beforeId != null) qp['before_id'] = beforeId;
    final res = await _dio.get(
      '/pulse/channels/$channelId/messages',
      queryParameters: qp,
    );
    final list = (res.data['data'] as List? ?? []);
    return list
        .map((e) => PulseMessage.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// POST /pulse/channels/{id}/messages → 201 { data: { ...message } }.
  Future<PulseMessage> send(int channelId, String body,
      {List<int> attachmentIds = const []}) async {
    final res = await _dio.post(
      '/pulse/channels/$channelId/messages',
      data: {
        'body': body,
        if (attachmentIds.isNotEmpty) 'attachment_ids': attachmentIds,
        if (attachmentIds.isNotEmpty) 'has_attachments': true,
      },
    );
    return PulseMessage.fromJson(
        (res.data['data'] as Map).cast<String, dynamic>());
  }

  /// POST /pulse/dms/{id}/messages → 201 { data: { ...message } }.
  /// DM channels use a dedicated send path.
  Future<PulseMessage> sendDm(int channelId, String body,
      {List<int> attachmentIds = const []}) async {
    final res = await _dio.post(
      '/pulse/dms/$channelId/messages',
      data: {
        'body': body,
        if (attachmentIds.isNotEmpty) 'attachment_ids': attachmentIds,
        if (attachmentIds.isNotEmpty) 'has_attachments': true,
      },
    );
    return PulseMessage.fromJson(
        (res.data['data'] as Map).cast<String, dynamic>());
  }

  // ---- Attachments ----

  /// Two-step upload (sign → PUT bytes → finalize); returns the attachment id to
  /// attach to a message. Mirrors the web composer flow.
  Future<int> uploadAttachment({
    required int channelId,
    required String filename,
    required String mimeType,
    required List<int> bytes,
  }) async {
    final sign = await _dio.post('/pulse/attachments/sign-upload', data: {
      'filename': filename,
      'mime_type': mimeType,
      'size_bytes': bytes.length,
      'channel_id': channelId,
    });
    final d = (sign.data['data'] as Map).cast<String, dynamic>();
    final attachmentId = d['attachment_id'] as int;
    final uploadUrl = d['upload_url'] as String;
    final headers = (d['headers'] as Map?)?.cast<String, dynamic>() ??
        {'Content-Type': mimeType};
    final opts = Options(
      headers: {...headers, Headers.contentLengthHeader: bytes.length},
    );
    if (uploadUrl.startsWith('http')) {
      // Prod: presigned object-storage PUT — no app auth/tenant headers.
      await Dio().put(uploadUrl, data: Stream.value(bytes), options: opts);
    } else {
      // Local: our upload receiver. Strip the /api/v1 prefix the sign response
      // includes, since _dio's baseUrl already carries it.
      final path = uploadUrl.startsWith(AppConfig.apiPrefix)
          ? uploadUrl.substring(AppConfig.apiPrefix.length)
          : uploadUrl;
      await _dio.put(path, data: Stream.value(bytes), options: opts);
    }
    await _dio.post('/pulse/attachments/finalize',
        data: {'attachment_id': attachmentId});
    return attachmentId;
  }

  /// Resolves an attachment to a directly-openable (presigned) URL. Returns null
  /// when the backend streams the file instead of redirecting (local disk).
  Future<String?> resolveAttachmentUrl(int attachmentId) async {
    final res = await _dio.get(
      '/pulse/attachments/$attachmentId/url',
      options: Options(
        followRedirects: false,
        validateStatus: (s) => s != null && s < 400,
      ),
    );
    return res.headers.value('location');
  }

  /// Fetches an attachment's bytes (following the presigned URL in prod, or the
  /// local stream) for inline image previews.
  Future<Uint8List> fetchAttachmentBytes(int attachmentId) async {
    final presigned = await resolveAttachmentUrl(attachmentId);
    if (presigned != null) {
      final r = await Dio().get<List<int>>(presigned,
          options: Options(responseType: ResponseType.bytes));
      return Uint8List.fromList(r.data ?? const []);
    }
    final r = await _dio.get<List<int>>(
      '/pulse/attachments/$attachmentId/url',
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(r.data ?? const []);
  }

  // ---- Drafts (unsent composer text, per conversation) ----

  /// GET /pulse/drafts → { data: [{ channel_id, body }] }. Returns the saved
  /// draft body for [channelId], or null.
  Future<String?> loadDraft(int channelId) async {
    final res = await _dio.get('/pulse/drafts');
    final list = (res.data['data'] as List? ?? []);
    for (final d in list) {
      final m = (d as Map);
      if ((m['channel_id'] as int?) == channelId) return m['body'] as String?;
    }
    return null;
  }

  Future<void> saveDraft(int channelId, String body) async {
    await _dio.put('/pulse/channels/$channelId/draft', data: {'body': body});
  }

  Future<void> clearDraft(int channelId) async {
    await _dio.delete('/pulse/channels/$channelId/draft');
  }

  // ---- Presence ----

  /// POST /pulse/presence/ping — heartbeat marking the current user online.
  Future<void> pingPresence() async {
    await _dio.post('/pulse/presence/ping');
  }

  /// GET /pulse/presence/online → { data: [userId, ...] }. Online user ids.
  Future<Set<int>> onlineUserIds() async {
    final res = await _dio.get('/pulse/presence/online');
    final list = (res.data['data'] as List? ?? []);
    return list
        .map((e) => e is int ? e : int.tryParse('$e') ?? -1)
        .where((e) => e > 0)
        .toSet();
  }

  // ---- Reactions / message actions ----

  /// POST /pulse/messages/{id}/reactions { emoji } — add a reaction (idempotent).
  Future<void> addReaction(int messageId, String emoji) async {
    await _dio.post('/pulse/messages/$messageId/reactions',
        data: {'emoji': emoji});
  }

  /// DELETE /pulse/messages/{id}/reactions/{emoji} — remove my reaction.
  Future<void> removeReaction(int messageId, String emoji) async {
    await _dio.delete(
        '/pulse/messages/$messageId/reactions/${Uri.encodeComponent(emoji)}');
  }

  /// DELETE /pulse/messages/{id} — delete a message (author / permitted only).
  Future<void> deleteMessage(int messageId) async {
    await _dio.delete('/pulse/messages/$messageId');
  }

  /// PATCH /pulse/messages/{id} { body } → 200 { data: message }.
  /// Author only, within a 10-minute edit window; re-parses mentions.
  Future<PulseMessage> editMessage(int messageId, String body) async {
    final res =
        await _dio.patch('/pulse/messages/$messageId', data: {'body': body});
    return PulseMessage.fromJson(
        (res.data['data'] as Map).cast<String, dynamic>());
  }

  /// POST /pulse/channels/{id}/read { last_read_message_id } — clears unread up
  /// to that message (monotonic; never moves the pointer back). Works for DMs.
  Future<void> markRead(int channelId, int lastReadMessageId) async {
    await _dio.post('/pulse/channels/$channelId/read',
        data: {'last_read_message_id': lastReadMessageId});
  }

  /// POST /pulse/typing/{channel} — ping that the current user is typing
  /// (server broadcasts `member.typing`; 5s expiry, ping every ~3s).
  Future<void> sendTyping(int channelId) async {
    await _dio.post('/pulse/typing/$channelId');
  }

  /// POST /pulse/messages/{id}/forward { channel_id, comment? } — re-posts into
  /// the target channel with a "Forwarded from …" quote.
  Future<void> forwardMessage(int messageId, int channelId,
      {String? comment}) async {
    final data = <String, dynamic>{'channel_id': channelId};
    if (comment != null && comment.trim().isNotEmpty) {
      data['comment'] = comment.trim();
    }
    await _dio.post('/pulse/messages/$messageId/forward', data: data);
  }

  // ---- Meetings ----

  /// POST /pulse/channels/{id}/meeting → 201 { data: { join_url, message } }.
  /// Mints a real Google Meet link on the user's connected Google account,
  /// posts the join link into the channel as a message, and returns the URL.
  /// A 409 DioException means Google isn't connected (body carries `error`,
  /// `needs_google`, `google_configured`); 422 means archived / no link.
  Future<String> startMeeting(int channelId) async {
    final res = await _dio.post('/pulse/channels/$channelId/meeting');
    final data = (res.data['data'] as Map).cast<String, dynamic>();
    return data['join_url'] as String;
  }

  // ---- Reminders ("Remind me about this message") ----

  /// GET /pulse/reminders → { data: [...] } — active (not-yet-notified),
  /// soonest first.
  Future<List<PulseReminder>> reminders() async {
    final res = await _dio.get('/pulse/reminders');
    final list = (res.data['data'] as List? ?? []);
    return list
        .map((e) => PulseReminder.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// POST /pulse/messages/{id}/remind { preset } → 201. The time is resolved
  /// server-side; presets: in_20_min | in_1_hour | in_3_hours | tomorrow |
  /// next_week.
  Future<void> remindMe(int messageId, String preset) async {
    await _dio
        .post('/pulse/messages/$messageId/remind', data: {'preset': preset});
  }

  /// DELETE /pulse/reminders/{id} — cancel a reminder.
  Future<void> deleteReminder(int reminderId) async {
    await _dio.delete('/pulse/reminders/$reminderId');
  }

  // ---- Threads ----

  /// GET /pulse/messages/{id}/thread → { data: { parent, replies:[...] } }
  Future<({PulseMessage parent, List<PulseMessage> replies})> thread(
      int messageId) async {
    final res = await _dio.get('/pulse/messages/$messageId/thread');
    final data = (res.data['data'] as Map).cast<String, dynamic>();
    final parent =
        PulseMessage.fromJson((data['parent'] as Map).cast<String, dynamic>());
    final replies = (data['replies'] as List? ?? [])
        .map((e) => PulseMessage.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    return (parent: parent, replies: replies);
  }

  /// POST /pulse/messages/{id}/follow — follow a thread (by root or any reply);
  /// idempotent (201 created / 200 already following). Notifies you of replies
  /// even without a mention.
  Future<void> followMessage(int messageId) async {
    await _dio.post('/pulse/messages/$messageId/follow');
  }

  /// DELETE /pulse/messages/{id}/follow — stop following the thread.
  Future<void> unfollowMessage(int messageId) async {
    await _dio.delete('/pulse/messages/$messageId/follow');
  }

  /// POST /pulse/messages/{id}/replies { body } → 201 { data: message }
  Future<PulseMessage> replyInThread(int messageId, String body) async {
    final res = await _dio.post('/pulse/messages/$messageId/replies',
        data: {'body': body});
    return PulseMessage.fromJson(
        (res.data['data'] as Map).cast<String, dynamic>());
  }

  // ---- Message search ----

  /// GET /pulse/search?q=&channel_id= → { data:[...], meta }.
  /// Global (no channelId) is plan-gated — a 402 DioException means the
  /// workspace plan lacks `pulse.search.global`; search within a channel works.
  Future<List<SearchResult>> searchMessages(String q,
      {int? channelId, int limit = 50}) async {
    final qp = <String, dynamic>{'q': q, 'limit': limit};
    if (channelId != null) qp['channel_id'] = channelId;
    final res = await _dio.get('/pulse/search', queryParameters: qp);
    final list = (res.data['data'] as List? ?? []);
    return list
        .map((e) => SearchResult.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  // ---- Mentions inbox ----

  /// GET /pulse/mentions?filter=unread|all → { data: [ ... ] } (newest first).
  Future<List<Mention>> mentions({String filter = 'all'}) async {
    final res = await _dio
        .get('/pulse/mentions', queryParameters: {'filter': filter});
    final list = (res.data['data'] as List? ?? []);
    return list
        .map((e) => Mention.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// PATCH /pulse/mentions/{id}/read — mark one mention read.
  Future<void> markMentionRead(int mentionId) async {
    await _dio.patch('/pulse/mentions/$mentionId/read');
  }

  // ---- Pins ----

  /// GET /pulse/channels/{id}/pins → { data: [ { message: {...} } ] }.
  Future<List<PulseMessage>> pins(int channelId) async {
    final res = await _dio.get('/pulse/channels/$channelId/pins');
    final list = (res.data['data'] as List? ?? []);
    return list
        .whereType<Map>()
        .where((e) => e['message'] is Map)
        .map((e) => PulseMessage.fromJson(
            (e['message'] as Map).cast<String, dynamic>()))
        .toList();
  }

  /// POST /pulse/messages/{id}/pin — pin a message.
  Future<void> pinMessage(int messageId) async {
    await _dio.post('/pulse/messages/$messageId/pin');
  }

  /// DELETE /pulse/messages/{id}/pin — unpin a message.
  Future<void> unpinMessage(int messageId) async {
    await _dio.delete('/pulse/messages/$messageId/pin');
  }

  // ---- Saved messages ----

  /// GET /pulse/saved-messages → { data: [ { message, channel } ] }.
  Future<List<SavedItem>> savedMessages() async {
    final res = await _dio.get('/pulse/saved-messages');
    final list = (res.data['data'] as List? ?? []);
    return list.whereType<Map>().where((e) => e['message'] is Map).map((e) {
      final msg =
          PulseMessage.fromJson((e['message'] as Map).cast<String, dynamic>());
      final ch = e['channel'] is Map ? (e['channel'] as Map) : const {};
      return SavedItem(
        message: msg,
        channelId: (ch['id'] ?? e['channel_id'] ?? 0) as int,
        channelName: (ch['name'] ?? '') as String,
        channelKind: (ch['kind'] ?? 'public') as String,
      );
    }).toList();
  }

  /// POST /pulse/messages/{id}/save — bookmark a message.
  Future<void> saveMessage(int messageId) async {
    await _dio.post('/pulse/messages/$messageId/save');
  }

  /// DELETE /pulse/messages/{id}/save — remove a bookmark.
  Future<void> unsaveMessage(int messageId) async {
    await _dio.delete('/pulse/messages/$messageId/save');
  }

  // ---- Todos (assignable workspace tasks) ----

  /// GET /pulse/todos?filter=mine|assigned|created|all → { data: [...] }.
  Future<List<PulseTodo>> todos({String filter = 'mine'}) async {
    final res =
        await _dio.get('/pulse/todos', queryParameters: {'filter': filter});
    final list = (res.data['data'] as List? ?? []);
    return list
        .map((e) => PulseTodo.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// POST /pulse/todos { title, description?, assigned_to_user_id? } → 201.
  Future<PulseTodo> createTodo({
    required String title,
    String? description,
    int? assignedToUserId,
  }) async {
    final data = <String, dynamic>{'title': title};
    if (description != null && description.isNotEmpty) {
      data['description'] = description;
    }
    if (assignedToUserId != null) {
      data['assigned_to_user_id'] = assignedToUserId;
    }
    final res = await _dio.post('/pulse/todos', data: data);
    return PulseTodo.fromJson((res.data['data'] as Map).cast<String, dynamic>());
  }

  /// PATCH /pulse/todos/{id} { title?, description?, is_done?,
  /// assigned_to_user_id? } — creator or assignee only.
  Future<PulseTodo> updateTodo(int id,
      {String? title,
      String? description,
      bool? isDone,
      int? assignedToUserId}) async {
    final data = <String, dynamic>{};
    if (title != null) data['title'] = title;
    if (description != null) data['description'] = description;
    if (isDone != null) data['is_done'] = isDone;
    if (assignedToUserId != null) data['assigned_to_user_id'] = assignedToUserId;
    final res = await _dio.patch('/pulse/todos/$id', data: data);
    return PulseTodo.fromJson((res.data['data'] as Map).cast<String, dynamic>());
  }

  /// DELETE /pulse/todos/{id} — creator or assignee only.
  Future<void> deleteTodo(int id) async {
    await _dio.delete('/pulse/todos/$id');
  }

  // ---- People directory ----

  /// GET /pulse/members/directory?q= → { data: [ {user_id,name,email,status,online} ] }.
  Future<List<PulseMember>> directory({String? q}) async {
    final res = await _dio.get(
      '/pulse/members/directory',
      queryParameters: {if (q != null && q.isNotEmpty) 'q': q},
    );
    final list = (res.data['data'] as List? ?? []);
    return list
        .map((e) => PulseMember.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }
}
