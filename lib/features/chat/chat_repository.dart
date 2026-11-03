import 'package:dio/dio.dart';

import '../../core/api_client.dart';
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
  Future<PulseMessage> send(int channelId, String body) async {
    final res = await _dio.post(
      '/pulse/channels/$channelId/messages',
      data: {'body': body},
    );
    return PulseMessage.fromJson(
        (res.data['data'] as Map).cast<String, dynamic>());
  }

  /// POST /pulse/dms/{id}/messages → 201 { data: { ...message } }.
  /// DM channels use a dedicated send path.
  Future<PulseMessage> sendDm(int channelId, String body) async {
    final res = await _dio.post(
      '/pulse/dms/$channelId/messages',
      data: {'body': body},
    );
    return PulseMessage.fromJson(
        (res.data['data'] as Map).cast<String, dynamic>());
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
