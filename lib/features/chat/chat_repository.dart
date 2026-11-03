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
