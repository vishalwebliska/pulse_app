import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import 'chat_models.dart';

/// Thin wrapper over the `/api/v1/pulse/*` endpoints used by Phase 1 chat.
class ChatRepository {
  ChatRepository._();
  static final ChatRepository instance = ChatRepository._();

  Dio get _dio => ApiClient.instance.dio;

  /// GET /pulse/channels → { data: [ ... ] }
  Future<List<PulseChannel>> channels() async {
    final res = await _dio.get('/pulse/channels');
    final list = (res.data['data'] as List? ?? []);
    return list
        .map((e) => PulseChannel.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// GET /pulse/channels/{id}/messages → { data: [ ... ascending by id ], meta }
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

  /// POST /pulse/channels/{id}/messages → 201 { data: { ...message } }
  Future<PulseMessage> send(int channelId, String body) async {
    final res = await _dio.post(
      '/pulse/channels/$channelId/messages',
      data: {'body': body},
    );
    return PulseMessage.fromJson(
        (res.data['data'] as Map).cast<String, dynamic>());
  }
}
